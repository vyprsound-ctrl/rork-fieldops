import { AuthError, corsHeaders, createAdminClient, jsonResponse, requireAuth } from "../_shared/auth.ts";
import { isStripeConfigured, StripeError, stripeRequest } from "../_shared/stripe.ts";

/// Buys SMS credits.
///
/// This is FLOW A money — the trade business paying Harbour South — and it goes
/// to the PLATFORM Stripe account. It is deliberately not routed through the
/// connected account: a company buying credits is a customer of Harbour South,
/// not a merchant taking a payment. No `Stripe-Account` header appears anywhere
/// in this file.
///
/// It is also entirely separate from the SaaS subscription: a different Stripe
/// object, a different price, a different ledger. Buying credits never touches
/// the subscription and cancelling the subscription never destroys credits.
///
/// NO MINIMUM QUANTITY. The bundles come from the `sms_bundles` table, which
/// starts at 25 messages and can be repriced or extended with an UPDATE. A
/// caller may also name any positive quantity; the price is then derived from
/// the nearest bundle's unit rate, server-side. Nothing about the quantity is
/// decided by the app.
///
/// Credits are NOT granted here. They are granted by `credit_sms_purchase`,
/// called from the Stripe webhook once the money has actually arrived.

interface PurchaseRequest {
  action?: "bundles" | "checkout";
  bundleId?: string;
  credits?: number;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const { supabase, userId } = await requireAuth(req);
    const request = (await req.json().catch(() => ({}))) as PurchaseRequest;
    const action = request.action ?? "bundles";

    const { data: companyId, error: companyError } = await supabase.rpc("current_company_id");
    if (companyError || !companyId) return jsonResponse({ error: "No company for this user." }, 403);

    // The published price list is readable by anyone signed in; buying is not.
    const { data: bundles, error: bundleError } = await supabase
      .from("sms_bundles")
      .select("id,credits,price_cents,sort_order")
      .eq("is_active", true)
      .order("sort_order");

    if (bundleError) {
      console.error("[sms-purchase] could not read bundles", bundleError.message);
      return jsonResponse({ error: "Could not load credit bundles." }, 500);
    }

    const { data: balance } = await supabase.rpc("sms_credit_balance");

    if (action === "bundles") {
      return jsonResponse({
        configured: isStripeConfigured(),
        balance: balance ?? 0,
        bundles: (bundles ?? []).map((b: { id: string; credits: number; price_cents: number }) => ({
          id: b.id,
          credits: b.credits,
          priceCents: b.price_cents,
        })),
      });
    }

    // --- checkout ---------------------------------------------------------
    const { data: canBuy } = await supabase.rpc("has_perm", { p: "smsCreditsPurchase" });
    if (canBuy !== true) {
      return jsonResponse({ error: "You do not have permission to buy SMS credits." }, 403);
    }

    if (!isStripeConfigured()) {
      return jsonResponse({
        error: "Credit purchasing is not enabled for this deployment yet.",
        configured: false,
      }, 503);
    }

    const list = bundles ?? [];
    let credits: number;
    let priceCents: number;
    let bundleId: string | null = null;

    if (request.bundleId) {
      const bundle = list.find((b: { id: string }) => b.id === request.bundleId);
      if (!bundle) return jsonResponse({ error: "That bundle is no longer available." }, 400);
      credits = bundle.credits;
      priceCents = bundle.price_cents;
      bundleId = bundle.id;
    } else {
      // Arbitrary quantity. Priced from the largest bundle at or below the
      // requested size, so a custom amount never costs more per message than
      // the equivalent published bundle.
      credits = Math.floor(Number(request.credits ?? 0));
      if (!Number.isFinite(credits) || credits <= 0) {
        return jsonResponse({ error: "Choose how many credits to buy." }, 400);
      }
      if (credits > 100_000) {
        return jsonResponse({ error: "That is more credits than can be bought in one go." }, 400);
      }
      const applicable = [...list]
        .filter((b: { credits: number }) => b.credits <= credits)
        .sort((a: { credits: number }, b: { credits: number }) => b.credits - a.credits)[0]
        ?? list[0];

      if (!applicable) return jsonResponse({ error: "No pricing is configured." }, 500);
      const unit = applicable.price_cents / applicable.credits;
      priceCents = Math.max(1, Math.round(unit * credits));
    }

    const admin = createAdminClient();

    // Recorded as pending BEFORE Stripe is involved, so a checkout that
    // succeeds while the app is closed still has a row for the webhook to find.
    const { data: purchase, error: purchaseError } = await admin
      .from("sms_credit_purchases")
      .insert({
        company_id: companyId,
        bundle_id: bundleId,
        credits,
        price_cents: priceCents,
        status: "pending",
        requested_by_user_id: userId,
      })
      .select("id")
      .single();

    if (purchaseError || !purchase) {
      console.error("[sms-purchase] could not record the purchase", purchaseError?.message);
      return jsonResponse({ error: "Could not start the purchase." }, 500);
    }

    const returnBase = Deno.env.get("APP_RETURN_URL") ?? "https://harboursouth.us";

    try {
      const session = await stripeRequest<{ id: string; url: string }>("/checkout/sessions", {
        mode: "payment",
        success_url: `${returnBase}/sms/success?purchase=${purchase.id}`,
        cancel_url: `${returnBase}/sms/cancelled?purchase=${purchase.id}`,
        client_reference_id: purchase.id,
        // Metadata written by US, which is what the webhook trusts. A client
        // never supplies a company id anywhere in this flow.
        metadata: {
          company_id: companyId,
          purchase_id: purchase.id,
          kind: "sms_credits",
        },
        line_items: [{
          quantity: 1,
          price_data: {
            currency: "usd",
            unit_amount: priceCents,
            product_data: {
              name: `${credits.toLocaleString("en-US")} SMS credits`,
              description: "Harbour South FieldOps messaging credits",
            },
          },
        }],
      }, {
        // One checkout session per purchase row, however many times the button
        // is tapped.
        idempotencyKey: `sms-checkout-${purchase.id}`,
      });

      await admin.from("sms_credit_purchases").update({
        stripe_checkout_session_id: session.id,
        updated_at: new Date().toISOString(),
      }).eq("id", purchase.id);

      return jsonResponse({
        configured: true,
        purchaseId: purchase.id,
        credits,
        priceCents,
        checkoutUrl: session.url,
      });
    } catch (err) {
      await admin.from("sms_credit_purchases").update({
        status: "failed",
        updated_at: new Date().toISOString(),
      }).eq("id", purchase.id);

      if (err instanceof StripeError) {
        return jsonResponse({ error: err.message }, 400);
      }
      throw err;
    }
  } catch (err) {
    if (err instanceof AuthError) return jsonResponse({ error: "Unauthorized" }, 401);
    console.error("[sms-purchase] unexpected failure", err instanceof Error ? err.message : err);
    return jsonResponse({ error: "Internal server error" }, 500);
  }
});
