import { createAdminClient } from "../_shared/auth.ts";

/// Delivers queued push notifications to Apple.
///
/// This function is the only thing in the system that talks to APNs, and the
/// only thing that can turn a queued push row into `sent` or `failed`. It runs
/// with the service role because it acts on behalf of the whole estate rather
/// than any one signed-in user — there is no caller whose JWT could scope it.
/// The two database functions it uses (`claim_push_batch`, `settle_push_delivery`)
/// are granted to `service_role` alone and additionally assert the caller's
/// role, so a signed-in user cannot reach them.
///
/// Honesty rules, in order of importance:
///
///   1. A notification is marked `sent` only when APNs returned 200 for it.
///      There is no other path to `sent` anywhere in this file.
///   2. When the APNs credentials are absent nothing is claimed and nothing is
///      marked failed — no attempt was made, so the rows stay honestly `queued`
///      and the response says exactly how many are waiting and why.
///   3. When APNs rejects the token itself (410 Unregistered, 400
///      BadDeviceToken) the device registration is revoked, so an expired token
///      stops generating attempts instead of failing forever.
///
/// This function never touches the SMS credit ledger. Push costs no credit, and
/// `settle_notification` — the function that does move credit — is not called
/// from here.

interface ClaimedRow {
  notification_id: string;
  company_id: string;
  token: string;
  environment: "sandbox" | "production";
  bundle_id: string;
  title: string | null;
  body: string | null;
  deep_link: string | null;
  job_id: string | null;
  event: string;
}

interface DeliveryResult {
  notificationId: string;
  event: string;
  status: "sent" | "failed";
  detail: string;
  tokenRevoked: boolean;
}

const APNS_HOSTS = {
  production: "https://api.push.apple.com",
  sandbox: "https://api.sandbox.push.apple.com",
} as const;

/// APNs reasons that mean "this address is dead" rather than "this attempt
/// failed". Only these revoke the registration.
const DEAD_TOKEN_REASONS = new Set([
  "Unregistered",
  "BadDeviceToken",
  "DeviceTokenNotForTopic",
  "ExpiredToken",
]);

function base64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pkcs8FromPem(pem: string): ArrayBuffer {
  const base64 = pem
    .replace(/-----BEGIN [A-Z ]+-----/g, "")
    .replace(/-----END [A-Z ]+-----/g, "")
    .replace(/\s+/g, "");
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}

/// Builds the ES256 provider token APNs expects. Apple rejects tokens older
/// than an hour, so it is regenerated per run rather than cached across runs.
async function makeProviderToken(p8: string, keyId: string, teamId: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pkcs8FromPem(p8),
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );

  const encoder = new TextEncoder();
  const header = base64Url(encoder.encode(JSON.stringify({ alg: "ES256", kid: keyId })));
  const claims = base64Url(
    encoder.encode(JSON.stringify({ iss: teamId, iat: Math.floor(Date.now() / 1000) })),
  );
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    encoder.encode(`${header}.${claims}`),
  );

  return `${header}.${claims}.${base64Url(new Uint8Array(signature))}`;
}

/// One delivery attempt. Returns what actually happened — never an assumption.
async function deliver(
  row: ClaimedRow,
  providerToken: string,
  topic: string,
): Promise<{ delivered: boolean; reference: string | null; detail: string; deadToken: boolean }> {
  const host = APNS_HOSTS[row.environment] ?? APNS_HOSTS.production;

  const payload = {
    aps: {
      alert: { title: row.title ?? "TradeDesk", body: row.body ?? "" },
      sound: "default",
      "interruption-level": row.event === "job.cancelled" ? "time-sensitive" : "active",
    },
    // Read by the app to route the tap to the right screen.
    deepLink: row.deep_link,
    jobId: row.job_id,
    event: row.event,
  };

  try {
    const response = await fetch(`${host}/3/device/${row.token}`, {
      method: "POST",
      headers: {
        authorization: `bearer ${providerToken}`,
        "apns-topic": topic,
        "apns-push-type": "alert",
        "apns-priority": "10",
        // A job alert that could not be delivered within the hour is stale.
        "apns-expiration": String(Math.floor(Date.now() / 1000) + 3600),
        // Repeated updates about one job replace each other on the lock screen.
        "apns-collapse-id": (row.job_id ?? row.notification_id).slice(0, 63),
        "content-type": "application/json",
      },
      body: JSON.stringify(payload),
    });

    const reference = response.headers.get("apns-id");

    if (response.ok) {
      return { delivered: true, reference, detail: "Accepted by APNs.", deadToken: false };
    }

    let reason = `APNs returned ${response.status}`;
    try {
      const parsed = JSON.parse(await response.text()) as { reason?: string };
      if (parsed.reason) reason = `${parsed.reason} (HTTP ${response.status})`;
      return {
        delivered: false,
        reference,
        detail: reason,
        deadToken: DEAD_TOKEN_REASONS.has(parsed.reason ?? ""),
      };
    } catch {
      return {
        delivered: false,
        reference,
        detail: reason,
        deadToken: response.status === 410,
      };
    }
  } catch (error) {
    // A transport failure is a failure. It is never recorded as delivered.
    return {
      delivered: false,
      reference: null,
      detail: `Could not reach APNs: ${error instanceof Error ? error.message : "unknown error"}`,
      deadToken: false,
    };
  }
}

