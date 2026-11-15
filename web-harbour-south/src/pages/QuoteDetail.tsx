import { useState } from "react";
import { Link, useNavigate, useParams } from "react-router-dom";
import { ArrowLeft, Briefcase, CalendarClock, MapPin, Receipt, User } from "lucide-react";
import { toast } from "sonner";

import { Page } from "@/components/hs/AppShell";
import { LoadingRows } from "@/components/hs/primitives";
import { Confirm, LineItemsEditor, Section, ToneBadge } from "@/components/hs/crm";
import { ConvertQuoteDialog } from "@/components/hs/crmDialogs";
import { Button } from "@/components/ui/button";
import {
  QUOTE_STATUS,
  createInvoiceFromQuote,
  deleteQuoteLine,
  quoteActions,
  saveQuoteLine,
  setQuoteStatus,
  siteLine,
  type QuoteStatus,
} from "@/lib/crm";
import { dateOnly, dayAndTime } from "@/lib/format";
import { useCustomers, useInvoices, useQuote, useRefreshCrm, useSites } from "@/lib/queries";
import { useWorkspace } from "@/lib/session";

export default function QuoteDetail() {
  const { id = "" } = useParams();
  const ws = useWorkspace();
  const navigate = useNavigate();
  const refresh = useRefreshCrm();
  const { data, isLoading, error } = useQuote(id);
  const { data: customers = [] } = useCustomers();
  const { data: sites = [] } = useSites();
  const { data: invoices = [] } = useInvoices();
  const [busy, setBusy] = useState(false);
  const [converting, setConverting] = useState(false);
  const [declining, setDeclining] = useState(false);

  if (isLoading)
    return (
      <Page>
        <LoadingRows count={6} />
      </Page>
    );
  if (error || !data)
    return (
      <Page>
        <p className="text-sm text-destructive">{(error as Error)?.message ?? "That quote couldn't be found."}</p>
      </Page>
    );

  const { quote, lines } = data;
  const manage = ws.can("quotesManage");
  const financial = ws.can("quoteFinancialsRead");
  const currency = ws.company.currency_code;
  const customer = customers.find((c) => c.id === quote.customer_id);
  const site = sites.find((s) => s.id === quote.address_id);
  const invoice = invoices.find((i) => i.quote_id === quote.id && i.status !== "void");
  const status = QUOTE_STATUS[quote.status];

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

  const move = (to: QuoteStatus) => {
    if (to === "sent" && financial && lines.length === 0) {
      toast.error("Add at least one line item before sending the quote.");
      return;
    }
    void run(() => setQuoteStatus(quote.id, to), `Quote marked ${QUOTE_STATUS[to].title.toLowerCase()}`);
  };

  const makeInvoice = async () => {
    setBusy(true);
    try {
      const invoiceId = await createInvoiceFromQuote(quote.id);
      toast.success("Draft invoice created from the quote");
      refresh();
      navigate(`/invoices/${invoiceId}`);
    } catch (err) {
      toast.error((err as Error).message);
    } finally {
      setBusy(false);
    }
  };

  const timeline = [
    { label: "Created", at: quote.created_at },
    { label: "Sent", at: quote.sent_at },
    { label: "Viewed", at: quote.viewed_at },
    { label: "Accepted", at: quote.accepted_at },
    { label: "Declined", at: quote.declined_at },
  ].filter((t) => t.at);

  const canConvert = quote.status === "accepted" && !quote.converted_job_id && manage && ws.can("jobsManage");
  const canInvoice = quote.status === "accepted" && !invoice && ws.can("invoicesManage");

  return (
    <Page>
      <Link to="/quotes" className="mb-4 inline-flex items-center gap-1.5 text-sm font-medium text-muted-foreground hover:text-foreground">
        <ArrowLeft className="h-4 w-4" /> Quotes
      </Link>

      <div className="flex flex-wrap items-end justify-between gap-4 pb-6">
        <div>
          <p className="text-sm font-semibold tabular-nums text-muted-foreground">{quote.number}</p>
          <h1 className="text-[28px] font-bold leading-tight tracking-tight">{quote.title || "Untitled quote"}</h1>
          <div className="mt-2 flex flex-wrap items-center gap-2 text-sm text-muted-foreground">
            <ToneBadge tone={status.tone}>{status.title}</ToneBadge>
            {quote.valid_until && <span>Valid until {dateOnly(quote.valid_until)}</span>}
          </div>
        </div>
        <div className="flex flex-wrap gap-2">
          {manage &&
            quoteActions(quote.status).map((a) =>
              a.destructive ? (
                <Button key={a.to} variant="outline" disabled={busy} className="text-destructive hover:text-destructive" onClick={() => setDeclining(true)}>
                  {a.label}
                </Button>
              ) : (
                <Button
                  key={a.to}
                  disabled={busy}
                  variant={a.to === "expired" ? "outline" : "default"}
                  className={a.to === "expired" ? "" : a.to === "accepted" ? "bg-success hover:bg-success/90" : "bg-brand-orange hover:bg-brand-orange/90"}
                  onClick={() => move(a.to)}
                >
                  {a.label}
                </Button>
              ),
            )}
          {canConvert && (
            <Button disabled={busy} className="gap-1.5 bg-brand-orange hover:bg-brand-orange/90" onClick={() => setConverting(true)}>
              <Briefcase className="h-4 w-4" /> Turn into a job
            </Button>
          )}
          {canInvoice && (
            <Button disabled={busy} variant="outline" className="gap-1.5" onClick={() => void makeInvoice()}>
              <Receipt className="h-4 w-4" /> Create invoice
            </Button>
          )}
        </div>
      </div>

      <div className="grid gap-6 lg:grid-cols-[1fr_320px]">
        <div className="grid content-start gap-6">
          {quote.scope_of_work && (
            <Section title="Scope of work">
              <p className="whitespace-pre-wrap px-5 py-4 text-sm leading-relaxed">{quote.scope_of_work}</p>
            </Section>
          )}
          {financial ? (
            <Section title="Line items">
              <LineItemsEditor
                lines={lines}
                currency={currency}
                editable={manage && quote.status === "draft"}
                lockedReason={quote.status === "draft" ? undefined : "Line items are locked once a quote has been sent, as on the iPhone app."}
                totals={{ subtotal: quote.subtotal ?? 0, tax: quote.tax ?? 0, total: quote.total ?? 0 }}
                onSave={async (lineId, d) => {
                  await saveQuoteLine(quote.id, lineId, d);
                  refresh();
                }}
                onDelete={async (lineId) => {
                  await deleteQuoteLine(quote.id, lineId);
                  refresh();
                }}
              />
            </Section>
          ) : (
            <Section title="Line items">
              <p className="px-5 py-6 text-sm text-muted-foreground">Prices on quotes are visible to owners, admins and accounts staff.</p>
            </Section>
          )}
        </div>

        <div className="grid content-start gap-6">
          <Section title="Customer">
            <div className="grid gap-3 px-5 py-4 text-sm">
              <Link to={`/customers/${quote.customer_id}`} className="flex items-center gap-2 font-semibold text-primary hover:underline">
                <User className="h-4 w-4" /> {customer?.name ?? "Customer"}
              </Link>
              <p className="flex items-start gap-2 text-muted-foreground">
                <MapPin className="mt-0.5 h-4 w-4 shrink-0" /> {siteLine(site) || "Site not found"}
              </p>
            </div>
          </Section>

          {(quote.converted_job_id || invoice) && (
            <Section title="Follow-on work">
              <div className="grid gap-2 px-5 py-4 text-sm">
                {quote.converted_job_id && (
                  <Link to={`/jobs?filter=all&job=${quote.converted_job_id}`} className="flex items-center gap-2 font-medium text-primary hover:underline">
                    <Briefcase className="h-4 w-4" /> Open the booked job
                  </Link>
                )}
                {invoice && (
                  <Link to={`/invoices/${invoice.id}`} className="flex items-center gap-2 font-medium text-primary hover:underline">
                    <Receipt className="h-4 w-4" /> Invoice {invoice.number}
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

      <ConvertQuoteDialog open={converting} onOpenChange={setConverting} quote={quote} />
      <Confirm
        open={declining}
        onOpenChange={setDeclining}
        title={`Mark ${quote.number} as declined?`}
        body="Declined quotes can't be accepted or turned into a job later."
        action="Mark declined"
        onConfirm={() => move("declined")}
      />
    </Page>
  );
}
