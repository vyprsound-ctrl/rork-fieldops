import { useEffect } from "react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { BrowserRouter, Navigate, Route, Routes, useLocation } from "react-router-dom";
import { Loader2 } from "lucide-react";

import { Toaster } from "@/components/ui/sonner";
import { TooltipProvider } from "@/components/ui/tooltip";
import { AppShell } from "@/components/hs/AppShell";
import { SessionProvider, useSession } from "@/lib/session";

import Dashboard from "./pages/Dashboard";
import Jobs from "./pages/Jobs";
import Dispatch from "./pages/Dispatch";
import CalendarPage from "./pages/Calendar";
import LiveMap from "./pages/LiveMap";
import SignIn from "./pages/auth/SignIn";
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
          <Route path="*" element={<SignIn />} />
        </Routes>
      );
    case "error":
      return <Blocked kind="error" />;
    case "noMembership":
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
