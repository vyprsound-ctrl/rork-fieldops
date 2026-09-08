import { corsHeaders, createAdminClient, jsonResponse } from "../_shared/auth.ts";
import { verifyStripeSignature } from "../_shared/stripe.ts";

/// The authoritative source of payment truth.
///
/// NOTHING ELSE MARKS AN INVOICE PAID. The iOS app can report that a payment
/// sheet closed successfully; that is a UI event, not money. Only a
/// signature-verified event from Stripe, processed here, moves an invoice to
/// paid or part-paid.
///
/// SECURITY MODEL
///   1. Signature first. The body is verified against STRIPE_WEBHOOK_SECRET (or
///      STRIPE_CONNECT_WEBHOOK_SECRET for connected-account events) before it is
///      parsed. An unsigned or stale payload never reaches any logic.
///   2. Company is resolved from the connected account id or from metadata
///      written by our own code at creation time — never from a company_id in
///      the event body.
///   3. Idempotency is a primary key. The event id is inserted into
///      `stripe_events` before the work is done; a duplicate delivery loses the
///      insert and returns 200 without repeating anything.
///
/// FLOW SEPARATION
///   Events carrying an `account` field belong to FLOW B (a customer paying the
///   trade business). Events without one belong to FLOW A (the trade business
///   paying Harbour South). They are dispatched separately and can never be
///   confused for one another.

interface StripeEvent {
  id: string;
  type: string;
  livemode?: boolean;
  account?: string;
  data: { object: Record<string, unknown> };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);

  const payload = await req.text();
  const signature = req.headers.get("Stripe-Signature");

  const platformSecret = Deno.env.get("STRIPE_WEBHOOK_SECRET");
  const connectSecret = Deno.env.get("STRIPE_CONNECT_WEBHOOK_SECRET") ?? platformSecret;

  if (!platformSecret && !connectSecret) {
    console.error("[stripe-webhook] no webhook secret configured — refusing every event");
    return jsonResponse({ error: "Webhook not configured" }, 500);
  }

  // --- 1. Verify before parsing ------------------------------------------
  let verified = false;
  for (const secret of [platformSecret, connectSecret]) {
    if (!secret) continue;
    if (await verifyStripeSignature(payload, signature, secret)) {
      verified = true;
      break;
    }
  }

  if (!verified) {
    console.warn("[stripe-webhook] rejected an event with an invalid signature");
    return jsonResponse({ error: "Invalid signature" }, 400);
  }

  let event: StripeEvent;
  try {
    event = JSON.parse(payload) as StripeEvent;
  } catch {
    return jsonResponse({ error: "Malformed payload" }, 400);
  }

  const admin = createAdminClient();

  // --- 2. Idempotency, arbitrated by the primary key ----------------------
  //
  // Claim the event id first. If the insert fails on a duplicate key this
  // delivery is a repeat and there is nothing to do — return 200 so Stripe
  // stops retrying.
  const { error: claimError } = await admin.from("stripe_events").insert({
    id: event.id,
    type: event.type,
    account_id: event.account ?? null,
    livemode: event.livemode ?? false,
  });

  if (claimError) {
    if (claimError.code === "23505") {
      return jsonResponse({ received: true, duplicate: true });
    }
    console.error("[stripe-webhook] could not claim the event", claimError.message);
    // 500 makes Stripe retry, which is correct: we have not processed it.
    return jsonResponse({ error: "Could not record the event" }, 500);
  }

  let outcome = "ignored";
  let companyId: string | null = null;
  let errorDetail: string | null = null;

  try {
    const object = event.data.object;

    // --- 3. Resolve the company, server-side only -------------------------
    if (event.account) {
      // FLOW B. The connected account IS the tenant key.
      const { data } = await admin
        .from("stripe_connect_accounts")
        .select("company_id")
        .eq("stripe_account_id", event.account)
        .maybeSingle();
      companyId = data?.company_id ?? null;
    } else {
      // FLOW A, or a platform-side object for FLOW B (checkout sessions for SMS
      // credits are created on the platform). Metadata here was written by our
      // own functions, never by a client.
      const metadata = (object.metadata ?? {}) as Record<string, string>;
      companyId = metadata.company_id ?? null;

      if (!companyId && typeof object.customer === "string") {
        const { data } = await admin
          .from("company_subscriptions")
          .select("company_id")
          .eq("stripe_customer_id", object.customer)
          .maybeSingle();
        companyId = data?.company_id ?? null;
      }
    }

    switch (event.type) {
      // ---------- FLOW B: a customer paid the trade business --------------
      case "payment_intent.succeeded":
        outcome = await handlePaymentSucceeded(admin, object, event.account ?? null, companyId);
        break;

      case "payment_intent.payment_failed":
        outcome = await handlePaymentFailed(admin, object, "failed");
        break;

      case "payment_intent.canceled":
        outcome = await handlePaymentFailed(admin, object, "cancelled");
        break;

      case "account.updated":
        outcome = await handleAccountUpdated(admin, object);
        break;

      // ---------- SMS credit purchase (platform-side) ---------------------
      case "checkout.session.completed":
        outcome = await handleCheckoutCompleted(admin, object);
        break;

      // ---------- FLOW A: Harbour South's own subscription ----------------
      case "customer.subscription.created":
      case "customer.subscription.updated":
      case "customer.subscription.deleted":
        outcome = await handleSubscriptionChanged(admin, object, event.type, companyId);
        break;

      case "invoice.payment_failed":
        outcome = await handleSubscriptionPaymentFailed(admin, object, companyId);
        break;

      case "invoice.payment_succeeded":
        outcome = await handleSubscriptionPaymentSucceeded(admin, object, companyId);
        break;

      default:
        outcome = "unhandled";
    }
  } catch (err) {
    errorDetail = err instanceof Error ? err.message : String(err);
    outcome = "error";
    console.error(`[stripe-webhook] ${event.type} failed`, errorDetail);
  }

  await admin.from("stripe_events").update({
    company_id: companyId,
    processed_at: new Date().toISOString(),
    outcome,
    error_detail: errorDetail,
  }).eq("id", event.id);

  // A handler failure still returns 200 once recorded: the event is stored with
  // its error for replay, and letting Stripe hammer a deterministic failure
  // helps nobody.
  return jsonResponse({ received: true, outcome });
});

