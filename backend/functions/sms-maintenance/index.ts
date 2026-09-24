import { corsHeaders, createAdminClient, jsonResponse } from "../_shared/auth.ts";
import { deliverReservation, firstRow, outcomeMessage, renderMessage, type Reservation, resolveRecipient } from "../_shared/sms.ts";
import { advanceProvisioning } from "../_shared/provisioning.ts";
import { masterConfig, releaseNumber, setSubaccountStatus, type TwilioCredentials } from "../_shared/twilio.ts";

/// Scheduled SMS maintenance. Invoked every minute by pg_cron with an HMAC
/// signature over a timestamp (key in Supabase Vault); anything unsigned is
/// refused. Work, in order:
///   1. Due scheduled/automated messages: rendered server-side and sent through
///      the SAME reservation as a manual send (subscription, messaging status,
///      opt-out, segments, credit — all re-checked at send time). A message
///      cancelled before it was claimed is never sent.
///   2. Provisioning/registration progress (transient retries with backoff;
///      permanent 4xx errors wait for the owner).
///   3. Monthly number fees -> grace -> pause (never an immediate release).
///   4. Number release ONLY where the database release guard allows it.
///   5. Closed-company teardown after retention: release numbers, suspend then
///      close the company's subaccount. The master account is never touched.
///
/// Trust Hub status callbacks (?event=trusthub) are acknowledged only;
/// registration state is always re-read from Twilio by step 2.

const MAX_RUNTIME_MS = 45_000;

