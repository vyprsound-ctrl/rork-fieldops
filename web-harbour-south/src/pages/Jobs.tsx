import { useMemo, useState } from "react";
import { useSearchParams } from "react-router-dom";
import { isSameDay } from "date-fns";
import { ArrowDown, ArrowUp, Briefcase, Search } from "lucide-react";

import { Page, useShell } from "@/components/hs/AppShell";
import { EmptyState, LoadingRows, PageHeader, StatusBadge, UrgentTag, WorkerAvatar, useJobPanel } from "@/components/hs/primitives";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { cn } from "@/lib/utils";
import { JOB_STATUSES, KIND_TITLE, isFieldActive, isOpen, shortAddress, statusTitle, type JobView } from "@/lib/domain";
import { dayAndTime } from "@/lib/format";
import { useJobs, useWorkers } from "@/lib/queries";
import { useWorkspace } from "@/lib/session";

const FILTERS = [
  { id: "open", label: "Open" },
  { id: "today", label: "Today" },
  { id: "unassigned", label: "Unassigned" },
  { id: "urgent", label: "Urgent" },
  { id: "active", label: "In the field" },
  { id: "done", label: "Finished" },
  { id: "all", label: "All" },
] as const;
type FilterId = (typeof FILTERS)[number]["id"];

type SortKey = "number" | "title" | "customer" | "when" | "worker" | "status";

const matches = (f: FilterId, j: JobView) => {
  switch (f) {
    case "open": return isOpen(j.status);
    case "today": return !!j.scheduled_start && isSameDay(new Date(j.scheduled_start), new Date());
    case "unassigned": return isOpen(j.status) && !j.workerId;
    case "urgent": return isOpen(j.status) && j.priority === "urgent";
    case "active": return isFieldActive(j.status);
    case "done": return !isOpen(j.status);
    case "all": return true;
  }
};

