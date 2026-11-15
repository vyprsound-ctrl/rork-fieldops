import { useEffect, useMemo, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import { AlertTriangle, Flame } from "lucide-react";
import { toast } from "sonner";

import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { cn } from "@/lib/utils";
import { clashesFor, createJob, customerAddresses, customers } from "@/lib/api";
import { KIND_TITLE, addressLine, type JobKind, type JobPriority } from "@/lib/domain";
import { fromLocalInput } from "@/lib/format";
import { useJobs, useRefreshJobs, useWorkers } from "@/lib/queries";
import { useWorkspace } from "@/lib/session";
import { useJobPanel } from "./primitives";

function nextHour(offsetHours: number) {
  const d = new Date();
  d.setMinutes(0, 0, 0);
  d.setHours(d.getHours() + 1 + offsetHours);
  const pad = (n: number) => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:00`;
}

export function NewJobDialog({ open, onOpenChange }: { open: boolean; onOpenChange: (open: boolean) => void }) {
  const ws = useWorkspace();
  const refresh = useRefreshJobs();
  const panel = useJobPanel();
  const { data: workers = [] } = useWorkers();
  const { data: jobs = [] } = useJobs();
  const customerList = useQuery({ queryKey: ["customers"], queryFn: customers, enabled: open });

  const [customerId, setCustomerId] = useState("");
  const [addressId, setAddressId] = useState("");
  const [title, setTitle] = useState("");
  const [description, setDescription] = useState("");
  const [kind, setKind] = useState<JobKind>("callOut");
  const [priority, setPriority] = useState<JobPriority>("standard");
  const [start, setStart] = useState(nextHour(0));
  const [end, setEnd] = useState(nextHour(2));
  const [workerId, setWorkerId] = useState("none");
  const [saving, setSaving] = useState(false);

  const addresses = useQuery({
    queryKey: ["addresses", customerId],
    queryFn: () => customerAddresses(customerId),
    enabled: !!customerId,
  });

  useEffect(() => {
    if (!open) return;
    setCustomerId("");
    setAddressId("");
    setTitle("");
    setDescription("");
    setKind("callOut");
    setPriority("standard");
    setStart(nextHour(0));
    setEnd(nextHour(2));
    setWorkerId("none");
  }, [open]);

  useEffect(() => {
    const list = addresses.data ?? [];
    setAddressId(list.length === 1 ? list[0].id : "");
  }, [addresses.data]);

  const s = fromLocalInput(start);
  const e = fromLocalInput(end);
  const clashes = useMemo(
    () =>
      workerId !== "none"
        ? clashesFor({ id: "new", scheduled_start: s, scheduled_end: e }, workerId, jobs)
        : [],
    [workerId, s, e, jobs],
  );
  const timeError = s && e && new Date(e) < new Date(s) ? "A job can't finish before it starts." : null;
  const canAssign = ws.can("assignmentsManage");
  const ready = customerId && addressId && title.trim() && !timeError && !saving;

  const submit = async () => {
    setSaving(true);
    try {
      const id = await createJob({
        customerId,
        addressId,
        title: title.trim(),
        description: description.trim(),
        kind,
        priority,
        start: s,
        end: e,
        workerId: canAssign && workerId !== "none" ? workerId : null,
      });
      toast.success("Job created");
      refresh();
      onOpenChange(false);
      if (id) panel.open(String(id));
    } catch (err) {
      toast.error((err as Error).message);
    } finally {
      setSaving(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-h-[92vh] overflow-y-auto sm:max-w-[620px] scroll-thin">
        <DialogHeader>
          <DialogTitle className="text-xl">New job</DialogTitle>
          <DialogDescription>It appears on the dispatch board and the {ws.terms.worker}'s iPhone straight away.</DialogDescription>
        </DialogHeader>

        <div className="grid gap-4 py-2">
          <div className="grid grid-cols-2 gap-3">
            <Field label="Customer">
              <Select value={customerId} onValueChange={setCustomerId}>
                <SelectTrigger className="h-11">
                  <SelectValue placeholder={customerList.isLoading ? "Loading…" : "Choose a customer"} />
                </SelectTrigger>
                <SelectContent className="max-h-72">
                  {(customerList.data ?? []).map((c) => (
                    <SelectItem key={c.id} value={c.id}>
                      {c.name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </Field>
            <Field label="Site">
              <Select value={addressId} onValueChange={setAddressId} disabled={!customerId}>
                <SelectTrigger className="h-11">
                  <SelectValue placeholder={customerId ? (addresses.data?.length === 0 ? "No sites on file" : "Choose a site") : "Pick a customer first"} />
                </SelectTrigger>
                <SelectContent>
                  {(addresses.data ?? []).map((a) => (
                    <SelectItem key={a.id} value={a.id}>
                      {addressLine(a)}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </Field>
          </div>

          <Field label="Title">
            <Input value={title} onChange={(e) => setTitle(e.target.value)} placeholder="e.g. No heat — boiler fault" className="h-11" />
          </Field>
          <Field label="What needs doing">
            <Textarea value={description} onChange={(e) => setDescription(e.target.value)} placeholder="Details for the visit" />
          </Field>

          <div className="grid grid-cols-2 gap-3">
            <Field label="Type">
              <Select value={kind} onValueChange={(v) => setKind(v as JobKind)}>
                <SelectTrigger className="h-11">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {(Object.keys(KIND_TITLE) as JobKind[]).map((k) => (
                    <SelectItem key={k} value={k}>
                      {KIND_TITLE[k]}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </Field>
            <Field label="Priority">
              <div className="flex h-11 rounded-md border border-input p-1">
                {(["standard", "urgent"] as JobPriority[]).map((p) => (
                  <button
                    key={p}
                    type="button"
                    onClick={() => setPriority(p)}
                    className={cn(
                      "flex flex-1 items-center justify-center gap-1 rounded text-sm font-medium transition-colors",
                      priority === p
                        ? p === "urgent"
                          ? "bg-brand-orange text-white"
                          : "bg-primary text-white"
                        : "text-muted-foreground hover:bg-secondary",
                    )}
                  >
                    {p === "urgent" && <Flame className="h-3.5 w-3.5" />}
                    {p === "urgent" ? "Urgent" : "Standard"}
                  </button>
                ))}
              </div>
            </Field>
          </div>

          <div className="grid grid-cols-2 gap-3">
            <Field label="Starts">
              <Input type="datetime-local" value={start} onChange={(e) => setStart(e.target.value)} className="h-11" />
            </Field>
            <Field label="Ends">
              <Input type="datetime-local" value={end} onChange={(e) => setEnd(e.target.value)} className="h-11" />
            </Field>
          </div>
          {timeError && <p className="-mt-2 text-sm text-destructive">{timeError}</p>}

          {canAssign && (
            <Field label={ws.terms.Worker}>
              <Select value={workerId} onValueChange={setWorkerId}>
                <SelectTrigger className="h-11">
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  <SelectItem value="none">Leave unassigned</SelectItem>
                  {workers.map((w) => (
                    <SelectItem key={w.id} value={w.id}>
                      {w.name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </Field>
          )}
          {clashes.length > 0 && (
            <div className="flex gap-2 rounded-xl bg-[hsl(38_100%_94%)] px-3 py-2.5 text-sm text-warning">
              <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" />
              <span>
                Overlaps {clashes.map((c) => `${c.number} (${c.range})`).join(", ")}. Creating it will double-book this{" "}
                {ws.terms.worker}.
              </span>
            </div>
          )}
        </div>

        <DialogFooter>
          <Button variant="ghost" onClick={() => onOpenChange(false)}>
            Cancel
          </Button>
          <Button disabled={!ready} onClick={submit} className="bg-brand-orange hover:bg-brand-orange/90">
            {saving ? "Creating…" : "Create job"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <label className="grid gap-1.5 text-sm font-medium">
      <span className="text-xs text-muted-foreground">{label}</span>
      {children}
    </label>
  );
}
