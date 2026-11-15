import { useMemo, useState } from "react";
import { Link, useNavigate, useParams } from "react-router-dom";
import { ArrowLeft, FileText, Mail, MapPin, Pencil, Phone, Plus, Receipt, Star, Trash2, Wrench } from "lucide-react";
import { toast } from "sonner";

import { Page } from "@/components/hs/AppShell";
import { LoadingRows, StatusBadge, useJobPanel } from "@/components/hs/primitives";
import { Confirm, Section, StatTile, ToneBadge } from "@/components/hs/crm";
import { ContactDialog, CustomerDialog, NewInvoiceDialog, NewQuoteDialog, SiteDialog } from "@/components/hs/crmDialogs";
import { Button } from "@/components/ui/button";
import {
  CUSTOMER_TYPE_TITLE,
  INVOICE_STATUS,
  QUOTE_STATUS,
  createInvoiceFromJob,
  deleteContact,
  deleteCustomer,
  deleteSite,
  effectiveStatus,
  isReceivable,
  siteLine,
  type Contact,
  type Site,
} from "@/lib/crm";
import { isOpen } from "@/lib/domain";
import { dateOnly, dayAndTime, money2 } from "@/lib/format";
import { useCustomer, useInvoices, useJobs, useQuotes, useRefreshCrm } from "@/lib/queries";
import { useWorkspace } from "@/lib/session";

