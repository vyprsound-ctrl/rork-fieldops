import { useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";

import { Page } from "@/components/hs/AppShell";
import { LoadingRows, PageHeader, WorkerAvatar } from "@/components/hs/primitives";
import { Section, StatTile } from "@/components/hs/crm";
import { cn } from "@/lib/utils";
import { supabase } from "@/lib/supabase";
import { rows } from "@/lib/api";
import { PAYMENT_METHOD_TITLE, effectiveStatus, isReceivable, type PaymentMethod } from "@/lib/crm";
import { KIND_TITLE, PIPELINE, isOpen, statusTitle, type JobKind } from "@/lib/domain";
import { dateOnly, money, money2, shortDate } from "@/lib/format";
import { useCustomers, useInvoices, useJobs } from "@/lib/queries";
import { useWorkspace } from "@/lib/session";

const RANGES = [
  { id: 7, label: "7 days" },
  { id: 30, label: "30 days" },
  { id: 90, label: "90 days" },
  { id: 365, label: "12 months" },
];

interface PaymentRow {
  id: string;
  invoice_id: string;
  amount: string;
  method: PaymentMethod;
  status: string;
  received_at: string;
  paid_by_customer: boolean;
}

const DAY = 86_400_000;

function Bars({ items, format }: { items: { label: string; value: number; tone?: string }[]; format?: (n: number) => string }) {
  const max = Math.max(1, ...items.map((i) => i.value));
  return (
    <ul className="grid gap-2.5 px-5 py-4">
      {items.map((i) => (
        <li key={i.label} className="grid grid-cols-[140px_1fr_auto] items-center gap-3 text-sm">
          <span className="truncate text-muted-foreground">{i.label}</span>
          <span className="h-2.5 overflow-hidden rounded-full bg-secondary">
            <span className={cn("block h-full rounded-full", i.tone ?? "bg-primary")} style={{ width: `${(i.value / max) * 100}%` }} />
          </span>
          <span className="min-w-[56px] text-right font-semibold tabular-nums">{format ? format(i.value) : i.value}</span>
        </li>
      ))}
    </ul>
  );
}

export default function Reports() {
  const ws = useWorkspace();
  const ops = ws.can("reportsOperational") && ws.can("jobsReadAll");
  const fin = ws.can("reportsFinancial") && ws.can("invoicesRead");
  const [range, setRange] = useState(30);
  const currency = ws.company.currency_code;
  const since = Date.now() - range * DAY;

  return (
    <Page>
      <PageHeader
        title="Reports"
        subtitle="Live figures from the same data as the iPhone app."
        actions={
          <div className="flex gap-1 rounded-full border border-border bg-card p-1">
            {RANGES.map((r) => (
              <button
                key={r.id}
                onClick={() => setRange(r.id)}
                className={cn(
                  "press rounded-full px-3 py-1 text-sm font-medium transition-colors",
                  range === r.id ? "bg-primary text-primary-foreground" : "text-muted-foreground hover:text-foreground",
                )}
              >
                {r.label}
              </button>
            ))}
          </div>
        }
      />
      <div className="grid gap-8">
        {ops && <Operational since={since} />}
        {fin && <Financial since={since} currency={currency} />}
      </div>
    </Page>
  );
}

function Operational({ since }: { since: number }) {
  const ws = useWorkspace();
  const { data: jobs = [], isLoading } = useJobs();

  const stats = useMemo(() => {
    const when = (j: (typeof jobs)[number]) => new Date(j.scheduled_start ?? j.created_at).getTime();
    const inRange = jobs.filter((j) => when(j) >= since && when(j) <= Date.now() + DAY);
    const done = inRange.filter((j) => ["completed", "invoiced", "paid"].includes(j.status));
    const counted = inRange.filter((j) => j.status !== "cancelled");
    const open = jobs.filter((j) => isOpen(j.status));
    const byWorker = new Map<string, { name: string; id: string; done: number }>();
    for (const j of done) {
      if (!j.worker) continue;
      const cur = byWorker.get(j.worker.id) ?? { name: j.worker.name, id: j.worker.id, done: 0 };
      cur.done += 1;
      byWorker.set(j.worker.id, cur);
    }
    const kinds = (Object.keys(KIND_TITLE) as JobKind[]).map((k) => ({ label: KIND_TITLE[k], value: inRange.filter((j) => j.kind === k).length }));
    return {
      open: open.length,
      unscheduled: open.filter((j) => !j.scheduled_start).length,
      scheduled: inRange.length,
      done: done.length,
      cancelled: inRange.length - counted.length,
      rate: counted.length ? Math.round((done.length / counted.length) * 100) : null,
      pipeline: PIPELINE.map((s) => ({ label: statusTitle(s, ws.terms), value: open.filter((j) => j.status === s).length })).filter((p) => p.value > 0),
      kinds,
      workers: [...byWorker.values()].sort((a, b) => b.done - a.done),
    };
  }, [jobs, since, ws.terms]);

  if (isLoading) return <LoadingRows count={4} />;

  return (
    <div className="grid gap-4">
      <h2 className="section-label">Jobs</h2>
      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <StatTile label="Open now" value={String(stats.open)} sub={`${stats.unscheduled} without a date`} tone={stats.unscheduled ? "orange" : undefined} />
        <StatTile label="Jobs in period" value={String(stats.scheduled)} sub={`${stats.cancelled} cancelled`} />
        <StatTile label="Completed" value={String(stats.done)} tone="success" sub="Completed, invoiced or paid" />
        <StatTile label="Completion rate" value={stats.rate == null ? "—" : `${stats.rate}%`} sub="Of jobs not cancelled" />
      </div>
      <div className="grid gap-4 lg:grid-cols-2">
        <Section title="Open jobs by stage">
          {stats.pipeline.length ? <Bars items={stats.pipeline} /> : <p className="px-5 py-6 text-sm text-muted-foreground">No open jobs.</p>}
        </Section>
        <Section title="Jobs by type">
          <Bars items={stats.kinds} />
        </Section>
      </div>
      <Section title={`Completed by ${ws.terms.worker}`}>
        {stats.workers.length === 0 ? (
          <p className="px-5 py-6 text-sm text-muted-foreground">No completed jobs with a {ws.terms.worker} in this period.</p>
        ) : (
          <ul className="divide-y divide-border">
            {stats.workers.map((w) => (
              <li key={w.id} className="flex items-center gap-3 px-5 py-3 text-sm">
                <WorkerAvatar name={w.name} id={w.id} />
                <span className="flex-1 font-medium">{w.name}</span>
                <span className="font-semibold tabular-nums">{w.done}</span>
              </li>
            ))}
          </ul>
        )}
      </Section>
    </div>
  );
}

function Financial({ since, currency }: { since: number; currency: string }) {
  const ws = useWorkspace();
  const canPayments = ws.can("paymentsRead");
  const { data: invoices = [], isLoading } = useInvoices();
  const { data: customers = [] } = useCustomers();
  const { data: payments = [] } = useQuery({
    queryKey: ["reports", "payments"],
    enabled: canPayments,
    queryFn: () =>
      rows<PaymentRow>(
        supabase
          .from("payments")
          .select("id,invoice_id,amount::text,method,status,received_at,paid_by_customer")
          .eq("status", "succeeded")
          .order("received_at", { ascending: false })
          .limit(1000),
      ),
  });

  const names = useMemo(() => new Map(customers.map((c) => [c.id, c.name])), [customers]);
  const invoiceById = useMemo(() => new Map(invoices.map((i) => [i.id, i])), [invoices]);

  const s = useMemo(() => {
    const now = Date.now();
    const shown = invoices.map((i) => ({ ...i, shown: effectiveStatus(i) }));
    const receivable = shown.filter((i) => isReceivable(i.shown));
    const overdue = receivable.filter((i) => i.shown === "overdue");
    const week = receivable.filter((i) => {
      const due = new Date(`${i.due_date}T23:59:59`).getTime();
      return due >= now && due <= now + 7 * DAY;
    });
    const sum = (l: { balance: number }[]) => l.reduce((t, i) => t + i.balance, 0);
    const daysLate = (d: string) => Math.floor((now - new Date(`${d}T23:59:59`).getTime()) / DAY);
    const aging = [
      { label: "1–30 days late", value: sum(overdue.filter((i) => daysLate(i.due_date) <= 30)), tone: "bg-warning" },
      { label: "31–60 days late", value: sum(overdue.filter((i) => daysLate(i.due_date) > 30 && daysLate(i.due_date) <= 60)), tone: "bg-brand-orange" },
      { label: "61–90 days late", value: sum(overdue.filter((i) => daysLate(i.due_date) > 60 && daysLate(i.due_date) <= 90)), tone: "bg-destructive" },
      { label: "Over 90 days", value: sum(overdue.filter((i) => daysLate(i.due_date) > 90)), tone: "bg-destructive" },
    ];
    const owing = new Map<string, number>();
    for (const i of receivable) owing.set(i.customer_id, (owing.get(i.customer_id) ?? 0) + i.balance);
    const issued = shown.filter((i) => i.status !== "draft" && i.shown !== "void" && new Date(`${i.issue_date}T12:00:00`).getTime() >= since);
    const paid = payments.filter((p) => new Date(p.received_at).getTime() >= since);
    const collected = paid.reduce((t, p) => t + (Number(p.amount) || 0), 0);
    const online = paid.filter((p) => p.paid_by_customer).reduce((t, p) => t + (Number(p.amount) || 0), 0);
    return {
      outstanding: sum(receivable),
      receivableCount: receivable.length,
      overdue: sum(overdue),
      overdueCount: overdue.length,
      week: sum(week),
      weekCount: week.length,
      aging,
      topOwing: [...owing.entries()].sort((a, b) => b[1] - a[1]).slice(0, 6),
      invoiced: issued.reduce((t, i) => t + i.total, 0),
      invoicedCount: issued.length,
      collected,
      online,
      recent: paid.slice(0, 8),
    };
  }, [invoices, payments, since]);

  if (isLoading) return <LoadingRows count={4} />;

  return (
    <div className="grid gap-4">
      <h2 className="section-label">Money</h2>
      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <StatTile label="Outstanding" value={money(s.outstanding, currency)} sub={`${s.receivableCount} unpaid invoices`} tone="orange" />
        <StatTile label="Overdue" value={money(s.overdue, currency)} sub={s.overdueCount ? `${s.overdueCount} past due` : "Nothing overdue"} tone={s.overdueCount ? "danger" : undefined} />
        <StatTile label="Due in 7 days" value={money(s.week, currency)} sub={`${s.weekCount} invoices`} />
        {canPayments ? (
          <StatTile label="Collected in period" value={money(s.collected, currency)} sub={s.online ? `${money(s.online, currency)} paid online` : "Recorded payments"} tone="success" />
        ) : (
          <StatTile label="Invoiced in period" value={money(s.invoiced, currency)} sub={`${s.invoicedCount} invoices`} />
        )}
      </div>
      <div className="grid gap-4 lg:grid-cols-2">
        <Section title="Overdue by age">
          <Bars items={s.aging} format={(n) => money(n, currency)} />
        </Section>
        <Section title="Who owes the most">
          {s.topOwing.length === 0 ? (
            <p className="px-5 py-6 text-sm text-muted-foreground">Nobody owes anything right now.</p>
          ) : (
            <ul className="divide-y divide-border">
              {s.topOwing.map(([id, amount]) => (
                <li key={id} className="flex items-center justify-between gap-3 px-5 py-3 text-sm">
                  <span className="font-medium">{names.get(id) ?? "—"}</span>
                  <span className="font-semibold tabular-nums">{money2(amount, currency)}</span>
                </li>
              ))}
            </ul>
          )}
        </Section>
      </div>
      {canPayments && (
        <Section title="Recent payments">
          {s.recent.length === 0 ? (
            <p className="px-5 py-6 text-sm text-muted-foreground">No payments in this period.</p>
          ) : (
            <table className="w-full text-sm">
              <tbody className="divide-y divide-border">
                {s.recent.map((p) => {
                  const inv = invoiceById.get(p.invoice_id);
                  return (
                    <tr key={p.id}>
                      <td className="px-5 py-3 tabular-nums text-muted-foreground">{shortDate(p.received_at)}</td>
                      <td className="px-5 py-3">
                        <p className="font-medium">{inv ? names.get(inv.customer_id) ?? "—" : "—"}</p>
                        {inv && <p className="text-xs text-muted-foreground">Invoice {inv.number} · due {dateOnly(inv.due_date)}</p>}
                      </td>
                      <td className="px-5 py-3 text-muted-foreground">{PAYMENT_METHOD_TITLE[p.method] ?? p.method}</td>
                      <td className="px-5 py-3 text-right font-semibold tabular-nums">{money2(Number(p.amount) || 0, currency)}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          )}
        </Section>
      )}
    </div>
  );
}
