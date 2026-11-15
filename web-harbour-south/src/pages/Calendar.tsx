import { useMemo, useState } from "react";
import {
  addDays,
  addMonths,
  addWeeks,
  eachDayOfInterval,
  endOfMonth,
  endOfWeek,
  format,
  isSameDay,
  isSameMonth,
  startOfDay,
  startOfMonth,
  startOfWeek,
} from "date-fns";
import { ChevronLeft, ChevronRight } from "lucide-react";

import { Page } from "@/components/hs/AppShell";
import { PageHeader, TONE_CLASS, TONE_DOT, WorkerAvatar, useJobPanel } from "@/components/hs/primitives";
import { Button } from "@/components/ui/button";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { cn } from "@/lib/utils";
import { slot, statusTone, type JobView } from "@/lib/domain";
import { time, timeRange } from "@/lib/format";
import { useJobs, useWorkers } from "@/lib/queries";
import { useWorkspace } from "@/lib/session";

type View = "day" | "week" | "month";
const START_HOUR = 6;
const END_HOUR = 21;
const HOUR_PX = 56;

export default function CalendarPage() {
  const ws = useWorkspace();
  const panel = useJobPanel();
  const { data: jobs = [] } = useJobs();
  const { data: workers = [] } = useWorkers();
  const [view, setView] = useState<View>("week");
  const [anchor, setAnchor] = useState(() => startOfDay(new Date()));
  const [worker, setWorker] = useState("any");

  const visible = useMemo(
    () =>
      jobs.filter(
        (j) =>
          j.scheduled_start &&
          j.status !== "cancelled" &&
          (worker === "any" || (worker === "none" ? !j.workerId : j.workerId === worker)),
      ),
    [jobs, worker],
  );

  const step = (dir: 1 | -1) =>
    setAnchor((a) => (view === "day" ? addDays(a, dir) : view === "week" ? addWeeks(a, dir) : addMonths(a, dir)));

  const title =
    view === "day"
      ? format(anchor, "EEEE d MMMM")
      : view === "week"
        ? `${format(startOfWeek(anchor, { weekStartsOn: 1 }), "d MMM")} – ${format(endOfWeek(anchor, { weekStartsOn: 1 }), "d MMM yyyy")}`
        : format(anchor, "MMMM yyyy");

  const days =
    view === "day"
      ? [anchor]
      : eachDayOfInterval({ start: startOfWeek(anchor, { weekStartsOn: 1 }), end: endOfWeek(anchor, { weekStartsOn: 1 }) });

  return (
    <Page className="max-w-none">
      <PageHeader
        title="Calendar"
        actions={
          <>
            <Select value={worker} onValueChange={setWorker}>
              <SelectTrigger className="h-10 w-[180px] bg-card">
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="any">Everyone</SelectItem>
                <SelectItem value="none">Unassigned</SelectItem>
                {workers.map((w) => (
                  <SelectItem key={w.id} value={w.id}>
                    {w.name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            <div className="flex rounded-xl border border-border bg-card p-1">
              {(["day", "week", "month"] as View[]).map((v) => (
                <button
                  key={v}
                  onClick={() => setView(v)}
                  className={cn(
                    "rounded-lg px-3.5 py-1.5 text-sm font-medium capitalize transition-colors",
                    view === v ? "bg-primary text-white" : "text-muted-foreground hover:text-foreground",
                  )}
                >
                  {v}
                </button>
              ))}
            </div>
          </>
        }
      />

      <div className="card-surface overflow-hidden">
        <div className="flex items-center gap-2 border-b border-border px-4 py-3">
          <Button variant="ghost" size="icon" className="h-8 w-8" onClick={() => step(-1)} aria-label="Previous">
            <ChevronLeft className="h-4 w-4" />
          </Button>
          <Button variant="ghost" size="icon" className="h-8 w-8" onClick={() => step(1)} aria-label="Next">
            <ChevronRight className="h-4 w-4" />
          </Button>
          <h2 className="text-lg font-semibold">{title}</h2>
          <Button variant="outline" size="sm" className="ml-auto" onClick={() => setAnchor(startOfDay(new Date()))}>
            Today
          </Button>
        </div>

        {view === "month" ? (
          <MonthGrid anchor={anchor} jobs={visible} onOpen={panel.open} onDay={(d) => (setAnchor(d), setView("day"))} />
        ) : (
          <TimeGrid days={days} jobs={visible} onOpen={panel.open} onDay={(d) => (setAnchor(d), setView("day"))} />
        )}
      </div>
      <p className="mt-3 text-xs text-muted-foreground">
        Click a job to open it. Change times and {ws.terms.workerPlural} from the job panel or the dispatch board.
      </p>
    </Page>
  );
}

/** Side-by-side lanes for overlapping jobs on one day. */
function lanes(jobs: JobView[]) {
  const sorted = [...jobs].sort((a, b) => slot(a)![0] - slot(b)![0]);
  const ends: number[] = [];
  const placed = sorted.map((j) => {
    const [s, e] = slot(j)!;
    let lane = ends.findIndex((end) => end <= s);
    if (lane === -1) lane = ends.length;
    ends[lane] = e;
    return { job: j, lane };
  });
  return { placed, count: Math.max(1, ends.length) };
}

function TimeGrid({ days, jobs, onOpen, onDay }: { days: Date[]; jobs: JobView[]; onOpen: (id: string) => void; onDay: (d: Date) => void }) {
  const now = new Date();
  const hours = END_HOUR - START_HOUR;
  return (
    <div className="max-h-[calc(100vh-250px)] overflow-auto scroll-thin">
      <div className="sticky top-0 z-10 flex border-b border-border bg-card">
        <div className="w-16 shrink-0" />
        {days.map((d) => (
          <button key={d.toISOString()} onClick={() => onDay(d)} className="flex-1 border-l border-border px-2 py-2.5 text-left hover:bg-secondary/60">
            <p className="section-label">{format(d, "EEE")}</p>
            <p
              className={cn(
                "mt-0.5 inline-flex h-8 min-w-8 items-center justify-center rounded-full text-lg font-bold tabular-nums",
                isSameDay(d, now) && "bg-brand-orange px-2 text-white",
              )}
            >
              {format(d, "d")}
            </p>
          </button>
        ))}
      </div>
      <div className="flex">
        <div className="w-16 shrink-0">
          {Array.from({ length: hours }).map((_, i) => (
            <div key={i} className="pr-2 text-right text-[11px] tabular-nums text-meta" style={{ height: HOUR_PX }}>
              <span className="-mt-2 block">{String(START_HOUR + i).padStart(2, "0")}:00</span>
            </div>
          ))}
        </div>
        {days.map((d) => {
          const dayJobs = jobs.filter((j) => isSameDay(new Date(j.scheduled_start!), d));
          const { placed, count } = lanes(dayJobs);
          const nowTop = isSameDay(d, now) ? (now.getHours() + now.getMinutes() / 60 - START_HOUR) * HOUR_PX : null;
          return (
            <div key={d.toISOString()} className="relative flex-1 border-l border-border" style={{ height: hours * HOUR_PX }}>
              {Array.from({ length: hours }).map((_, i) => (
                <div key={i} className="absolute inset-x-0 border-t border-border/60" style={{ top: i * HOUR_PX }} />
              ))}
              {nowTop !== null && nowTop > 0 && (
                <div className="absolute inset-x-0 z-[5] h-0.5 bg-brand-orange" style={{ top: nowTop }}>
                  <span className="absolute -left-1 -top-1 h-2.5 w-2.5 rounded-full bg-brand-orange" />
                </div>
              )}
              {placed.map(({ job, lane }) => {
                const [s, e] = slot(job)!;
                const start = new Date(s);
                const top = Math.max(0, (start.getHours() + start.getMinutes() / 60 - START_HOUR) * HOUR_PX);
                const height = Math.max(26, ((e - s) / 3600_000) * HOUR_PX - 3);
                const tone = statusTone(job.status);
                return (
                  <button
                    key={job.id}
                    onClick={() => onOpen(job.id)}
                    className={cn(
                      "absolute z-[6] overflow-hidden rounded-lg px-2 py-1 text-left text-xs shadow-sm transition-shadow hover:z-[7] hover:shadow-panel",
                      TONE_CLASS[tone],
                      job.priority === "urgent" && "ring-1 ring-brand-orange",
                    )}
                    style={{ top, height, left: `calc(${(lane / count) * 100}% + 2px)`, width: `calc(${100 / count}% - 4px)` }}
                  >
                    <p className="truncate font-semibold text-foreground">{job.title}</p>
                    <p className="truncate opacity-80">{timeRange(job.scheduled_start, job.scheduled_end)}</p>
                    {height > 60 && job.worker && (
                      <p className="mt-1 flex items-center gap-1 truncate text-foreground/80">
                        <WorkerAvatar name={job.worker.name} id={job.worker.id} size={16} />
                        {job.worker.name}
                      </p>
                    )}
                  </button>
                );
              })}
            </div>
          );
        })}
      </div>
    </div>
  );
}

function MonthGrid({ anchor, jobs, onOpen, onDay }: { anchor: Date; jobs: JobView[]; onOpen: (id: string) => void; onDay: (d: Date) => void }) {
  const days = eachDayOfInterval({
    start: startOfWeek(startOfMonth(anchor), { weekStartsOn: 1 }),
    end: endOfWeek(endOfMonth(anchor), { weekStartsOn: 1 }),
  });
  const now = new Date();
  return (
    <div>
      <div className="grid grid-cols-7 border-b border-border bg-secondary/50">
        {["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"].map((d) => (
          <div key={d} className="section-label px-3 py-2">
            {d}
          </div>
        ))}
      </div>
      <div className="grid grid-cols-7">
        {days.map((d) => {
          const dayJobs = jobs
            .filter((j) => isSameDay(new Date(j.scheduled_start!), d))
            .sort((a, b) => a.scheduled_start!.localeCompare(b.scheduled_start!));
          return (
            <div
              key={d.toISOString()}
              className={cn("min-h-[118px] border-b border-l border-border p-1.5", !isSameMonth(d, anchor) && "bg-secondary/40")}
            >
              <button
                onClick={() => onDay(d)}
                className={cn(
                  "mb-1 inline-flex h-6 min-w-6 items-center justify-center rounded-full px-1.5 text-xs font-semibold tabular-nums hover:bg-secondary",
                  isSameDay(d, now) && "bg-brand-orange text-white hover:bg-brand-orange",
                  !isSameMonth(d, anchor) && "text-meta",
                )}
              >
                {format(d, "d")}
              </button>
              <div className="space-y-0.5">
                {dayJobs.slice(0, 3).map((j) => (
                  <button
                    key={j.id}
                    onClick={() => onOpen(j.id)}
                    className="flex w-full items-center gap-1.5 rounded px-1 py-0.5 text-left text-[11px] hover:bg-secondary"
                  >
                    <span className={cn("h-1.5 w-1.5 shrink-0 rounded-full", TONE_DOT[statusTone(j.status)])} />
                    <span className="tabular-nums text-muted-foreground">{time(j.scheduled_start!)}</span>
                    <span className="truncate">{j.title}</span>
                  </button>
                ))}
                {dayJobs.length > 3 && (
                  <button onClick={() => onDay(d)} className="px-1 text-[11px] font-semibold text-primary hover:underline">
                    +{dayJobs.length - 3} more
                  </button>
                )}
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}
