import { supabase } from "./supabase";
import { AppError, inIds, rows, rpc, translate } from "./api";

// ---------------------------------------------------------------------------
// Office inbox: chat between the office and engineers
// ---------------------------------------------------------------------------

export interface OfficeThread {
  id: string;
  engineer_user_id: string;
  job_id: string | null;
  customer_id: string | null;
  subject: string;
  created_at: string;
  last_message_at: string;
  last_message_preview: string;
  last_sender_user_id: string | null;
  unread: boolean;
  engineerName: string;
  jobNumber?: string;
}

export interface OfficeMessage {
  id: string;
  thread_id: string;
  sender_user_id: string;
  body: string;
  job_photo_ids: string[] | null;
  created_at: string;
}

export const threadTitle = (t: Pick<OfficeThread, "subject">) => t.subject?.trim() || "Message to the office";

export async function blockedUsers(): Promise<Set<string>> {
  const list = await rows<{ blocked_user_id: string }>(supabase.from("chat_blocks").select("blocked_user_id")).catch(
    () => [] as { blocked_user_id: string }[],
  );
  return new Set(list.map((b) => b.blocked_user_id));
}

export async function officeThreads(me: string): Promise<OfficeThread[]> {
  const list = await rows<Omit<OfficeThread, "unread" | "engineerName" | "jobNumber">>(
    supabase
      .from("office_threads")
      .select("id,engineer_user_id,job_id,customer_id,subject,created_at,last_message_at,last_message_preview,last_sender_user_id")
      .order("last_message_at", { ascending: false })
      .limit(60),
  );
  const [reads, people, jobs] = await Promise.all([
    rows<{ thread_id: string; last_read_at: string }>(supabase.from("office_thread_reads").select("thread_id,last_read_at")),
    inIds<{ id: string; name: string }>("app_users", "id,name", "id", list.map((t) => t.engineer_user_id)),
    inIds<{ id: string; number: string }>("jobs", "id,number", "id", list.map((t) => t.job_id ?? "")),
  ]);
  const readAt = new Map(reads.map((r) => [r.thread_id, r.last_read_at]));
  const names = new Map(people.map((p) => [p.id, p.name]));
  const numbers = new Map(jobs.map((j) => [j.id, j.number]));
  return list.map((t) => {
    const read = readAt.get(t.id);
    return {
      ...t,
      unread: t.last_sender_user_id !== me && (!read || new Date(read) < new Date(t.last_message_at)),
      engineerName: names.get(t.engineer_user_id) ?? "Team member",
      jobNumber: t.job_id ? numbers.get(t.job_id) : undefined,
    };
  });
}

export async function officeMessages(threadId: string): Promise<OfficeMessage[]> {
  return rows<OfficeMessage>(
    supabase
      .from("office_messages")
      .select("id,thread_id,sender_user_id,body,job_photo_ids,created_at")
      .eq("thread_id", threadId)
      .order("created_at", { ascending: true }),
  );
}

export async function sendOfficeMessage(input: {
  threadId: string | null;
  engineerId: string | null;
  jobId: string | null;
  subject: string;
  body: string;
}): Promise<string> {
  const body = input.body.trim();
  if (!body) throw new AppError("Write a message first.");
  if (body.length > 4000) throw new AppError("Keep messages under 4,000 characters.");
  if (input.subject.length > 120) throw new AppError("Keep the subject under 120 characters.");
  const { data, error } = await supabase.rpc("send_office_message", {
    p_thread: input.threadId,
    p_job: input.jobId,
    p_engineer: input.engineerId,
    p_subject: input.subject.trim(),
    p_body: body,
    p_photo_ids: [],
  });
  if (error) {
    if (error.code === "TD422" || error.code === "P0001") throw new AppError(error.message);
    throw translate(error);
  }
  return String(data);
}

export const markThreadRead = (threadId: string) => rpc("mark_office_thread_read", { p_thread: threadId }).catch(() => undefined);

// ---------------------------------------------------------------------------
// Reports and blocks (chat safety, same as the iPhone app)
// ---------------------------------------------------------------------------

export const REPORT_REASONS: { id: string; label: string }[] = [
  { id: "harassment", label: "Harassment or bullying" },
  { id: "hate", label: "Hate speech" },
  { id: "threat", label: "Threats or violence" },
  { id: "sexual", label: "Sexual content" },
  { id: "spam", label: "Spam or scam" },
  { id: "illegal", label: "Illegal activity" },
  { id: "self_harm", label: "Self-harm" },
  { id: "other", label: "Something else" },
];

