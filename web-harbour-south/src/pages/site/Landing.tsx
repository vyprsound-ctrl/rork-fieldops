import { useState } from "react";
import {
  BadgeCheck,
  CalendarDays,
  Camera,
  Check,
  ClipboardList,
  CreditCard,
  FileText,
  LayoutDashboard,
  MapPin,
  MessageSquare,
  MessagesSquare,
  Monitor,
  Navigation,
  ShieldCheck,
  Smartphone,
  Users,
} from "lucide-react";

import { cn } from "@/lib/utils";
import { Accordion, AccordionContent, AccordionItem, AccordionTrigger } from "@/components/ui/accordion";
import { APP_STORE_URL, LEGAL_PATHS } from "@/lib/site";
import { AppStoreButton, SitePage, loginHref, usePageTitle } from "./SiteChrome";

/* ------------------------------------------------------------------ */
/* Plans — the same list prices as the App Store (PlanCatalog / 0013). */
/* ------------------------------------------------------------------ */

type Period = "monthly" | "annual";

const PLANS = [
  { id: "starter", name: "Starter", tagline: "Just me", users: "1 user", monthly: 1999, annual: 19199 },
  { id: "team", name: "Team", tagline: "My small team", users: "Up to 5 users", monthly: 3999, annual: 38499, highlight: true },
  { id: "business", name: "Business", tagline: "My business, 10+ people", users: "10+ users", monthly: 6999, annual: 66999 },
] as const;

const usd = (cents: number) =>
  new Intl.NumberFormat("en-US", { style: "currency", currency: "USD", minimumFractionDigits: 2 }).format(cents / 100);

const savingPct = (monthly: number, annual: number) => Math.round((1 - annual / (monthly * 12)) * 100);

const INCLUDED = [
  "Jobs, scheduling and dispatch",
  "Day, week and month calendar",
  "Live engineer map",
  "Quotes and invoices",
  "Card payments through your own Stripe account",
  "Photos, signatures and job notes",
  "Office ↔ engineer messaging",
  "Customer texting with a dedicated number*",
  "Roles and permissions",
  "iPhone app and office web app",
];

/* ------------------------------------------------------------------ */

export default function Landing() {
  usePageTitle("Harbour South FieldOps — Field service software for trade businesses");

  return (
    <SitePage>
      <Hero />
      <Trades />
      <Features />
      <HowItWorks />
      <Pricing />
      <Faq />
      <FinalCta />
    </SitePage>
  );
}

/* ------------------------------- Hero ------------------------------- */

function Hero() {
  return (
    <section className="relative -mt-16 overflow-hidden bg-brand-navy pt-16 text-white">
      {/* Harbour arch, echoing the logo */}
      <div className="pointer-events-none absolute -right-72 top-[58%] h-[820px] w-[820px] rounded-full border-[56px] border-brand-orange/90" />
      <div className="pointer-events-none absolute -right-20 top-[52%] h-[560px] w-[560px] rounded-full border border-white/10" />
      <div className="pointer-events-none absolute inset-0 bg-[radial-gradient(circle_at_15%_0%,hsl(225_72%_38%/0.6),transparent_55%)]" />
      <div className="pointer-events-none absolute inset-0 opacity-[0.07] [background-image:linear-gradient(white_1px,transparent_1px),linear-gradient(90deg,white_1px,transparent_1px)] [background-size:56px_56px] [mask-image:linear-gradient(to_bottom,black,transparent_80%)]" />

      <div className="relative mx-auto grid max-w-6xl items-center gap-14 px-5 pb-24 pt-16 lg:grid-cols-[1fr_1.05fr] lg:pb-32 lg:pt-24">
        <div className="animate-in fade-in slide-in-from-bottom-4 duration-700">
          <span className="inline-flex items-center gap-2 rounded-full border border-white/15 bg-white/5 px-3 py-1 text-xs font-semibold uppercase tracking-[0.14em] text-white/80">
            <span className="h-1.5 w-1.5 rounded-full bg-brand-orange" />
            Field service software for the trades
          </span>
          <h1 className="mt-6 text-[44px] font-bold leading-[1.02] tracking-tight sm:text-[56px]">
            Every job, every engineer, <span className="text-brand-orange">every invoice.</span>
          </h1>
          <p className="mt-6 max-w-lg text-lg leading-relaxed text-white/70">
            Harbour South FieldOps runs your trade business from the first call to the paid invoice — an iPhone app for your
            engineers and a web app for your office, working from the same live schedule.
          </p>
          <div className="mt-9 flex flex-wrap items-center gap-3">
            <AppStoreButton className="bg-white text-black hover:bg-white/90 [&_svg]:text-black" />
            <a href="#pricing" className="press rounded-xl border border-white/20 px-5 py-3 text-[15px] font-semibold text-white transition-colors hover:bg-white/10">
              See pricing
            </a>
          </div>
          <p className="mt-5 text-sm text-white/50">Start with a 14-day free trial · Cancel any time in the App Store</p>
        </div>

        <HeroVisual />
      </div>
    </section>
  );
}

