import { AuthError, corsHeaders, createAdminClient, jsonResponse, requireAuth } from "../_shared/auth.ts";
import { isStripeConfigured, StripeError, stripeRequest } from "../_shared/stripe.ts";

/// FLOW B onboarding — the trade business connects its OWN Stripe account.
///
/// Customer money belongs to the trade business. Harbour South never becomes
/// the merchant of record for a customer invoice; it takes a configurable
/// application fee on the payment and nothing more. This function creates and
/// inspects the connected account that makes that possible.
///
/// The company is NEVER taken from the request body. It is read from
/// `current_company_id()` using the caller's own JWT, so a user cannot onboard,
/// inspect or hijack another company's Stripe account by editing a payload.
///
/// Actions:
///   status   — current readiness, refreshed from Stripe
///   onboard  — an Account Link the owner completes in a browser
///   dashboard— an Express login link to the merchant's own Stripe dashboard

interface ConnectRequest {
  action?: "status" | "onboard" | "dashboard";
  refresh?: boolean;
}

interface StripeAccount {
  id: string;
  charges_enabled?: boolean;
  payouts_enabled?: boolean;
  details_submitted?: boolean;
  country?: string;
  default_currency?: string;
  requirements?: { currently_due?: string[]; disabled_reason?: string | null };
}