/// APNs reasons that prove our provider credentials were accepted. Apple only
/// reaches a verdict about the device token or the topic once it has already
/// authenticated the provider token, so any of these means the auth key, Key ID
/// and Team ID are genuinely good.
const AUTH_ACCEPTED_REASONS = new Set([
  "BadDeviceToken",
  "Unregistered",
  "DeviceTokenNotForTopic",
  "ExpiredToken",
]);

/// APNs reasons that mean the credentials themselves are wrong.
const AUTH_REJECTED_REASONS = new Set([
  "InvalidProviderToken",
  "ExpiredProviderToken",
  "MissingProviderToken",
  "TopicDisallowed",
  "BadCertificate",
  "BadCertificateEnvironment",
  "Forbidden",
]);

/// Describes why a key could not be used, in words that cannot contain any part
/// of the key. The underlying error message is deliberately discarded rather
/// than forwarded, so no key material can ever reach a response or a log.
function keyFailureCategory(error: unknown): string {
  const message = error instanceof Error ? error.message : "";
  if (/atob|base64|character/i.test(message)) return "MalformedPEM";
  if (/DataError|key data|import/i.test(message)) return "NotAValidP256PrivateKey";
  return "KeyUnusable";
}

/// Proves the APNs credentials are real, without delivering anything to anyone.
///
/// Checking that four environment variables are non-empty proves nothing: a
/// truncated paste, a Key ID belonging to a different key, or a Team ID from
/// another account all look identical to a correct setup until the first real
/// send. This answers the three questions that actually matter — does the key
/// parse, can it sign a provider token, and does Apple accept that token — and
/// it answers the last one by asking Apple.
///
/// It is safe to run against production at any time:
///   * it claims nothing, settles nothing, and writes no row;
///   * it addresses a deliberately synthetic device token that belongs to no
///     handset, so nobody can receive anything as a result of it;
///   * a rejection of that token is the expected outcome and is reported as
///     proof of authentication, never as a delivery failure;
///   * it returns only booleans, Apple's own public reason codes, and the
///     bundle id (which already ships inside the app). No secret, and no
///     derivative of a secret such as a hash, ever enters the response.
async function verifyApnsCredentials(
  p8: string,
  keyId: string,
  teamId: string,
  topic: string,
): Promise<Response> {
  const credentialsPresent = {
    APNS_AUTH_KEY_P8: p8.length > 0,
    APNS_KEY_ID: keyId.length > 0,
    APNS_TEAM_ID: teamId.length > 0,
    APNS_BUNDLE_ID: topic.length > 0,
  };

  const result = {
    check: "apns-credentials",
    credentialsPresent,
    privateKeyParsed: false,
    providerTokenGenerated: false,
    apnsAuthentication: "not attempted",
    category: null as string | null,
    topic: topic.length > 0 ? topic : null,
    detail: "",
  };

  const absent = Object.entries(credentialsPresent)
    .filter(([, isSet]) => !isSet)
    .map(([name]) => name);

  const answer = (): Response =>
    new Response(JSON.stringify(result), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });

  if (absent.length > 0) {
    result.category = "MissingCredentials";
    result.detail = `Nothing to verify: ${absent.join(", ")} is not set.`;
    return answer();
  }

  // Step one: is this actually an EC P-256 private key? Checked separately from
  // signing so that a bad key and a bad Key ID cannot be mistaken for one
  // another. The delivery path above is untouched by any of this.
  try {
    await crypto.subtle.importKey(
      "pkcs8",
      pkcs8FromPem(p8),
      { name: "ECDSA", namedCurve: "P-256" },
      false,
      ["sign"],
    );
    result.privateKeyParsed = true;
  } catch (error) {
    result.category = keyFailureCategory(error);
    result.detail =
      "APNS_AUTH_KEY_P8 is not a usable EC P-256 private key. Re-paste the .p8 " +
      "file whole, including its BEGIN and END lines.";
    return answer();
  }

  // Step two: sign a real provider token, through the very same function the
  // delivery path uses, so this cannot pass while delivery would fail.
  let providerToken: string;
  try {
    providerToken = await makeProviderToken(p8, keyId, teamId);
    result.providerTokenGenerated = true;
  } catch (error) {
    result.category = keyFailureCategory(error);
    result.detail = "The key parsed but could not sign a provider token.";
    return answer();
  }

  // Step three: ask Apple. This token is 64 zeros — syntactically well formed,
  // deliberately belonging to no device in existence. Apple must authenticate
  // us before it can judge the token, so its verdict on the token is the proof
  // we are after.
  const probeToken = "0".repeat(64);

  try {
    const response = await fetch(`${APNS_HOSTS.production}/3/device/${probeToken}`, {
      method: "POST",
      headers: {
        authorization: `bearer ${providerToken}`,
        "apns-topic": topic,
        "apns-push-type": "alert",
        "apns-priority": "5",
        "apns-expiration": "1",
        "content-type": "application/json",
      },
      body: JSON.stringify({ aps: { alert: { title: "connectivity check", body: "" } } }),
    });

    let reason = "";
    try {
      reason = (JSON.parse(await response.text()) as { reason?: string }).reason ?? "";
    } catch {
      reason = "";
    }

    if (response.ok) {
      // Vanishingly unlikely for a zero token, but it still proves the point.
      result.apnsAuthentication = "accepted";
      result.category = "Accepted";
      result.detail = "APNs accepted the provider token.";
    } else if (AUTH_ACCEPTED_REASONS.has(reason)) {
      result.apnsAuthentication = "accepted";
      result.category = reason;
      result.detail =
        `APNs authenticated the credentials and then rejected the synthetic device ` +
        `token with "${reason}", which is the expected and correct outcome. The auth ` +
        `key, Key ID, Team ID and topic are all good. This is not a delivery failure: ` +
        `nothing was sent and no row was touched.`;
    } else if (AUTH_REJECTED_REASONS.has(reason)) {
      result.apnsAuthentication = "rejected";
      result.category = reason;
      result.detail = reason === "TopicDisallowed"
        ? `APNs refused the topic "${topic}": the key is not entitled to this bundle id, ` +
          `or Push Notifications is not enabled on that App ID.`
        : `APNs refused the provider credentials with "${reason}". The Key ID or Team ID ` +
          `does not match the auth key, or the key has been revoked in the developer portal.`;
    } else {
      result.apnsAuthentication = "inconclusive";
      result.category = reason || `HTTP ${response.status}`;
      result.detail =
        `APNs answered HTTP ${response.status}${reason ? ` (${reason})` : ""}, which proves ` +
        `neither good nor bad credentials. Try again shortly.`;
    }
  } catch (error) {
    result.apnsAuthentication = "inconclusive";
    result.category = "NetworkUnreachable";
    result.detail = `Could not reach APNs: ${
      error instanceof Error ? error.message : "unknown error"
    }. The credentials were not judged.`;
  }

  return answer();
}

