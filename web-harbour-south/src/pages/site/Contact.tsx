import { useState } from "react";
import { Check, Copy, CreditCard, LifeBuoy, Mail, ShieldCheck } from "lucide-react";
import { toast } from "sonner";

import { CONTACT_EMAIL, LEGAL_PATHS } from "@/lib/site";
import { SitePage, usePageTitle } from "./SiteChrome";

const TOPICS = [
  {
    icon: LifeBuoy,
    title: "Help with the app",
    body: "Questions about jobs, dispatch, invoices, texting or your account. Tell us your company name and what you were trying to do.",
    subject: "Help with Harbour South FieldOps",
  },
  {
    icon: CreditCard,
    title: "Plans and billing",
    body: "Choosing a plan, adding users or questions about your subscription and free trial.",
    subject: "Plans and billing",
  },
  {
    icon: ShieldCheck,
    title: "Privacy and data requests",
    body: "Access, correction or deletion of your personal information.",
    subject: "Privacy request",
  },
] as const;

export default function Contact() {
  usePageTitle("Contact us — Harbour South FieldOps");
  const [copied, setCopied] = useState(false);

  const copy = async () => {
    try {
      await navigator.clipboard.writeText(CONTACT_EMAIL);
      setCopied(true);
      toast.success("Email address copied");
      setTimeout(() => setCopied(false), 1800);
    } catch {
      toast.error("Couldn't copy — select the address instead");
    }
  };

  return (
    <SitePage headerTone="light">
      <section className="relative overflow-hidden border-b border-border bg-white">
        <div className="pointer-events-none absolute -right-40 -top-56 h-[520px] w-[520px] rounded-full border-[40px] border-brand-orange/15" />
        <div className="relative mx-auto max-w-6xl px-5 pb-16 pt-16">
          <p className="text-xs font-bold uppercase tracking-[0.16em] text-brand-orange">Contact us</p>
          <h1 className="mt-3 max-w-2xl text-4xl font-bold tracking-tight md:text-[48px] md:leading-[1.05]">We're here to help.</h1>
          <p className="mt-4 max-w-xl text-lg text-muted-foreground">
            Email the Harbour South team and we'll get back to you as soon as we can.
          </p>

          <div className="mt-10 flex max-w-2xl flex-col gap-4 rounded-[20px] bg-brand-navy p-6 text-white shadow-[0_30px_60px_-30px_rgba(10,36,71,0.7)] sm:flex-row sm:items-center sm:p-7">
            <span className="flex h-14 w-14 shrink-0 items-center justify-center rounded-2xl bg-brand-orange">
              <Mail className="h-6 w-6" />
            </span>
            <div className="min-w-0 flex-1">
              <p className="text-sm text-white/60">Email</p>
              <a href={`mailto:${CONTACT_EMAIL}`} className="block break-all text-2xl font-bold tracking-tight hover:underline sm:text-[28px]">
                {CONTACT_EMAIL}
              </a>
            </div>
            <div className="flex gap-2">
              <button
                onClick={copy}
                className="press inline-flex items-center gap-2 rounded-xl border border-white/20 px-4 py-2.5 text-sm font-semibold transition-colors hover:bg-white/10"
              >
                {copied ? <Check className="h-4 w-4" /> : <Copy className="h-4 w-4" />}
                {copied ? "Copied" : "Copy"}
              </button>
              <a
                href={`mailto:${CONTACT_EMAIL}`}
                className="press inline-flex items-center rounded-xl bg-white px-4 py-2.5 text-sm font-semibold text-brand-navy transition hover:bg-white/90"
              >
                Send email
              </a>
            </div>
          </div>
        </div>
      </section>

      <section className="mx-auto max-w-6xl px-5 py-16">
        <p className="section-label">What can we help with?</p>
        <div className="mt-5 grid gap-4 md:grid-cols-3">
          {TOPICS.map(({ icon: Icon, title, body, subject }) => (
            <a
              key={title}
              href={`mailto:${CONTACT_EMAIL}?subject=${encodeURIComponent(subject)}`}
              className="card-surface group p-6 transition-all hover:-translate-y-0.5 hover:shadow-[0_18px_40px_-20px_rgba(10,36,71,0.35)]"
            >
              <span className="flex h-11 w-11 items-center justify-center rounded-xl bg-primary-tint text-primary">
                <Icon className="h-5 w-5" />
              </span>
              <h2 className="mt-5 text-[17px] font-bold">{title}</h2>
              <p className="mt-2 text-[15px] leading-relaxed text-muted-foreground">{body}</p>
              <p className="mt-4 text-sm font-semibold text-primary group-hover:underline">Email us →</p>
            </a>
          ))}
        </div>
        <p className="mt-10 max-w-2xl text-sm leading-relaxed text-muted-foreground">
          Are you a customer of a business that uses Harbour South? For questions about your appointment or invoice, please
          contact that business directly. You can stop texts from a business at any time by replying STOP. See our{" "}
          <a href={LEGAL_PATHS.privacy} className="font-medium text-primary hover:underline">
            Privacy Policy
          </a>{" "}
          for how we handle information.
        </p>
      </section>
    </SitePage>
  );
}
