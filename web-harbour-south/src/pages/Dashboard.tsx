import { useMemo } from "react";
import { Link } from "react-router-dom";
import { isSameDay, startOfDay } from "date-fns";
import { AlertCircle, ArrowRight, CalendarCheck2, Coffee, Flame, Inbox, Navigation, Plus } from "lucide-react";

import { Page, useShell } from "@/components/hs/AppShell";
import { EmptyState, LoadingRows, StatusBadge, UrgentTag, WorkerAvatar, useJobPanel } from "@/components/hs/primitives";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import { isFieldActive, isOpen, shortAddress, type JobView } from "@/lib/domain";
import { money, time, timeRange } from "@/lib/format";
import { useJobs, useMoney, useWorkers } from "@/lib/queries";
import { useWorkspace } from "@/lib/session";

function greeting() {
  const h = new Date().getHours();
  return h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening";
}

export default function Dashboard() {
  const ws = useWorkspace();
  const shell = useShell();
  const panel = useJobPanel();
  const { data: jobs = [], isLoading } = useJobs();
  const { data: workers = [] } = useWorkers();
  const moneyQuery = useMoney();

  const today = new Date();
  const stats = useMemo(() => {
    const todays = jobs
      .filter((j) => j.scheduled_start && isSameDay(new Date(j.scheduled_start), today) && j.status !== "cancelled")
      .sort((a, b) => (a.scheduled_start ?? "").localeCompare(b.scheduled_start ?? ""));
    const unassigned = jobs.filter((j) => isOpen(j.status) && !j.workerId);
    const urgent = jobs.filter((j) => isOpen(j.status) && j.priority === "urgent");
    const active = jobs.filter((j) => isFieldActive(j.status));
    const late = jobs.filter(
      (j) => j.status === "workerAssigned" && j.scheduled_start && new Date(j.scheduled_start) < new Date(Date.now() - 30 * 60_000),
    );
    const doneToday = todays.filter((j) => !isOpen(j.status)).length;
    return { todays, unassigned, urgent, active, late, doneToday };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [jobs, startOfDay(today).getTime()]);

  const progress = stats.todays.length ? stats.doneToday / stats.todays.length : 0;
  const m = moneyQuery.data;
  const currency = ws.company.currency_code || "USD";

  return (
    <Page>
      <div className="flex flex-wrap items-end justify-between gap-4 pb-8">
        <div>
          <p className="section-label">{today.toLocaleDateString(undefined, { weekday: "long", day: "numeric", month: "long" })}</p>
          <h1 className="mt-1 text-[32px] font-bold tracking-tight">
            {greeting()}, {ws.me.name.split(" ")[0]}
          </h1>
        </div>
        {ws.can("jobsManage") && (
          <Button onClick={shell.newJob} className="press gap-2 bg-brand-orange hover:bg-brand-orange/90">
            <Plus className="h-4 w-4" /> New job
            <kbd className="ml-1 rounded bg-white/20 px-1.5 text-[10px]">N</kbd>
          </Button>
        )}
      </div>

      {/* Hero: today's progress */}
      <div className="grid gap-4 lg:grid-cols-[1.4fr_1fr_1fr_1fr]">
        <div className="relative overflow-hidden rounded-[18px] bg-primary p-6 text-white shadow-panel">
          <div className="pointer-events-none absolute -bottom-24 -right-16 h-56 w-56 rounded-full border-[22px] border-brand-orange/80" />
          <p className="text-sm font-medium text-white/75">Today's jobs</p>
          <div className="mt-2 flex items-end gap-3">
            <span className="text-[56px] font-bold leading-none tabular-nums">{stats.todays.length}</span>
            <span className="pb-2 text-sm text-white/75">{stats.doneToday} finished</span>
          </div>
          <div className="mt-5 h-2 w-3/4 overflow-hidden rounded-full bg-white/20">
            <div className="h-full rounded-full bg-brand-orange transition-all duration-700" style={{ width: `${progress * 100}%` }} />
          </div>
        </div>
        <StatTile
          label="Unassigned"
          value={stats.unassigned.length}
          icon={Inbox}
          tone={stats.unassigned.length ? "orange" : "plain"}
          to="/jobs?filter=unassigned"
          hint={stats.unassigned.length ? "Waiting for a " + ws.terms.worker : "All covered"}
        />
        <StatTile
          label="Urgent open"
          value={stats.urgent.length}
          icon={Flame}
          tone={stats.urgent.length ? "red" : "plain"}
          to="/jobs?filter=urgent"
          hint="Priority call-outs"
        />
        <StatTile
          label="On the road"
          value={stats.active.length}
          icon={Navigation}
          tone="plain"
          to="/map"
          hint="Travelling or on site"
        />
      </div>

      {m && (
        <div className="mt-4 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          {m.quotesOut !== null && <MoneyTile label="Quotes out" value={money(m.quotesOut, currency)} />}
          {m.outstanding !== null && <MoneyTile label="Owed to you" value={money(m.outstanding, currency)} />}
          {m.overdue !== null && (
            <MoneyTile
              label="Overdue"
              value={money(m.overdue, currency)}
              sub={m.overdueCount ? `${m.overdueCount} invoice${m.overdueCount === 1 ? "" : "s"}` : "Nothing overdue"}
              danger={m.overdueCount > 0}
            />
          )}
          {m.paid30 !== null && <MoneyTile label="Paid in 30 days" value={money(m.paid30, currency)} good />}
        </div>
      )}

      <div className="mt-8 grid gap-6 xl:grid-cols-[1.6fr_1fr]">
        {/* Timeline */}
        <section className="card-surface overflow-hidden">
          <header className="flex items-center justify-between border-b border-border px-5 py-4">
            <h2 className="text-base font-semibold">Today's schedule</h2>
            <Link to="/dispatch" className="inline-flex items-center gap-1 text-sm font-medium text-primary hover:underline">
              Dispatch board <ArrowRight className="h-3.5 w-3.5" />
            </Link>
          </header>
          {isLoading ? (
            <LoadingRows />
          ) : stats.todays.length === 0 ? (
            <EmptyState icon={Coffee} title="Nothing booked today" body="New jobs you schedule for today will appear here." />
          ) : (
            <ul className="divide-y divide-border">
              {stats.todays.map((j) => (
                <TimelineRow key={j.id} job={j} onOpen={() => panel.open(j.id)} />
              ))}
            </ul>
          )}
        </section>

        <div className="space-y-6">
          {stats.late.length > 0 && (
            <section className="card-surface border-warning/40 p-5">
              <div className="flex items-center gap-2 text-warning">
                <AlertCircle className="h-4 w-4" />
                <h2 className="text-sm font-semibold">Running late</h2>
              </div>
              <p className="mt-1 text-xs text-muted-foreground">Due to start over 30 minutes ago and not on the way yet.</p>
              <ul className="mt-3 space-y-2">
                {stats.late.slice(0, 5).map((j) => (
                  <MiniRow key={j.id} job={j} onOpen={() => panel.open(j.id)} />
                ))}
              </ul>
            </section>
          )}

          <section className="card-surface p-5">
            <div className="flex items-center justify-between">
              <h2 className="text-sm font-semibold">Needs a {ws.terms.worker}</h2>
              <span className="rounded-full bg-brand-orange-tint px-2 py-0.5 text-xs font-bold text-brand-orange-text">
                {stats.unassigned.length}
              </span>
            </div>
            {stats.unassigned.length === 0 ? (
              <p className="mt-3 flex items-center gap-2 text-sm text-muted-foreground">
                <CalendarCheck2 className="h-4 w-4 text-success" /> Every open job has someone on it.
              </p>
            ) : (
              <ul className="mt-3 space-y-2">
                {stats.unassigned.slice(0, 6).map((j) => (
                  <MiniRow key={j.id} job={j} onOpen={() => panel.open(j.id)} />
                ))}
              </ul>
            )}
          </section>

          <section className="card-surface p-5">
            <h2 className="text-sm font-semibold">{ws.terms.WorkerPlural} today</h2>
            <ul className="mt-3 space-y-3">
              {workers.map((w) => {
                const mine = stats.todays.filter((j) => j.workerId === w.id);
                const live = stats.active.find((j) => j.workerId === w.id);
                return (
                  <li key={w.id} className="flex items-center gap-3">
                    <WorkerAvatar name={w.name} id={w.id} size={32} />
                    <div className="min-w-0 flex-1">
                      <p className="truncate text-sm font-medium">{w.name}</p>
                      <p className="truncate text-xs text-muted-foreground">
                        {live ? `${live.status === "travelling" ? "Travelling to" : "On site at"} ${live.customer?.name ?? live.number}` : mine.length ? `${mine.length} job${mine.length === 1 ? "" : "s"} today` : "Free today"}
                      </p>
                    </div>
                    {live && <span className="h-2 w-2 rounded-full bg-brand-orange shadow-[0_0_0_4px_hsl(var(--brand-orange-tint))]" />}
                  </li>
                );
              })}
              {workers.length === 0 && <p className="text-sm text-muted-foreground">No active {ws.terms.workerPlural} yet.</p>}
            </ul>
          </section>
        </div>
      </div>
    </Page>
  );
}

function StatTile({
  label,
  value,
  icon: Icon,
  tone,
  to,
  hint,
}: {
  label: string;
  value: number;
  icon: typeof Inbox;
  tone: "orange" | "red" | "plain";
  to: string;
  hint: string;
}) {
  return (
    <Link to={to} className="card-surface press group block p-5 transition-shadow hover:shadow-panel">
      <div className="flex items-center justify-between">
        <p className="text-sm font-medium text-muted-foreground">{label}</p>
        <span
          className={cn(
            "flex h-9 w-9 items-center justify-center rounded-xl",
            tone === "orange" && "bg-brand-orange-tint text-brand-orange",
            tone === "red" && "bg-[hsl(6_80%_95%)] text-destructive",
            tone === "plain" && "bg-primary-tint text-primary",
          )}
        >
          <Icon className="h-[18px] w-[18px]" />
        </span>
      </div>
      <p className="mt-3 text-[40px] font-bold leading-none tabular-nums">{value}</p>
      <p className="mt-2 flex items-center gap-1 text-xs text-muted-foreground">
        {hint}
        <ArrowRight className="h-3 w-3 opacity-0 transition-opacity group-hover:opacity-100" />
      </p>
    </Link>
  );
}

function MoneyTile({ label, value, sub, danger, good }: { label: string; value: string; sub?: string; danger?: boolean; good?: boolean }) {
  return (
    <div className="card-surface px-5 py-4">
      <p className="section-label">{label}</p>
      <p className={cn("mt-1.5 text-2xl font-bold tabular-nums", danger && "text-destructive", good && "text-success")}>{value}</p>
      {sub && <p className="mt-0.5 text-xs text-muted-foreground">{sub}</p>}
    </div>
  );
}

function TimelineRow({ job, onOpen }: { job: JobView; onOpen: () => void }) {
  const ws = useWorkspace();
  const past = !isOpen(job.status);
  return (
    <li>
      <button onClick={onOpen} className={cn("flex w-full items-center gap-4 px-5 py-3.5 text-left transition-colors hover:bg-secondary/60", past && "opacity-60")}>
        <div className="w-24 shrink-0 text-sm font-semibold tabular-nums">{timeRange(job.scheduled_start, job.scheduled_end)}</div>
        <div className={cn("h-10 w-1 shrink-0 rounded-full", job.priority === "urgent" ? "bg-brand-orange" : "bg-primary/30")} />
        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-2">
            <p className="truncate font-medium">{job.title}</p>
            {job.priority === "urgent" && <UrgentTag compact />}
          </div>
          <p className="truncate text-xs text-muted-foreground">
            {job.customer?.name} · {shortAddress(job.address)}
          </p>
        </div>
        <div className="hidden w-40 items-center gap-2 lg:flex">
          {job.worker ? (
            <>
              <WorkerAvatar name={job.worker.name} id={job.worker.id} size={24} />
              <span className="truncate text-sm">{job.worker.name}</span>
            </>
          ) : (
            <span className="text-sm font-medium text-brand-orange-text">Unassigned</span>
          )}
        </div>
        <StatusBadge status={job.status} terms={ws.terms} />
      </button>
    </li>
  );
}

function MiniRow({ job, onOpen }: { job: JobView; onOpen: () => void }) {
  return (
    <li>
      <button onClick={onOpen} className="flex w-full items-center gap-3 rounded-xl px-2 py-1.5 text-left hover:bg-secondary">
        <span className="w-14 shrink-0 text-xs font-semibold tabular-nums text-muted-foreground">
          {job.scheduled_start ? time(job.scheduled_start) : "—"}
        </span>
        <span className="min-w-0 flex-1 truncate text-sm">{job.title}</span>
        {job.priority === "urgent" && <Flame className="h-3.5 w-3.5 text-brand-orange" />}
      </button>
    </li>
  );
}