export const reportOfficeMessage = (messageId: string, reason: string, details: string) =>
  rpc("report_office_message", { p_message: messageId, p_reason: reason, p_details: details.trim() || null });

export const reportSmsMessage = (messageId: string, reason: string, details: string) =>
  rpc("report_sms_message", { p_message: messageId, p_reason: reason, p_details: details.trim() || null });

export const blockUser = (userId: string, reason: string) =>
  rpc("block_chat_user", { p_user: userId, p_reason: reason, p_details: null });

export const unblockUser = (userId: string) => rpc("unblock_chat_user", { p_user: userId });

// ---------------------------------------------------------------------------
// Customer SMS
// ---------------------------------------------------------------------------

export interface SmsConversation {
  conversation_id: string;
  phone_e164: string;
  customer_id: string | null;
  customer_name: string | null;
  job_id: string | null;
  job_number: string | null;
  last_message_at: string | null;
  last_preview: string | null;
  last_direction: "inbound" | "outbound" | null;
  unread: number;
  opted_out: boolean;
}

export interface SmsMessage {
  id: string;
  conversation_id: string;
  direction: "inbound" | "outbound";
  body: string;
  at: string;
  status: string | null;
  template: string | null;
  segments: number | null;
  credits_charged: number | null;
  credits_refunded: number | null;
  job_id: string | null;
  failure_reason: string | null;
}

export const smsConversations = () => rpc<SmsConversation[]>("sms_conversation_list", { p_limit: 200 }).then((d) => d ?? []);

export async function smsMessages(conversationId: string): Promise<SmsMessage[]> {
  return rows<SmsMessage>(
    supabase
      .from("sms_thread_messages")
      .select("id,conversation_id,direction,body,at,status,template,segments,credits_charged,credits_refunded,job_id,failure_reason")
      .eq("conversation_id", conversationId)
      .order("at", { ascending: true }),
  );
}

export const markSmsRead = (conversationId: string) =>
  rpc("mark_sms_conversation_read", { p_conversation: conversationId }).catch(() => undefined);

export interface SmsSendResult {
  sent?: boolean;
  preview?: boolean;
  body?: string;
  recipient?: string;
  segments?: number;
  encoding?: string;
  blockerMessage?: string | null;
  creditsNeeded?: number;
  creditsCharged?: number;
  balance?: number;
  conversationId?: string;
  detail?: string;
  error?: string;
}

async function edge<T>(name: string, body: Record<string, unknown>, fallback: string): Promise<T> {
  const { data, error } = await supabase.functions.invoke(name, { body });
  if (error) {
    let message = fallback;
    const ctx = (error as { context?: Response }).context;
    if (ctx && typeof ctx.json === "function") {
      const b = await ctx.json().catch(() => null);
      if (b?.blockerMessage) message = String(b.blockerMessage);
      else if (b?.error) message = String(b.error);
      else if (b?.detail) message = String(b.detail);
      else if (b?.message) message = String(b.message);
    }
    throw new AppError(message);
  }
  return data as T;
}

export const smsPreview = (customerId: string, body: string, phone?: string) =>
  edge<SmsSendResult>("sms-send", { action: "preview", customerId, template: "custom", body, phone }, "The message couldn't be checked.");

export const smsSend = (customerId: string, body: string, phone?: string) =>
  edge<SmsSendResult>("sms-send", { action: "send", customerId, template: "custom", body, phone }, "The message couldn't be sent.");

// ---------------------------------------------------------------------------
// SMS setup and credits
// ---------------------------------------------------------------------------

export interface SmsStatus {
  status: string;
  friendly_status: string | null;
  registration_status: string | null;
  registration_route: string | null;
  phone_number: string | null;
  number_status: string | null;
  billing_state: string | null;
  next_fee_due_at: string | null;
  number_fee_cents: number | null;
  number_fee_credits: number | null;
  setup_fee_cents: number | null;
  credits_per_segment: number | null;
  attention: string | null;
  business_name: string | null;
  can_manage: boolean;
  has_subscription: boolean;
  balance: number | null;
  provisioning_step: string | null;
  requested_number: string | null;
  needs_number_choice: boolean;
  sole_prop_verification_pending: boolean;
}

export interface SmsSetupResponse {
  status?: SmsStatus | SmsStatus[] | null;
  providerAvailable?: boolean;
  error?: string | null;
  numberUnavailable?: boolean;
  numbers?: AvailableNumber[];
}