const MOCK_ROWS = [
  { name: "Marcus Reid", initials: "MR", color: "bg-[hsl(225_72%_38%)]", jobs: [{ left: 4, width: 26, label: "AC service", tone: "blue" }, { left: 40, width: 30, label: "Boiler repair", tone: "orange" }] },
  { name: "Dana Ortiz", initials: "DO", color: "bg-[hsl(147_81%_31%)]", jobs: [{ left: 14, width: 34, label: "Heat pump install", tone: "green" }, { left: 62, width: 22, label: "Leak check", tone: "blue" }] },
  { name: "Sam Patel", initials: "SP", color: "bg-[hsl(24_79%_49%)]", jobs: [{ left: 0, width: 20, label: "Panel upgrade", tone: "green" }, { left: 28, width: 24, label: "Rewire", tone: "amber" }, { left: 70, width: 24, label: "Quote visit", tone: "blue" }] },
] as const;

const TONE: Record<string, string> = {
  blue: "bg-primary-tint text-primary border-primary/20",
  orange: "bg-brand-orange-tint text-brand-orange-text border-brand-orange/30",
  green: "bg-[hsl(147_60%_94%)] text-success border-success/20",
  amber: "bg-[hsl(40_100%_94%)] text-warning border-warning/25",
};

function HeroVisual() {
  return (
    <div className="relative animate-in fade-in slide-in-from-bottom-6 duration-1000">
      {/* Office web app */}
      <div className="overflow-hidden rounded-2xl border border-white/15 bg-white text-foreground shadow-[0_40px_80px_-20px_rgba(0,0,0,0.55)]">
        <div className="flex items-center gap-1.5 border-b border-border bg-secondary/70 px-4 py-2.5">
          <span className="h-2.5 w-2.5 rounded-full bg-[#FF5F57]" />
          <span className="h-2.5 w-2.5 rounded-full bg-[#FEBC2E]" />
          <span className="h-2.5 w-2.5 rounded-full bg-[#28C840]" />
          <span className="ml-3 rounded-md bg-white px-3 py-0.5 text-[11px] text-meta">Dispatch · Today</span>
        </div>
        <div className="flex">
          <div className="hidden w-14 flex-col items-center gap-3 bg-brand-navy py-4 sm:flex">
            {[LayoutDashboard, ClipboardList, Navigation, CalendarDays, MapPin].map((I, i) => (
              <span key={i} className={cn("flex h-8 w-8 items-center justify-center rounded-lg", i === 2 ? "bg-brand-orange text-white" : "text-white/50")}>
                <I className="h-4 w-4" />
              </span>
            ))}
          </div>
          <div className="flex-1 p-4">
            <div className="mb-3 flex justify-between pl-[92px] text-[10px] font-medium text-meta">
              {["8am", "10am", "12pm", "2pm", "4pm"].map((t) => (
                <span key={t}>{t}</span>
              ))}
            </div>
            <div className="space-y-2.5">
              {MOCK_ROWS.map((r) => (
                <div key={r.name} className="flex items-center gap-3">
                  <div className="flex w-20 shrink-0 items-center gap-2">
                    <span className={cn("flex h-6 w-6 items-center justify-center rounded-full text-[9px] font-bold text-white", r.color)}>{r.initials}</span>
                    <span className="truncate text-[11px] font-semibold">{r.name.split(" ")[0]}</span>
                  </div>
                  <div className="relative h-9 flex-1 rounded-lg bg-secondary/80">
                    {r.jobs.map((j) => (
                      <div
                        key={j.label}
                        className={cn("absolute inset-y-1 flex items-center rounded-md border px-2 text-[10px] font-semibold", TONE[j.tone])}
                        style={{ left: `${j.left}%`, width: `${j.width}%` }}
                      >
                        <span className="truncate">{j.label}</span>
                      </div>
                    ))}
                  </div>
                </div>
              ))}
            </div>
            <div className="mt-3 flex items-center gap-2 rounded-lg border border-dashed border-border px-3 py-2 text-[11px] text-muted-foreground">
              <span className="rounded bg-brand-orange-tint px-1.5 py-0.5 text-[10px] font-bold text-brand-orange-text">2 unassigned</span>
              Drag onto a row to dispatch
            </div>
          </div>
        </div>
      </div>

      {/* iPhone */}
      <div className="absolute -bottom-24 -left-4 w-[190px] lg:-left-20 rounded-[34px] border-[6px] border-[#0b1220] bg-[#0b1220] shadow-[0_30px_60px_-15px_rgba(0,0,0,0.6)] sm:-left-10 sm:w-[210px]">
        <div className="overflow-hidden rounded-[28px] bg-background">
          <div className="flex justify-center pt-2">
            <span className="h-[18px] w-[70px] rounded-full bg-[#0b1220]" />
          </div>
          <div className="px-3 pb-4 pt-3">
            <p className="text-[9px] font-semibold uppercase tracking-[0.12em] text-meta">Next job · 10:30</p>
            <p className="mt-1 text-[14px] font-bold leading-tight">Boiler repair</p>
            <p className="text-[10px] text-muted-foreground">14 Harbor View Rd</p>
            <div className="mt-3 h-16 overflow-hidden rounded-xl bg-[linear-gradient(135deg,hsl(220_43%_93%),hsl(220_43%_88%))]">
              <svg viewBox="0 0 160 64" className="h-full w-full">
                <path d="M10 50 C40 50 50 18 85 22 S130 40 150 12" stroke="hsl(225 72% 38%)" strokeWidth="3" fill="none" strokeLinecap="round" strokeDasharray="1 7" />
                <circle cx="150" cy="12" r="5" fill="hsl(24 79% 49%)" />
                <circle cx="10" cy="50" r="4" fill="hsl(225 72% 38%)" />
              </svg>
            </div>
            <div className="mt-3 grid grid-cols-3 gap-1.5">
              {["En route", "Arrived", "Done"].map((s, i) => (
                <span key={s} className={cn("rounded-md py-1 text-center text-[9px] font-semibold", i === 0 ? "bg-brand-orange text-white" : "bg-secondary text-muted-foreground")}>
                  {s}
                </span>
              ))}
            </div>
            <div className="mt-2.5 flex items-center gap-1.5 rounded-lg bg-[hsl(147_60%_94%)] px-2 py-1.5 text-[9px] font-semibold text-success">
              <MessageSquare className="h-3 w-3" /> Customer texted: on my way
            </div>
          </div>
        </div>
      </div>

      {/* Floating paid chip */}
      <div className="absolute -right-2 -top-5 hidden items-center gap-2 rounded-xl bg-white px-3 py-2 text-foreground shadow-xl sm:flex">
        <span className="flex h-7 w-7 items-center justify-center rounded-full bg-[hsl(147_60%_94%)]">
          <Check className="h-4 w-4 text-success" />
        </span>
        <div className="leading-tight">
          <p className="text-[10px] text-meta">Invoice INV-1042</p>
          <p className="text-[12px] font-bold">Paid by card · $480.00</p>
        </div>
      </div>
    </div>
  );
}

