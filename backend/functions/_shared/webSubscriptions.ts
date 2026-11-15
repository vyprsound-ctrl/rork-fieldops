import { stripeRequest, stripeSecret } from "./stripe.ts";

/// Harbour South's own subscription, paid on the web. FLOW A only: every call
/// in this file is made on the PLATFORM account (no Stripe-Account header).
///
/// The plans and prices are the same rows the App Store uses
/// (`subscription_tiers`). Stripe products and prices are created from them on
/// first use, so a price change in the table produces a new Stripe price
/// automatically; existing subscribers keep the price they signed up at until
/// they change plan, exactly like Stripe's normal behaviour.

export const WEB_APP_URL = (Deno.env.get("WEB_APP_URL") ?? "https://harboursouth.us/app").replace(/\/$/, "");
const SITE_URL = WEB_APP_URL.replace(/\/app$/, "");

export type BillingPeriod = "monthly" | "annual";

export interface Tier {
  id: string;
  display_name: string;
  base_cents: number;
  annual_cents: number;
  user_limit: number | null;
  included_users: number | null;
}

export interface Catalog {
  signature: string;
  prices: Record<string, { monthly: string; annual: string; product: string }>;
  portal: string;
}

interface StripeList<T> {
  data: T[];
}

// deno-lint-ignore no-explicit-any
type Admin = any;

const CATALOG_KEY = "stripe_web_catalog";

function stripeMode(): "live" | "test" {
  return /^(sk|rk)_live_/.test(stripeSecret()) ? "live" : "test";
}

export async function loadTiers(admin: Admin): Promise<Tier[]> {
  const { data, error } = await admin
    .from("subscription_tiers")
    .select("id,display_name,base_cents,annual_cents,user_limit,included_users,sort_order")
    .eq("is_active", true)
    .order("sort_order");
  if (error) throw new Error(`Could not read plans: ${error.message}`);
  return (data ?? []) as Tier[];
}

async function ensureProduct(tier: Tier): Promise<string> {
  const id = `hs_plan_${tier.id}`;
  try {
    const existing = await stripeRequest<{ id: string; name: string }>(`/products/${id}`, {}, { method: "GET" });
    return existing.id;
  } catch (err) {
    if ((err as { statusCode?: number }).statusCode !== 404) throw err;
  }
  const created = await stripeRequest<{ id: string }>("/products", {
    id,
    name: `Harbour South FieldOps ${tier.display_name}`,
    metadata: { tier_id: tier.id },
  }, { idempotencyKey: `hs-product-${id}` });
  return created.id;
}

async function ensurePrice(product: string, tier: Tier, period: BillingPeriod): Promise<string> {
  const cents = period === "annual" ? tier.annual_cents : tier.base_cents;
  const lookupKey = `hs_${tier.id}_${period}_${cents}`;
  const found = await stripeRequest<StripeList<{ id: string; active: boolean }>>(
    "/prices",
    { lookup_keys: [lookupKey], active: true, limit: 1 },
    { method: "GET" },
  );
  if (found.data[0]) return found.data[0].id;

  const price = await stripeRequest<{ id: string }>("/prices", {
    product,
    currency: "usd",
    unit_amount: cents,
    recurring: { interval: period === "annual" ? "year" : "month" },
    lookup_key: lookupKey,
    nickname: `${tier.display_name} ${period === "annual" ? "annual" : "monthly"}`,
    metadata: { tier_id: tier.id, billing_period: period },
  }, { idempotencyKey: `hs-price-${lookupKey}` });
  return price.id;
}

