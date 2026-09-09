import { corsHeaders, createAdminClient, jsonResponse } from "../_shared/auth.ts";

/// Generates the recurring service visits that have fallen due.
///
/// THIS IS NO LONGER THE PRODUCTION SCHEDULER. Migration 0005 registers a
/// pg_cron job that calls `public.run_recurring_tick(7)` inside the database
/// every morning, so recurring visits appear whether or not anything invokes
/// this endpoint — no phone, no network hop and no shared secret involved.
/// This function remains as the MANUAL entry point: a backfill after downtime,
/// or a deliberate run while investigating an agreement.
///
/// SECURITY: there is no user here, so there is no JWT. The function is
/// deployed with --no-verify-jwt and authenticates the CALLER with a shared
/// secret header, compared in constant time. Without CRON_SECRET set it
/// refuses to run at all rather than leaving an unauthenticated
/// job-creation endpoint on the internet.
///
/// IT CALLS THE SAME LOCKED PATH AS THE SCHEDULE. Previously this invoked
/// `generate_due_recurring_jobs` directly, which meant a manual run could
/// overlap the scheduled one. Overlapping runs cannot create a duplicate visit
/// — the partial unique index on (service_agreement_id, generated_for_date)
/// arbitrates that — but the loser of the race has already drawn a number from
/// the company's job sequence, leaving a permanent gap in that company's job
/// numbering. Going through `run_recurring_tick` means both paths contend for
/// the same advisory lock, so the second one returns immediately instead.
///
/// The per-company argument this function used to accept has been removed. It
/// had no caller, and it reached the generator by a route that skipped that
/// lock — the two reasons not to keep an option.

interface TickSummary {
  ran: boolean;
  skipped?: string;
  at?: string;
  horizonDays?: number;
  considered?: number;
  generated?: number;
  alreadyGenerated?: number;
  failed?: number;
  failures?: string[];
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

  const body = (await req.json().catch(() => ({}))) as { horizonDays?: number };

  // A small horizon lets visits appear on the schedule a little before they are
  // strictly due, which is what a dispatcher actually wants. The scheduled job
  // uses 7; this defaults to the same so a manual run behaves identically.
  const horizon = Math.max(0, Math.min(Number(body.horizonDays ?? 7), 90));

  const admin = createAdminClient();

  const { data, error } = await admin.rpc("run_recurring_tick", {
    p_horizon_days: horizon,
  });

  if (error) {
    console.error("[recurring-tick] generation failed", error.message);
    return jsonResponse({ error: "Generation failed" }, 500);
  }

  const summary = (data ?? { ran: false }) as TickSummary;

  // A run that generated nothing because another run held the lock is reported
  // as exactly that, rather than as a successful no-op.
  if (summary.ran === false) {
    return jsonResponse({ ...summary, manual: true }, 200);
  }

  if ((summary.failed ?? 0) > 0) {
    console.error(
      `[recurring-tick] ${summary.failed} agreement(s) failed`,
      summary.failures ?? [],
    );
  }

  return jsonResponse({ ...summary, manual: true });
});
