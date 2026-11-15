import { useEffect, useState } from "react";
import {
  CalendarClock,
  Camera,
  Check,
  Clock,
  History,
  Lock,
  MapPin,
  MessageSquareText,
  Phone,
  User,
  Wrench,
  X,
} from "lucide-react";
import { toast } from "sonner";

import { Sheet, SheetContent, SheetTitle } from "@/components/ui/sheet";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
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
import { cn } from "@/lib/utils";
import { addJobNote, updateJobStatus, type JobDetail } from "@/lib/api";
import {
  KIND_TITLE,
  PHOTO_KIND_TITLE,
  PIPELINE,
  addressLine,
  isOpen,
  officeTransitions,
  statusTitle,
  type JobStatus,
  type NoteVisibility,
} from "@/lib/domain";
import { dayAndTime, fromLocalInput, relativeAgo, shortDate, time, timeRange, toLocalInput } from "@/lib/format";
import { useJobDetail, useRefreshJobs, useWorkers } from "@/lib/queries";
import { useWorkspace } from "@/lib/session";
import { useScheduleActions } from "./ClashGuard";
import { LoadingRows, StatusBadge, UrgentTag, WorkerAvatar, useJobPanel } from "./primitives";

export function JobPanel() {
  const { jobId, close } = useJobPanel();
  const { data, isLoading, error } = useJobDetail(jobId);

  return (
    <Sheet open={!!jobId} onOpenChange={(open) => !open && close()}>
      <SheetContent side="right" className="w-full overflow-y-auto border-l p-0 sm:max-w-[560px] scroll-thin [&>button]:hidden">
        <SheetTitle className="sr-only">Job</SheetTitle>
        {isLoading && <LoadingRows count={8} />}
        {error && <p className="p-8 text-sm text-destructive">{(error as Error).message}</p>}
        {data && <JobBody detail={data} onClose={close} />}
      </SheetContent>
    </Sheet>
  );
}

function Section({ icon: Icon, title, children, right }: { icon: typeof Clock; title: string; children: React.ReactNode; right?: React.ReactNode }) {
  return (
    <section className="border-t border-border px-6 py-5">
      <div className="mb-3 flex items-center justify-between">
        <div className="flex items-center gap-2">
          <Icon className="h-4 w-4 text-primary" />
          <h3 className="section-label">{title}</h3>
        </div>
        {right}
      </div>
      {children}
    </section>
  );
}

function Pipeline({ status }: { status: JobStatus }) {
  const ws = useWorkspace();
  if (status === "cancelled") {
    return (
      <div className="rounded-xl bg-secondary px-4 py-3 text-sm font-medium text-muted-foreground">This job was cancelled.</div>
    );
  }
  const current = PIPELINE.indexOf(status);
  return (
    <div className="flex items-start">
      {PIPELINE.map((step, i) => {
        const done = i < current;
        const now = i === current;
        return (
          <div key={step} className="flex flex-1 flex-col items-center">
            <div className="flex w-full items-center">
              <div className={cn("h-[2px] flex-1", i === 0 ? "bg-transparent" : i <= current ? "bg-primary" : "bg-border")} />
              <div
                className={cn(
                  "flex h-6 w-6 shrink-0 items-center justify-center rounded-full border-2 text-[10px] font-bold transition-colors",
                  done && "border-primary bg-primary text-white",
                  now && "border-brand-orange bg-brand-orange text-white shadow-[0_0_0_4px_hsl(var(--brand-orange-tint))]",
                  !done && !now && "border-border bg-card text-meta",
                )}
              >
                {done ? <Check className="h-3 w-3" strokeWidth={3} /> : i + 1}
              </div>
              <div
                className={cn("h-[2px] flex-1", i === PIPELINE.length - 1 ? "bg-transparent" : i < current ? "bg-primary" : "bg-border")}
              />
            </div>
            <span
              className={cn(
                "mt-1.5 px-0.5 text-center text-[10px] leading-tight",
                now ? "font-semibold text-brand-orange-text" : "text-meta",
              )}
            >
              {statusTitle(step, ws.terms).replace(" assigned", "")}
            </span>
          </div>
        );
      })}
    </div>
  );
}

