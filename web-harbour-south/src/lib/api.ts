import type { PostgrestError } from "@supabase/supabase-js";

import { supabase } from "./supabase";
import {
  JOB_COLUMNS,
  slot,
  type Address,
  type AppUser,
  type Clash,
  type Customer,
  type JobKind,
  type JobPriority,
  type JobRow,
  type JobStatus,
  type JobView,
  type NoteVisibility,
  type Role,
  type Trade,
  isOpen,
} from "./domain";
import { timeRange } from "./format";

// ---------------------------------------------------------------------------
// Errors — the same sentences the iPhone app shows for the same refusals.
// ---------------------------------------------------------------------------

export class AppError extends Error {}

export function translate(error: PostgrestError | Error | null | undefined): AppError {
  if (!error) return new AppError("Something went wrong talking to the server.");
  const pg = error as PostgrestError;
  const code = pg.code ?? "";
  switch (code) {
    case "TD401":
    case "42501":
      return new AppError("Your role doesn't allow that.");
    case "TD403":
      return new AppError("Your company's workspace is read-only right now.");
    case "TD404":
      return new AppError("That record couldn't be found.");
    case "TD409":
      return new AppError("That isn't a step this job can take.");
    case "TD422":
      return new AppError(pg.message);
    case "23505":
      return new AppError("That record already exists.");
    case "PGRST301":
    case "PGRST303":
      return new AppError("Your session has expired. Sign in again.");
    case "PGRST202":
      return new AppError("The server doesn't recognise this request yet.");
  }
  if (/fetch|network/i.test(error.message)) return new AppError("Couldn't reach the server. Check your connection.");
  if (/jwt/i.test(error.message)) return new AppError("Your session has expired. Sign in again.");
  console.error("[data]", code, error.message);
  return new AppError("The server refused that request.");
}

export async function rows<T>(query: PromiseLike<{ data: unknown; error: PostgrestError | null }>): Promise<T[]> {
  const { data, error } = await query;
  if (error) throw translate(error);
  return (data ?? []) as T[];
}

export async function rpc<T = unknown>(name: string, params?: Record<string, unknown>): Promise<T> {
  const { data, error } = await supabase.rpc(name, params);
  if (error) throw translate(error);
  return data as T;
}

const chunk = <T,>(items: T[], size = 150) =>
  Array.from({ length: Math.ceil(items.length / size) }, (_, i) => items.slice(i * size, i * size + size));

export async function inIds<T>(table: string, columns: string, column: string, ids: string[]): Promise<T[]> {
  const unique = Array.from(new Set(ids.filter(Boolean)));
  if (!unique.length) return [];
  const parts = await Promise.all(
    chunk(unique).map((part) => rows<T>(supabase.from(table).select(columns).in(column, part))),
  );
  return parts.flat();
}

// ---------------------------------------------------------------------------
// Session
// ---------------------------------------------------------------------------

export interface Membership {
  id: string;
  company_id: string;
  name: string;
  email: string;
  role: Role;
  status: string;
}

export interface Company {
  id: string;
  name: string;
  trade: Trade;
  currency_code: string;
  country_code: string;
}

export interface WorkspaceAccess {
  has_active_subscription: boolean;
  subscription_state: string;
  plan_name: string | null;
  user_limit: number | null;
  active_users: number;
  seats_over_limit: boolean;
  users_to_deactivate: number;
}

export async function loadMembership(userId: string): Promise<Membership | null> {
  const list = await rows<Membership>(
    supabase.from("app_users").select("id,company_id,name,email,role,status").eq("id", userId).limit(1),
  );
  return list[0] ?? null;
}

export async function loadCompany(companyId: string): Promise<Company | null> {
  const list = await rows<Company>(
    supabase.from("companies").select("id,name,trade,currency_code,country_code").eq("id", companyId).limit(1),
  );
  return list[0] ?? null;
}

export async function loadWorkspaceAccess(): Promise<WorkspaceAccess | null> {
  const data = await rpc<WorkspaceAccess[]>("company_workspace_access");
  return data?.[0] ?? null;
}

// ---------------------------------------------------------------------------
// Jobs
// ---------------------------------------------------------------------------

export const ADDRESS_COLUMNS = "id,customer_id,line1,city,state,postal_code,latitude,longitude,access_notes";

export async function fieldWorkers(): Promise<AppUser[]> {
  const list = await rows<AppUser>(
    supabase.from("app_users").select("id,name,phone,role,status").eq("role", "fieldWorker").eq("status", "active"),
  );
  return list.sort((a, b) => a.name.localeCompare(b.name));
}