/// The Stripe prices for every active plan and the Customer Portal
/// configuration that lets an owner switch between them. Built once and
/// cached in platform_settings (service role only); rebuilt when a plan's
/// price changes or the Stripe key switches between test and live.
export async function ensureCatalog(admin: Admin): Promise<{ catalog: Catalog; tiers: Tier[] }> {
  const tiers = await loadTiers(admin);
  const signature = `v1:${stripeMode()}:` + tiers.map((t) => `${t.id}=${t.base_cents}/${t.annual_cents}`).join(",");

  const { data: cached } = await admin.from("platform_settings").select("value").eq("key", CATALOG_KEY).maybeSingle();
  const existing = cached?.value as Catalog | undefined;
  if (existing?.signature === signature && existing.portal) return { catalog: existing, tiers };

  const prices: Catalog["prices"] = {};
  for (const tier of tiers) {
    const product = await ensureProduct(tier);
    prices[tier.id] = {
      product,
      monthly: await ensurePrice(product, tier, "monthly"),
      annual: await ensurePrice(product, tier, "annual"),
    };
  }

  const portal = await stripeRequest<{ id: string }>("/billing_portal/configurations", {
    business_profile: {
      headline: "Harbour South FieldOps — manage your plan",
      privacy_policy_url: `${SITE_URL}/privacy-policy`,
      terms_of_service_url: `${SITE_URL}/terms-of-service`,
    },
    default_return_url: `${WEB_APP_URL}/billing?portal=return`,
    features: {
      customer_update: { enabled: true, allowed_updates: ["email", "name", "address", "tax_id"] },
      invoice_history: { enabled: true },
      payment_method_update: { enabled: true },
      subscription_cancel: { enabled: true, mode: "at_period_end" },
      subscription_update: {
        enabled: true,
        default_allowed_updates: ["price"],
        proration_behavior: "create_prorations",
        products: tiers.map((t) => ({ product: prices[t.id].product, prices: [prices[t.id].monthly, prices[t.id].annual] })),
      },
    },
  });

  const catalog: Catalog = { signature, prices, portal: portal.id };
  const { error } = await admin.from("platform_settings").upsert({
    key: CATALOG_KEY,
    value: catalog,
    description: "Stripe prices and Customer Portal for web subscriptions. Rebuilt automatically; safe to delete.",
    updated_at: new Date().toISOString(),
  });
  if (error) console.error("[web-billing] could not cache the catalog", error.message);
  return { catalog, tiers };
}

interface StripeSubscription {
  id: string;
  status: string;
  customer: string;
  cancel_at_period_end?: boolean;
  cancel_at?: number | null;
  current_period_start?: number;
  current_period_end?: number;
  metadata?: Record<string, string>;
  items?: {
    data: Array<{
      current_period_start?: number;
      current_period_end?: number;
      price?: { id: string; metadata?: Record<string, string>; recurring?: { interval?: string } };
    }>;
  };
}

const iso = (seconds?: number | null) => (seconds ? new Date(seconds * 1000).toISOString() : null);

/// Reads the subscription fresh from Stripe (so event order and the account's
/// API version never matter) and applies it through the database's single
/// writer, apply_stripe_subscription(). The company comes from metadata our
/// own code wrote at checkout, or from the customer we linked to it.
export async function syncStripeSubscription(
  admin: Admin,
  subscriptionId: string,
  hintCompany: string | null = null,
): Promise<{ outcome: string; companyId: string | null }> {
  const sub = await stripeRequest<StripeSubscription>(`/subscriptions/${subscriptionId}`, {}, { method: "GET" });

  let companyId: string | null = sub.metadata?.company_id ?? null;
  if (!companyId && sub.customer) {
    const { data } = await admin
      .from("company_subscriptions")
      .select("company_id")
      .eq("stripe_customer_id", sub.customer)
      .maybeSingle();
    companyId = data?.company_id ?? null;
  }
  companyId = companyId ?? hintCompany;
  if (!companyId) return { outcome: "unknownCompany", companyId: null };

  const item = sub.items?.data?.[0];
  const price = item?.price;
  const tierId = price?.metadata?.tier_id ?? sub.metadata?.tier_id ?? null;
  const period = price?.metadata?.billing_period ??
    (price?.recurring?.interval === "year" ? "annual" : price?.recurring?.interval === "month" ? "monthly" : null) ??
    sub.metadata?.billing_period ?? null;

  const { data, error } = await admin.rpc("apply_stripe_subscription", {
    p_company: companyId,
    p_customer: sub.customer ?? null,
    p_subscription: sub.id,
    p_price: price?.id ?? null,
    p_status: sub.status,
    p_period_start: iso(sub.current_period_start ?? item?.current_period_start),
    p_period_end: iso(sub.current_period_end ?? item?.current_period_end),
    p_cancel_at_end: Boolean(sub.cancel_at_period_end) || Boolean(sub.cancel_at),
    p_tier: tierId,
    p_period: period,
  });
  if (error) throw new Error(`apply_stripe_subscription: ${error.message}`);
  return { outcome: `subscription:${String(data)}`, companyId };
}