export default function CustomerDetail() {
  const { id = "" } = useParams();
  const ws = useWorkspace();
  const navigate = useNavigate();
  const panel = useJobPanel();
  const refresh = useRefreshCrm();
  const { data, isLoading, error } = useCustomer(id);
  const { data: jobs = [] } = useJobs();
  const { data: quotes = [] } = useQuotes();
  const { data: invoices = [] } = useInvoices();

  const [editing, setEditing] = useState(false);
  const [deleting, setDeleting] = useState(false);
  const [site, setSite] = useState<{ open: boolean; existing?: Site }>({ open: false });
  const [contact, setContact] = useState<{ open: boolean; existing?: Contact }>({ open: false });
  const [newQuote, setNewQuote] = useState(false);
  const [newInvoice, setNewInvoice] = useState(false);
  const [busyJob, setBusyJob] = useState<string | null>(null);

  const manage = ws.can("customersManage");
  const currency = ws.company.currency_code;

  const mine = useMemo(() => {
    const myJobs = jobs.filter((j) => j.customer_id === id);
    const myQuotes = quotes.filter((q) => q.customer_id === id);
    const myInvoices = invoices.filter((i) => i.customer_id === id);
    const invoicedJobs = new Set(myInvoices.filter((i) => i.status !== "void").map((i) => i.job_id));
    const owed = myInvoices.filter((i) => isReceivable(effectiveStatus(i))).reduce((s, i) => s + i.balance, 0);
    const overdue = myInvoices.filter((i) => effectiveStatus(i) === "overdue").reduce((s, i) => s + i.balance, 0);
    return { myJobs, myQuotes, myInvoices, invoicedJobs, owed, overdue };
  }, [jobs, quotes, invoices, id]);

  if (isLoading) return <Page><LoadingRows count={6} /></Page>;
  if (error || !data)
    return (
      <Page>
        <p className="text-sm text-destructive">{(error as Error)?.message ?? "That customer couldn't be found."}</p>
      </Page>
    );

  const { customer, sites, contacts, equipment } = data;
  const openJobs = mine.myJobs.filter((j) => isOpen(j.status)).length;

  const invoiceJob = async (jobId: string) => {
    setBusyJob(jobId);
    try {
      const invoiceId = await createInvoiceFromJob(jobId);
      toast.success("Draft invoice created from the job");
      refresh();
      navigate(`/invoices/${invoiceId}`);
    } catch (err) {
      toast.error((err as Error).message);
    } finally {
      setBusyJob(null);
    }
  };

  const tryDelete = async (fn: () => Promise<void>, done: string) => {
    try {
      await fn();
      toast.success(done);
      refresh();
    } catch (err) {
      toast.error((err as Error).message);
    }
  };

  return (
    <Page>
      <Link to="/customers" className="mb-4 inline-flex items-center gap-1.5 text-sm font-medium text-muted-foreground hover:text-foreground">
        <ArrowLeft className="h-4 w-4" /> Customers
      </Link>

      <div className="flex flex-wrap items-end justify-between gap-4 pb-6">
        <div>
          <h1 className="text-[28px] font-bold leading-tight tracking-tight">{customer.name}</h1>
          <div className="mt-2 flex flex-wrap items-center gap-2 text-sm text-muted-foreground">
            <ToneBadge tone="info">{CUSTOMER_TYPE_TITLE[customer.type] ?? customer.type}</ToneBadge>
            <span>Terms: {customer.billing_terms}</span>
            <span className="text-meta">·</span>
            <span>Customer since {dateOnly(customer.created_at)}</span>
          </div>
        </div>
        <div className="flex flex-wrap gap-2">
          {ws.can("quotesManage") && (
            <Button variant="outline" className="gap-1.5" onClick={() => setNewQuote(true)}>
              <FileText className="h-4 w-4" /> New quote
            </Button>
          )}
          {ws.can("invoicesManage") && (
            <Button variant="outline" className="gap-1.5" onClick={() => setNewInvoice(true)}>
              <Receipt className="h-4 w-4" /> New invoice
            </Button>
          )}
          {manage && (
            <>
              <Button variant="outline" className="gap-1.5" onClick={() => setEditing(true)}>
                <Pencil className="h-4 w-4" /> Edit
              </Button>
              <Button variant="ghost" size="icon" className="text-destructive hover:text-destructive" onClick={() => setDeleting(true)} aria-label="Delete customer">
                <Trash2 className="h-4 w-4" />
              </Button>
            </>
          )}
        </div>
      </div>

      <div className="mb-6 grid gap-3 sm:grid-cols-3">
        <StatTile label="Open jobs" value={String(openJobs)} sub={`${mine.myJobs.length} jobs in total`} />
        {ws.can("invoicesRead") && (
          <StatTile
            label="Balance owed"
            value={money2(mine.owed, currency)}
            tone={mine.overdue > 0 ? "danger" : undefined}
            sub={mine.overdue > 0 ? `${money2(mine.overdue, currency)} overdue` : "Nothing overdue"}
          />
        )}
        {ws.can("quotesRead") && (
          <StatTile
            label="Quotes"
            value={String(mine.myQuotes.length)}
            sub={`${mine.myQuotes.filter((q) => q.status === "sent" || q.status === "viewed").length} awaiting an answer`}
          />
        )}
      </div>

      <div className="grid gap-6 lg:grid-cols-[1fr_360px]">
        <div className="space-y-6">
          <Section
            title={`Sites · ${sites.length}`}
            action={
              manage && (
                <Button size="sm" variant="ghost" className="h-8 gap-1 text-primary" onClick={() => setSite({ open: true })}>
                  <Plus className="h-4 w-4" /> Add site
                </Button>
              )
            }
          >
            {sites.length === 0 ? (
              <p className="px-5 py-6 text-sm text-muted-foreground">No sites on file.</p>
            ) : (
              <ul className="divide-y divide-border">
                {sites.map((s, i) => {
                  const units = equipment.filter((e) => e.address_id === s.id);
                  return (
                    <li key={s.id} className="group px-5 py-4">
                      <div className="flex items-start gap-3">
                        <MapPin className="mt-0.5 h-4 w-4 shrink-0 text-brand-orange" />
                        <div className="min-w-0 flex-1">
                          <p className="font-medium">
                            {siteLine(s)}
                            {i === 0 && <span className="ml-2 text-xs font-semibold text-meta">PRIMARY</span>}
                          </p>
                          {s.access_notes && <p className="mt-0.5 text-sm text-muted-foreground">{s.access_notes}</p>}
                          {units.length > 0 && (
                            <div className="mt-2 flex flex-wrap gap-1.5">
                              {units.map((u) => (
                                <span key={u.id} className="inline-flex items-center gap-1 rounded-lg bg-secondary px-2 py-1 text-xs">
                                  <Wrench className="h-3 w-3 text-primary" />
                                  {[u.make, u.model].filter(Boolean).join(" ") || u.category}
                                  {u.serial_number && <span className="text-meta">· {u.serial_number}</span>}
                                </span>
                              ))}
                            </div>
                          )}
                        </div>
                        {manage && (
                          <div className="flex gap-1 opacity-0 transition-opacity group-hover:opacity-100">
                            <Button size="icon" variant="ghost" className="h-8 w-8" onClick={() => setSite({ open: true, existing: s })} aria-label="Edit site">
                              <Pencil className="h-3.5 w-3.5" />
                            </Button>
                            {sites.length > 1 && (
                              <Button
                                size="icon"
                                variant="ghost"
                                className="h-8 w-8 text-destructive hover:text-destructive"
                                onClick={() => void tryDelete(() => deleteSite(s.id), "Site removed")}
                                aria-label="Remove site"
                              >
                                <Trash2 className="h-3.5 w-3.5" />
                              </Button>
                            )}
                          </div>
                        )}
                      </div>
                    </li>
                  );
                })}
              </ul>
            )}
          </Section>

          <Section title={`Jobs · ${mine.myJobs.length}`}>
            {mine.myJobs.length === 0 ? (
              <p className="px-5 py-6 text-sm text-muted-foreground">No jobs yet.</p>
            ) : (
              <ul className="divide-y divide-border">
                {mine.myJobs.slice(0, 30).map((j) => (
                  <li key={j.id} className="flex cursor-pointer items-center gap-3 px-5 py-3 transition-colors hover:bg-primary-tint/50" onClick={() => panel.open(j.id)}>
                    <span className="w-16 shrink-0 text-xs font-semibold tabular-nums text-muted-foreground">{j.number}</span>
                    <div className="min-w-0 flex-1">
                      <p className="truncate text-sm font-medium">{j.title}</p>
                      <p className="text-xs text-meta">{dayAndTime(j.scheduled_start)}</p>
                    </div>
                    {ws.can("invoicesManage") && j.status === "completed" && !mine.invoicedJobs.has(j.id) && (
                      <Button
                        size="sm"
                        variant="outline"
                        className="h-8 border-brand-orange/40 text-brand-orange-text"
                        disabled={busyJob === j.id}
                        onClick={(e) => {
                          e.stopPropagation();
                          void invoiceJob(j.id);
                        }}
                      >
                        {busyJob === j.id ? "Creating…" : "Invoice"}
                      </Button>
                    )}
                    <StatusBadge status={j.status} terms={ws.terms} />
                  </li>
                ))}
              </ul>
            )}
          </Section>

          {ws.can("quotesRead") && (
            <Section title={`Quotes · ${mine.myQuotes.length}`}>
              {mine.myQuotes.length === 0 ? (
                <p className="px-5 py-6 text-sm text-muted-foreground">No quotes yet.</p>
              ) : (
                <ul className="divide-y divide-border">
                  {mine.myQuotes.map((q) => (
                    <li key={q.id}>
                      <Link to={`/quotes/${q.id}`} className="flex items-center gap-3 px-5 py-3 transition-colors hover:bg-primary-tint/50">
                        <span className="w-16 shrink-0 text-xs font-semibold tabular-nums text-muted-foreground">{q.number}</span>
                        <p className="min-w-0 flex-1 truncate text-sm font-medium">{q.title || "Untitled quote"}</p>
                        {q.total != null && <span className="text-sm font-semibold tabular-nums">{money2(q.total, currency)}</span>}
                        <ToneBadge tone={QUOTE_STATUS[q.status].tone}>{QUOTE_STATUS[q.status].title}</ToneBadge>
                      </Link>
                    </li>
                  ))}
                </ul>
              )}
            </Section>
          )}

          {ws.can("invoicesRead") && (
            <Section title={`Invoices · ${mine.myInvoices.length}`}>
              {mine.myInvoices.length === 0 ? (
                <p className="px-5 py-6 text-sm text-muted-foreground">No invoices yet.</p>
              ) : (
                <ul className="divide-y divide-border">
                  {mine.myInvoices.map((inv) => {
                    const s = effectiveStatus(inv);
                    return (
                      <li key={inv.id}>
                        <Link to={`/invoices/${inv.id}`} className="flex items-center gap-3 px-5 py-3 transition-colors hover:bg-primary-tint/50">
                          <span className="w-16 shrink-0 text-xs font-semibold tabular-nums text-muted-foreground">{inv.number}</span>
                          <div className="min-w-0 flex-1">
                            <p className="truncate text-sm font-medium">{inv.title || "Invoice"}</p>
                            <p className="text-xs text-meta">Due {dateOnly(inv.due_date)}</p>
                          </div>
                          <span className="text-sm font-semibold tabular-nums">{money2(isReceivable(s) ? inv.balance : inv.total, inv.currency_code)}</span>
                          <ToneBadge tone={INVOICE_STATUS[s].tone}>{INVOICE_STATUS[s].title}</ToneBadge>
                        </Link>
                      </li>
                    );
                  })}
                </ul>
              )}
            </Section>
          )}
        </div>

        <div className="space-y-6">
          <Section
            title="Contacts"
            action={
              manage && (
                <Button size="sm" variant="ghost" className="h-8 gap-1 text-primary" onClick={() => setContact({ open: true })}>
                  <Plus className="h-4 w-4" /> Add
                </Button>
              )
            }
          >
            {contacts.length === 0 ? (
              <p className="px-5 py-6 text-sm text-muted-foreground">No contacts you can see.</p>
            ) : (
              <ul className="divide-y divide-border">
                {contacts.map((c) => (
                  <li key={c.id} className="group px-5 py-4">
                    <div className="flex items-start justify-between gap-2">
                      <div className="min-w-0">
                        <p className="flex items-center gap-1.5 font-semibold">
                          {c.name}
                          {c.is_primary && <Star className="h-3.5 w-3.5 fill-brand-orange text-brand-orange" />}
                        </p>
                        <p className="text-xs text-meta">
                          {c.contact_role}
                          {c.is_billing_contact && " · Billing contact"}
                        </p>
                      </div>
                      {manage && (
                        <div className="flex gap-1 opacity-0 transition-opacity group-hover:opacity-100">
                          <Button size="icon" variant="ghost" className="h-7 w-7" onClick={() => setContact({ open: true, existing: c })} aria-label="Edit contact">
                            <Pencil className="h-3.5 w-3.5" />
                          </Button>
                          {contacts.length > 1 && (
                            <Button
                              size="icon"
                              variant="ghost"
                              className="h-7 w-7 text-destructive hover:text-destructive"
                              onClick={() => void tryDelete(() => deleteContact(c.id), "Contact removed")}
                              aria-label="Remove contact"
                            >
                              <Trash2 className="h-3.5 w-3.5" />
                            </Button>
                          )}
                        </div>
                      )}
                    </div>
                    <div className="mt-2 space-y-1 text-sm">
                      {c.phone && (
                        <a href={`tel:${c.phone}`} className="flex items-center gap-2 text-primary hover:underline">
                          <Phone className="h-3.5 w-3.5" /> {c.phone}
                        </a>
                      )}
                      {c.email && (
                        <a href={`mailto:${c.email}`} className="flex items-center gap-2 truncate text-primary hover:underline">
                          <Mail className="h-3.5 w-3.5" /> {c.email}
                        </a>
                      )}
                    </div>
                  </li>
                ))}
              </ul>
            )}
          </Section>

          {customer.notes && (
            <Section title="Notes">
              <p className="whitespace-pre-wrap px-5 py-4 text-sm text-muted-foreground">{customer.notes}</p>
            </Section>
          )}
        </div>
      </div>

      <CustomerDialog open={editing} onOpenChange={setEditing} existing={customer} />
      <SiteDialog open={site.open} onOpenChange={(o) => setSite((s) => ({ ...s, open: o }))} customerId={id} existing={site.existing} />
      <ContactDialog open={contact.open} onOpenChange={(o) => setContact((c) => ({ ...c, open: o }))} customerId={id} existing={contact.existing} />
      {ws.can("quotesManage") && <NewQuoteDialog open={newQuote} onOpenChange={setNewQuote} customerId={id} />}
      {ws.can("invoicesManage") && <NewInvoiceDialog open={newInvoice} onOpenChange={setNewInvoice} customerId={id} />}
      <Confirm
        open={deleting}
        onOpenChange={setDeleting}
        title={`Delete ${customer.name}?`}
        body="This removes the customer with their sites, contacts and equipment. Customers with jobs, quotes or invoices can't be deleted."
        action="Delete customer"
        onConfirm={() =>
          void tryDelete(async () => {
            await deleteCustomer(id);
            navigate("/customers");
          }, "Customer deleted")
        }
      />
    </Page>
  );
}
