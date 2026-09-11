import { AuthError, corsHeaders, jsonResponse, requireAuth } from "../_shared/auth.ts";

/// Sends an invoice to the customer by email, SMS or both.
///
/// Sending is server-side on purpose: provider credentials never reach the iOS
/// app. Authorisation is the caller's own — the invoice is read with their JWT,
/// so RLS proves it belongs to their company, and `invoicesManage` is checked
/// against the same role/permission matrix the rest of the app uses. The request
/// never carries a company id, so there is nothing to tamper with.
///
/// Every attempt is written to the existing `notifications` ledger with its real
/// outcome. When a provider is not configured the attempt is recorded as
/// **failed**, never as sent, and the caller is told so plainly.
///
/// SMS credit is spent in the same database transaction that queues the
/// notification (`queue_invoice_notification`), so it cannot be checked and
/// debited separately, and two simultaneous sends cannot spend the same credit.
/// A failed delivery returns the credit through `settle_notification`. Email
/// never touches SMS credit.
///
/// WHOSE EMAIL IS THIS? THE TRADE BUSINESS'S.
///
/// A customer receiving an invoice must see their contractor, not Harbour
/// South. So the message is branded as the trade business throughout: the
/// visible sender name is the company's name, `Reply-To` is the company's own
/// `business_email` when it has set one, and the body carries the company's
/// name, logo mark, address, phone and invoice detail.
///
/// The TRANSPORT stays Harbour South's verified Resend domain, because that is
/// the only domain whose SPF/DKIM this deployment controls. Putting the
/// business's address in `from` without owning its domain would fail
/// authentication and land the invoice in spam — worse for the business than a
/// visible "via" line. No DNS, SPF, DKIM, SMTP or API-key configuration is
/// asked of the business, and none is required to send.
///
/// EXTENSION POINT: when a business later authenticates its own sending domain,
/// `resolveSender()` below is the single place that changes — it starts
/// returning the business address as `from`. Invoice generation, the share
/// token, the notifications ledger and the billing system are all untouched by
/// that change. Harbour South's OWN system mail (invitations, account and
/// security notices) is sent by the Cloudflare Worker and is deliberately not
/// affected by any of this.

interface SendRequest {
  invoiceId?: string;
  channels?: string[];
  email?: string;
  phone?: string;
}

interface ChannelOutcome {
  channel: "email" | "sms";
  recipient: string;
  status: "sent" | "failed";
  configured: boolean;
  detail: string;
  /// Credits actually held against this send once it settled. Always 0 for
  /// email, and 0 for an SMS that failed and had its credit returned.
  creditsCharged: number;
  /// Remaining SMS credit after this attempt settled. Null for email.
  smsCreditBalance: number | null;
}

interface QueueRow {
  notification_id: string;
  outcome: "queued" | "insufficientCredit";
  credits_charged: number;
  balance_after: number | null;
}

interface SettleRow {
  outcome: string;
  credits_refunded: number;
  balance_after: number | null;
}

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const EMAIL_PATTERN = /^[^\s@]+@[^\s@.]+(\.[^\s@.]+)+$/;
const PHONE_PATTERN = /^\+?[0-9][0-9()\s.-]{6,19}$/;

/// The project's own backend host, which serves the customer invoice page. Not
/// a secret — it is the public address printed in the message — so it is safe
/// as a fallback when the env var isn't present in the function's secret store.
const PAGE_BASE_FALLBACK = "https://field-ops-backend.rork.app";

const NOT_CONFIGURED_EMAIL =
  "Email provider not configured — nothing was delivered. Set RESEND_API_KEY and RESEND_FROM_EMAIL.";
const NOT_CONFIGURED_SMS =
  "SMS provider not configured — nothing was delivered. Set TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN and TWILIO_FROM_NUMBER.";

function money(value: string | number | null, currency: string): string {
  const amount = Number(value ?? 0);
  try {
    return new Intl.NumberFormat("en-US", { style: "currency", currency: (currency || "USD").trim() })
      .format(amount);
  } catch {
    return `${(currency || "").trim()} ${amount.toFixed(2)}`;
  }
}

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

/// The customer-facing identity of one invoice email.
interface SenderIdentity {
  /// RFC 5322 `from`, e.g. `AB Heating <invoices@harboursouth.us>`. The display
  /// name is the trade business; the address is the verified transport domain.
  from: string;
  /// The business's own address, so a customer's reply reaches the business and
  /// never Harbour South. Omitted when the business has not set one.
  replyTo?: string;
}

