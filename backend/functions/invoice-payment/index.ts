import { corsHeaders, createAdminClient, jsonResponse } from "../_shared/auth.ts";
import {
  applicationFeeCents,
  isStripeConfigured,
  loadApplicationFeePolicy,
  StripeError,
  stripeRequest,
} from "../_shared/stripe.ts";

/// Starts a customer's payment of one invoice — FLOW B.
///
/// THE CALLER HERE IS THE CUSTOMER, NOT A LOGGED-IN USER. They arrive from the
/// invoice link with a share token and nothing else: no Supabase account, no
/// JWT, no company. The token is the only credential, and it is the thing that
/// resolves the invoice, the company and the connected account. Deployed with
/// --no-verify-jwt for that reason.
///
/// WHERE THE MONEY GOES: the PaymentIntent is created ON BEHALF OF the trade
/// business's connected account (`Stripe-Account: acct_...`), so the funds land
/// with the trade business. Harbour South takes only `application_fee_amount`,
/// read from `platform_settings` at request time — never a constant, and never
/// anything the client can influence.
///
/// WHAT THIS FUNCTION DOES NOT DO: mark anything paid. It records a pending
/// intent and returns a client secret. The invoice moves only when
/// `stripe-webhook` receives a signature-verified `payment_intent.succeeded`.

interface PaymentRequest {
  token?: string;
  action?: "quote" | "intent";
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const request = (await req.json().catch(() => ({}))) as PaymentRequest;
    const token = (request.token ?? "").trim();
    if (!token || token.length < 16) {
      return jsonResponse({ error: "This payment link is not valid." }, 400);
    }

    // The public invoice page has no authenticated caller at all, so the admin
    // client is the only way to resolve the token. The token IS the
    // authorisation, and it is random, revocable and scoped to one invoice.
    const admin = createAdminClient();

    const { data: share } = await admin
      .from("invoice_share_tokens")
      .select("invoice_id,revoked_at,expires_at")
      .eq("token", token)
      .maybeSingle();

    if (!share || share.revoked_at) {
      return jsonResponse({ error: "This payment link is no longer active." }, 404);
    }
    if (share.expires_at && new Date(share.expires_at) < new Date()) {
      return jsonResponse({ error: "This payment link has expired." }, 410);
    }

    const { data: invoice } = await admin
      .from("invoices")
      .select("id,company_id,number,total,amount_paid,balance,status,currency_code,due_date,payment_terms_label")
      .eq("id", share.invoice_id)
      .maybeSingle();

    if (!invoice) return jsonResponse({ error: "This invoice could not be found." }, 404);

    const balanceCents = Math.round(Number(invoice.balance) * 100);

    if (invoice.status === "void") {
      return jsonResponse({ error: "This invoice has been cancelled." }, 409);
    }
    if (invoice.status === "paid" || balanceCents <= 0) {
      return jsonResponse({
        payable: false,
        reason: "alreadyPaid",
        invoiceNumber: invoice.number,
        detail: "This invoice is already paid in full. Thank you.",
      });
    }

    // The company's connected account. No account, no card payment — and we say
    // so plainly rather than offering a button that cannot work.
    const { data: connect } = await admin
      .from("stripe_connect_accounts")
      .select("stripe_account_id,charges_enabled,default_currency")
      .eq("company_id", invoice.company_id)
      .maybeSingle();

    const { data: company } = await admin
      .from("companies")
      .select("name,online_payment_link_url,currency_code")
      .eq("id", invoice.company_id)
      .maybeSingle();

    const cardsAvailable = Boolean(isStripeConfigured() && connect?.charges_enabled);

    if (request.action !== "intent") {
      return jsonResponse({
        payable: true,
        invoiceNumber: invoice.number,
        companyName: company?.name ?? "",
        balanceCents,
        currency: (invoice.currency_code ?? "usd").toLowerCase(),
        dueDate: invoice.due_date,
        paymentTerms: invoice.payment_terms_label,
        cardsAvailable,
        // The manual link the contractor configured, which stays available as a
        // fallback when they have not connected Stripe.
        fallbackPaymentUrl: company?.online_payment_link_url ?? null,
      });
    }