export async function usersById(ids: string[]): Promise<Map<string, AppUser>> {
  const list = await inIds<AppUser>("app_users", "id,name,phone,role,status", "id", ids);
  return new Map(list.map((u) => [u.id, u]));
}

async function decorate(jobs: JobRow[]): Promise<JobView[]> {
  const jobIds = jobs.map((j) => j.id);
  const [customers, addresses, assignments] = await Promise.all([
    inIds<Customer>("customers", "id,name,type", "id", jobs.map((j) => j.customer_id)),
    inIds<Address>("addresses", ADDRESS_COLUMNS, "id", jobs.map((j) => j.address_id)),
    inIds<{ job_id: string; user_id: string; is_primary: boolean }>(
      "field_worker_assignments",
      "job_id,user_id,is_primary",
      "job_id",
      jobIds,
    ),
  ]);
  const byJob = new Map<string, string>();
  assignments.filter((a) => a.is_primary).forEach((a) => byJob.set(a.job_id, a.user_id));
  const users = await usersById(Array.from(byJob.values()));
  const c = new Map(customers.map((x) => [x.id, x]));
  const a = new Map(addresses.map((x) => [x.id, x]));
  return jobs.map((job) => {
    const workerId = byJob.get(job.id);
    return {
      ...job,
      customer: c.get(job.customer_id),
      address: a.get(job.address_id),
      workerId,
      worker: workerId ? users.get(workerId) : undefined,
    };
  });
}

/** Every job RLS lets this person see, with customer, site and assignee. */
export async function allJobs(): Promise<JobView[]> {
  const list = await rows<JobRow>(supabase.from("jobs").select(JOB_COLUMNS).order("created_at", { ascending: false }));
  return decorate(list);
}

export interface JobNote {
  id: string;
  user_id: string | null;
  body: string;
  visibility: NoteVisibility;
  created_at: string;
  author?: string;
}

export interface JobPhoto {
  id: string;
  user_id: string | null;
  storage_reference: string;
  caption: string | null;
  kind: string;
  captured_at: string;
  url: string | null;
  simulated: boolean;
  author?: string;
}

export interface HistoryRow {
  id: string;
  from_status: JobStatus | null;
  to_status: JobStatus;
  changed_by_user_id: string | null;
  changed_at: string;
  latitude: number | null;
  longitude: number | null;
  by?: string;
}

export interface Equipment {
  id: string;
  make: string;
  model: string;
  serial_number: string;
  category: string;
}

export interface SiteContact {
  name: string;
  contact_role: string | null;
  phone: string | null;
}

export interface JobDetail {
  job: JobView;
  notes: JobNote[];
  photos: JobPhoto[];
  history: HistoryRow[];
  contact?: SiteContact;
  equipment?: Equipment;
}

async function mediaUrl(reference: string): Promise<{ url: string | null; simulated: boolean }> {
  if (reference.startsWith("sim://")) return { url: null, simulated: true };
  if (reference.startsWith("data:")) return { url: reference, simulated: false };
  if (reference.startsWith("storage://")) {
    const rest = reference.slice("storage://".length);
    const slash = rest.indexOf("/");
    if (slash > 0) {
      const { data } = await supabase.storage.from(rest.slice(0, slash)).createSignedUrl(rest.slice(slash + 1), 3600);
      return { url: data?.signedUrl ?? null, simulated: false };
    }
  }
  return { url: null, simulated: false };
}