// ---------------------------------------------------------------------------
// FLOW B handlers
// ---------------------------------------------------------------------------

// deno-lint-ignore no-explicit-any
async function handlePaymentSucceeded(
  admin: any,
  intent: Record<string, unknown>,
  account: string | null,
  companyId: string | null,
): Promise<string> {
  const intentId = String(intent.id);

  // The invoice is taken from OUR record of the intent, not from the event's
  // metadata: the payment_intents row was written by this backend when the
  // intent was created, so it cannot have been influenced by a client.
  const { data: record } = await admin
    .from("payment_intents")
    .select("id,company_id,invoice_id,amount_cents,currency_code,application_fee_cents,stripe_account_id")
    .eq("stripe_payment_intent_id", intentId)
    .maybeSingle();

  if (!record) return "unknownIntent";
  if (companyId && record.company_id !== companyId) return "companyMismatch";

  const charges = (intent.charges ?? {}) as { data?: Array<Record<string, unknown>> };
  const charge = charges.data?.[0];
  const amountReceived = Number(intent.amount_received ?? intent.amount ?? record.amount_cents);
  const applicationFee = Number(intent.application_fee_amount ?? record.application_fee_cents ?? 0);

  // Stripe's own processing fee, which is a DIFFERENT number from Harbour
  // South's application fee and is only known once the balance transaction has
  // settled. Absent is recorded as null, never as zero.
  let processingFee: number | null = null;
  const balanceTransaction = charge?.balance_transaction;
  if (balanceTransaction && typeof balanceTransaction === "object") {
    processingFee = Number((balanceTransaction as { fee?: number }).fee ?? 0);
  }

  const net = processingFee === null
    ? amountReceived - applicationFee
    : amountReceived - applicationFee - processingFee;

  // record_payment re-derives the invoice balance and status inside one
  // transaction, so a payment without a re-derived balance is not expressible.
  const { error: paymentError } = await admin.rpc("record_payment_from_stripe", {
    p_invoice: record.invoice_id,
    p_company: record.company_id,
    p_amount_cents: amountReceived,
    p_intent: intentId,
    p_charge: charge?.id ? String(charge.id) : null,
    p_account: account ?? record.stripe_account_id,
    p_application_fee_cents: applicationFee,
    p_processing_fee_cents: processingFee,
    p_net_cents: net,
    p_currency: String(intent.currency ?? record.currency_code ?? "usd"),
  });

  if (paymentError) {
    // Fall back to a direct insert guarded by the unique index on the intent id,
    // so a missing helper function cannot lose a real payment.
    const { error: insertError } = await admin.from("payments").insert({
      company_id: record.company_id,
      invoice_id: record.invoice_id,
      amount: amountReceived / 100,
      method: "stripe",
      status: "succeeded",
      stripe_payment_intent_id: intentId,
      stripe_charge_id: charge?.id ? String(charge.id) : null,
      stripe_account_id: account ?? record.stripe_account_id,
      application_fee_cents: applicationFee,
      processing_fee_cents: processingFee,
      net_cents: net,
      currency_code: String(intent.currency ?? "usd"),
      paid_by_customer: true,
      is_simulated: false,
      received_at: new Date().toISOString(),
      recorded_by_user_id: null,
      reference: intentId,
    });

    if (insertError && insertError.code !== "23505") {
      throw new Error(`payment not recorded: ${paymentError.message} / ${insertError.message}`);
    }
    if (insertError?.code === "23505") return "alreadyRecorded";
  }

  await admin.from("payment_intents")
    .update({ status: "succeeded", updated_at: new Date().toISOString() })
    .eq("id", record.id);

  return "paymentRecorded";
}

