/**
 * Customers, quotes and invoices — the same tables and database functions the
 * iPhone app uses, so both apps always show the same records and rules.
 */
import { supabase } from "./supabase";
import { AppError, inIds, rows, rpc, translate } from "./api";
import type { Tone } from "./domain";

const num = (v: string | number | null | undefined) => (v == null || v === "" ? 0 : Number(v) || 0);
const tidy = (s: string) => s.trim().replace(/\s+/g, " ");
const blankToNull = (s: string) => (s.trim() ? s.trim() : null);
const nowIso = () => new Date().toISOString();

// ---------------------------------------------------------------------------
// Customers
// ---------------------------------------------------------------------------

export type CustomerType = "residential" | "commercial" | "propertyManagement" | "other";

export const CUSTOMER_TYPE_TITLE: Record<CustomerType, string> = {
  residential: "Residential",
  commercial: "Commercial",
  propertyManagement: "Property management",
  other: "Other",
};

export const BILLING_TERMS = ["Due on receipt", "Net 7", "Net 14", "Net 15", "Net 30", "Net 45", "Net 60"];

export interface CustomerRecord {
  id: string;
  name: string;
  type: CustomerType;
  billing_terms: string;
  notes: string | null;
  status: string;
  created_at: string;
}

export interface Site {
  id: string;
  customer_id: string;
  line1: string;
  line2: string | null;
  city: string;
  state: string;
  postal_code: string;
  access_notes: string | null;
  latitude: number | null;
  longitude: number | null;
  created_at: string;
}

export interface Contact {
  id: string;
  customer_id: string;
  name: string;
  contact_role: string;
  phone: string;
  email: string | null;
  is_primary: boolean;
  is_billing_contact: boolean;
}

export interface EquipmentUnit {
  id: string;
  address_id: string;
  category: string;
  make: string;
  model: string;
  serial_number: string;
  installed_on: string | null;
}

const CUSTOMER_COLUMNS = "id,name,type,billing_terms,notes,status,created_at";
const SITE_COLUMNS = "id,customer_id,line1,line2,city,state,postal_code,access_notes,latitude,longitude,created_at";
const CONTACT_COLUMNS = "id,customer_id,name,contact_role,phone,email,is_primary,is_billing_contact";

export const siteLine = (s?: Pick<Site, "line1" | "line2" | "city" | "state" | "postal_code"> | null) =>
  s ? [s.line1, s.line2, s.city, [s.state, s.postal_code].filter(Boolean).join(" ")].filter(Boolean).join(", ") : "";

export async function customerList(): Promise<CustomerRecord[]> {
  const list = await rows<CustomerRecord>(supabase.from("customers").select(CUSTOMER_COLUMNS));
  return list.sort((a, b) => a.name.localeCompare(b.name));
}

export async function allSites(): Promise<Site[]> {
  return rows<Site>(supabase.from("addresses").select(SITE_COLUMNS));
}

export interface CustomerDetail {
  customer: CustomerRecord;
  sites: Site[];
  contacts: Contact[];
  equipment: EquipmentUnit[];
}

export async function customerDetail(id: string, canEquipment: boolean): Promise<CustomerDetail> {
  const list = await rows<CustomerRecord>(supabase.from("customers").select(CUSTOMER_COLUMNS).eq("id", id).limit(1));
  const customer = list[0];
  if (!customer) throw new AppError("That customer couldn't be found.");
  const [sites, contacts] = await Promise.all([
    rows<Site>(supabase.from("addresses").select(SITE_COLUMNS).eq("customer_id", id)),
    rows<Contact>(supabase.from("customer_contacts").select(CONTACT_COLUMNS).eq("customer_id", id)).catch(() => [] as Contact[]),
  ]);
  sites.sort((a, b) => a.created_at.localeCompare(b.created_at));
  contacts.sort((a, b) => Number(b.is_primary) - Number(a.is_primary) || a.name.localeCompare(b.name));
  const equipment = canEquipment
    ? await inIds<EquipmentUnit>(
        "equipment",
        "id,address_id,category,make,model,serial_number,installed_on",
        "address_id",
        sites.map((s) => s.id),
      ).catch(() => [] as EquipmentUnit[])
    : [];
  return { customer, sites, contacts, equipment };
}