export async function jobDetail(jobId: string, canSeeNotes: boolean, canSeePhotos: boolean): Promise<JobDetail> {
  const list = await rows<JobRow>(supabase.from("jobs").select(JOB_COLUMNS).eq("id", jobId).limit(1));
  if (!list[0]) throw new AppError("That job couldn't be found.");
  const [job] = await decorate(list);

  const [notes, photos, history, contacts, equipment] = await Promise.all([
    canSeeNotes
      ? rows<JobNote>(
          supabase
            .from("job_notes")
            .select("id,user_id,body,visibility,created_at")
            .eq("job_id", jobId)
            .order("created_at", { ascending: false }),
        )
      : Promise.resolve([] as JobNote[]),
    canSeePhotos
      ? rows<Omit<JobPhoto, "url" | "simulated">>(
          supabase
            .from("job_photos")
            .select("id,user_id,storage_reference,caption,kind,captured_at")
            .eq("job_id", jobId)
            .order("captured_at", { ascending: true }),
        )
      : Promise.resolve([]),
    rows<HistoryRow>(
      supabase
        .from("job_status_history")
        .select("id,from_status,to_status,changed_by_user_id,changed_at,latitude,longitude")
        .eq("job_id", jobId)
        .order("changed_at", { ascending: true }),
    ).catch(() => [] as HistoryRow[]),
    rows<SiteContact & { customer_id: string }>(
      supabase.from("site_contacts_operational").select("customer_id,name,contact_role,phone").eq("customer_id", job.customer_id),
    ).catch(() => []),
    job.equipment_id
      ? rows<Equipment>(
          supabase.from("equipment").select("id,make,model,serial_number,category").eq("id", job.equipment_id),
        ).catch(() => [] as Equipment[])
      : Promise.resolve([] as Equipment[]),
  ]);

  const people = await usersById([
    ...notes.map((n) => n.user_id ?? ""),
    ...photos.map((p) => p.user_id ?? ""),
    ...history.map((h) => h.changed_by_user_id ?? ""),
  ]);

  const resolvedPhotos = await Promise.all(
    photos.map(async (p) => ({
      ...p,
      ...(await mediaUrl(p.storage_reference)),
      author: p.user_id ? people.get(p.user_id)?.name : undefined,
    })),
  );

  return {
    job,
    notes: notes.map((n) => ({ ...n, author: n.user_id ? people.get(n.user_id)?.name : undefined })),
    photos: resolvedPhotos,
    history: history.map((h) => ({ ...h, by: h.changed_by_user_id ? people.get(h.changed_by_user_id)?.name : undefined })),
    contact: contacts[0],
    equipment: equipment[0],
  };
}

// ---------------------------------------------------------------------------
// Clash rule — identical to the iPhone app's conflictRows. The database applies
// it again on every assignment and reschedule.
// ---------------------------------------------------------------------------

export function clashesFor(
  job: Pick<JobRow, "id" | "scheduled_start" | "scheduled_end">,
  workerId: string | undefined,
  jobs: JobView[],
  override?: { start: string | null; end: string | null },
): Clash[] {
  if (!workerId) return [];
  const candidate = slot(override ? { scheduled_start: override.start, scheduled_end: override.end } : job);
  if (!candidate) return [];
  return jobs
    .filter((other) => {
      if (other.id === job.id || other.workerId !== workerId || !isOpen(other.status)) return false;
      const s = slot(other);
      return !!s && candidate[0] < s[1] && s[0] < candidate[1];
    })
    .sort((a, b) => (a.scheduled_start ?? "").localeCompare(b.scheduled_start ?? ""))
    .map((other) => ({
      jobId: other.id,
      number: other.number,
      title: other.title,
      range: timeRange(other.scheduled_start, other.scheduled_end),
    }));
}

// ---------------------------------------------------------------------------
// Writes — the same database functions the iPhone app calls.
// ---------------------------------------------------------------------------

export interface NewJobInput {
  customerId: string;
  addressId: string;
  title: string;
  description: string;
  kind: JobKind;
  priority: JobPriority;
  start: string | null;
  end: string | null;
  workerId: string | null;
}

export async function createJob(input: NewJobInput): Promise<string> {
  return rpc<string>("create_job", {
    p_customer_id: input.customerId,
    p_address_id: input.addressId,
    p_title: input.title,
    p_job_description: input.description,
    p_kind: input.kind,
    p_priority: input.priority,
    p_scheduled_start: input.start,
    p_scheduled_end: input.end,
    p_equipment_id: null,
    p_quote_id: null,
    p_field_worker_user_id: input.workerId,
  });
}

export async function updateJobStatus(jobId: string, to: JobStatus) {
  await rpc("update_job_status", { p_job: jobId, p_to: to, p_latitude: null, p_longitude: null });
}

export async function assignJob(jobId: string, workerId: string | null, acknowledgesConflict: boolean) {
  await rpc("assign_job", { p_job: jobId, p_worker: workerId, p_acknowledges_conflict: acknowledgesConflict });
}

export async function rescheduleJob(jobId: string, start: string | null, end: string | null, acknowledgesConflict: boolean) {
  if (start && end && new Date(end) < new Date(start)) throw new AppError("A job can't finish before it starts.");
  await rpc("reschedule_job", { p_job: jobId, p_start: start, p_end: end, p_acknowledges_conflict: acknowledgesConflict });
}

