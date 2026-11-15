import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { toast } from "sonner";

import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Switch } from "@/components/ui/switch";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import {
  BILLING_TERMS,
  CUSTOMER_TYPE_TITLE,
  PAYMENT_METHOD_TITLE,
  convertQuoteToJob,
  createCustomer,
  createInvoice,
  createQuote,
  emptyContact,
  emptySite,
  recordPayment,
  saveContact,
  saveSite,
  sendInvoiceEmail,
  updateCustomer,
  type Contact,
  type ContactDraft,
  type CustomerDraft,
  type CustomerRecord,
  type CustomerType,
  type Invoice,
  type PaymentMethod,
  type Quote,
  type Site,
  type SiteDraft,
} from "@/lib/crm";
import { customerAddresses } from "@/lib/api";
import { KIND_TITLE, addressLine, type JobKind, type JobPriority } from "@/lib/domain";
import { fromLocalInput, money2, toLocalInput } from "@/lib/format";
import { useCustomers, useRefreshCrm, useWorkers } from "@/lib/queries";
import { useWorkspace } from "@/lib/session";
import { Field } from "./crm";

const ORANGE = "bg-brand-orange hover:bg-brand-orange/90";

function useSaving() {
  const [saving, setSaving] = useState(false);
  const run = async (fn: () => Promise<void>) => {
    setSaving(true);
    try {
      await fn();
    } catch (err) {
      toast.error((err as Error).message);
    } finally {
      setSaving(false);
    }
  };
  return { saving, run };
}