export interface CustomerDraft {
  name: string;
  type: CustomerType;
  billingTerms: string;
  notes: string;
}

export interface SiteDraft {
  line1: string;
  line2: string;
  city: string;
  state: string;
  postalCode: string;
  accessNotes: string;
}

export interface ContactDraft {
  name: string;
  role: string;
  phone: string;
  email: string;
  isPrimary: boolean;
  isBilling: boolean;
}

export const emptySite = (): SiteDraft => ({ line1: "", line2: "", city: "", state: "", postalCode: "", accessNotes: "" });
export const emptyContact = (): ContactDraft => ({ name: "", role: "", phone: "", email: "", isPrimary: false, isBilling: false });

function siteProblem(d: SiteDraft): string | null {
  if (!d.line1.trim()) return "Enter the first line of the address.";
  if (!d.city.trim()) return "Enter the town or city.";
  return null;
}

function contactProblem(d: ContactDraft): string | null {
  if (!d.name.trim()) return "Enter the contact's name.";
  if (d.email.trim() && !/^\S+@\S+\.\S+$/.test(d.email.trim())) return "That email address doesn't look right.";
  return null;
}

async function write(query: PromiseLike<{ error: import("@supabase/supabase-js").PostgrestError | null }>) {
  const { error } = await query;
  if (error) throw translate(error);
}

/** Customer, first site and primary contact — the same three writes the iPhone app makes. */
export async function createCustomer(
  companyId: string,
  draft: CustomerDraft,
  site: SiteDraft,
  contact: Pick<ContactDraft, "name" | "phone" | "email">,
): Promise<string> {
  if (!draft.name.trim()) throw new AppError("Enter the customer's name.");
  const problem = siteProblem(site);
  if (problem) throw new AppError(problem);
  const contactDraft: ContactDraft = {
    ...emptyContact(),
    name: contact.name.trim() || draft.name,
    phone: contact.phone,
    email: contact.email,
    isPrimary: true,
    isBilling: true,
  };
  const cProblem = contactProblem(contactDraft);
  if (cProblem) throw new AppError(cProblem);

  const id = crypto.randomUUID();
  const now = nowIso();
  await write(
    supabase.from("customers").insert({
      id,
      company_id: companyId,
      name: tidy(draft.name),
      type: draft.type,
      billing_terms: draft.billingTerms.trim() || "Net 30",
      notes: blankToNull(draft.notes),
      created_at: now,
      updated_at: now,
    }),
  );
  try {
    await saveSite(companyId, id, null, site);
    await saveContact(companyId, id, null, contactDraft);
  } catch (err) {
    await supabase.from("customer_contacts").delete().eq("customer_id", id);
    await supabase.from("addresses").delete().eq("customer_id", id);
    await supabase.from("customers").delete().eq("id", id);
    throw err;
  }
  return id;
}

export async function updateCustomer(id: string, draft: CustomerDraft) {
  if (!draft.name.trim()) throw new AppError("Enter the customer's name.");
  await write(
    supabase
      .from("customers")
      .update({
        name: tidy(draft.name),
        type: draft.type,
        billing_terms: draft.billingTerms.trim() || "Net 30",
        notes: blankToNull(draft.notes),
        updated_at: nowIso(),
      })
      .eq("id", id),
  );
}

