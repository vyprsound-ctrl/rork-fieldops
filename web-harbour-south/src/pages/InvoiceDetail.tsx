import { useState } from "react";
import { Link, useParams } from "react-router-dom";
import { ArrowLeft, Ban, Briefcase, CalendarClock, Banknote, FileText, Link2, Mail, MapPin, Send, User } from "lucide-react";
import { toast } from "sonner";

import { Page } from "@/components/hs/AppShell";
import { LoadingRows } from "@/components/hs/primitives";
import { Confirm, LineItemsEditor, Section, ToneBadge } from "@/components/hs/crm";
import { PaymentDialog, SendInvoiceDialog } from "@/components/hs/crmDialogs";
import { Button } from "@/components/ui/button";
import {
  INVOICE_STATUS,
  PAYMENT_METHOD_TITLE,
  deleteInvoiceLine,
  effectiveStatus,
  invoiceShareLink,
  saveInvoiceLine,
  setInvoiceStatus,
  siteLine,
} from "@/lib/crm";
import { dateOnly, dayAndTime, money2 } from "@/lib/format";
import { useCustomers, useInvoice, useRefreshCrm, useSites } from "@/lib/queries";
import { useWorkspace } from "@/lib/session";

export default function InvoiceDetail() {
  const { id = "" } = useParams();
  const ws = useWorkspace();
  const refresh = useRefreshCrm();
  const { data, isLoading, error } = useInvoice(id);
  const { data: customers = [] } = useCustomers();
  const { data: sites = [] } = useSites();
  const [busy, setBusy] = useState(false);
  const [paying, setPaying] = useState(false);
  const [sending, setSending] = useState(false);
  const [voiding, setVoiding] = useState(false);

  if (isLoading)
    return (
      <Page>
        <LoadingRows count={6} />
      </Page>
    );
  if (error || !data)
    return (
      <Page>
        <p className="text-sm text-destructive">{(error as Error)?.message ?? "That invoice couldn't be found."}</p>
      </Page>
    );

  const { invoice, lines, payments, billingContact } = data;
  const manage = ws.can("invoicesManage");
  const shown = effectiveStatus(invoice);
  const status = INVOICE_STATUS[shown];
  const currency = invoice.currency_code || ws.company.currency_code;
  const customer = customers.find((c) => c.id === invoice.customer_id);
  const site = invoice.address_id ? sites.find((s) => s.id === invoice.address_id) : undefined;
  const isDraft = invoice.status === "draft";
  const isVoid = invoice.status === "void";
  const canPay = ws.can("paymentsManage") && ["sent", "viewed", "partPaid", "overdue"].includes(invoice.status) && invoice.balance > 0;
  const canVoid = manage && ["draft", "sent", "viewed"].includes(invoice.status) && invoice.amount_paid === 0;

  const run = async (fn: () => Promise<unknown>, done: string) => {
    setBusy(true);
    try {
      await fn();
      toast.success(done);
      refresh();
    } catch (err) {
      toast.error((err as Error).message);
    } finally {
      setBusy(false);
    }
  };

  const issue = async () => {
    if (lines.length === 0) throw new Error("Add at least one line item before issuing the invoice.");
    await setInvoiceStatus(invoice.id, "sent");
  };

  const copyLink = () =>
    run(async () => {
      const url = await invoiceShareLink(invoice.id);
      await navigator.clipboard.writeText(url);
    }, "Payment link copied");

  const timeline = [
    { label: "Created", at: invoice.created_at },
    { label: "Issued", at: invoice.sent_at },
    { label: "Viewed by customer", at: invoice.viewed_at },
    { label: "Paid in full", at: invoice.paid_at },
    { label: "Voided", at: invoice.voided_at },
  ].filter((t) => t.at);

  return (
    <Page>
      <Link to="/invoices" className="mb-4 inline-flex items-center gap-1.5 text-sm font-medium text-muted-foreground hover:text-foreground">
        <ArrowLeft className="h-4 w-4" /> Invoices
      </Link>

      <div className="flex flex-wrap items-end justify-between gap-4 pb-6">
        <div>
          <p className="text-sm font-semibold tabular-nums text-muted-foreground">{invoice.number}</p>
          <h1 className="text-[28px] font-bold leading-tight tracking-tight">{invoice.title || customer?.name || "Invoice"}</h1>
          <div className="mt-2 flex flex-wrap items-center gap-2 text-sm text-muted-foreground">
            <ToneBadge tone={status.tone}>{status.title}</ToneBadge>
            {!isDraft && <span>Issued {dateOnly(invoice.issue_date)}</span>}
            <span className="text-meta">·</span>
            <span className={shown === "overdue" ? "font-semibold text-destructive" : ""}>Due {dateOnly(invoice.due_date)}</span>
            <span className="text-meta">·</span>
            <span>{invoice.payment_terms_label}</span>
          </div>
        </div>
        <div className="flex flex-wrap gap-2">
          {manage && isDraft && (
            <Button variant="outline" disabled={busy} className="gap-1.5" onClick={() => void run(issue, "Invoice issued")}>
              <FileText className="h-4 w-4" /> Issue without sending
            </Button>
          )}
          {manage && !isVoid && invoice.status !== "paid" && (
            <Button
              disabled={busy}
              className="gap-1.5 bg-brand-orange hover:bg-brand-orange/90"
              onClick={() => {
                if (isDraft && lines.length === 0) {
                  toast.error("Add at least one line item before sending the invoice.");
                  return;
                }
                setSending(true);
              }}
            >
              <Send className="h-4 w-4" /> {isDraft ? "Issue and email" : "Email invoice"}
            </Button>
          )}
          {canPay && (
            <Button disabled={busy} className="gap-1.5 bg-success hover:bg-success/90" onClick={() => setPaying(true)}>
              <Banknote className="h-4 w-4" /> Record payment
            </Button>
          )}
          {!isDraft && !isVoid && invoice.status !== "paid" && (
            <Button variant="outline" disabled={busy} className="gap-1.5" onClick={() => void copyLink()}>
              <Link2 className="h-4 w-4" /> Copy payment link
            </Button>
          )}
          {canVoid && (
            <Button variant="ghost" disabled={busy} className="gap-1.5 text-destructive hover:text-destructive" onClick={() => setVoiding(true)}>
              <Ban className="h-4 w-4" /> Void
            </Button>
          )}
        </div>
      </div>

      <div className="grid gap-6 lg:grid-cols-[1fr_320px]">
        <div className="grid content-start gap-6">
          {invoice.scope_of_work && (
            <Section title="Work carried out">
              <p className="whitespace-pre-wrap px-5 py-4 text-sm leading-relaxed">{invoice.scope_of_work}</p>
            </Section>
          )}
          <Section title="Line items">
            <LineItemsEditor
              lines={lines}
              currency={currency}
              editable={manage && isDraft}
              lockedReason={isDraft ? undefined : "Line items are locked once an invoice is issued, as on the iPhone app."}
              totals={{ subtotal: invoice.subtotal, tax: invoice.tax, total: invoice.total }}
              extraTotals={
                !isDraft && (
                  <>
                    <dt className="text-muted-foreground">Paid</dt>
                    <dd className="text-right tabular-nums text-success">−{money2(invoice.amount_paid, currency)}</dd>
                    <dt className="font-semibold">Balance due</dt>
                    <dd className={`text-right text-lg font-bold tabular-nums ${shown === "overdue" ? "text-destructive" : ""}`}>
                      {money2(isVoid ? 0 : invoice.balance, currency)}
                    </dd>
                  </>
                )
              }
              onSave={async (lineId, d) => {
                await saveInvoiceLine(invoice.id, lineId, d);
                refresh();
              }}
              onDelete={async (lineId) => {
                await deleteInvoiceLine(invoice.id, lineId);
                refresh();
              }}
            />
          </Section>

          {ws.can("paymentsRead") && !isDraft && (
            <Section title="Payments">
              {payments.length === 0 ? (
                <p className="px-5 py-6 text-sm text-muted-foreground">No payments yet. Card payments made through the payment link appear here automatically.</p>
              ) : (
                <ul className="divide-y divide-border">
                  {payments.map((p) => (
                    <li key={p.id} className="flex items-center justify-between gap-4 px-5 py-3 text-sm">
                      <div>
                        <p className="font-medium">
                          {PAYMENT_METHOD_TITLE[p.method] ?? p.method}
                          {p.reference && <span className="ml-1.5 text-muted-foreground">· {p.reference}</span>}
                        </p>
                        <p className="text-xs text-muted-foreground">
                          {dayAndTime(p.received_at)}
                          {p.paid_by_customer && " · Paid online by the customer"}
                          {p.note && ` · ${p.note}`}
                        </p>
                      </div>
                      <p className="font-semibold tabular-nums text-success">{money2(p.amount, currency)}</p>
                    </li>
                  ))}
                </ul>
              )}
            </Section>
          )}
        </div>

        <div className="grid content-start gap-6">
          <Section title="Bill to">
            <div className="grid gap-3 px-5 py-4 text-sm">
              <Link to={`/customers/${invoice.customer_id}`} className="flex items-center gap-2 font-semibold text-primary hover:underline">
                <User className="h-4 w-4" /> {customer?.name ?? "Customer"}
              </Link>
              {billingContact && (
                <div className="text-muted-foreground">
                  <p className="font-medium text-foreground">{billingContact.name}</p>
                  {billingContact.email && (
                    <p className="flex items-center gap-1.5">
                      <Mail className="h-3.5 w-3.5" /> {billingContact.email}
                    </p>
                  )}
                </div>
              )}
              {site && (
                <p className="flex items-start gap-2 text-muted-foreground">
                  <MapPin className="mt-0.5 h-4 w-4 shrink-0" /> {siteLine(site)}
                </p>
              )}
            </div>
          </Section>

          {(invoice.job_id || invoice.quote_id) && (
            <Section title="Linked work">
              <div className="grid gap-2 px-5 py-4 text-sm">
                {invoice.job_id && (
                  <Link to={`/jobs?filter=all&job=${invoice.job_id}`} className="flex items-center gap-2 font-medium text-primary hover:underline">
                    <Briefcase className="h-4 w-4" /> Open the job
                  </Link>
                )}
                {invoice.quote_id && ws.can("quotesRead") && (
                  <Link to={`/quotes/${invoice.quote_id}`} className="flex items-center gap-2 font-medium text-primary hover:underline">
                    <FileText className="h-4 w-4" /> Open the quote
                  </Link>
                )}
              </div>
            </Section>
          )}

          <Section title="History">
            <ol className="grid gap-3 px-5 py-4 text-sm">
              {timeline.map((t) => (
                <li key={t.label} className="flex items-start gap-2">
                  <CalendarClock className="mt-0.5 h-4 w-4 shrink-0 text-meta" />
                  <span>
                    <span className="font-medium">{t.label}</span>
                    <span className="block text-xs text-muted-foreground">{dayAndTime(t.at)}</span>
                  </span>
                </li>
              ))}
            </ol>
          </Section>
        </div>
      </div>

      {canPay && <PaymentDialog open={paying} onOpenChange={setPaying} invoice={invoice} />}
      <SendInvoiceDialog
        open={sending}
        onOpenChange={setSending}
        invoice={invoice}
        defaultEmail={billingContact?.email ?? ""}
        issueFirst={isDraft}
        onIssue={issue}
      />
      <Confirm
        open={voiding}
        onOpenChange={setVoiding}
        title={`Void ${invoice.number}?`}
        body="A void invoice can't be paid or reopened. The customer's payment link stops working."
        action="Void invoice"
        onConfirm={() => void run(() => setInvoiceStatus(invoice.id, "void"), "Invoice voided")}
      />
    </Page>
  );
}
