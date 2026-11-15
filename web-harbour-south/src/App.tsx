import { useEffect } from "react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { BrowserRouter, Navigate, Route, Routes, useLocation } from "react-router-dom";
import { Loader2 } from "lucide-react";

import { Toaster } from "@/components/ui/sonner";
import { TooltipProvider } from "@/components/ui/tooltip";
import { AppShell, canSeeMessages, canSeeReports, canSeeVehicles } from "@/components/hs/AppShell";
import { SessionProvider, useSession, useWorkspace, type Workspace } from "@/lib/session";
import type { Permission } from "@/lib/domain";
import type { ReactNode } from "react";

import Dashboard from "./pages/Dashboard";
import Jobs from "./pages/Jobs";
import Dispatch from "./pages/Dispatch";
import CalendarPage from "./pages/Calendar";
import LiveMap from "./pages/LiveMap";
import Customers from "./pages/Customers";
import CustomerDetail from "./pages/CustomerDetail";
import Quotes from "./pages/Quotes";
import QuoteDetail from "./pages/QuoteDetail";
import Invoices from "./pages/Invoices";
import InvoiceDetail from "./pages/InvoiceDetail";
import Billing from "./pages/Billing";
import Team from "./pages/Team";
import SettingsPage from "./pages/Settings";
import Messages from "./pages/Messages";
import Recurring from "./pages/Recurring";
import Reports from "./pages/Reports";
import Vehicles from "./pages/Vehicles";
import SignIn from "./pages/auth/SignIn";
import SignUp from "./pages/auth/SignUp";
import CompanySetup from "./pages/auth/CompanySetup";
import ForgotPassword from "./pages/auth/ForgotPassword";
import ResetPassword from "./pages/auth/ResetPassword";
import Blocked from "./pages/auth/Blocked";
import Landing from "./pages/site/Landing";
import LegalPage from "./pages/site/LegalPage";
import Contact from "./pages/site/Contact";
import { LEGAL_DOCS } from "@/lib/legal";
import { APP_BASE, CONTACT_PATH, isAppPath } from "@/lib/site";

const queryClient = new QueryClient({
  defaultOptions: { queries: { retry: 1, refetchOnWindowFocus: true, staleTime: 20_000 } },
});

/** Pages a role can't use send people back to the dashboard. */
function Allowed({ permission, children }: { permission: Permission; children: ReactNode }) {
  const ws = useWorkspace();
  return ws.can(permission) ? <>{children}</> : <Navigate to="/" replace />;
}

/** For pages open to any of several permissions (or tied to a trade). */
function When({ test, children }: { test: (ws: Workspace) => boolean; children: ReactNode }) {
  const ws = useWorkspace();
  return test(ws) ? <>{children}</> : <Navigate to="/" replace />;
}

/** Billing is the owner's alone, and stays open while the workspace is read-only. */
function OwnerOnly({ children }: { children: ReactNode }) {
  const ws = useWorkspace();
  return ws.me.role === "owner" ? <>{children}</> : <Navigate to="/" replace />;
}