/** Only customers with no jobs, quotes or invoices can be deleted, as on the iPhone. */
export async function deleteCustomer(id: string) {
  const [jobs, quotes, invoices] = await Promise.all(
    ["jobs", "quotes_operational", "invoices"].map((t) =>
      supabase.from(t).select("id", { count: "exact", head: true }).eq("customer_id", id),
    ),
  );
  if ((jobs.count ?? 0) > 0) throw new AppError("This customer has job history, so it can't be deleted.");
  if ((quotes.count ?? 0) > 0) throw new AppError("This customer has quotes, so it can't be deleted.");
  if ((invoices.count ?? 0) > 0) throw new AppError("This customer has invoices, so it can't be deleted.");
  const sites = await rows<{ id: string }>(supabase.from("addresses").select("id").eq("customer_id", id));
  if (sites.length) await write(supabase.from("equipment").delete().in("address_id", sites.map((s) => s.id)));
  await write(supabase.from("customer_contacts").delete().eq("customer_id", id));
  await write(supabase.from("addresses").delete().eq("customer_id", id));
  await write(supabase.from("customers").delete().eq("id", id));
}

export async function saveSite(companyId: string, customerId: string, siteId: string | null, d: SiteDraft): Promise<string> {
  const problem = siteProblem(d);
  if (problem) throw new AppError(problem);
  const fields = {
    line1: tidy(d.line1),
    line2: blankToNull(d.line2),
    city: tidy(d.city),
    state: d.state.trim(),
    postal_code: d.postalCode.trim(),
    access_notes: blankToNull(d.accessNotes),
    updated_at: nowIso(),
  };
  if (siteId) {
    await write(supabase.from("addresses").update(fields).eq("id", siteId));
    return siteId;
  }
  const id = crypto.randomUUID();
  // Zero means "no position recorded", exactly as the iPhone app writes it.
  await write(
    supabase.from("addresses").insert({
      ...fields,
      id,
      company_id: companyId,
      customer_id: customerId,
      latitude: 0,
      longitude: 0,
      created_at: fields.updated_at,
    }),
  );
  return id;
}

export async function deleteSite(siteId: string) {
  const [jobs, quotes] = await Promise.all(
    ["jobs", "quotes_operational"].map((t) =>
      supabase.from(t).select("id", { count: "exact", head: true }).eq("address_id", siteId),
    ),
  );
  if ((jobs.count ?? 0) > 0 || (quotes.count ?? 0) > 0) throw new AppError("This site has jobs or quotes, so it can't be removed.");
  await write(supabase.from("equipment").delete().eq("address_id", siteId));
  await write(supabase.from("addresses").delete().eq("id", siteId));
}

export async function saveContact(companyId: string, customerId: string, contactId: string | null, d: ContactDraft): Promise<string> {
  const problem = contactProblem(d);
  if (problem) throw new AppError(problem);
  // Only one primary and one billing contact per customer.
  if (d.isPrimary) {
    await write(supabase.from("customer_contacts").update({ is_primary: false }).eq("customer_id", customerId).neq("id", contactId ?? ""));
  }
  if (d.isBilling) {
    await write(
      supabase.from("customer_contacts").update({ is_billing_contact: false }).eq("customer_id", customerId).neq("id", contactId ?? ""),
    );
  }
  const fields = {
    name: tidy(d.name),
    contact_role: d.role.trim() || "Contact",
    phone: d.phone.trim(),
    email: blankToNull(d.email),
    is_primary: d.isPrimary,
    is_billing_contact: d.isBilling,
    updated_at: nowIso(),
  };
  if (contactId) {
    await write(supabase.from("customer_contacts").update(fields).eq("id", contactId));
    return contactId;
  }
  const id = crypto.randomUUID();
  await write(
    supabase.from("customer_contacts").insert({ ...fields, id, company_id: companyId, customer_id: customerId, created_at: fields.updated_at }),
  );
  return id;
}

export async function deleteContact(contactId: string) {
  await write(supabase.from("customer_contacts").delete().eq("id", contactId));
}

// ---------------------------------------------------------------------------
// Line items (shared by quotes and invoices)
// ---------------------------------------------------------------------------