/// Strips anything that could break out of a display name and inject a header.
function sanitiseDisplayName(value: string): string {
  return value
    .replace(/[\r\n]+/g, " ")
    .replace(/["<>;,]/g, "")
    .trim()
    .slice(0, 78);
}

/// Builds the trade business's sending identity over Harbour South's verified
/// transport.
///
/// THE ONE PLACE TO CHANGE when authenticated customer-owned domains arrive:
/// return `businessEmail` as `from` once its domain is verified. Nothing else
/// in invoice generation or billing needs to know.
function resolveSender(companyName: string, businessEmail: string | null): SenderIdentity | null {
  const transport = Deno.env.get("RESEND_FROM_EMAIL");
  if (!transport) return null;

  const name = sanitiseDisplayName(companyName);
  // The transport value may already be `Something <addr>`; take just the address
  // so the business's name is the one the customer sees.
  const address = (transport.match(/<([^>]+)>/)?.[1] ?? transport).trim();
  const reply = (businessEmail ?? "").trim();

  return {
    from: name ? `${name} <${address}>` : address,
    replyTo: reply && EMAIL_PATTERN.test(reply) ? reply : undefined,
  };
}

async function sendEmail(
  to: string,
  subject: string,
  html: string,
  text: string,
  sender: SenderIdentity | null,
): Promise<{ status: "sent" | "failed"; configured: boolean; detail: string; reference?: string }> {
  const apiKey = Deno.env.get("RESEND_API_KEY");
  if (!apiKey || !sender) {
    return { status: "failed", configured: false, detail: NOT_CONFIGURED_EMAIL };
  }

  try {
    const response = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        from: sender.from,
        to: [to],
        subject,
        html,
        text,
        // A customer replying to their invoice reaches their contractor.
        ...(sender.replyTo ? { reply_to: sender.replyTo } : {}),
      }),
    });
    const body = await response.json().catch(() => ({}));
    if (!response.ok) {
      return {
        status: "failed",
        configured: true,
        detail: `Email provider refused the message (${response.status}).`,
      };
    }
    return { status: "sent", configured: true, detail: "Handed to the email provider.", reference: body?.id };
  } catch (err) {
    console.error("[send-invoice] email transport failed", err instanceof Error ? err.message : err);
    return { status: "failed", configured: true, detail: "Couldn't reach the email provider." };
  }
}

