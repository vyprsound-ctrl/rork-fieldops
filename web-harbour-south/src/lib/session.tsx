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

async function resolve(session: Session | null): Promise<SessionState> {
  if (!session) return { kind: "signedOut" };
  const email = session.user.email ?? "";
  const me = await loadMembership(session.user.id);
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
