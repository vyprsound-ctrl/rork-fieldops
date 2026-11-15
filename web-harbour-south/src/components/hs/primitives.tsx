import type { ReactNode } from "react";
import type { LucideIcon } from "lucide-react";
import { Flame } from "lucide-react";
import { useSearchParams } from "react-router-dom";

import { cn } from "@/lib/utils";
import { initials, statusTitle, statusTone, type JobStatus, type Terminology, type Tone } from "@/lib/domain";

export const TONE_CLASS: Record<Tone, string> = {
  info: "bg-primary-tint text-primary",
  warning: "bg-[hsl(38_100%_94%)] text-warning",
  success: "bg-[hsl(147_55%_93%)] text-success",
  neutral: "bg-secondary text-muted-foreground",
  danger: "bg-[hsl(6_80%_95%)] text-destructive",
};

export const TONE_DOT: Record<Tone, string> = {
  info: "bg-primary",
  warning: "bg-warning",
  success: "bg-success",
  neutral: "bg-meta",
  danger: "bg-destructive",
};

export function StatusBadge({ status, terms, className }: { status: JobStatus; terms: Terminology; className?: string }) {
  const tone = statusTone(status);
  return (
    <span
      className={cn(
        "inline-flex items-center gap-1.5 whitespace-nowrap rounded-full px-2.5 py-0.5 text-xs font-semibold",
        TONE_CLASS[tone],
        className,
      )}
    >
      <span className={cn("h-1.5 w-1.5 rounded-full", TONE_DOT[tone])} />
      {statusTitle(status, terms)}
    </span>
  );
}

export function UrgentTag({ compact }: { compact?: boolean }) {
  return (
    <span className="inline-flex items-center gap-1 rounded-full bg-brand-orange-tint px-2 py-0.5 text-[11px] font-bold uppercase tracking-wide text-brand-orange-text">
      <Flame className="h-3 w-3" />
      {!compact && "Urgent"}
    </span>
  );
}

const AVATAR_TONES = [
  "bg-primary text-primary-foreground",
  "bg-brand-orange text-white",
  "bg-success text-white",
  "bg-brand-navy text-white",
  "bg-warning text-white",
];

export function WorkerAvatar({ name, id, size = 28 }: { name: string; id?: string; size?: number }) {
  const seed = (id ?? name).split("").reduce((s, c) => s + c.charCodeAt(0), 0);
  return (
    <span
      className={cn("inline-flex shrink-0 items-center justify-center rounded-full font-bold", AVATAR_TONES[seed % AVATAR_TONES.length])}
      style={{ width: size, height: size, fontSize: Math.max(10, size * 0.38) }}
      title={name}
    >
      {initials(name)}
    </span>
  );
}

export function PageHeader({ title, subtitle, actions }: { title: string; subtitle?: ReactNode; actions?: ReactNode }) {
  return (
    <div className="flex flex-wrap items-end justify-between gap-4 pb-6">
      <div>
        <h1 className="text-[28px] font-bold leading-tight tracking-tight text-foreground">{title}</h1>
        {subtitle && <p className="mt-1 text-sm text-muted-foreground">{subtitle}</p>}
      </div>
      {actions && <div className="flex items-center gap-2">{actions}</div>}
    </div>
  );
}

export function EmptyState({ icon: Icon, title, body, action }: { icon: LucideIcon; title: string; body?: string; action?: ReactNode }) {
  return (
    <div className="flex flex-col items-center justify-center px-6 py-14 text-center">
      <div className="mb-4 flex h-14 w-14 items-center justify-center rounded-2xl bg-primary-tint text-primary">
        <Icon className="h-6 w-6" />
      </div>
      <p className="text-base font-semibold">{title}</p>
      {body && <p className="mt-1 max-w-sm text-sm text-muted-foreground">{body}</p>}
      {action && <div className="mt-5">{action}</div>}
    </div>
  );
}

export function LoadingRows({ count = 6 }: { count?: number }) {
  return (
    <div className="space-y-2 p-4">
      {Array.from({ length: count }).map((_, i) => (
        <div key={i} className="h-12 animate-pulse rounded-xl bg-secondary" style={{ opacity: 1 - i * 0.12 }} />
      ))}
    </div>
  );
}

/** Any page can open the job side panel; the job id lives in the address bar. */
export function useJobPanel() {
  const [params, setParams] = useSearchParams();
  const jobId = params.get("job");
  return {
    jobId,
    open: (id: string) =>
      setParams((p) => {
        const next = new URLSearchParams(p);
        next.set("job", id);
        return next;
      }),
    close: () =>
      setParams((p) => {
        const next = new URLSearchParams(p);
        next.delete("job");
        return next;
      }),
  };
}
