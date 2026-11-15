import { useEffect, useMemo } from "react";
import { MapContainer, Marker, Popup, TileLayer, useMap } from "react-leaflet";
import L from "leaflet";
import "leaflet/dist/leaflet.css";
import { MapPinOff, Navigation, ShieldAlert } from "lucide-react";

import { Page } from "@/components/hs/AppShell";
import { EmptyState, PageHeader, StatusBadge, WorkerAvatar, useJobPanel } from "@/components/hs/primitives";
import { cn } from "@/lib/utils";
import { initials, isFieldActive } from "@/lib/domain";
import { relativeAgo } from "@/lib/format";
import { RECENT_MINUTES, type WorkerPosition } from "@/lib/api";
import { useJobs, usePositions, useWorkers } from "@/lib/queries";
import { useWorkspace } from "@/lib/session";

const pin = (p: WorkerPosition) =>
  L.divIcon({
    className: "",
    html: `<div class="worker-pin ${p.recent ? "recent" : "stale"}">${initials(p.name)}</div>`,
    iconSize: [34, 34],
    iconAnchor: [17, 17],
    popupAnchor: [0, -18],
  });

function FitBounds({ points }: { points: [number, number][] }) {
  const map = useMap();
  const key = points.map((p) => p.join(",")).join("|");
  useEffect(() => {
    if (!points.length) return;
    if (points.length === 1) map.setView(points[0], 13);
    else map.fitBounds(L.latLngBounds(points), { padding: [60, 60], maxZoom: 14 });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key, map]);
  return null;
}

export default function LiveMap() {
  const ws = useWorkspace();
  const panel = useJobPanel();
  const { data: positions = [], isLoading, dataUpdatedAt } = usePositions();
  const { data: workers = [] } = useWorkers();
  const { data: jobs = [] } = useJobs();

  const points = useMemo(() => positions.map((p) => [p.latitude, p.longitude] as [number, number]), [positions]);
  const located = new Set(positions.map((p) => p.user_id));
  const missing = workers.filter((w) => !located.has(w.id));
  const activeJob = (userId: string) => jobs.find((j) => j.workerId === userId && isFieldActive(j.status));

  if (!ws.can("fieldWorkerLocationReadAll")) {
    return (
      <Page>
        <PageHeader title="Live map" />
        <div className="card-surface">
          <EmptyState icon={ShieldAlert} title="Not available for your role" body={`Only owners, admins and dispatchers can see where ${ws.terms.workerPlural} are.`} />
        </div>
      </Page>
    );
  }

  return (
    <Page className="max-w-none">
      <PageHeader
        title="Live map"
        subtitle={`Positions are shared only while a ${ws.terms.worker} is on a job. Updated ${dataUpdatedAt ? relativeAgo(new Date(dataUpdatedAt).toISOString()) : "—"}.`}
      />
      <div className="grid gap-5 xl:grid-cols-[1fr_320px]">
        <div className="card-surface relative h-[calc(100vh-220px)] min-h-[440px] overflow-hidden">
          <MapContainer center={[39.5, -98.35]} zoom={4} className="h-full w-full" scrollWheelZoom>
            <TileLayer
              attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a>'
              url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png"
            />
            <FitBounds points={points} />
            {positions.map((p) => {
              const job = activeJob(p.user_id);
              return (
                <Marker key={p.id} position={[p.latitude, p.longitude]} icon={pin(p)}>
                  <Popup>
                    <div className="min-w-[180px] space-y-1">
                      <p className="text-sm font-semibold">{p.name}</p>
                      <p className="text-xs text-muted-foreground">
                        {p.recent ? "Live" : "Last seen"} · {relativeAgo(p.recorded_at)}
                        {p.is_simulated ? " · test location" : ""}
                      </p>
                      {job && (
                        <button onClick={() => panel.open(job.id)} className="mt-1 text-left text-xs font-semibold text-primary hover:underline">
                          {job.number} · {job.title}
                        </button>
                      )}
                    </div>
                  </Popup>
                </Marker>
              );
            })}
          </MapContainer>
          {!isLoading && positions.length === 0 && (
            <div className="pointer-events-none absolute inset-0 z-[500] flex items-center justify-center">
              <div className="rounded-2xl bg-card/95 px-5 py-4 text-center shadow-panel">
                <p className="text-sm font-semibold">No one is sharing a location</p>
                <p className="mt-0.5 text-xs text-muted-foreground">Pins appear when a {ws.terms.worker} starts travelling.</p>
              </div>
            </div>
          )}
        </div>

        <aside className="space-y-4">
          <section className="card-surface p-4">
            <h2 className="mb-3 text-sm font-semibold">On the map</h2>
            <div className="mb-3 flex gap-4 text-xs text-muted-foreground">
              <span className="flex items-center gap-1.5"><span className="h-2.5 w-2.5 rounded-full bg-brand-orange" /> Last {RECENT_MINUTES} min</span>
              <span className="flex items-center gap-1.5"><span className="h-2.5 w-2.5 rounded-full bg-meta" /> Older</span>
            </div>
            <ul className="space-y-2.5">
              {positions.map((p) => {
                const job = activeJob(p.user_id);
                return (
                  <li key={p.id} className="flex items-center gap-3">
                    <div className="relative">
                      <WorkerAvatar name={p.name} id={p.user_id} size={32} />
                      <span className={cn("absolute -bottom-0.5 -right-0.5 h-3 w-3 rounded-full border-2 border-card", p.recent ? "bg-brand-orange" : "bg-meta")} />
                    </div>
                    <div className="min-w-0 flex-1">
                      <p className="truncate text-sm font-medium">{p.name}</p>
                      <p className="truncate text-xs text-muted-foreground">{relativeAgo(p.recorded_at)}</p>
                    </div>
                    {job ? (
                      <button onClick={() => panel.open(job.id)}>
                        <StatusBadge status={job.status} terms={ws.terms} />
                      </button>
                    ) : (
                      <Navigation className="h-4 w-4 text-meta" />
                    )}
                  </li>
                );
              })}
              {positions.length === 0 && <p className="text-sm text-muted-foreground">Nobody yet.</p>}
            </ul>
          </section>

          {missing.length > 0 && (
            <section className="card-surface p-4">
              <div className="mb-3 flex items-center gap-2">
                <MapPinOff className="h-4 w-4 text-meta" />
                <h2 className="text-sm font-semibold">No location</h2>
              </div>
              <ul className="space-y-2">
                {missing.map((w) => (
                  <li key={w.id} className="flex items-center gap-3 text-sm text-muted-foreground">
                    <WorkerAvatar name={w.name} id={w.id} size={26} />
                    {w.name}
                  </li>
                ))}
              </ul>
            </section>
          )}
        </aside>
      </div>
    </Page>
  );
}
