import { useEffect, useMemo, useRef, useState } from "react";
import { useSearchParams } from "react-router-dom";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import {
  Ban,
  Coins,
  Flag,
  Loader2,
  MessageCircle,
  MessageSquare,
  MoreHorizontal,
  PenSquare,
  Phone,
  RefreshCw,
  Search,
  Send,
  Settings2,
} from "lucide-react";
import { toast } from "sonner";

import { Page } from "@/components/hs/AppShell";
import { EmptyState, LoadingRows, PageHeader, WorkerAvatar } from "@/components/hs/primitives";
import { Confirm, Field, Section, StatTile, ToneBadge } from "@/components/hs/crm";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Textarea } from "@/components/ui/textarea";
import { Checkbox } from "@/components/ui/checkbox";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from "@/components/ui/dropdown-menu";
import { cn } from "@/lib/utils";
import { usd } from "@/lib/billing";
import { LEGAL_PATHS } from "@/lib/site";
import { dateOnly, relativeAgo, time } from "@/lib/format";
import { useCustomers, useJobs, useWorkers } from "@/lib/queries";
import { useWorkspace } from "@/lib/session";
import {
  REPORT_REASONS,
  ROUTES,
  STRUCTURES,
  blockUser,
  blockedUsers,
  detailsProblem,
  firstStatus,
  markSmsRead,
  markThreadRead,
  officeMessages,
  officeThreads,
  prettyPhone,
  reportOfficeMessage,
  reportSmsMessage,
  sendOfficeMessage,
  smsBundles,
  smsCheckout,
  smsConversations,
  smsMessages,
  smsPreview,
  smsSend,
  smsSetup,
  smsUsage,
  threadTitle,
  unblockUser,
  type AvailableNumber,
  type SmsDetails,
  type SmsSendResult,
  type SmsStatus,
} from "@/lib/messages";

type Tab = "office" | "customers" | "setup" | "credits";

export default function Messages() {
  const ws = useWorkspace();
  const [params, setParams] = useSearchParams();
  const smsAccess = ws.can("smsCreditsConsume") || ws.can("smsLedgerRead");
  const tabs: { id: Tab; label: string; icon: typeof MessageCircle; show: boolean }[] = [
    { id: "office", label: `${ws.terms.WorkerPlural}`, icon: MessageCircle, show: ws.can("jobsReadAll") },
    { id: "customers", label: "Customer texts", icon: MessageSquare, show: smsAccess && ws.can("customersReadAll") },
    { id: "setup", label: "SMS setup", icon: Settings2, show: smsAccess },
    { id: "credits", label: "SMS credits", icon: Coins, show: ws.can("smsLedgerRead") },
  ];
  const visible = tabs.filter((t) => t.show);
  const tab = visible.find((t) => t.id === params.get("tab")) ?? visible[0];

  return (
    <Page className="max-w-[1400px]">
      <PageHeader title="Messages" subtitle="Chat with your team and text your customers." />
      <div className="mb-5 flex flex-wrap gap-1.5">
        {visible.map((t) => (
          <button
            key={t.id}
            onClick={() => setParams({ tab: t.id })}
            className={cn(
              "press inline-flex items-center gap-1.5 rounded-full border px-3.5 py-1.5 text-sm font-medium transition-colors",
              tab?.id === t.id ? "border-brand-orange bg-brand-orange text-white" : "border-border bg-card text-muted-foreground hover:text-foreground",
            )}
          >
            <t.icon className="h-4 w-4" /> {t.label}
          </button>
        ))}
      </div>
      {!tab && <EmptyState icon={MessageCircle} title="Messages aren't available for your role" />}
      {tab?.id === "office" && <OfficeInbox />}
      {tab?.id === "customers" && <CustomerTexts />}
      {tab?.id === "setup" && <SmsSetupPanel />}
      {tab?.id === "credits" && <Credits />}
    </Page>
  );
}

// ---------------------------------------------------------------------------
// Office inbox
// ---------------------------------------------------------------------------

function OfficeInbox() {
  const ws = useWorkspace();
  const qc = useQueryClient();
  const threads = useQuery({ queryKey: ["office", "threads"], queryFn: () => officeThreads(ws.me.id), refetchInterval: 20_000 });
  const blocked = useQuery({ queryKey: ["office", "blocked"], queryFn: blockedUsers });
  const [selected, setSelected] = useState<string | null>(null);
  const [composing, setComposing] = useState(false);
  const [query, setQuery] = useState("");

  const list = useMemo(() => {
    const q = query.trim().toLowerCase();
    return (threads.data ?? []).filter(
      (t) => !q || [t.engineerName, t.subject, t.jobNumber, t.last_message_preview].some((s) => s?.toLowerCase().includes(q)),
    );
  }, [threads.data, query]);
  const thread = (threads.data ?? []).find((t) => t.id === selected) ?? null;

  useEffect(() => {
    if (!selected && list[0]) setSelected(list[0].id);
  }, [list, selected]);

  return (
    <div className="card-surface grid min-h-[620px] overflow-hidden md:grid-cols-[340px_1fr]">
      <div className="flex min-h-0 flex-col border-b border-border md:border-b-0 md:border-r">
        <div className="flex gap-2 border-b border-border p-3">
          <div className="relative flex-1">
            <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-meta" />
            <Input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Search" className="h-9 border-0 bg-secondary pl-9 shadow-none" />
          </div>
          {ws.can("jobsManage") && (
            <Button size="icon" className="h-9 w-9 bg-brand-orange hover:bg-brand-orange/90" onClick={() => setComposing(true)} aria-label="New message">
              <PenSquare className="h-4 w-4" />
            </Button>
          )}
        </div>
        <div className="min-h-0 flex-1 overflow-y-auto scroll-thin">
          {threads.isLoading ? (
            <LoadingRows count={6} />
          ) : threads.error ? (
            <p className="p-4 text-sm text-destructive">{(threads.error as Error).message}</p>
          ) : list.length === 0 ? (
            <EmptyState icon={MessageCircle} title="No conversations yet" body={`Messages between the office and your ${ws.terms.workerPlural} appear here.`} />
          ) : (
            list.map((t) => (
              <button
                key={t.id}
                onClick={() => setSelected(t.id)}
                className={cn(
                  "flex w-full items-start gap-3 border-b border-border px-4 py-3 text-left transition-colors",
                  selected === t.id ? "bg-primary-tint/60" : "hover:bg-secondary/60",
                )}
              >
                <WorkerAvatar name={t.engineerName} id={t.engineer_user_id} size={36} />
                <div className="min-w-0 flex-1">
                  <div className="flex items-center gap-2">
                    <p className={cn("flex-1 truncate text-sm", t.unread ? "font-bold" : "font-medium")}>{t.engineerName}</p>
                    <span className="shrink-0 text-[11px] text-meta">{relativeAgo(t.last_message_at)}</span>
                  </div>
                  <p className="truncate text-xs font-medium text-muted-foreground">
                    {t.jobNumber ? `${t.jobNumber} · ` : ""}
                    {threadTitle(t)}
                  </p>
                  <p className={cn("truncate text-xs", t.unread ? "text-foreground" : "text-meta")}>{t.last_message_preview}</p>
                </div>
                {t.unread && <span className="mt-1.5 h-2 w-2 shrink-0 rounded-full bg-brand-orange" />}
              </button>
            ))
          )}
        </div>
      </div>
      {thread ? (
        <OfficeThreadView
          key={thread.id}
          threadId={thread.id}
          title={threadTitle(thread)}
          engineerId={thread.engineer_user_id}
          engineerName={thread.engineerName}
          jobNumber={thread.jobNumber}
          isBlocked={!!blocked.data?.has(thread.engineer_user_id)}
          onChanged={() => {
            void qc.invalidateQueries({ queryKey: ["office"] });
          }}
        />
      ) : (
        <div className="hidden items-center justify-center md:flex">
          <EmptyState icon={MessageCircle} title="Choose a conversation" />
        </div>
      )}
      {composing && (
        <ComposeOffice
          onClose={() => setComposing(false)}
          onSent={(id) => {
            setSelected(id);
            void qc.invalidateQueries({ queryKey: ["office"] });
          }}
        />
      )}
    </div>
  );
}