export async function addJobNote(companyId: string, userId: string, jobId: string, body: string, visibility: NoteVisibility) {
  const trimmed = body.trim();
  if (!trimmed) throw new AppError("Write something before saving the note.");
  const { error } = await supabase.from("job_notes").insert({
    id: crypto.randomUUID(),
    company_id: companyId,
    job_id: jobId,
    user_id: userId,
    body: trimmed,
    visibility,
    created_at: new Date().toISOString(),
  });
  if (error) throw translate(error);
}

// ---------------------------------------------------------------------------
// Customers (for raising a job)
// ---------------------------------------------------------------------------

export async function customers(): Promise<Customer[]> {
  const list = await rows<Customer>(supabase.from("customers").select("id,name,type"));
  return list.sort((a, b) => a.name.localeCompare(b.name));
}

export async function customerAddresses(customerId: string): Promise<Address[]> {
  return rows<Address>(supabase.from("addresses").select(ADDRESS_COLUMNS).eq("customer_id", customerId));
}

// ---------------------------------------------------------------------------
// Money at a glance (only for roles RLS lets read it)
// ---------------------------------------------------------------------------

export interface MoneySnapshot {
  quotesOut: number | null;
  outstanding: number | null;
  overdue: number | null;
  overdueCount: number;
  paid30: number | null;
}

interface InvoiceMoney {
  status: string;
  due_date: string;
  total: string | null;
  balance: string | null;
  paid_at: string | null;
}

export async function moneySnapshot(canQuotes: boolean, canInvoices: boolean): Promise<MoneySnapshot> {
  const snapshot: MoneySnapshot = { quotesOut: null, outstanding: null, overdue: null, overdueCount: 0, paid30: null };
  const num = (v: string | null) => (v ? Number(v) || 0 : 0);

  if (canQuotes) {
    const quotes = await rows<{ total: string | null }>(
      supabase.from("quotes").select("total::text").in("status", ["sent", "viewed"]),
    );
    snapshot.quotesOut = quotes.reduce((s, q) => s + num(q.total), 0);
  }
  if (canInvoices) {
    const invoices = await rows<InvoiceMoney>(
      supabase.from("invoices").select("status,due_date,total::text,balance::text,paid_at"),
    );
    const now = Date.now();
    const issued = (s: string) => !["draft", "void"].includes(s);
    const settled = (s: string) => ["paid", "void"].includes(s);
    const receivable = invoices.filter((i) => issued(i.status) && !settled(i.status) && num(i.balance) > 0);
    const overdue = receivable.filter((i) => new Date(i.due_date).getTime() < now);
    const since = now - 30 * 86400_000;
    snapshot.outstanding = receivable.reduce((s, i) => s + num(i.balance), 0);
    snapshot.overdue = overdue.reduce((s, i) => s + num(i.balance), 0);
    snapshot.overdueCount = overdue.length;
    snapshot.paid30 = invoices
      .filter((i) => i.paid_at && new Date(i.paid_at).getTime() >= since)
      .reduce((s, i) => s + num(i.total), 0);
  }
  return snapshot;
}

// ---------------------------------------------------------------------------
// Live positions
// ---------------------------------------------------------------------------

export interface WorkerPosition {
  id: string;
  user_id: string;
  latitude: number;
  longitude: number;
  accuracy_meters: number | null;
  speed_meters_per_second: number | null;
  job_id: string | null;
  recorded_at: string;
  is_simulated: boolean;
  name: string;
  recent: boolean;
}

/** Positions count as recent for 15 minutes, as on the iPhone app. */
export const RECENT_MINUTES = 15;

export async function latestPositions(): Promise<WorkerPosition[]> {
  const list = await rows<Omit<WorkerPosition, "name" | "recent">>(
    supabase
      .from("field_worker_locations")
      .select("id,user_id,latitude,longitude,accuracy_meters,speed_meters_per_second,job_id,recorded_at,is_simulated")
      .order("recorded_at", { ascending: false })
      .limit(400),
  );
  const latest = new Map<string, (typeof list)[number]>();
  for (const row of list) if (!latest.has(row.user_id)) latest.set(row.user_id, row);
  const people = await usersById(Array.from(latest.keys()));
  return Array.from(latest.values()).map((p) => ({
    ...p,
    name: people.get(p.user_id)?.name ?? "Team member",
    recent: Date.now() - new Date(p.recorded_at).getTime() <= RECENT_MINUTES * 60_000,
  }));
}