// deno-lint-ignore no-explicit-any
async function handlePaymentFailed(
  admin: any,
  intent: Record<string, unknown>,
  status: "failed" | "cancelled",
): Promise<string> {
  const intentId = String(intent.id);
  const lastError = (intent.last_payment_error ?? {}) as { message?: string };

  // The invoice is deliberately left exactly as it was. A failed payment
  // changes nothing about what is owed.
  const { error } = await admin.from("payment_intents").update({
    status,
    updated_at: new Date().toISOString(),
  }).eq("stripe_payment_intent_id", intentId);

  if (error) throw new Error(error.message);
  return `payment${status === "failed" ? "Failed" : "Cancelled"}`;
}

// deno-lint-ignore no-explicit-any
async function handleAccountUpdated(admin: any, account: Record<string, unknown>): Promise<string> {
  const requirements = (account.requirements ?? {}) as { currently_due?: string[]; disabled_reason?: string | null };
  const { error } = await admin.from("stripe_connect_accounts").update({
    charges_enabled: Boolean(account.charges_enabled),
    payouts_enabled: Boolean(account.payouts_enabled),
    details_submitted: Boolean(account.details_submitted),
    requirements_due: requirements.currently_due ?? [],
    disabled_reason: requirements.disabled_reason ?? null,
    onboarded_at: account.charges_enabled ? new Date().toISOString() : null,
    last_synced_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
  }).eq("stripe_account_id", String(account.id));

  if (error) throw new Error(error.message);
  return "accountUpdated";
}

// ---------------------------------------------------------------------------
// SMS credit purchase
// ---------------------------------------------------------------------------

