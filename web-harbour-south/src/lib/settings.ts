import { supabase } from "./supabase";
import { AppError, rows, rpc, translate } from "./api";
import type { Trade } from "./domain";

// ---------------------------------------------------------------------------
// Company profile
// ---------------------------------------------------------------------------

export interface CompanyProfile {
  id: string;
  name: string;
  trade: Trade;
  country_code: string;
  currency_code: string;
  time_zone_identifier: string;
  address_line: string | null;
  city: string | null;
  state: string | null;
  postal_code: string | null;
  phone: string | null;
  default_tax_rate: number | string | null;
  online_payment_link_url: string | null;
  business_email: string | null;
  default_payment_terms_label: string | null;
  default_payment_terms_days: number | null;
}

const PROFILE_COLUMNS =
  "id,name,trade,country_code,currency_code,time_zone_identifier,address_line,city,state,postal_code,phone,default_tax_rate,online_payment_link_url,business_email,default_payment_terms_label,default_payment_terms_days";

export async function companyProfile(id: string): Promise<CompanyProfile> {
  const list = await rows<CompanyProfile>(supabase.from("companies").select(PROFILE_COLUMNS).eq("id", id).limit(1));
  if (!list[0]) throw new AppError("Your company couldn't be found.");
  return list[0];
}

async function updateCompany(id: string, patch: Record<string, unknown>) {
  const { error } = await supabase
    .from("companies")
    .update({ ...patch, updated_at: new Date().toISOString() })
    .eq("id", id);
  if (error) {
    if (error.code === "23514" && /business_email/.test(error.message)) {
      throw new AppError("That doesn't look like an email address.");
    }
    if (error.code === "23514") throw new AppError("One of those values isn't accepted. Check and try again.");
    throw translate(error);
  }
}

export interface ProfileDraft {
  name: string;
  trade: Trade;
  timeZone: string;
  addressLine: string;
  city: string;
  state: string;
  postalCode: string;
  phone: string;
  taxPercent: string;
}

export async function saveProfile(id: string, d: ProfileDraft) {
  if (!d.name.trim()) throw new AppError("Enter your company name.");
  const tax = Number(d.taxPercent || "0");
  if (!Number.isFinite(tax) || tax < 0 || tax > 100) throw new AppError("Enter a tax rate between 0 and 100%.");
  await updateCompany(id, {
    name: d.name.trim(),
    trade: d.trade,
    time_zone_identifier: d.timeZone,
    address_line: d.addressLine.trim(),
    city: d.city.trim(),
    state: d.state.trim(),
    postal_code: d.postalCode.trim(),
    phone: d.phone.trim(),
    default_tax_rate: Math.round(tax * 1000) / 100000,
  });
}

// ---------------------------------------------------------------------------
// Payment terms (same options and stored labels as the iPhone app)
// ---------------------------------------------------------------------------

export type TermOption = "onCompletion" | "net7" | "net14" | "net30" | "net60" | "net90" | "custom";

export const TERM_OPTIONS: { id: TermOption; label: string; days: number | null }[] = [
  { id: "onCompletion", label: "Due on completion", days: 0 },
  { id: "net7", label: "Due in 7 days", days: 7 },
  { id: "net14", label: "Due in 14 days", days: 14 },
  { id: "net30", label: "Due in 30 days", days: 30 },
  { id: "net60", label: "Due in 60 days", days: 60 },
  { id: "net90", label: "Due in 90 days", days: 90 },
  { id: "custom", label: "Custom", days: null },
];

export function termFromLabel(label: string | null): TermOption {
  const l = (label ?? "").toLowerCase();
  if (!l) return "net30";
  if (l.includes("completion")) return "onCompletion";
  for (const o of TERM_OPTIONS) if (o.days && l.includes(String(o.days))) return o.id;
  return "custom";
}

export async function savePaymentTerms(id: string, option: TermOption, customDays: number) {
  const opt = TERM_OPTIONS.find((o) => o.id === option)!;
  const days = option === "custom" ? Math.max(Math.round(customDays) || 0, 0) : opt.days ?? 30;
  if (option === "custom" && days > 365) throw new AppError("Use 365 days or fewer.");
  const label = option === "custom" ? (days === 0 ? "Due on receipt" : `Due in ${days} days`) : opt.label;
  await updateCompany(id, { default_payment_terms_label: label, default_payment_terms_days: days });
}

// ---------------------------------------------------------------------------
// Business email and own payment link
// ---------------------------------------------------------------------------

