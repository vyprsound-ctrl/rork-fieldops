import { supabase } from "./supabase";
import { AppError, rows, rpc, translate } from "./api";
import type { Role } from "./domain";

export const INVITABLE_ROLES: Role[] = ["fieldWorker", "dispatcher", "accounts", "admin"];

export const ROLE_SUMMARY: Record<Role, string> = {
  owner: "Full company access, users and subscription",
  admin: "Full operations, no company or SaaS billing",
  dispatcher: "Jobs, calendar, customers and assignments",
  fieldWorker: "Assigned stops only",
  accounts: "Invoices, payments and financial reports",
};

export const EXPIRY_OPTIONS = [2, 7, 14, 30];

export type MemberStatus = "active" | "invited" | "suspended";

export interface Member {
  id: string;
  name: string;
  email: string;
  phone: string | null;
  role: Role;
  status: MemberStatus;
  last_active_at: string | null;
}

export interface Invitation {
  id: string;
  email: string;
  role: Role;
  created_at: string;
  expires_at: string;
  accepted_at: string | null;
  revoked_at: string | null;
}

export interface FinancialGrant {
  user_id: string;
  can_invoice: boolean;
  can_collect_payments: boolean;
}

export interface Seats {
  plan_user_limit: number | null;
  active_users: number;
  open_invitations: number;
  can_add_user: boolean;
  seat_limits_enforced: boolean;
  seats_over_limit: boolean;
  users_to_deactivate: number;
}

export async function members(): Promise<Member[]> {
  const list = await rows<Member>(supabase.from("app_users").select("id,name,email,phone,role,status,last_active_at"));
  const order: Record<string, number> = { owner: 0, admin: 1, dispatcher: 2, accounts: 3, fieldWorker: 4 };
  return list.sort((a, b) => (order[a.role] ?? 9) - (order[b.role] ?? 9) || a.name.localeCompare(b.name));
}

export async function openInvitations(): Promise<Invitation[]> {
  const list = await rows<Invitation>(
    supabase
      .from("invitations")
      .select("id,email,role,created_at,expires_at,accepted_at,revoked_at")
      .is("accepted_at", null)
      .is("revoked_at", null)
      .order("created_at", { ascending: false }),
  );
  return list;
}

export async function financialGrants(): Promise<Map<string, FinancialGrant>> {
  const list = await rows<FinancialGrant>(
    supabase.from("member_financial_permissions").select("user_id,can_invoice,can_collect_payments"),
  ).catch(() => [] as FinancialGrant[]);
  return new Map(list.map((g) => [g.user_id, g]));
}

export async function seats(): Promise<Seats | null> {
  const data = await rpc<Seats[]>("company_commercial_state");
  return data?.[0] ?? null;
}

const FUNCTIONS = ((import.meta.env.EXPO_PUBLIC_RORK_FUNCTIONS_URL as string | undefined) ?? "").replace(/\/+$/, "");

export interface InviteResult {
  emailed: boolean;
  detail: string;
  link: string | null;
}

/** Creates the invitation and asks the Worker to email it, exactly as the iPhone app does. */
export async function invite(email: string, role: Role, days: number, name: string): Promise<InviteResult> {
  const address = email.trim().toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(address)) throw new AppError("Enter a valid email address.");
  if (!INVITABLE_ROLES.includes(role)) throw new AppError("Choose a role.");
  const { data, error } = await supabase.rpc("create_invitation", {
    p_email: address,
    p_role: role,
    p_expires_in_days: days,
  });
  if (error) {
    if (/already/i.test(error.message) && /member/i.test(error.message)) {
      throw new AppError("That email already belongs to somebody in your company.");
    }
    if (error.code === "23505") throw new AppError("There's already an open invitation for that address.");
    if (error.code === "TD422" || error.code === "P0001") throw new AppError(error.message);
    throw translate(error);
  }
  const row = (data as { invitation_id: string; invitation_token: string }[] | null)?.[0];
  if (!row) throw new AppError("The invitation couldn't be created.");
  const link = FUNCTIONS ? `${FUNCTIONS}/join?t=${row.invitation_token}` : null;

  if (!FUNCTIONS) return { emailed: false, detail: "Invitation created. Share the link with them.", link };
  try {
    const { data: auth } = await supabase.auth.getSession();
    const response = await fetch(`${FUNCTIONS}/invite`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${auth.session?.access_token ?? ""}` },
      body: JSON.stringify({ invitationId: row.invitation_id, token: row.invitation_token, name: name.trim() }),
    });
    const body = (await response.json().catch(() => ({}))) as { delivered?: boolean; recipient?: string; detail?: string };
    if (response.ok && body.delivered) {
      return { emailed: true, detail: `Invitation emailed to ${body.recipient ?? address}.`, link };
    }
    return { emailed: false, detail: body.detail || "The invitation was created but the email couldn't be sent. Share the link instead.", link };
  } catch {
    return { emailed: false, detail: "The invitation was created but the email couldn't be sent. Share the link instead.", link };
  }
}

export const revokeInvitation = (id: string) => rpc("revoke_invitation", { p_invitation_id: id });

async function updateMember(id: string, patch: Record<string, unknown>) {
  const { error } = await supabase
    .from("app_users")
    .update({ ...patch, updated_at: new Date().toISOString() })
    .eq("id", id);
  if (error) throw translate(error);
}

export const setMemberRole = (id: string, role: Role) => {
  if (role === "owner") throw new AppError("Ownership can't be given from here.");
  return updateMember(id, { role });
};
export const setMemberStatus = (id: string, status: "active" | "suspended") => updateMember(id, { status });
export const saveMemberDetails = (id: string, name: string, phone: string) => {
  if (!name.trim()) throw new AppError("Enter a name.");
  return updateMember(id, { name: name.trim(), phone: phone.trim() || null });
};

export const setFinancialGrant = (userId: string, canInvoice: boolean, canCollect: boolean) =>
  rpc("set_member_financial_permissions", { p_user: userId, p_can_invoice: canInvoice, p_can_collect: canCollect });