export interface LineItem {
  id: string;
  item_description: string;
  quantity: number;
  unit_price: number;
  /** A fraction: 0.08 is 8%. */
  tax_rate: number;
  line_total: number;
  sort_order: number;
}

type RawLine = Record<keyof LineItem, string>;
const LINE_COLUMNS = "id,item_description,quantity::text,unit_price::text,tax_rate::text,line_total::text,sort_order";
const toLine = (r: RawLine): LineItem => ({
  id: r.id,
  item_description: r.item_description,
  quantity: num(r.quantity),
  unit_price: num(r.unit_price),
  tax_rate: num(r.tax_rate),
  line_total: num(r.line_total),
  sort_order: Number(r.sort_order) || 0,
});

export interface LineDraft {
  description: string;
  quantity: string;
  unitPrice: string;
  /** Percent as typed, e.g. "8". */
  taxPercent: string;
}

function lineParams(d: LineDraft) {
  const quantity = Number(d.quantity);
  const unit = Number(d.unitPrice);
  const tax = Number(d.taxPercent || "0");
  if (!d.description.trim()) throw new AppError("Describe the line item before saving.");
  if (!Number.isFinite(quantity) || quantity <= 0) throw new AppError("Quantity must be greater than zero.");
  if (!Number.isFinite(unit) || unit < 0) throw new AppError("Unit price can't be negative.");
  if (!Number.isFinite(tax) || tax < 0 || tax > 100) throw new AppError("Tax must be between 0% and 100%.");
  return {
    p_description: d.description.trim(),
    p_quantity: String(quantity),
    p_unit_price: String(Math.round(unit * 100) / 100),
    p_tax_rate: String(Math.round(tax * 10000) / 1000000),
  };
}

// ---------------------------------------------------------------------------
// Quotes
// ---------------------------------------------------------------------------

export type QuoteStatus = "draft" | "sent" | "viewed" | "accepted" | "declined" | "expired";

export const QUOTE_STATUS: Record<QuoteStatus, { title: string; tone: Tone }> = {
  draft: { title: "Draft", tone: "neutral" },
  sent: { title: "Sent", tone: "info" },
  viewed: { title: "Viewed", tone: "info" },
  accepted: { title: "Accepted", tone: "success" },
  declined: { title: "Declined", tone: "danger" },
  expired: { title: "Expired", tone: "warning" },
};

export interface Quote {
  id: string;
  customer_id: string;
  address_id: string;
  number: string;
  title: string;
  scope_of_work: string;
  status: QuoteStatus;
  /** Null when this role can't see quote money. */
  subtotal: number | null;
  tax: number | null;
  total: number | null;
  valid_until: string | null;
  created_at: string;
  sent_at: string | null;
  viewed_at: string | null;
  accepted_at: string | null;
  declined_at: string | null;
  converted_job_id: string | null;
}

const QUOTE_BASE =
  "id,customer_id,address_id,number,title,scope_of_work,status,valid_until,created_at,sent_at,viewed_at,accepted_at,declined_at,converted_job_id";

type RawQuote = Omit<Quote, "subtotal" | "tax" | "total"> & { subtotal?: string; tax?: string; total?: string };
const toQuote = (r: RawQuote, financial: boolean): Quote => ({
  ...r,
  subtotal: financial ? num(r.subtotal) : null,
  tax: financial ? num(r.tax) : null,
  total: financial ? num(r.total) : null,
});

export async function quoteList(financial: boolean): Promise<Quote[]> {
  const list = financial
    ? await rows<RawQuote>(supabase.from("quotes").select(`${QUOTE_BASE},subtotal::text,tax::text,total::text`))
    : await rows<RawQuote>(supabase.from("quotes_operational").select(QUOTE_BASE));
  return list.map((r) => toQuote(r, financial)).sort((a, b) => b.created_at.localeCompare(a.created_at));
}