/* ------------------------------ Trades ------------------------------ */

function Trades() {
  return (
    <section className="border-b border-border bg-white">
      <div className="mx-auto flex max-w-6xl flex-wrap items-center justify-center gap-x-10 gap-y-3 px-5 pb-8 pt-24 text-sm font-semibold text-muted-foreground lg:pt-20">
        <span className="section-label">Built for</span>
        {["HVAC", "Plumbing", "Electrical", "and other trades"].map((t) => (
          <span key={t}>{t}</span>
        ))}
      </div>
    </section>
  );
}

/* ----------------------------- Features ----------------------------- */

const FEATURES = [
  { icon: ClipboardList, title: "Jobs from call to completion", body: "Create jobs, track every status from scheduled to complete, and keep notes, equipment and history in one record." },
  { icon: Navigation, title: "Dispatch board", body: "See your engineers' days side by side. Drag a job to assign or reschedule, with a warning before you double-book anyone." },
  { icon: MapPin, title: "Live engineer map", body: "Know who's travelling and who's on site. Location is shared only while an engineer is on the way to a job." },
  { icon: FileText, title: "Quotes and invoices", body: "Send professional quotes, turn them into jobs, invoice when the work is done and see what's owed at a glance." },
  { icon: CreditCard, title: "Get paid by card", body: "Customers pay invoices online into your own Stripe account. Payments are matched to the invoice automatically." },
  { icon: MessageSquare, title: "Text your customers", body: "A dedicated US number for your business. Send on-my-way and appointment texts and see replies in one place." },
  { icon: Camera, title: "Photos and signatures", body: "Engineers capture before-and-after photos and customer signatures on site, attached straight to the job." },
  { icon: MessagesSquare, title: "Office ↔ engineer chat", body: "Message your team with text and photos, without mixing work into personal group chats." },
  { icon: ShieldCheck, title: "Roles and permissions", body: "Owner, Admin, Dispatcher, Engineer and Accounts — everyone sees exactly what their job needs." },
] as const;

