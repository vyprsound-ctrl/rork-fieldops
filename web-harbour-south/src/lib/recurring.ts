import { addDays, format } from "date-fns";

import { supabase } from "./supabase";
import { AppError, rows, translate } from "./api";
import type { JobKind } from "./domain";

export type Frequency = "monthly" | "quarterly" | "semiAnnual" | "annual" | "custom";

export const FREQUENCIES: { id: Frequency; title: string; days: number | null }[] = [
  { id: "monthly", title: "Monthly", days: 30 },
  { id: "quarterly", title: "Every 3 months", days: 91 },
  { id: "semiAnnual", title: "Every 6 months", days: 182 },
  { id: "annual", title: "Every year", days: 365 },
  { id: "custom", title: "Custom interval", days: null },
];

export const frequencyTitle = (f: Frequency, interval: number | null) =>
  f === "custom" ? `Every ${interval ?? 0} day${interval === 1 ? "" : "s"}` : FREQUENCIES.find((x) => x.id === f)?.title ?? f;

export interface Agreement {
  id: string;
  customer_id: string;
  address_id: string;
  equipment_id: string | null;
  frequency: Frequency;
  interval_days: number | null;
  next_due_date: string;
  template_job_kind: JobKind;
  template_title: string;
  template_description: string;
  notes: string | null;
  is_active: boolean;
  lead_time_days: number;
  last_generated_job_id: string | null;
  last_generated_on: string | null;
  created_at: string;
}

const COLUMNS =
  "id,customer_id,address_id,equipment_id,frequency,interval_days,next_due_date,template_job_kind,template_title,template_description,notes,is_active,lead_time_days,last_generated_job_id,last_generated_on,created_at";

export async function agreements(): Promise<Agreement[]> {
  const list = await rows<Agreement>(supabase.from("service_agreements").select(COLUMNS));
  return list.sort((a, b) => Number(b.is_active) - Number(a.is_active) || a.next_due_date.localeCompare(b.next_due_date));
}

/** Due when the next visit falls inside its lead time (the server cron creates the job then). */
export function isDue(a: Pick<Agreement, "next_due_date" | "lead_time_days" | "is_active">) {
  if (!a.is_active) return false;
  const due = new Date(`${a.next_due_date}T12:00:00`).getTime();
  return due - Date.now() <= a.lead_time_days * 86_400_000;
}

export const isOverdue = (a: Pick<Agreement, "next_due_date" | "is_active">) =>
  a.is_active && new Date(`${a.next_due_date}T23:59:59`).getTime() < Date.now();

export interface AgreementDraft {
  id: string | null;
  customerId: string;
  addressId: string;
  equipmentId: string;
  frequency: Frequency;
  intervalDays: number;
  nextDueDate: string;
  kind: JobKind;
  title: string;
  description: string;
  notes: string;
  isActive: boolean;
}

export const emptyDraft = (): AgreementDraft => ({
  id: null,
  customerId: "",
  addressId: "",
  equipmentId: "",
  frequency: "semiAnnual",
  intervalDays: 90,
  nextDueDate: format(addDays(new Date(), 30), "yyyy-MM-dd"),
  kind: "maintenance",
  title: "",
  description: "",
  notes: "",
  isActive: true,
});

/** Loads every field so editing never wipes the address, kind or description. */
export const draftFrom = (a: Agreement): AgreementDraft => ({
  id: a.id,
  customerId: a.customer_id,
  addressId: a.address_id,
  equipmentId: a.equipment_id ?? "",
  frequency: a.frequency,
  intervalDays: a.interval_days ?? 90,
  nextDueDate: a.next_due_date,
  kind: a.template_job_kind,
  title: a.template_title,
  description: a.template_description,
  notes: a.notes ?? "",
  isActive: a.is_active,
});

export function validation(d: AgreementDraft): string | null {
  if (!d.customerId) return "Choose a customer.";
  if (!d.addressId) return "Choose which site this covers.";
  if (!d.title.trim()) return "Give the recurring visit a name.";
  if (d.frequency === "custom" && (!Number.isFinite(d.intervalDays) || d.intervalDays < 1)) {
    return "A custom interval needs at least one day.";
  }
  if (!d.nextDueDate) return "Choose when the next visit is due.";
  return null;
}

export async function saveAgreement(companyId: string, d: AgreementDraft): Promise<string> {
  const problem = validation(d);
  if (problem) throw new AppError(problem);
  const payload = {
    customer_id: d.customerId,
    address_id: d.addressId,
    equipment_id: d.equipmentId || null,
    frequency: d.frequency,
    interval_days: d.frequency === "custom" ? Math.round(d.intervalDays) : null,
    next_due_date: d.nextDueDate,
    is_active: d.isActive,
    template_title: d.title.trim(),
    template_description: d.description.trim(),
    template_job_kind: d.kind,
    notes: d.notes.trim() || null,
    updated_at: new Date().toISOString(),
  };
  if (d.id) {
    const { error } = await supabase.from("service_agreements").update(payload).eq("id", d.id);
    if (error) throw translate(error);
    return d.id;
  }
  const { data, error } = await supabase
    .from("service_agreements")
    .insert({ ...payload, company_id: companyId })
    .select("id")
    .single();
  if (error) throw translate(error);
  return (data as { id: string }).id;
}

export async function setAgreementActive(id: string, active: boolean) {
  const { error } = await supabase
    .from("service_agreements")
    .update({ is_active: active, updated_at: new Date().toISOString() })
    .eq("id", id);
  if (error) throw translate(error);
}

export async function deleteAgreement(id: string) {
  const { error } = await supabase.from("service_agreements").delete().eq("id", id);
  if (error) throw translate(error);
}
