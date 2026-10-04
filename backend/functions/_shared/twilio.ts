/// Harbour South's single Twilio integration point.
///
/// ARCHITECTURE
///   Harbour South master account (platform; this code never closes it)
///     -> one subaccount per company (FriendlyName = "hs-company-<uuid>")
///        -> one Messaging Service, one dedicated number, the company's own
///           A2P brand + campaign
///
/// CREDENTIALS
///   * Master credentials come only from the Edge Function environment:
///     TWILIO_MASTER_ACCOUNT_SID / TWILIO_MASTER_AUTH_TOKEN. They are used for
///     subaccount lifecycle and number search, never sent to a device.
///   * A subaccount's own token lives in Supabase Vault and is read through a
///     service-role-only database function. Trust Hub and messaging.twilio.com
///     resources MUST be created with the subaccount's own credentials.
///
/// Nothing in this module decides which company a request belongs to. Callers
/// resolve the company server-side first and hand in that company's account.

export const TWILIO_API = "https://api.twilio.com/2010-04-01";
export const TRUST_HUB = "https://trusthub.twilio.com/v1";
export const MESSAGING = "https://messaging.twilio.com/v1";

/// Twilio policy SIDs for ISV secondary-customer onboarding (from Twilio's
/// ISV API onboarding guides).
export const POLICY = {
  secondaryCustomerProfile: "RNdfbf3fae0e1107f8aded0e7cead80bf5",
  a2pMessagingProfile: "RNb0d4771c2c98518d916a3d4cd70a8f8b",
  starterCustomerProfile: "RN806dd6cd175f314e1f96a9727ee271f4",
  soleProprietorTrustProduct: "RN670d5d2e282a6130ae063b234b6019c8",
} as const;

export interface TwilioCredentials {
  accountSid: string;
  authToken: string;
  /// Basic Auth username when it differs from the account (a Main API Key
  /// SID for the master account). Absent means the Account SID is used.
  username?: string;
}

export interface MasterConfig {
  master: TwilioCredentials;
  primaryCustomerProfileSid: string | null;
  callbackBase: string;
  notificationEmail: string | null;
}

/// Master configuration, or null when this deployment has none. A null here is
/// reported to the app as "SMS isn't available yet", never as a crash.
export function masterConfig(): MasterConfig | null {
  const accountSid = (Deno.env.get("TWILIO_MASTER_ACCOUNT_SID") ?? "").trim();
  if (!/^AC[0-9a-f]{32}$/i.test(accountSid)) return null;

  // Preferred: a Main API Key (SK SID + secret) as the Basic Auth username and
  // password; the AC SID stays the account identifier used in URLs. When both
  // are set but malformed, fail closed rather than silently using the token.
  let master: TwilioCredentials;
  const apiKeySid = (Deno.env.get("TWILIO_MASTER_API_KEY_SID") ?? "").trim();
  const apiKeySecret = (Deno.env.get("TWILIO_MASTER_API_KEY_SECRET") ?? "").trim();
  if (apiKeySid && apiKeySecret) {
    if (!/^SK[0-9a-f]{32}$/i.test(apiKeySid) || apiKeySecret.length < 16) return null;
    master = { accountSid, authToken: apiKeySecret, username: apiKeySid };
  } else {
    const authToken = (Deno.env.get("TWILIO_MASTER_AUTH_TOKEN") ?? "").trim();
    if (authToken.length < 16) return null;
    master = { accountSid, authToken };
  }
  return {
    master,
    primaryCustomerProfileSid: (Deno.env.get("TWILIO_PRIMARY_CUSTOMER_PROFILE_SID") ?? "").trim() || null,
    callbackBase: callbackBase(),
    notificationEmail: (Deno.env.get("TWILIO_ISV_NOTIFICATION_EMAIL") ?? "").trim() || null,
  };
}

/// Public base URL that Twilio calls back. Signatures are computed over the
/// exact URL Twilio was given, so this is the single source for building AND
/// verifying callback URLs.
export function callbackBase(): string {
  const configured = (Deno.env.get("SMS_CALLBACK_BASE_URL") ?? "").trim();
  const fallback = `${(Deno.env.get("SUPABASE_URL") ?? "").replace(/\/+$/, "")}/functions/v1`;
  return (configured || fallback).replace(/\/+$/, "");
}

