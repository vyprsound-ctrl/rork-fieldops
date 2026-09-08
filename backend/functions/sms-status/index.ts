import { corsHeaders, createAdminClient, jsonResponse } from "../_shared/auth.ts";

/// Twilio's delivery status callback.
///
/// WHY THIS EXISTS: handing a message to Twilio is not delivering it. Without
/// this callback every message would sit on "sent" forever and the app would be
/// claiming an outcome it does not know. `sent` here means the carrier accepted
/// it; `delivered` means the handset got it; `undelivered` and `failed` mean it
/// did not arrive, and that is when the company gets its credit back.
///
/// SECURITY: Twilio does not carry a Supabase JWT, so this function is deployed
/// with --no-verify-jwt and authenticates the REQUEST ITSELF by validating
/// Twilio's X-Twilio-Signature over the exact posted form. An unsigned callback
/// is refused before it can move a message to "delivered".
///
/// TENANCY: the company is never read from the callback. The MessageSid is
/// looked up in our own notifications table, which was company-stamped when the
/// message was created, so a forged SID for another company's message resolves
/// to that company's own row or to nothing at all.
///
/// IDEMPOTENCY: Twilio retries. Terminal states are only applied once, and the
/// refund helper refuses to refund a message twice, so repeated callbacks
/// cannot return two credits for one failure.

/// Validates Twilio's HMAC-SHA1 signature over the full URL plus the sorted
/// POST body, per Twilio's documented scheme.
async function verifyTwilioSignature(
  url: string,
  params: Record<string, string>,
  signature: string | null,
  authToken: string,
): Promise<boolean> {
  if (!signature) return false;

  const sorted = Object.keys(params).sort();
  let payload = url;
  for (const key of sorted) payload += key + params[key];

  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(authToken),
    { name: "HMAC", hash: "SHA-1" },
    false,
    ["sign"],
  );
  const mac = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(payload));
  const expected = btoa(String.fromCharCode(...new Uint8Array(mac)));

  if (expected.length !== signature.length) return false;
  let diff = 0;
  for (let i = 0; i < expected.length; i++) diff |= expected.charCodeAt(i) ^ signature.charCodeAt(i);
  return diff === 0;
}

/// Twilio's vocabulary mapped onto ours. Anything unrecognised is left alone
/// rather than guessed at.
function mapStatus(twilioStatus: string): "sent" | "delivered" | "failed" | "undelivered" | null {
  switch (twilioStatus) {
    case "queued":
    case "accepted":
    case "sending":
    case "sent":
      return "sent";
    case "delivered":
      return "delivered";
    case "undelivered":
      return "undelivered";
    case "failed":
      return "failed";
    default:
      return null;
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);

  const authToken = Deno.env.get("TWILIO_AUTH_TOKEN");
  if (!authToken) {
    console.error("[sms-status] no Twilio auth token — refusing every callback");
    return jsonResponse({ error: "Not configured" }, 500);
  }

  const raw = await req.text();
  const form = new URLSearchParams(raw);
  const params: Record<string, string> = {};
  for (const [key, value] of form.entries()) params[key] = value;

  // Twilio signs the URL it was configured with. Prefer the explicitly
  // configured value so a proxy rewriting the host cannot break verification.
  const callbackUrl = Deno.env.get("TWILIO_STATUS_CALLBACK_URL") ?? req.url;

  const verified = await verifyTwilioSignature(
    callbackUrl,
    params,
    req.headers.get("X-Twilio-Signature"),
    authToken,
  );

  if (!verified) {
    console.warn("[sms-status] rejected a callback with an invalid signature");
    return jsonResponse({ error: "Invalid signature" }, 403);
  }

  const sid = params.MessageSid ?? params.SmsSid;
  const twilioStatus = params.MessageStatus ?? params.SmsStatus ?? "";
  if (!sid) return jsonResponse({ error: "No message id" }, 400);

  const status = mapStatus(twilioStatus);
  if (!status) return jsonResponse({ received: true, ignored: twilioStatus });

  const admin = createAdminClient();

  const { data: notification } = await admin
    .from("notifications")
    .select("id,company_id,status,credits_charged,credits_refunded")
    .eq("provider_reference", sid)
    .maybeSingle();

  if (!notification) {
    // Not ours, or not ours yet. 200 so Twilio stops retrying a message we will
    // never recognise.
    return jsonResponse({ received: true, unknown: true });
  }

  // Never walk a terminal state backwards: a late "sent" callback arriving
  // after "delivered" must not undo the delivery.
  const terminal = new Set(["delivered", "failed", "undelivered"]);
  if (terminal.has(notification.status) && status === "sent") {
    return jsonResponse({ received: true, ignored: "already settled" });
  }

  const update: Record<string, unknown> = {
    status,
    provider_status: twilioStatus,
    updated_at: new Date().toISOString(),
  };
  if (status === "delivered") update.delivered_at = new Date().toISOString();
  if (status === "failed" || status === "undelivered") {
    update.failure_reason = params.ErrorMessage ?? `Carrier reported ${twilioStatus}.`;
    update.provider_error = params.ErrorCode ?? null;
  }

  const { error } = await admin.from("notifications").update(update).eq("id", notification.id);
  if (error) {
    console.error("[sms-status] could not update the message", error.message);
    return jsonResponse({ error: "Could not record the status" }, 500);
  }

  // The message was paid for and never arrived, so the credit goes back.
  // refund_sms_credit is idempotent — a second callback for the same failure
  // returns 'nothingToRefund' and writes no ledger row.
  let refunded = 0;
  if (status === "failed" || status === "undelivered") {
    const { data } = await admin.rpc("refund_sms_credit", {
      p_notification: notification.id,
      p_reason: `carrier ${twilioStatus}`,
    });
    const result = (Array.isArray(data) ? data[0] : data) as { credits_refunded?: number } | null;
    refunded = result?.credits_refunded ?? 0;
  }

  return jsonResponse({ received: true, status, creditsRefunded: refunded });
});
