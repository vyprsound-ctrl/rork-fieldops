/// App Store Server Notifications V2 for Harbour South's own subscription.
///
/// Apple POSTs `{ "signedPayload": "<JWS>" }` here for every subscription
/// event: SUBSCRIBED, DID_RENEW, DID_CHANGE_RENEWAL_PREF (upgrade / downgrade),
/// DID_CHANGE_RENEWAL_STATUS (cancel / un-cancel), OFFER_REDEEMED (Offer
/// Codes), DID_FAIL_TO_RENEW (billing retry, grace period), GRACE_PERIOD_EXPIRED,
/// EXPIRED, REFUND, REVOKE, and TEST. Called by Apple, not by a user, so there
/// is no JWT: the request authenticates itself by Apple's signature, which is
/// verified — for the envelope and for the transaction and renewal info inside
/// it — to Apple Root CA - G3 before anything is read.
///
/// The notification only reports facts; the entitlement is derived by
/// `apple_apply_transaction()` and re-evaluated against the database clock on
/// every read, so an out-of-order or missing notification cannot leave a
/// company entitled past its expiry.
///
/// Responses: 200 once handled (or a duplicate, or a subscription not yet
/// linked to any company). 500 when it could not be processed, so Apple
/// retries.

import { corsHeaders, createAdminClient, jsonResponse } from "../_shared/auth.ts";
import {
  type AppleRenewalInfo,
  type AppleTransaction,
  AppleVerificationError,
  expectedBundleId,
  verifyAppleJws,
  verifyTransaction,
} from "../_shared/apple.ts";

interface NotificationPayload {
  notificationType: string;
  subtype?: string;
  notificationUUID: string;
  signedDate?: number;
  data?: {
    bundleId?: string;
    environment?: string;
    signedTransactionInfo?: string;
    signedRenewalInfo?: string;
  };
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);

  let notification: NotificationPayload;
  try {
    const body = await req.json();
    notification = await verifyAppleJws<NotificationPayload>(String(body?.signedPayload ?? ""));
  } catch (err) {
    const reason = err instanceof AppleVerificationError ? err.message : "malformed body";
    console.warn("[app-store-notifications] refused:", reason);
    return jsonResponse({ error: "Invalid notification" }, 400);
  }

  if (notification.data?.bundleId && notification.data.bundleId !== expectedBundleId()) {
    return jsonResponse({ error: "Wrong app" }, 400);
  }

  const admin = createAdminClient();

  // Idempotency, arbitrated by the primary key.
  const { error: claimError } = await admin.from("apple_notifications").insert({
    notification_uuid: notification.notificationUUID,
    notification_type: notification.notificationType,
    subtype: notification.subtype ?? null,
    environment: notification.data?.environment ?? null,
    signed_at: notification.signedDate ? new Date(notification.signedDate).toISOString() : null,
  });
  if (claimError) {
    if (claimError.code === "23505") return jsonResponse({ received: true, duplicate: true });
    console.error("[app-store-notifications] could not record", claimError.message);
    return jsonResponse({ error: "Could not record" }, 500);
  }

  const finish = async (outcome: string, companyId: string | null, original: string | null) => {
    await admin.from("apple_notifications").update({
      outcome,
      company_id: companyId,
      original_transaction_id: original,
    }).eq("notification_uuid", notification.notificationUUID);
  };

  try {
    if (notification.notificationType === "TEST" || !notification.data?.signedTransactionInfo) {
      await finish(notification.notificationType === "TEST" ? "test" : "noTransaction", null, null);
      return jsonResponse({ received: true });
    }

    const tx: AppleTransaction = await verifyTransaction(notification.data.signedTransactionInfo);
    let renewal: AppleRenewalInfo | null = null;
    if (notification.data.signedRenewalInfo) {
      renewal = await verifyAppleJws<AppleRenewalInfo>(notification.data.signedRenewalInfo);
    }

    // The company: the subscription already linked to it, else the
    // appAccountToken the app set at purchase (the company id).
    let companyId: string | null = null;
    const { data: linked } = await admin
      .from("company_subscriptions")
      .select("company_id")
      .eq("apple_original_transaction_id", tx.originalTransactionId)
      .maybeSingle();
    companyId = linked?.company_id ?? null;

    if (!companyId && tx.appAccountToken && UUID.test(tx.appAccountToken)) {
      const { data: company } = await admin
        .from("companies").select("id").eq("id", tx.appAccountToken.toLowerCase()).maybeSingle();
      companyId = company?.id ?? null;
    }

    if (!companyId) {
      // Not linked yet — e.g. an Offer Code redeemed before the owner opened
      // the app. The app links it on its next sync; nothing to retry here.
      await finish("unlinked", null, tx.originalTransactionId);
      return jsonResponse({ received: true, linked: false });
    }

    const { data: outcome, error } = await admin.rpc("apple_apply_transaction", {
      p_company: companyId,
      p_transaction: tx,
      p_renewal: renewal,
      p_source: "notification",
    });
    if (error) throw new Error(`${error.code ?? ""} ${error.message}`);

    await finish(String(outcome), companyId, tx.originalTransactionId);
    return jsonResponse({ received: true });
  } catch (err) {
    console.error("[app-store-notifications] processing failed", err instanceof Error ? err.message : err);
    // Release the claim so Apple's retry is processed rather than deduplicated.
    await admin.from("apple_notifications").delete().eq("notification_uuid", notification.notificationUUID);
    return jsonResponse({ error: "Processing failed" }, 500);
  }
});
