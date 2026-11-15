import { useMemo, useState } from "react";
import { useNavigate, useSearchParams } from "react-router-dom";
import { Plus, Receipt, Search } from "lucide-react";

import { Page } from "@/components/hs/AppShell";
import { EmptyState, LoadingRows, PageHeader } from "@/components/hs/primitives";
import { StatTile, ToneBadge } from "@/components/hs/crm";
import { NewInvoiceDialog } from "@/components/hs/crmDialogs";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import { INVOICE_STATUS, effectiveStatus, isReceivable, type Invoice, type InvoiceStatus } from "@/lib/crm";
import { dateOnly, money2 } from "@/lib/format";
import { useCustomers, useInvoices } from "@/lib/queries";
import { useWorkspace } from "@/lib/session";
import { Input } from "@/components/ui/input";

type Row = Invoice & { shown: InvoiceStatus };

const FILTERS: { id: string; label: string; match: (r: Row) => boolean }[] = [
  { id: "outstanding", label: "Outstanding", match: (r) => isReceivable(r.shown) },
  { id: "overdue", label: "Overdue", match: (r) => r.shown === "overdue" },
  { id: "draft", label: "Drafts", match: (r) => r.shown === "draft" },
  { id: "paid", label: "Paid", match: (r) => r.shown === "paid" },
  { id: "void", label: "Void", match: (r) => r.shown === "void" },
  { id: "all", label: "All", match: () => true },
];

export default function Invoices() {
  const ws = useWorkspace();
  const navigate = useNavigate();
  const [params, setParams] = useSearchParams();
  const { data: invoices = [], isLoading, error } = useInvoices();
  const { data: customers = [] } = useCustomers();
  const [query, setQuery] = useState("");
  const [creating, setCreating] = useState(false);
  const currency = ws.company.currency_code;

  const filter = FILTERS.find((f) => f.id === params.get("filter")) ?? FILTERS[5];
  const names = useMemo(() => new Map(customers.map((c) => [c.id, c.name])), [customers]);
  const all: Row[] = useMemo(() => invoices.map((i) => ({ ...i, shown: effectiveStatus(i) })), [invoices]);

  const list = useMemo(() => {
    const q = query.trim().toLowerCase();
    return all.filter(
      (x) =>
        filter.match(x) &&
        (!q || [x.number, x.title, names.get(x.customer_id)].filter(Boolean).some((s) => s!.toLowerCase().includes(q))),
    );
  }, [all, filter, query, names]);

  const outstanding = all.filter((r) => isReceivable(r.shown));
  const overdue = all.filter((r) => r.shown === "overdue");
  const monthAgo = Date.now() - 30 * 86_400_000;
  const paid30 = all.filter((r) => r.shown === "paid" && r.paid_at && new Date(r.paid_at).getTime() >= monthAgo);
  const sum = (l: Row[], k: "balance" | "total") => l.reduce((s, r) => s + r[k], 0);

  return (
    <Page>
      <PageHeader
        title="Invoices"
        subtitle={`${invoices.length} invoices`}
        actions={
          ws.can("invoicesManage") && (
            <Button onClick={() => setCreating(true)} className="press gap-1.5 bg-brand-orange hover:bg-brand-orange/90">
              <Plus className="h-4 w-4" /> New invoice
            </Button>
          )
        }
      />

      <div className="mb-6 grid gap-3 sm:grid-cols-3">
        <StatTile label="Outstanding" value={money2(sum(outstanding, "balance"), currency)} sub={`${outstanding.length} unpaid invoices`} tone="orange" />
        <StatTile
          label="Overdue"
          value={money2(sum(overdue, "balance"), currency)}
          sub={overdue.length ? `${overdue.length} past their due date` : "Nothing overdue"}
          tone={overdue.length ? "danger" : undefined}
        />
        <StatTile label="Paid in the last 30 days" value={money2(sum(paid30, "total"), currency)} sub={`${paid30.length} invoices`} tone="success" />
      </div>

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
            <span className={cn("text-xs tabular-nums", filter.id === f.id ? "text-white/80" : "text-meta")}>{all.filter(f.match).length}</span>
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
          <EmptyState
            icon={Receipt}
            title={invoices.length ? "No invoices match" : "No invoices yet"}
            body={invoices.length ? "Try another filter." : "Invoice a completed job from its customer page, or create one here."}
          />
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full min-w-[900px] text-sm">
              <thead className="bg-secondary/50">
                <tr className="text-left">
                  <th className="section-label w-24 px-4 py-3">No.</th>
                  <th className="section-label px-4 py-3">Customer</th>
                  <th className="section-label w-32 px-4 py-3">Issued</th>
                  <th className="section-label w-32 px-4 py-3">Due</th>
                  <th className="section-label w-32 px-4 py-3 text-right">Total</th>
                  <th className="section-label w-32 px-4 py-3 text-right">Balance</th>
                  <th className="section-label w-28 px-4 py-3">Status</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-border">
                {list.map((r) => (
                  <tr key={r.id} onClick={() => navigate(`/invoices/${r.id}`)} className="cursor-pointer transition-colors hover:bg-primary-tint/50">
                    <td className="px-4 py-3 font-semibold tabular-nums text-muted-foreground">{r.number}</td>
                    <td className="px-4 py-3">
                      <p className="font-medium">{names.get(r.customer_id) ?? "—"}</p>
                      {r.title && <p className="text-xs text-muted-foreground">{r.title}</p>}
                    </td>
                    <td className="px-4 py-3 tabular-nums">{r.status === "draft" ? <span className="text-meta">Not issued</span> : dateOnly(r.issue_date)}</td>
                    <td className={cn("px-4 py-3 tabular-nums", r.shown === "overdue" && "font-semibold text-destructive")}>{dateOnly(r.due_date)}</td>
                    <td className="px-4 py-3 text-right tabular-nums">{money2(r.total, r.currency_code || currency)}</td>
                    <td className="px-4 py-3 text-right font-semibold tabular-nums">
                      {isReceivable(r.shown) ? money2(r.balance, r.currency_code || currency) : <span className="font-normal text-meta">—</span>}
                    </td>
                    <td className="px-4 py-3">
                      <ToneBadge tone={INVOICE_STATUS[r.shown].tone}>{INVOICE_STATUS[r.shown].title}</ToneBadge>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
      {ws.can("invoicesManage") && <NewInvoiceDialog open={creating} onOpenChange={setCreating} />}
    </Page>
  );
}
