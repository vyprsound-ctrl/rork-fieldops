import { corsHeaders, createAdminClient, jsonResponse } from "../_shared/auth.ts";

/// Emails Harbour South support about every chat report (Guideline 1.2).
///
/// Invoked only by the database (pg_net, migration 0015): immediately when a
/// report is filed and every two minutes as a retry sweep. Each call carries an
/// HMAC over a timestamp (key in Supabase Vault); anything unsigned is refused.
///
/// Recipient: MODERATION_ALERT_EMAIL only (blank or malformed = not configured;
/// there is deliberately no fallback). The address is never logged, returned,
/// or written to the database. When it is missing, alerts are marked failed so
/// they retry and, after 10 attempts, surface in moderation_alerts_attention.
/// Sender: RESEND_FROM_EMAIL over RESEND_API_KEY, the same transport as invoices.

const REASONS: Record<string, string> = {
  harassment: "Harassment or bullying",
  hate: "Hate speech",
  threat: "Threat or violence",
  sexual: "Sexual content",
  spam: "Spam",
  illegal: "Illegal activity",
  self_harm: "Self-harm",
  other: "Other",
};

function escapeHtml(value: string): string {
  return value.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]!));
}

const RECIPIENT_MISSING = "Moderation recipient not configured";

function moderationRecipient(): string | null {
  const value = (Deno.env.get("MODERATION_ALERT_EMAIL") ?? "").trim();
  if (!value) return null;
  return /^[^\s@<>,;]+@[^\s@<>,;]+\.[^\s@<>,;]+$/.test(value) ? value : null;
}

// deno-lint-ignore no-explicit-any
function composeTest(row: any): { subject: string; text: string } {
  const lines = [
    "TEST — no action needed.",
    "",
    "This confirms Harbour South FieldOps moderation alerts reach this inbox.",
    "It is not a report, contains no customer or company data, and needs no reply.",
    `Alert ID: ${row.alert_id}`,
    `Queued: ${row.created_at}`,
    `Attempt: ${row.attempt ?? 1}`,
    row.note ? `Note: ${row.note}` : "",
  ].filter((l) => l !== "");
  return { subject: "[FieldOps moderation] TEST — no action needed", text: lines.join("\n") };
}

// deno-lint-ignore no-explicit-any
function compose(row: any): { subject: string; text: string } {
  if (row.kind === "test") return composeTest(row);
  const kind = row.source === "user" ? "Block" : row.source === "sms" ? "Customer SMS report" : "Office chat report";
  const reason = REASONS[row.reason] ?? row.reason;
  const reported = row.source === "sms"
    ? `Customer ${row.snapshot_meta?.from_number ?? "(unknown number)"}`
    : `${row.reported_name ?? "(unknown)"} (${row.reported_role ?? "-"})`;
  const excerpt = typeof row.snapshot_body === "string" ? row.snapshot_body.slice(0, 1500) : "";

  const lines = [
    `${kind} — ${reason}${row.escalated ? " — ESCALATED: Harbour South must act" : ""}`,
    "",
    `Company: ${row.company_name}`,
    `Report ID: ${row.report_id}`,
    `Filed: ${row.created_at}`,
    `Reporter: ${row.reporter_name ?? "(unknown)"} (${row.reporter_role ?? "-"})`,
    `Reported: ${reported}`,
    `Status: ${row.status}`,
    row.details ? `Reporter's note: ${row.details}` : "",
    excerpt ? `\nMessage:\n${excerpt}` : "",
    row.photo_count ? `Photos attached: ${row.photo_count}` : "",
    "",
    "Act within 24 hours. Platform action (service role):",
    `select public.moderate_message_report('${row.report_id}', 'remove_message' | 'restrict_chat' | 'suspend_account' | 'dismiss', 'note');`,
    "Never share the reporter's identity with the reported person.",
  ].filter((l) => l !== "");

  return {
    subject: `[FieldOps moderation] ${kind}: ${reason}${row.escalated ? " (escalated)" : ""}`,
    text: lines.join("\n"),
  };
}

async function sendEmail(to: string, subject: string, text: string): Promise<string | null> {
  const apiKey = Deno.env.get("RESEND_API_KEY");
  const transport = Deno.env.get("RESEND_FROM_EMAIL");
  if (!apiKey || !transport) return "Email provider not configured";
  const address = (transport.match(/<([^>]+)>/)?.[1] ?? transport).trim();
  try {
    const response = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        from: `Harbour South FieldOps <${address}>`,
        to: [to],
        subject,
        text,
        html: `<pre style="font-family:ui-monospace,Menlo,monospace;white-space:pre-wrap">${escapeHtml(text)}</pre>`,
      }),
    });
    return response.ok ? null : `Email provider refused the message (${response.status})`;
  } catch (err) {
    return `Couldn't reach the email provider: ${err instanceof Error ? err.message : "unknown"}`;
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return jsonResponse({ error: "Method not allowed" }, 405);

  const admin = createAdminClient();
  const { data: valid } = await admin.rpc("moderation_verify_signature", {
    p_timestamp: req.headers.get("x-moderation-timestamp") ?? "",
    p_signature: req.headers.get("x-moderation-signature") ?? "",
  });
  if (valid !== true) return jsonResponse({ error: "Invalid signature" }, 403);

  const recipient = moderationRecipient();
  if (!recipient) console.error("[moderation-notify]", RECIPIENT_MISSING);

  const { data: rows, error } = await admin.rpc("moderation_claim_alerts", { p_limit: 20 });
  if (error) {
    console.error("[moderation-notify] claim failed", error.message);
    return jsonResponse({ error: "Claim failed" }, 500);
  }

  let sent = 0;
  let failed = 0;
  // deno-lint-ignore no-explicit-any
  for (const row of (rows ?? []) as any[]) {
    const { subject, text } = compose(row);
    const failure = recipient ? await sendEmail(recipient, subject, text) : RECIPIENT_MISSING;
    const { error: markError } = await admin.rpc("moderation_mark_alert", {
      p_alert: row.alert_id,
      p_ok: failure === null,
      p_error: failure,
    });
    if (markError) console.error("[moderation-notify] mark failed", row.alert_id, markError.message);
    if (failure === null) sent += 1;
    else {
      failed += 1;
      console.error("[moderation-notify] alert not delivered", row.alert_id, failure);
    }
  }

  return jsonResponse({ sent, failed });
});