function OfficeThreadView({
  threadId,
  title,
  engineerId,
  engineerName,
  jobNumber,
  isBlocked,
  onChanged,
}: {
  threadId: string;
  title: string;
  engineerId: string;
  engineerName: string;
  jobNumber?: string;
  isBlocked: boolean;
  onChanged: () => void;
}) {
  const ws = useWorkspace();
  const messages = useQuery({ queryKey: ["office", "messages", threadId], queryFn: () => officeMessages(threadId), refetchInterval: 10_000 });
  const [body, setBody] = useState("");
  const [busy, setBusy] = useState(false);
  const [reporting, setReporting] = useState<string | null>(null);
  const [blocking, setBlocking] = useState(false);
  const end = useRef<HTMLDivElement>(null);
  const count = messages.data?.length ?? 0;

  useEffect(() => {
    void markThreadRead(threadId).then(onChanged);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [threadId, count]);
  useEffect(() => end.current?.scrollIntoView({ block: "end" }), [count]);

  const send = async () => {
    setBusy(true);
    try {
      await sendOfficeMessage({ threadId, engineerId: null, jobId: null, subject: "", body });
      setBody("");
      await messages.refetch();
      onChanged();
    } catch (err) {
      toast.error((err as Error).message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="flex min-h-[520px] flex-col">
      <div className="flex items-center gap-3 border-b border-border px-5 py-3">
        <WorkerAvatar name={engineerName} id={engineerId} size={36} />
        <div className="min-w-0 flex-1">
          <p className="truncate font-semibold">{engineerName}</p>
          <p className="truncate text-xs text-muted-foreground">
            {jobNumber ? `${jobNumber} · ` : ""}
            {title}
          </p>
        </div>
        <DropdownMenu>
          <DropdownMenuTrigger className="rounded-lg p-1.5 text-muted-foreground hover:bg-secondary" aria-label="More">
            <MoreHorizontal className="h-4 w-4" />
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end">
            {isBlocked ? (
              <DropdownMenuItem
                onClick={() =>
                  void unblockUser(engineerId)
                    .then(() => {
                      toast.success(`${engineerName} is unblocked.`);
                      onChanged();
                    })
                    .catch((e: Error) => toast.error(e.message))
                }
              >
                Unblock {engineerName}
              </DropdownMenuItem>
            ) : (
              <DropdownMenuItem className="text-destructive" onClick={() => setBlocking(true)}>
                <Ban className="mr-2 h-4 w-4" /> Block {engineerName}
              </DropdownMenuItem>
            )}
          </DropdownMenuContent>
        </DropdownMenu>
      </div>
      <div className="min-h-0 flex-1 space-y-2 overflow-y-auto bg-secondary/30 px-5 py-4 scroll-thin">
        {messages.isLoading ? (
          <LoadingRows count={4} />
        ) : (
          (messages.data ?? []).map((m) => {
            const mine = m.sender_user_id === ws.me.id;
            const fromEngineer = m.sender_user_id === engineerId;
            const hidden = fromEngineer && isBlocked;
            return (
              <div key={m.id} className={cn("group flex items-end gap-2", mine ? "justify-end" : "justify-start")}>
                {!mine && fromEngineer && (
                  <button
                    onClick={() => setReporting(m.id)}
                    className="order-2 rounded p-1 text-meta opacity-0 transition-opacity hover:text-destructive group-hover:opacity-100"
                    aria-label="Report message"
                    title="Report message"
                  >
                    <Flag className="h-3.5 w-3.5" />
                  </button>
                )}
                <div
                  className={cn(
                    "max-w-[72%] rounded-2xl px-3.5 py-2 text-sm shadow-sm",
                    mine ? "rounded-br-md bg-primary text-primary-foreground" : "rounded-bl-md bg-card",
                  )}
                >
                  <p className="whitespace-pre-wrap break-words">{hidden ? <span className="italic text-meta">Message from a blocked person</span> : m.body}</p>
                  {(m.job_photo_ids?.length ?? 0) > 0 && !hidden && (
                    <p className={cn("mt-1 text-[11px]", mine ? "text-white/70" : "text-meta")}>
                      {m.job_photo_ids!.length} photo{m.job_photo_ids!.length === 1 ? "" : "s"} on the job
                    </p>
                  )}
                  <p className={cn("mt-0.5 text-right text-[10px]", mine ? "text-white/70" : "text-meta")}>{time(m.created_at)}</p>
                </div>
              </div>
            );
          })
        )}
        <div ref={end} />
      </div>
      {ws.can("jobsManage") ? (
        <div className="flex items-end gap-2 border-t border-border p-3">
          <Textarea
            value={body}
            onChange={(e) => setBody(e.target.value)}
            placeholder={`Message ${engineerName}`}
            rows={1}
            className="max-h-40 min-h-[40px] resize-none"
            onKeyDown={(e) => {
              if (e.key === "Enter" && !e.shiftKey && body.trim()) {
                e.preventDefault();
                void send();
              }
            }}
          />
          <Button onClick={() => void send()} disabled={busy || !body.trim()} size="icon" className="h-10 w-10 shrink-0 bg-brand-orange hover:bg-brand-orange/90">
            {busy ? <Loader2 className="h-4 w-4 animate-spin" /> : <Send className="h-4 w-4" />}
          </Button>
        </div>
      ) : (
        <p className="border-t border-border px-5 py-3 text-xs text-muted-foreground">Your role can read these conversations but not reply.</p>
      )}
      <ReportDialog
        open={!!reporting}
        onClose={() => setReporting(null)}
        onSubmit={(reason, details) => reportOfficeMessage(reporting!, reason, details)}
      />
      <Confirm
        open={blocking}
        onOpenChange={setBlocking}
        title={`Block ${engineerName}?`}
        body="Their messages are hidden for you. They aren't told. You can unblock them any time from this menu."
        action="Block"
        onConfirm={() =>
          void blockUser(engineerId, "harassment")
            .then(() => {
              toast.success(`${engineerName} is blocked.`);
              onChanged();
            })
            .catch((e: Error) => toast.error(e.message))
        }
      />
    </div>
  );
}

function ReportDialog({
  open,
  onClose,
  onSubmit,
}: {
  open: boolean;
  onClose: () => void;
  onSubmit: (reason: string, details: string) => Promise<unknown>;
}) {
  const [reason, setReason] = useState("harassment");
  const [details, setDetails] = useState("");
  const [busy, setBusy] = useState(false);
  const submit = async () => {
    setBusy(true);
    try {
      await onSubmit(reason, details);
      toast.success("Thanks. The message has been reported and will be reviewed.");
      setDetails("");
      onClose();
    } catch (err) {
      toast.error((err as Error).message);
    } finally {
      setBusy(false);
    }
  };
  return (
    <Dialog open={open} onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="sm:max-w-[440px]">
        <DialogHeader>
          <DialogTitle>Report this message</DialogTitle>
          <DialogDescription>Reports are reviewed within 24 hours. Abusive users are removed.</DialogDescription>
        </DialogHeader>
        <div className="grid gap-4">
          <Field label="What's wrong?">
            <Select value={reason} onValueChange={setReason}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {REPORT_REASONS.map((r) => (
                  <SelectItem key={r.id} value={r.id}>
                    {r.label}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </Field>
          <Field label="Anything else (optional)">
            <Textarea value={details} onChange={(e) => setDetails(e.target.value)} rows={3} maxLength={1000} />
          </Field>
        </div>
        <DialogFooter>
          <Button variant="ghost" onClick={onClose}>
            Cancel
          </Button>
          <Button variant="destructive" onClick={() => void submit()} disabled={busy}>
            Report
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function ComposeOffice({ onClose, onSent }: { onClose: () => void; onSent: (threadId: string) => void }) {
  const ws = useWorkspace();
  const { data: workers = [] } = useWorkers();
  const { data: jobs = [] } = useJobs();
  const [engineer, setEngineer] = useState("");
  const [job, setJob] = useState("none");
  const [subject, setSubject] = useState("");
  const [body, setBody] = useState("");
  const [busy, setBusy] = useState(false);
  const theirJobs = jobs.filter((j) => j.workerId === engineer).slice(0, 50);

  const send = async () => {
    if (!engineer) return toast.error(`Choose a ${ws.terms.worker}.`);
    setBusy(true);
    try {
      const id = await sendOfficeMessage({ threadId: null, engineerId: engineer, jobId: job === "none" ? null : job, subject, body });
      toast.success("Message sent.");
      onSent(id);
      onClose();
    } catch (err) {
      toast.error((err as Error).message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="sm:max-w-[520px]">
        <DialogHeader>
          <DialogTitle>New message</DialogTitle>
          <DialogDescription>They'll get it in the iPhone app.</DialogDescription>
        </DialogHeader>
        <div className="grid gap-4">
          <Field label="To">
            <Select value={engineer} onValueChange={(v) => { setEngineer(v); setJob("none"); }}>
              <SelectTrigger>
                <SelectValue placeholder={`Choose a ${ws.terms.worker}`} />
              </SelectTrigger>
              <SelectContent>
                {workers.filter((w) => w.status === "active").map((w) => (
                  <SelectItem key={w.id} value={w.id}>
                    {w.name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </Field>
          <Field label="About a job (optional)">
            <Select value={job} onValueChange={setJob} disabled={!engineer}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                <SelectItem value="none">No particular job</SelectItem>
                {theirJobs.map((j) => (
                  <SelectItem key={j.id} value={j.id}>
                    {j.number} · {j.title}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </Field>
          <Field label="Subject (optional)">
            <Input value={subject} onChange={(e) => setSubject(e.target.value)} maxLength={120} />
          </Field>
          <Field label="Message">
            <Textarea value={body} onChange={(e) => setBody(e.target.value)} rows={4} maxLength={4000} />
          </Field>
        </div>
        <DialogFooter>
          <Button variant="ghost" onClick={onClose}>
            Cancel
          </Button>
          <Button onClick={() => void send()} disabled={busy || !body.trim()} className="gap-1.5 bg-brand-orange hover:bg-brand-orange/90">
            <Send className="h-4 w-4" /> Send
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

// ---------------------------------------------------------------------------
// Customer texts
// ---------------------------------------------------------------------------

function CustomerTexts() {
  const ws = useWorkspace();
  const qc = useQueryClient();
  const convs = useQuery({ queryKey: ["sms", "conversations"], queryFn: smsConversations, refetchInterval: 20_000 });
  const [selected, setSelected] = useState<string | null>(null);
  const [newText, setNewText] = useState(false);
  const [query, setQuery] = useState("");
  const list = useMemo(() => {
    const q = query.trim().toLowerCase();
    return (convs.data ?? []).filter(
      (c) => !q || [c.customer_name, c.phone_e164, c.job_number, c.last_preview].some((s) => s?.toLowerCase().includes(q)),
    );
  }, [convs.data, query]);
  const conv = (convs.data ?? []).find((c) => c.conversation_id === selected) ?? null;

  useEffect(() => {
    if (!selected && list[0]) setSelected(list[0].conversation_id);
  }, [list, selected]);

  return (
    <div className="card-surface grid min-h-[620px] overflow-hidden md:grid-cols-[340px_1fr]">
      <div className="flex min-h-0 flex-col border-b border-border md:border-b-0 md:border-r">
        <div className="flex gap-2 border-b border-border p-3">
          <div className="relative flex-1">
            <Search className="absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-meta" />
            <Input value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Search" className="h-9 border-0 bg-secondary pl-9 shadow-none" />
          </div>
          {ws.can("smsCreditsConsume") && (
            <Button size="icon" className="h-9 w-9 bg-brand-orange hover:bg-brand-orange/90" onClick={() => setNewText(true)} aria-label="New text">
              <PenSquare className="h-4 w-4" />
            </Button>
          )}
        </div>
        <div className="min-h-0 flex-1 overflow-y-auto scroll-thin">
          {convs.isLoading ? (
            <LoadingRows count={6} />
          ) : convs.error ? (
            <p className="p-4 text-sm text-destructive">{(convs.error as Error).message}</p>
          ) : list.length === 0 ? (
            <EmptyState icon={MessageSquare} title="No texts yet" body="Texts you send to customers, and their replies, appear here." />
          ) : (
            list.map((c) => (
              <button
                key={c.conversation_id}
                onClick={() => setSelected(c.conversation_id)}
                className={cn(
                  "flex w-full items-start gap-3 border-b border-border px-4 py-3 text-left transition-colors",
                  selected === c.conversation_id ? "bg-primary-tint/60" : "hover:bg-secondary/60",
                )}
              >
                <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full bg-secondary text-primary">
                  <Phone className="h-4 w-4" />
                </div>
                <div className="min-w-0 flex-1">
                  <div className="flex items-center gap-2">
                    <p className={cn("flex-1 truncate text-sm", c.unread ? "font-bold" : "font-medium")}>{c.customer_name ?? prettyPhone(c.phone_e164)}</p>
                    {c.last_message_at && <span className="shrink-0 text-[11px] text-meta">{relativeAgo(c.last_message_at)}</span>}
                  </div>
                  <p className="truncate text-xs text-muted-foreground">
                    {prettyPhone(c.phone_e164)}
                    {c.job_number ? ` · ${c.job_number}` : ""}
                  </p>
                  <p className={cn("truncate text-xs", c.unread ? "text-foreground" : "text-meta")}>
                    {c.last_direction === "outbound" ? "You: " : ""}
                    {c.last_preview}
                  </p>
                </div>
                {c.unread > 0 && (
                  <span className="mt-1 rounded-full bg-brand-orange px-1.5 text-[10px] font-bold text-white">{c.unread}</span>
                )}
              </button>
            ))
          )}
        </div>
      </div>
      {conv ? (
        <SmsThread
          key={conv.conversation_id}
          conversationId={conv.conversation_id}
          customerId={conv.customer_id}
          title={conv.customer_name ?? prettyPhone(conv.phone_e164)}
          phone={conv.phone_e164}
          optedOut={conv.opted_out}
          onChanged={() => void qc.invalidateQueries({ queryKey: ["sms", "conversations"] })}
        />
      ) : (
        <div className="hidden items-center justify-center md:flex">
          <EmptyState icon={MessageSquare} title="Choose a conversation" />
        </div>
      )}
      {newText && (
        <NewTextDialog
          onClose={() => setNewText(false)}
          onSent={(id) => {
            if (id) setSelected(id);
            void qc.invalidateQueries({ queryKey: ["sms"] });
          }}
        />
      )}
    </div>
  );
}

function SmsThread({
  conversationId,
  customerId,
  title,
  phone,
  optedOut,
  onChanged,
}: {
  conversationId: string;
  customerId: string | null;
  title: string;
  phone: string;
  optedOut: boolean;
  onChanged: () => void;
}) {
  const ws = useWorkspace();
  const messages = useQuery({ queryKey: ["sms", "messages", conversationId], queryFn: () => smsMessages(conversationId), refetchInterval: 10_000 });
  const [body, setBody] = useState("");
  const [preview, setPreview] = useState<SmsSendResult | null>(null);
  const [busy, setBusy] = useState(false);
  const [reporting, setReporting] = useState<string | null>(null);
  const end = useRef<HTMLDivElement>(null);
  const count = messages.data?.length ?? 0;

  useEffect(() => {
    void markSmsRead(conversationId).then(onChanged);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [conversationId, count]);
  useEffect(() => end.current?.scrollIntoView({ block: "end" }), [count]);

  const check = async () => {
    if (!customerId) return;
    setBusy(true);
    try {
      setPreview(await smsPreview(customerId, body, phone));
    } catch (err) {
      toast.error((err as Error).message);
    } finally {
      setBusy(false);
    }
  };

  const send = async () => {
    if (!customerId) return;
    setBusy(true);
    try {
      const r = await smsSend(customerId, body, phone);
      toast.success(`Sent · ${r.creditsCharged ?? 1} credit${(r.creditsCharged ?? 1) === 1 ? "" : "s"} used`);
      setBody("");
      setPreview(null);
      await messages.refetch();
      onChanged();
    } catch (err) {
      toast.error((err as Error).message);
    } finally {
      setBusy(false);
    }
  };

  const canSend = ws.can("smsCreditsConsume") && !!customerId && !optedOut;

  return (
    <div className="flex min-h-[520px] flex-col">
      <div className="flex items-center gap-3 border-b border-border px-5 py-3">
        <div className="min-w-0 flex-1">
          <p className="truncate font-semibold">{title}</p>
          <p className="text-xs text-muted-foreground">{prettyPhone(phone)}</p>
        </div>
        {optedOut && <ToneBadge tone="danger">Opted out</ToneBadge>}
      </div>
      <div className="min-h-0 flex-1 space-y-2 overflow-y-auto bg-secondary/30 px-5 py-4 scroll-thin">
        {messages.isLoading ? (
          <LoadingRows count={4} />
        ) : (
          (messages.data ?? []).map((m) => {
            const out = m.direction === "outbound";
            return (
              <div key={m.id} className={cn("group flex items-end gap-2", out ? "justify-end" : "justify-start")}>
                {!out && (
                  <button
                    onClick={() => setReporting(m.id)}
                    className="order-2 rounded p-1 text-meta opacity-0 transition-opacity hover:text-destructive group-hover:opacity-100"
                    aria-label="Report message"
                    title="Report message"
                  >
                    <Flag className="h-3.5 w-3.5" />
                  </button>
                )}
                <div className={cn("max-w-[72%] rounded-2xl px-3.5 py-2 text-sm shadow-sm", out ? "rounded-br-md bg-success text-white" : "rounded-bl-md bg-card")}>
                  <p className="whitespace-pre-wrap break-words">{m.body}</p>
                  <p className={cn("mt-0.5 text-right text-[10px]", out ? "text-white/75" : "text-meta")}>
                    {time(m.at)}
                    {out && m.status && m.status !== "sent" ? ` · ${m.status}` : ""}
                  </p>
                  {m.failure_reason && <p className="mt-0.5 text-[11px] text-white/90">{m.failure_reason}</p>}
                </div>
              </div>
            );
          })
        )}
        <div ref={end} />
      </div>
      {optedOut ? (
        <p className="border-t border-border px-5 py-3 text-xs text-muted-foreground">This number replied STOP. Texts can't be sent until they reply START.</p>
      ) : !customerId ? (
        <p className="border-t border-border px-5 py-3 text-xs text-muted-foreground">This number isn't linked to a customer yet. Add it to a customer to reply.</p>
      ) : canSend ? (
        <div className="border-t border-border p-3">
          {preview && (
            <div className="mb-2 rounded-xl bg-secondary px-3 py-2 text-xs text-muted-foreground">
              {preview.blockerMessage ? (
                <span className="text-destructive">{preview.blockerMessage}</span>
              ) : (
                <>
                  {preview.segments ?? 1} segment{(preview.segments ?? 1) === 1 ? "" : "s"} · uses {preview.creditsNeeded ?? preview.segments ?? 1} credit
                  {(preview.creditsNeeded ?? preview.segments ?? 1) === 1 ? "" : "s"}. Press Send to confirm.
                </>
              )}
            </div>
          )}
          <div className="flex items-end gap-2">
            <Textarea
              value={body}
              onChange={(e) => {
                setBody(e.target.value);
                setPreview(null);
              }}
              placeholder="Text message"
              rows={1}
              maxLength={1000}
              className="max-h-40 min-h-[40px] resize-none"
            />
            <Button
              onClick={() => void (preview && !preview.blockerMessage ? send() : check())}
              disabled={busy || !body.trim()}
              className="h-10 shrink-0 gap-1.5 bg-brand-orange hover:bg-brand-orange/90"
            >
              {busy ? <Loader2 className="h-4 w-4 animate-spin" /> : <Send className="h-4 w-4" />}
              {preview && !preview.blockerMessage ? "Send" : "Check"}
            </Button>
          </div>
        </div>
      ) : (
        <p className="border-t border-border px-5 py-3 text-xs text-muted-foreground">Your role can read texts but not send them.</p>
      )}
      <ReportDialog
        open={!!reporting}
        onClose={() => setReporting(null)}
        onSubmit={(reason, details) => reportSmsMessage(reporting!, reason, details)}
      />
    </div>
  );
}

function NewTextDialog({ onClose, onSent }: { onClose: () => void; onSent: (conversationId: string | null) => void }) {
  const { data: customers = [] } = useCustomers();
  const [customer, setCustomer] = useState("");
  const [body, setBody] = useState("");
  const [preview, setPreview] = useState<SmsSendResult | null>(null);
  const [busy, setBusy] = useState(false);

  const act = async () => {
    if (!customer) return toast.error("Choose a customer.");
    setBusy(true);
    try {
      if (!preview || preview.blockerMessage) {
        setPreview(await smsPreview(customer, body));
      } else {
        const r = await smsSend(customer, body);
        toast.success("Text sent.");
        onSent(r.conversationId ?? null);
        onClose();
      }
    } catch (err) {
      toast.error((err as Error).message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="sm:max-w-[500px]">
        <DialogHeader>
          <DialogTitle>Text a customer</DialogTitle>
          <DialogDescription>Goes to the customer's main mobile number from your business number.</DialogDescription>
        </DialogHeader>
        <div className="grid gap-4">
          <Field label="Customer">
            <Select value={customer} onValueChange={(v) => { setCustomer(v); setPreview(null); }}>
              <SelectTrigger>
                <SelectValue placeholder="Choose a customer" />
              </SelectTrigger>
              <SelectContent className="max-h-72">
                {customers.map((c) => (
                  <SelectItem key={c.id} value={c.id}>
                    {c.name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </Field>
          <Field label="Message">
            <Textarea value={body} onChange={(e) => { setBody(e.target.value); setPreview(null); }} rows={4} maxLength={1000} />
          </Field>
          {preview && (
            <div className="rounded-xl bg-secondary px-3 py-2 text-sm">
              {preview.blockerMessage ? (
                <p className="text-destructive">{preview.blockerMessage}</p>
              ) : (
                <>
                  <p className="text-xs text-muted-foreground">
                    To {prettyPhone(preview.recipient)} · {preview.segments ?? 1} segment{(preview.segments ?? 1) === 1 ? "" : "s"} ·{" "}
                    {preview.creditsNeeded ?? preview.segments ?? 1} credit{(preview.creditsNeeded ?? 1) === 1 ? "" : "s"}
                  </p>
                  <p className="mt-1 whitespace-pre-wrap">{preview.body}</p>
                </>
              )}
            </div>
          )}
        </div>
        <DialogFooter>
          <Button variant="ghost" onClick={onClose}>
            Cancel
          </Button>
          <Button onClick={() => void act()} disabled={busy || !body.trim() || !customer} className="gap-1.5 bg-brand-orange hover:bg-brand-orange/90">
            {busy ? <Loader2 className="h-4 w-4 animate-spin" /> : <Send className="h-4 w-4" />}
            {preview && !preview.blockerMessage ? "Send text" : "Preview"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

// ---------------------------------------------------------------------------
// SMS setup (the owner registers the business and picks a number)
// ---------------------------------------------------------------------------

const emptyDetails = (name: string): SmsDetails => ({
  route: "low_volume",
  legal_name: name,
  business_type: "Limited Liability Corporation",
  ein: "",
  website: "",
  street: "",
  street2: "",
  city: "",
  state: "",
  postal_code: "",
  rep_first_name: "",
  rep_last_name: "",
  rep_title: "Owner",
  rep_email: "",
  rep_phone: "",
  opt_in_description:
    "Customers give their mobile number when they book a job by phone, in person or on our website, and agree to receive appointment and invoice texts. They can reply STOP at any time.",
  mobile_phone: "",
});

function SmsSetupPanel() {
  const ws = useWorkspace();
  const qc = useQueryClient();
  const setup = useQuery({ queryKey: ["sms", "setup"], queryFn: () => smsSetup({ action: "status" }) });
  const [busy, setBusy] = useState<string | null>(null);
  const [releasing, setReleasing] = useState(false);
  const owner = ws.me.role === "owner";
  const status = firstStatus(setup.data?.status);

  const act = async (key: string, body: Record<string, unknown>, done?: string) => {
    setBusy(key);
    try {
      const r = await smsSetup(body);
      if (r.error) toast.error(r.error);
      else if (done) toast.success(done);
      qc.setQueryData(["sms", "setup"], { ...setup.data, ...r });
      void qc.invalidateQueries({ queryKey: ["sms", "setup"] });
      return r;
    } catch (err) {
      toast.error((err as Error).message);
      return null;
    } finally {
      setBusy(null);
    }
  };

  if (setup.isLoading) return <LoadingRows count={4} />;
  if (setup.error || !status) return <p className="card-surface px-5 py-4 text-sm text-destructive">{(setup.error as Error | null)?.message ?? "SMS settings couldn't be loaded."}</p>;

  const notStarted = !status.status || status.status === "not_started" || status.status === "none" || status.status === "released";
  const tone = status.status === "active" ? "success" : status.attention ? "warning" : notStarted ? "neutral" : "info";

  return (
    <div className="grid gap-6">
      <section className="card-surface overflow-hidden">
        <div className="flex flex-wrap items-start gap-4 px-6 py-5">
          <div className="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl bg-primary-tint text-primary">
            <MessageSquare className="h-5 w-5" />
          </div>
          <div className="min-w-0 flex-1">
            <div className="flex flex-wrap items-center gap-2">
              <h2 className="text-lg font-semibold">{status.phone_number ? prettyPhone(status.phone_number) : "Business texting"}</h2>
              <ToneBadge tone={tone}>{status.friendly_status || (notStarted ? "Not set up" : status.status)}</ToneBadge>
            </div>
            {status.business_name && <p className="text-sm text-muted-foreground">{status.business_name}</p>}
            {status.attention && <p className="mt-2 text-sm text-brand-orange-text">{status.attention}</p>}
            {status.sole_prop_verification_pending && (
              <p className="mt-2 text-sm text-brand-orange-text">Reply YES to the verification text sent to the owner's mobile to finish registration.</p>
            )}
            {setup.data?.providerAvailable === false && (
              <p className="mt-2 text-sm text-muted-foreground">Texting isn't available yet. Harbour South is finishing its setup.</p>
            )}
            <div className="mt-3 flex flex-wrap gap-4 text-xs text-muted-foreground">
              {status.balance !== null && <span>{status.balance.toLocaleString("en-US")} credits</span>}
              {status.credits_per_segment && <span>{status.credits_per_segment} credit per text segment</span>}
              {status.number_fee_credits ? <span>Number: {status.number_fee_credits} credits a month</span> : null}
              {status.next_fee_due_at && <span>Next number fee {dateOnly(status.next_fee_due_at)}</span>}
            </div>
          </div>
        </div>
        {owner && !notStarted && (
          <div className="flex flex-wrap justify-end gap-2 border-t border-border bg-secondary/40 px-6 py-3">
            <Button variant="outline" size="sm" className="gap-1.5" disabled={!!busy} onClick={() => void act("refresh", { action: "refresh" }, "Status updated.")}>
              <RefreshCw className={cn("h-3.5 w-3.5", busy === "refresh" && "animate-spin")} /> Check status
            </Button>
            {status.attention && (
              <Button variant="outline" size="sm" disabled={!!busy} onClick={() => void act("retry", { action: "retry" }, "Submitted again.")}>
                Try again
              </Button>
            )}
            {status.phone_number && (
              <Button variant="ghost" size="sm" className="text-destructive" disabled={!!busy} onClick={() => setReleasing(true)}>
                Release number
              </Button>
            )}
          </div>
        )}
      </section>

      {!owner && notStarted && (
        <p className="card-surface px-5 py-4 text-sm text-muted-foreground">Only the company owner can set up business texting.</p>
      )}

      {owner && status.needs_number_choice && (
        <NumberPicker
          title="That number was taken. Choose another."
          busy={busy === "choose"}
          onChoose={(n) => void act("choose", { action: "choose_number", phoneNumber: n.phoneNumber }, "Number chosen.")}
        />
      )}

      {owner && notStarted && setup.data?.providerAvailable !== false && (
        <SetupForm status={status} busy={busy === "start"} onStart={(phoneNumber, details) => act("start", { action: "start", phoneNumber, details, acceptedTerms: true }, "Setup started. Carrier approval usually takes a few days.")} />
      )}

      <Confirm
        open={releasing}
        onOpenChange={setReleasing}
        title="Release your texting number?"
        body="Customers will no longer be able to text it and it may be given to someone else. This can't be undone."
        action="Release"
        onConfirm={() => void act("release", { action: "release" }, "Number released.")}
      />
    </div>
  );
}

function NumberPicker({ title, busy, onChoose }: { title: string; busy: boolean; onChoose: (n: AvailableNumber) => void }) {
  const [area, setArea] = useState("");
  const [numbers, setNumbers] = useState<AvailableNumber[] | null>(null);
  const [searching, setSearching] = useState(false);
  const [chosen, setChosen] = useState<string | null>(null);

  const search = async () => {
    setSearching(true);
    try {
      const r = await smsSetup({ action: "search", areaCode: area.trim() || undefined });
      if (r.error) toast.error(r.error);
      setNumbers(r.numbers ?? []);
    } catch (err) {
      toast.error((err as Error).message);
    } finally {
      setSearching(false);
    }
  };

  return (
    <Section title={title}>
      <div className="flex flex-wrap items-end gap-2 p-5">
        <Field label="Area code" className="w-40">
          <Input value={area} onChange={(e) => setArea(e.target.value.replace(/\D/g, "").slice(0, 3))} placeholder="305" inputMode="numeric" />
        </Field>
        <Button variant="outline" onClick={() => void search()} disabled={searching} className="gap-1.5">
          {searching ? <Loader2 className="h-4 w-4 animate-spin" /> : <Search className="h-4 w-4" />} Find numbers
        </Button>
      </div>
      {numbers && (
        <div className="grid gap-2 px-5 pb-5 sm:grid-cols-2 lg:grid-cols-3">
          {numbers.length === 0 && <p className="text-sm text-muted-foreground">No numbers found. Try another area code.</p>}
          {numbers.map((n) => (
            <button
              key={n.phoneNumber}
              onClick={() => {
                setChosen(n.phoneNumber);
                onChoose(n);
              }}
              disabled={busy}
              className={cn(
                "press rounded-xl border px-4 py-3 text-left transition-colors",
                chosen === n.phoneNumber ? "border-brand-orange bg-brand-orange-tint" : "border-border hover:border-primary",
              )}
            >
              <p className="font-semibold tabular-nums">{prettyPhone(n.phoneNumber)}</p>
              <p className="text-xs text-muted-foreground">{[n.locality, n.region].filter(Boolean).join(", ") || "United States"}</p>
            </button>
          ))}
        </div>
      )}
    </Section>
  );
}

function SetupForm({
  status,
  busy,
  onStart,
}: {
  status: SmsStatus;
  busy: boolean;
  onStart: (phoneNumber: string, details: SmsDetails) => Promise<unknown>;
}) {
  const ws = useWorkspace();
  const [d, setD] = useState<SmsDetails>(() => emptyDetails(ws.company.name));
  const [number, setNumber] = useState<AvailableNumber | null>(null);
  const [accepted, setAccepted] = useState(false);
  const set = (patch: Partial<SmsDetails>) => setD((x) => ({ ...x, ...patch }));
  const sole = d.route === "sole_proprietor";

  const submit = () => {
    const problem = detailsProblem(d);
    if (problem) return toast.error(problem);
    if (!number) return toast.error("Choose a number first.");
    if (!accepted) return toast.error("Please confirm you've read the SMS & Messaging Terms.");
    void onStart(number.phoneNumber, d);
  };

  return (
    <div className="grid gap-6">
      <Section title="1 · Your business">
        <div className="grid gap-4 p-5 sm:grid-cols-2">
          <div className="grid gap-2 sm:col-span-2">
            {ROUTES.map((r) => (
              <button
                key={r.id}
                onClick={() => set({ route: r.id })}
                className={cn(
                  "press rounded-xl border px-4 py-3 text-left transition-colors",
                  d.route === r.id ? "border-brand-orange bg-brand-orange-tint" : "border-border hover:border-primary",
                )}
              >
                <p className="text-sm font-semibold">{r.title}</p>
                <p className="text-xs text-muted-foreground">{r.detail}</p>
              </button>
            ))}
          </div>
          <Field label="Legal business name" className="sm:col-span-2">
            <Input value={d.legal_name} onChange={(e) => set({ legal_name: e.target.value })} />
          </Field>
          {!sole && (
            <>
              <Field label="Company structure">
                <Select value={d.business_type} onValueChange={(v) => set({ business_type: v })}>
                  <SelectTrigger>
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent>
                    {STRUCTURES.map((s) => (
                      <SelectItem key={s.id} value={s.id}>
                        {s.title}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </Field>
              <Field label="EIN">
                <Input value={d.ein} onChange={(e) => set({ ein: e.target.value })} placeholder="12-3456789" />
              </Field>
              <Field label="Website" className="sm:col-span-2" hint="Carriers check that it matches your business.">
                <Input value={d.website} onChange={(e) => set({ website: e.target.value })} placeholder="https://" />
              </Field>
            </>
          )}
          <Field label="Street address" className="sm:col-span-2">
            <Input value={d.street} onChange={(e) => set({ street: e.target.value })} />
          </Field>
          <Field label="Suite / unit (optional)">
            <Input value={d.street2} onChange={(e) => set({ street2: e.target.value })} />
          </Field>
          <Field label="City">
            <Input value={d.city} onChange={(e) => set({ city: e.target.value })} />
          </Field>
          <Field label="State">
            <Input value={d.state} maxLength={2} onChange={(e) => set({ state: e.target.value.toUpperCase() })} placeholder="FL" />
          </Field>
          <Field label="ZIP">
            <Input value={d.postal_code} onChange={(e) => set({ postal_code: e.target.value })} />
          </Field>
        </div>
      </Section>

      <Section title="2 · Authorized representative">
        <div className="grid gap-4 p-5 sm:grid-cols-2">
          <Field label="First name">
            <Input value={d.rep_first_name} onChange={(e) => set({ rep_first_name: e.target.value })} />
          </Field>
          <Field label="Last name">
            <Input value={d.rep_last_name} onChange={(e) => set({ rep_last_name: e.target.value })} />
          </Field>
          <Field label="Job title">
            <Input value={d.rep_title} onChange={(e) => set({ rep_title: e.target.value })} />
          </Field>
          <Field label="Email">
            <Input type="email" value={d.rep_email} onChange={(e) => set({ rep_email: e.target.value })} />
          </Field>
          <Field label="Phone">
            <Input value={d.rep_phone} onChange={(e) => set({ rep_phone: e.target.value })} />
          </Field>
          {sole && (
            <Field label="Owner's own mobile" hint="Receives a one-time verification text. Reply YES to it.">
              <Input value={d.mobile_phone} onChange={(e) => set({ mobile_phone: e.target.value })} />
            </Field>
          )}
          <Field label="How do customers agree to texts?" className="sm:col-span-2" hint="Carriers read this. Describe it in your own words.">
            <Textarea value={d.opt_in_description} onChange={(e) => set({ opt_in_description: e.target.value })} rows={3} />
          </Field>
        </div>
      </Section>

      <NumberPicker title="3 · Choose your texting number" busy={false} onChoose={setNumber} />

      <section className="card-surface flex flex-wrap items-center gap-4 px-5 py-4">
        <label className="flex flex-1 items-start gap-2 text-sm">
          <Checkbox checked={accepted} onCheckedChange={(v) => setAccepted(v === true)} className="mt-0.5" />
          <span>
            I've read the{" "}
            <a href={LEGAL_PATHS.sms} target="_blank" rel="noreferrer" className="font-medium text-primary underline">
              SMS &amp; Messaging Terms
            </a>{" "}
            and only text customers who agreed to it.
            {status.setup_fee_cents ? ` A one-time setup fee of ${usd(status.setup_fee_cents)} applies.` : ""}
          </span>
        </label>
        <Button onClick={submit} disabled={busy} className="press gap-1.5 bg-brand-orange hover:bg-brand-orange/90">
          {busy && <Loader2 className="h-4 w-4 animate-spin" />} Submit for approval
        </Button>
      </section>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Credits
// ---------------------------------------------------------------------------

function Credits() {
  const ws = useWorkspace();
  const qc = useQueryClient();
  const [params, setParams] = useSearchParams();
  const handled = useRef(false);
  const usage = useQuery({ queryKey: ["sms", "usage"], queryFn: smsUsage });
  const bundles = useQuery({ queryKey: ["sms", "bundles"], queryFn: smsBundles });
  const [busy, setBusy] = useState<string | null>(null);
  const canBuy = ws.can("smsCreditsPurchase");

  useEffect(() => {
    if (handled.current) return;
    const back = params.get("sms");
    if (!back) return;
    handled.current = true;
    setParams({ tab: "credits" }, { replace: true });
    if (back === "success") toast.success("Payment received. Your credits will appear in a moment.");
    else toast("Purchase cancelled. You haven't been charged.");
    const t = setTimeout(() => void qc.invalidateQueries({ queryKey: ["sms"] }), 2500);
    return () => clearTimeout(t);
  }, [params, setParams, qc]);

  const buy = async (id: string) => {
    setBusy(id);
    try {
      const { checkoutUrl } = await smsCheckout(id);
      window.location.href = checkoutUrl;
    } catch (err) {
      toast.error((err as Error).message);
      setBusy(null);
    }
  };

  const u = usage.data;
  const balance = u?.balance ?? bundles.data?.balance ?? 0;

  return (
    <div className="grid gap-6">
      <div className="grid gap-3 sm:grid-cols-4">
        <StatTile label="Credits left" value={balance.toLocaleString("en-US")} tone={balance < 50 ? "danger" : "success"} sub="1 credit ≈ 1 text segment" />
        <StatTile label="Sent (30 days)" value={String(u?.messages_sent_30d ?? 0)} sub={`${u?.segments_30d ?? 0} segments`} />
        <StatTile label="Replies (30 days)" value={String(u?.messages_received_30d ?? 0)} sub="Replies are free" />
        <StatTile label="Failed (30 days)" value={String(u?.messages_failed_30d ?? 0)} sub="Credits refunded" tone={(u?.messages_failed_30d ?? 0) > 0 ? "orange" : undefined} />
      </div>

      <Section title="Buy credits">
        {bundles.isLoading ? (
          <LoadingRows count={2} />
        ) : bundles.error ? (
          <p className="p-5 text-sm text-destructive">{(bundles.error as Error).message}</p>
        ) : !bundles.data?.configured ? (
          <p className="p-5 text-sm text-muted-foreground">Credit purchases aren't switched on yet.</p>
        ) : (
          <div className="grid gap-3 p-5 sm:grid-cols-2 lg:grid-cols-4">
            {bundles.data.bundles.map((b) => (
              <div key={b.id} className="rounded-2xl border border-border p-4">
                <p className="text-2xl font-bold tabular-nums">{b.credits.toLocaleString("en-US")}</p>
                <p className="text-xs text-muted-foreground">credits</p>
                <p className="mt-3 text-lg font-semibold">{usd(b.priceCents)}</p>
                <p className="text-xs text-meta">{((b.priceCents / b.credits) as number).toFixed(1)}¢ each</p>
                {canBuy && (
                  <Button onClick={() => void buy(b.id)} disabled={!!busy} className="press mt-3 w-full bg-brand-orange hover:bg-brand-orange/90">
                    {busy === b.id ? <Loader2 className="h-4 w-4 animate-spin" /> : "Buy"}
                  </Button>
                )}
              </div>
            ))}
          </div>
        )}
        {!canBuy && <p className="border-t border-border px-5 py-3 text-xs text-muted-foreground">Only the company owner can buy credits.</p>}
      </Section>

      {u && (
        <Section title="All-time">
          <div className="grid gap-4 p-5 text-sm sm:grid-cols-4">
            <div>
              <p className="section-label">Bought</p>
              <p className="mt-1 font-semibold tabular-nums">{u.purchased.toLocaleString("en-US")}</p>
            </div>
            <div>
              <p className="section-label">Used</p>
              <p className="mt-1 font-semibold tabular-nums">{u.used.toLocaleString("en-US")}</p>
            </div>
            <div>
              <p className="section-label">Refunded</p>
              <p className="mt-1 font-semibold tabular-nums">{u.refunded.toLocaleString("en-US")}</p>
            </div>
            <div>
              <p className="section-label">Number fees</p>
              <p className="mt-1 font-semibold tabular-nums">{u.fees.toLocaleString("en-US")}</p>
            </div>
          </div>
        </Section>
      )}
    </div>
  );
}
