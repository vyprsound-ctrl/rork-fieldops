import { createContext, useContext, useEffect, useState, type ReactNode } from "react";
import { NavLink, Outlet, useNavigate } from "react-router-dom";
import {
  BarChart3,
  Briefcase,
  CalendarDays,
  ClipboardList,
  CreditCard,
  FileText,
  LayoutDashboard,
  Lock,
  LogOut,
  Map as MapIcon,
  MessageCircle,
  Plus,
  Receipt,
  Search,
  Settings,
  Truck,
  Users,
  UsersRound,
} from "lucide-react";

import {
  CommandDialog,
  CommandEmpty,
  CommandGroup,
  CommandInput,
  CommandItem,
  CommandList,
} from "@/components/ui/command";
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuLabel, DropdownMenuSeparator, DropdownMenuTrigger } from "@/components/ui/dropdown-menu";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import { ROLE_TITLE, shortAddress, type Permission } from "@/lib/domain";
import { useCustomers, useJobs } from "@/lib/queries";
import { useSession, useWorkspace } from "@/lib/session";
import { JobPanel } from "./JobPanel";
import { NewJobDialog } from "./NewJobDialog";
import { StatusBadge, WorkerAvatar, useJobPanel } from "./primitives";

interface ShellContextValue {
  newJob: () => void;
}
const ShellContext = createContext<ShellContextValue>({ newJob: () => undefined });
export const useShell = () => useContext(ShellContext);

const NAV: { to: string; label: string; icon: typeof Users; end?: boolean; needs?: Permission; ownerOnly?: boolean }[] = [
  { to: "/", label: "Dashboard", icon: LayoutDashboard, end: true },
  { to: "/jobs", label: "Jobs", icon: Briefcase },
  { to: "/dispatch", label: "Dispatch", icon: ClipboardList },
  { to: "/calendar", label: "Calendar", icon: CalendarDays },
  { to: "/map", label: "Live map", icon: MapIcon },
  { to: "/customers", label: "Customers", icon: Users },
  { to: "/quotes", label: "Quotes", icon: FileText, needs: "quotesRead" },
  { to: "/invoices", label: "Invoices", icon: Receipt, needs: "invoicesRead" },
  { to: "/billing", label: "Billing", icon: CreditCard, ownerOnly: true },
];

function useNav() {
  const ws = useWorkspace();
  return NAV.filter((n) => (!n.needs || ws.can(n.needs)) && (!n.ownerOnly || ws.me.role === "owner"));
}

const SOON = [
  { label: "Team", icon: UsersRound },
  { label: "Messages", icon: MessageCircle },
  { label: "Vehicles", icon: Truck },
  { label: "Reports", icon: BarChart3 },
  { label: "Settings", icon: Settings },
];

