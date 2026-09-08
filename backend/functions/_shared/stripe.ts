/// Stripe access for the Edge Functions.
///
/// TWO STRIPE CONTEXTS LIVE IN THIS PROJECT AND THEY MUST NEVER MIX:
///
///   FLOW A — Harbour South's SaaS subscription.
///     The trade business is the CUSTOMER. Charges are made on the PLATFORM
///     account (no Stripe-Account header). Money moves to Harbour South.
///
///   FLOW B — the trade business's own customer paying an invoice.
///     The trade business is the MERCHANT. Charges are made ON BEHALF OF its
///     connected account (`Stripe-Account: acct_...`). Money moves to the trade
///     business, less a configurable Harbour South application fee.
///
/// Every helper below states which flow it belongs to. A call that forgets the
/// `stripeAccount` argument silently becomes a platform charge, which is how a
/// customer's invoice payment would end up in Harbour South's balance — so the
/// connected-account helpers take it as a required parameter, not an option.

const STRIPE_API = "https://api.stripe.com/v1";
const STRIPE_VERSION = "2024-06-20";

export class StripeNotConfigured extends Error {
  constructor() {
    super("Stripe is not configured for this deployment.");
    this.name = "StripeNotConfigured";
  }
}

export class StripeError extends Error {
  readonly code: string | undefined;
  readonly statusCode: number;
  constructor(message: string, code: string | undefined, statusCode: number) {
    super(message);
    this.name = "StripeError";
    this.code = code;
    this.statusCode = statusCode;
  }
}

export function stripeSecret(): string {
  const key = Deno.env.get("STRIPE_SECRET_KEY");
  if (!key) throw new StripeNotConfigured();
  return key;
}

export function isStripeConfigured(): boolean {
  return Boolean(Deno.env.get("STRIPE_SECRET_KEY"));
}

/// Flattens the nested objects Stripe's form encoding expects
/// (`metadata[company_id]=...`, `expand[0]=...`).
function encodeForm(payload: Record<string, unknown>, prefix = ""): string[] {
  const parts: string[] = [];
  for (const [rawKey, value] of Object.entries(payload)) {
    if (value === undefined || value === null) continue;
    const key = prefix ? `${prefix}[${rawKey}]` : rawKey;
    if (Array.isArray(value)) {
      value.forEach((item, index) => {
        if (item !== null && typeof item === "object") {
          parts.push(...encodeForm(item as Record<string, unknown>, `${key}[${index}]`));
        } else {
          parts.push(`${encodeURIComponent(`${key}[${index}]`)}=${encodeURIComponent(String(item))}`);
        }
      });
    } else if (typeof value === "object") {
      parts.push(...encodeForm(value as Record<string, unknown>, key));
    } else {
      parts.push(`${encodeURIComponent(key)}=${encodeURIComponent(String(value))}`);
    }
  }
  return parts;
}

export interface StripeCallOptions {
  /// Present ONLY for FLOW B. Sends the request on behalf of the connected
  /// account, which is what keeps the money with the trade business.
  stripeAccount?: string;
  /// Stripe deduplicates on this for 24h. Every mutating financial call in this
  /// project supplies one so a retry cannot create a second charge.
  idempotencyKey?: string;
  method?: "GET" | "POST" | "DELETE";
}

export async function stripeRequest<T>(
  path: string,
  payload: Record<string, unknown> = {},
  options: StripeCallOptions = {},
): Promise<T> {
  const method = options.method ?? "POST";
  const headers: Record<string, string> = {
    "Authorization": `Bearer ${stripeSecret()}`,
    "Stripe-Version": STRIPE_VERSION,
  };
  if (options.stripeAccount) headers["Stripe-Account"] = options.stripeAccount;
  if (options.idempotencyKey) headers["Idempotency-Key"] = options.idempotencyKey;

  let url = `${STRIPE_API}${path}`;
  let body: string | undefined;

  if (method === "GET") {
    const query = encodeForm(payload).join("&");
    if (query) url += `?${query}`;
  } else {
    headers["Content-Type"] = "application/x-www-form-urlencoded";
    body = encodeForm(payload).join("&");
  }

  const response = await fetch(url, { method, headers, body });
  const text = await response.text();
  let parsed: unknown;
  try {
    parsed = text ? JSON.parse(text) : {};
  } catch {
    throw new StripeError(`Stripe returned an unreadable response (${response.status}).`, undefined, response.status);
  }

  if (!response.ok) {
    const err = (parsed as { error?: { message?: string; code?: string } }).error;
    throw new StripeError(
      err?.message ?? `Stripe rejected the request (${response.status}).`,
      err?.code,
      response.status,
    );
  }

  return parsed as T;
}

