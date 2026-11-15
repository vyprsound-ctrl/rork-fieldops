import { useEffect, useRef, useState } from "react";
import { useSearchParams } from "react-router-dom";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Apple, Check, CreditCard, ExternalLink, Loader2, ShieldCheck } from "lucide-react";
import { toast } from "sonner";

import { Page } from "@/components/hs/AppShell";
import { LoadingRows, PageHeader } from "@/components/hs/primitives";
import { ToneBadge } from "@/components/hs/crm";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import {
  STATE_LABEL,
  commercialState,
  confirmCheckout,
  openPortal,
  planTiers,
  refreshSubscription,
  startCheckout,
  usd,
  type CommercialState,
  type PlanTier,
} from "@/lib/billing";
import { useSession } from "@/lib/session";

type Period = "monthly" | "annual";

const longDate = (iso: string | null) =>
  iso ? new Date(iso).toLocaleDateString("en-US", { month: "long", day: "numeric", year: "numeric" }) : null;

export default function Billing() {
  const { reload } = useSession();
  const qc = useQueryClient();
  const [params, setParams] = useSearchParams();
  const [period, setPeriod] = useState<Period>("monthly");
  const [busy, setBusy] = useState<string | null>(null);
  const handled = useRef(false);

  const state = useQuery({ queryKey: ["billing", "state"], queryFn: commercialState });
  const tiers = useQuery({ queryKey: ["billing", "tiers"], queryFn: planTiers, staleTime: 5 * 60_000 });

  const refreshAll = async () => {
    await qc.invalidateQueries({ queryKey: ["billing"] });
    reload();
  };

  // Coming back from Stripe Checkout or the billing portal.
  useEffect(() => {
    if (handled.current) return;
    const checkout = params.get("checkout");
    const sessionId = params.get("session_id");
    const portal = params.get("portal");
    if (!checkout && !portal) return;
    handled.current = true;
    setParams({}, { replace: true });

    if (checkout === "cancelled") {
      toast("Checkout cancelled. You haven't been charged.");
      return;
    }
    setBusy("returning");
    const work = checkout === "success" && sessionId ? confirmCheckout(sessionId) : refreshSubscription();
    work
      .then((r) => {
        if (checkout === "success") {
          if (r.outcome.startsWith("applied")) toast.success("You're subscribed. Your whole team is unlocked.");
          else toast("Payment received. Your plan will appear here in a moment.");
        }
      })
      .catch((err: Error) => toast.error(err.message))
      .finally(() => {
        setBusy(null);
        void refreshAll();
      });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const subscribe = async (tier: PlanTier) => {
    setBusy(tier.id);
    try {
      const { url } = await startCheckout(tier.id, period);
      window.location.href = url;
    } catch (err) {
      toast.error((err as Error).message);
      setBusy(null);
    }
  };

  const manage = async () => {
    setBusy("portal");
    try {
      const { url } = await openPortal();
      window.location.href = url;
    } catch (err) {
      toast.error((err as Error).message);
      setBusy(null);
    }
  };

  const s = state.data;
  const store = s?.billing_store ?? "none";
  const onApple = store === "apple" && !!s?.has_entitlement;
  const onStripe = store === "stripe" && s?.entitlement_state !== "expired" && s?.entitlement_state !== "none";

  return (
    <Page className="max-w-[1100px]">
      <PageHeader title="Billing" subtitle="Your company's Harbour South plan. One plan covers the web and the iPhone app." />

      {state.isLoading || !s ? (
        state.error ? (
          <p className="card-surface px-5 py-4 text-sm text-destructive">{(state.error as Error).message}</p>
        ) : (
          <LoadingRows count={3} />
        )
      ) : (
        <>
          <CurrentPlan state={s} busy={busy} onManage={manage} showManage={onStripe} />

          {onApple ? (
            <div className="card-surface mt-6 flex items-start gap-4 px-6 py-5">
              <span className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-muted">
                <Apple className="h-5 w-5" />
              </span>
              <div className="text-sm">
                <p className="font-semibold">Billed through the App Store</p>
                <p className="mt-1 text-muted-foreground">
                  Change or cancel this plan on the iPhone of the person who subscribed: Settings → your name → Subscriptions.
                </p>
              </div>
            </div>
          ) : (
            !onStripe && (
              <PlanPicker
                tiers={tiers.data ?? []}
                loading={tiers.isLoading}
                period={period}
                onPeriod={setPeriod}
                activeUsers={s.active_users}
                busy={busy}
                onSubscribe={subscribe}
              />
            )
          )}
        </>
      )}
    </Page>
  );
}

function CurrentPlan({
  state,
  busy,
  onManage,
  showManage,
}: {
  state: CommercialState;
  busy: string | null;
  onManage: () => void;
  showManage: boolean;
}) {
  const label = STATE_LABEL[state.entitlement_state] ?? STATE_LABEL.none;
  const ends = longDate(state.period_ends_at);
  const hasPlan = state.entitlement_state !== "none" && !!state.tier_id;
  const renewal =
    !ends || !hasPlan
      ? null
      : state.entitlement_state === "cancelling" || state.will_auto_renew === false
        ? `Ends ${ends}`
        : state.entitlement_state === "expired"
          ? `Ended ${ends}`
          : `Renews ${ends}`;
  const where = state.billing_store === "apple" ? "App Store" : state.billing_store === "stripe" ? "Card, billed on the web" : null;

  return (
    <section className="card-surface relative overflow-hidden">
      <div className="pointer-events-none absolute -right-20 -top-24 h-64 w-64 rounded-full border-[26px] border-brand-orange/10" />
      <div className="relative flex flex-wrap items-center gap-6 px-6 py-6">
        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-2">
            <p className="section-label">Current plan</p>
            <ToneBadge tone={label.tone}>{label.text}</ToneBadge>
          </div>
          <p className="mt-2 text-[28px] font-bold tracking-tight">
            {hasPlan ? state.tier_name : "No active plan"}
            {hasPlan && state.plan_price_cents != null && (
              <span className="ml-2 text-base font-medium text-muted-foreground">
                {usd(state.plan_price_cents)} / {state.billing_period === "annual" ? "year" : "month"}
              </span>
            )}
          </p>
          <p className="mt-1 text-sm text-muted-foreground">
            {[
              renewal,
              where,
              `${state.active_users} active ${state.active_users === 1 ? "user" : "users"}${
                state.plan_user_limit ? ` of ${state.plan_user_limit}` : ""
              }`,
            ]
              .filter(Boolean)
              .join(" · ")}
          </p>
          {(state.entitlement_state === "gracePeriod" || state.entitlement_state === "billingRetry") && (
            <p className="mt-3 rounded-xl bg-brand-orange-tint px-3 py-2 text-sm text-brand-orange-text">
              Your last payment didn't go through. Update your card to keep your team working.
            </p>
          )}
        </div>
        {showManage && (
          <Button onClick={onManage} disabled={busy === "portal"} className="press h-11 gap-2 bg-primary">
            {busy === "portal" ? <Loader2 className="h-4 w-4 animate-spin" /> : <CreditCard className="h-4 w-4" />}
            Manage billing
            <ExternalLink className="h-3.5 w-3.5 opacity-70" />
          </Button>
        )}
        {busy === "returning" && (
          <p className="flex items-center gap-2 text-sm text-muted-foreground">
            <Loader2 className="h-4 w-4 animate-spin" /> Updating your plan…
          </p>
        )}
      </div>
    </section>
  );
}

function PlanPicker({
  tiers,
  loading,
  period,
  onPeriod,
  activeUsers,
  busy,
  onSubscribe,
}: {
  tiers: PlanTier[];
  loading: boolean;
  period: Period;
  onPeriod: (p: Period) => void;
  activeUsers: number;
  busy: string | null;
  onSubscribe: (t: PlanTier) => void;
}) {
  const popular = "team";
  return (
    <section className="mt-10">
      <div className="mb-5 flex flex-wrap items-end justify-between gap-4">
        <div>
          <h2 className="text-xl font-bold tracking-tight">Choose a plan</h2>
          <p className="mt-1 text-sm text-muted-foreground">Prices in US dollars. Cancel any time from Manage billing.</p>
        </div>
        <div className="flex rounded-xl bg-muted p-1 text-sm font-semibold">
          {(["monthly", "annual"] as const).map((p) => (
            <button
              key={p}
              onClick={() => onPeriod(p)}
              className={cn(
                "rounded-lg px-4 py-1.5 transition-colors",
                period === p ? "bg-card text-foreground shadow-sm" : "text-muted-foreground hover:text-foreground",
              )}
            >
              {p === "monthly" ? "Monthly" : "Annual"}
              {p === "annual" && <span className="ml-1.5 text-xs text-success">Save 20%</span>}
            </button>
          ))}
        </div>
      </div>

      {loading ? (
        <LoadingRows count={3} />
      ) : (
        <div className="grid gap-4 md:grid-cols-3">
          {tiers.map((t) => {
            const tooSmall = t.user_limit != null && t.user_limit < activeUsers;
            const price = period === "annual" ? t.annual_cents : t.base_cents;
            const featured = t.id === popular;
            return (
              <div
                key={t.id}
                className={cn(
                  "card-surface relative flex flex-col px-6 py-6 transition-shadow hover:shadow-lift",
                  featured && "ring-2 ring-primary",
                )}
              >
                {featured && (
                  <span className="absolute -top-3 left-6 rounded-full bg-primary px-3 py-0.5 text-xs font-semibold text-primary-foreground">
                    Most popular
                  </span>
                )}
                <p className="text-lg font-bold">{t.display_name}</p>
                {t.tagline && <p className="mt-0.5 text-sm text-muted-foreground">{t.tagline}</p>}
                <p className="mt-5 text-4xl font-bold tabular-nums tracking-tight">
                  {usd(price)}
                  <span className="ml-1 text-base font-medium text-muted-foreground">/{period === "annual" ? "yr" : "mo"}</span>
                </p>
                {period === "annual" && (
                  <p className="mt-1 text-xs text-muted-foreground">{usd(Math.round(t.annual_cents / 12))} a month, billed yearly</p>
                )}
                <ul className="mt-5 flex-1 space-y-2 text-sm">
                  <li className="flex gap-2">
                    <Check className="mt-0.5 h-4 w-4 shrink-0 text-success" />
                    {t.user_limit == null
                      ? `${t.included_users ?? 10}+ users`
                      : t.user_limit === 1
                        ? "1 user"
                        : `Up to ${t.user_limit} users`}
                  </li>
                  <li className="flex gap-2">
                    <Check className="mt-0.5 h-4 w-4 shrink-0 text-success" />
                    Web app and iPhone app
                  </li>
                  <li className="flex gap-2">
                    <Check className="mt-0.5 h-4 w-4 shrink-0 text-success" />
                    Jobs, quotes, invoices and dispatch
                  </li>
                </ul>
                <Button
                  onClick={() => onSubscribe(t)}
                  disabled={tooSmall || busy !== null}
                  className={cn(
                    "press mt-6 h-11 w-full font-semibold",
                    featured ? "bg-brand-orange hover:bg-brand-orange/90" : "",
                  )}
                  variant={featured ? "default" : "outline"}
                >
                  {busy === t.id ? <Loader2 className="h-4 w-4 animate-spin" /> : tooSmall ? `You have ${activeUsers} users` : "Subscribe"}
                </Button>
              </div>
            );
          })}
        </div>
      )}

      <p className="mt-6 flex items-center gap-2 text-xs text-muted-foreground">
        <ShieldCheck className="h-4 w-4" /> Secure card payment by Stripe. We never see your card number.
      </p>
    </section>
  );
}
