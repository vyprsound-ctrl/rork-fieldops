import { useEffect, useRef, useState, type ReactNode } from "react";
import { NavLink, Navigate, useNavigate, useParams, useSearchParams } from "react-router-dom";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import {
  Bell,
  Building2,
  CreditCard,
  ExternalLink,
  FileText,
  Link2,
  Loader2,
  Mail,
  MessageSquare,
  Plug,
  ShieldAlert,
  Smartphone,
} from "lucide-react";
import { toast } from "sonner";

import { Page } from "@/components/hs/AppShell";
import { EmptyState, LoadingRows, PageHeader } from "@/components/hs/primitives";
import { Field, Section, ToneBadge } from "@/components/hs/crm";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Checkbox } from "@/components/ui/checkbox";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { cn } from "@/lib/utils";
import type { Permission, Tone, Trade } from "@/lib/domain";
import { relativeAgo } from "@/lib/format";
import { TRADE_OPTIONS } from "@/lib/signup";
import { useSession, useWorkspace } from "@/lib/session";
import {
  TERM_OPTIONS,
  companyProfile,
  connectDashboard,
  connectOnboard,
  connectStatus,
  deleteMyAccount,
  deletionContext,
  notificationLog,
  paymentsState,
  readiness,
  saveBusinessEmail,
  savePaymentLink,
  savePaymentTerms,
  saveProfile,
  termFromLabel,
  type CompanyProfile,
  type ProfileDraft,
  type Readiness,
  type TermOption,
} from "@/lib/settings";
import { firstStatus, prettyPhone, smsSetup } from "@/lib/messages";

const SECTIONS: { id: string; label: string; icon: typeof Building2; needs?: Permission }[] = [
  { id: "company", label: "Company profile", icon: Building2 },
  { id: "invoicing", label: "Invoicing", icon: FileText, needs: "invoicesRead" },
  { id: "payments", label: "Card payments", icon: CreditCard, needs: "paymentsRead" },
  { id: "notifications", label: "Notifications", icon: Bell },
  { id: "integrations", label: "Integrations", icon: Plug },
  { id: "account", label: "Your account", icon: ShieldAlert },
];

const US_ZONES = [
  ["America/New_York", "Eastern"],
  ["America/Chicago", "Central"],
  ["America/Denver", "Mountain"],
  ["America/Phoenix", "Arizona"],
  ["America/Los_Angeles", "Pacific"],
  ["America/Anchorage", "Alaska"],
  ["Pacific/Honolulu", "Hawaii"],
] as const;

const PROFILE_KEY = ["settings", "profile"] as const;

export default function Settings() {
  const ws = useWorkspace();
  const { section } = useParams();
  const sections = SECTIONS.filter((s) => !s.needs || ws.can(s.needs));
  const current = sections.find((s) => s.id === section);
  if (!current) return <Navigate to={`/settings/${sections[0].id}`} replace />;

  return (
    <Page className="max-w-[1200px]">
      <PageHeader title="Settings" subtitle={ws.company.name} />
      <div className="grid gap-6 lg:grid-cols-[220px_1fr]">
        <nav className="flex gap-1 overflow-x-auto lg:flex-col">
          {sections.map((s) => (
            <NavLink
              key={s.id}
              to={`/settings/${s.id}`}
              className={({ isActive }) =>
                cn(
                  "press flex shrink-0 items-center gap-2.5 rounded-xl px-3 py-2 text-sm font-medium transition-colors",
                  isActive ? "bg-card text-foreground shadow-sm ring-1 ring-border" : "text-muted-foreground hover:bg-secondary hover:text-foreground",
                )
              }
            >
              <s.icon className={cn("h-4 w-4", current.id === s.id && "text-brand-orange")} />
              {s.label}
            </NavLink>
          ))}
        </nav>
        <div className="min-w-0">
          {current.id === "company" && <CompanySection />}
          {current.id === "invoicing" && <InvoicingSection />}
          {current.id === "payments" && <PaymentsSection />}
          {current.id === "notifications" && <NotificationsSection />}
          {current.id === "integrations" && <IntegrationsSection />}
          {current.id === "account" && <AccountSection />}
        </div>
      </div>
    </Page>
  );
}