export function normaliseBusinessEmail(raw: string): string | null {
  const t = raw.trim();
  if (!t) return null;
  if (t.length > 254 || t.length < 6) throw new AppError("That address is too long.");
  const parts = t.split("@");
  if (
    /\s/.test(t) ||
    parts.length !== 2 ||
    !parts[0] ||
    !parts[1].includes(".") ||
    parts[1].startsWith(".") ||
    parts[1].endsWith(".") ||
    parts[1].includes("..")
  ) {
    throw new AppError(
      "That doesn't look like an email address. Use the address your customers already write to, like invoices@yourbusiness.com.",
    );
  }
  return t;
}

export const saveBusinessEmail = (id: string, raw: string) =>
  updateCompany(id, { business_email: normaliseBusinessEmail(raw) });

export function normalisePaymentLink(raw: string): string | null {
  const t = raw.trim();
  if (!t) return null;
  let url: URL;
  try {
    url = new URL(t);
  } catch {
    throw new AppError("Enter the full web address, starting with https://");
  }
  if (url.protocol !== "https:") throw new AppError("The payment link must start with https://");
  return url.toString();
}

export const savePaymentLink = (id: string, raw: string) =>
  updateCompany(id, { online_payment_link_url: normalisePaymentLink(raw) });

// ---------------------------------------------------------------------------
// Notifications log
// ---------------------------------------------------------------------------

export interface NotificationRow {
  id: string;
  channel: "sms" | "email" | "push";
  template: string;
  recipient: string;
  status: "queued" | "sent" | "delivered" | "failed";
  sent_at: string | null;
  failure_reason: string | null;
  title: string | null;
  created_at: string;
}

export async function notificationLog(): Promise<NotificationRow[]> {
  return rows<NotificationRow>(
    supabase
      .from("notifications")
      .select("id,channel,template,recipient,status,sent_at,failure_reason,title,created_at")
      .order("created_at", { ascending: false })
      .limit(200),
  );
}

// ---------------------------------------------------------------------------
// Card payments (Stripe Connect, the business's own customers paying them)
// ---------------------------------------------------------------------------

export interface ConnectStatus {
  configured: boolean;
  connected: boolean;
  accountId?: string | null;
  chargesEnabled?: boolean;
  payoutsEnabled?: boolean;
  detailsSubmitted?: boolean;
  requirementsDue?: string[];
  disabledReason?: string | null;
}

export type Readiness = "notConfigured" | "notConnected" | "restricted" | "ready" | "pending";

export function readiness(s: ConnectStatus | undefined): Readiness {
  if (!s || !s.configured) return "notConfigured";
  if (!s.connected) return "notConnected";
  if (s.disabledReason) return "restricted";
  if (s.chargesEnabled) return "ready";
  return "pending";
}

async function connect<T>(body: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.functions.invoke("stripe-connect", { body: { ...body, returnTo: "web" } });
  if (error) {
    let message = "Stripe couldn't be reached. Try again.";
    const ctx = (error as { context?: Response }).context;
    if (ctx && typeof ctx.json === "function") {
      const b = await ctx.json().catch(() => null);
      if (b?.error) message = String(b.error);
      else if (b?.message) message = String(b.message);
    }
    throw new AppError(message);
  }
  return data as T;
}

export const connectStatus = () => connect<ConnectStatus>({ action: "status" });
export const connectOnboard = (businessType?: "individual" | "company") =>
  connect<{ url: string }>({ action: "onboard", businessType });
export const connectDashboard = () => connect<{ url: string }>({ action: "dashboard" });

export interface PaymentsState {
  payment_model: string | null;
  platform_fee_bps: number | null;
  external_payment_url: string | null;
}

export async function paymentsState(): Promise<PaymentsState | null> {
  const data = await rpc<PaymentsState[]>("company_commercial_state");
  return data?.[0] ?? null;
}

// ---------------------------------------------------------------------------
// Account deletion (same database functions as the iPhone app)
// ---------------------------------------------------------------------------

export interface DeletionContext {
  has_membership: boolean;
  is_owner: boolean;
  is_sole_owner: boolean;
  company_name: string | null;
  other_active_members: number;
}

export async function deletionContext(): Promise<DeletionContext | null> {
  const data = await rpc<DeletionContext[]>("account_deletion_context");
  return data?.[0] ?? null;
}

export async function deleteMyAccount(closeCompany: boolean): Promise<string> {
  const { data, error } = await supabase.rpc("delete_my_account", { p_close_company: closeCompany });
  if (error) {
    if (error.code === "TD409" || error.code === "P0001") throw new AppError(error.message);
    throw translate(error);
  }
  return String(data ?? "");
}
