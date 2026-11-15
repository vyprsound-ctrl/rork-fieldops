import { useMemo, useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { MoreHorizontal, Pause, Pencil, Play, Plus, Repeat, Search, Trash2 } from "lucide-react";
import { toast } from "sonner";

import { Page } from "@/components/hs/AppShell";
import { EmptyState, LoadingRows, PageHeader } from "@/components/hs/primitives";
import { Confirm, Field, StatTile, ToneBadge } from "@/components/hs/crm";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Switch } from "@/components/ui/switch";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from "@/components/ui/dropdown-menu";
import { cn } from "@/lib/utils";
import { siteLine } from "@/lib/crm";
import { KIND_TITLE, type JobKind } from "@/lib/domain";
import { dateOnly } from "@/lib/format";
import { useCustomers, useSites } from "@/lib/queries";
import { useWorkspace } from "@/lib/session";
import {
  FREQUENCIES,
  agreements,
  deleteAgreement,
  draftFrom,
  emptyDraft,
  frequencyTitle,
  isDue,
  isOverdue,
  saveAgreement,
  setAgreementActive,
  validation,
  type Agreement,
  type AgreementDraft,
  type Frequency,
} from "@/lib/recurring";

const KEY = ["recurring"] as const;

type Filter = "active" | "due" | "paused" | "all";
const FILTERS: { id: Filter; label: string; match: (a: Agreement) => boolean }[] = [
  { id: "active", label: "Active", match: (a) => a.is_active },
  { id: "due", label: "Due soon", match: (a) => isDue(a) },
  { id: "paused", label: "Paused", match: (a) => !a.is_active },
  { id: "all", label: "All", match: () => true },
];