// ---------------------------------------------------------------------------
// Webhook signature verification
// ---------------------------------------------------------------------------

/// Verifies Stripe's `Stripe-Signature` header.
///
/// This is the ONLY thing standing between the webhook endpoint and anyone on
/// the internet marking invoices paid, so it is deliberately strict: the
/// timestamp must be recent, the comparison is constant-time, and an
/// unverifiable payload is rejected before it is even parsed.
export async function verifyStripeSignature(
  payload: string,
  header: string | null,
  secret: string,
  toleranceSeconds = 300,
): Promise<boolean> {
  if (!header) return false;

  let timestamp = "";
  const signatures: string[] = [];
  for (const part of header.split(",")) {
    const [key, value] = part.split("=", 2);
    if (key?.trim() === "t") timestamp = value?.trim() ?? "";
    if (key?.trim() === "v1" && value) signatures.push(value.trim());
  }
  if (!timestamp || signatures.length === 0) return false;

  const age = Math.abs(Math.floor(Date.now() / 1000) - Number(timestamp));
  if (!Number.isFinite(age) || age > toleranceSeconds) return false;

  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const mac = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(`${timestamp}.${payload}`),
  );
  const expected = Array.from(new Uint8Array(mac))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");

  return signatures.some((candidate) => timingSafeEqual(candidate, expected));
}

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

// ---------------------------------------------------------------------------
// Application fee — FLOW B only
// ---------------------------------------------------------------------------

export interface ApplicationFeePolicy {
  enabled: boolean;
  basisPoints: number;
  minimumCents: number;
}

/// Reads the fee policy from `platform_settings`.
///
/// The fee is NOT compiled in anywhere. Harbour South changes the row and the
/// next payment uses the new value — no app release, no redeploy. It is also
/// not readable by any app user: `platform_settings` has no policy for
/// `authenticated`, so only the service-role client used here can see it.
export async function loadApplicationFeePolicy(
  // deno-lint-ignore no-explicit-any
  adminClient: any,
): Promise<ApplicationFeePolicy> {
  const { data, error } = await adminClient
    .from("platform_settings")
    .select("key,value")
    .in("key", ["application_fee_bps", "application_fee_enabled", "application_fee_minimum_cents"]);

  if (error) {
    // Fail CLOSED: an unreadable policy takes no fee at all rather than
    // guessing one. Under-charging Harbour South is recoverable; over-charging
    // a merchant is not.
    console.error("[stripe] could not read the fee policy, taking no fee", error.message);
    return { enabled: false, basisPoints: 0, minimumCents: 0 };
  }

  const map = new Map<string, unknown>((data ?? []).map((r: { key: string; value: unknown }) => [r.key, r.value]));
  return {
    enabled: map.get("application_fee_enabled") !== false,
    basisPoints: Number(map.get("application_fee_bps") ?? 0),
    minimumCents: Number(map.get("application_fee_minimum_cents") ?? 0),
  };
}

/// Harbour South's cut of a customer payment, in cents.
///
/// This is NOT Stripe's processing fee. Stripe charges the connected account
/// separately and reports it on the balance transaction; the two are recorded
/// in different columns and must never be added together or substituted.
export function applicationFeeCents(amountCents: number, policy: ApplicationFeePolicy): number {
  if (!policy.enabled || policy.basisPoints <= 0) return 0;
  const fee = Math.floor((amountCents * policy.basisPoints) / 10_000);
  if (fee < policy.minimumCents) return 0;
  // Never let the fee approach the payment itself.
  return Math.max(0, Math.min(fee, amountCents - 1));
}
