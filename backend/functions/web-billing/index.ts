import { AuthError, corsHeaders, createAdminClient, jsonResponse, requireAuth } from "../_shared/auth.ts";
import { isStripeConfigured, StripeError, stripeRequest } from "../_shared/stripe.ts";
import { ensureCatalog, syncStripeSubscription, WEB_APP_URL, type BillingPeriod } from "../_shared/webSubscriptions.ts";

/// Harbour South's subscription, bought and managed on the web.
///
/// FLOW A only: the trade business is Harbour South's customer and every call
/// goes to the PLATFORM Stripe account. Owner only (saasBillingManage).
///
/// Actions
///   checkout { tierId, period }  -> Stripe Checkout URL (no free trial)
///   portal                       -> Stripe Customer Portal URL
///   confirm  { sessionId }       -> applies a finished checkout straight away
///   refresh                      -> re-reads the subscription from Stripe
///
/// The company is ALWAYS the caller's own (current_company_id); a client never
/// supplies a company id. Entitlement is only ever written by the database's
/// apply_stripe_subscription(), which never overrides a live Apple plan.

interface BillingRequest {
  action?: "checkout" | "portal" | "confirm" | "refresh";
  tierId?: string;
  period?: BillingPeriod;
  sessionId?: string;
}

interface Commercial {
  has_entitlement: boolean;
  billing_store: string;
  active_users: number;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);

  try {
    const { supabase, userId } = await requireAuth(req);
    const request = (await req.json().catch(() => ({}))) as BillingRequest;

    const { data: canManage } = await supabase.rpc("has_perm", { p: "saasBillingManage" });
    if (canManage !== true) return jsonResponse({ error: "Only the account owner can manage the subscription." }, 403);

    const { data: companyId } = await supabase.rpc("current_company_id");
    if (!companyId) return jsonResponse({ error: "No company for this user." }, 403);

    if (!isStripeConfigured()) {
      return jsonResponse({ error: "Web payments aren't switched on yet. Please contact help@harboursouth.us." }, 503);
    }

    const admin = createAdminClient();
    const { data: sub } = await admin
      .from("company_subscriptions")
      .select("stripe_customer_id,stripe_subscription_id,stripe_status")
      .eq("company_id", companyId)
      .maybeSingle();

    switch (request.action) {
      case "checkout": {
        const period: BillingPeriod = request.period === "annual" ? "annual" : "monthly";
        const { data: stateRows, error: stateError } = await supabase.rpc("company_commercial_state", { p_company: companyId });
        if (stateError) throw new Error(stateError.message);
        const state = (Array.isArray(stateRows) ? stateRows[0] : stateRows) as Commercial | null;

        if (state?.has_entitlement && state.billing_store === "apple") {
          return jsonResponse({
            error: "Your company's plan is billed through the App Store. Change or cancel it on the iPhone of the person who subscribed.",
          }, 409);
        }
        const liveStripe = sub?.stripe_subscription_id && ["active", "trialing", "past_due"].includes(sub.stripe_status ?? "");
        if ((state?.has_entitlement && state.billing_store === "stripe") || liveStripe) {
          return jsonResponse({ error: "Your company already has a web subscription. Use Manage billing to change it." }, 409);
        }

        const { catalog, tiers } = await ensureCatalog(admin);
        const tier = tiers.find((t) => t.id === request.tierId);
        if (!tier || !catalog.prices[tier.id]) return jsonResponse({ error: "That plan isn't available." }, 400);
        if (tier.user_limit !== null && (state?.active_users ?? 0) > tier.user_limit) {
          return jsonResponse({
            error: `${tier.display_name} covers up to ${tier.user_limit} active ${tier.user_limit === 1 ? "user" : "users"} and your company has ${state?.active_users}. Choose a bigger plan.`,
          }, 400);
        }

        const customer = sub?.stripe_customer_id ?? (await createCustomer(admin, supabase, companyId, userId));
        const metadata = { company_id: companyId, tier_id: tier.id, billing_period: period, kind: "web_subscription" };

        const session = await stripeRequest<{ id: string; url: string }>("/checkout/sessions", {
          mode: "subscription",
          customer,
          client_reference_id: companyId,
          line_items: [{ price: catalog.prices[tier.id][period], quantity: 1 }],
          billing_address_collection: "auto",
          success_url: `${WEB_APP_URL}/billing?checkout=success&session_id={CHECKOUT_SESSION_ID}`,
          cancel_url: `${WEB_APP_URL}/billing?checkout=cancelled`,
          metadata,
          subscription_data: { metadata, description: `Harbour South FieldOps ${tier.display_name}` },
        });
        return jsonResponse({ url: session.url });
      }

      case "portal": {
        if (!sub?.stripe_customer_id) {
          return jsonResponse({ error: "There's no web subscription to manage yet." }, 400);
        }
        const { catalog } = await ensureCatalog(admin);
        const portal = await stripeRequest<{ url: string }>("/billing_portal/sessions", {
          customer: sub.stripe_customer_id,
          configuration: catalog.portal,
          return_url: `${WEB_APP_URL}/billing?portal=return`,
        });
        return jsonResponse({ url: portal.url });
      }

      case "confirm": {
        const sessionId = String(request.sessionId ?? "");
        if (!/^cs_[A-Za-z0-9_]+$/.test(sessionId)) return jsonResponse({ error: "Unknown checkout." }, 400);
        const session = await stripeRequest<{ subscription?: string | null; metadata?: Record<string, string>; status?: string }>(
          `/checkout/sessions/${sessionId}`,
          {},
          { method: "GET" },
        );
        // Only the caller's own company's checkout can be confirmed.
        if (session.metadata?.company_id !== companyId) return jsonResponse({ error: "Unknown checkout." }, 404);
        if (!session.subscription) return jsonResponse({ outcome: `checkout:${session.status ?? "open"}` });
        const result = await syncStripeSubscription(admin, String(session.subscription), companyId);
        return jsonResponse({ outcome: result.outcome });
      }

      case "refresh": {
        if (!sub?.stripe_subscription_id) return jsonResponse({ outcome: "none" });
        const result = await syncStripeSubscription(admin, sub.stripe_subscription_id, companyId);
        return jsonResponse({ outcome: result.outcome });
      }

      default:
        return jsonResponse({ error: "Unknown action." }, 400);
    }
  } catch (err) {
    if (err instanceof AuthError) return jsonResponse({ error: "Unauthorized" }, 401);
    if (err instanceof StripeError) {
      console.error("[web-billing] stripe", err.statusCode, err.code, err.message);
      return jsonResponse({ error: "Stripe couldn't complete that just now. Please try again in a moment." }, 502);
    }
    console.error("[web-billing] unexpected failure", err instanceof Error ? err.message : err);
    return jsonResponse({ error: "Something went wrong. Please try again." }, 500);
  }
});

// deno-lint-ignore no-explicit-any
async function createCustomer(admin: any, supabase: any, companyId: string, userId: string): Promise<string> {
  const [{ data: company }, { data: me }] = await Promise.all([
    supabase.from("companies").select("name").eq("id", companyId).maybeSingle(),
    supabase.from("app_users").select("email,name").eq("id", userId).maybeSingle(),
  ]);
  const customer = await stripeRequest<{ id: string }>("/customers", {
    name: company?.name ?? undefined,
    email: me?.email || undefined,
    metadata: { company_id: companyId, kind: "web_subscription" },
  }, { idempotencyKey: `hs-customer-${companyId}` });

  const { error } = await admin
    .from("company_subscriptions")
    .update({ stripe_customer_id: customer.id, updated_at: new Date().toISOString() })
    .eq("company_id", companyId);
  if (error) throw new Error(`could not link the Stripe customer: ${error.message}`);
  return customer.id;
}
