import { useMemo, useRef, useState } from "react";
import { addDays, format, isSameDay, startOfDay } from "date-fns";
import { ChevronLeft, ChevronRight, Flame, GripVertical, Inbox, Info } from "lucide-react";

import { Page } from "@/components/hs/AppShell";
import { useScheduleActions } from "@/components/hs/ClashGuard";
import { PageHeader, TONE_CLASS, WorkerAvatar, useJobPanel } from "@/components/hs/primitives";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import { dayTitle, timeRange } from "@/lib/format";
import { isOpen, shortAddress, slot, statusTone, type JobView } from "@/lib/domain";
import { useJobs, useWorkers } from "@/lib/queries";
import { useWorkspace } from "@/lib/session";

const START_HOUR = 6;
const END_HOUR = 21;
const HOURS = END_HOUR - START_HOUR;
const HOUR_PX = 96;
const ROW_PX = 76;

export default function Dispatch() {
  const ws = useWorkspace();
  const panel = useJobPanel();
  const { data: jobs = [] } = useJobs();
  const { data: workers = [] } = useWorkers();
  const actions = useScheduleActions();
  const [day, setDay] = useState(() => startOfDay(new Date()));
  const [dragId, setDragId] = useState<string | null>(null);
  const [hover, setHover] = useState<{ row: string; hour: number } | null>(null);
  const canDrag = ws.can("assignmentsManage") && ws.can("jobsManage");

  const dayJobs = useMemo(
    () => jobs.filter((j) => j.status !== "cancelled" && j.scheduled_start && isSameDay(new Date(j.scheduled_start), day)),
    [jobs, day],
  );
  const tray = useMemo(
    () =>
      jobs
        .filter((j) => isOpen(j.status) && !j.workerId)
        .sort((a, b) => (a.scheduled_start ?? "9").localeCompare(b.scheduled_start ?? "9")),
    [jobs],
  );

  const dragJob = dragId ? jobs.find((j) => j.id === dragId) : undefined;

  const dropAt = (workerId: string | null, hour: number | null) => {
    setHover(null);
    if (!dragJob) return;
    const worker = workers.find((w) => w.id === workerId);
    let start = dragJob.scheduled_start;
    let end = dragJob.scheduled_end;
    if (hour !== null) {
      const s = slot(dragJob);
      const duration = s ? s[1] - s[0] : 2 * 3600_000;
      const startDate = new Date(day.getTime() + hour * 3600_000);
      start = startDate.toISOString();
      end = new Date(startDate.getTime() + duration).toISOString();
    }
    actions.move(dragJob, workerId, start, end, worker?.name);
    setDragId(null);
  };

  const now = new Date();
  const nowOffset = isSameDay(now, day) ? (now.getHours() + now.getMinutes() / 60 - START_HOUR) * HOUR_PX : null;

  return (
    <Page className="max-w-none">
      <PageHeader
        title="Dispatch"
        subtitle={canDrag ? `Drag a job onto a ${ws.terms.worker}'s row to assign it, or along the row to change the time.` : "Your team's day at a glance."}
        actions={
          <div className="flex items-center gap-1 rounded-xl border border-border bg-card p-1">
            <Button variant="ghost" size="icon" className="h-8 w-8" onClick={() => setDay((d) => addDays(d, -1))} aria-label="Previous day">
              <ChevronLeft className="h-4 w-4" />
            </Button>
            <button onClick={() => setDay(startOfDay(new Date()))} className="min-w-[150px] px-2 text-sm font-semibold">
              {dayTitle(day)} <span className="font-normal text-muted-foreground">· {format(day, "d MMM")}</span>
            </button>
            <Button variant="ghost" size="icon" className="h-8 w-8" onClick={() => setDay((d) => addDays(d, 1))} aria-label="Next day">
              <ChevronRight className="h-4 w-4" />
            </Button>
          </div>
        }
      />

      <div className="grid gap-5 xl:grid-cols-[300px_1fr]">
        {/* Unassigned tray */}
        <aside
          className={cn(
            "card-surface flex max-h-[calc(100vh-200px)] flex-col overflow-hidden transition-colors",
            dragJob?.workerId && "ring-2 ring-brand-orange/40",
          )}
          onDragOver={(e) => dragJob?.workerId && e.preventDefault()}
          onDrop={() => dropAt(null, null)}
        >
          <header className="flex items-center justify-between border-b border-border px-4 py-3">
            <div className="flex items-center gap-2">
              <Inbox className="h-4 w-4 text-brand-orange" />
              <h2 className="text-sm font-semibold">Unassigned</h2>
            </div>
            <span className="rounded-full bg-brand-orange-tint px-2 py-0.5 text-xs font-bold text-brand-orange-text">{tray.length}</span>
          </header>
          <div className="flex-1 space-y-2 overflow-y-auto p-3 scroll-thin">
            {tray.length === 0 && <p className="px-1 py-6 text-center text-sm text-muted-foreground">Every open job has someone on it.</p>}
            {tray.map((j) => (
              <div
                key={j.id}
                draggable={canDrag}
                onDragStart={(e) => {
                  e.dataTransfer.effectAllowed = "move";
                  setDragId(j.id);
                }}
                onDragEnd={() => (setDragId(null), setHover(null))}
                onClick={() => panel.open(j.id)}
                className={cn(
                  "group flex cursor-pointer gap-2 rounded-xl border border-border bg-card p-3 transition-all hover:border-primary/40 hover:shadow-panel",
                  canDrag && "cursor-grab active:cursor-grabbing",
                  dragId === j.id && "opacity-40",
                )}
              >
                {canDrag && <GripVertical className="mt-0.5 h-4 w-4 shrink-0 text-meta" />}
                <div className="min-w-0 flex-1">
                  <div className="flex items-center gap-1.5">
                    {j.priority === "urgent" && <Flame className="h-3.5 w-3.5 shrink-0 text-brand-orange" />}
                    <p className="truncate text-sm font-medium">{j.title}</p>
                  </div>
                  <p className="truncate text-xs text-muted-foreground">{j.customer?.name}</p>
                  <p className="mt-1 text-xs font-medium tabular-nums text-primary">
                    {j.scheduled_start ? `${dayTitle(new Date(j.scheduled_start))} · ${timeRange(j.scheduled_start, j.scheduled_end)}` : "Unscheduled"}
                  </p>
                </div>
              </div>
            ))}
          </div>
          {canDrag && dragJob?.workerId && (
            <p className="border-t border-border bg-brand-orange-tint px-4 py-2 text-xs font-medium text-brand-orange-text">
              Drop here to unassign
            </p>
          )}
        </aside>

        {/* Timeline */}
        <section className="card-surface overflow-hidden">
          <div className="overflow-x-auto scroll-thin">
            <div style={{ width: 200 + HOURS * HOUR_PX }}>
              <div className="sticky top-0 z-10 flex border-b border-border bg-secondary/60">
                <div className="w-[200px] shrink-0 px-4 py-2.5 section-label">{ws.terms.WorkerPlural}</div>
                {Array.from({ length: HOURS }).map((_, i) => (
                  <div key={i} className="shrink-0 border-l border-border px-2 py-2.5 text-xs font-medium tabular-nums text-muted-foreground" style={{ width: HOUR_PX }}>
                    {String(START_HOUR + i).padStart(2, "0")}:00
                  </div>
                ))}
              </div>

              {workers.length === 0 && (
                <p className="flex items-center gap-2 p-6 text-sm text-muted-foreground">
                  <Info className="h-4 w-4" /> No active {ws.terms.workerPlural}. Invite them from the iPhone app's Team screen.
                </p>
              )}

              {workers.map((w) => {
                const mine = dayJobs.filter((j) => j.workerId === w.id);
                return (
                  <div key={w.id} className="flex border-b border-border last:border-b-0">
                    <div className="flex w-[200px] shrink-0 items-center gap-2.5 px-4" style={{ height: ROW_PX }}>
                      <WorkerAvatar name={w.name} id={w.id} size={32} />
                      <div className="min-w-0">
                        <p className="truncate text-sm font-semibold">{w.name}</p>
                        <p className="text-xs text-muted-foreground">
                          {mine.length} job{mine.length === 1 ? "" : "s"}
                        </p>
                      </div>
                    </div>
                    <TimelineRow
                      rowId={w.id}
                      jobs={mine}
                      dragJob={dragJob}
                      hover={hover?.row === w.id ? hover.hour : null}
                      nowOffset={nowOffset}
                      canDrag={canDrag}
                      onHover={(hour) => setHover(hour === null ? null : { row: w.id, hour })}
                      onDrop={(hour) => dropAt(w.id, hour)}
                      onDragStart={setDragId}
                      onDragEnd={() => (setDragId(null), setHover(null))}
                      onOpen={panel.open}
                      dragId={dragId}
                    />
                  </div>
                );
              })}
            </div>
          </div>
        </section>
      </div>
      {actions.dialog}
    </Page>
  );
}