export interface AvailableNumber {
  phoneNumber: string;
  friendlyName: string;
  locality: string | null;
  region: string | null;
}

export const firstStatus = (s: SmsSetupResponse["status"]): SmsStatus | null =>
  Array.isArray(s) ? s[0] ?? null : s ?? null;

export const smsSetup = (body: Record<string, unknown>) =>
  edge<SmsSetupResponse>("sms-setup", body, "SMS setup couldn't be reached. Try again.");

export const ROUTES = [
  { id: "low_volume", title: "Registered business, low volume", detail: "You have an EIN and send fewer than about 6,000 texts a month. Cheapest for most trade businesses." },
  { id: "standard", title: "Registered business", detail: "You have an EIN and send more than a few thousand texts a month." },
  { id: "sole_proprietor", title: "Sole proprietor (no EIN)", detail: "You trade as yourself without an EIN. You'll confirm a one-time text on your own mobile." },
];

export const STRUCTURES = [
  { id: "Limited Liability Corporation", title: "LLC" },
  { id: "Corporation", title: "Corporation" },
  { id: "Partnership", title: "Partnership" },
  { id: "Co-operative", title: "Co-operative" },
  { id: "Non-profit Corporation", title: "Non-profit" },
];

export interface SmsDetails {
  route: string;
  legal_name: string;
  business_type: string;
  ein: string;
  website: string;
  street: string;
  street2: string;
  city: string;
  state: string;
  postal_code: string;
  rep_first_name: string;
  rep_last_name: string;
  rep_title: string;
  rep_email: string;
  rep_phone: string;
  opt_in_description: string;
  mobile_phone: string;
}

/** The same checks the server makes, so the owner sees the sentence before sending. */
export function detailsProblem(d: SmsDetails): string | null {
  const req = (v: string) => v.trim().length > 0;
  if (!d.route) return "Choose your business type.";
  if (!req(d.legal_name)) return "Enter your legal business name.";
  if (!req(d.street) || !req(d.city) || !req(d.state) || !req(d.postal_code)) return "Enter your full business address.";
  if (!/^[A-Za-z]{2}$/.test(d.state.trim())) return "Use the two-letter state code, like FL.";
  if (!/^\d{5}(-\d{4})?$/.test(d.postal_code.trim())) return "Enter a valid ZIP code.";
  if (!req(d.rep_first_name) || !req(d.rep_last_name)) return "Enter the authorized representative's name.";
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(d.rep_email)) return "Enter a valid email for the representative.";
  if (!/^\+?[0-9()\s.-]{10,20}$/.test(d.rep_phone)) return "Enter a valid phone number for the representative.";
  if (d.opt_in_description.trim().length < 40) return "Describe how customers agree to receive texts (at least a sentence).";
  if (d.route === "sole_proprietor") {
    if (!/^\+?[0-9()\s.-]{10,20}$/.test(d.mobile_phone)) {
      return "Enter the owner's own mobile number — it receives a one-time verification text.";
    }
  } else {
    if (!req(d.business_type)) return "Choose your company structure.";
    if (!/^\d{2}-?\d{7}$/.test(d.ein.trim())) return "Enter your 9-digit EIN, like 12-3456789.";
    if (!/^https?:\/\/[^\s.]+\.[^\s]{2,}/i.test(d.website.trim())) return "Enter your business website (carriers review it).";
  }
  return null;
}

export interface SmsUsage {
  balance: number;
  purchased: number;
  used: number;
  refunded: number;
  fees: number;
  segments_30d: number;
  messages_sent_30d: number;
  messages_failed_30d: number;
  messages_received_30d: number;
}

export const smsUsage = () => rpc<SmsUsage[]>("sms_usage_summary").then((d) => d?.[0] ?? null);

export interface Bundle {
  id: string;
  credits: number;
  priceCents: number;
}

export const smsBundles = () =>
  edge<{ configured: boolean; balance: number; bundles: Bundle[] }>("sms-purchase", { action: "bundles" }, "Credit bundles couldn't be loaded.");

export const smsCheckout = (bundleId: string) =>
  edge<{ checkoutUrl: string }>("sms-purchase", { action: "checkout", bundleId, returnTo: "web" }, "The purchase couldn't be started.");

export const prettyPhone = (e164: string | null | undefined) => {
  if (!e164) return "";
  const d = e164.replace(/\D/g, "");
  if (d.length === 11 && d.startsWith("1")) return `(${d.slice(1, 4)}) ${d.slice(4, 7)}-${d.slice(7)}`;
  return e164;
};