function returnBase(): string {
  return Deno.env.get("APP_RETURN_URL") ?? "https://harboursouth.us";
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const { supabase, userId } = await requireAuth(req);

    if (!isStripeConfigured()) {
      return jsonResponse({
        configured: false,
        detail: "Card payments are not enabled for this deployment yet.",
      }, 200);
    }

    const body = (await req.json().catch(() => ({}))) as ConnectRequest;
    const action = body.action ?? "status";

    // --- Tenancy and permission, both server-side -------------------------
    //
    // current_company_id() derives the company from the authenticated user
    // inside the database. Nothing the client sent is consulted.
    const { data: companyId, error: companyError } = await supabase.rpc("current_company_id");
    if (companyError || !companyId) {
      return jsonResponse({ error: "No company for this user." }, 403);
    }

    // Connecting a bank account is an owner-level act, so it is gated on the
    // company-profile permission rather than a payments-read one.
    const { data: canManage } = await supabase.rpc("has_perm", { p: "companyProfileManage" });
    const { data: canRead } = await supabase.rpc("has_perm", { p: "paymentsRead" });

    if (action !== "status" && canManage !== true) {
      return jsonResponse({ error: "You do not have permission to manage payment settings." }, 403);
    }
    if (action === "status" && canRead !== true && canManage !== true) {
      return jsonResponse({ error: "You do not have permission to view payment settings." }, 403);
    }

    const admin = createAdminClient();

    // Existing link, if any.
    const { data: existing } = await admin
      .from("stripe_connect_accounts")
      .select("*")
      .eq("company_id", companyId)
      .maybeSingle();

    // --- dashboard --------------------------------------------------------
    if (action === "dashboard") {
      if (!existing?.stripe_account_id) {
        return jsonResponse({ error: "This company has not connected Stripe yet." }, 409);
      }
      const link = await stripeRequest<{ url: string }>(
        `/accounts/${existing.stripe_account_id}/login_links`,
      );
      return jsonResponse({ configured: true, url: link.url });
    }

    // --- create the account on first onboard ------------------------------
    let accountId: string | undefined = existing?.stripe_account_id;

    if (!accountId && action === "onboard") {
      const { data: company } = await supabase
        .from("companies")
        .select("id,name,country_code,currency_code,phone")
        .eq("id", companyId)
        .maybeSingle();

      const created = await stripeRequest<StripeAccount>("/accounts", {
        type: "express",
        country: company?.country_code ?? "US",
        default_currency: (company?.currency_code ?? "usd").toLowerCase(),
        business_type: "company",
        company: { name: company?.name ?? "" },
        capabilities: {
          card_payments: { requested: true },
          transfers: { requested: true },
        },
        // Stamped so the webhook can resolve account -> company without
        // trusting anything a client ever sends.
        metadata: { company_id: companyId, connected_by_user_id: userId },
      }, {
        // Prevents a double-tap creating two Stripe accounts for one company.
        idempotencyKey: `connect-create-${companyId}`,
      });

      accountId = created.id;

      const { error: insertError } = await admin
        .from("stripe_connect_accounts")
        .upsert({
          company_id: companyId,
          stripe_account_id: created.id,
          charges_enabled: created.charges_enabled ?? false,
          payouts_enabled: created.payouts_enabled ?? false,
          details_submitted: created.details_submitted ?? false,
          country_code: created.country ?? "US",
          default_currency: created.default_currency ?? "usd",
          last_synced_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        }, { onConflict: "company_id" });

      if (insertError) {
        console.error("[stripe-connect] could not store the account link", insertError.message);
        return jsonResponse({ error: "The Stripe account was created but could not be linked. Contact support before retrying." }, 500);
      }
    }

    if (!accountId) {
      return jsonResponse({
        configured: true,
        connected: false,
        chargesEnabled: false,
        payoutsEnabled: false,
        detailsSubmitted: false,
        requirementsDue: [],
        detail: "No Stripe account is connected yet.",
      });
    }

    // --- refresh readiness from Stripe ------------------------------------
    //
    // Stripe is authoritative about whether this account may take a card. A
    // cached "yes" that has since become "no" would let the app offer a payment
    // that cannot succeed.
    let account: StripeAccount | null = null;
    try {
      account = await stripeRequest<StripeAccount>(`/accounts/${accountId}`, {}, { method: "GET" });
    } catch (err) {
      if (err instanceof StripeError) {
        console.error("[stripe-connect] account lookup failed", err.message);
      } else {
        throw err;
      }
    }

    if (account) {
      await admin.from("stripe_connect_accounts").upsert({
        company_id: companyId,
        stripe_account_id: account.id,
        charges_enabled: account.charges_enabled ?? false,
        payouts_enabled: account.payouts_enabled ?? false,
        details_submitted: account.details_submitted ?? false,
        requirements_due: account.requirements?.currently_due ?? [],
        disabled_reason: account.requirements?.disabled_reason ?? null,
        country_code: account.country ?? "US",
        default_currency: account.default_currency ?? "usd",
        onboarded_at: account.charges_enabled ? new Date().toISOString() : null,
        last_synced_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      }, { onConflict: "company_id" });
    }

    // --- onboard link -----------------------------------------------------
    if (action === "onboard") {
      const link = await stripeRequest<{ url: string; expires_at: number }>("/account_links", {
        account: accountId,
        type: "account_onboarding",
        refresh_url: `${returnBase()}/stripe/refresh`,
        return_url: `${returnBase()}/stripe/return`,
      });

      return jsonResponse({
        configured: true,
        connected: true,
        url: link.url,
        expiresAt: link.expires_at,
        chargesEnabled: account?.charges_enabled ?? false,
        payoutsEnabled: account?.payouts_enabled ?? false,
        detailsSubmitted: account?.details_submitted ?? false,
        requirementsDue: account?.requirements?.currently_due ?? [],
      });
    }

    return jsonResponse({
      configured: true,
      connected: true,
      accountId,
      chargesEnabled: account?.charges_enabled ?? existing?.charges_enabled ?? false,
      payoutsEnabled: account?.payouts_enabled ?? existing?.payouts_enabled ?? false,
      detailsSubmitted: account?.details_submitted ?? existing?.details_submitted ?? false,
      requirementsDue: account?.requirements?.currently_due ?? [],
      disabledReason: account?.requirements?.disabled_reason ?? null,
    });
  } catch (err) {
    if (err instanceof AuthError) return jsonResponse({ error: "Unauthorized" }, 401);
    if (err instanceof StripeError) return jsonResponse({ error: err.message }, 400);
    console.error("[stripe-connect] unexpected failure", err instanceof Error ? err.message : err);
    return jsonResponse({ error: "Internal server error" }, 500);
  }
});