// deno-lint-ignore no-explicit-any
async function handleCheckoutCompleted(admin: any, session: Record<string, unknown>): Promise<string> {
  if (session.payment_status !== "paid") return "checkoutUnpaid";

  const { data: purchase } = await admin
    .from("sms_credit_purchases")
    .select("id,status")
    .eq("stripe_checkout_session_id", String(session.id))
    .maybeSingle();

  if (!purchase) return "unknownPurchase";

  // credit_sms_purchase is itself idempotent — an already-credited purchase
  // returns 'alreadyCredited' and writes no second ledger row.
  const { data, error } = await admin.rpc("credit_sms_purchase", { p_purchase: purchase.id });
  if (error) throw new Error(error.message);

  const result = Array.isArray(data) ? data[0] : data;
  return `sms:${result?.outcome ?? "unknown"}`;
}

// ---------------------------------------------------------------------------
// FLOW A handlers — Harbour South's subscription
// ---------------------------------------------------------------------------

// deno-lint-ignore no-explicit-any
async function handleSubscriptionChanged(
  admin: any,
  subscription: Record<string, unknown>,
  eventType: string,
  companyId: string | null,
): Promise<string> {
  if (!companyId) return "unknownCompany";

  const cancelled = eventType === "customer.subscription.deleted";
  const stripeStatus = String(subscription.status ?? "");

  // Stripe's vocabulary mapped onto ours. `incomplete_expired` and `unpaid`
  // both mean the company is not entitled, which is not the same as cancelled.
  const status = cancelled
    ? "cancelled"
    : stripeStatus === "trialing"
    ? "trialing"
    : stripeStatus === "active"
    ? "active"
    : stripeStatus === "past_due"
    ? "pastDue"
    : stripeStatus === "canceled"
    ? "cancelled"
    : "expired";

  const periodStart = subscription.current_period_start
    ? new Date(Number(subscription.current_period_start) * 1000).toISOString()
    : null;
  const periodEnd = subscription.current_period_end
    ? new Date(Number(subscription.current_period_end) * 1000).toISOString()
    : null;

  const update: Record<string, unknown> = {
    status,
    stripe_subscription_id: String(subscription.id),
    store: "none",
    updated_at: new Date().toISOString(),
  };
  if (periodStart) update.current_period_start = periodStart;
  if (periodEnd) {
    update.current_period_end = periodEnd;
    update.renewal_date = periodEnd;
  }
  if (cancelled || stripeStatus === "canceled") {
    update.cancelled_at = new Date().toISOString();
  }
  if (status === "active") {
    update.past_due_since = null;
    update.last_payment_failure = null;
  }

  const { error } = await admin.from("company_subscriptions").update(update).eq("company_id", companyId);
  if (error) throw new Error(error.message);

  // Re-derive the seat count and price from the roster, so the stored price is
  // never a stale copy of what Stripe last billed.
  await admin.rpc("sync_subscription_seats", { p_company: companyId });

  return `subscription:${status}`;
}

// deno-lint-ignore no-explicit-any
async function handleSubscriptionPaymentFailed(
  admin: any,
  invoice: Record<string, unknown>,
  companyId: string | null,
): Promise<string> {
  if (!companyId) return "unknownCompany";

  const { error } = await admin.from("company_subscriptions").update({
    status: "pastDue",
    past_due_since: new Date().toISOString(),
    last_payment_failure: String(
      (invoice.last_finalization_error as { message?: string } | undefined)?.message ??
        "The card on file was declined.",
    ),
    last_payment_failed_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
  }).eq("company_id", companyId);

  if (error) throw new Error(error.message);
  return "subscriptionPastDue";
}

// deno-lint-ignore no-explicit-any
async function handleSubscriptionPaymentSucceeded(
  admin: any,
  _invoice: Record<string, unknown>,
  companyId: string | null,
): Promise<string> {
  if (!companyId) return "unknownCompany";

  const { error } = await admin.from("company_subscriptions").update({
    status: "active",
    past_due_since: null,
    last_payment_failure: null,
    updated_at: new Date().toISOString(),
  }).eq("company_id", companyId);

  if (error) throw new Error(error.message);
  await admin.rpc("sync_subscription_seats", { p_company: companyId });
  return "subscriptionPaid";
}