function SiteFields({ value, onChange }: { value: SiteDraft; onChange: (v: SiteDraft) => void }) {
  const set = (k: keyof SiteDraft) => (e: React.ChangeEvent<HTMLInputElement | HTMLTextAreaElement>) =>
    onChange({ ...value, [k]: e.target.value });
  return (
    <div className="grid gap-3">
      <Field label="Address line 1">
        <Input value={value.line1} onChange={set("line1")} placeholder="24 Harbour Road" className="h-11" />
      </Field>
      <Field label="Address line 2 (optional)">
        <Input value={value.line2} onChange={set("line2")} placeholder="Unit 3" className="h-11" />
      </Field>
      <div className="grid grid-cols-[2fr_1fr_1fr] gap-3">
        <Field label="Town or city">
          <Input value={value.city} onChange={set("city")} className="h-11" />
        </Field>
        <Field label="State">
          <Input value={value.state} onChange={set("state")} className="h-11" />
        </Field>
        <Field label="ZIP / postcode">
          <Input value={value.postalCode} onChange={set("postalCode")} className="h-11" />
        </Field>
      </div>
      <Field label="Access notes (optional)">
        <Textarea value={value.accessNotes} onChange={set("accessNotes")} placeholder="Gate code, parking, pets…" rows={2} />
      </Field>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Customer
// ---------------------------------------------------------------------------

export function CustomerDialog({
  open,
  onOpenChange,
  existing,
}: {
  open: boolean;
  onOpenChange: (o: boolean) => void;
  existing?: CustomerRecord;
}) {
  const ws = useWorkspace();
  const refresh = useRefreshCrm();
  const navigate = useNavigate();
  const { saving, run } = useSaving();
  const [draft, setDraft] = useState<CustomerDraft>({ name: "", type: "residential", billingTerms: "Net 30", notes: "" });
  const [site, setSite] = useState<SiteDraft>(emptySite());
  const [contact, setContact] = useState({ name: "", phone: "", email: "" });

  useEffect(() => {
    if (!open) return;
    setDraft(
      existing
        ? { name: existing.name, type: existing.type, billingTerms: existing.billing_terms, notes: existing.notes ?? "" }
        : { name: "", type: "residential", billingTerms: "Net 30", notes: "" },
    );
    setSite(emptySite());
    setContact({ name: "", phone: "", email: "" });
  }, [open, existing]);

  const terms = BILLING_TERMS.includes(draft.billingTerms) ? BILLING_TERMS : [draft.billingTerms, ...BILLING_TERMS];

  const submit = () =>
    run(async () => {
      if (existing) {
        await updateCustomer(existing.id, draft);
        toast.success("Customer updated");
        refresh();
        onOpenChange(false);
      } else {
        const id = await createCustomer(ws.company.id, draft, site, contact);
        toast.success("Customer added");
        refresh();
        onOpenChange(false);
        navigate(`/customers/${id}`);
      }
    });

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-h-[92vh] overflow-y-auto sm:max-w-[620px] scroll-thin">
        <DialogHeader>
          <DialogTitle className="text-xl">{existing ? "Edit customer" : "New customer"}</DialogTitle>
          <DialogDescription>
            {existing ? "Changes show on the iPhone app straight away." : "Add the customer with their first site and main contact."}
          </DialogDescription>
        </DialogHeader>

        <div className="grid gap-4 py-2">
          <Field label="Customer name">
            <Input value={draft.name} onChange={(e) => setDraft({ ...draft, name: e.target.value })} placeholder="e.g. Marina Heights HOA" className="h-11" />
          </Field>
          <div className="grid grid-cols-2 gap-3">
            <Field label="Type">
              <Select value={draft.type} onValueChange={(v) => setDraft({ ...draft, type: v as CustomerType })}>
                <SelectTrigger className="h-11">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {(Object.keys(CUSTOMER_TYPE_TITLE) as CustomerType[]).map((t) => (
                    <SelectItem key={t} value={t}>
                      {CUSTOMER_TYPE_TITLE[t]}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </Field>
            <Field label="Payment terms">
              <Select value={draft.billingTerms} onValueChange={(v) => setDraft({ ...draft, billingTerms: v })}>
                <SelectTrigger className="h-11">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {terms.map((t) => (
                    <SelectItem key={t} value={t}>
                      {t}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </Field>
          </div>

          {!existing && (
            <>
              <p className="section-label -mb-1 pt-2">First site</p>
              <SiteFields value={site} onChange={setSite} />
              <p className="section-label -mb-1 pt-2">Main contact</p>
              <div className="grid grid-cols-3 gap-3">
                <Field label="Name">
                  <Input value={contact.name} onChange={(e) => setContact({ ...contact, name: e.target.value })} placeholder={draft.name || "Name"} className="h-11" />
                </Field>
                <Field label="Phone">
                  <Input type="tel" value={contact.phone} onChange={(e) => setContact({ ...contact, phone: e.target.value })} className="h-11" />
                </Field>
                <Field label="Email">
                  <Input type="email" value={contact.email} onChange={(e) => setContact({ ...contact, email: e.target.value })} className="h-11" />
                </Field>
              </div>
            </>
          )}

          <Field label="Notes (optional)">
            <Textarea value={draft.notes} onChange={(e) => setDraft({ ...draft, notes: e.target.value })} rows={2} />
          </Field>
        </div>

        <DialogFooter>
          <Button variant="ghost" onClick={() => onOpenChange(false)}>
            Cancel
          </Button>
          <Button disabled={saving || !draft.name.trim()} onClick={() => void submit()} className={ORANGE}>
            {saving ? "Saving…" : existing ? "Save changes" : "Add customer"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

export function SiteDialog({
  open,
  onOpenChange,
  customerId,
  existing,
}: {
  open: boolean;
  onOpenChange: (o: boolean) => void;
  customerId: string;
  existing?: Site;
}) {
  const ws = useWorkspace();
  const refresh = useRefreshCrm();
  const { saving, run } = useSaving();
  const [site, setSite] = useState<SiteDraft>(emptySite());

  useEffect(() => {
    if (!open) return;
    setSite(
      existing
        ? {
            line1: existing.line1,
            line2: existing.line2 ?? "",
            city: existing.city,
            state: existing.state,
            postalCode: existing.postal_code,
            accessNotes: existing.access_notes ?? "",
          }
        : emptySite(),
    );
  }, [open, existing]);

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-[560px]">
        <DialogHeader>
          <DialogTitle className="text-xl">{existing ? "Edit site" : "Add site"}</DialogTitle>
          <DialogDescription>Where the work happens. Engineers see this address on their iPhone.</DialogDescription>
        </DialogHeader>
        <SiteFields value={site} onChange={setSite} />
        <DialogFooter>
          <Button variant="ghost" onClick={() => onOpenChange(false)}>
            Cancel
          </Button>
          <Button
            disabled={saving}
            className={ORANGE}
            onClick={() =>
              void run(async () => {
                await saveSite(ws.company.id, customerId, existing?.id ?? null, site);
                toast.success(existing ? "Site updated" : "Site added");
                refresh();
                onOpenChange(false);
              })
            }
          >
            {saving ? "Saving…" : "Save site"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

export function ContactDialog({
  open,
  onOpenChange,
  customerId,
  existing,
}: {
  open: boolean;
  onOpenChange: (o: boolean) => void;
  customerId: string;
  existing?: Contact;
}) {
  const ws = useWorkspace();
  const refresh = useRefreshCrm();
  const { saving, run } = useSaving();
  const [d, setD] = useState<ContactDraft>(emptyContact());

  useEffect(() => {
    if (!open) return;
    setD(
      existing
        ? {
            name: existing.name,
            role: existing.contact_role,
            phone: existing.phone,
            email: existing.email ?? "",
            isPrimary: existing.is_primary,
            isBilling: existing.is_billing_contact,
          }
        : emptyContact(),
    );
  }, [open, existing]);

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-[520px]">
        <DialogHeader>
          <DialogTitle className="text-xl">{existing ? "Edit contact" : "Add contact"}</DialogTitle>
          <DialogDescription>The billing contact receives invoices by email.</DialogDescription>
        </DialogHeader>
        <div className="grid gap-3">
          <div className="grid grid-cols-2 gap-3">
            <Field label="Name">
              <Input value={d.name} onChange={(e) => setD({ ...d, name: e.target.value })} className="h-11" />
            </Field>
            <Field label="Role">
              <Input value={d.role} onChange={(e) => setD({ ...d, role: e.target.value })} placeholder="e.g. Property manager" className="h-11" />
            </Field>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <Field label="Phone">
              <Input type="tel" value={d.phone} onChange={(e) => setD({ ...d, phone: e.target.value })} className="h-11" />
            </Field>
            <Field label="Email">
              <Input type="email" value={d.email} onChange={(e) => setD({ ...d, email: e.target.value })} className="h-11" />
            </Field>
          </div>
          <label className="flex items-center justify-between rounded-xl bg-secondary px-4 py-3 text-sm font-medium">
            Main contact
            <Switch checked={d.isPrimary} onCheckedChange={(v) => setD({ ...d, isPrimary: v })} />
          </label>
          <label className="flex items-center justify-between rounded-xl bg-secondary px-4 py-3 text-sm font-medium">
            Billing contact (receives invoices)
            <Switch checked={d.isBilling} onCheckedChange={(v) => setD({ ...d, isBilling: v })} />
          </label>
        </div>
        <DialogFooter>
          <Button variant="ghost" onClick={() => onOpenChange(false)}>
            Cancel
          </Button>
          <Button
            disabled={saving}
            className={ORANGE}
            onClick={() =>
              void run(async () => {
                await saveContact(ws.company.id, customerId, existing?.id ?? null, d);
                toast.success(existing ? "Contact updated" : "Contact added");
                refresh();
                onOpenChange(false);
              })
            }
          >
            {saving ? "Saving…" : "Save contact"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

// ---------------------------------------------------------------------------
// Quotes and invoices
// ---------------------------------------------------------------------------

function CustomerSitePicker({
  customerId,
  setCustomerId,
  addressId,
  setAddressId,
  optionalSite,
  enabled,
}: {
  customerId: string;
  setCustomerId: (v: string) => void;
  addressId: string;
  setAddressId: (v: string) => void;
  optionalSite?: boolean;
  enabled: boolean;
}) {
  const customers = useCustomers();
  const sites = useQuery({
    queryKey: ["addresses", customerId],
    queryFn: () => customerAddresses(customerId),
    enabled: enabled && !!customerId,
  });

  useEffect(() => {
    const list = sites.data ?? [];
    if (list.length === 1) setAddressId(list[0].id);
    else if (!list.some((s) => s.id === addressId)) setAddressId(optionalSite ? "none" : "");
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [sites.data]);

  return (
    <div className="grid grid-cols-2 gap-3">
      <Field label="Customer">
        <Select value={customerId} onValueChange={setCustomerId}>
          <SelectTrigger className="h-11">
            <SelectValue placeholder={customers.isLoading ? "Loading…" : "Choose a customer"} />
          </SelectTrigger>
          <SelectContent className="max-h-72">
            {(customers.data ?? []).map((c) => (
              <SelectItem key={c.id} value={c.id}>
                {c.name}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </Field>
      <Field label={optionalSite ? "Site (optional)" : "Site"}>
        <Select value={addressId} onValueChange={setAddressId} disabled={!customerId}>
          <SelectTrigger className="h-11">
            <SelectValue placeholder={customerId ? (sites.data?.length === 0 ? "No sites on file" : "Choose a site") : "Pick a customer first"} />
          </SelectTrigger>
          <SelectContent>
            {optionalSite && <SelectItem value="none">No site</SelectItem>}
            {(sites.data ?? []).map((a) => (
              <SelectItem key={a.id} value={a.id}>
                {addressLine(a)}
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </Field>
    </div>
  );
}

export function NewQuoteDialog({
  open,
  onOpenChange,
  customerId: initialCustomer,
}: {
  open: boolean;
  onOpenChange: (o: boolean) => void;
  customerId?: string;
}) {
  const refresh = useRefreshCrm();
  const navigate = useNavigate();
  const { saving, run } = useSaving();
  const [customerId, setCustomerId] = useState("");
  const [addressId, setAddressId] = useState("");
  const [title, setTitle] = useState("");
  const [scope, setScope] = useState("");
  const [validUntil, setValidUntil] = useState("");

  useEffect(() => {
    if (!open) return;
    setCustomerId(initialCustomer ?? "");
    setAddressId("");
    setTitle("");
    setScope("");
    const d = new Date(Date.now() + 30 * 86400_000);
    setValidUntil(d.toISOString().slice(0, 10));
  }, [open, initialCustomer]);

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-[620px]">
        <DialogHeader>
          <DialogTitle className="text-xl">New quote</DialogTitle>
          <DialogDescription>Starts as a draft. Add line items, then mark it as sent.</DialogDescription>
        </DialogHeader>
        <div className="grid gap-4 py-2">
          <CustomerSitePicker
            enabled={open}
            customerId={customerId}
            setCustomerId={setCustomerId}
            addressId={addressId}
            setAddressId={setAddressId}
          />
          <Field label="Title">
            <Input value={title} onChange={(e) => setTitle(e.target.value)} placeholder="e.g. Replace rooftop unit" className="h-11" />
          </Field>
          <Field label="Scope of work">
            <Textarea value={scope} onChange={(e) => setScope(e.target.value)} rows={4} placeholder="What's included" />
          </Field>
          <Field label="Valid until" className="max-w-[220px]">
            <Input type="date" value={validUntil} onChange={(e) => setValidUntil(e.target.value)} className="h-11" />
          </Field>
        </div>
        <DialogFooter>
          <Button variant="ghost" onClick={() => onOpenChange(false)}>
            Cancel
          </Button>
          <Button
            disabled={saving || !customerId || !addressId || !title.trim()}
            className={ORANGE}
            onClick={() =>
              void run(async () => {
                const id = await createQuote({ customerId, addressId, title, scope, validUntil: validUntil || null });
                toast.success("Quote created");
                refresh();
                onOpenChange(false);
                navigate(`/quotes/${id}`);
              })
            }
          >
            {saving ? "Creating…" : "Create quote"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

export function NewInvoiceDialog({
  open,
  onOpenChange,
  customerId: initialCustomer,
}: {
  open: boolean;
  onOpenChange: (o: boolean) => void;
  customerId?: string;
}) {
  const refresh = useRefreshCrm();
  const navigate = useNavigate();
  const { saving, run } = useSaving();
  const [customerId, setCustomerId] = useState("");
  const [addressId, setAddressId] = useState("none");
  const [title, setTitle] = useState("");
  const [scope, setScope] = useState("");

  useEffect(() => {
    if (!open) return;
    setCustomerId(initialCustomer ?? "");
    setAddressId("none");
    setTitle("");
    setScope("");
  }, [open, initialCustomer]);

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-[620px]">
        <DialogHeader>
          <DialogTitle className="text-xl">New invoice</DialogTitle>
          <DialogDescription>
            Uses the customer's payment terms for the due date. To bill a finished job or an accepted quote, open it and choose
            Create invoice.
          </DialogDescription>
        </DialogHeader>
        <div className="grid gap-4 py-2">
          <CustomerSitePicker
            enabled={open}
            optionalSite
            customerId={customerId}
            setCustomerId={setCustomerId}
            addressId={addressId}
            setAddressId={setAddressId}
          />
          <Field label="Title">
            <Input value={title} onChange={(e) => setTitle(e.target.value)} placeholder="e.g. Annual maintenance visit" className="h-11" />
          </Field>
          <Field label="Description (optional)">
            <Textarea value={scope} onChange={(e) => setScope(e.target.value)} rows={3} />
          </Field>
        </div>
        <DialogFooter>
          <Button variant="ghost" onClick={() => onOpenChange(false)}>
            Cancel
          </Button>
          <Button
            disabled={saving || !customerId}
            className={ORANGE}
            onClick={() =>
              void run(async () => {
                const id = await createInvoice({ customerId, addressId: addressId === "none" ? null : addressId, title, scope });
                toast.success("Draft invoice created");
                refresh();
                onOpenChange(false);
                navigate(`/invoices/${id}`);
              })
            }
          >
            {saving ? "Creating…" : "Create draft"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

export function PaymentDialog({ open, onOpenChange, invoice }: { open: boolean; onOpenChange: (o: boolean) => void; invoice: Invoice }) {
  const refresh = useRefreshCrm();
  const { saving, run } = useSaving();
  const [amount, setAmount] = useState("");
  const [method, setMethod] = useState<PaymentMethod>("ach");
  const [receivedAt, setReceivedAt] = useState("");
  const [reference, setReference] = useState("");
  const [note, setNote] = useState("");

  useEffect(() => {
    if (!open) return;
    setAmount(invoice.balance.toFixed(2));
    setMethod("ach");
    setReceivedAt(toLocalInput(new Date().toISOString()));
    setReference("");
    setNote("");
  }, [open, invoice.balance]);

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-[520px]">
        <DialogHeader>
          <DialogTitle className="text-xl">Record a payment</DialogTitle>
          <DialogDescription>
            {invoice.number} · {money2(invoice.balance, invoice.currency_code)} outstanding. Card payments made on the customer's
            payment page are recorded automatically.
          </DialogDescription>
        </DialogHeader>
        <div className="grid gap-3">
          <div className="grid grid-cols-2 gap-3">
            <Field label={`Amount (${invoice.currency_code})`}>
              <Input inputMode="decimal" value={amount} onChange={(e) => setAmount(e.target.value)} className="h-11 tabular-nums" />
            </Field>
            <Field label="Method">
              <Select value={method} onValueChange={(v) => setMethod(v as PaymentMethod)}>
                <SelectTrigger className="h-11">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {(["ach", "check", "cash", "card"] as PaymentMethod[]).map((m) => (
                    <SelectItem key={m} value={m}>
                      {PAYMENT_METHOD_TITLE[m]}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </Field>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <Field label="Received">
              <Input type="datetime-local" value={receivedAt} onChange={(e) => setReceivedAt(e.target.value)} className="h-11" />
            </Field>
            <Field label="Reference (optional)">
              <Input value={reference} onChange={(e) => setReference(e.target.value)} placeholder="Check no. or transfer ref" className="h-11" />
            </Field>
          </div>
          <Field label="Note (optional)">
            <Input value={note} onChange={(e) => setNote(e.target.value)} className="h-11" />
          </Field>
        </div>
        <DialogFooter>
          <Button variant="ghost" onClick={() => onOpenChange(false)}>
            Cancel
          </Button>
          <Button
            disabled={saving}
            className="bg-success hover:bg-success/90"
            onClick={() =>
              void run(async () => {
                await recordPayment(invoice.id, amount, method, fromLocalInput(receivedAt) ?? "", reference, note);
                toast.success("Payment recorded");
                refresh();
                onOpenChange(false);
              })
            }
          >
            {saving ? "Recording…" : "Record payment"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

export function SendInvoiceDialog({
  open,
  onOpenChange,
  invoice,
  defaultEmail,
  issueFirst,
  onIssue,
}: {
  open: boolean;
  onOpenChange: (o: boolean) => void;
  invoice: Invoice;
  defaultEmail: string;
  issueFirst: boolean;
  onIssue: () => Promise<void>;
}) {
  const refresh = useRefreshCrm();
  const { saving, run } = useSaving();
  const [email, setEmail] = useState("");

  useEffect(() => {
    if (open) setEmail(defaultEmail);
  }, [open, defaultEmail]);

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-[500px]">
        <DialogHeader>
          <DialogTitle className="text-xl">Email {invoice.number}</DialogTitle>
          <DialogDescription>
            The customer gets a link to view the invoice and pay by card if you've set up Stripe payments.
            {issueFirst && " Sending issues the invoice, which locks its line items."}
          </DialogDescription>
        </DialogHeader>
        <Field label="Send to">
          <Input type="email" value={email} onChange={(e) => setEmail(e.target.value)} placeholder="customer@example.com" className="h-11" />
        </Field>
        <DialogFooter>
          <Button variant="ghost" onClick={() => onOpenChange(false)}>
            Cancel
          </Button>
          <Button
            disabled={saving || !/^\S+@\S+\.\S+$/.test(email.trim())}
            className={ORANGE}
            onClick={() =>
              void run(async () => {
                if (issueFirst) await onIssue();
                await sendInvoiceEmail(invoice.id, email);
                toast.success(`Invoice emailed to ${email.trim()}`);
                refresh();
                onOpenChange(false);
              })
            }
          >
            {saving ? "Sending…" : issueFirst ? "Issue and send" : "Send email"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

export function ConvertQuoteDialog({ open, onOpenChange, quote }: { open: boolean; onOpenChange: (o: boolean) => void; quote: Quote }) {
  const ws = useWorkspace();
  const refresh = useRefreshCrm();
  const navigate = useNavigate();
  const { data: workers = [] } = useWorkers();
  const { saving, run } = useSaving();
  const [kind, setKind] = useState<JobKind>("install");
  const [priority, setPriority] = useState<JobPriority>("standard");
  const [start, setStart] = useState("");
  const [end, setEnd] = useState("");
  const [workerId, setWorkerId] = useState("none");

  useEffect(() => {
    if (!open) return;
    setKind("install");
    setPriority("standard");
    setStart("");
    setEnd("");
    setWorkerId("none");
  }, [open]);

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-[560px]">
        <DialogHeader>
          <DialogTitle className="text-xl">Turn {quote.number} into a job</DialogTitle>
          <DialogDescription>The job copies the quote's customer, site, title and agreed scope.</DialogDescription>
        </DialogHeader>
        <div className="grid gap-3">
          <div className="grid grid-cols-2 gap-3">
            <Field label="Type">
              <Select value={kind} onValueChange={(v) => setKind(v as JobKind)}>
                <SelectTrigger className="h-11">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {(Object.keys(KIND_TITLE) as JobKind[]).map((k) => (
                    <SelectItem key={k} value={k}>
                      {KIND_TITLE[k]}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </Field>
            <Field label="Priority">
              <Select value={priority} onValueChange={(v) => setPriority(v as JobPriority)}>
                <SelectTrigger className="h-11">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="standard">Standard</SelectItem>
                  <SelectItem value="urgent">Urgent</SelectItem>
                </SelectContent>
              </Select>
            </Field>
          </div>
          <div className="grid grid-cols-2 gap-3">
            <Field label="Starts (optional)">
              <Input type="datetime-local" value={start} onChange={(e) => setStart(e.target.value)} className="h-11" />
            </Field>
            <Field label="Ends (optional)">
              <Input type="datetime-local" value={end} onChange={(e) => setEnd(e.target.value)} className="h-11" />
            </Field>
          </div>
          {ws.can("assignmentsManage") && (
            <Field label={ws.terms.Worker}>
              <Select value={workerId} onValueChange={setWorkerId}>
                <SelectTrigger className="h-11">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="none">Leave unassigned</SelectItem>
                  {workers.map((w) => (
                    <SelectItem key={w.id} value={w.id}>
                      {w.name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </Field>
          )}
        </div>
        <DialogFooter>
          <Button variant="ghost" onClick={() => onOpenChange(false)}>
            Cancel
          </Button>
          <Button
            disabled={saving}
            className={ORANGE}
            onClick={() =>
              void run(async () => {
                const s = fromLocalInput(start);
                const e = fromLocalInput(end);
                if (s && e && new Date(e) < new Date(s)) throw new Error("A job can't finish before it starts.");
                const jobId = await convertQuoteToJob(quote.id, kind, priority, s, e, workerId === "none" ? null : workerId);
                toast.success("Job created from quote");
                refresh();
                onOpenChange(false);
                navigate(`/jobs?filter=all&job=${jobId}`);
              })
            }
          >
            {saving ? "Creating…" : "Create job"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