async function sendSms(
  to: string,
  body: string,
): Promise<{ status: "sent" | "failed"; configured: boolean; detail: string; reference?: string }> {
  const sid = Deno.env.get("TWILIO_ACCOUNT_SID");
  const authToken = Deno.env.get("TWILIO_AUTH_TOKEN");
  const from = Deno.env.get("TWILIO_FROM_NUMBER");
  if (!sid || !authToken || !from) {
    return { status: "failed", configured: false, detail: NOT_CONFIGURED_SMS };
  }

  try {
    const response = await fetch(`https://api.twilio.com/2010-04-01/Accounts/${sid}/Messages.json`, {
      method: "POST",
      headers: {
        Authorization: `Basic ${btoa(`${sid}:${authToken}`)}`,
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: new URLSearchParams({ To: to, From: from, Body: body }),
    });
    const payload = await response.json().catch(() => ({}));
    if (!response.ok) {
      return {
        status: "failed",
        configured: true,
        detail: `SMS provider refused the message (${response.status}).`,
      };
    }
    return { status: "sent", configured: true, detail: "Handed to the SMS provider.", reference: payload?.sid };
  } catch (err) {
    console.error("[send-invoice] sms transport failed", err instanceof Error ? err.message : err);
    return { status: "failed", configured: true, detail: "Couldn't reach the SMS provider." };
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);

  try {
    const { userId, supabase } = await requireAuth(req);
    const payload = (await req.json().catch(() => ({}))) as SendRequest;

    const invoiceId = payload.invoiceId ?? "";
    if (!UUID_PATTERN.test(invoiceId)) return jsonResponse({ error: "invalidRequest" }, 400);

    const requested = Array.isArray(payload.channels) ? payload.channels : [];
    const channels = (["email", "sms"] as const).filter((channel) => requested.includes(channel));
    if (channels.length === 0) return jsonResponse({ error: "invalidRequest" }, 400);

    // Who is asking. RLS lets a user read their own row and no other company's.
    const { data: caller } = await supabase
      .from("app_users")
      .select("id, company_id, role, status")
      .eq("id", userId)
      .maybeSingle();

    if (!caller || caller.status !== "active") return jsonResponse({ error: "notPermitted" }, 403);

    // The same role/permission matrix the app and every RLS policy use.
    const { data: grants } = await supabase
      .from("role_permissions")
      .select("permission")
      .eq("role", caller.role)
      .eq("permission", "invoicesManage");

    if (!grants || grants.length === 0) {
      return jsonResponse({ error: "notPermitted", permission: "invoicesManage" }, 403);
    }

    // Read with the caller's JWT: RLS is what proves this invoice is theirs.
    const { data: invoice } = await supabase
      .from("invoices")
      .select(
        "id, company_id, customer_id, billing_contact_id, number, title, status, currency_code, due_date, total, balance",
      )
      .eq("id", invoiceId)
      .maybeSingle();

    if (!invoice) return jsonResponse({ error: "notFound" }, 404);
    if (invoice.company_id !== caller.company_id) return jsonResponse({ error: "notFound" }, 404);
    if (invoice.status === "draft") {
      return jsonResponse(
        { error: "rejected", message: `Move ${invoice.number} out of draft before sending it.` },
        422,
      );
    }
    if (invoice.status === "void") {
      return jsonResponse(
        { error: "rejected", message: `${invoice.number} has been voided and can't be sent.` },
        422,
      );
    }

    const [{ data: company }, { data: contact }] = await Promise.all([
      supabase
        .from("companies")
        // `business_email` is the business's own customer-facing reply address.
        // Read with the caller's JWT, so RLS proves it is their company's.
        .select("name, phone, time_zone_identifier, address_line, city, state, postal_code, business_email")
        .eq("id", invoice.company_id)
        .maybeSingle(),
      invoice.billing_contact_id
        ? supabase
          .from("customer_contacts")
          .select("name, email, phone")
          .eq("id", invoice.billing_contact_id)
          .maybeSingle()
        : Promise.resolve({ data: null }),
    ]);

    const emailRecipient = (payload.email ?? contact?.email ?? "").trim();
    const phoneRecipient = (payload.phone ?? contact?.phone ?? "").trim();

    if (channels.includes("email") && !EMAIL_PATTERN.test(emailRecipient)) {
      return jsonResponse(
        { error: "rejected", message: "There's no valid email address for this invoice's billing contact." },
        422,
      );
    }
    if (channels.includes("sms") && !PHONE_PATTERN.test(phoneRecipient)) {
      return jsonResponse(
        { error: "rejected", message: "There's no valid mobile number for this invoice's billing contact." },
        422,
      );
    }

    // The customer-facing link. Issued through the caller's own JWT, so the
    // function's permission rules apply here too.
    const { data: token, error: tokenError } = await supabase.rpc("issue_invoice_share_token", {
      p_invoice: invoice.id,
      p_rotate: false,
    });

    if (tokenError || typeof token !== "string") {
      console.error("[send-invoice] could not issue share token", tokenError?.message);
      return jsonResponse({ error: "rejected", message: tokenError?.message ?? "Couldn't prepare the link." }, 422);
    }

    // The customer-facing page is served by the project's Cloudflare Worker:
    // Supabase's edge gateway forces every function response to `text/plain`,
    // so an invoice rendered from there would reach the customer as raw markup.
    const pageBase = (Deno.env.get("EXPO_PUBLIC_RORK_FUNCTIONS_URL") || PAGE_BASE_FALLBACK)
      .replace(/\/+$/, "");
    const viewUrl = `${pageBase}/i?t=${token}`;
    const companyName = company?.name ?? "Your contractor";
    const businessEmail = (company?.business_email ?? "").trim() || null;
    const sender = resolveSender(companyName, businessEmail);
    const amount = money(invoice.balance, invoice.currency_code);
    const subject = `Invoice ${invoice.number} from ${companyName} — ${amount} due`;

    // The business's own contact block, as a customer expects to see it on a
    // bill. Empty parts are dropped rather than printed as blanks.
    const companyAddress = [company?.address_line, company?.city, company?.state, company?.postal_code]
      .filter((part) => part && String(part).trim().length > 0)
      .join(", ");

    const contactLines = [
      company?.phone ? `Call ${company.phone}` : null,
      businessEmail,
    ].filter((line): line is string => Boolean(line));

    const text =
      `${companyName}\n${companyAddress ? `${companyAddress}\n` : ""}` +
      `\nInvoice ${invoice.number}${invoice.title ? ` — ${invoice.title}` : ""}\n` +
      `Amount due: ${amount}\nDue date: ${invoice.due_date}\n\nView and pay your invoice:\n${viewUrl}\n\n` +
      `${contactLines.length > 0 ? `Questions? ${contactLines.join(" · ")}\n` : ""}` +
      `\nThis invoice was sent by ${companyName} using Harbour South FieldOps.\n`;

    // Branded as the TRADE BUSINESS. The business's mark is its own initial on
    // its brand colours — an <img> is deliberately not used, because a hosted
    // logo would be blocked by most mail clients by default and leave a broken
    // image where the business's identity should be.
    const initial = escapeHtml((companyName.trim()[0] ?? "·").toUpperCase());
    const html =
      `<div style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;` +
      `color:#0F1B2A;line-height:1.6;max-width:560px">` +
      `<table role="presentation" cellpadding="0" cellspacing="0" style="margin:0 0 18px"><tr>` +
      `<td style="width:44px;height:44px;background:#14367A;border-radius:11px;color:#fff;` +
      `font-size:20px;font-weight:700;text-align:center;vertical-align:middle">${initial}</td>` +
      `<td style="padding-left:12px">` +
      `<div style="font-size:17px;font-weight:700;color:#0F1B2A">${escapeHtml(companyName)}</div>` +
      `${companyAddress ? `<div style="font-size:13px;color:#5B6675">${escapeHtml(companyAddress)}</div>` : ""}` +
      `</td></tr></table>` +
      `<p style="margin:0 0 6px;color:#5B6675">Invoice <strong style="color:#0F1B2A">${escapeHtml(invoice.number)}</strong>${
        invoice.title ? ` — ${escapeHtml(invoice.title)}` : ""
      }</p>` +
      `<p style="font-size:30px;font-weight:700;margin:12px 0 4px;color:#0F1B2A">${escapeHtml(amount)}</p>` +
      `<p style="margin:0 0 22px;color:#5B6675">due ${escapeHtml(String(invoice.due_date))}</p>` +
      `<p style="margin:0 0 22px"><a href="${escapeHtml(viewUrl)}" style="background:#E1691A;color:#fff;` +
      `text-decoration:none;padding:14px 24px;border-radius:11px;font-weight:700;display:inline-block">` +
      `View &amp; pay invoice</a></p>` +
      `${
        contactLines.length > 0
          ? `<p style="color:#5B6675;margin:0 0 6px;font-size:14px">Questions? ${
            escapeHtml(contactLines.join(" · "))
          }</p>`
          : ""
      }` +
      `<p style="color:#8A94A3;margin:18px 0 0;font-size:12px">Sent by ${escapeHtml(companyName)} ` +
      `using Harbour South FieldOps.</p>` +
      `</div>`;

    const smsBody = `${companyName}: invoice ${invoice.number}, ${amount} due ${invoice.due_date}. View and pay: ${viewUrl}`;

    const outcomes: ChannelOutcome[] = [];

    for (const channel of channels) {
      const recipient = channel === "email" ? emailRecipient : phoneRecipient;

      // Reserve first. For SMS this verifies and debits credit in the same
      // transaction that writes the notification row, under a per-company
      // lock. Nothing is handed to a provider before the credit is secured.
      const { data: queued, error: queueError } = await supabase.rpc("queue_invoice_notification", {
        p_invoice: invoice.id,
        p_channel: channel,
        p_recipient: recipient,
      });

      const reservation = (Array.isArray(queued) ? queued[0] : queued) as QueueRow | null;

      if (queueError || !reservation) {
        console.error("[send-invoice] could not queue the attempt", queueError?.message);
        outcomes.push({
          channel,
          recipient,
          status: "failed",
          configured: true,
          detail: queueError?.message ?? "Couldn't record this send, so nothing was delivered.",
          creditsCharged: 0,
          smsCreditBalance: null,
        });
        continue;
      }

      // Out of credit: the attempt is already recorded as failed and no credit
      // moved. Never hand it to the provider — that would be an unpaid send.
      if (reservation.outcome === "insufficientCredit") {
        outcomes.push({
          channel,
          recipient,
          status: "failed",
          configured: true,
          detail: `Not enough SMS credit to send this message. Balance: ${reservation.balance_after ?? 0}.`,
          creditsCharged: 0,
          smsCreditBalance: reservation.balance_after,
        });
        continue;
      }

      const result = channel === "email"
        ? await sendEmail(recipient, subject, html, text, sender)
        : await sendSms(recipient, smsBody);

      // Record the real outcome. A failed SMS gets its credit back here.
      const { data: settled, error: settleError } = await supabase.rpc("settle_notification", {
        p_notification: reservation.notification_id,
        p_delivered: result.status === "sent",
        p_provider_reference: result.reference ?? null,
        p_failure_reason: result.status === "failed" ? result.detail : null,
      });

      if (settleError) {
        console.error("[send-invoice] could not settle the attempt", settleError.message);
      }

      const settlement = (Array.isArray(settled) ? settled[0] : settled) as SettleRow | null;
      const refunded = settlement?.credits_refunded ?? 0;

      outcomes.push({
        channel,
        recipient,
        status: result.status,
        configured: result.configured,
        detail: result.detail,
        creditsCharged: Math.max(0, reservation.credits_charged - refunded),
        smsCreditBalance: channel === "sms" ? settlement?.balance_after ?? reservation.balance_after : null,
      });
    }

    return jsonResponse({ invoiceId: invoice.id, viewUrl, results: outcomes });
  } catch (err) {
    if (err instanceof AuthError) return jsonResponse({ error: "Unauthorized" }, 401);
    console.error("[send-invoice] unexpected failure", err instanceof Error ? err.message : err);
    return jsonResponse({ error: "Internal server error" }, 500);
  }
});