/// Compares two strings without leaking, through timing, how much of a guess
/// was correct.
function constantTimeEquals(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let difference = 0;
  for (let i = 0; i < a.length; i += 1) difference |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return difference === 0;
}

/// Verifies a tick signed by `dispatch_push_tick()` in the database.
///
/// The database cannot safely carry a credential to us: pg_net stores every
/// outbound request header in a table that is readable by PUBLIC. So it signs
/// a timestamp instead, with a key that never leaves Vault. A signature is
/// accepted only inside a short window, which bounds replay to the moment it
/// was issued — and even a replay only asks for the dispatch that runs on a
/// timer anyway.
async function hasValidSignature(req: Request): Promise<boolean> {
  const signingKey = Deno.env.get("PUSH_DISPATCH_SIGNING_KEY") ?? "";
  const timestamp = req.headers.get("x-dispatch-timestamp") ?? "";
  const signature = req.headers.get("x-dispatch-signature") ?? "";

  if (!signingKey || !timestamp || !signature) return false;

  const issuedAt = Number(timestamp);
  if (!Number.isFinite(issuedAt)) return false;
  if (Math.abs(Date.now() / 1000 - issuedAt) > 120) return false;

  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(signingKey),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const mac = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(timestamp));
  const expected = Array.from(new Uint8Array(mac))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");

  return constantTimeEquals(expected, signature.toLowerCase());
}