export function AppShell() {
  const ws = useWorkspace();
  const { signOut } = useSession();
  const [search, setSearch] = useState(false);
  const [newJob, setNewJob] = useState(false);
  const canCreate = ws.can("jobsManage");
  const nav = useNav();

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") {
        e.preventDefault();
        setSearch((s) => !s);
      }
      const typing = (e.target as HTMLElement)?.closest("input,textarea,[contenteditable],[role=dialog]");
      if (!typing && e.key.toLowerCase() === "n" && !e.metaKey && !e.ctrlKey && canCreate) {
        e.preventDefault();
        setNewJob(true);
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [canCreate]);

  return (
    <ShellContext.Provider value={{ newJob: () => setNewJob(true) }}>
      <div className="flex h-full">
        <aside className="relative hidden w-[248px] shrink-0 flex-col overflow-hidden bg-sidebar text-sidebar-foreground md:flex">
          <div className="pointer-events-none absolute -left-24 -top-24 h-64 w-64 rounded-full border-[22px] border-brand-orange/15" />
          <div className="relative flex items-center gap-3 px-5 pb-6 pt-6">
            <div className="flex h-10 w-10 items-center justify-center overflow-hidden rounded-xl bg-white">
              <img src="/brand-logo.png" alt="" className="h-9 w-9 object-contain" />
            </div>
            <div className="leading-tight">
              <p className="text-[15px] font-bold text-white">Harbour South</p>
              <p className="text-[11px] font-medium uppercase tracking-[0.14em] text-brand-orange">FieldOps</p>
            </div>
          </div>

          <button
            onClick={() => setSearch(true)}
            className="relative mx-4 mb-5 flex items-center gap-2 rounded-xl bg-sidebar-accent px-3 py-2 text-left text-sm text-sidebar-foreground/70 transition-colors hover:bg-sidebar-accent/80"
          >
            <Search className="h-4 w-4" />
            <span className="flex-1">Find a job</span>
            <kbd className="rounded bg-white/10 px-1.5 py-0.5 text-[10px] font-semibold">⌘K</kbd>
          </button>

          <nav className="relative flex-1 space-y-0.5 overflow-y-auto px-3 scroll-thin">
            {nav.map((item) => (
              <NavLink
                key={item.to}
                to={item.to}
                end={item.end}
                className={({ isActive }) =>
                  cn(
                    "group flex items-center gap-3 rounded-xl px-3 py-2.5 text-sm font-medium transition-colors",
                    isActive ? "bg-white text-brand-navy shadow-sm" : "text-sidebar-foreground hover:bg-sidebar-accent hover:text-white",
                  )
                }
              >
                {({ isActive }) => (
                  <>
                    <item.icon className={cn("h-[18px] w-[18px]", isActive ? "text-brand-orange" : "")} />
                    {item.label}
                  </>
                )}
              </NavLink>
            ))}

            <p className="px-3 pb-1.5 pt-6 text-[10px] font-semibold uppercase tracking-[0.14em] text-sidebar-foreground/45">
              Coming to the web
            </p>
            {SOON.map((item) => (
              <div
                key={item.label}
                className="flex cursor-default items-center gap-3 rounded-xl px-3 py-2 text-sm text-sidebar-foreground/40"
                title="Available in the iPhone app today"
              >
                <item.icon className="h-[18px] w-[18px]" />
                {item.label}
              </div>
            ))}
          </nav>

          <div className="relative border-t border-sidebar-border p-3">
            <DropdownMenu>
              <DropdownMenuTrigger className="flex w-full items-center gap-3 rounded-xl p-2 text-left transition-colors hover:bg-sidebar-accent">
                <WorkerAvatar name={ws.me.name} id={ws.me.id} size={34} />
                <div className="min-w-0 flex-1 leading-tight">
                  <p className="truncate text-sm font-semibold text-white">{ws.me.name}</p>
                  <p className="truncate text-xs text-sidebar-foreground/60">
                    {ROLE_TITLE[ws.me.role]} · {ws.company.name}
                  </p>
                </div>
              </DropdownMenuTrigger>
              <DropdownMenuContent align="end" side="top" className="w-56">
                <DropdownMenuLabel className="font-normal">
                  <p className="text-sm font-semibold">{ws.me.name}</p>
                  <p className="text-xs text-muted-foreground">{ws.me.email}</p>
                </DropdownMenuLabel>
                <DropdownMenuSeparator />
                <DropdownMenuItem onClick={() => void signOut()}>
                  <LogOut className="mr-2 h-4 w-4" /> Sign out
                </DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenu>
          </div>
        </aside>

        <div className="flex min-w-0 flex-1 flex-col">
          {ws.readOnly && <ReadOnlyBanner />}
          <MobileBar onSearch={() => setSearch(true)} />
          <main className="relative min-h-0 flex-1 overflow-y-auto scroll-thin">
            <Outlet />
          </main>
        </div>
      </div>

      {canCreate && (
        <Button
          onClick={() => setNewJob(true)}
          className="press fixed bottom-6 right-6 z-30 h-12 gap-2 rounded-full bg-brand-orange px-5 text-[15px] font-semibold shadow-lift hover:bg-brand-orange/90"
        >
          <Plus className="h-5 w-5" /> New job
        </Button>
      )}

      <QuickSearch open={search} onOpenChange={setSearch} />
      {canCreate && <NewJobDialog open={newJob} onOpenChange={setNewJob} />}
      <JobPanel />
    </ShellContext.Provider>
  );
}