async function subCredentials(
  admin: ReturnType<typeof createAdminClient>,
  accountId: string,
  sid: string | null,
): Promise<TwilioCredentials | null> {
  if (!sid) return null;
  const { data } = await admin.rpc("messaging_subaccount_token", { p_account: accountId });
  return typeof data === "string" && data ? { accountSid: sid, authToken: data } : null;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  const url = new URL(req.url);
  if (url.searchParams.get("event") === "trusthub") return new Response("", { status: 204 });
  if (req.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);

  const admin = createAdminClient();
  const { data: valid } = await admin.rpc("sms_verify_maintenance_signature", {
    p_timestamp: req.headers.get("x-sms-timestamp") ?? "",
    p_signature: req.headers.get("x-sms-signature") ?? "",
  });
  if (valid !== true) return jsonResponse({ error: "Invalid signature" }, 403);

  const started = Date.now();
  const report = { scheduledSent: 0, scheduledSkipped: 0, scheduledFailed: 0, provisioning: 0, fees: {} as Record<string, number>, released: 0, closed: 0 };
  const timeLeft = () => Date.now() - started < MAX_RUNTIME_MS;

  // 1. Scheduled messages
  const { data: due } = await admin.rpc("claim_due_scheduled_sms", { p_limit: 25 });
  // deno-lint-ignore no-explicit-any
  for (const item of (due ?? []) as any[]) {
    if (!timeLeft()) break;
    let finalStatus = "failed";
    let reason: string | null = null;
    let notificationId: string | null = null;
    try {
      const to = item.to_number ?? await resolveRecipient(admin, item.company_id, item.customer_id, null);
      if (!to) {
        finalStatus = "skipped"; reason = outcomeMessage("invalidRecipient");
      } else {
        const rendered = await renderMessage(admin, {
          companyId: item.company_id, templateKey: item.template_key, customerId: item.customer_id,
          jobId: item.job_id, quoteId: item.quote_id, invoiceId: item.invoice_id, recipient: to,
          eta: item.eta_text, body: item.body,
        });
        if (!rendered.ok) {
          finalStatus = "skipped"; reason = rendered.error ?? "The message couldn't be prepared.";
        } else {
          const { data } = await admin.rpc("reserve_sms_send_service", {
            p_company: item.company_id, p_customer: item.customer_id, p_job: item.job_id, p_quote: item.quote_id,
            p_invoice: item.invoice_id, p_to: to, p_body: rendered.body, p_template: item.template_key, p_scheduled: item.id,
          });
          const reservation = firstRow<Reservation>(data);
          if (!reservation || reservation.outcome !== "reserved") {
            finalStatus = "skipped";
            reason = outcomeMessage(reservation?.outcome ?? "unknown", { needed: reservation?.segments ?? undefined,
              balance: reservation?.balance_after ?? undefined });
          } else {
            notificationId = reservation.notification_id;
            const delivery = await deliverReservation(admin, item.company_id, reservation, rendered.body);
            finalStatus = delivery.sent ? "sent" : "failed";
            reason = delivery.sent ? null : delivery.detail;
          }
        }
      }
    } catch (err) {
      finalStatus = "failed";
      reason = "The message couldn't be sent.";
      console.error("[sms-maintenance] scheduled send failed", err instanceof Error ? err.message : "unknown");
    }
    await admin.rpc("finish_scheduled_sms", { p_id: item.id, p_status: finalStatus, p_notification: notificationId, p_reason: reason });
    if (finalStatus === "sent") report.scheduledSent++;
    else if (finalStatus === "skipped") report.scheduledSkipped++;
    else report.scheduledFailed++;
  }

  // 2. Provisioning & registration progress
  if (masterConfig()) {
    const { data: pending } = await admin.from("company_messaging_accounts").select("id, next_attempt_at, provisioning_step")
      .in("status", ["provisioning", "awaiting_registration"]).neq("provisioning_step", "number_unavailable")
      .or(`next_attempt_at.is.null,next_attempt_at.lte.${new Date().toISOString()}`).limit(10);
    for (const account of pending ?? []) {
      if (!timeLeft()) break;
      await advanceProvisioning(admin, account.id);
      report.provisioning++;
    }
  }

  // 3. Monthly number fees
  const { data: dueNumbers } = await admin.from("company_phone_numbers").select("id")
    .eq("status", "active").lte("next_fee_due_at", new Date().toISOString()).limit(50);
  for (const number of dueNumbers ?? []) {
    if (!timeLeft()) break;
    const { data: outcome } = await admin.rpc("sms_charge_number_fee", { p_number: number.id });
    const key = String(outcome ?? "unknown");
    report.fees[key] = (report.fees[key] ?? 0) + 1;
    if (key === "releaseEligible") {
      await admin.from("company_phone_numbers").update({ status: "releasing", release_reason: "unpaid_retention_elapsed" })
        .eq("id", number.id).eq("status", "active");
    }
  }

  // 4. Release numbers the guard has already approved (status = releasing)
  const config = masterConfig();
  if (config) {
    const { data: releasing } = await admin.from("company_phone_numbers")
      .select("id, phone_number_sid, messaging_account_id").eq("status", "releasing").limit(10);
    for (const number of releasing ?? []) {
      if (!timeLeft()) break;
      const { data: allowed } = await admin.rpc("sms_number_release_allowed", { p_number: number.id });
      if (allowed !== true) continue;
      const { data: account } = await admin.from("company_messaging_accounts").select("id, twilio_subaccount_sid")
        .eq("id", number.messaging_account_id).maybeSingle();
      const sub = account ? await subCredentials(admin, account.id, account.twilio_subaccount_sid) : null;
      try {
        if (sub && number.phone_number_sid) await releaseNumber(sub, number.phone_number_sid);
        await admin.from("company_phone_numbers").update({ status: "released", released_at: new Date().toISOString() })
          .eq("id", number.id);
        report.released++;
      } catch (err) {
        // Transient: stays "releasing" and is retried next tick. Never deleted.
        console.error("[sms-maintenance] release failed; will retry", err instanceof Error ? err.message : "unknown");
      }
    }

    // 5. Closed companies after retention
    const { data: closing } = await admin.from("company_messaging_accounts")
      .select("id, company_id, twilio_subaccount_sid, retention_until").eq("status", "closing")
      .lte("retention_until", new Date().toISOString()).limit(5);
    for (const account of closing ?? []) {
      if (!timeLeft()) break;
      await admin.from("company_phone_numbers").update({ status: "releasing", release_reason: "company_closed" })
        .eq("messaging_account_id", account.id).eq("status", "active");
      const { count } = await admin.from("company_phone_numbers").select("id", { count: "exact", head: true })
        .eq("messaging_account_id", account.id).neq("status", "released");
      if ((count ?? 0) > 0) continue; // numbers first; subaccount closes on a later tick
      try {
        if (account.twilio_subaccount_sid && account.twilio_subaccount_sid !== config.master.accountSid) {
          await setSubaccountStatus(config.master, account.twilio_subaccount_sid, "closed");
        }
        await admin.from("company_messaging_accounts").update({ status: "closed", closed_at: new Date().toISOString(),
          updated_at: new Date().toISOString() }).eq("id", account.id);
        await admin.from("messaging_provisioning_events").insert({ company_id: account.company_id, messaging_account_id: account.id,
          operation: "teardown", stage: "subaccount_closed", outcome: "succeeded", provider_reference: account.twilio_subaccount_sid });
        report.closed++;
      } catch (err) {
        console.error("[sms-maintenance] subaccount close failed; will retry", err instanceof Error ? err.message : "unknown");
      }
    }
  }

  return jsonResponse({ ok: true, ...report });
});
