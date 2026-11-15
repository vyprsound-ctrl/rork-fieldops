import { supabase } from "./supabase";
import { AppError, rows, rpc } from "./api";

/** The company's plan, from the same server function the iPhone app reads. */
export interface CommercialState {
  has_entitlement: boolean;
  entitlement_state: string;
  tier_id: string | null;
  tier_name: string;
  billing_period: "monthly" | "annual" | null;
  plan_price_cents: number | null;
  plan_user_limit: number | null;
  plan_included_users: number | null;
  active_users: number;
  period_ends_at: string | null;
  will_auto_renew: boolean | null;
  grace_period_ends_at: string | null;
  billing_store: "apple" | "stripe" | "google" | "none";
  is_free_offer: boolean;
}

export interface PlanTier {
  id: string;
  display_name: string;
  base_cents: number;
  annual_cents: number;
  user_limit: number | null;
  included_users: number | null;
  tagline: string | null;
  sort_order: number;
}

export async function commercialState(): Promise<CommercialState | null> {
  const data = await rpc<CommercialState[]>("company_commercial_state", { p_company: null });
  return data?.[0] ?? null;
}

export async function planTiers(): Promise<PlanTier[]> {
  return rows<PlanTier>(
    supabase
      .from("subscription_tiers")
      .select("id,display_name,base_cents,annual_cents,user_limit,included_users,tagline,sort_order")
      .eq("is_active", true)
      .order("sort_order"),
  );
}

async function billing<T>(body: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.functions.invoke("web-billing", { body });
  if (error) {
    // The function's own sentence, when it sent one.
    const context = (error as { context?: Response }).context;
    if (context && typeof context.json === "function") {
      const payload = (await context.json().catch(() => null)) as { error?: string } | null;
      if (payload?.error) throw new AppError(payload.error);
    }
    throw new AppError("Couldn't reach billing. Check your connection and try again.");
  }
  if ((data as { error?: string })?.error) throw new AppError((data as { error: string }).error);
  return data as T;
}

export const startCheckout = (tierId: string, period: "monthly" | "annual") =>
  billing<{ url: string }>({ action: "checkout", tierId, period });

export const openPortal = () => billing<{ url: string }>({ action: "portal" });

export const confirmCheckout = (sessionId: string) => billing<{ outcome: string }>({ action: "confirm", sessionId });

export const refreshSubscription = () => billing<{ outcome: string }>({ action: "refresh" });

export const STATE_LABEL: Record<string, { text: string; tone: "success" | "warning" | "danger" | "neutral" }> = {
  active: { text: "Active", tone: "success" },
  trial: { text: "Free trial", tone: "success" },
  offer: { text: "Offer", tone: "success" },
  cancelling: { text: "Ends at period end", tone: "warning" },
  gracePeriod: { text: "Payment problem", tone: "warning" },
  billingRetry: { text: "Payment failed", tone: "danger" },
  revoked: { text: "Refunded", tone: "danger" },
  expired: { text: "Expired", tone: "danger" },
  none: { text: "No plan", tone: "neutral" },
};

export const usd = (cents: number) =>
  new Intl.NumberFormat("en-US", { style: "currency", currency: "USD", minimumFractionDigits: 2 }).format(cents / 100);