function TimelineRow({
  rowId,
  jobs,
  dragJob,
  hover,
  nowOffset,
  canDrag,
  dragId,
  onHover,
  onDrop,
  onDragStart,
  onDragEnd,
  onOpen,
}: {
  rowId: string;
  jobs: JobView[];
  dragJob?: JobView;
  hover: number | null;
  nowOffset: number | null;
  canDrag: boolean;
  dragId: string | null;
  onHover: (hour: number | null) => void;
  onDrop: (hour: number) => void;
  onDragStart: (id: string) => void;
  onDragEnd: () => void;
  onOpen: (id: string) => void;
}) {
  const ws = useWorkspace();
  const ref = useRef<HTMLDivElement>(null);

  const hourAt = (clientX: number) => {
    const rect = ref.current!.getBoundingClientRect();
    const raw = (clientX - rect.left) / HOUR_PX + START_HOUR;
    return Math.min(END_HOUR - 0.5, Math.max(START_HOUR, Math.round(raw * 2) / 2));
  };

  const dragDuration = dragJob ? (() => {
    const s = slot(dragJob);
    return s ? (s[1] - s[0]) / 3600_000 : 2;
  })() : 0;

  return (
    <div
      ref={ref}
      className="relative shrink-0"
      style={{ width: HOURS * HOUR_PX, height: ROW_PX }}
      onDragOver={(e) => {
        if (!dragJob || !canDrag) return;
        e.preventDefault();
        onHover(hourAt(e.clientX));
      }}
      onDragLeave={() => onHover(null)}
      onDrop={(e) => {
        e.preventDefault();
        onDrop(hourAt(e.clientX));
      }}
    >
      {Array.from({ length: HOURS }).map((_, i) => (
        <div key={i} className="absolute inset-y-0 border-l border-border/70" style={{ left: i * HOUR_PX }} />
      ))}
      {nowOffset !== null && nowOffset > 0 && nowOffset < HOURS * HOUR_PX && (
        <div className="absolute inset-y-0 z-[5] w-0.5 bg-brand-orange" style={{ left: nowOffset }} data-row={rowId} />
      )}
      {hover !== null && dragJob && (
        <div
          className="absolute inset-y-2 z-[4] rounded-lg border-2 border-dashed border-brand-orange bg-brand-orange-tint/70"
          style={{ left: (hover - START_HOUR) * HOUR_PX, width: Math.max(0.5, dragDuration) * HOUR_PX }}
        >
          <span className="absolute -top-0.5 left-1.5 text-[10px] font-bold text-brand-orange-text">
            {String(Math.floor(hover)).padStart(2, "0")}:{hover % 1 ? "30" : "00"}
          </span>
        </div>
      )}
      {jobs.map((j) => {
        const s = slot(j)!;
        const start = new Date(s[0]);
        const startH = start.getHours() + start.getMinutes() / 60;
        const durH = Math.max(0.5, (s[1] - s[0]) / 3600_000);
        const left = Math.max(0, (startH - START_HOUR) * HOUR_PX);
        const width = Math.max(56, Math.min(HOURS * HOUR_PX - left, durH * HOUR_PX) - 4);
        const tone = statusTone(j.status);
        return (
          <div
            key={j.id}
            draggable={canDrag && isOpen(j.status)}
            onDragStart={(e) => {
              e.dataTransfer.effectAllowed = "move";
              onDragStart(j.id);
            }}
            onDragEnd={onDragEnd}
            onClick={() => onOpen(j.id)}
            title={`${j.number} · ${j.title}`}
            className={cn(
              "absolute inset-y-2 z-[6] cursor-pointer overflow-hidden rounded-lg border-l-[3px] px-2 py-1.5 text-left shadow-sm transition-all hover:z-[7] hover:shadow-panel",
              TONE_CLASS[tone],
              tone === "info" && "border-primary",
              tone === "warning" && "border-warning",
              tone === "success" && "border-success",
              tone === "neutral" && "border-meta",
              j.priority === "urgent" && "ring-1 ring-brand-orange",
              dragId === j.id && "opacity-40",
            )}
            style={{ left: left + 2, width }}
          >
            <p className="truncate text-xs font-semibold text-foreground">{j.title}</p>
            <p className="truncate text-[11px] opacity-80">
              {timeRange(j.scheduled_start, j.scheduled_end)} · {j.customer?.name ?? shortAddress(j.address)}
            </p>
            <span className="sr-only">{ws.terms.worker}</span>
          </div>
        );
      })}
    </div>
  );
}