function Features() {
  return (
    <section id="features" className="scroll-mt-16 bg-background py-24">
      <div className="mx-auto max-w-6xl px-5">
        <SectionHeading
          eyebrow="Features"
          title="Everything between the phone ringing and the money landing."
          body="One system for scheduling, the work itself and getting paid — so nothing lives on whiteboards, spreadsheets or sticky notes."
        />
        <div className="mt-14 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {FEATURES.map(({ icon: Icon, title, body }, i) => (
            <div
              key={title}
              className={cn(
                "group card-surface p-6 transition-all duration-200 hover:-translate-y-0.5 hover:shadow-[0_18px_40px_-20px_rgba(10,36,71,0.35)]",
                i === 1 && "lg:row-span-1",
              )}
            >
              <span
                className={cn(
                  "flex h-11 w-11 items-center justify-center rounded-xl transition-colors",
                  i % 3 === 1 ? "bg-brand-orange-tint text-brand-orange-text" : "bg-primary-tint text-primary",
                )}
              >
                <Icon className="h-5 w-5" />
              </span>
              <h3 className="mt-5 text-[17px] font-bold tracking-tight">{title}</h3>
              <p className="mt-2 text-[15px] leading-relaxed text-muted-foreground">{body}</p>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}

/* --------------------------- How it works --------------------------- */

function HowItWorks() {
  const steps = [
    {
      icon: Monitor,
      who: "The office",
      title: "Book and dispatch",
      body: "Owners, admins, dispatchers and accounts staff work from the web app or iPhone: take the call, create the job, drop it on an engineer's day.",
      points: ["Dispatch board and calendar", "Clash warnings", "Quotes, invoices and money owed"],
    },
    {
      icon: Smartphone,
      who: "Your engineers",
      title: "Do the work",
      body: "Engineers get the job on their iPhone with the address, notes and equipment, then mark travel, arrival and completion as they go.",
      points: ["Directions and live status", "Photos and signatures", "Chat with the office"],
    },
    {
      icon: Users,
      who: "Your customers",
      title: "Stay informed and pay",
      body: "Customers get texts from your own number when you're on the way, and pay their invoice online by card.",
      points: ["Texts from your business number", "Online quotes and invoices", "Card payments into your Stripe"],
    },
  ];
  return (
    <section id="how" className="scroll-mt-16 border-y border-border bg-white py-24">
      <div className="mx-auto max-w-6xl px-5">
        <SectionHeading eyebrow="How it works" title="One live schedule, three people who need it." />
        <div className="relative mt-14 grid gap-6 lg:grid-cols-3">
          <div className="pointer-events-none absolute left-[16%] right-[16%] top-[30px] hidden border-t-2 border-dashed border-brand-orange/40 lg:block" />
          {steps.map(({ icon: Icon, who, title, body, points }, i) => (
            <div key={who} className="relative">
              <div className="relative z-10 flex h-[60px] w-[60px] items-center justify-center rounded-2xl bg-brand-navy text-white shadow-lg shadow-brand-navy/25">
                <Icon className="h-6 w-6" />
                <span className="absolute -right-2 -top-2 flex h-6 w-6 items-center justify-center rounded-full bg-brand-orange text-[11px] font-bold">{i + 1}</span>
              </div>
              <p className="section-label mt-6">{who}</p>
              <h3 className="mt-1.5 text-xl font-bold tracking-tight">{title}</h3>
              <p className="mt-2 text-[15px] leading-relaxed text-muted-foreground">{body}</p>
              <ul className="mt-4 space-y-2">
                {points.map((p) => (
                  <li key={p} className="flex items-center gap-2 text-sm font-medium">
                    <Check className="h-4 w-4 text-success" /> {p}
                  </li>
                ))}
              </ul>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}

/* ------------------------------ Pricing ----------------------------- */

function Pricing() {
  const [period, setPeriod] = useState<Period>("annual");

  return (
    <section id="pricing" className="relative scroll-mt-16 overflow-hidden bg-background py-24">
      <div className="pointer-events-none absolute left-1/2 top-0 h-[420px] w-[900px] -translate-x-1/2 rounded-full bg-[radial-gradient(closest-side,hsl(220_75%_95%),transparent)]" />
      <div className="relative mx-auto max-w-6xl px-5">
        <SectionHeading
          eyebrow="Pricing"
          title="Simple plans that grow with your team."
          body="Every plan includes every feature. Pick the one that fits the number of people using it."
          center
        />

        <div className="mt-10 flex justify-center">
          <div className="inline-flex rounded-xl border border-border bg-white p-1 shadow-sm">
            {(["monthly", "annual"] as const).map((p) => (
              <button
                key={p}
                onClick={() => setPeriod(p)}
                className={cn(
                  "press flex items-center gap-2 rounded-lg px-5 py-2 text-sm font-semibold transition-colors",
                  period === p ? "bg-brand-navy text-white shadow" : "text-muted-foreground hover:text-foreground",
                )}
              >
                {p === "monthly" ? "Monthly" : "Annual"}
                {p === "annual" && (
                  <span className={cn("rounded-full px-2 py-0.5 text-[11px] font-bold", period === p ? "bg-brand-orange text-white" : "bg-brand-orange-tint text-brand-orange-text")}>
                    Save 20%
                  </span>
                )}
              </button>
            ))}
          </div>
        </div>

        <div className="mt-12 grid gap-5 lg:grid-cols-3">
          {PLANS.map((plan) => {
            const highlight = "highlight" in plan && plan.highlight;
            const price = period === "monthly" ? plan.monthly : plan.annual;
            return (
              <div
                key={plan.id}
                className={cn(
                  "relative flex flex-col rounded-[20px] border p-7 transition-shadow",
                  highlight
                    ? "border-brand-navy bg-brand-navy text-white shadow-[0_30px_60px_-25px_rgba(10,36,71,0.6)]"
                    : "border-border bg-white hover:shadow-[0_18px_40px_-22px_rgba(10,36,71,0.3)]",
                )}
              >
                {highlight && (
                  <span className="absolute -top-3 left-7 rounded-full bg-brand-orange px-3 py-1 text-[11px] font-bold uppercase tracking-wider text-white shadow">
                    Great for crews
                  </span>
                )}
                <div className="flex items-baseline justify-between">
                  <h3 className="text-xl font-bold">{plan.name}</h3>
                  <span className={cn("text-sm font-medium", highlight ? "text-white/60" : "text-meta")}>{plan.tagline}</span>
                </div>
                <div className="mt-6 flex items-end gap-1.5">
                  <span className="text-[44px] font-bold leading-none tracking-tight">{usd(price)}</span>
                  <span className={cn("pb-1.5 text-sm font-medium", highlight ? "text-white/60" : "text-muted-foreground")}>
                    /{period === "monthly" ? "month" : "year"}
                  </span>
                </div>
                <p className={cn("mt-2 h-5 text-sm", highlight ? "text-white/60" : "text-muted-foreground")}>
                  {period === "annual"
                    ? `${usd(Math.round(plan.annual / 12))}/month billed yearly · save ${savingPct(plan.monthly, plan.annual)}%`
                    : `or ${usd(plan.annual)}/year`}
                </p>
                <div
                  className={cn(
                    "mt-6 flex items-center gap-2.5 rounded-xl px-4 py-3 text-[15px] font-semibold",
                    highlight ? "bg-white/10" : "bg-secondary",
                  )}
                >
                  <Users className={cn("h-5 w-5", highlight ? "text-brand-orange" : "text-primary")} />
                  {plan.users}
                </div>
                <a
                  href={APP_STORE_URL}
                  target="_blank"
                  rel="noreferrer"
                  className={cn(
                    "press mt-6 rounded-xl py-3 text-center text-[15px] font-semibold transition",
                    highlight ? "bg-brand-orange text-white shadow-lg shadow-brand-orange/30 hover:brightness-110" : "bg-brand-navy text-white hover:bg-brand-navy/90",
                  )}
                >
                  Start 14-day free trial
                </a>
              </div>
            );
          })}
        </div>

        <div className="mt-8 card-surface p-7">
          <div className="flex items-center gap-2">
            <BadgeCheck className="h-5 w-5 text-success" />
            <p className="font-bold">Every plan includes</p>
          </div>
          <ul className="mt-5 grid gap-x-8 gap-y-3 sm:grid-cols-2 lg:grid-cols-3">
            {INCLUDED.map((f) => (
              <li key={f} className="flex items-start gap-2.5 text-[15px]">
                <Check className="mt-0.5 h-4 w-4 shrink-0 text-success" />
                {f}
              </li>
            ))}
          </ul>
        </div>

        <p className="mx-auto mt-6 max-w-3xl text-center text-[13px] leading-relaxed text-muted-foreground">
          Prices in US dollars. Subscriptions are billed by Apple through the App Store, start with a free trial where offered,
          and renew automatically unless cancelled at least 24 hours before the period ends. Your local App Store price may
          differ. *Customer texting is optional and uses prepaid SMS credits and a monthly number fee, separate from your plan —
          see the{" "}
          <a href={LEGAL_PATHS.sms} className="font-medium text-primary underline-offset-2 hover:underline">
            SMS &amp; Messaging Terms
          </a>
          .
        </p>
      </div>
    </section>
  );
}

/* -------------------------------- FAQ ------------------------------- */

const FAQS = [
  {
    q: "How do I get started?",
    a: "Download Harbour South FieldOps from the App Store, create your company and choose a plan. Your free trial starts straight away, and you can invite your team from the app.",
  },
  {
    q: "Is there a web version?",
    a: "Yes. Owners, admins, dispatchers and accounts staff can sign in to the office web app with the same login to run jobs, the dispatch board, the calendar and the live map on a big screen. Engineers use the iPhone app in the field.",
  },
  {
    q: "How does the free trial work?",
    a: "New subscribers get a 14-day free trial through the App Store. If you cancel before it ends you won't be charged; otherwise it continues on the plan you chose.",
  },
  {
    q: "Can I change plans as my team grows?",
    a: "Yes. Switch between Starter, Team and Business at any time. If you move to a plan with fewer users, you choose who stays active — we never deactivate anyone for you.",
  },
  {
    q: "How does customer texting work?",
    a: "When you turn it on, your business gets its own dedicated US number. Texts use prepaid SMS credits bought in the app, plus a small monthly number fee. Customers can reply STOP at any time and opt-outs are always honoured.",
  },
  {
    q: "How do my customers pay me?",
    a: "Connect your own Stripe account and customers can pay invoices online by card. The money goes to your Stripe account; Harbour South charges a platform fee on eligible payments, shown in the app.",
  },
  {
    q: "Who owns my data?",
    a: "Your company does. Each company's data is kept separate from every other company's, and access inside your company follows the roles you set.",
  },
];

function Faq() {
  return (
    <section id="faq" className="scroll-mt-16 border-t border-border bg-white py-24">
      <div className="mx-auto grid max-w-6xl gap-12 px-5 lg:grid-cols-[1fr_1.5fr]">
        <div>
          <SectionHeading eyebrow="FAQ" title="Questions, answered." />
          <p className="mt-4 text-[15px] leading-relaxed text-muted-foreground">
            Read our{" "}
            <a href={LEGAL_PATHS.privacy} className="font-medium text-primary hover:underline">
              Privacy Policy
            </a>{" "}
            and{" "}
            <a href={LEGAL_PATHS.terms} className="font-medium text-primary hover:underline">
              Terms of Service
            </a>{" "}
            for the details.
          </p>
        </div>
        <Accordion type="single" collapsible className="w-full">
          {FAQS.map((f) => (
            <AccordionItem key={f.q} value={f.q}>
              <AccordionTrigger className="text-left text-[16px] font-semibold hover:no-underline">{f.q}</AccordionTrigger>
              <AccordionContent className="text-[15px] leading-relaxed text-muted-foreground">{f.a}</AccordionContent>
            </AccordionItem>
          ))}
        </Accordion>
      </div>
    </section>
  );
}

/* ----------------------------- Final CTA ---------------------------- */

function FinalCta() {
  return (
    <section className="bg-background px-5 py-20">
      <div className="relative mx-auto max-w-6xl overflow-hidden rounded-[28px] bg-brand-navy px-8 py-14 text-white md:px-14">
        <div className="pointer-events-none absolute -bottom-72 -right-24 h-[520px] w-[520px] rounded-full border-[44px] border-brand-orange/90" />
        <div className="relative max-w-xl">
          <h2 className="text-3xl font-bold tracking-tight md:text-4xl">Run tomorrow's jobs from one place.</h2>
          <p className="mt-3 text-lg text-white/70">Try Harbour South FieldOps free for 14 days on your iPhone.</p>
          <div className="mt-8 flex flex-wrap items-center gap-3">
            <AppStoreButton className="bg-white text-black hover:bg-white/90" />
            <a href={loginHref()} className="press rounded-xl border border-white/20 px-5 py-3 text-[15px] font-semibold transition-colors hover:bg-white/10">
              Office log in
            </a>
          </div>
          <p className="mt-6 flex items-center gap-2 text-sm text-white/50">
            <Smartphone className="h-4 w-4" /> Engineers sign in on the iPhone app; the web app is for office roles.
          </p>
        </div>
      </div>
    </section>
  );
}

/* ------------------------------ Shared ------------------------------ */

function SectionHeading({ eyebrow, title, body, center }: { eyebrow: string; title: string; body?: string; center?: boolean }) {
  return (
    <div className={cn("max-w-2xl", center && "mx-auto text-center")}>
      <p className="text-xs font-bold uppercase tracking-[0.16em] text-brand-orange">{eyebrow}</p>
      <h2 className="mt-3 text-3xl font-bold leading-tight tracking-tight md:text-[40px]">{title}</h2>
      {body && <p className="mt-4 text-lg leading-relaxed text-muted-foreground">{body}</p>}
    </div>
  );
}