function useProfile() {
  const ws = useWorkspace();
  return useQuery({ queryKey: PROFILE_KEY, queryFn: () => companyProfile(ws.company.id) });
}

function ManagedNote() {
  const ws = useWorkspace();
  if (ws.can("companyProfileManage")) return null;
  return (
    <p className="mb-4 rounded-xl bg-secondary px-4 py-2.5 text-sm text-muted-foreground">
      {ws.readOnly ? "Your workspace is read-only, so these can't be changed right now." : "Only the company owner can change these."}
    </p>
  );
}

function ErrorLine({ error }: { error: unknown }) {
  return <p className="card-surface px-5 py-4 text-sm text-destructive">{(error as Error).message}</p>;
}

// ---------------------------------------------------------------------------

function CompanySection() {
  const profile = useProfile();
  if (profile.error) return <ErrorLine error={profile.error} />;
  if (!profile.data) return <LoadingRows count={4} />;
  return <CompanyForm profile={profile.data} />;
}

function CompanyForm({ profile }: { profile: CompanyProfile }) {
  const ws = useWorkspace();
  const { reload } = useSession();
  const qc = useQueryClient();
  const canEdit = ws.can("companyProfileManage");
  const [busy, setBusy] = useState(false);
  const [d, setD] = useState<ProfileDraft>(() => ({
    name: profile.name,
    trade: profile.trade,
    timeZone: profile.time_zone_identifier || "America/New_York",
    addressLine: profile.address_line ?? "",
    city: profile.city ?? "",
    state: profile.state ?? "",
    postalCode: profile.postal_code ?? "",
    phone: profile.phone ?? "",
    taxPercent: String(Math.round(Number(profile.default_tax_rate ?? 0) * 100000) / 1000),
  }));
  const set = (patch: Partial<ProfileDraft>) => setD((x) => ({ ...x, ...patch }));

  const save = async () => {
    setBusy(true);
    try {
      await saveProfile(profile.id, d);
      toast.success("Company profile saved.");
      await qc.invalidateQueries({ queryKey: PROFILE_KEY });
      if (d.name !== profile.name || d.trade !== profile.trade) reload();
    } catch (err) {
      toast.error((err as Error).message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <Section title="Company profile">
      <div className="grid gap-4 p-5 sm:grid-cols-2">
        <div className="sm:col-span-2">
          <ManagedNote />
        </div>
        <Field label="Company name" className="sm:col-span-2">
          <Input value={d.name} disabled={!canEdit} onChange={(e) => set({ name: e.target.value })} />
        </Field>
        <Field label="Trade" hint="Changes the words used for your team, like plumber or technician.">
          <Select value={d.trade} disabled={!canEdit} onValueChange={(v) => set({ trade: v as Trade })}>
            <SelectTrigger>
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {TRADE_OPTIONS.map((t) => (
                <SelectItem key={t.id} value={t.id}>
                  {t.label}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </Field>
        <Field label="Time zone">
          <Select value={d.timeZone} disabled={!canEdit} onValueChange={(v) => set({ timeZone: v })}>
            <SelectTrigger>
              <SelectValue />
            </SelectTrigger>
            <SelectContent>
              {US_ZONES.map(([id, label]) => (
                <SelectItem key={id} value={id}>
                  {label} ({id})
                </SelectItem>
              ))}
              {!US_ZONES.some(([id]) => id === d.timeZone) && <SelectItem value={d.timeZone}>{d.timeZone}</SelectItem>}
            </SelectContent>
          </Select>
        </Field>
        <Field label="Street address" className="sm:col-span-2">
          <Input value={d.addressLine} disabled={!canEdit} onChange={(e) => set({ addressLine: e.target.value })} />
        </Field>
        <Field label="City">
          <Input value={d.city} disabled={!canEdit} onChange={(e) => set({ city: e.target.value })} />
        </Field>
        <div className="grid grid-cols-2 gap-4">
          <Field label="State">
            <Input value={d.state} maxLength={2} disabled={!canEdit} onChange={(e) => set({ state: e.target.value.toUpperCase() })} placeholder="FL" />
          </Field>
          <Field label="ZIP">
            <Input value={d.postalCode} disabled={!canEdit} onChange={(e) => set({ postalCode: e.target.value })} />
          </Field>
        </div>
        <Field label="Phone">
          <Input value={d.phone} disabled={!canEdit} onChange={(e) => set({ phone: e.target.value })} />
        </Field>
        <Field label="Default sales tax (%)" hint="Used on new quote and invoice lines.">
          <Input
            value={d.taxPercent}
            inputMode="decimal"
            disabled={!canEdit}
            onChange={(e) => set({ taxPercent: e.target.value.replace(/[^0-9.]/g, "") })}
          />
        </Field>
        <p className="text-xs text-muted-foreground sm:col-span-2">Country: United States · Currency: USD</p>
      </div>
      {canEdit && (
        <div className="flex justify-end border-t border-border px-5 py-3">
          <Button onClick={() => void save()} disabled={busy} className="press bg-brand-orange hover:bg-brand-orange/90">
            {busy ? "Saving…" : "Save changes"}
          </Button>
        </div>
      )}
    </Section>
  );
}

// ---------------------------------------------------------------------------

function InvoicingSection() {
  const profile = useProfile();
  if (profile.error) return <ErrorLine error={profile.error} />;
  if (!profile.data) return <LoadingRows count={4} />;
  return <InvoicingForms profile={profile.data} />;
}

function InvoicingForms({ profile }: { profile: CompanyProfile }) {
  const ws = useWorkspace();
  const qc = useQueryClient();
  const canEdit = ws.can("companyProfileManage");
  const [term, setTerm] = useState<TermOption>(() => termFromLabel(profile.default_payment_terms_label));
  const [customDays, setCustomDays] = useState(String(profile.default_payment_terms_days ?? 30));
  const [email, setEmail] = useState(profile.business_email ?? "");
  const [link, setLink] = useState(profile.online_payment_link_url ?? "");
  const [busy, setBusy] = useState<string | null>(null);

  const run = async (key: string, work: () => Promise<unknown>, done: string) => {
    setBusy(key);
    try {
      await work();
      toast.success(done);
      await qc.invalidateQueries({ queryKey: PROFILE_KEY });
    } catch (err) {
      toast.error((err as Error).message);
    } finally {
      setBusy(null);
    }
  };

  return (
    <div className="grid gap-6">
      <ManagedNote />
      <Section title="Payment terms">
        <div className="grid gap-4 p-5 sm:grid-cols-2">
          <Field label="Default terms for new invoices" hint={`Currently: ${profile.default_payment_terms_label || "Due in 30 days"}`}>
            <Select value={term} disabled={!canEdit} onValueChange={(v) => setTerm(v as TermOption)}>
              <SelectTrigger>
                <SelectValue />
              </SelectTrigger>
              <SelectContent>
                {TERM_OPTIONS.map((o) => (
                  <SelectItem key={o.id} value={o.id}>
                    {o.label}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </Field>
          {term === "custom" && (
            <Field label="Days until due">
              <Input value={customDays} inputMode="numeric" disabled={!canEdit} onChange={(e) => setCustomDays(e.target.value.replace(/\D/g, ""))} />
            </Field>
          )}
        </div>
        {canEdit && (
          <div className="flex justify-end border-t border-border px-5 py-3">
            <Button
              onClick={() => void run("terms", () => savePaymentTerms(profile.id, term, Number(customDays)), "Payment terms saved.")}
              disabled={busy === "terms"}
            >
              Save terms
            </Button>
          </div>
        )}
      </Section>

      <Section title="Business email">
        <div className="grid gap-2 p-5">
          <Field
            label="Reply-to address on invoices and quotes"
            hint="Customers who reply to an emailed invoice reach this address. Leave empty to use your account email."
          >
            <Input type="email" value={email} disabled={!canEdit} onChange={(e) => setEmail(e.target.value)} placeholder="invoices@yourbusiness.com" />
          </Field>
        </div>
        {canEdit && (
          <div className="flex justify-end border-t border-border px-5 py-3">
            <Button onClick={() => void run("email", () => saveBusinessEmail(profile.id, email), "Business email saved.")} disabled={busy === "email"}>
              Save email
            </Button>
          </div>
        )}
      </Section>

      <Section title="Your own payment link">
        <div className="grid gap-2 p-5">
          <Field
            label="Payment page address"
            hint="Optional. If you already take payments elsewhere (Square, PayPal, your bank), invoices can show this link. Card payments through Harbour South are set up under Card payments."
          >
            <Input value={link} disabled={!canEdit} onChange={(e) => setLink(e.target.value)} placeholder="https://" />
          </Field>
        </div>
        {canEdit && (
          <div className="flex justify-end border-t border-border px-5 py-3">
            <Button onClick={() => void run("link", () => savePaymentLink(profile.id, link), "Payment link saved.")} disabled={busy === "link"}>
              Save link
            </Button>
          </div>
        )}
      </Section>
    </div>
  );
}

// ---------------------------------------------------------------------------

const READINESS: Record<Readiness, { title: string; tone: Tone; body: string }> = {
  notConfigured: { title: "Unavailable", tone: "neutral", body: "Card payments aren't switched on for Harbour South yet." },
  notConnected: { title: "Not set up", tone: "neutral", body: "Connect a Stripe account so customers can pay invoices by card." },
  pending: { title: "Finishing setup", tone: "warning", body: "Stripe still needs a few details before you can take card payments." },
  restricted: { title: "Action needed", tone: "danger", body: "Stripe has paused card payments on your account until details are updated." },
  ready: { title: "Taking card payments", tone: "success", body: "Customers can pay your invoices by card. Money goes to your bank through Stripe." },
};

function PaymentsSection() {
  const ws = useWorkspace();
  const qc = useQueryClient();
  const [params, setParams] = useSearchParams();
  const handled = useRef(false);
  const [busy, setBusy] = useState<string | null>(null);
  const status = useQuery({ queryKey: ["settings", "connect"], queryFn: connectStatus });
  const state = useQuery({ queryKey: ["settings", "payments-state"], queryFn: paymentsState });
  const canManage = ws.can("companyProfileManage");

  useEffect(() => {
    if (handled.current) return;
    const back = params.get("stripe");
    if (!back) return;
    handled.current = true;
    setParams({}, { replace: true });
    if (back === "refresh") toast("That Stripe link expired. Continue setup to get a fresh one.");
    else toast.success("Back from Stripe. Checking your account…");
    void qc.invalidateQueries({ queryKey: ["settings", "connect"] });
  }, [params, setParams, qc]);

  const go = async (key: string, work: () => Promise<{ url: string }>) => {
    setBusy(key);
    try {
      const { url } = await work();
      window.location.href = url;
    } catch (err) {
      toast.error((err as Error).message);
      setBusy(null);
    }
  };

  if (status.error) return <ErrorLine error={status.error} />;
  if (status.isLoading) return <LoadingRows count={3} />;
  const s = status.data;
  const r = readiness(s);
  const info = READINESS[r];
  const bps = state.data?.platform_fee_bps;
  const due = s?.requirementsDue ?? [];

  return (
    <div className="grid gap-6">
      <section className="card-surface overflow-hidden">
        <div className="flex items-start gap-4 px-6 py-5">
          <div className="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl bg-primary-tint text-primary">
            <CreditCard className="h-5 w-5" />
          </div>
          <div className="min-w-0 flex-1">
            <div className="flex flex-wrap items-center gap-2">
              <h2 className="text-lg font-semibold">Card payments</h2>
              <ToneBadge tone={info.tone}>{info.title}</ToneBadge>
            </div>
            <p className="mt-1 text-sm text-muted-foreground">{info.body}</p>
            {s?.connected && (
              <div className="mt-3 flex flex-wrap gap-2 text-xs">
                <ToneBadge tone={s.chargesEnabled ? "success" : "neutral"}>{s.chargesEnabled ? "Charges on" : "Charges off"}</ToneBadge>
                <ToneBadge tone={s.payoutsEnabled ? "success" : "neutral"}>{s.payoutsEnabled ? "Payouts on" : "Payouts off"}</ToneBadge>
                <ToneBadge tone={s.detailsSubmitted ? "success" : "warning"}>{s.detailsSubmitted ? "Details submitted" : "Details needed"}</ToneBadge>
              </div>
            )}
            {due.length > 0 && <p className="mt-3 text-sm text-brand-orange-text">Stripe is asking for {due.length} more detail{due.length === 1 ? "" : "s"}.</p>}
          </div>
        </div>
        {r !== "notConfigured" && (
          <div className="flex flex-wrap items-center justify-end gap-2 border-t border-border bg-secondary/40 px-6 py-3">
            {!canManage && <p className="mr-auto text-xs text-muted-foreground">Only the company owner can change card payments.</p>}
            {canManage && r !== "ready" && (
              <Button onClick={() => void go("onboard", () => connectOnboard())} disabled={!!busy} className="press gap-1.5 bg-brand-orange hover:bg-brand-orange/90">
                {busy === "onboard" ? <Loader2 className="h-4 w-4 animate-spin" /> : <ExternalLink className="h-4 w-4" />}
                {r === "notConnected" ? "Set up with Stripe" : "Continue setup"}
              </Button>
            )}
            {canManage && s?.connected && (
              <Button variant="outline" onClick={() => void go("dash", connectDashboard)} disabled={!!busy} className="gap-1.5">
                {busy === "dash" ? <Loader2 className="h-4 w-4 animate-spin" /> : <ExternalLink className="h-4 w-4" />}
                Open Stripe dashboard
              </Button>
            )}
          </div>
        )}
      </section>

      <Section title="How it works">
        <ul className="grid gap-3 p-5 text-sm text-muted-foreground">
          <li>Customers pay from the invoice link you send by email or text. Payments are recorded on the invoice automatically.</li>
          <li>Stripe pays out to your bank account on its usual schedule. Stripe's own card processing fees apply.</li>
          {typeof bps === "number" && bps > 0 && (
            <li>
              Harbour South adds a {(bps / 100).toLocaleString("en-US", { maximumFractionDigits: 2 })}% platform fee on each card payment, taken
              automatically by Stripe.
            </li>
          )}
          <li>Cash, check and bank transfers can still be recorded by hand on any invoice.</li>
        </ul>
      </Section>
    </div>
  );
}

// ---------------------------------------------------------------------------

const CHANNEL_TITLE = { sms: "Text", email: "Email", push: "Push" } as const;
const NOTE_TONE: Record<string, Tone> = { queued: "info", sent: "info", delivered: "success", failed: "danger" };

function templateTitle(t: string) {
  return t
    .replace(/_/g, " ")
    .replace(/([a-z])([A-Z])/g, "$1 $2")
    .replace(/^./, (c) => c.toUpperCase());
}

function NotificationsSection() {
  const log = useQuery({ queryKey: ["settings", "notifications"], queryFn: notificationLog });
  const [channel, setChannel] = useState<"all" | "sms" | "email" | "push">("all");
  const list = (log.data ?? []).filter((n) => channel === "all" || n.channel === channel);
  return (
    <Section
      title="Messages sent to customers and your team"
      action={
        <div className="flex gap-1">
          {(["all", "email", "sms", "push"] as const).map((c) => (
            <button
              key={c}
              onClick={() => setChannel(c)}
              className={cn(
                "press rounded-full px-2.5 py-1 text-xs font-medium",
                channel === c ? "bg-brand-orange text-white" : "text-muted-foreground hover:bg-secondary",
              )}
            >
              {c === "all" ? "All" : CHANNEL_TITLE[c]}
            </button>
          ))}
        </div>
      }
    >
      {log.isLoading ? (
        <LoadingRows count={6} />
      ) : log.error ? (
        <p className="p-5 text-sm text-destructive">{(log.error as Error).message}</p>
      ) : list.length === 0 ? (
        <EmptyState icon={Bell} title="Nothing sent yet" body="Invoice emails, appointment texts and alerts appear here once they go out." />
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full min-w-[720px] text-sm">
            <thead className="bg-secondary/50">
              <tr className="text-left">
                <th className="section-label w-20 px-4 py-3">Type</th>
                <th className="section-label px-4 py-3">Message</th>
                <th className="section-label px-4 py-3">To</th>
                <th className="section-label w-28 px-4 py-3">Status</th>
                <th className="section-label w-32 px-4 py-3">When</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-border">
              {list.map((n) => (
                <tr key={n.id}>
                  <td className="px-4 py-3 text-muted-foreground">{CHANNEL_TITLE[n.channel] ?? n.channel}</td>
                  <td className="px-4 py-3">
                    <p className="font-medium">{n.title || templateTitle(n.template)}</p>
                    {n.failure_reason && <p className="text-xs text-destructive">{n.failure_reason}</p>}
                  </td>
                  <td className="max-w-[220px] truncate px-4 py-3 text-muted-foreground">{n.channel === "sms" ? prettyPhone(n.recipient) : n.recipient}</td>
                  <td className="px-4 py-3">
                    <ToneBadge tone={NOTE_TONE[n.status] ?? "neutral"}>{n.status[0].toUpperCase() + n.status.slice(1)}</ToneBadge>
                  </td>
                  <td className="px-4 py-3 text-muted-foreground">{relativeAgo(n.sent_at ?? n.created_at)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </Section>
  );
}

// ---------------------------------------------------------------------------

function IntegrationsSection() {
  const ws = useWorkspace();
  const navigate = useNavigate();
  const profile = useProfile();
  const connect = useQuery({ queryKey: ["settings", "connect"], queryFn: connectStatus, enabled: ws.can("paymentsRead") });
  const smsAllowed = ws.can("smsLedgerRead") || ws.can("smsCreditsConsume");
  const sms = useQuery({ queryKey: ["sms", "setup"], queryFn: () => smsSetup({ action: "status" }), enabled: smsAllowed });
  const smsStatus = firstStatus(sms.data?.status);
  const r = readiness(connect.data);

  const items: { icon: typeof Mail; title: string; body: string; tone: Tone; state: string; action?: ReactNode; show: boolean }[] = [
    {
      icon: CreditCard,
      title: "Stripe card payments",
      body: "Customers pay invoices by card. Payments are recorded on the invoice.",
      tone: READINESS[r].tone,
      state: connect.isLoading ? "Checking…" : READINESS[r].title,
      action: (
        <Button variant="outline" size="sm" onClick={() => navigate("/settings/payments")}>
          Manage
        </Button>
      ),
      show: ws.can("paymentsRead"),
    },
    {
      icon: MessageSquare,
      title: "Customer text messages",
      body: smsStatus?.phone_number
        ? `Texts go out from ${prettyPhone(smsStatus.phone_number)}.`
        : "Send appointment reminders, on-the-way texts and invoices by SMS from your own number.",
      tone: smsStatus?.status === "active" ? "success" : smsStatus?.attention ? "warning" : "neutral",
      state: sms.isLoading ? "Checking…" : smsStatus?.friendly_status || (smsStatus?.status === "active" ? "Active" : "Not set up"),
      action: (
        <Button variant="outline" size="sm" onClick={() => navigate("/messages?tab=setup")}>
          Manage
        </Button>
      ),
      show: smsAllowed,
    },
    {
      icon: Mail,
      title: "Business email",
      body: profile.data?.business_email ? `Replies go to ${profile.data.business_email}.` : "Replies to emailed invoices go to your account email.",
      tone: profile.data?.business_email ? "success" : "neutral",
      state: profile.data?.business_email ? "Set" : "Not set",
      action: (
        <Button variant="outline" size="sm" onClick={() => navigate("/settings/invoicing")}>
          Change
        </Button>
      ),
      show: ws.can("invoicesRead"),
    },
    {
      icon: Link2,
      title: "Your own payment link",
      body: profile.data?.online_payment_link_url ?? "Optional link to a payment page you already use.",
      tone: profile.data?.online_payment_link_url ? "success" : "neutral",
      state: profile.data?.online_payment_link_url ? "Set" : "Not set",
      action: (
        <Button variant="outline" size="sm" onClick={() => navigate("/settings/invoicing")}>
          Change
        </Button>
      ),
      show: ws.can("invoicesRead"),
    },
    {
      icon: Smartphone,
      title: "Harbour South iPhone app",
      body: "Your field team uses the iPhone app with the same logins. Jobs, notes and photos sync both ways.",
      tone: "success",
      state: "Connected",
      show: true,
    },
  ];

  return (
    <Section title="Integrations">
      <ul className="divide-y divide-border">
        {items
          .filter((i) => i.show)
          .map((i) => (
            <li key={i.title} className="flex flex-wrap items-center gap-4 px-5 py-4">
              <div className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl bg-primary-tint text-primary">
                <i.icon className="h-5 w-5" />
              </div>
              <div className="min-w-0 flex-1">
                <div className="flex flex-wrap items-center gap-2">
                  <p className="font-semibold">{i.title}</p>
                  <ToneBadge tone={i.tone}>{i.state}</ToneBadge>
                </div>
                <p className="mt-0.5 truncate text-sm text-muted-foreground">{i.body}</p>
              </div>
              {i.action}
            </li>
          ))}
      </ul>
    </Section>
  );
}

// ---------------------------------------------------------------------------

function AccountSection() {
  const ws = useWorkspace();
  const { signOut } = useSession();
  const ctx = useQuery({ queryKey: ["settings", "deletion"], queryFn: deletionContext });
  const [open, setOpen] = useState(false);
  const [confirmText, setConfirmText] = useState("");
  const [closeCompany, setCloseCompany] = useState(false);
  const [busy, setBusy] = useState(false);
  const c = ctx.data;
  const mustClose = !!c?.is_sole_owner && (c?.other_active_members ?? 0) === 0;
  const blocked = !!c?.is_sole_owner && (c?.other_active_members ?? 0) > 0 && !closeCompany;

  const remove = async () => {
    setBusy(true);
    try {
      await deleteMyAccount(mustClose || closeCompany);
      toast.success("Your account has been deleted.");
      await signOut();
    } catch (err) {
      toast.error((err as Error).message);
      setBusy(false);
    }
  };

  return (
    <div className="grid gap-6">
      <Section title="Signed in as">
        <div className="px-5 py-4 text-sm">
          <p className="font-semibold">{ws.me.name}</p>
          <p className="text-muted-foreground">{ws.me.email}</p>
          <p className="mt-3 text-xs text-muted-foreground">
            To change your password, sign out and choose "Forgot password" on the sign-in page.
          </p>
        </div>
      </Section>

      <section className="card-surface overflow-hidden ring-1 ring-destructive/20">
        <div className="px-5 py-4">
          <h2 className="font-semibold text-destructive">Delete your account</h2>
          <p className="mt-1 text-sm text-muted-foreground">
            Permanently deletes your login and personal details. This can't be undone. Jobs and invoices you worked on stay with the company.
          </p>
          {c?.is_sole_owner && (
            <p className="mt-2 text-sm text-brand-orange-text">
              You're the only owner of {c.company_name}.{" "}
              {(c.other_active_members ?? 0) > 0
                ? `${c.other_active_members} other people still use it. To delete your account you'll need to close the company for everyone.`
                : "Deleting your account also closes the company."}
            </p>
          )}
        </div>
        <div className="flex justify-end border-t border-border bg-secondary/40 px-5 py-3">
          <Button variant="destructive" onClick={() => setOpen(true)} disabled={ctx.isLoading}>
            Delete my account
          </Button>
        </div>
      </section>

      <Dialog open={open} onOpenChange={(o) => !busy && setOpen(o)}>
        <DialogContent className="sm:max-w-[460px]">
          <DialogHeader>
            <DialogTitle>Delete your account?</DialogTitle>
            <DialogDescription>
              This permanently removes your Harbour South login on the web and the iPhone app. App Store subscriptions are managed in your Apple ID settings.
            </DialogDescription>
          </DialogHeader>
          {c?.is_sole_owner && (c?.other_active_members ?? 0) > 0 && (
            <label className="flex items-start gap-2 text-sm">
              <Checkbox checked={closeCompany} onCheckedChange={(v) => setCloseCompany(v === true)} className="mt-0.5" />
              Close {c.company_name} for everyone ({c.other_active_members} other people lose access)
            </label>
          )}
          <Field label='Type DELETE to confirm'>
            <Input value={confirmText} onChange={(e) => setConfirmText(e.target.value)} autoComplete="off" />
          </Field>
          <DialogFooter>
            <Button variant="ghost" onClick={() => setOpen(false)} disabled={busy}>
              Cancel
            </Button>
            <Button variant="destructive" disabled={busy || confirmText.trim() !== "DELETE" || blocked} onClick={() => void remove()}>
              {busy ? "Deleting…" : "Delete permanently"}
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  );
}
