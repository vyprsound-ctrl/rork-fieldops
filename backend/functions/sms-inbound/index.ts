import { corsHeaders, createAdminClient } from "../_shared/auth.ts";
import { inboundCallbackUrl, readTwilioForm, verifyTwilioSignature } from "../_shared/twilio.ts";
import { firstRow } from "../_shared/sms.ts";

/// Customer replies to a company's dedicated number.
///
/// Bound to the company by the random callback key in the Messaging Service's
/// inbound URL, then proven by the Twilio signature, the subaccount SID, the
/// Messaging Service SID and the receiving number — all checked in
/// `sms_record_inbound`. The reply is stored, matched to the customer/contact
/// and their current job, opt-out keywords are recorded (Twilio's Advanced
/// Opt-Out on the company's Messaging Service sends the carrier-required
/// STOP/START/HELP replies), and only owner/admin/dispatcher users are alerted.
///
/// The response is always empty TwiML: Harbour South never auto-replies on a
/// company's behalf.

const KEY_PATTERN = /^[0-9a-f]{48}$/;
const EMPTY_TWIML = '<?xml version="1.0" encoding="UTF-8"?><Response></Response>';

function twiml(status = 200): Response {
  return new Response(EMPTY_TWIML, { status, headers: { ...corsHeaders, "Content-Type": "text/xml" } });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return twiml(405);

  const key = new URL(req.url).searchParams.get("k") ?? "";
  if (!KEY_PATTERN.test(key)) return twiml(404);

  const params = await readTwilioForm(req);
  const admin = createAdminClient();

  const { data: ctxData } = await admin.rpc("messaging_webhook_context", { p_callback_key: key });
  const ctx = firstRow<{ company_id: string; auth_token: string | null }>(ctxData);
  if (!ctx) return twiml(404);

  const verified = await verifyTwilioSignature(
    inboundCallbackUrl(key),
    params,
    req.headers.get("X-Twilio-Signature"),
    [ctx.auth_token, Deno.env.get("TWILIO_MASTER_AUTH_TOKEN")],
  );
  if (!verified) {
    console.warn("[sms-inbound] rejected a request with an invalid signature");
    return twiml(403);
  }

  const { data, error } = await admin.rpc("sms_record_inbound", {
    p_callback_key: key,
    p_account_sid: params.AccountSid ?? "",
    p_messaging_service_sid: params.MessagingServiceSid ?? "",
    p_from: params.From ?? "",
    p_to: params.To ?? "",
    p_body: (params.Body ?? "").slice(0, 1600),
    p_message_sid: params.MessageSid ?? params.SmsSid ?? "",
    p_opt_out_type: params.OptOutType ?? null,
  });
  if (error) {
    console.error("[sms-inbound] could not record the message", error.code);
    return twiml(500);
  }
  const result = firstRow<{ outcome: string }>(data);
  if (result && ["wrongAccount", "wrongService", "wrongNumber"].includes(result.outcome)) {
    console.warn("[sms-inbound] refused a cross-company message:", result.outcome);
    return twiml(403);
  }
  return twiml(200);
});
