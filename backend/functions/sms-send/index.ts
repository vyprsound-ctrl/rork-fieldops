import { AuthError, corsHeaders, createAdminClient, jsonResponse, requireAuth } from "../_shared/auth.ts";
import {
  deliverReservation,
  firstRow,
  outcomeMessage,
  renderMessage,
  type Reservation,
  resolveRecipient,
  UUID_PATTERN,
} from "../_shared/sms.ts";

/// Sends (or schedules, or previews) one customer SMS on the company's credit,
/// from the company's OWN Twilio subaccount, Messaging Service and number.
///
/// ORDER OF OPERATIONS:
///   1. Authenticate. 2. Company from the session — the request has no company,
///   account, service, number or SID field to tamper with. 3. Customer, job,
///   quote and invoice read under the CALLER'S RLS and re-checked against that
///   company. 4. Template rendered server-side with server-looked-up values;
///   unknown or missing variables stop here. 5. ONE database transaction
///   (`reserve_sms_send`) checks permission, subscription, messaging status,
///   opt-out, segment count and balance under the company lock, then writes
///   the message and the ledger debit. 6. Only then Twilio, through that
///   company's subaccount. 7. The real outcome is recorded; a rejection
///   refunds exactly once.
///
/// action: "send" (default) · "schedule" · "preview" (renders + counts, charges nothing)

interface SendSmsRequest {
  action?: "send" | "schedule" | "preview";
  customerId?: string;
  jobId?: string;
  invoiceId?: string;
  quoteId?: string;
  template?: string;
  body?: string;
  phone?: string;
  eta?: string;
  scheduledFor?: string;
}

const LEGACY_TEMPLATES: Record<string, string> = {
  jobConfirmation: "appointment_confirmation",
  appointmentReminder: "appointment_reminder",
  engineerEnRoute: "engineer_on_the_way",
  runningLate: "eta_update",
  jobCompleted: "job_completed",
  quoteReady: "quote_sent",
  invoiceSent: "invoice_sent",
  paymentReminder: "payment_reminder",
  custom: "custom_message",
  customerMessage: "custom_message",
};