export function statusCallbackUrl(callbackKey: string): string {
  return `${callbackBase()}/sms-status?k=${encodeURIComponent(callbackKey)}`;
}

export function inboundCallbackUrl(callbackKey: string): string {
  return `${callbackBase()}/sms-inbound?k=${encodeURIComponent(callbackKey)}`;
}

// ---------------------------------------------------------------------------
// Errors
// ---------------------------------------------------------------------------

export class TwilioError extends Error {
  constructor(
    message: string,
    readonly httpStatus: number,
    readonly code: string | null,
    readonly moreInfo: string | null = null,
  ) {
    super(message);
    this.name = "TwilioError";
  }

  /// 429, 5xx and network failures are worth retrying. A 4xx is a decision
  /// Twilio made about this request and will make again.
  get isTransient(): boolean {
    return this.httpStatus === 0 || this.httpStatus === 429 || this.httpStatus >= 500;
  }
}

/// A sentence a trade business owner can act on. Never a raw code, SID or
/// stack trace (the code is kept separately in the provisioning log).
export function friendlyTwilioError(error: unknown): string {
  if (!(error instanceof TwilioError)) return "Something went wrong while setting up SMS. We'll try again shortly.";
  if (error.isTransient) return "The SMS provider is busy right now. We'll try again automatically.";
  switch (error.code) {
    case "21422":
    case "21452":
      return "That number was just taken by someone else. Choose another number.";
    case "21610":
      return "This customer has replied STOP and can't receive texts until they reply START.";
    case "21211":
    case "21614":
      return "That mobile number doesn't look valid. Check the number on the customer's record.";
    case "21408":
    case "21612":
      return "Texts can't be sent to that number.";
    case "30034":
    case "30007":
      return "The carrier blocked this message. Make sure your SMS registration is approved.";
    case "20003":
    case "20404":
      return "SMS setup needs attention from Harbour South support.";
    default:
      return "The SMS provider couldn't complete that request. Check your details and try again.";
  }
}

// ---------------------------------------------------------------------------
// Transport
// ---------------------------------------------------------------------------

export type FormValue = string | number | boolean | null | undefined | Array<string | number | boolean>;

/// Twilio form encoding: arrays repeat the key, null/undefined are omitted.
export function encodeForm(params: Record<string, FormValue>): string {
  const form = new URLSearchParams();
  for (const [key, value] of Object.entries(params)) {
    if (value === null || value === undefined) continue;
    if (Array.isArray(value)) {
      for (const item of value) form.append(key, String(item));
    } else {
      form.set(key, String(value));
    }
  }
  return form.toString();
}

export interface RequestOptions {
  method?: "GET" | "POST" | "DELETE";
  params?: Record<string, FormValue>;
  query?: Record<string, FormValue>;
  retries?: number;
  headers?: Record<string, string>;
}

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

/// One Twilio REST call. Retries 429/5xx/network with backoff; never retries a 4xx.
// deno-lint-ignore no-explicit-any
export async function twilioRequest<T = any>(
  credentials: TwilioCredentials,
  url: string,
  options: RequestOptions = {},
): Promise<T> {
  const method = options.method ?? (options.params ? "POST" : "GET");
  const retries = options.retries ?? 2;
  const target = options.query ? `${url}?${encodeForm(options.query)}` : url;

  let attempt = 0;
  while (true) {
    let response: Response;
    try {
      response = await fetch(target, {
        method,
        headers: {
          Authorization: `Basic ${btoa(`${credentials.username ?? credentials.accountSid}:${credentials.authToken}`)}`,
          ...(options.params ? { "Content-Type": "application/x-www-form-urlencoded" } : {}),
          ...(options.headers ?? {}),
        },
        body: options.params ? encodeForm(options.params) : undefined,
      });
    } catch (err) {
      if (attempt < retries) {
        attempt += 1;
        await sleep(400 * 2 ** attempt);
        continue;
      }
      throw new TwilioError(err instanceof Error ? err.message : "network error", 0, null);
    }

    if (response.status === 204) return {} as T;
    const payload = await response.json().catch(() => ({}));
    if (response.ok) return payload as T;

    const error = new TwilioError(
      String(payload?.message ?? `Twilio returned ${response.status}`),
      response.status,
      payload?.code !== undefined && payload?.code !== null ? String(payload.code) : null,
      payload?.more_info ? String(payload.more_info) : null,
    );
    if (error.isTransient && attempt < retries) {
      attempt += 1;
      const retryAfter = Number(response.headers.get("Retry-After") ?? "0");
      await sleep(retryAfter > 0 ? Math.min(retryAfter, 5) * 1000 : 500 * 2 ** attempt);
      continue;
    }
    throw error;
  }
}