export interface QuoteDetail {
  quote: Quote;
  lines: LineItem[];
}

export async function quoteDetail(id: string, financial: boolean): Promise<QuoteDetail> {
  const list = financial
    ? await rows<RawQuote>(supabase.from("quotes").select(`${QUOTE_BASE},subtotal::text,tax::text,total::text`).eq("id", id).limit(1))
    : await rows<RawQuote>(supabase.from("quotes_operational").select(QUOTE_BASE).eq("id", id).limit(1));
  if (!list[0]) throw new AppError("That quote couldn't be found.");
  const lines = financial
    ? (await rows<RawLine>(supabase.from("quote_line_items").select(LINE_COLUMNS).eq("quote_id", id))).map(toLine)
    : [];
  return { quote: toQuote(list[0], financial), lines: lines.sort((a, b) => a.sort_order - b.sort_order) };
}

export async function createQuote(input: {
  customerId: string;
  addressId: string;
  title: string;
  scope: string;
  validUntil: string | null;
}): Promise<string> {
  if (!input.title.trim()) throw new AppError("Give the quote a title.");
  return rpc<string>("create_quote", {
    p_customer_id: input.customerId,
    p_address_id: input.addressId,
    p_title: input.title.trim(),
    p_scope_of_work: input.scope.trim(),
    p_valid_until: input.validUntil || null,
  });
}

export const saveQuoteLine = (quoteId: string, lineId: string | null, d: LineDraft) =>
  rpc("save_quote_line_item", { p_quote: quoteId, p_line: lineId, ...lineParams(d) });

export const deleteQuoteLine = (quoteId: string, lineId: string) => rpc("delete_quote_line_item", { p_quote: quoteId, p_line: lineId });

export const setQuoteStatus = (quoteId: string, to: QuoteStatus) => rpc("update_quote_status", { p_quote: quoteId, p_to: to });

export const convertQuoteToJob = (
  quoteId: string,
  kind: string,
  priority: string,
  start: string | null,
  end: string | null,
  workerId: string | null,
) =>
  rpc<string>("convert_quote_to_job", {
    p_quote: quoteId,
    p_kind: kind,
    p_priority: priority,
    p_scheduled_start: start,
    p_scheduled_end: end,
    p_field_worker_user_id: workerId,
  });

/** The quote moves the iPhone app allows, mirrored from update_quote_status. */
export function quoteActions(status: QuoteStatus): { to: QuoteStatus; label: string; destructive?: boolean }[] {
  switch (status) {
    case "draft":
      return [{ to: "sent", label: "Mark as sent" }];
    case "sent":
    case "viewed":
      return [
        { to: "accepted", label: "Mark accepted" },
        { to: "declined", label: "Mark declined", destructive: true },
        { to: "expired", label: "Mark expired" },
      ];
    case "expired":
      return [{ to: "sent", label: "Re-send" }];
    default:
      return [];
  }
}

// ---------------------------------------------------------------------------
// Invoices
// ---------------------------------------------------------------------------

export type InvoiceStatus = "draft" | "sent" | "viewed" | "partPaid" | "paid" | "overdue" | "void";

export const INVOICE_STATUS: Record<InvoiceStatus, { title: string; tone: Tone }> = {
  draft: { title: "Draft", tone: "neutral" },
  sent: { title: "Sent", tone: "info" },
  viewed: { title: "Viewed", tone: "info" },
  partPaid: { title: "Part paid", tone: "warning" },
  paid: { title: "Paid", tone: "success" },
  overdue: { title: "Overdue", tone: "danger" },
  void: { title: "Void", tone: "neutral" },
};

export interface Invoice {
  id: string;
  customer_id: string;
  billing_contact_id: string | null;
  address_id: string | null;
  job_id: string | null;
  quote_id: string | null;
  number: string;
  title: string;
  scope_of_work: string;
  status: InvoiceStatus;
  currency_code: string;
  payment_terms_label: string;
  issue_date: string;
  due_date: string;
  subtotal: number;
  tax: number;
  total: number;
  amount_paid: number;
  balance: number;
  sent_at: string | null;
  viewed_at: string | null;
  paid_at: string | null;
  voided_at: string | null;
  created_at: string;
}

