import { useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";
import { Plus, Search, Users } from "lucide-react";

import { Page } from "@/components/hs/AppShell";
import { EmptyState, LoadingRows, PageHeader } from "@/components/hs/primitives";
import { CustomerDialog } from "@/components/hs/crmDialogs";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { cn } from "@/lib/utils";
import { CUSTOMER_TYPE_TITLE, effectiveStatus, isReceivable, siteLine, type CustomerType, type Site } from "@/lib/crm";
import { isOpen } from "@/lib/domain";
import { money2 } from "@/lib/format";
import { useCustomers, useInvoices, useJobs, useSites } from "@/lib/queries";
import { useWorkspace } from "@/lib/session";

const TYPES: ("all" | CustomerType)[] = ["all", "residential", "commercial", "propertyManagement", "other"];

export default function Customers() {
  const ws = useWorkspace();
  const navigate = useNavigate();
  const { data: customers = [], isLoading, error } = useCustomers();
  const { data: sites = [] } = useSites();
  const { data: jobs = [] } = useJobs();
  const { data: invoices = [] } = useInvoices();
  const [query, setQuery] = useState("");
  const [type, setType] = useState<(typeof TYPES)[number]>("all");
  const [creating, setCreating] = useState(false);
  const canMoney = ws.can("invoicesRead");

  const stats = useMemo(() => {
    const firstSite = new Map<string, Site>();
    const siteCount = new Map<string, number>();
    [...sites]
      .sort((a, b) => a.created_at.localeCompare(b.created_at))
      .forEach((s) => {
        if (!firstSite.has(s.customer_id)) firstSite.set(s.customer_id, s);
        siteCount.set(s.customer_id, (siteCount.get(s.customer_id) ?? 0) + 1);
      });
    const openJobs = new Map<string, number>();
    jobs.filter((j) => isOpen(j.status)).forEach((j) => openJobs.set(j.customer_id, (openJobs.get(j.customer_id) ?? 0) + 1));
    const owed = new Map<string, number>();
    const overdue = new Set<string>();
    invoices.forEach((i) => {
      const s = effectiveStatus(i);
      if (!isReceivable(s)) return;
      owed.set(i.customer_id, (owed.get(i.customer_id) ?? 0) + i.balance);
      if (s === "overdue") overdue.add(i.customer_id);
    });
    return { firstSite, siteCount, openJobs, owed, overdue };
  }, [sites, jobs, invoices]);

  const list = useMemo(() => {
    const q = query.trim().toLowerCase();
    return customers.filter(
      (c) =>
        (type === "all" || c.type === type) &&
        (!q || c.name.toLowerCase().includes(q) || siteLine(stats.firstSite.get(c.id)).toLowerCase().includes(q)),
    );
  }, [customers, type, query, stats]);

  return (
    <Page>
      <PageHeader
        title="Customers"
        subtitle={`${customers.length} customers in ${ws.company.name}`}
        actions={
          ws.can("customersManage") && (
            <Button onClick={() => setCreating(true)} className="press gap-1.5 bg-brand-orange hover:bg-brand-orange/90">
              <Plus className="h-4 w-4" /> New customer
            </Button>
          )
        }
      />

      <div className="mb-4 flex flex-wrap gap-1.5">
        {TYPES.map((t) => (
          <button
            key={t}
            onClick={() => setType(t)}
            className={cn(
              "press rounded-full border px-3.5 py-1.5 text-sm font-medium transition-colors",
              type === t ? "border-brand-orange bg-brand-orange text-white" : "border-border bg-card text-muted-foreground hover:text-foreground",
            )}
          >
            {t === "all" ? "All" : CUSTOMER_TYPE_TITLE[t]}
          </button>
        ))}
      </div>

      <div className="card-surface overflow-hidden">
        <div className="border-b border-border p-3">
          <div className="relative">
            <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-meta" />
            <Input
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Search name or address…"
              className="h-10 border-0 bg-secondary pl-9 shadow-none"
            />
          </div>
        </div>

        {isLoading ? (
          <LoadingRows count={8} />
        ) : error ? (
          <p className="p-6 text-sm text-destructive">{(error as Error).message}</p>
        ) : list.length === 0 ? (
          <EmptyState
            icon={Users}
            title={customers.length ? "No customers match" : "No customers yet"}
            body={customers.length ? "Try another filter or clear the search." : "Add your first customer with their site and main contact."}
            action={
              ws.can("customersManage") && !customers.length ? (
                <Button onClick={() => setCreating(true)} className="bg-brand-orange hover:bg-brand-orange/90">
                  New customer
                </Button>
              ) : undefined
            }
          />
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full min-w-[820px] text-sm">
              <thead className="bg-secondary/50">
                <tr className="text-left">
                  <th className="section-label px-4 py-3">Customer</th>
                  <th className="section-label px-4 py-3">Main site</th>
                  <th className="section-label w-28 px-4 py-3 text-right">Open jobs</th>
                  {canMoney && <th className="section-label w-40 px-4 py-3 text-right">Owed</th>}
                </tr>
              </thead>
              <tbody className="divide-y divide-border">
                {list.map((c) => {
                  const site = stats.firstSite.get(c.id);
                  const more = (stats.siteCount.get(c.id) ?? 0) - 1;
                  const open = stats.openJobs.get(c.id) ?? 0;
                  const owed = stats.owed.get(c.id) ?? 0;
                  return (
                    <tr key={c.id} onClick={() => navigate(`/customers/${c.id}`)} className="cursor-pointer transition-colors hover:bg-primary-tint/50">
                      <td className="px-4 py-3">
                        <p className="font-semibold">{c.name}</p>
                        <p className="text-xs text-meta">
                          {CUSTOMER_TYPE_TITLE[c.type] ?? c.type} · {c.billing_terms}
                        </p>
                      </td>
                      <td className="px-4 py-3 text-muted-foreground">
                        {site ? siteLine(site) : "No site on file"}
                        {more > 0 && <span className="ml-1.5 text-xs text-meta">+{more} more</span>}
                      </td>
                      <td className="px-4 py-3 text-right tabular-nums">
                        {open ? <span className="font-semibold text-primary">{open}</span> : <span className="text-meta">—</span>}
                      </td>
                      {canMoney && (
                        <td className="px-4 py-3 text-right tabular-nums">
                          {owed > 0 ? (
                            <span className={cn("font-semibold", stats.overdue.has(c.id) ? "text-destructive" : "text-foreground")}>
                              {money2(owed, ws.company.currency_code)}
                            </span>
                          ) : (
                            <span className="text-meta">—</span>
                          )}
                        </td>
                      )}
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>

      <CustomerDialog open={creating} onOpenChange={setCreating} />
    </Page>
  );
}