// ---------------------------------------------------------------------------
// Webhook signatures
// ---------------------------------------------------------------------------

/// Twilio's documented scheme: HMAC-SHA1 over the full URL followed by every
/// POST parameter (sorted by name, name+value concatenated), base64.
export async function computeTwilioSignature(
  url: string,
  params: Record<string, string>,
  authToken: string,
): Promise<string> {
  let payload = url;
  for (const key of Object.keys(params).sort()) payload += key + params[key];
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(authToken),
    { name: "HMAC", hash: "SHA-1" },
    false,
    ["sign"],
  );
  const mac = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(payload));
  return btoa(String.fromCharCode(...new Uint8Array(mac)));
}

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

/// Accepts a signature made with ANY of the given secrets. Twilio's docs do
/// not state whether callbacks for a subaccount's number are signed with the
/// subaccount's token or the parent's, so both — each a secret only Twilio
/// and Harbour South hold — are accepted. An unsigned or mis-signed request
/// is refused either way.
export async function verifyTwilioSignature(
  url: string,
  params: Record<string, string>,
  signature: string | null,
  tokens: Array<string | null | undefined>,
): Promise<boolean> {
  if (!signature) return false;
  for (const token of tokens) {
    if (!token) continue;
    const expected = await computeTwilioSignature(url, params, token);
    if (timingSafeEqual(expected, signature)) return true;
  }
  return false;
}

export async function readTwilioForm(req: Request): Promise<Record<string, string>> {
  const raw = await req.text();
  const params: Record<string, string> = {};
  for (const [key, value] of new URLSearchParams(raw).entries()) params[key] = value;
  return params;
}

// ---------------------------------------------------------------------------
// Resources
// ---------------------------------------------------------------------------

export interface TwilioAccount {
  sid: string;
  auth_token: string;
  friendly_name: string;
  status: string;
}

export function subaccountFriendlyName(companyId: string): string {
  return `hs-company-${companyId}`;
}

/// Finds this company's subaccount by its deterministic name, or creates it.
/// Retrying after a crash finds the one already made instead of a duplicate.
export async function ensureSubaccount(master: TwilioCredentials, companyId: string): Promise<TwilioAccount> {
  const name = subaccountFriendlyName(companyId);
  const existing = await twilioRequest<{ accounts: TwilioAccount[] }>(master, `${TWILIO_API}/Accounts.json`, {
    query: { FriendlyName: name, PageSize: 20 },
  });
  const live = (existing.accounts ?? []).find((a) => a.friendly_name === name && a.status !== "closed");
  if (live) return live;
  return await twilioRequest<TwilioAccount>(master, `${TWILIO_API}/Accounts.json`, { params: { FriendlyName: name } });
}

export async function setSubaccountStatus(
  master: TwilioCredentials,
  subaccountSid: string,
  status: "active" | "suspended" | "closed",
): Promise<void> {
  if (subaccountSid === master.accountSid) throw new Error("Refusing to change the master account");
  await twilioRequest(master, `${TWILIO_API}/Accounts/${subaccountSid}.json`, { params: { Status: status } });
}

export interface MessagingService {
  sid: string;
  friendly_name: string;
}

