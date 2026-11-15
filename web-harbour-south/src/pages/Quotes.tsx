import { useMemo, useState } from "react";
import { useNavigate, useSearchParams } from "react-router-dom";
import { FileText, Plus, Search } from "lucide-react";

import { Page } from "@/components/hs/AppShell";
import { EmptyState, LoadingRows, PageHeader } from "@/components/hs/primitives";
import { StatTile, ToneBadge } from "@/components/hs/crm";
import { NewQuoteDialog } from "@/components/hs/crmDialogs";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { cn } from "@/lib/utils";
import { QUOTE_STATUS, siteLine, type Quote } from "@/lib/crm";
import { dateOnly, money2 } from "@/lib/format";
import { useCustomers, useQuotes, useSites } from "@/lib/queries";
import { useWorkspace } from "@/lib/session";

const FILTERS = [
  { id: "open", label: "Awaiting answer", match: (q: Quote) => q.status === "sent" || q.status === "viewed" },
  { id: "draft", label: "Drafts", match: (q: Quote) => q.status === "draft" },
  { id: "accepted", label: "Accepted", match: (q: Quote) => q.status === "accepted" },
  { id: "closed", label: "Declined or expired", match: (q: Quote) => q.status === "declined" || q.status === "expired" },
  { id: "all", label: "All", match: () => true },
] as const;

export default function Quotes() {
  const ws = useWorkspace();
  const navigate = useNavigate();
  const [params, setParams] = useSearchParams();
  const { data: quotes = [], isLoading, error } = useQuotes();
  const { data: customers = [] } = useCustomers();
  const { data: sites = [] } = useSites();
  const [query, setQuery] = useState("");
  const [creating, setCreating] = useState(false);
  const financial = ws.can("quoteFinancialsRead");
  const currency = ws.company.currency_code;

  const filter = FILTERS.find((f) => f.id === params.get("filter")) ?? FILTERS[4];
  const names = useMemo(() => new Map(customers.map((c) => [c.id, c.name])), [customers]);
  const siteMap = useMemo(() => new Map(sites.map((s) => [s.id, s])), [sites]);

  const list = useMemo(() => {
    const q = query.trim().toLowerCase();
    return quotes.filter(
      (x) =>
        filter.match(x) &&
        (!q || [x.number, x.title, names.get(x.customer_id)].filter(Boolean).some((s) => s!.toLowerCase().includes(q))),
    );
  }, [quotes, filter, query, names]);

  const awaiting = quotes.filter((q) => q.status === "sent" || q.status === "viewed");
  const accepted = quotes.filter((q) => q.status === "accepted");
  const sum = (l: Quote[]) => l.reduce((s, q) => s + (q.total ?? 0), 0);
  const decided = quotes.filter((q) => q.status === "accepted" || q.status === "declined").length;

  return (
    <Page>
      <PageHeader
        title="Quotes"
        subtitle={`${quotes.length} quotes`}
        actions={
          ws.can("quotesManage") && (
            <Button onClick={() => setCreating(true)} className="press gap-1.5 bg-brand-orange hover:bg-brand-orange/90">
              <Plus className="h-4 w-4" /> New quote
            </Button>
          )
        }
      />

      {financial && (
        <div className="mb-6 grid gap-3 sm:grid-cols-3">
          <StatTile label="Awaiting an answer" value={money2(sum(awaiting), currency)} sub={`${awaiting.length} quotes out`} tone="orange" />
          <StatTile label="Accepted" value={money2(sum(accepted), currency)} sub={`${accepted.filter((q) => !q.converted_job_id).length} not yet booked`} tone="success" />
          <StatTile
            label="Win rate"
            value={decided ? `${Math.round((accepted.length / decided) * 100)}%` : "—"}
            sub="Accepted out of accepted or declined"
          />
        </div>
      )}

      <div className="mb-4 flex flex-wrap gap-1.5">
        {FILTERS.map((f) => (
          <button
            key={f.id}
            onClick={() => setParams({ filter: f.id })}
            className={cn(
              "press inline-flex items-center gap-1.5 rounded-full border px-3.5 py-1.5 text-sm font-medium transition-colors",
              filter.id === f.id ? "border-brand-orange bg-brand-orange text-white" : "border-border bg-card text-muted-foreground hover:text-foreground",
            )}
          >
            {f.label}
            <span className={cn("text-xs tabular-nums", filter.id === f.id ? "text-white/80" : "text-meta")}>{quotes.filter(f.match).length}</span>
          </button>
        ))}
      </div>

      <div className="card-surface overflow-hidden">
        <div className="border-b border-border p-3">
          <div className="relative">
            <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-meta" />
            <Input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Search number, title or customer…" className="h-10 border-0 bg-secondary pl-9 shadow-none" />
          </div>
        </div>
        {isLoading ? (
          <LoadingRows count={8} />
        ) : error ? (
          <p className="p-6 text-sm text-destructive">{(error as Error).message}</p>
        ) : list.length === 0 ? (
          <EmptyState icon={FileText} title={quotes.length ? "No quotes match" : "No quotes yet"} body={quotes.length ? "Try another filter." : "Create a quote, add line items and send it to the customer."} />
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full min-w-[860px] text-sm">
              <thead className="bg-secondary/50">
                <tr className="text-left">
                  <th className="section-label w-24 px-4 py-3">No.</th>
                  <th className="section-label px-4 py-3">Quote</th>
                  <th className="section-label px-4 py-3">Customer and site</th>
                  <th className="section-label w-36 px-4 py-3">Valid until</th>
                  {financial && <th className="section-label w-36 px-4 py-3 text-right">Total</th>}
                  <th className="section-label w-32 px-4 py-3">Status</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-border">
                {list.map((q) => (
                  <tr key={q.id} onClick={() => navigate(`/quotes/${q.id}`)} className="cursor-pointer transition-colors hover:bg-primary-tint/50">
                    <td className="px-4 py-3 font-semibold tabular-nums text-muted-foreground">{q.number}</td>
                    <td className="px-4 py-3">
                      <p className="font-medium">{q.title || "Untitled quote"}</p>
                      {q.converted_job_id && <p className="text-xs font-medium text-success">Booked as a job</p>}
                    </td>
                    <td className="px-4 py-3">
                      <p className="font-medium">{names.get(q.customer_id) ?? "—"}</p>
                      <p className="text-xs text-muted-foreground">{siteLine(siteMap.get(q.address_id))}</p>
                    </td>
                    <td className="px-4 py-3 tabular-nums">{dateOnly(q.valid_until)}</td>
                    {financial && <td className="px-4 py-3 text-right font-semibold tabular-nums">{money2(q.total ?? 0, currency)}</td>}
                    <td className="px-4 py-3">
                      <ToneBadge tone={QUOTE_STATUS[q.status].tone}>{QUOTE_STATUS[q.status].title}</ToneBadge>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
      {ws.can("quotesManage") && <NewQuoteDialog open={creating} onOpenChange={setCreating} />}
    </Page>
  );
}
