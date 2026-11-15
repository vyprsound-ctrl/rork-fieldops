import { useEffect, useState, type ReactNode } from "react";
import { Check, Pencil, Plus, Trash2, X } from "lucide-react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
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
import type { Tone } from "@/lib/domain";
import type { LineDraft, LineItem } from "@/lib/crm";
import { money2 } from "@/lib/format";
import { TONE_CLASS, TONE_DOT } from "./primitives";

export function ToneBadge({ tone, children, className }: { tone: Tone; children: ReactNode; className?: string }) {
  return (
    <span
      className={cn(
        "inline-flex items-center gap-1.5 whitespace-nowrap rounded-full px-2.5 py-0.5 text-xs font-semibold",
        TONE_CLASS[tone],
        className,
      )}
    >
      <span className={cn("h-1.5 w-1.5 rounded-full", TONE_DOT[tone])} />
      {children}
    </span>
  );
}

export function Field({ label, children, hint, className }: { label: string; children: ReactNode; hint?: string; className?: string }) {
  return (
    <label className={cn("grid gap-1.5 text-sm font-medium", className)}>
      <span className="text-xs text-muted-foreground">{label}</span>
      {children}
      {hint && <span className="text-xs font-normal text-meta">{hint}</span>}
    </label>
  );
}

export function Section({
  title,
  action,
  children,
  className,
}: {
  title: string;
  action?: ReactNode;
  children: ReactNode;
  className?: string;
}) {
  return (
    <section className={cn("card-surface overflow-hidden", className)}>
      <div className="flex items-center justify-between gap-3 border-b border-border px-5 py-3">
        <h2 className="section-label">{title}</h2>
        {action}
      </div>
      {children}
    </section>
  );
}

export function StatTile({ label, value, tone, sub }: { label: string; value: string; tone?: "danger" | "success" | "orange"; sub?: string }) {
  return (
    <div className="card-surface px-5 py-4">
      <p className="section-label">{label}</p>
      <p
        className={cn(
          "mt-1 text-2xl font-bold tabular-nums tracking-tight",
          tone === "danger" && "text-destructive",
          tone === "success" && "text-success",
          tone === "orange" && "text-brand-orange-text",
        )}
      >
        {value}
      </p>
      {sub && <p className="mt-0.5 text-xs text-muted-foreground">{sub}</p>}
    </div>
  );
}

/** A small "are you sure" around destructive actions. */
export function Confirm({
  open,
  onOpenChange,
  title,
  body,
  action,
  onConfirm,
}: {
  open: boolean;
  onOpenChange: (o: boolean) => void;
  title: string;
  body: string;
  action: string;
  onConfirm: () => void;
}) {
  return (
    <AlertDialog open={open} onOpenChange={onOpenChange}>
      <AlertDialogContent>
        <AlertDialogHeader>
          <AlertDialogTitle>{title}</AlertDialogTitle>
          <AlertDialogDescription>{body}</AlertDialogDescription>
        </AlertDialogHeader>
        <AlertDialogFooter>
          <AlertDialogCancel>Keep it</AlertDialogCancel>
          <AlertDialogAction onClick={onConfirm} className="bg-destructive hover:bg-destructive/90">
            {action}
          </AlertDialogAction>
        </AlertDialogFooter>
      </AlertDialogContent>
    </AlertDialog>
  );
}

const toDraft = (l?: LineItem): LineDraft => ({
  description: l?.item_description ?? "",
  quantity: l ? String(l.quantity) : "1",
  unitPrice: l ? l.unit_price.toFixed(2) : "",
  taxPercent: l ? String(Math.round(l.tax_rate * 100000) / 1000) : "0",
});

/**
 * Line items with inline editing. The database recalculates totals after every
 * save, exactly as it does for the iPhone app.
 */
