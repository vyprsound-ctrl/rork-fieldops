/// Links the company's Apple subscription to Harbour South, from the app.
///
/// Called by the iOS app after a StoreKit 2 purchase, an Offer Code
/// redemption, a restore, a Transaction.updates delivery, or a launch-time
/// entitlement sync. The body carries Apple's own signed data — the
/// transaction JWS and, when StoreKit has it, the renewal-info JWS. Nothing the
/// app says is believed: every JWS is verified to Apple Root CA - G3 and the
/// bundle id is checked before `apple_apply_transaction()` is called.
///
/// Tenancy: the company comes from the signed-in user inside the database, and
/// only a role holding `saasBillingManage` (the owner) may link a purchase.
/// When the app set `appAccountToken` at purchase it is the company id, and a
/// mismatch is refused. Offer Codes redeemed outside the app carry no token and
/// are linked to the caller's company; the database still refuses to attach one
/// Apple subscription to two companies.
///
/// Harbour South's subscription is billed by Apple only. This function never
/// takes a payment and never touches Stripe.

import { AuthError, corsHeaders, createAdminClient, jsonResponse, requireAuth } from "../_shared/auth.ts";
import {
  type AppleRenewalInfo,
  AppleVerificationError,
  verifyAppleJws,
  verifyTransaction,
} from "../_shared/apple.ts";

interface SyncRequest {
  purchases?: { transaction: string; renewal?: string | null }[];
}

const MAX_PURCHASES = 20;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);

  try {
    const { supabase } = await requireAuth(req);

    const { data: companyId, error: companyError } = await supabase.rpc("current_company_id");
    if (companyError || !companyId) return jsonResponse({ error: "No company for this user." }, 403);

    const { data: canManage } = await supabase.rpc("has_perm", { p: "saasBillingManage" });
    if (canManage !== true) {
      return jsonResponse({ error: "Only the account owner can manage the Harbour South subscription." }, 403);
    }

    const body = (await req.json().catch(() => ({}))) as SyncRequest;
    const purchases = Array.isArray(body.purchases) ? body.purchases.slice(0, MAX_PURCHASES) : [];
    if (purchases.length === 0) return jsonResponse({ results: [] });

    const admin = createAdminClient();
    const results: { transactionId: string | null; outcome: string }[] = [];

    for (const purchase of purchases) {
      let transactionId: string | null = null;
      try {
        const tx = await verifyTransaction(purchase.transaction);
        transactionId = tx.transactionId;

        if (tx.appAccountToken && tx.appAccountToken.toLowerCase() !== String(companyId).toLowerCase()) {
          results.push({ transactionId, outcome: "belongsToAnotherCompany" });
          continue;
        }

        let renewal: AppleRenewalInfo | null = null;
        if (purchase.renewal) {
          const decoded = await verifyAppleJws<AppleRenewalInfo>(purchase.renewal);
          if (decoded.originalTransactionId === tx.originalTransactionId) renewal = decoded;
        }

        const { data: outcome, error } = await admin.rpc("apple_apply_transaction", {
          p_company: companyId,
          p_transaction: tx,
          p_renewal: renewal,
          p_source: "app",
        });

        if (error) {
          if (error.code === "TD409") {
            results.push({ transactionId, outcome: "belongsToAnotherCompany" });
          } else {
            console.error("[apple-subscription] apply failed", error.code, error.message);
            results.push({ transactionId, outcome: "error" });
          }
          continue;
        }
        results.push({ transactionId, outcome: String(outcome) });
      } catch (err) {
        if (err instanceof AppleVerificationError) {
          console.warn("[apple-subscription] refused unverifiable data:", err.message);
          results.push({ transactionId, outcome: "unverified" });
        } else {
          console.error("[apple-subscription] unexpected", err instanceof Error ? err.message : err);
          results.push({ transactionId, outcome: "error" });
        }
      }
    }

    const anyApplied = results.some((r) => r.outcome.startsWith("applied") || r.outcome === "stale" || r.outcome === "upgradedAway");
    return jsonResponse({ results, linked: anyApplied });
  } catch (err) {
    if (err instanceof AuthError) return jsonResponse({ error: "Unauthorized" }, 401);
    console.error("[apple-subscription] failure", err instanceof Error ? err.message : err);
    return jsonResponse({ error: "Internal server error" }, 500);
  }
});