    if (!cardsAvailable || !connect) {
      return jsonResponse({
        error: "This business is not set up to take card payments yet.",
        fallbackPaymentUrl: company?.online_payment_link_url ?? null,
      }, 503);
    }

    // Reuse a live intent for the same invoice and amount rather than creating
    // a second one, so a customer who reloads the page does not end up with two
    // open intents against one invoice.
    const { data: existing } = await admin
      .from("payment_intents")
      .select("id,stripe_payment_intent_id,amount_cents,status")
      .eq("invoice_id", invoice.id)
      .in("status", ["requires_payment_method", "requires_confirmation", "requires_action", "processing"])
      .eq("amount_cents", balanceCents)
      .maybeSingle();

    const policy = await loadApplicationFeePolicy(admin);
    const feeCents = applicationFeeCents(balanceCents, policy);
    const currency = (invoice.currency_code ?? connect.default_currency ?? "usd").toLowerCase();

    if (existing) {
      const refreshed = await stripeRequest<{ client_secret: string; status: string }>(
        `/payment_intents/${existing.stripe_payment_intent_id}`,
        {},
        { method: "GET", stripeAccount: connect.stripe_account_id },
      );

      if (refreshed.status !== "succeeded" && refreshed.status !== "canceled") {
        return jsonResponse({
          clientSecret: refreshed.client_secret,
          publishableKey: Deno.env.get("STRIPE_PUBLISHABLE_KEY") ?? null,
          stripeAccount: connect.stripe_account_id,
          amountCents: existing.amount_cents,
          currency,
          reused: true,
        });
      }
    }

    let intent: { id: string; client_secret: string; status: string };
    try {
      intent = await stripeRequest<{ id: string; client_secret: string; status: string }>(
        "/payment_intents",
        {
          amount: balanceCents,
          currency,
          // Harbour South's cut. NOT Stripe's processing fee, which the
          // connected account is charged separately and which appears on the
          // balance transaction.
          application_fee_amount: feeCents > 0 ? feeCents : undefined,
          automatic_payment_methods: { enabled: true },
          description: `Invoice ${invoice.number}`,
          statement_descriptor_suffix: (company?.name ?? "").slice(0, 22) || undefined,
          metadata: {
            invoice_id: invoice.id,
            company_id: invoice.company_id,
            invoice_number: invoice.number,
          },
        },
        {
          // ON BEHALF OF the trade business. This header is what keeps the money
          // out of Harbour South's balance.
          stripeAccount: connect.stripe_account_id,
          // One intent per invoice per amount, however many times the customer
          // taps pay or the network retries.
          idempotencyKey: `invoice-${invoice.id}-${balanceCents}`,
        },
      );
    } catch (err) {
      if (err instanceof StripeError) {
        console.error("[invoice-payment] intent creation failed", err.message);
        return jsonResponse({ error: "The payment could not be started. Please try again." }, 502);
      }
      throw err;
    }

    const { error: recordError } = await admin.from("payment_intents").upsert({
      company_id: invoice.company_id,
      invoice_id: invoice.id,
      stripe_payment_intent_id: intent.id,
      stripe_account_id: connect.stripe_account_id,
      amount_cents: balanceCents,
      currency_code: currency,
      application_fee_cents: feeCents,
      status: intent.status,
      client_secret_issued_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    }, { onConflict: "stripe_payment_intent_id" });

    if (recordError) {
      console.error("[invoice-payment] could not record the intent", recordError.message);
      // The intent exists at Stripe but we have no local record, so its webhook
      // would not resolve to an invoice. Refuse rather than take a payment we
      // cannot reconcile.
      return jsonResponse({ error: "The payment could not be started. Please try again." }, 500);
    }

    return jsonResponse({
      clientSecret: intent.client_secret,
      publishableKey: Deno.env.get("STRIPE_PUBLISHABLE_KEY") ?? null,
      stripeAccount: connect.stripe_account_id,
      amountCents: balanceCents,
      currency,
      reused: false,
    });
  } catch (err) {
    console.error("[invoice-payment] unexpected failure", err instanceof Error ? err.message : err);
    return jsonResponse({ error: "Internal server error" }, 500);
  }
});