export function LineItemsEditor({
  lines,
  currency,
  editable,
  lockedReason,
  totals,
  extraTotals,
  onSave,
  onDelete,
}: {
  lines: LineItem[];
  currency: string;
  editable: boolean;
  lockedReason?: string;
  totals: { subtotal: number; tax: number; total: number };
  extraTotals?: ReactNode;
  onSave: (lineId: string | null, draft: LineDraft) => Promise<unknown>;
  onDelete: (lineId: string) => Promise<unknown>;
}) {
  const [editing, setEditing] = useState<string | null>(null);
  const [draft, setDraft] = useState<LineDraft>(toDraft());
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    if (lines.length === 0 && editable && editing === null) {
      setEditing("new");
      setDraft(toDraft());
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [lines.length, editable]);

  const start = (line?: LineItem) => {
    setEditing(line?.id ?? "new");
    setDraft(toDraft(line));
  };

  const save = async () => {
    setBusy(true);
    try {
      await onSave(editing === "new" ? null : editing, draft);
      setEditing(null);
    } catch (err) {
      toast.error((err as Error).message);
    } finally {
      setBusy(false);
    }
  };

  const remove = async (id: string) => {
    setBusy(true);
    try {
      await onDelete(id);
    } catch (err) {
      toast.error((err as Error).message);
    } finally {
      setBusy(false);
    }
  };

  const preview = (Number(draft.quantity) || 0) * (Number(draft.unitPrice) || 0);

  const editRow = (key: string) => (
    <tr key={key} className="bg-primary-tint/40">
      <td className="px-4 py-2.5">
        <Input
          autoFocus
          value={draft.description}
          onChange={(e) => setDraft({ ...draft, description: e.target.value })}
          onKeyDown={(e) => e.key === "Enter" && void save()}
          placeholder="e.g. Replace condenser fan motor"
          className="h-9 bg-card"
        />
      </td>
      <td className="px-2 py-2.5">
        <Input
          inputMode="decimal"
          value={draft.quantity}
          onChange={(e) => setDraft({ ...draft, quantity: e.target.value })}
          className="h-9 bg-card text-right tabular-nums"
        />
      </td>
      <td className="px-2 py-2.5">
        <Input
          inputMode="decimal"
          value={draft.unitPrice}
          onChange={(e) => setDraft({ ...draft, unitPrice: e.target.value })}
          placeholder="0.00"
          className="h-9 bg-card text-right tabular-nums"
        />
      </td>
      <td className="px-2 py-2.5">
        <Input
          inputMode="decimal"
          value={draft.taxPercent}
          onChange={(e) => setDraft({ ...draft, taxPercent: e.target.value })}
          className="h-9 bg-card text-right tabular-nums"
        />
      </td>
      <td className="px-4 py-2.5 text-right font-semibold tabular-nums">{money2(preview, currency)}</td>
      <td className="px-3 py-2.5">
        <div className="flex justify-end gap-1">
          <Button size="icon" className="h-8 w-8 bg-success hover:bg-success/90" disabled={busy} onClick={() => void save()} aria-label="Save line">
            <Check className="h-4 w-4" />
          </Button>
          <Button size="icon" variant="ghost" className="h-8 w-8" disabled={busy} onClick={() => setEditing(null)} aria-label="Cancel">
            <X className="h-4 w-4" />
          </Button>
        </div>
      </td>
    </tr>
  );

  return (
    <div>
      <div className="overflow-x-auto">
        <table className="w-full min-w-[720px] text-sm">
          <thead className="bg-secondary/50">
            <tr className="text-left">
              <th className="section-label px-4 py-2.5">Description</th>
              <th className="section-label w-24 px-2 py-2.5 text-right">Qty</th>
              <th className="section-label w-32 px-2 py-2.5 text-right">Unit price</th>
              <th className="section-label w-24 px-2 py-2.5 text-right">Tax %</th>
              <th className="section-label w-32 px-4 py-2.5 text-right">Amount</th>
              <th className="w-24" />
            </tr>
          </thead>
          <tbody className="divide-y divide-border">
            {lines.map((l) =>
              editing === l.id ? (
                editRow(l.id)
              ) : (
                <tr key={l.id} className="group">
                  <td className="px-4 py-3 font-medium">{l.item_description}</td>
                  <td className="px-2 py-3 text-right tabular-nums">{l.quantity}</td>
                  <td className="px-2 py-3 text-right tabular-nums">{money2(l.unit_price, currency)}</td>
                  <td className="px-2 py-3 text-right tabular-nums text-muted-foreground">
                    {l.tax_rate ? `${Math.round(l.tax_rate * 100000) / 1000}%` : "—"}
                  </td>
                  <td className="px-4 py-3 text-right font-semibold tabular-nums">{money2(l.line_total, currency)}</td>
                  <td className="px-3 py-3">
                    {editable && (
                      <div className="flex justify-end gap-1 opacity-0 transition-opacity group-hover:opacity-100">
                        <Button size="icon" variant="ghost" className="h-8 w-8" onClick={() => start(l)} aria-label="Edit line">
                          <Pencil className="h-3.5 w-3.5" />
                        </Button>
                        <Button
                          size="icon"
                          variant="ghost"
                          className="h-8 w-8 text-destructive hover:text-destructive"
                          disabled={busy}
                          onClick={() => void remove(l.id)}
                          aria-label="Delete line"
                        >
                          <Trash2 className="h-3.5 w-3.5" />
                        </Button>
                      </div>
                    )}
                  </td>
                </tr>
              ),
            )}
            {editing === "new" && editRow("new")}
            {lines.length === 0 && editing !== "new" && (
              <tr>
                <td colSpan={6} className="px-4 py-8 text-center text-sm text-muted-foreground">
                  No line items yet.
                </td>
              </tr>
            )}
          </tbody>
        </table>
      </div>

      <div className="flex flex-wrap items-start justify-between gap-6 border-t border-border px-5 py-4">
        <div>
          {editable ? (
            <Button variant="outline" size="sm" className="gap-1.5" onClick={() => start()} disabled={editing === "new"}>
              <Plus className="h-4 w-4" /> Add line
            </Button>
          ) : (
            lockedReason && <p className="max-w-sm text-xs text-meta">{lockedReason}</p>
          )}
        </div>
        <dl className="grid min-w-[240px] grid-cols-[1fr_auto] gap-x-8 gap-y-1.5 text-sm">
          <dt className="text-muted-foreground">Subtotal</dt>
          <dd className="text-right tabular-nums">{money2(totals.subtotal, currency)}</dd>
          <dt className="text-muted-foreground">Tax</dt>
          <dd className="text-right tabular-nums">{money2(totals.tax, currency)}</dd>
          <dt className="border-t border-border pt-2 font-semibold">Total</dt>
          <dd className="border-t border-border pt-2 text-right text-lg font-bold tabular-nums">{money2(totals.total, currency)}</dd>
          {extraTotals}
        </dl>
      </div>
    </div>
  );
}