const INVOICE_COLUMNS =
  "id,customer_id,billing_contact_id,address_id,job_id,quote_id,number,title,scope_of_work,status,currency_code,payment_terms_label,issue_date,due_date,subtotal::text,tax::text,total::text,amount_paid::text,balance::text,sent_at,viewed_at,paid_at,voided_at,created_at";

type RawInvoice = Omit<Invoice, "subtotal" | "tax" | "total" | "amount_paid" | "balance"> &
  Record<"subtotal" | "tax" | "total" | "amount_paid" | "balance", string>;

const toInvoice = (r: RawInvoice): Invoice => ({
  ...r,
  subtotal: num(r.subtotal),
  tax: num(r.tax),
  total: num(r.total),
  amount_paid: num(r.amount_paid),
  balance: num(r.balance),
});

/** Issued, unpaid and past its due date counts as overdue, even before the nightly sweep marks it. */
export function effectiveStatus(i: Pick<Invoice, "status" | "due_date" | "balance">): InvoiceStatus {
  if (["sent", "viewed", "partPaid"].includes(i.status) && i.balance > 0) {
    const due = new Date(`${i.due_date}T23:59:59`);
    if (due.getTime() < Date.now()) return "overdue";
  }
  return i.status;
}

export const isReceivable = (s: InvoiceStatus) => !["draft", "void", "paid"].includes(s);

export async function invoiceList(): Promise<Invoice[]> {
  const list = await rows<RawInvoice>(supabase.from("invoices").select(INVOICE_COLUMNS));
  return list.map(toInvoice).sort((a, b) => b.created_at.localeCompare(a.created_at));
}

export type PaymentMethod = "card" | "ach" | "cash" | "check" | "stripe";

export const PAYMENT_METHOD_TITLE: Record<PaymentMethod, string> = {
  card: "Card",
  ach: "Bank transfer",
  cash: "Cash",
  check: "Check",
  stripe: "Online card payment",
};

export interface Payment {
  id: string;
  amount: number;
  method: PaymentMethod;
  status: string;
  reference: string | null;
  note: string | null;
  received_at: string;
  paid_by_customer: boolean;
}

export interface InvoiceDetail {
  invoice: Invoice;
  lines: LineItem[];
  payments: Payment[];
  billingContact: Contact | null;
}

export async function invoiceDetail(id: string, canPayments: boolean): Promise<InvoiceDetail> {
  const list = await rows<RawInvoice>(supabase.from("invoices").select(INVOICE_COLUMNS).eq("id", id).limit(1));
  if (!list[0]) throw new AppError("That invoice couldn't be found.");
  const invoice = toInvoice(list[0]);
  const [lines, payments, contacts] = await Promise.all([
    rows<RawLine>(supabase.from("invoice_line_items").select(LINE_COLUMNS).eq("invoice_id", id)),
    canPayments
      ? rows<Omit<Payment, "amount"> & { amount: string }>(
          supabase
            .from("payments")
            .select("id,amount::text,method,status,reference,note,received_at,paid_by_customer")
            .eq("invoice_id", id)
            .order("received_at", { ascending: false }),
        ).catch(() => [])
      : Promise.resolve([]),
    rows<Contact>(supabase.from("customer_contacts").select(CONTACT_COLUMNS).eq("customer_id", invoice.customer_id)).catch(
      () => [] as Contact[],
    ),
  ]);
  const billingContact =
    contacts.find((c) => c.id === invoice.billing_contact_id) ??
    contacts.find((c) => c.is_billing_contact) ??
    contacts.find((c) => c.is_primary) ??
    null;
  return {
    invoice,
    lines: lines.map(toLine).sort((a, b) => a.sort_order - b.sort_order),
    payments: payments.map((p) => ({ ...p, amount: num(p.amount) })),
    billingContact,
  };
}