export default function Jobs() {
  const ws = useWorkspace();
  const shell = useShell();
  const panel = useJobPanel();
  const [params, setParams] = useSearchParams();
  const { data: jobs = [], isLoading, error } = useJobs();
  const { data: workers = [] } = useWorkers();

  const filter = (FILTERS.find((f) => f.id === params.get("filter"))?.id ?? "open") as FilterId;
  const [query, setQuery] = useState("");
  const [status, setStatus] = useState("any");
  const [worker, setWorker] = useState("any");
  const [sort, setSort] = useState<{ key: SortKey; asc: boolean }>({ key: "when", asc: true });

  const setFilter = (id: FilterId) =>
    setParams((p) => {
      const n = new URLSearchParams(p);
      n.set("filter", id);
      return n;
    });

  const counts = useMemo(() => Object.fromEntries(FILTERS.map((f) => [f.id, jobs.filter((j) => matches(f.id, j)).length])), [jobs]);

  const rows = useMemo(() => {
    const q = query.trim().toLowerCase();
    const list = jobs.filter(
      (j) =>
        matches(filter, j) &&
        (status === "any" || j.status === status) &&
        (worker === "any" || (worker === "none" ? !j.workerId : j.workerId === worker)) &&
        (!q ||
          [j.number, j.title, j.customer?.name, shortAddress(j.address), j.worker?.name]
            .filter(Boolean)
            .some((s) => s!.toLowerCase().includes(q))),
    );
    const val = (j: JobView): string => {
      switch (sort.key) {
        case "number": return j.number.padStart(12, "0");
        case "title": return j.title.toLowerCase();
        case "customer": return (j.customer?.name ?? "").toLowerCase();
        case "when": return j.scheduled_start ?? "9999";
        case "worker": return j.worker?.name ?? "~";
        case "status": return String(JOB_STATUSES.indexOf(j.status)).padStart(2, "0");
      }
    };
    return list.sort((a, b) => (sort.asc ? 1 : -1) * val(a).localeCompare(val(b)));
  }, [jobs, filter, status, worker, query, sort]);

  const header = (key: SortKey, label: string, className?: string) => (
    <th className={cn("px-4 py-3 text-left", className)}>
      <button
        onClick={() => setSort((s) => ({ key, asc: s.key === key ? !s.asc : true }))}
        className={cn("section-label inline-flex items-center gap-1 hover:text-foreground", sort.key === key && "text-primary")}
      >
        {label}
        {sort.key === key && (sort.asc ? <ArrowUp className="h-3 w-3" /> : <ArrowDown className="h-3 w-3" />)}
      </button>
    </th>
  );

  return (
    <Page>
      <PageHeader title="Jobs" subtitle={`${jobs.length} jobs in ${ws.company.name}`} />

      <div className="mb-4 flex flex-wrap gap-1.5">
        {FILTERS.map((f) => (
          <button
            key={f.id}
            onClick={() => setFilter(f.id)}
            className={cn(
              "press inline-flex items-center gap-1.5 rounded-full border px-3.5 py-1.5 text-sm font-medium transition-colors",
              filter === f.id
                ? "border-brand-orange bg-brand-orange text-white"
                : "border-border bg-card text-muted-foreground hover:text-foreground",
            )}
          >
            {f.label}
            <span className={cn("text-xs tabular-nums", filter === f.id ? "text-white/80" : "text-meta")}>{counts[f.id]}</span>
          </button>
        ))}
      </div>

      <div className="card-surface overflow-hidden">
        <div className="flex flex-wrap items-center gap-2 border-b border-border p-3">
          <div className="relative min-w-[240px] flex-1">
            <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-meta" />
            <Input
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Search number, title, customer, address…"
              className="h-10 border-0 bg-secondary pl-9 shadow-none"
            />
          </div>
          <Select value={status} onValueChange={setStatus}>
            <SelectTrigger className="h-10 w-[170px]">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="any">Any status</SelectItem>
              {JOB_STATUSES.map((s) => (
                <SelectItem key={s} value={s}>
                  {statusTitle(s, ws.terms)}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
          <Select value={worker} onValueChange={setWorker}>
            <SelectTrigger className="h-10 w-[180px]">
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              <SelectItem value="any">Any {ws.terms.worker}</SelectItem>
              <SelectItem value="none">Unassigned</SelectItem>
              {workers.map((w) => (
                <SelectItem key={w.id} value={w.id}>
                  {w.name}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>

        {isLoading ? (
          <LoadingRows count={8} />
        ) : error ? (
          <p className="p-6 text-sm text-destructive">{(error as Error).message}</p>
        ) : rows.length === 0 ? (
          <EmptyState
            icon={Briefcase}
            title="No jobs match"
            body="Try another filter or clear the search."
            action={
              ws.can("jobsManage") ? (
                <Button onClick={shell.newJob} className="bg-brand-orange hover:bg-brand-orange/90">
                  New job
                </Button>
              ) : undefined
            }
          />
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full min-w-[920px] text-sm">
              <thead className="bg-secondary/50">
                <tr>
                  {header("number", "No.", "w-28")}
                  {header("title", "Job")}
                  {header("customer", "Customer and site")}
                  {header("when", "When", "w-48")}
                  {header("worker", ws.terms.Worker, "w-48")}
                  {header("status", "Status", "w-44")}
                </tr>
              </thead>
              <tbody className="divide-y divide-border">
                {rows.map((j) => (
                  <tr
                    key={j.id}
                    onClick={() => panel.open(j.id)}
                    className={cn(
                      "cursor-pointer transition-colors hover:bg-primary-tint/50",
                      panel.jobId === j.id && "bg-brand-orange-tint/60",
                    )}
                  >
                    <td className="px-4 py-3 font-semibold tabular-nums text-muted-foreground">{j.number}</td>
                    <td className="px-4 py-3">
                      <div className="flex items-center gap-2">
                        <span className="font-medium">{j.title}</span>
                        {j.priority === "urgent" && <UrgentTag compact />}
                      </div>
                      <span className="text-xs text-meta">{KIND_TITLE[j.kind]}</span>
                    </td>
                    <td className="px-4 py-3">
                      <p className="font-medium">{j.customer?.name}</p>
                      <p className="text-xs text-muted-foreground">{shortAddress(j.address)}</p>
                    </td>
                    <td className="px-4 py-3 tabular-nums">{dayAndTime(j.scheduled_start)}</td>
                    <td className="px-4 py-3">
                      {j.worker ? (
                        <span className="flex items-center gap-2">
                          <WorkerAvatar name={j.worker.name} id={j.worker.id} size={24} />
                          <span className="truncate">{j.worker.name}</span>
                        </span>
                      ) : (
                        <span className="font-medium text-brand-orange-text">Unassigned</span>
                      )}
                    </td>
                    <td className="px-4 py-3">
                      <StatusBadge status={j.status} terms={ws.terms} />
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </Page>
  );
}