export async function ensureMessagingService(
  sub: TwilioCredentials,
  companyId: string,
  callbackKey: string,
): Promise<MessagingService> {
  const name = `hs-${companyId}`.slice(0, 64);
  const list = await twilioRequest<{ services: MessagingService[] }>(sub, `${MESSAGING}/Services`, {
    query: { PageSize: 50 },
  });
  const found = (list.services ?? []).find((s) => s.friendly_name === name);
  const settings = {
    InboundRequestUrl: inboundCallbackUrl(callbackKey),
    InboundMethod: "POST",
    StatusCallback: statusCallbackUrl(callbackKey),
    UseInboundWebhookOnNumber: false,
    StickySender: true,
    SmartEncoding: false,
  };
  if (found) {
    return await twilioRequest<MessagingService>(sub, `${MESSAGING}/Services/${found.sid}`, { params: settings });
  }
  return await twilioRequest<MessagingService>(sub, `${MESSAGING}/Services`, {
    params: { FriendlyName: name, ...settings },
  });
}

export interface AvailableNumber {
  phoneNumber: string;
  friendlyName: string;
  locality: string | null;
  region: string | null;
  postalCode: string | null;
}

export async function searchLocalNumbers(
  master: TwilioCredentials,
  filters: { areaCode?: string; contains?: string; region?: string; limit?: number },
): Promise<AvailableNumber[]> {
  // deno-lint-ignore no-explicit-any
  const result = await twilioRequest<{ available_phone_numbers: any[] }>(
    master,
    `${TWILIO_API}/Accounts/${master.accountSid}/AvailablePhoneNumbers/US/Local.json`,
    {
      query: {
        SmsEnabled: true,
        AreaCode: filters.areaCode,
        Contains: filters.contains,
        InRegion: filters.region,
        PageSize: Math.min(Math.max(filters.limit ?? 20, 1), 30),
      },
    },
  );
  return (result.available_phone_numbers ?? []).map((n) => ({
    phoneNumber: String(n.phone_number),
    friendlyName: String(n.friendly_name ?? n.phone_number),
    locality: n.locality ?? null,
    region: n.region ?? null,
    postalCode: n.postal_code ?? null,
  }));
}

export interface IncomingNumber {
  sid: string;
  phone_number: string;
  friendly_name: string;
}

export async function listIncomingNumbers(sub: TwilioCredentials): Promise<IncomingNumber[]> {
  const result = await twilioRequest<{ incoming_phone_numbers: IncomingNumber[] }>(
    sub,
    `${TWILIO_API}/Accounts/${sub.accountSid}/IncomingPhoneNumbers.json`,
    { query: { PageSize: 50 } },
  );
  return result.incoming_phone_numbers ?? [];
}

export async function purchaseNumber(sub: TwilioCredentials, phoneNumber: string, companyId: string): Promise<IncomingNumber> {
  return await twilioRequest<IncomingNumber>(sub, `${TWILIO_API}/Accounts/${sub.accountSid}/IncomingPhoneNumbers.json`, {
    params: { PhoneNumber: phoneNumber, FriendlyName: `hs-${companyId}`.slice(0, 64) },
    retries: 0,
  });
}

export async function attachNumberToService(sub: TwilioCredentials, serviceSid: string, phoneSid: string): Promise<void> {
  try {
    await twilioRequest(sub, `${MESSAGING}/Services/${serviceSid}/PhoneNumbers`, { params: { PhoneNumberSid: phoneSid } });
  } catch (err) {
    // 21710: already in this service — the desired end state.
    if (err instanceof TwilioError && err.code === "21710") return;
    throw err;
  }
}

export async function releaseNumber(sub: TwilioCredentials, phoneSid: string): Promise<void> {
  try {
    await twilioRequest(sub, `${TWILIO_API}/Accounts/${sub.accountSid}/IncomingPhoneNumbers/${phoneSid}.json`, {
      method: "DELETE",
    });
  } catch (err) {
    if (err instanceof TwilioError && err.httpStatus === 404) return;
    throw err;
  }
}

// ---------------------------------------------------------------------------
// Sending
// ---------------------------------------------------------------------------

export interface SendResult {
  accepted: boolean;
  sid: string | null;
  status: string | null;
  from: string | null;
  segments: number | null;
  priceMicros: number | null;
  errorCode: string | null;
  errorMessage: string | null;
}

