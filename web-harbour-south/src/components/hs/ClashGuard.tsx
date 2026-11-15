import { useCallback, useState } from "react";
import { AlertTriangle } from "lucide-react";
import { toast } from "sonner";

import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from "@/components/ui/alert-dialog";
import { assignJob, clashesFor, rescheduleJob } from "@/lib/api";
import type { Clash, JobView } from "@/lib/domain";
import { useJobs, useRefreshJobs } from "@/lib/queries";
import { useWorkspace } from "@/lib/session";

interface Pending {
  clashes: Clash[];
  who: string;
  run: () => Promise<void>;
}

/**
 * Assigning or rescheduling runs the iPhone app's clash rule first. If the slot
 * overlaps another open job for that person, the office must confirm; the
 * database checks again and only accepts with that confirmation.
 */
export function useScheduleActions() {
  const ws = useWorkspace();
  const { data: jobs = [] } = useJobs();
  const refresh = useRefreshJobs();
  const [pending, setPending] = useState<Pending | null>(null);
  const [busy, setBusy] = useState(false);

  const perform = useCallback(
    async (jobId: string, task: () => Promise<void>, success: string) => {
      setBusy(true);
      try {
        await task();
        toast.success(success);
      } catch (err) {
        toast.error((err as Error).message);
      } finally {
        setBusy(false);
        refresh(jobId);
      }
    },
    [refresh],
  );

  const assign = useCallback(
    (job: JobView, workerId: string | null, workerName?: string) => {
      const success = workerId ? `Assigned to ${workerName ?? `the ${ws.terms.worker}`}` : `${ws.terms.Worker} unassigned`;
      const clashes = workerId ? clashesFor(job, workerId, jobs) : [];
      if (clashes.length) {
        setPending({
          clashes,
          who: workerName ?? `this ${ws.terms.worker}`,
          run: () => perform(job.id, () => assignJob(job.id, workerId, true), success),
        });
        return;
      }
      void perform(job.id, () => assignJob(job.id, workerId, false), success);
    },
    [jobs, perform, ws.terms],
  );

  const reschedule = useCallback(
    (job: JobView, start: string | null, end: string | null) => {
      const clashes = clashesFor(job, job.workerId, jobs, { start, end });
      if (clashes.length) {
        setPending({
          clashes,
          who: job.worker?.name ?? `this ${ws.terms.worker}`,
          run: () => perform(job.id, () => rescheduleJob(job.id, start, end, true), "Job rescheduled"),
        });
        return;
      }
      void perform(job.id, () => rescheduleJob(job.id, start, end, false), "Job rescheduled");
    },
    [jobs, perform, ws.terms],
  );

  /** Drag on the dispatch board: new time and/or new person in one go. */
  const move = useCallback(
    (job: JobView, workerId: string | null, start: string | null, end: string | null, workerName?: string) => {
      const timeChanged = start !== job.scheduled_start || end !== job.scheduled_end;
      const workerChanged = (workerId ?? undefined) !== job.workerId;
      if (!timeChanged && !workerChanged) return;
      const clashes = workerId ? clashesFor(job, workerId, jobs, { start, end }) : [];
      const run = (ack: boolean) =>
        perform(
          job.id,
          async () => {
            // When the person changes too, the new time is only checked against the
            // new person's day (the final state); the assignment carries the real check.
            if (timeChanged) await rescheduleJob(job.id, start, end, workerChanged ? true : ack);
            if (workerChanged) await assignJob(job.id, workerId, ack);
          },
          workerChanged ? (workerId ? `Moved to ${workerName ?? ws.terms.worker}` : `${ws.terms.Worker} unassigned`) : "Job rescheduled",
        );
      if (clashes.length) {
        setPending({ clashes, who: workerName ?? `this ${ws.terms.worker}`, run: () => run(true) });
        return;
      }
      void run(false);
    },
    [jobs, perform, ws.terms],
  );

  const dialog = (
    <AlertDialog open={!!pending} onOpenChange={(open) => !open && setPending(null)}>
      <AlertDialogContent>
        <AlertDialogHeader>
          <div className="mb-1 flex h-11 w-11 items-center justify-center rounded-xl bg-[hsl(38_100%_94%)] text-warning">
            <AlertTriangle className="h-5 w-5" />
          </div>
          <AlertDialogTitle>Schedule clash</AlertDialogTitle>
          <AlertDialogDescription>
            {pending?.who} already has {pending?.clashes.length === 1 ? "a job" : `${pending?.clashes.length} jobs`} at that
            time. Book it anyway?
          </AlertDialogDescription>
        </AlertDialogHeader>
        <ul className="space-y-1.5">
          {pending?.clashes.map((c) => (
            <li key={c.jobId} className="flex items-center justify-between rounded-lg bg-secondary px-3 py-2 text-sm">
              <span className="truncate">
                <span className="font-semibold">{c.number}</span> · {c.title}
              </span>
              <span className="ml-3 shrink-0 tabular-nums text-muted-foreground">{c.range}</span>
            </li>
          ))}
        </ul>
        <AlertDialogFooter>
          <AlertDialogCancel>Keep current schedule</AlertDialogCancel>
          <AlertDialogAction
            className="bg-brand-orange text-white hover:bg-brand-orange/90"
            onClick={() => {
              const run = pending?.run;
              setPending(null);
              void run?.();
            }}
          >
            Book anyway
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );

  return { assign, reschedule, move, busy, dialog };
}
