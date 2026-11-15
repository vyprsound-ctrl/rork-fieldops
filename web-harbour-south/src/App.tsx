import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { BrowserRouter, Navigate, Route, Routes } from "react-router-dom";
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
import { LEGAL_DOCS } from "@/lib/legal";
import { isMarketingHost } from "@/lib/site";

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

/**
 * Public pages (legal documents, and the landing page on harboursouth.us)
 * render regardless of sign-in; everything else goes through the app gate.
 * The iPhone app links to the four legal paths, so they must always resolve.
 */
function Site() {
  const marketing = isMarketingHost();
  return (
    <Routes>
      {LEGAL_DOCS.map((doc) => (
        <Route key={doc.key} path={doc.path} element={<LegalPage doc={doc} />} />
      ))}
      <Route path="/welcome" element={<Landing />} />
      {marketing && <Route path="/" element={<Landing />} />}
      <Route path="*" element={<Gate />} />
    </Routes>
  );
}

const App = () => (
  <QueryClientProvider client={queryClient}>
    <TooltipProvider>
      <Toaster position="bottom-left" richColors />
      <BrowserRouter future={{ v7_startTransition: true, v7_relativeSplatPath: true }}>
        <SessionProvider>
          <Site />
        </SessionProvider>
      </BrowserRouter>
    </TooltipProvider>
  </QueryClientProvider>
);

export default App;
