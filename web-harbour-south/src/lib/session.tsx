import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from "react";
import type { Session } from "@supabase/supabase-js";

import { supabase } from "./supabase";
import {
  loadCompany,
  loadMembership,
  loadWorkspaceAccess,
  type Company,
  type Membership,
  type WorkspaceAccess,
} from "./api";
import { OFFICE_ROLES, permissionsFor, terminology, type Permission, type Terminology } from "./domain";

export type SessionState =
  | { kind: "loading" }
  | { kind: "signedOut" }
  | { kind: "error"; message: string }
  | { kind: "noMembership"; email: string }
  | { kind: "inactive"; email: string }
  | { kind: "fieldWorker"; name: string }
  | { kind: "ready"; workspace: Workspace };

export interface Workspace {
  userId: string;
  me: Membership;
  company: Company;
  access: WorkspaceAccess | null;
  readOnly: boolean;
  perms: Set<Permission>;
  terms: Terminology;
  can: (p: Permission) => boolean;
}

interface SessionContextValue {
  state: SessionState;
  signOut: () => Promise<void>;
  reload: () => void;
}

const SessionContext = createContext<SessionContextValue | null>(null);

/** Same metadata keys the iPhone app parks at sign-up (PendingCompanySetup). */
export interface CompanySetupInput {
  company_name: string;
  trade: string;
  country_code: string;
  currency_code: string;
  time_zone_identifier: string;
  owner_name: string;
}

const TRADES = new Set([
  "hvac", "plumbing", "electrical", "roofing", "applianceRepair", "locksmith",
  "generalMaintenance", "pestControl", "other", "propertyServices", "automotive",
]);

function pendingSetup(metadata: Record<string, unknown> | undefined): CompanySetupInput | null {
  if (!metadata || metadata.pending_company_setup !== true) return null;
  const s = (k: string) => (typeof metadata[k] === "string" ? (metadata[k] as string).trim() : "");
  const input = {
    company_name: s("company_name"),
    trade: s("trade"),
    country_code: s("country_code").toUpperCase(),
    currency_code: s("currency_code").toUpperCase(),
    time_zone_identifier: s("time_zone_identifier") || Intl.DateTimeFormat().resolvedOptions().timeZone,
    owner_name: s("owner_name"),
  };
  if (!input.company_name || !TRADES.has(input.trade) || input.country_code.length !== 2 || input.currency_code.length !== 3) return null;
  return input;
}

let provisioning: Promise<void> | null = null;

/** Creates the company with this login as owner, then clears the pending flag so it never runs twice. */
export function createCompany(input: CompanySetupInput): Promise<void> {
  provisioning ??= (async () => {
    const { error } = await supabase.rpc("create_company_and_owner", {
      p_name: input.company_name,
      p_trade: input.trade,
      p_country_code: input.country_code,
      p_currency_code: input.currency_code,
      p_time_zone_identifier: input.time_zone_identifier,
      p_owner_name: input.owner_name,
    });
    if (error) throw new Error("Couldn't create your company. Try again, or contact help@harboursouth.us.");
    await supabase.auth.updateUser({ data: { pending_company_setup: false } });
  })().finally(() => {
    provisioning = null;
  });
  return provisioning;
}

async function resolve(session: Session | null): Promise<SessionState> {
  if (!session) return { kind: "signedOut" };
  const email = session.user.email ?? "";
  let me = await loadMembership(session.user.id);
  const pending = me ? null : pendingSetup(session.user.user_metadata);
  if (pending) {
    await createCompany(pending);
    me = await loadMembership(session.user.id);
  }
  if (!me) return { kind: "noMembership", email };
  if (me.status !== "active") return { kind: "inactive", email };
  if (!OFFICE_ROLES.includes(me.role)) return { kind: "fieldWorker", name: me.name };

  const [company, access] = await Promise.all([loadCompany(me.company_id), loadWorkspaceAccess().catch(() => null)]);
  if (!company) return { kind: "noMembership", email };

  // Same entitlement the iPhone app reads: no active subscription means read-only.
  const readOnly = access ? !access.has_active_subscription : false;
  const perms = permissionsFor(me.role, readOnly);
  return {
    kind: "ready",
    workspace: {
      userId: session.user.id,
      me,
      company,
      access,
      readOnly,
      perms,
      terms: terminology(company.trade),
      can: (p) => perms.has(p),
    },
  };
}

export function SessionProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null | undefined>(undefined);
  const [state, setState] = useState<SessionState>({ kind: "loading" });
  const [nonce, setNonce] = useState(0);

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => setSession(data.session));
    const { data } = supabase.auth.onAuthStateChange((event, next) => {
      // Token refreshes keep the same person; only react to real changes.
      if (event === "TOKEN_REFRESHED") return;
      setSession(next);
    });
    return () => data.subscription.unsubscribe();
  }, []);

  const userId = session?.user.id;

  useEffect(() => {
    if (session === undefined) return;
    let cancelled = false;
    setState((prev) => (prev.kind === "ready" && prev.workspace.userId === userId ? prev : { kind: "loading" }));
    resolve(session)
      .then((next) => !cancelled && setState(next))
      .catch((err: Error) => !cancelled && setState({ kind: "error", message: err.message }));
    return () => {
      cancelled = true;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [userId, session === null, nonce]);

  const signOut = useCallback(async () => {
    await supabase.auth.signOut();
    setSession(null);
  }, []);

  const value = useMemo(() => ({ state, signOut, reload: () => setNonce((n) => n + 1) }), [state, signOut]);
  return <SessionContext.Provider value={value}>{children}</SessionContext.Provider>;
}

export function useSession() {
  const ctx = useContext(SessionContext);
  if (!ctx) throw new Error("useSession outside SessionProvider");
  return ctx;
}

/** The signed-in office workspace. Only call below the signed-in gate. */
export function useWorkspace(): Workspace {
  const { state } = useSession();
  if (state.kind !== "ready") throw new Error("useWorkspace before the workspace is ready");
  return state.workspace;
}