function Gate() {
  const { state } = useSession();

  switch (state.kind) {
    case "loading":
      return (
        <div className="flex h-full items-center justify-center bg-brand-navy">
          <div className="flex flex-col items-center gap-4">
            <img src="/brand-logo.png" alt="" className="h-16 w-16 rounded-2xl bg-white object-contain p-1" />
            <Loader2 className="h-5 w-5 animate-spin text-white/70" />
          </div>
        </div>
      );
    case "signedOut":
      return (
        <Routes>
          <Route path="/forgot-password" element={<ForgotPassword />} />
          <Route path="/reset-password" element={<ResetPassword />} />
          <Route path="/signup" element={<SignUp />} />
          <Route path="*" element={<SignIn />} />
        </Routes>
      );
    case "error":
      return <Blocked kind="error" />;
    case "noMembership":
      return (
        <Routes>
          <Route path="/reset-password" element={<ResetPassword />} />
          <Route path="*" element={<CompanySetup email={state.email} />} />
        </Routes>
      );
    case "inactive":
    case "fieldWorker":
      return (
        <Routes>
          <Route path="/reset-password" element={<ResetPassword />} />
          <Route path="*" element={<Blocked kind={state.kind} />} />
        </Routes>
      );
    case "ready":
      return (
        <Routes>
          <Route path="/reset-password" element={<ResetPassword />} />
          <Route element={<AppShell />}>
            <Route path="/" element={<Dashboard />} />
            <Route path="/jobs" element={<Jobs />} />
            <Route path="/dispatch" element={<Dispatch />} />
            <Route path="/calendar" element={<CalendarPage />} />
            <Route path="/map" element={<LiveMap />} />
            <Route path="/customers" element={<Customers />} />
            <Route path="/customers/:id" element={<CustomerDetail />} />
            <Route path="/quotes" element={<Allowed permission="quotesRead"><Quotes /></Allowed>} />
            <Route path="/quotes/:id" element={<Allowed permission="quotesRead"><QuoteDetail /></Allowed>} />
            <Route path="/invoices" element={<Allowed permission="invoicesRead"><Invoices /></Allowed>} />
            <Route path="/invoices/:id" element={<Allowed permission="invoicesRead"><InvoiceDetail /></Allowed>} />
            <Route path="/billing" element={<OwnerOnly><Billing /></OwnerOnly>} />
            <Route path="/team" element={<Allowed permission="usersRead"><Team /></Allowed>} />
            <Route path="/settings" element={<Allowed permission="companyProfileRead"><SettingsPage /></Allowed>} />
            <Route path="/settings/:section" element={<Allowed permission="companyProfileRead"><SettingsPage /></Allowed>} />
            <Route path="/messages" element={<When test={canSeeMessages}><Messages /></When>} />
            <Route path="/recurring" element={<Allowed permission="customersReadAll"><Recurring /></Allowed>} />
            <Route path="/reports" element={<When test={canSeeReports}><Reports /></When>} />
            <Route path="/vehicles" element={<When test={canSeeVehicles}><Vehicles /></When>} />
          </Route>
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      );
  }
}

/** Anything outside the public pages (old bookmarks like /jobs, /login) belongs to the office app. */
function ToOfficeApp() {
  const { pathname, search, hash } = useLocation();
  useEffect(() => {
    const rest = pathname === "/" || pathname === "/login" ? "" : pathname;
    window.location.replace(`${APP_BASE}${rest}${search}${hash}`);
  }, [pathname, search, hash]);
  return null;
}

/**
 * The public website: landing, contact and the four legal pages the iPhone
 * app links to. These never depend on sign-in.
 */
function PublicSite() {
  return (
    <Routes>
      <Route path="/" element={<Landing />} />
      <Route path="/welcome" element={<Navigate to="/" replace />} />
      <Route path={CONTACT_PATH} element={<Contact />} />
      {LEGAL_DOCS.map((doc) => (
        <Route key={doc.key} path={doc.path} element={<LegalPage doc={doc} />} />
      ))}
      <Route path="*" element={<ToOfficeApp />} />
    </Routes>
  );
}

const router = { v7_startTransition: true, v7_relativeSplatPath: true } as const;

/** harboursouth.us/app/* is the office web app; everything else is the public website. */
const App = () => (
  <QueryClientProvider client={queryClient}>
    <TooltipProvider>
      <Toaster position="bottom-left" richColors />
      {isAppPath(window.location.pathname) ? (
        <BrowserRouter basename={APP_BASE} future={router}>
          <SessionProvider>
            <Gate />
          </SessionProvider>
        </BrowserRouter>
      ) : (
        <BrowserRouter future={router}>
          <PublicSite />
        </BrowserRouter>
      )}
    </TooltipProvider>
  </QueryClientProvider>
);

export default App;
