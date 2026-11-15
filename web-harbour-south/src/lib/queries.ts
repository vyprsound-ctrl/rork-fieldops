import { useQuery, useQueryClient } from "@tanstack/react-query";

import { allJobs, fieldWorkers, jobDetail, latestPositions, moneySnapshot } from "./api";
import { useWorkspace } from "./session";
import { allSites, customerDetail, customerList, invoiceDetail, invoiceList, quoteDetail, quoteList } from "./crm";

export const keys = {
  jobs: ["jobs"] as const,
  workers: ["workers"] as const,
  job: (id: string) => ["job", id] as const,
  money: ["money"] as const,
  positions: ["positions"] as const,
  customers: ["crm", "customers"] as const,
  sites: ["crm", "sites"] as const,
  customer: (id: string) => ["crm", "customer", id] as const,
  quotes: ["crm", "quotes"] as const,
  quote: (id: string) => ["crm", "quote", id] as const,
  invoices: ["crm", "invoices"] as const,
  invoice: (id: string) => ["crm", "invoice", id] as const,
};

export function useCustomers() {
  return useQuery({ queryKey: keys.customers, queryFn: customerList });
}

export function useSites() {
  return useQuery({ queryKey: keys.sites, queryFn: allSites, staleTime: 60_000 });
}

export function useCustomer(id: string) {
  const ws = useWorkspace();
  return useQuery({ queryKey: keys.customer(id), queryFn: () => customerDetail(id, ws.can("equipmentRead")) });
}

export function useQuotes() {
  const ws = useWorkspace();
  return useQuery({
    queryKey: keys.quotes,
    queryFn: () => quoteList(ws.can("quoteFinancialsRead")),
    enabled: ws.can("quotesRead"),
  });
}

export function useQuote(id: string) {
  const ws = useWorkspace();
  return useQuery({ queryKey: keys.quote(id), queryFn: () => quoteDetail(id, ws.can("quoteFinancialsRead")) });
}

export function useInvoices() {
  const ws = useWorkspace();
  return useQuery({ queryKey: keys.invoices, queryFn: invoiceList, enabled: ws.can("invoicesRead") });
}

export function useInvoice(id: string) {
  const ws = useWorkspace();
  return useQuery({ queryKey: keys.invoice(id), queryFn: () => invoiceDetail(id, ws.can("paymentsRead")) });
}

/** After a customer, quote or invoice write: refresh every money and CRM view, plus jobs. */
export function useRefreshCrm() {
  const qc = useQueryClient();
  return () => {
    qc.invalidateQueries({ queryKey: ["crm"] });
    qc.invalidateQueries({ queryKey: keys.money });
    qc.invalidateQueries({ queryKey: keys.jobs });
    qc.invalidateQueries({ queryKey: ["customers"] });
    qc.invalidateQueries({ queryKey: ["addresses"] });
  };
}

export function useJobs() {
  return useQuery({ queryKey: keys.jobs, queryFn: allJobs, refetchInterval: 60_000 });
}

export function useWorkers() {
  return useQuery({ queryKey: keys.workers, queryFn: fieldWorkers, staleTime: 5 * 60_000 });
}

export function useJobDetail(id: string | null) {
  const ws = useWorkspace();
  return useQuery({
    queryKey: keys.job(id ?? "none"),
    queryFn: () => jobDetail(id!, ws.can("jobNotesRead"), ws.can("jobPhotosRead")),
    enabled: !!id,
  });
}

export function useMoney() {
  const ws = useWorkspace();
  const quotes = ws.can("quoteFinancialsRead");
  const invoices = ws.can("invoicesRead");
  return useQuery({
    queryKey: keys.money,
    queryFn: () => moneySnapshot(quotes, invoices),
    enabled: quotes || invoices,
  });
}

export function usePositions() {
  const ws = useWorkspace();
  return useQuery({
    queryKey: keys.positions,
    queryFn: latestPositions,
    enabled: ws.can("fieldWorkerLocationReadAll"),
    refetchInterval: 30_000,
  });
}

/** After any write: refresh lists and the open job everywhere. */
export function useRefreshJobs() {
  const qc = useQueryClient();
  return (jobId?: string) => {
    qc.invalidateQueries({ queryKey: keys.jobs });
    if (jobId) qc.invalidateQueries({ queryKey: keys.job(jobId) });
  };
}