export async function createInvoice(input: { customerId: string; addressId: string | null; title: string; scope: string }) {
  return rpc<string>("create_invoice", {
    p_customer_id: input.customerId,
    p_address_id: input.addressId,
    p_title: input.title.trim(),
    p_scope_of_work: input.scope.trim(),
    p_payment_terms_label: null,
    p_issue_date: null,
    p_due_date: null,
  });
}

export const createInvoiceFromJob = (jobId: string) =>
  rpc<string>("create_invoice_from_job", {
    p_job: jobId,
    p_payment_terms_label: null,
    p_issue_date: null,
    p_due_date: null,
    p_copy_line_items: true,
    p_advance_job_status: true,
  });

export const createInvoiceFromQuote = (quoteId: string) =>
  rpc<string>("create_invoice_from_quote", {
    p_quote: quoteId,
    p_payment_terms_label: null,
    p_issue_date: null,
    p_due_date: null,
    p_copy_line_items: true,
    p_advance_job_status: true,
  });

export const saveInvoiceLine = (invoiceId: string, lineId: string | null, d: LineDraft) =>
  rpc("save_invoice_line_item", { p_invoice: invoiceId, p_line: lineId, ...lineParams(d) });

export const deleteInvoiceLine = (invoiceId: string, lineId: string) =>
  rpc("delete_invoice_line_item", { p_invoice: invoiceId, p_line: lineId });

export const setInvoiceStatus = (invoiceId: string, to: InvoiceStatus) =>
  rpc("update_invoice_status", { p_invoice: invoiceId, p_to: to });

export async function recordPayment(invoiceId: string, amount: string, method: PaymentMethod, receivedAt: string, reference: string, note: string) {
  const value = Number(amount);
  if (!Number.isFinite(value) || value <= 0) throw new AppError("Enter an amount greater than zero.");
  await rpc("record_payment", {
    p_invoice: invoiceId,
    p_amount: String(Math.round(value * 100) / 100),
    p_method: method,
    p_received_at: receivedAt ? new Date(receivedAt).toISOString() : nowIso(),
    p_reference: reference.trim() || null,
    p_note: note.trim() || null,
  });
}

const PAGE_BASE = ((import.meta.env.EXPO_PUBLIC_RORK_FUNCTIONS_URL as string | undefined) ?? "").replace(/\/+$/, "");

/** The customer-facing invoice page, where they can view and pay by card. */
export async function invoiceShareLink(invoiceId: string): Promise<string> {
  const token = await rpc<string>("issue_invoice_share_token", { p_invoice: invoiceId, p_rotate: false });
  if (!PAGE_BASE || !token) throw new AppError("The payment page isn't configured yet.");
  return `${PAGE_BASE}/i?t=${token}`;
}

export async function sendInvoiceEmail(invoiceId: string, email: string): Promise<string | null> {
  const { data, error } = await supabase.functions.invoke("send-invoice", {
    body: { invoiceId, channels: ["email"], email: email.trim() || undefined },
  });
  if (error) {
    let message = "The invoice couldn't be sent.";
    const ctx = (error as { context?: Response }).context;
    if (ctx && typeof ctx.json === "function") {
      const body = await ctx.json().catch(() => null);
      if (body?.message) message = String(body.message);
      else if (body?.error === "notPermitted") message = "Your role doesn't allow sending invoices.";
    }
    throw new AppError(message);
  }
  const result = data as { viewUrl?: string; results?: { channel: string; status: "sent" | "failed"; detail?: string }[] };
  const failed = result.results?.find((r) => r.status === "failed");
  if (failed) throw new AppError(failed.detail || "The email couldn't be delivered.");
  return result.viewUrl ?? null;
}
