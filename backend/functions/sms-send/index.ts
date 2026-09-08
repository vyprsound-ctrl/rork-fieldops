import { AuthError, corsHeaders, createAdminClient, jsonResponse, requireAuth } from "../_shared/auth.ts";

/// Sends one customer SMS through Twilio, on the company's credit.
///
/// THE ORDER OF OPERATIONS IS THE WHOLE DESIGN:
///
///   1. Authenticate the caller.
///   2. Derive the company from the authenticated identity — NEVER from the
///      request body. There is no company field in the request to tamper with.
///   3. Check `smsCreditsConsume` against the same role matrix the app uses.
///   4. Resolve the customer WITH THE CALLER'S OWN JWT, so RLS proves the
///      customer belongs to the caller's company. Company A physically cannot
///      name a Company B customer here.
///   5. Create the notification row (company-stamped by the database).
///   6. Consume the credit ATOMICALLY. `consume_sms_credit` takes a
///      per-company advisory lock, so two simultaneous sends against a balance
///      of one produce exactly one message.
///   7. Only then hand the message to Twilio.
///   8. Record the real provider outcome. A Twilio rejection refunds the
///      credit; a Twilio acceptance does NOT claim delivery — that only comes
///      from the status callback.
///
/// If step 6 says there is not enough credit, step 7 never happens and the
/// balance is untouched.
///
/// Twilio credentials exist only in this function's environment. The iOS app
/// has never held one and cannot reach Twilio directly.

interface SendSmsRequest {
  customerId?: string;
  jobId?: string;
  invoiceId?: string;
  quoteId?: string;
  template?: string;
  body?: string;
  /// Optional explicit recipient. Validated against the customer's own contacts
  /// so it cannot be used to send to an arbitrary number on someone's credit.
  phone?: string;
}

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const PHONE_PATTERN = /^\+?[0-9][0-9()\s.-]{6,19}$/;

const MAX_BODY = 640;

interface ConsumeRow {
  outcome: string;
  credits_charged: number;
  balance_after: number | null;
}

function normalisePhone(raw: string): string {
  const trimmed = raw.trim();
  if (trimmed.startsWith("+")) return "+" + trimmed.slice(1).replace(/[^0-9]/g, "");
  const digits = trimmed.replace(/[^0-9]/g, "");
  // The product is US-first; a bare 10-digit number is a US number.
  if (digits.length === 10) return `+1${digits}`;
  if (digits.length === 11 && digits.startsWith("1")) return `+${digits}`;
  return `+${digits}`;
}

interface TwilioOutcome {
  configured: boolean;
  accepted: boolean;
  sid: string | null;
  status: string | null;
  segments: number | null;
  fromNumber: string | null;
  detail: string;
}

