import { corsHeaders, createAdminClient, jsonResponse } from "../_shared/auth.ts";
import { priceToMicros, readTwilioForm, statusCallbackUrl, verifyTwilioSignature } from "../_shared/twilio.ts";
import { firstRow } from "../_shared/sms.ts";

/// Twilio delivery status callback, per company.
///
/// Every company's Messaging Service and every message it sends carry a
/// status URL with that company's random callback key (`?k=`). A callback is
/// only applied when ALL of these hold:
///   1. the key resolves to a messaging account;
///   2. X-Twilio-Signature is valid over the exact URL + form (subaccount or
///      master token — both are secrets only Twilio and Harbour South hold);
///   3. the posted AccountSid is that company's subaccount;
///   4. the MessageSid belongs to a message OF THAT COMPANY (the database looks
///      it up by reference AND company id).
/// So a forged, replayed or cross-company callback can never move a message
/// or return a credit. Terminal states never walk backwards; refunds are
/// idempotent.

const KEY_PATTERN = /^[0-9a-f]{48}$/;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);

  const key = new URL(req.url).searchParams.get("k") ?? "";
  if (!KEY_PATTERN.test(key)) return jsonResponse({ error: "Unknown callback" }, 404);

  const params = await readTwilioForm(req);
  const admin = createAdminClient();

  const { data: ctxData, error: ctxError } = await admin.rpc("messaging_webhook_context", { p_callback_key: key });
  const ctx = firstRow<{ company_id: string; twilio_subaccount_sid: string | null; auth_token: string | null }>(ctxData);
  if (ctxError || !ctx) return jsonResponse({ error: "Unknown callback" }, 404);

  const verified = await verifyTwilioSignature(
    statusCallbackUrl(key),
    params,
    req.headers.get("X-Twilio-Signature"),
    [ctx.auth_token, Deno.env.get("TWILIO_MASTER_AUTH_TOKEN")],
  );
  if (!verified) {
    console.warn("[sms-status] rejected a callback with an invalid signature");
    return jsonResponse({ error: "Invalid signature" }, 403);
  }

  const sid = params.MessageSid ?? params.SmsSid ?? "";
  const status = params.MessageStatus ?? params.SmsStatus ?? "";
  if (!sid) return jsonResponse({ error: "No message id" }, 400);

  const { data, error } = await admin.rpc("sms_apply_status", {
    p_callback_key: key,
    p_account_sid: params.AccountSid ?? "",
    p_message_sid: sid,
    p_status: status,
    p_error_code: params.ErrorCode ?? null,
    p_error_message: params.ErrorCode ? "The carrier could not deliver this message." : null,
    p_price_micros: priceToMicros(params.Price),
  });
  if (error) {
    console.error("[sms-status] could not apply status", error.code);
    return jsonResponse({ error: "Could not record the status" }, 500);
  }
  const result = firstRow<{ outcome: string; credits_refunded: number }>(data);
  if (result?.outcome === "wrongAccount") return jsonResponse({ error: "Account mismatch" }, 403);
  // Unknown or already-settled messages answer 200 so Twilio stops retrying.
  return jsonResponse({ received: true, outcome: result?.outcome ?? "unknown", creditsRefunded: result?.credits_refunded ?? 0 });
});
