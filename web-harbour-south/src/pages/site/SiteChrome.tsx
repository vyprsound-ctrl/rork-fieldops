import { useEffect, type ReactNode } from "react";
import { Link } from "react-router-dom";

import { cn } from "@/lib/utils";
import { APP_STORE_URL, CONTACT_PATH, LEGAL_PATHS, OFFICE_APP_URL } from "@/lib/site";

/** "Log in" goes to the office app on this same domain (a full page load into its own router). */
export const loginHref = () => OFFICE_APP_URL;

export function usePageTitle(title: string) {
  useEffect(() => {
    const prev = document.title;
    document.title = title;
    return () => {
      document.title = prev;
    };
  }, [title]);
}

export function AppStoreButton({ className, label = "Download on the App Store" }: { className?: string; label?: string }) {
  return (
    <a
      href={APP_STORE_URL}
      target="_blank"
      rel="noreferrer"
      className={cn(
        "press inline-flex items-center gap-2.5 rounded-xl bg-black px-5 py-3 text-white shadow-lg shadow-black/20 transition-colors hover:bg-neutral-800",
        className,
      )}
    >
      <AppleLogo className="h-5 w-5" />
      <span className="text-[15px] font-semibold">{label}</span>
    </a>
  );
}

export function AppleLogo({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 384 512" aria-hidden className={className} fill="currentColor">
      <path d="M318.7 268.7c-.2-36.7 16.4-64.4 50-84.8-18.8-26.9-47.2-41.7-84.7-44.6-35.5-2.8-74.3 20.7-88.5 20.7-15 0-49.4-19.7-76.4-19.7C63.3 141.2 4 184.8 4 273.5q0 39.3 14.4 81.2c12.8 36.7 59 126.7 107.2 125.2 25.2-.6 43-17.9 75.8-17.9 31.8 0 48.3 17.9 76.4 17.9 48.6-.7 90.4-82.5 102.6-119.3-65.2-30.7-61.7-90-61.7-91.9zm-56.6-164.2c27.3-32.4 24.8-61.9 24-72.5-24.1 1.4-52 16.4-67.9 34.9-17.5 19.8-27.8 44.3-25.6 71.9 26.1 2 49.9-11.4 69.5-34.3z" />
    </svg>
  );
}

export function SiteHeader({ tone = "dark" }: { tone?: "dark" | "light" }) {
  const dark = tone === "dark";
  return (
    <header
      className={cn(
        "sticky top-0 z-40 border-b backdrop-blur-md",
        dark ? "border-white/10 bg-brand-navy/85 text-white" : "border-border bg-white/85 text-foreground",
      )}
    >
      <div className="mx-auto flex h-16 max-w-6xl items-center gap-6 px-5">
        <Link to="/" className="flex items-center gap-2.5">
          <span className="flex h-9 w-9 items-center justify-center rounded-[10px] bg-white shadow-sm">
            <img src="/hs-favicon-512.png" alt="Harbour South" className="h-8 w-8 rounded-md object-contain" />
          </span>
          <span className="leading-tight">
            <span className="block text-[15px] font-bold">Harbour South</span>
            <span className="block text-[10px] font-semibold uppercase tracking-[0.18em] text-brand-orange">FieldOps</span>
          </span>
        </Link>
        <nav className={cn("ml-4 hidden items-center gap-6 text-sm font-medium md:flex", dark ? "text-white/70" : "text-muted-foreground")}>
          <a href="/#features" className={dark ? "hover:text-white" : "hover:text-foreground"}>Features</a>
          <a href="/#how" className={dark ? "hover:text-white" : "hover:text-foreground"}>How it works</a>
          <a href="/#pricing" className={dark ? "hover:text-white" : "hover:text-foreground"}>Pricing</a>
          <a href="/#faq" className={dark ? "hover:text-white" : "hover:text-foreground"}>FAQ</a>
          <Link to={CONTACT_PATH} className={dark ? "hover:text-white" : "hover:text-foreground"}>Contact</Link>
        </nav>
        <div className="ml-auto flex items-center gap-2">
          <a
            href={loginHref()}
            className={cn(
              "rounded-lg px-3.5 py-2 text-sm font-semibold transition-colors",
              dark ? "text-white hover:bg-white/10" : "text-foreground hover:bg-secondary",
            )}
          >
            Log in
          </a>
          <a
            href={APP_STORE_URL}
            target="_blank"
            rel="noreferrer"
            className="press hidden rounded-lg bg-brand-orange px-4 py-2 text-sm font-semibold text-white shadow-md shadow-brand-orange/30 transition hover:brightness-110 sm:inline-flex"
          >
            Start free trial
          </a>
        </div>
      </div>
    </header>
  );
}

export function SiteFooter() {
  return (
    <footer className="bg-brand-navy text-white/70">
      <div className="mx-auto grid max-w-6xl gap-10 px-5 py-14 md:grid-cols-[1.4fr_1fr_1fr]">
        <div>
          <div className="flex items-center gap-2.5">
            <span className="flex h-9 w-9 items-center justify-center rounded-[10px] bg-white">
              <img src="/hs-favicon-512.png" alt="Harbour South" className="h-8 w-8 rounded-md object-contain" />
            </span>
            <span className="text-[15px] font-bold text-white">Harbour South FieldOps</span>
          </div>
          <p className="mt-4 max-w-xs text-sm leading-relaxed">
            Field service software for HVAC, plumbing, electrical and other trade businesses.
          </p>
          <AppStoreButton className="mt-6 bg-white/10 shadow-none hover:bg-white/15" />
        </div>
        <FooterCol
          title="Product"
          links={[
            { label: "Features", href: "/#features" },
            { label: "Pricing", href: "/#pricing" },
            { label: "FAQ", href: "/#faq" },
            { label: "Contact us", href: CONTACT_PATH },
            { label: "Office log in", href: loginHref() },
          ]}
        />
        <FooterCol
          title="Legal"
          links={[
            { label: "Privacy Policy", href: LEGAL_PATHS.privacy },
            { label: "Terms of Service", href: LEGAL_PATHS.terms },
            { label: "SMS & Messaging Terms", href: LEGAL_PATHS.sms },
            { label: "Account & Data Deletion", href: LEGAL_PATHS.deletion },
          ]}
        />
      </div>
      <div className="border-t border-white/10">
        <div className="mx-auto flex max-w-6xl flex-wrap items-center justify-between gap-2 px-5 py-5 text-xs text-white/45">
          <span>© {new Date().getFullYear()} Harbour South. All rights reserved.</span>
          <span>Apple, the Apple logo and iPhone are trademarks of Apple Inc. App Store is a service mark of Apple Inc.</span>
        </div>
      </div>
    </footer>
  );
}

function FooterCol({ title, links }: { title: string; links: { label: string; href: string }[] }) {
  return (
    <div>
      <p className="text-[11px] font-semibold uppercase tracking-[0.14em] text-white/40">{title}</p>
      <ul className="mt-4 space-y-2.5 text-sm">
        {links.map((l) => (
          <li key={l.label}>
            <a href={l.href} className="transition-colors hover:text-white">
              {l.label}
            </a>
          </li>
        ))}
      </ul>
    </div>
  );
}

export function SitePage({ children, headerTone }: { children: ReactNode; headerTone?: "dark" | "light" }) {
  return (
    <div className="min-h-full bg-background">
      <SiteHeader tone={headerTone} />
      {children}
      <SiteFooter />
    </div>
  );
}