async function sendThroughTwilio(to: string, body: string): Promise<TwilioOutcome> {
  const sid = Deno.env.get("TWILIO_ACCOUNT_SID");
  const token = Deno.env.get("TWILIO_AUTH_TOKEN");
  const messagingService = Deno.env.get("TWILIO_MESSAGING_SERVICE_SID");
  const fromNumber = Deno.env.get("TWILIO_FROM_NUMBER");

  if (!sid || !token || (!messagingService && !fromNumber)) {
    return {
      configured: false,
      accepted: false,
      sid: null,
      status: null,
      segments: null,
      fromNumber: null,
      detail: "SMS is not configured for this deployment.",
    };
  }

  const form = new URLSearchParams();
  form.set("To", to);
  form.set("Body", body);
  if (messagingService) form.set("MessagingServiceSid", messagingService);
  else if (fromNumber) form.set("From", fromNumber);

  const statusCallback = Deno.env.get("TWILIO_STATUS_CALLBACK_URL");
  if (statusCallback) form.set("StatusCallback", statusCallback);

  try {
    const response = await fetch(
      `https://api.twilio.com/2010-04-01/Accounts/${sid}/Messages.json`,
      {
        method: "POST",
        headers: {
          "Authorization": `Basic ${btoa(`${sid}:${token}`)}`,
          "Content-Type": "application/x-www-form-urlencoded",
        },
        body: form.toString(),
      },
    );

    const payload = await response.json().catch(() => ({}));

    if (!response.ok) {
      return {
        configured: true,
        accepted: false,
        sid: null,
        status: null,
        segments: null,
        fromNumber: null,
        detail: String(payload?.message ?? `Twilio rejected the message (${response.status}).`),
      };
    }

    return {
      configured: true,
      accepted: true,
      sid: String(payload.sid),
      // "queued" or "accepted" — emphatically NOT "delivered".
      status: String(payload.status ?? "queued"),
      segments: payload.num_segments ? Number(payload.num_segments) : null,
      fromNumber: payload.from ? String(payload.from) : null,
      detail: "Handed to the carrier. Delivery is confirmed separately.",
    };
  } catch (err) {
    return {
      configured: true,
      accepted: false,
      sid: null,
      status: null,
      segments: null,
      fromNumber: null,
      detail: err instanceof Error ? err.message : "Could not reach the SMS provider.",
    };
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const { supabase } = await requireAuth(req);
    const request = (await req.json().catch(() => ({}))) as SendSmsRequest;

    const body = (request.body ?? "").trim();
    if (!body) return jsonResponse({ error: "The message is empty." }, 400);
    if (body.length > MAX_BODY) {
      return jsonResponse({ error: `Keep the message under ${MAX_BODY} characters.` }, 400);
    }
    if (!request.customerId || !UUID_PATTERN.test(request.customerId)) {
      return jsonResponse({ error: "A customer is required." }, 400);
    }

    // --- 2. Company from the session, not the payload ---------------------
    const { data: companyId, error: companyError } = await supabase.rpc("current_company_id");
    if (companyError || !companyId) return jsonResponse({ error: "No company for this user." }, 403);

    // --- 3. Permission ----------------------------------------------------
    const { data: canSend } = await supabase.rpc("has_perm", { p: "smsCreditsConsume" });
    if (canSend !== true) {
      return jsonResponse({ error: "You do not have permission to send messages." }, 403);
    }

    // --- 4. The customer, read under the CALLER'S OWN RLS -----------------
    //
    // This is the cross-company gate. The row simply does not exist for a
    // caller in another company, so a borrowed customer id returns "not found"
    // rather than someone else's phone number.
    const { data: customer, error: customerError } = await supabase
      .from("customers")
      .select("id,name,company_id")
      .eq("id", request.customerId)
      .maybeSingle();

    if (customerError || !customer) {
      return jsonResponse({ error: "That customer could not be found." }, 404);
    }
    if (customer.company_id !== companyId) {
      // Belt and braces: RLS should already have made this unreachable.
      console.warn("[sms-send] refused a cross-company customer reference");
      return jsonResponse({ error: "That customer could not be found." }, 404);
    }

    // Recipient must be one of that customer's own contacts.
    const { data: contacts } = await supabase
      .from("customer_contacts")
      .select("phone,is_primary")
      .eq("customer_id", customer.id)
      .order("is_primary", { ascending: false });

    const known = (contacts ?? [])
      .map((c: { phone: string | null }) => (c.phone ?? "").trim())
      .filter((p: string) => p.length > 0);

    let recipient = request.phone?.trim() ?? known[0] ?? "";
    if (request.phone) {
      const wanted = normalisePhone(request.phone);
      const matches = known.some((p: string) => normalisePhone(p) === wanted);
      if (!matches) {
        return jsonResponse({
          error: "That number is not on the customer's record. Add it as a contact first.",
        }, 400);
      }
      recipient = request.phone;
    }

    if (!recipient || !PHONE_PATTERN.test(recipient)) {
      return jsonResponse({ error: "This customer has no usable mobile number." }, 400);
    }

    const toNumber = normalisePhone(recipient);
    const admin = createAdminClient();

    // --- 5. The delivery record, company-stamped --------------------------
    const { data: notification, error: notificationError } = await admin
      .from("notifications")
      .insert({
        company_id: companyId,
        channel: "sms",
        status: "queued",
        template: request.template ?? "customerMessage",
        recipient: toNumber,
        to_number: toNumber,
        body,
        customer_id: customer.id,
        job_id: request.jobId && UUID_PATTERN.test(request.jobId) ? request.jobId : null,
        invoice_id: request.invoiceId && UUID_PATTERN.test(request.invoiceId) ? request.invoiceId : null,
      })
      .select("id")
      .single();

    if (notificationError || !notification) {
      console.error("[sms-send] could not create the delivery record", notificationError?.message);
      return jsonResponse({ error: "Could not queue the message." }, 500);
    }

    // --- 6. Atomic credit consumption -------------------------------------
    //
    // Runs with the CALLER'S client so the function's own
    // current_company_id()/has_perm() checks apply to the real user.
    const { data: consumeData, error: consumeError } = await supabase.rpc("consume_sms_credit", {
      p_notification: notification.id,
      p_customer: customer.id,
      p_job: request.jobId && UUID_PATTERN.test(request.jobId) ? request.jobId : null,
      p_credits: null,
    });

    if (consumeError) {
      await admin.from("notifications").update({
        status: "failed",
        failure_reason: "Credit could not be reserved.",
        updated_at: new Date().toISOString(),
      }).eq("id", notification.id);
      console.error("[sms-send] credit reservation failed", consumeError.message);
      return jsonResponse({ error: "Could not reserve an SMS credit." }, 500);
    }

    const consumed = (Array.isArray(consumeData) ? consumeData[0] : consumeData) as ConsumeRow | null;

    if (!consumed || consumed.outcome !== "consumed") {
      await admin.from("notifications").update({
        status: "failed",
        failure_reason: consumed?.outcome ?? "Credit could not be reserved.",
        updated_at: new Date().toISOString(),
      }).eq("id", notification.id);

      if (consumed?.outcome === "insufficientCredits") {
        // NOT a send, NOT an error state — a clear business answer, with the
        // balance left exactly where it was.
        return jsonResponse({
          sent: false,
          reason: "insufficientCredits",
          balance: consumed.balance_after ?? 0,
          error: "You do not have enough SMS credit to send this message. Buy more credits to continue.",
        }, 402);
      }

      return jsonResponse({
        sent: false,
        reason: consumed?.outcome ?? "unknown",
        error: "The message could not be sent.",
      }, 400);
    }

    // --- 7. Twilio --------------------------------------------------------
    const result = await sendThroughTwilio(toNumber, body);

    // --- 8. Record the real outcome ---------------------------------------
    if (!result.accepted) {
      // The provider never took it, so the credit goes back. Idempotent, so a
      // retry cannot refund twice.
      const { data: refund } = await admin.rpc("refund_sms_credit", {
        p_notification: notification.id,
        p_reason: result.configured ? "provider rejected" : "provider not configured",
      });
      const refunded = (Array.isArray(refund) ? refund[0] : refund) as
        | { balance_after: number | null }
        | null;

      await admin.from("notifications").update({
        status: "failed",
        failure_reason: result.detail,
        provider_error: result.detail,
        updated_at: new Date().toISOString(),
      }).eq("id", notification.id);

      return jsonResponse({
        sent: false,
        configured: result.configured,
        reason: result.configured ? "providerRejected" : "notConfigured",
        balance: refunded?.balance_after ?? consumed.balance_after,
        error: result.detail,
      }, result.configured ? 502 : 503);
    }

    await admin.from("notifications").update({
      // "accepted" — the carrier has it. Delivery is a separate, later fact.
      status: "sent",
      provider_reference: result.sid,
      provider_status: result.status,
      from_number: result.fromNumber,
      segments: result.segments,
      sent_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    }).eq("id", notification.id);

    return jsonResponse({
      sent: true,
      messageId: notification.id,
      providerReference: result.sid,
      status: result.status,
      creditsCharged: consumed.credits_charged,
      balance: consumed.balance_after,
      detail: result.detail,
    });
  } catch (err) {
    if (err instanceof AuthError) return jsonResponse({ error: "Unauthorized" }, 401);
    console.error("[sms-send] unexpected failure", err instanceof Error ? err.message : err);
    return jsonResponse({ error: "Internal server error" }, 500);
  }
});