Deno.serve(async (req: Request): Promise<Response> => {
  if (req.method === "OPTIONS") return new Response("ok");

  // Only the scheduler, or an operator holding the service-role key, may run a
  // dispatch. This endpoint acts for the whole estate, so it must never be
  // reachable with the anon key that ships inside the app.
  //
  // The service-role key is accepted here but is never stored in the database
  // and never sent by the scheduler — it exists only in this function's own
  // environment and in an operator's hands.
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
  const presented = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "").trim();
  const authorized = (serviceKey.length > 0 && constantTimeEquals(presented, serviceKey)) ||
    await hasValidSignature(req);

  if (!authorized) {
    return new Response(
      JSON.stringify({ error: "Unauthorized" }),
      { status: 401, headers: { "Content-Type": "application/json" } },
    );
  }

  const requested = await req.json().catch(() => ({})) as { limit?: number; mode?: string };

  const p8 = Deno.env.get("APNS_AUTH_KEY_P8") ?? "";
  const keyId = Deno.env.get("APNS_KEY_ID") ?? "";
  const teamId = Deno.env.get("APNS_TEAM_ID") ?? "";
  const topic = Deno.env.get("APNS_BUNDLE_ID") ?? "";

  // A credential check, behind exactly the same authorisation as a dispatch. It
  // runs before anything is claimed and returns without touching the database.
  if (requested.mode === "verify") {
    return await verifyApnsCredentials(p8, keyId, teamId, topic);
  }

  const admin = createAdminClient();

  const missing = [
    p8 ? null : "APNS_AUTH_KEY_P8",
    keyId ? null : "APNS_KEY_ID",
    teamId ? null : "APNS_TEAM_ID",
    topic ? null : "APNS_BUNDLE_ID",
  ].filter((name): name is string => name !== null);

  if (missing.length > 0) {
    // Deliberately claim nothing. No attempt was made, so no row is touched:
    // marking them failed would be a lie about work that never happened.
    const { count } = await admin
      .from("notifications")
      .select("id", { count: "exact", head: true })
      .eq("channel", "push")
      .eq("status", "queued");

    return new Response(
      JSON.stringify({
        configured: false,
        attempted: 0,
        sent: 0,
        failed: 0,
        waiting: count ?? 0,
        detail:
          `APNs is not configured (missing ${missing.join(", ")}). ` +
          `Nothing was attempted and nothing was marked delivered; ${count ?? 0} notification(s) remain queued.`,
      }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  }

  const limit = Math.min(Math.max(requested.limit ?? 50, 1), 500);

  const { data: claimed, error: claimError } = await admin.rpc("claim_push_batch", { p_limit: limit });
  if (claimError) {
    return new Response(
      JSON.stringify({ configured: true, error: claimError.message }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }

  const rows = (claimed ?? []) as ClaimedRow[];
  if (rows.length === 0) {
    return new Response(
      JSON.stringify({ configured: true, attempted: 0, sent: 0, failed: 0, detail: "Nothing queued." }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  }

  let providerToken: string;
  try {
    providerToken = await makeProviderToken(p8, keyId, teamId);
  } catch (error) {
    // The key itself is unusable. Every claimed row is settled as failed with
    // the real reason, and the claim is released by that settlement.
    const detail = `APNs auth key could not be used: ${error instanceof Error ? error.message : "unknown error"}`;
    for (const row of rows) {
      await admin.rpc("settle_push_delivery", {
        p_notification: row.notification_id,
        p_delivered: false,
        p_provider_reference: null,
        p_failure_reason: detail,
        p_invalid_token: false,
      });
    }
    return new Response(
      JSON.stringify({ configured: true, attempted: rows.length, sent: 0, failed: rows.length, detail }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  }

  const results: DeliveryResult[] = [];

  for (const row of rows) {
    const outcome = await deliver(row, providerToken, row.bundle_id || topic);

    const { data: settled } = await admin.rpc("settle_push_delivery", {
      p_notification: row.notification_id,
      p_delivered: outcome.delivered,
      p_provider_reference: outcome.reference,
      p_failure_reason: outcome.delivered ? null : outcome.detail,
      p_invalid_token: outcome.deadToken,
    });

    results.push({
      notificationId: row.notification_id,
      event: row.event,
      status: outcome.delivered ? "sent" : "failed",
      detail: outcome.detail,
      tokenRevoked: typeof settled === "string" && settled.includes("TokenRevoked"),
    });
  }

  const sent = results.filter((result) => result.status === "sent").length;

  return new Response(
    JSON.stringify({
      configured: true,
      attempted: results.length,
      sent,
      failed: results.length - sent,
      revokedTokens: results.filter((result) => result.tokenRevoked).length,
      results,
    }),
    { status: 200, headers: { "Content-Type": "application/json" } },
  );
});