/// Sends through the company's own subaccount and Messaging Service. There is
/// deliberately no parameter for a raw From number or another account.
export async function sendThroughCompany(
  sub: TwilioCredentials,
  messagingServiceSid: string,
  callbackKey: string,
  to: string,
  body: string,
): Promise<SendResult> {
  try {
    // deno-lint-ignore no-explicit-any
    const payload = await twilioRequest<any>(sub, `${TWILIO_API}/Accounts/${sub.accountSid}/Messages.json`, {
      params: {
        To: to,
        Body: body,
        MessagingServiceSid: messagingServiceSid,
        StatusCallback: statusCallbackUrl(callbackKey),
      },
      retries: 0,
    });
    return {
      accepted: true,
      sid: String(payload.sid),
      status: String(payload.status ?? "queued"),
      from: payload.from ? String(payload.from) : null,
      segments: payload.num_segments ? Number(payload.num_segments) : null,
      priceMicros: priceToMicros(payload.price),
      errorCode: null,
      errorMessage: null,
    };
  } catch (err) {
    const code = err instanceof TwilioError ? err.code : null;
    return {
      accepted: false,
      sid: null,
      status: null,
      from: null,
      segments: null,
      priceMicros: null,
      errorCode: code ?? (err instanceof TwilioError ? String(err.httpStatus) : "network"),
      errorMessage: friendlyTwilioError(err),
    };
  }
}

/// Twilio reports price as a negative decimal string ("-0.00830").
export function priceToMicros(price: unknown): number | null {
  if (price === null || price === undefined || price === "") return null;
  const value = Math.abs(Number(price));
  return Number.isFinite(value) ? Math.round(value * 1_000_000) : null;
}

// ---------------------------------------------------------------------------
// A2P registration (Trust Hub + Messaging) — subaccount credentials only
// ---------------------------------------------------------------------------

export async function trustHubCreate(
  sub: TwilioCredentials,
  path: string,
  params: Record<string, FormValue>,
): Promise<{ sid: string; status?: string }> {
  return await twilioRequest(sub, `${TRUST_HUB}/${path}`, { params, retries: 1 });
}

export async function trustHubAssign(sub: TwilioCredentials, bundlePath: string, objectSid: string): Promise<void> {
  try {
    await twilioRequest(sub, `${TRUST_HUB}/${bundlePath}/EntityAssignments`, { params: { ObjectSid: objectSid } });
  } catch (err) {
    // Already assigned — the desired end state on a resumed run.
    if (err instanceof TwilioError && err.httpStatus === 409) return;
    throw err;
  }
}

export async function trustHubEvaluateAndSubmit(
  sub: TwilioCredentials,
  bundlePath: string,
  policySid: string,
): Promise<{ compliant: boolean; detail: string | null }> {
  // deno-lint-ignore no-explicit-any
  const evaluation = await twilioRequest<any>(sub, `${TRUST_HUB}/${bundlePath}/Evaluations`, {
    params: { PolicySid: policySid },
  });
  if (evaluation?.status === "noncompliant") {
    // deno-lint-ignore no-explicit-any
    const failures = (evaluation.results ?? []).flatMap((r: any) =>
      // deno-lint-ignore no-explicit-any
      (r.fields ?? []).filter((f: any) => f.passed === false).map((f: any) => String(f.friendly_name ?? f.object_field))
    );
    return {
      compliant: false,
      detail: failures.length > 0 ? `Some details were incomplete: ${failures.slice(0, 4).join(", ")}.` : null,
    };
  }
  await twilioRequest(sub, `${TRUST_HUB}/${bundlePath}`, { params: { Status: "pending-review" } });
  return { compliant: true, detail: null };
}

// deno-lint-ignore no-explicit-any
export async function fetchBrand(sub: TwilioCredentials, brandSid: string): Promise<any> {
  return await twilioRequest(sub, `${MESSAGING}/a2p/BrandRegistrations/${brandSid}`);
}

// deno-lint-ignore no-explicit-any
export async function fetchCampaign(sub: TwilioCredentials, serviceSid: string, campaignSid: string): Promise<any> {
  return await twilioRequest(sub, `${MESSAGING}/Services/${serviceSid}/Compliance/Usa2p/${campaignSid}`);
}