function ReadOnlyBanner() {
  const ws = useWorkspace();
  const owner = ws.me.role === "owner";
  return (
    <div className="flex items-center gap-3 bg-brand-orange-tint px-6 py-2.5 text-sm text-brand-orange-text">
      <Lock className="h-4 w-4 shrink-0" />
      <p className="flex-1">
        <span className="font-semibold">Your workspace is read-only.</span> The company subscription isn't active.{" "}
        {owner
          ? "Choose a plan here on the web, or in the iPhone app under Settings → Subscription."
          : "The owner can subscribe on the web under Billing, or in the iPhone app."}
      </p>
      {owner && (
        <NavLink to="/billing" className="shrink-0 rounded-lg bg-brand-orange px-3 py-1.5 text-xs font-semibold text-white hover:bg-brand-orange/90">
          Choose a plan
        </NavLink>
      )}
    </div>
  );
}

function MobileBar({ onSearch }: { onSearch: () => void }) {
  const navigate = useNavigate();
  const nav = useNav();
  return (
    <div className="flex items-center gap-2 overflow-x-auto bg-brand-navy px-3 py-2 md:hidden">
      {nav.map((n) => (
        <button key={n.to} onClick={() => navigate(n.to)} className="rounded-lg px-2.5 py-1.5 text-xs font-medium text-white/80">
          {n.label}
        </button>
      ))}
      <button onClick={onSearch} className="ml-auto rounded-lg p-1.5 text-white/80" aria-label="Search">
        <Search className="h-4 w-4" />
      </button>
    </div>
  );
}

function QuickSearch({ open, onOpenChange }: { open: boolean; onOpenChange: (o: boolean) => void }) {
  const ws = useWorkspace();
  const { data: jobs = [] } = useJobs();
  const { data: customers = [] } = useCustomers();
  const panel = useJobPanel();
  const navigate = useNavigate();
  const nav = useNav();

  const go = (fn: () => void) => {
    onOpenChange(false);
    fn();
  };

  return (
    <CommandDialog open={open} onOpenChange={onOpenChange}>
      <CommandInput placeholder="Search jobs, customers, addresses, people…" />
      <CommandList className="max-h-[420px]">
        <CommandEmpty>No matches.</CommandEmpty>
        <CommandGroup heading="Go to">
          {nav.map((n) => (
            <CommandItem key={n.to} value={`go ${n.label}`} onSelect={() => go(() => navigate(n.to))}>
              <n.icon className="mr-2 h-4 w-4 text-primary" />
              {n.label}
            </CommandItem>
          ))}
        </CommandGroup>
        <CommandGroup heading="Customers">
          {customers.slice(0, 300).map((c) => (
            <CommandItem key={c.id} value={`customer ${c.name}`} onSelect={() => go(() => navigate(`/customers/${c.id}`))}>
              <Users className="mr-2 h-4 w-4 text-primary" />
              {c.name}
            </CommandItem>
          ))}
        </CommandGroup>
        <CommandGroup heading="Jobs">
          {jobs.slice(0, 400).map((j) => (
            <CommandItem
              key={j.id}
              value={`${j.number} ${j.title} ${j.customer?.name ?? ""} ${shortAddress(j.address)} ${j.worker?.name ?? ""}`}
              onSelect={() => go(() => panel.open(j.id))}
              className="gap-3"
            >
              <span className="w-16 shrink-0 text-xs font-semibold tabular-nums text-muted-foreground">{j.number}</span>
              <div className="min-w-0 flex-1">
                <p className="truncate text-sm font-medium">{j.title}</p>
                <p className="truncate text-xs text-muted-foreground">
                  {j.customer?.name} · {shortAddress(j.address)}
                </p>
              </div>
              <StatusBadge status={j.status} terms={ws.terms} />
            </CommandItem>
          ))}
        </CommandGroup>
      </CommandList>
    </CommandDialog>
  );
}

export function Page({ children, className }: { children: ReactNode; className?: string }) {
  return <div className={cn("mx-auto w-full max-w-[1400px] px-6 pb-24 pt-8 lg:px-10", className)}>{children}</div>;
}
