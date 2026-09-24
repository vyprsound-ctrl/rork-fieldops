import type { SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import { sendThroughCompany, type TwilioCredentials } from "./twilio.ts";

/// Everything every customer-SMS path shares: server-side template rendering,
/// company identification, the reservation, delivery through the company's own
/// Twilio subaccount, and the wording customers see.
///
/// COMPANY CONTEXT IS NEVER TAKEN FROM A CLIENT. Callers pass the company they
/// resolved from the authenticated session (or from the callback key), and
/// every lookup below is filtered by it explicitly as well as by RLS.

export const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const VARIABLE = /\{\{\s*([^{}]*?)\s*\}\}/g;
const PAGE_BASE_FALLBACK = "https://field-ops-backend.rork.app";

export function normalisePhone(raw: string | null | undefined): string | null {
  const trimmed = (raw ?? "").trim();
  if (!trimmed) return null;
  const digits = trimmed.replace(/[^0-9]/g, "");
  if (trimmed.startsWith("+")) return digits.length >= 8 && digits.length <= 15 ? `+${digits}` : null;
  if (digits.length === 10) return `+1${digits}`;
  if (digits.length === 11 && digits.startsWith("1")) return `+${digits}`;
  return null;
}

/// Customer-facing link base (the Cloudflare Worker serves /i and /q).
export function pageBase(): string {
  return (Deno.env.get("EXPO_PUBLIC_RORK_FUNCTIONS_URL") || PAGE_BASE_FALLBACK).replace(/\/+$/, "");
}

/// What a reservation outcome means, in words a trade business understands.
export function outcomeMessage(outcome: string, extra: { needed?: number; balance?: number } = {}): string {
  switch (outcome) {
    case "noSubscription": return "Texting customers needs an active Harbour South subscription.";
    case "notSetUp": return "SMS isn't set up yet. The owner can set it up in More → SMS & Messaging.";
    case "awaitingApproval": return "Your SMS number is waiting for carrier approval. You can send as soon as it's approved.";
    case "suspended": return "SMS is suspended for your company. Contact Harbour South support.";
    case "paused": return "SMS is paused because the monthly number fee is unpaid. Add SMS credits to resume.";
    case "noNumber": return "Your SMS number isn't ready yet.";
    case "companyClosed": return "This workspace is closed.";
    case "optedOut": return "This customer has opted out of texts. They can reply START to opt back in.";
    case "insufficientCredits":
      return extra.needed
        ? `You need ${extra.needed} SMS credit${extra.needed === 1 ? "" : "s"} for this message but have ${extra.balance ?? 0}. Buy more to continue.`
        : "You don't have enough SMS credits for this message. Buy more to continue.";
    case "recipientNotOnRecord": return "That number isn't on the customer's record. Add it as a contact first.";
    case "invalidRecipient": return "This customer has no usable mobile number.";
    case "emptyMessage": return "Write the message first.";
    case "tooLong": return "Keep the message under 640 characters.";
    case "unresolvedVariables": return "The message still has a {{placeholder}} that couldn't be filled in.";
    case "unknownCustomer": return "That customer could not be found.";
    case "unknownJob": return "That job could not be found for this customer.";
    case "unknownQuote": return "That quote could not be found for this customer.";
    case "unknownInvoice": return "That invoice could not be found for this customer.";
    case "unknownTemplate": return "Unknown message type.";
    case "notPermitted": return "Your role doesn't include texting customers.";
    default: return "The message could not be sent.";
  }
}

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------

export interface RenderContext {
  companyId: string;
  templateKey: string;
  customerId: string;
  jobId?: string | null;
  quoteId?: string | null;
  invoiceId?: string | null;
  recipient?: string | null;
  eta?: string | null;
  /// When set, render this text instead of the company's saved template.
  body?: string | null;
}

export interface RenderResult {
  ok: boolean;
  body: string;
  error?: string;
  missing?: string[];
}

interface TemplateRow {
  body: string;
  allowed_variables: string[];
  context: string;
}

function money(value: unknown, currency: string): string {
  const amount = Number(value ?? 0);
  try {
    return new Intl.NumberFormat("en-US", { style: "currency", currency: (currency || "USD").trim() }).format(amount);
  } catch {
    return `$${amount.toFixed(2)}`;
  }
}

function formatDate(iso: string, tz: string): string {
  return new Intl.DateTimeFormat("en-US", { timeZone: tz, weekday: "short", month: "short", day: "numeric" })
    .format(new Date(iso));
}

function formatTime(iso: string, tz: string): string {
  return new Intl.DateTimeFormat("en-US", { timeZone: tz, hour: "numeric", minute: "2-digit" }).format(new Date(iso));
}

export function variablesIn(body: string): string[] {
  return [...body.matchAll(VARIABLE)].map((m) => m[1]);
}

/// Puts the business's name on every operational message so the customer
/// always knows who is texting.
export function withCompanyIdentification(body: string, companyName: string): string {
  const name = companyName.trim();
  if (!name) return body;
  if (body.toLowerCase().includes(name.toLowerCase())) return body;
  return `${name}: ${body}`;
}

/// Renders a template with values the SERVER looks up. Any variable not valid
/// for that template, or whose value doesn't exist for this record, stops the
/// render — a malformed or half-filled message never reaches Twilio.
export async function renderMessage(admin: SupabaseClient, ctx: RenderContext): Promise<RenderResult> {
  const { data: defaults } = await admin
    .from("sms_template_defaults")
    .select("body, allowed_variables, context")
    .eq("template_key", ctx.templateKey)
    .maybeSingle();
  if (!defaults) return { ok: false, body: "", error: "Unknown message type." };
  const template = defaults as TemplateRow;

  let source = ctx.body ?? null;
  if (source === null) {
    const { data: custom } = await admin
      .from("sms_templates")
      .select("body")
      .eq("company_id", ctx.companyId)
      .eq("template_key", ctx.templateKey)
      .maybeSingle();
    source = (custom?.body as string | undefined) ?? template.body;
  }
  source = source.trim();

  const used = [...new Set(variablesIn(source))];
  const invalid = used.filter((v) => !template.allowed_variables.includes(v));
  if (invalid.length > 0) {
    return { ok: false, body: source, error: `{{${invalid[0]}}} can't be used in this message.` };
  }

  const { data: company } = await admin
    .from("companies")
    .select("name, time_zone_identifier, currency_code, closed_at")
    .eq("id", ctx.companyId)
    .maybeSingle();
  if (!company || company.closed_at) return { ok: false, body: source, error: "This workspace is closed." };
  const tz = (company.time_zone_identifier as string) || "America/New_York";

  const values: Record<string, string | null> = { company_name: company.name as string };
  const need = new Set(used);

  if (need.has("customer_first_name") || need.has("customer_last_name")) {
    const { data: customer } = await admin.from("customers").select("name").eq("id", ctx.customerId)
      .eq("company_id", ctx.companyId).maybeSingle();
    let personName = (customer?.name as string | undefined) ?? "";
    const wanted = normalisePhone(ctx.recipient);
    const { data: contacts } = await admin.from("customer_contacts").select("name, phone, is_primary")
      .eq("company_id", ctx.companyId).eq("customer_id", ctx.customerId).order("is_primary", { ascending: false });
    const match = (contacts ?? []).find((c: { phone: string | null }) => wanted && normalisePhone(c.phone) === wanted)
      ?? (contacts ?? [])[0];
    if (match?.name) personName = String(match.name);
    const parts = personName.trim().split(/\s+/).filter(Boolean);
    values.customer_first_name = parts[0] ?? null;
    values.customer_last_name = parts.length > 1 ? parts.slice(1).join(" ") : null;
  }

  if (ctx.jobId && ["job_number", "appointment_date", "appointment_time", "engineer_name", "eta"].some((v) => need.has(v))) {
    const { data: job } = await admin.from("jobs").select("id, number, scheduled_start, customer_id")
      .eq("id", ctx.jobId).eq("company_id", ctx.companyId).maybeSingle();
    if (job && job.customer_id === ctx.customerId) {
      values.job_number = job.number as string;
      if (job.scheduled_start) {
        values.appointment_date = formatDate(job.scheduled_start as string, tz);
        values.appointment_time = formatTime(job.scheduled_start as string, tz);
      }
      if (need.has("engineer_name")) {
        const { data: assignment } = await admin.from("field_worker_assignments").select("user_id")
          .eq("job_id", job.id).eq("company_id", ctx.companyId).order("is_primary", { ascending: false }).limit(1)
          .maybeSingle();
        if (assignment?.user_id) {
          const { data: worker } = await admin.from("app_users").select("name, status").eq("id", assignment.user_id)
            .eq("company_id", ctx.companyId).maybeSingle();
          const first = String(worker?.name ?? "").trim().split(/\s+/)[0];
          if (first && worker?.status === "active") values.engineer_name = first;
        }
      }
      if (need.has("eta") && !ctx.eta && job.scheduled_start) {
        values.eta = `around ${formatTime(job.scheduled_start as string, tz)}`;
      }
    }
  }
  if (ctx.eta) {
    const eta = ctx.eta.trim().slice(0, 40);
    if (/[{}]/.test(eta)) return { ok: false, body: source, error: "The arrival time can't contain { or }." };
    values.eta = eta;
  }

  if (ctx.quoteId && ["quote_number", "quote_link"].some((v) => need.has(v))) {
    const { data: quote } = await admin.from("quotes").select("id, number, customer_id, status")
      .eq("id", ctx.quoteId).eq("company_id", ctx.companyId).maybeSingle();
    if (quote && quote.customer_id === ctx.customerId) {
      values.quote_number = quote.number as string;
      if (need.has("quote_link")) {
        const { data: token, error } = await admin.rpc("issue_quote_share_token_service", {
          p_company: ctx.companyId,
          p_quote: quote.id,
        });
        if (error) return { ok: false, body: source, error: "Mark the quote as sent before texting its link." };
        values.quote_link = `${pageBase()}/q?t=${token}`;
      }
    }
  }

  if (ctx.invoiceId && ["invoice_number", "invoice_balance", "invoice_link", "payment_link"].some((v) => need.has(v))) {
    const { data: invoice } = await admin.from("invoices").select("id, number, customer_id, balance, currency_code, status")
      .eq("id", ctx.invoiceId).eq("company_id", ctx.companyId).maybeSingle();
    if (invoice && invoice.customer_id === ctx.customerId) {
      values.invoice_number = invoice.number as string;
      values.invoice_balance = money(invoice.balance, (invoice.currency_code as string) || (company.currency_code as string));
      if (need.has("invoice_link") || need.has("payment_link")) {
        const { data: token, error } = await admin.rpc("issue_invoice_share_token_service", {
          p_company: ctx.companyId,
          p_invoice: invoice.id,
        });
        if (error) return { ok: false, body: source, error: "Move the invoice out of draft before texting its link." };
        const link = `${pageBase()}/i?t=${token}`;
        values.invoice_link = link;
        values.payment_link = link;
      }
    }
  }

  const missing = used.filter((v) => !values[v]);
  if (missing.length > 0) {
    const labels: Record<string, string> = {
      customer_first_name: "the customer's name", customer_last_name: "the customer's last name",
      engineer_name: "an assigned engineer", job_number: "a job", appointment_date: "a booked appointment time",
      appointment_time: "a booked appointment time", eta: "an arrival time", quote_number: "a quote",
      quote_link: "a quote", invoice_number: "an invoice", invoice_balance: "an invoice",
      invoice_link: "an invoice", payment_link: "an invoice",
    };
    return {
      ok: false,
      body: source,
      missing,
      error: `This message needs ${labels[missing[0]] ?? missing[0]}, which isn't available here.`,
    };
  }

  let rendered = source.replace(VARIABLE, (_m, name: string) => values[name] ?? "");
  rendered = rendered.replace(/[ \t]{2,}/g, " ").trim();
  if (/[{}]{2}/.test(rendered)) return { ok: false, body: rendered, error: "The message has a malformed placeholder." };
  rendered = withCompanyIdentification(rendered, company.name as string);
  if (!rendered) return { ok: false, body: rendered, error: "Write the message first." };
  return { ok: true, body: rendered };
}

// ---------------------------------------------------------------------------
// Reservation + delivery
// ---------------------------------------------------------------------------

export interface Reservation {
  outcome: string;
  notification_id: string | null;
  credits_charged: number;
  segments: number | null;
  encoding: string | null;
  balance_after: number | null;
  messaging_account_id: string | null;
  twilio_account_sid: string | null;
  messaging_service_sid: string | null;
  from_number: string | null;
  to_number: string | null;
  conversation_id: string | null;
}

export function firstRow<T>(data: unknown): T | null {
  return (Array.isArray(data) ? data[0] : data) as T | null;
}

export interface DeliveryResult {
  sent: boolean;
  providerReference: string | null;
  balance: number | null;
  creditsCharged: number;
  detail: string;
  errorCode: string | null;
}

/// Hands a committed reservation to Twilio through THAT company's subaccount
/// and Messaging Service, then records the real outcome (refund on rejection).
export async function deliverReservation(
  admin: SupabaseClient,
  companyId: string,
  reservation: Reservation,
  body: string,
): Promise<DeliveryResult> {
  const notificationId = reservation.notification_id!;
  const { data: account } = await admin
    .from("company_messaging_accounts")
    .select("id, company_id, status, callback_key, twilio_subaccount_sid, messaging_service_sid")
    .eq("id", reservation.messaging_account_id ?? "")
    .maybeSingle();

  const consistent = account && account.company_id === companyId && account.status === "active" &&
    account.twilio_subaccount_sid && account.twilio_subaccount_sid === reservation.twilio_account_sid &&
    account.messaging_service_sid && account.messaging_service_sid === reservation.messaging_service_sid;

  let token: string | null = null;
  if (consistent) {
    const { data } = await admin.rpc("messaging_subaccount_token", { p_account: account.id });
    token = typeof data === "string" && data.length > 0 ? data : null;
  }

  if (!consistent || !token) {
    const { data } = await admin.rpc("sms_record_provider_result", {
      p_notification: notificationId, p_accepted: false, p_sid: null, p_status: null, p_from: null,
      p_segments: null, p_price_micros: null, p_error_code: "notConfigured",
      p_error: "SMS isn't fully set up for this company yet.",
    });
    const refund = firstRow<{ balance_after: number | null }>(data);
    console.error("[sms] refused to send: messaging account inconsistent or token missing");
    return {
      sent: false, providerReference: null, balance: refund?.balance_after ?? null, creditsCharged: 0,
      detail: "SMS isn't fully set up for this company yet. Your credits were returned.", errorCode: "notConfigured",
    };
  }

  const credentials: TwilioCredentials = { accountSid: account.twilio_subaccount_sid, authToken: token };
  const result = await sendThroughCompany(credentials, account.messaging_service_sid, account.callback_key,
    reservation.to_number!, body);

  const { data: recorded } = await admin.rpc("sms_record_provider_result", {
    p_notification: notificationId,
    p_accepted: result.accepted,
    p_sid: result.sid,
    p_status: result.status,
    p_from: result.from,
    p_segments: result.segments,
    p_price_micros: result.priceMicros,
    p_error_code: result.errorCode,
    p_error: result.errorMessage,
  });
  const settled = firstRow<{ credits_refunded: number; balance_after: number | null }>(recorded);

  if (result.accepted) {
    return {
      sent: true, providerReference: result.sid, balance: reservation.balance_after,
      creditsCharged: reservation.credits_charged, detail: "Handed to the carrier. Delivery is confirmed separately.",
      errorCode: null,
    };
  }
  return {
    sent: false, providerReference: null, balance: settled?.balance_after ?? reservation.balance_after,
    creditsCharged: 0, detail: `${result.errorMessage ?? "The message could not be sent."} Your credits were returned.`,
    errorCode: result.errorCode,
  };
}

/// The recipient: the requested number if it is on the customer's record,
/// otherwise the primary contact with a phone.
export async function resolveRecipient(
  client: SupabaseClient,
  companyId: string,
  customerId: string,
  requested: string | null | undefined,
): Promise<string | null> {
  const { data: contacts } = await client.from("customer_contacts").select("phone, is_primary")
    .eq("company_id", companyId).eq("customer_id", customerId).order("is_primary", { ascending: false });
  const phones = (contacts ?? []).map((c: { phone: string | null }) => normalisePhone(c.phone)).filter(Boolean) as string[];
  if (requested) {
    const wanted = normalisePhone(requested);
    return wanted && phones.includes(wanted) ? wanted : wanted ?? null;
  }
  return phones[0] ?? null;
}