export default function Recurring() {
  const ws = useWorkspace();
  const qc = useQueryClient();
  const canManage = ws.can("jobsManage") && ws.can("customersManage");
  const { data = [], isLoading, error } = useQuery({ queryKey: KEY, queryFn: agreements });
  const { data: customers = [] } = useCustomers();
  const { data: sites = [] } = useSites();
  const [filter, setFilter] = useState<Filter>("active");
  const [query, setQuery] = useState("");
  const [editing, setEditing] = useState<AgreementDraft | null>(null);
  const [removing, setRemoving] = useState<Agreement | null>(null);

  const names = useMemo(() => new Map(customers.map((c) => [c.id, c.name])), [customers]);
  const siteMap = useMemo(() => new Map(sites.map((s) => [s.id, s])), [sites]);
  const refresh = () => qc.invalidateQueries({ queryKey: KEY });

  const f = FILTERS.find((x) => x.id === filter)!;
  const list = useMemo(() => {
    const q = query.trim().toLowerCase();
    return data.filter(
      (a) =>
        f.match(a) &&
        (!q || [a.template_title, names.get(a.customer_id), siteLine(siteMap.get(a.address_id))].some((s) => s?.toLowerCase().includes(q))),
    );
  }, [data, f, query, names, siteMap]);

  const active = data.filter((a) => a.is_active);
  const due = data.filter((a) => isDue(a));
  const overdue = data.filter((a) => isOverdue(a));

  const toggle = async (a: Agreement) => {
    try {
      await setAgreementActive(a.id, !a.is_active);
      toast.success(a.is_active ? "Paused. No new jobs will be created." : "Resumed.");
      refresh();
    } catch (e) {
      toast.error((e as Error).message);
    }
  };

  const remove = async () => {
    if (!removing) return;
    try {
      await deleteAgreement(removing.id);
      toast.success("Recurring visit removed. Jobs already created are kept.");
      refresh();
    } catch (e) {
      toast.error((e as Error).message);
    } finally {
      setRemoving(null);
    }
  };

  return (
    <Page>
      <PageHeader
        title="Recurring service"
        subtitle="Maintenance contracts. Jobs are created automatically ahead of each due date."
        actions={
          canManage && (
            <Button onClick={() => setEditing(emptyDraft())} className="press gap-1.5 bg-brand-orange hover:bg-brand-orange/90">
              <Plus className="h-4 w-4" /> New recurring visit
            </Button>
          )
        }
      />

      <div className="mb-6 grid gap-3 sm:grid-cols-3">
        <StatTile label="Active contracts" value={String(active.length)} sub={`${data.length - active.length} paused`} />
        <StatTile label="Due soon" value={String(due.length)} sub="Within their lead time" tone={due.length ? "orange" : undefined} />
        <StatTile label="Overdue" value={String(overdue.length)} sub={overdue.length ? "Past the due date" : "Nothing overdue"} tone={overdue.length ? "danger" : undefined} />
      </div>

      <div className="mb-4 flex flex-wrap gap-1.5">
        {FILTERS.map((x) => (
          <button
            key={x.id}
            onClick={() => setFilter(x.id)}
            className={cn(
              "press inline-flex items-center gap-1.5 rounded-full border px-3.5 py-1.5 text-sm font-medium transition-colors",
              filter === x.id ? "border-brand-orange bg-brand-orange text-white" : "border-border bg-card text-muted-foreground hover:text-foreground",
            )}
          >
            {x.label}
            <span className={cn("text-xs tabular-nums", filter === x.id ? "text-white/80" : "text-meta")}>{data.filter(x.match).length}</span>
          </button>
        ))}
      </div>

      <div className="card-surface overflow-hidden">
        <div className="border-b border-border p-3">
          <div className="relative">
            <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-meta" />
            <Input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Search name, customer or site…" className="h-10 border-0 bg-secondary pl-9 shadow-none" />
          </div>
        </div>
        {isLoading ? (
          <LoadingRows count={6} />
        ) : error ? (
          <p className="p-6 text-sm text-destructive">{(error as Error).message}</p>
        ) : list.length === 0 ? (
          <EmptyState
            icon={Repeat}
            title={data.length ? "Nothing matches" : "No recurring visits yet"}
            body={data.length ? "Try another filter." : "Set up a maintenance contract and the job is created for you before each visit is due."}
          />
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full min-w-[900px] text-sm">
              <thead className="bg-secondary/50">
                <tr className="text-left">
                  <th className="section-label px-4 py-3">Visit</th>
                  <th className="section-label px-4 py-3">Customer and site</th>
                  <th className="section-label w-40 px-4 py-3">How often</th>
                  <th className="section-label w-36 px-4 py-3">Next due</th>
                  <th className="section-label w-28 px-4 py-3">Status</th>
                  <th className="w-14" />
                </tr>
              </thead>
              <tbody className="divide-y divide-border">
                {list.map((a) => {
                  const over = isOverdue(a);
                  const soon = !over && isDue(a);
                  return (
                    <tr
                      key={a.id}
                      onClick={() => canManage && setEditing(draftFrom(a))}
                      className={cn("transition-colors", canManage && "cursor-pointer hover:bg-primary-tint/50", !a.is_active && "opacity-60")}
                    >
                      <td className="px-4 py-3">
                        <p className="font-medium">{a.template_title}</p>
                        <p className="text-xs text-muted-foreground">{KIND_TITLE[a.template_job_kind]}</p>
                      </td>
                      <td className="px-4 py-3">
                        <p className="font-medium">{names.get(a.customer_id) ?? "—"}</p>
                        <p className="text-xs text-muted-foreground">{siteLine(siteMap.get(a.address_id)) || "—"}</p>
                      </td>
                      <td className="px-4 py-3">{frequencyTitle(a.frequency, a.interval_days)}</td>
                      <td className={cn("px-4 py-3 tabular-nums", over && "font-semibold text-destructive")}>{dateOnly(a.next_due_date)}</td>
                      <td className="px-4 py-3">
                        {!a.is_active ? (
                          <ToneBadge tone="neutral">Paused</ToneBadge>
                        ) : over ? (
                          <ToneBadge tone="danger">Overdue</ToneBadge>
                        ) : soon ? (
                          <ToneBadge tone="warning">Due soon</ToneBadge>
                        ) : (
                          <ToneBadge tone="success">Active</ToneBadge>
                        )}
                      </td>
                      <td className="px-2 py-3" onClick={(e) => e.stopPropagation()}>
                        {canManage && (
                          <DropdownMenu>
                            <DropdownMenuTrigger asChild>
                              <Button variant="ghost" size="icon" className="h-8 w-8" aria-label="More">
                                <MoreHorizontal className="h-4 w-4" />
                              </Button>
                            </DropdownMenuTrigger>
                            <DropdownMenuContent align="end">
                              <DropdownMenuItem onClick={() => setEditing(draftFrom(a))}>
                                <Pencil className="mr-2 h-4 w-4" /> Edit
                              </DropdownMenuItem>
                              <DropdownMenuItem onClick={() => void toggle(a)}>
                                {a.is_active ? <Pause className="mr-2 h-4 w-4" /> : <Play className="mr-2 h-4 w-4" />}
                                {a.is_active ? "Pause" : "Resume"}
                              </DropdownMenuItem>
                              <DropdownMenuItem className="text-destructive focus:text-destructive" onClick={() => setRemoving(a)}>
                                <Trash2 className="mr-2 h-4 w-4" /> Remove
                              </DropdownMenuItem>
                            </DropdownMenuContent>
                          </DropdownMenu>
                        )}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {editing && (
        <AgreementDialog
          draft={editing}
          onClose={() => setEditing(null)}
          onSaved={() => {
            setEditing(null);
            refresh();
          }}
        />
      )}
      <Confirm
        open={!!removing}
        onOpenChange={(o) => !o && setRemoving(null)}
        title="Remove this recurring visit?"
        body="No more jobs will be created from it. Jobs it already created stay as they are."
        action="Remove"
        onConfirm={() => void remove()}
      />
    </Page>
  );
}

function AgreementDialog({ draft, onClose, onSaved }: { draft: AgreementDraft; onClose: () => void; onSaved: () => void }) {
  const ws = useWorkspace();
  const { data: customers = [] } = useCustomers();
  const { data: sites = [] } = useSites();
  const [d, setD] = useState<AgreementDraft>(draft);
  const [busy, setBusy] = useState(false);
  const customerSites = sites.filter((s) => s.customer_id === d.customerId);
  const problem = validation(d);

  const save = async () => {
    setBusy(true);
    try {
      await saveAgreement(ws.company.id, d);
      toast.success(d.id ? "Recurring visit updated." : "Recurring visit added.");
      onSaved();
    } catch (e) {
      toast.error((e as Error).message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="max-h-[90vh] overflow-y-auto sm:max-w-xl">
        <DialogHeader>
          <DialogTitle>{d.id ? "Edit recurring visit" : "New recurring visit"}</DialogTitle>
          <DialogDescription>A job is created automatically before each visit is due, then the next date moves on.</DialogDescription>
        </DialogHeader>

        <div className="grid gap-4">
          <div className="grid gap-4 sm:grid-cols-2">
            <Field label="Customer">
              <Select value={d.customerId} onValueChange={(v) => setD({ ...d, customerId: v, addressId: sites.find((s) => s.customer_id === v)?.id ?? "" })}>
                <SelectTrigger>
                  <SelectValue placeholder="Choose a customer" />
                </SelectTrigger>
                <SelectContent>
                  {customers.map((c) => (
                    <SelectItem key={c.id} value={c.id}>
                      {c.name}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </Field>
            <Field label="Site" hint={d.customerId && customerSites.length === 0 ? "This customer has no sites yet. Add one on their page." : undefined}>
              <Select value={d.addressId} onValueChange={(v) => setD({ ...d, addressId: v })} disabled={!d.customerId}>
                <SelectTrigger>
                  <SelectValue placeholder="Choose a site" />
                </SelectTrigger>
                <SelectContent>
                  {customerSites.map((s) => (
                    <SelectItem key={s.id} value={s.id}>
                      {siteLine(s)}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </Field>
          </div>

          <div className="grid gap-4 sm:grid-cols-2">
            <Field label="Name">
              <Input value={d.title} onChange={(e) => setD({ ...d, title: e.target.value })} placeholder="e.g. Spring AC tune-up" />
            </Field>
            <Field label="Job type">
              <Select value={d.kind} onValueChange={(v) => setD({ ...d, kind: v as JobKind })}>
                <SelectTrigger>
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
          </div>

          <div className="grid gap-4 sm:grid-cols-3">
            <Field label="How often" className={d.frequency === "custom" ? "" : "sm:col-span-2"}>
              <Select value={d.frequency} onValueChange={(v) => setD({ ...d, frequency: v as Frequency })}>
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {FREQUENCIES.map((x) => (
                    <SelectItem key={x.id} value={x.id}>
                      {x.title}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </Field>
            {d.frequency === "custom" && (
              <Field label="Every (days)">
                <Input type="number" min={1} value={d.intervalDays} onChange={(e) => setD({ ...d, intervalDays: Number(e.target.value) })} />
              </Field>
            )}
            <Field label="Next visit due">
              <Input type="date" value={d.nextDueDate} onChange={(e) => setD({ ...d, nextDueDate: e.target.value })} />
            </Field>
          </div>

          <Field label="Job description" hint="Copied onto every job this creates.">
            <Textarea rows={3} value={d.description} onChange={(e) => setD({ ...d, description: e.target.value })} placeholder="What the visit covers" />
          </Field>
          <Field label="Internal notes">
            <Textarea rows={2} value={d.notes} onChange={(e) => setD({ ...d, notes: e.target.value })} placeholder="Contract number, renewal date…" />
          </Field>

          <label className="flex items-center justify-between gap-3 rounded-lg border border-border px-4 py-3">
            <span>
              <span className="block text-sm font-medium">Active</span>
              <span className="text-xs text-muted-foreground">Paused contracts don't create jobs.</span>
            </span>
            <Switch checked={d.isActive} onCheckedChange={(v) => setD({ ...d, isActive: v })} />
          </label>
        </div>

        <DialogFooter className="items-center gap-2">
          {problem && <p className="mr-auto text-xs text-meta">{problem}</p>}
          <Button variant="outline" onClick={onClose}>
            Cancel
          </Button>
          <Button onClick={() => void save()} disabled={busy || !!problem} className="press bg-brand-orange hover:bg-brand-orange/90">
            {busy ? "Saving…" : d.id ? "Save changes" : "Add recurring visit"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