function JobBody({ detail, onClose }: { detail: JobDetail; onClose: () => void }) {
  const ws = useWorkspace();
  const { job } = detail;
  const refresh = useRefreshJobs();
  const { data: workers = [] } = useWorkers();
  const schedule = useScheduleActions();
  const [confirm, setConfirm] = useState<{ to: JobStatus; action: string } | null>(null);
  const [moving, setMoving] = useState(false);

  const transitions = officeTransitions(job.status, ws.perms, ws.terms);
  const canAssign = ws.can("assignmentsManage") && isOpen(job.status);
  const canReschedule = ws.can("jobsManage") && isOpen(job.status);

  const move = async (to: JobStatus, label: string) => {
    setMoving(true);
    try {
      await updateJobStatus(job.id, to);
      toast.success(`${label} — done`);
    } catch (err) {
      toast.error((err as Error).message);
    } finally {
      setMoving(false);
      refresh(job.id);
    }
  };

  return (
    <div className="pb-10">
      {/* Header */}
      <div className="relative overflow-hidden bg-brand-navy px-6 pb-6 pt-5 text-white">
        <div className="pointer-events-none absolute -right-16 -top-20 h-56 w-56 rounded-full border-[18px] border-brand-orange/25" />
        <div className="relative flex items-center justify-between">
          <div className="flex items-center gap-2 text-sm font-semibold text-white/70">
            <span className="tabular-nums">{job.number}</span>
            <span>·</span>
            <span>{KIND_TITLE[job.kind]}</span>
          </div>
          <button onClick={onClose} className="press rounded-full bg-white/10 p-1.5 hover:bg-white/20" aria-label="Close">
            <X className="h-4 w-4" />
          </button>
        </div>
        <h2 className="relative mt-2 text-2xl font-bold leading-tight">{job.title}</h2>
        <p className="relative mt-1 text-sm text-white/75">{job.customer?.name ?? "Customer"}</p>
        <div className="relative mt-4 flex flex-wrap items-center gap-2">
          <StatusBadge status={job.status} terms={ws.terms} className="bg-white text-primary" />
          {job.priority === "urgent" && <UrgentTag />}
          <span className="inline-flex items-center gap-1.5 rounded-full bg-white/10 px-2.5 py-0.5 text-xs font-medium">
            <Clock className="h-3 w-3" />
            {dayAndTime(job.scheduled_start)}
          </span>
        </div>
      </div>

      <div className="px-6 py-5">
        <Pipeline status={job.status} />
        {transitions.length > 0 && (
          <div className="mt-5 flex flex-wrap gap-2">
            {transitions.map((t) => (
              <Button
                key={t.to}
                size="sm"
                variant={t.destructive ? "outline" : "default"}
                disabled={moving}
                className={cn(
                  "press",
                  t.destructive ? "border-destructive/30 text-destructive hover:bg-destructive/5" : "bg-brand-orange hover:bg-brand-orange/90",
                )}
                onClick={() => (t.destructive ? setConfirm({ to: t.to, action: t.action }) : move(t.to, t.action))}
              >
                {t.action}
              </Button>
            ))}
          </div>
        )}
        {job.status !== "cancelled" && isOpen(job.status) && !transitions.length && (
          <p className="mt-4 text-xs text-muted-foreground">
            Travel, arrival, starting and completing are recorded by the {ws.terms.worker} on the iPhone app.
          </p>
        )}
      </div>

      {/* Assignment and schedule */}
      <Section icon={CalendarClock} title="Schedule">
        <div className="space-y-4">
          <div>
            <p className="mb-1.5 text-xs font-medium text-muted-foreground">{ws.terms.Worker}</p>
            {canAssign ? (
              <Select
                value={job.workerId ?? "none"}
                disabled={schedule.busy}
                onValueChange={(v) => {
                  const w = workers.find((x) => x.id === v);
                  schedule.assign(job, v === "none" ? null : v, w?.name);
                }}
              >
                <SelectTrigger className="h-11 bg-card">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="none">Unassigned</SelectItem>
                  {workers.map((w) => (
                    <SelectItem key={w.id} value={w.id}>
                      {w.name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            ) : (
              <div className="flex items-center gap-2 text-sm">
                {job.worker ? (
                  <>
                    <WorkerAvatar name={job.worker.name} id={job.worker.id} />
                    {job.worker.name}
                  </>
                ) : (
                  <span className="text-muted-foreground">Unassigned</span>
                )}
              </div>
            )}
          </div>
          <RescheduleForm
            key={`${job.scheduled_start}-${job.scheduled_end}`}
            start={job.scheduled_start}
            end={job.scheduled_end}
            editable={canReschedule}
            busy={schedule.busy}
            onSave={(s, e) => schedule.reschedule(job, s, e)}
          />
          {(job.actual_start || job.actual_end) && (
            <p className="text-xs text-muted-foreground">
              On site {job.actual_start ? time(job.actual_start) : "—"} to {job.actual_end ? time(job.actual_end) : "—"}
            </p>
          )}
        </div>
      </Section>

      <Section icon={MapPin} title="Customer and site">
        <p className="font-semibold">{job.customer?.name}</p>
        <p className="mt-0.5 text-sm text-muted-foreground">{addressLine(job.address)}</p>
        {job.address?.access_notes && (
          <p className="mt-3 rounded-xl bg-brand-orange-tint px-3 py-2 text-sm text-brand-orange-text">
            <span className="font-semibold">Access: </span>
            {job.address.access_notes}
          </p>
        )}
        {detail.contact && (
          <div className="mt-3 flex items-center gap-3 rounded-xl bg-secondary px-3 py-2.5 text-sm">
            <User className="h-4 w-4 text-primary" />
            <div className="flex-1">
              <span className="font-medium">{detail.contact.name}</span>
              {detail.contact.contact_role && <span className="text-muted-foreground"> · {detail.contact.contact_role}</span>}
            </div>
            {detail.contact.phone && (
              <a href={`tel:${detail.contact.phone}`} className="inline-flex items-center gap-1 font-medium text-primary hover:underline">
                <Phone className="h-3.5 w-3.5" />
                {detail.contact.phone}
              </a>
            )}
          </div>
        )}
        {job.job_description && <p className="mt-4 whitespace-pre-wrap text-sm leading-relaxed">{job.job_description}</p>}
      </Section>

      {detail.equipment && (
        <Section icon={Wrench} title="Equipment">
          <p className="text-sm font-medium">
            {detail.equipment.make} {detail.equipment.model}
          </p>
          <p className="text-xs text-muted-foreground">Serial {detail.equipment.serial_number}</p>
        </Section>
      )}

      {ws.can("jobNotesRead") && <NotesSection detail={detail} />}

      {ws.can("jobPhotosRead") && (
        <Section icon={Camera} title={`Photos and signatures (${detail.photos.length})`}>
          {detail.photos.length === 0 ? (
            <p className="text-sm text-muted-foreground">Nothing captured on site yet.</p>
          ) : (
            <div className="grid grid-cols-3 gap-2">
              {detail.photos.map((p) => (
                <a
                  key={p.id}
                  href={p.url ?? undefined}
                  target="_blank"
                  rel="noreferrer"
                  className={cn(
                    "group relative aspect-square overflow-hidden rounded-xl bg-secondary",
                    p.kind === "signature" && "bg-white ring-1 ring-border",
                  )}
                >
                  {p.url ? (
                    <img
                      src={p.url}
                      alt={p.caption ?? PHOTO_KIND_TITLE[p.kind] ?? "Photo"}
                      className={cn("h-full w-full transition-transform group-hover:scale-105", p.kind === "signature" ? "object-contain p-2" : "object-cover")}
                    />
                  ) : (
                    <div className="flex h-full items-center justify-center text-xs text-meta">
                      {p.simulated ? "Sample photo" : "Unavailable"}
                    </div>
                  )}
                  <span className="absolute bottom-1.5 left-1.5 rounded-full bg-black/55 px-2 py-0.5 text-[10px] font-semibold text-white">
                    {PHOTO_KIND_TITLE[p.kind] ?? p.kind}
                  </span>
                </a>
              ))}
            </div>
          )}
        </Section>
      )}

      <Section icon={History} title="History">
        {detail.history.length === 0 ? (
          <p className="text-sm text-muted-foreground">Created {shortDate(job.created_at)}.</p>
        ) : (
          <ol className="relative space-y-3 border-l border-border pl-4">
            {detail.history.map((h) => (
              <li key={h.id} className="relative text-sm">
                <span className="absolute -left-[21px] top-1.5 h-2.5 w-2.5 rounded-full border-2 border-card bg-primary" />
                <span className="font-medium">{statusTitle(h.to_status, ws.terms)}</span>
                <span className="text-muted-foreground">
                  {h.by ? ` · ${h.by}` : ""} · {shortDate(h.changed_at)} {time(h.changed_at)}
                </span>
              </li>
            ))}
          </ol>
        )}
      </Section>

      <AlertDialog open={!!confirm} onOpenChange={(o) => !o && setConfirm(null)}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Cancel {job.number}?</AlertDialogTitle>
            <AlertDialogDescription>
              The job is removed from schedules and the assigned {ws.terms.worker} is told. This can't be undone.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Keep job</AlertDialogCancel>
            <AlertDialogAction
              className="bg-destructive hover:bg-destructive/90"
              onClick={() => confirm && move(confirm.to, confirm.action)}
            >
              Cancel job
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
      {schedule.dialog}
    </div>
  );
}

function RescheduleForm({
  start,
  end,
  editable,
  busy,
  onSave,
}: {
  start: string | null;
  end: string | null;
  editable: boolean;
  busy: boolean;
  onSave: (start: string | null, end: string | null) => void;
}) {
  const [s, setS] = useState(toLocalInput(start));
  const [e, setE] = useState(toLocalInput(end));
  const dirty = s !== toLocalInput(start) || e !== toLocalInput(end);

  if (!editable) {
    return (
      <div>
        <p className="mb-1.5 text-xs font-medium text-muted-foreground">When</p>
        <p className="text-sm">
          {start ? `${dayAndTime(start).split(" · ")[0]} · ${timeRange(start, end)}` : "Unscheduled"}
        </p>
      </div>
    );
  }
  return (
    <div className="grid grid-cols-2 gap-3">
      <label className="text-xs font-medium text-muted-foreground">
        Starts
        <Input type="datetime-local" value={s} onChange={(ev) => setS(ev.target.value)} className="mt-1.5 h-11 bg-card" />
      </label>
      <label className="text-xs font-medium text-muted-foreground">
        Ends
        <Input type="datetime-local" value={e} onChange={(ev) => setE(ev.target.value)} className="mt-1.5 h-11 bg-card" />
      </label>
      {dirty && (
        <div className="col-span-2 flex justify-end gap-2">
          <Button variant="ghost" size="sm" onClick={() => (setS(toLocalInput(start)), setE(toLocalInput(end)))}>
            Undo
          </Button>
          <Button size="sm" disabled={busy} onClick={() => onSave(fromLocalInput(s), fromLocalInput(e))}>
            Save new time
          </Button>
        </div>
      )}
    </div>
  );
}

function NotesSection({ detail }: { detail: JobDetail }) {
  const ws = useWorkspace();
  const refresh = useRefreshJobs();
  const [body, setBody] = useState("");
  const [visibility, setVisibility] = useState<NoteVisibility>("internalOnly");
  const [saving, setSaving] = useState(false);
  const canWrite = ws.can("jobNotesCreate");

  useEffect(() => setBody(""), [detail.job.id]);

  const save = async () => {
    setSaving(true);
    try {
      await addJobNote(ws.company.id, ws.userId, detail.job.id, body, visibility);
      setBody("");
      toast.success("Note added");
      refresh(detail.job.id);
    } catch (err) {
      toast.error((err as Error).message);
    } finally {
      setSaving(false);
    }
  };

  return (
    <Section icon={MessageSquareText} title={`Notes (${detail.notes.length})`}>
      {canWrite && (
        <div className="mb-4 rounded-xl border border-border bg-card p-3 focus-within:ring-2 focus-within:ring-ring/30">
          <Textarea
            value={body}
            onChange={(e) => setBody(e.target.value)}
            placeholder="Add a note for the team…"
            className="min-h-[72px] resize-none border-0 p-0 shadow-none focus-visible:ring-0"
            onKeyDown={(e) => {
              if (e.key === "Enter" && (e.metaKey || e.ctrlKey) && body.trim()) void save();
            }}
          />
          <div className="mt-2 flex items-center justify-between">
            <div className="flex rounded-lg bg-secondary p-0.5 text-xs font-medium">
              {(["internalOnly", "customerVisible"] as NoteVisibility[]).map((v) => (
                <button
                  key={v}
                  onClick={() => setVisibility(v)}
                  className={cn(
                    "rounded-md px-2.5 py-1 transition-colors",
                    visibility === v ? "bg-card text-foreground shadow-sm" : "text-muted-foreground",
                  )}
                >
                  {v === "internalOnly" ? "Team only" : "Customer can see"}
                </button>
              ))}
            </div>
            <Button size="sm" disabled={!body.trim() || saving} onClick={save}>
              Add note
            </Button>
          </div>
        </div>
      )}
      {detail.notes.length === 0 ? (
        <p className="text-sm text-muted-foreground">No notes yet.</p>
      ) : (
        <ul className="space-y-3">
          {detail.notes.map((n) => (
            <li key={n.id} className="rounded-xl bg-secondary/70 px-3.5 py-3">
              <div className="mb-1 flex items-center gap-2 text-xs text-muted-foreground">
                <span className="font-semibold text-foreground">{n.author ?? "Team"}</span>
                <span>{relativeAgo(n.created_at)}</span>
                {n.visibility === "internalOnly" ? (
                  <span className="ml-auto inline-flex items-center gap-1">
                    <Lock className="h-3 w-3" /> Team only
                  </span>
                ) : (
                  <span className="ml-auto text-success">Customer can see</span>
                )}
              </div>
              <p className="whitespace-pre-wrap text-sm">{n.body}</p>
            </li>
          ))}
        </ul>
      )}
    </Section>
  );
}
