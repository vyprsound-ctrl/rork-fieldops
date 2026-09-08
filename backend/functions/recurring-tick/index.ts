import { corsHeaders, createAdminClient, jsonResponse } from "../_shared/auth.ts";

/// Generates the recurring service visits that have fallen due.
///
/// WHY THIS IS A SERVER FUNCTION: a maintenance contract that only produces its
/// next visit when somebody happens to open the app is not a maintenance
/// contract. This runs on a schedule, under the service role, whether or not a
/// single phone is switched on.
///
/// SECURITY: there is no user here, so there is no JWT. The function is
/// deployed with --no-verify-jwt and authenticates the CALLER with a shared
/// secret header. Without CRON_SECRET set it refuses to run at all rather than
/// leaving an unauthenticated job-creation endpoint on the internet.
///
/// IDEMPOTENCY: the work is done by `generate_due_recurring_jobs`, which writes
/// through a unique index on (service_agreement_id, generated_for_date). Two
/// overlapping runs, a retry, or a manual invocation on the same day cannot
/// produce two visits for one period — the second insert simply loses.

interface GenerationRow {
  service_agreement_id: string;
  job_id: string | null;
  scheduled_for: string;
  outcome: string;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  const expected = Deno.env.get("CRON_SECRET");
  if (!expected) {
    console.error("[recurring-tick] CRON_SECRET is not set — refusing to run");
    return jsonResponse({ error: "Not configured" }, 500);
  }

  const provided = req.headers.get("x-cron-secret");
  if (!provided || provided.length !== expected.length) {
    return jsonResponse({ error: "Forbidden" }, 403);
  }
  let diff = 0;
  for (let i = 0; i < expected.length; i++) diff |= expected.charCodeAt(i) ^ provided.charCodeAt(i);
  if (diff !== 0) return jsonResponse({ error: "Forbidden" }, 403);

  const body = (await req.json().catch(() => ({}))) as { horizonDays?: number; companyId?: string };

  // A small horizon lets visits appear on the schedule a little before they are
  // strictly due, which is what a dispatcher actually wants.
  const horizon = Math.max(0, Math.min(Number(body.horizonDays ?? 0), 90));

  const admin = createAdminClient();

  const { data, error } = await admin.rpc("generate_due_recurring_jobs", {
    p_company: body.companyId ?? null,
    p_horizon_days: horizon,
  });

  if (error) {
    console.error("[recurring-tick] generation failed", error.message);
    return jsonResponse({ error: "Generation failed" }, 500);
  }

  const rows = (data ?? []) as GenerationRow[];
  const generated = rows.filter((r) => r.outcome === "generated");
  const skipped = rows.filter((r) => r.outcome === "alreadyGenerated");
  const failed = rows.filter((r) => r.outcome.startsWith("failed"));

  if (failed.length > 0) {
    console.error(`[recurring-tick] ${failed.length} agreement(s) failed`, failed.map((f) => f.outcome));
  }

  return jsonResponse({
    ran: true,
    horizonDays: horizon,
    generated: generated.length,
    alreadyGenerated: skipped.length,
    failed: failed.length,
    jobs: generated.map((r) => ({
      serviceAgreementId: r.service_agreement_id,
      jobId: r.job_id,
      scheduledFor: r.scheduled_for,
    })),
  });
});