function optionalUuid(value: string | undefined): string | null {
  return value && UUID_PATTERN.test(value) ? value : null;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);

  try {
    const { supabase } = await requireAuth(req);
    const request = (await req.json().catch(() => ({}))) as SendSmsRequest;
    const action = request.action ?? "send";

    if (!request.customerId || !UUID_PATTERN.test(request.customerId)) {
      return jsonResponse({ sent: false, reason: "invalidRequest", error: "A customer is required." }, 400);
    }
    const templateKey = LEGACY_TEMPLATES[request.template ?? ""] ?? request.template ?? "custom_message";
    if (!/^[a-z_]{3,40}$/.test(templateKey)) {
      return jsonResponse({ sent: false, reason: "unknownTemplate", error: "Unknown message type." }, 400);
    }

    const { data: companyId } = await supabase.rpc("current_company_id");
    if (!companyId) return jsonResponse({ sent: false, reason: "notPermitted", error: "No company for this user." }, 403);
    const { data: canSend } = await supabase.rpc("has_perm", { p: "smsCreditsConsume" });
    if (canSend !== true) {
      return jsonResponse({ sent: false, reason: "notPermitted", error: outcomeMessage("notPermitted") }, 403);
    }

    // Tenancy under the caller's own RLS.
    const { data: customer } = await supabase.from("customers").select("id, company_id")
      .eq("id", request.customerId).maybeSingle();
    if (!customer || customer.company_id !== companyId) {
      return jsonResponse({ sent: false, reason: "unknownCustomer", error: outcomeMessage("unknownCustomer") }, 404);
    }
    const jobId = optionalUuid(request.jobId);
    let quoteId = optionalUuid(request.quoteId);
    let invoiceId = optionalUuid(request.invoiceId);

    // Quote / invoice messages sent from a job use THAT job's own quote or
    // latest invoice, looked up under the caller's RLS (a role that can't read
    // invoices simply finds none, and the render refuses).
    const quoteKinds = ["quote_sent", "quote_reminder", "quote_accepted", "quote_declined"];
    const invoiceKinds = ["invoice_sent", "payment_reminder", "overdue_reminder", "payment_received"];
    if (jobId && !quoteId && quoteKinds.includes(templateKey)) {
      const { data: job } = await supabase.from("jobs").select("quote_id, company_id").eq("id", jobId).maybeSingle();
      if (job && job.company_id === companyId && job.quote_id) quoteId = job.quote_id;
    }
    if (jobId && !invoiceId && invoiceKinds.includes(templateKey)) {
      const { data: inv } = await supabase.from("invoices").select("id, company_id").eq("job_id", jobId)
        .neq("status", "void").order("created_at", { ascending: false }).limit(1).maybeSingle();
      if (inv && inv.company_id === companyId) invoiceId = inv.id;
    }
    for (const [table, id, reason] of [["jobs", jobId, "unknownJob"], ["quotes", quoteId, "unknownQuote"],
      ["invoices", invoiceId, "unknownInvoice"]] as const) {
      if (!id) continue;
      const { data: row } = await supabase.from(table).select("id, company_id, customer_id").eq("id", id).maybeSingle();
      if (!row || row.company_id !== companyId || row.customer_id !== customer.id) {
        return jsonResponse({ sent: false, reason, error: outcomeMessage(reason) }, 404);
      }
    }

    const recipient = await resolveRecipient(supabase, companyId, customer.id, request.phone);
    if (!recipient) {
      return jsonResponse({ sent: false, reason: "invalidRecipient", error: outcomeMessage("invalidRecipient") }, 422);
    }

    const admin = createAdminClient();
    const rendered = await renderMessage(admin, {
      companyId, templateKey, customerId: customer.id, jobId, quoteId, invoiceId, recipient,
      eta: request.eta ?? null, body: typeof request.body === "string" ? request.body : null,
    });
    if (!rendered.ok) {
      return jsonResponse({ sent: false, reason: "templateInvalid", error: rendered.error, missing: rendered.missing ?? [] }, 422);
    }

    const { data: segData } = await supabase.rpc("sms_segment_info", { p_body: rendered.body });
    const seg = firstRow<{ segments: number; encoding: string }>(segData);
    const { data: readiness } = await supabase.rpc("sms_send_readiness", { p_to: recipient });

    if (action === "preview") {
      return jsonResponse({
        preview: true, body: rendered.body, recipient, segments: seg?.segments ?? 1, encoding: seg?.encoding ?? "GSM-7",
        creditsNeeded: seg?.segments ?? 1, blocker: readiness ?? null,
        blockerMessage: readiness ? outcomeMessage(String(readiness)) : null,
      });
    }

    if (action === "schedule") {
      const when = request.scheduledFor ? new Date(request.scheduledFor) : null;
      if (!when || Number.isNaN(when.getTime())) {
        return jsonResponse({ sent: false, reason: "invalidTime", error: "Pick a time for the message." }, 422);
      }
      const { data: scheduledId, error } = await supabase.rpc("schedule_sms", {
        p_customer: customer.id, p_job: jobId, p_quote: quoteId, p_invoice: invoiceId, p_template: templateKey,
        p_body: rendered.body, p_to: recipient, p_scheduled_for: when.toISOString(),
      });
      if (error) {
        const code = String(error.message ?? "");
        return jsonResponse({
          sent: false, reason: "scheduleRefused",
          error: ["optedOut", "notSetUp", "noSubscription", "companyClosed", "suspended"].includes(code)
            ? outcomeMessage(code) : code || "The message couldn't be scheduled.",
        }, 422);
      }
      return jsonResponse({ scheduled: true, scheduledId, scheduledFor: when.toISOString(), segments: seg?.segments ?? 1 });
    }

    const { data: reserveData, error: reserveError } = await supabase.rpc("reserve_sms_send", {
      p_customer: customer.id, p_job: jobId, p_quote: quoteId, p_invoice: invoiceId,
      p_to: recipient, p_body: rendered.body, p_template: templateKey,
    });
    if (reserveError) {
      console.error("[sms-send] reservation failed", reserveError.code);
      return jsonResponse({ sent: false, reason: "reserveFailed", error: "Could not reserve SMS credit. Nothing was sent." }, 500);
    }
    const reservation = firstRow<Reservation>(reserveData);
    if (!reservation || reservation.outcome !== "reserved") {
      const outcome = reservation?.outcome ?? "unknown";
      return jsonResponse({
        sent: false,
        reason: outcome === "insufficientCredits" ? "insufficientCredits" : outcome,
        balance: reservation?.balance_after ?? null,
        segments: reservation?.segments ?? seg?.segments ?? null,
        error: outcomeMessage(outcome, { needed: reservation?.segments ?? seg?.segments ?? undefined,
          balance: reservation?.balance_after ?? undefined }),
      }, outcome === "insufficientCredits" ? 402 : 422);
    }

    const delivery = await deliverReservation(admin, companyId, reservation, rendered.body);
    if (!delivery.sent) {
      return jsonResponse({
        sent: false, reason: "providerRejected", balance: delivery.balance, error: delivery.detail,
        messageId: reservation.notification_id,
      }, 502);
    }
    return jsonResponse({
      sent: true,
      messageId: reservation.notification_id,
      conversationId: reservation.conversation_id,
      providerReference: delivery.providerReference,
      status: "sent",
      creditsCharged: reservation.credits_charged,
      segments: reservation.segments,
      balance: delivery.balance,
      detail: delivery.detail,
    });
  } catch (err) {
    if (err instanceof AuthError) return jsonResponse({ error: "Unauthorized" }, 401);
    console.error("[sms-send] unexpected failure", err instanceof Error ? err.message : "unknown");
    return jsonResponse({ sent: false, error: "Something went wrong. Nothing was sent and no credit was used." }, 500);
  }
});
