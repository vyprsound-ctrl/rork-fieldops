import { useEffect } from "react";
import { Link } from "react-router-dom";
import { FileText, MessageSquare, ShieldCheck, UserX } from "lucide-react";

import { cn } from "@/lib/utils";
import { LEGAL_DOCS, type LegalDoc } from "@/lib/legal";
import { LEGAL_LAST_UPDATED } from "@/lib/site";
import { SitePage, usePageTitle } from "./SiteChrome";

const ICONS = { privacy: ShieldCheck, terms: FileText, sms: MessageSquare, deletion: UserX } as const;

const slug = (s: string) =>
  s
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/(^-|-$)/g, "");

export default function LegalPage({ doc }: { doc: LegalDoc }) {
  usePageTitle(`${doc.title} — Harbour South FieldOps`);
  useEffect(() => window.scrollTo(0, 0), [doc.key]);
  const Icon = ICONS[doc.key];

  return (
    <SitePage headerTone="light">
      <div className="border-b border-border bg-white">
        <div className="mx-auto max-w-6xl px-5 pb-10 pt-14">
          <div className="flex h-12 w-12 items-center justify-center rounded-2xl bg-primary-tint">
            <Icon className="h-6 w-6 text-primary" />
          </div>
          <h1 className="mt-5 text-4xl font-bold tracking-tight md:text-[44px]">{doc.title}</h1>
          <p className="mt-3 max-w-2xl text-lg text-muted-foreground">{doc.summary}</p>
          <p className="mt-4 text-sm font-medium text-meta">Harbour South FieldOps · Last updated {LEGAL_LAST_UPDATED}</p>
        </div>
      </div>

      <div className="mx-auto grid max-w-6xl gap-12 px-5 py-12 lg:grid-cols-[240px_1fr]">
        <aside className="lg:sticky lg:top-24 lg:self-start">
          <p className="section-label">Legal</p>
          <nav className="mt-3 flex flex-col gap-1">
            {LEGAL_DOCS.map((d) => (
              <Link
                key={d.key}
                to={d.path}
                className={cn(
                  "rounded-lg px-3 py-2 text-sm font-medium transition-colors",
                  d.key === doc.key ? "bg-brand-orange-tint text-brand-orange-text" : "text-muted-foreground hover:bg-secondary hover:text-foreground",
                )}
              >
                {d.title}
              </Link>
            ))}
          </nav>
          <p className="section-label mt-8 hidden lg:block">On this page</p>
          <nav className="mt-3 hidden flex-col gap-1.5 lg:flex">
            {doc.sections.map((s) => (
              <a key={s.heading} href={`#${slug(s.heading)}`} className="px-3 text-[13px] text-muted-foreground hover:text-foreground">
                {s.heading}
              </a>
            ))}
          </nav>
        </aside>

        <article className="max-w-[720px]">
          {doc.sections.map((s) => (
            <section key={s.heading} id={slug(s.heading)} className="scroll-mt-24 border-b border-border py-7 first:pt-0 last:border-0">
              <h2 className="text-xl font-bold tracking-tight">{s.heading}</h2>
              <div className="mt-3 space-y-3 text-[15.5px] leading-relaxed text-foreground/80">
                {s.paragraphs.map((p, i) => (
                  <p key={i}>{p}</p>
                ))}
              </div>
            </section>
          ))}
        </article>
      </div>
    </SitePage>
  );
}
