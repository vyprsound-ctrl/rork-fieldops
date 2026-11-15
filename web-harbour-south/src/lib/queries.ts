import { useQuery, useQueryClient } from "@tanstack/react-query";

import { allJobs, fieldWorkers, jobDetail, latestPositions, moneySnapshot } from "./api";
import { useWorkspace } from "./session";

export const keys = {
  jobs: ["jobs"] as const,
  workers: ["workers"] as const,
  job: (id: string) => ["job", id] as const,
  money: ["money"] as const,
  positions: ["positions"] as const,
};

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
