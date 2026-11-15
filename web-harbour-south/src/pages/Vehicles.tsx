import { useMemo, useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Car, Plus, Search } from "lucide-react";
import { toast } from "sonner";

import { Page } from "@/components/hs/AppShell";
import { EmptyState, LoadingRows, PageHeader } from "@/components/hs/primitives";
import { Field } from "@/components/hs/crm";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { cn } from "@/lib/utils";
import { shortDate } from "@/lib/format";
import { useCustomers } from "@/lib/queries";
import { useWorkspace } from "@/lib/session";
import { saveVehicle, vehicleJobCounts, vehicleTitle, vehicles, type Vehicle, type VehicleDraft } from "@/lib/vehicles";

const blank = (): VehicleDraft => ({ id: null, customerId: "", registration: "", vin: "", make: "", model: "" });
const toDraft = (v: Vehicle): VehicleDraft => ({
  id: v.id,
  customerId: v.customer_id,
  registration: v.registration,
  vin: v.vin,
  make: v.make,
  model: v.model,
});

export default function Vehicles() {
  const ws = useWorkspace();
  const qc = useQueryClient();
  const canManage = ws.can("customersManage");
  const { data = [], isLoading, error } = useQuery({ queryKey: ["vehicles"], queryFn: vehicles });
  const { data: counts } = useQuery({ queryKey: ["vehicles", "jobs"], queryFn: vehicleJobCounts, enabled: ws.can("jobsReadAll") });
  const { data: customers = [] } = useCustomers();
  const [query, setQuery] = useState("");
  const [editing, setEditing] = useState<VehicleDraft | null>(null);

  const names = useMemo(() => new Map(customers.map((c) => [c.id, c.name])), [customers]);
  const list = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return data;
    return data.filter((v) => [v.registration, v.vin, v.make, v.model, names.get(v.customer_id)].some((s) => s?.toLowerCase().includes(q)));
  }, [data, query, names]);

  return (
    <Page>
      <PageHeader
        title="Vehicles"
        subtitle={`${data.length} vehicle${data.length === 1 ? "" : "s"} on file`}
        actions={
          canManage && (
            <Button onClick={() => setEditing(blank())} className="press gap-1.5 bg-brand-orange hover:bg-brand-orange/90">
              <Plus className="h-4 w-4" /> Add vehicle
            </Button>
          )
        }
      />

      <div className="card-surface overflow-hidden">
        <div className="border-b border-border p-3">
          <div className="relative">
            <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-meta" />
            <Input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Search plate, VIN, make or customer…" className="h-10 border-0 bg-secondary pl-9 shadow-none" />
          </div>
        </div>
        {isLoading ? (
          <LoadingRows count={6} />
        ) : error ? (
          <p className="p-6 text-sm text-destructive">{(error as Error).message}</p>
        ) : list.length === 0 ? (
          <EmptyState
            icon={Car}
            title={data.length ? "No vehicles match" : "No vehicles yet"}
            body={data.length ? "Try a different search." : "Add a customer's vehicle so jobs can be tracked against it."}
          />
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full min-w-[820px] text-sm">
              <thead className="bg-secondary/50">
                <tr className="text-left">
                  <th className="section-label px-4 py-3">Vehicle</th>
                  <th className="section-label w-32 px-4 py-3">Plate</th>
                  <th className="section-label w-48 px-4 py-3">VIN</th>
                  <th className="section-label px-4 py-3">Customer</th>
                  {counts && <th className="section-label w-20 px-4 py-3 text-right">Jobs</th>}
                  <th className="section-label w-32 px-4 py-3">Added</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-border">
                {list.map((v) => (
                  <tr
                    key={v.id}
                    onClick={() => canManage && setEditing(toDraft(v))}
                    className={cn("transition-colors", canManage && "cursor-pointer hover:bg-primary-tint/50")}
                  >
                    <td className="px-4 py-3 font-medium">{vehicleTitle(v)}</td>
                    <td className="px-4 py-3 font-semibold tabular-nums">{v.registration || <span className="font-normal text-meta">—</span>}</td>
                    <td className="px-4 py-3 font-mono text-xs">{v.vin || <span className="font-sans text-meta">—</span>}</td>
                    <td className="px-4 py-3">{names.get(v.customer_id) ?? "—"}</td>
                    {counts && <td className="px-4 py-3 text-right tabular-nums">{counts.get(v.id) ?? 0}</td>}
                    <td className="px-4 py-3 tabular-nums text-muted-foreground">{shortDate(v.created_at)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {editing && (
        <VehicleDialog
          draft={editing}
          onClose={() => setEditing(null)}
          onSaved={() => {
            setEditing(null);
            qc.invalidateQueries({ queryKey: ["vehicles"] });
          }}
        />
      )}
    </Page>
  );
}

function VehicleDialog({ draft, onClose, onSaved }: { draft: VehicleDraft; onClose: () => void; onSaved: () => void }) {
  const ws = useWorkspace();
  const { data: customers = [] } = useCustomers();
  const [d, setD] = useState<VehicleDraft>(draft);
  const [busy, setBusy] = useState(false);

  const save = async () => {
    setBusy(true);
    try {
      await saveVehicle(ws.company.id, ws.userId, d);
      toast.success(d.id ? "Vehicle updated." : "Vehicle added.");
      onSaved();
    } catch (e) {
      toast.error((e as Error).message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>{d.id ? "Edit vehicle" : "Add vehicle"}</DialogTitle>
          <DialogDescription>A plate or a VIN is needed so the vehicle can be found again.</DialogDescription>
        </DialogHeader>
        <div className="grid gap-4">
          <Field label="Customer">
            <Select value={d.customerId} onValueChange={(v) => setD({ ...d, customerId: v })}>
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
          <div className="grid gap-4 sm:grid-cols-2">
            <Field label="Make">
              <Input value={d.make} onChange={(e) => setD({ ...d, make: e.target.value })} placeholder="Ford" />
            </Field>
            <Field label="Model">
              <Input value={d.model} onChange={(e) => setD({ ...d, model: e.target.value })} placeholder="F-150" />
            </Field>
          </div>
          <div className="grid gap-4 sm:grid-cols-2">
            <Field label="Plate">
              <Input value={d.registration} onChange={(e) => setD({ ...d, registration: e.target.value.toUpperCase() })} placeholder="7ABC123" />
            </Field>
            <Field label="VIN">
              <Input value={d.vin} onChange={(e) => setD({ ...d, vin: e.target.value.toUpperCase() })} placeholder="1FTFW1E50PFA00000" className="font-mono" />
            </Field>
          </div>
        </div>
        <DialogFooter>
          <Button variant="outline" onClick={onClose}>
            Cancel
          </Button>
          <Button onClick={() => void save()} disabled={busy} className="press bg-brand-orange hover:bg-brand-orange/90">
            {busy ? "Saving…" : d.id ? "Save changes" : "Add vehicle"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
