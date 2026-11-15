import { useState } from "react";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Copy, Mail, MoreHorizontal, Plus, UserPlus, UsersRound } from "lucide-react";
import { toast } from "sonner";

import { Page } from "@/components/hs/AppShell";
import { EmptyState, LoadingRows, PageHeader, WorkerAvatar } from "@/components/hs/primitives";
import { Confirm, Field, Section, StatTile, ToneBadge } from "@/components/hs/crm";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Switch } from "@/components/ui/switch";
import { Dialog, DialogContent, DialogDescription, DialogFooter, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { ROLE_TITLE, type Role } from "@/lib/domain";
import { relativeAgo, shortDate } from "@/lib/format";
import { useWorkspace } from "@/lib/session";
import {
  EXPIRY_OPTIONS,
  INVITABLE_ROLES,
  ROLE_SUMMARY,
  financialGrants,
  invite,
  members,
  openInvitations,
  revokeInvitation,
  saveMemberDetails,
  seats,
  setFinancialGrant,
  setMemberRole,
  setMemberStatus,
  type InviteResult,
  type Member,
} from "@/lib/team";

const KEY = ["team"] as const;

export default function Team() {
  const ws = useWorkspace();
  const qc = useQueryClient();
  const canManage = ws.can("usersManage");
  const team = useQuery({ queryKey: [...KEY, "members"], queryFn: members });
  const invites = useQuery({ queryKey: [...KEY, "invites"], queryFn: openInvitations, enabled: canManage });
  const grants = useQuery({ queryKey: [...KEY, "grants"], queryFn: financialGrants });
  const seat = useQuery({ queryKey: [...KEY, "seats"], queryFn: seats });
  const [inviting, setInviting] = useState(false);
  const [editing, setEditing] = useState<Member | null>(null);
  const [suspend, setSuspend] = useState<Member | null>(null);
  const [revoke, setRevoke] = useState<string | null>(null);

  const refresh = () => qc.invalidateQueries({ queryKey: KEY });
  const run = async (work: () => Promise<unknown>, done: string) => {
    try {
      await work();
      toast.success(done);
      void refresh();
    } catch (err) {
      toast.error((err as Error).message);
    }
  };

  const list = team.data ?? [];
  const active = list.filter((m) => m.status === "active");
  const s = seat.data;
  const limit = s?.plan_user_limit ?? null;
  const fieldWorkers = list.filter((m) => m.role === "fieldWorker" && m.status === "active");

  return (
    <Page className="max-w-[1200px]">
      <PageHeader
        title="Team"
        subtitle="Everyone in your company, on the web and the iPhone app."
        actions={
          canManage && (
            <Button
              onClick={() => setInviting(true)}
              disabled={s ? !s.can_add_user : false}
              className="press gap-1.5 bg-brand-orange hover:bg-brand-orange/90"
            >
              <UserPlus className="h-4 w-4" /> Invite someone
            </Button>
          )
        }
      />

      <div className="mb-6 grid gap-3 sm:grid-cols-3">
        <StatTile
          label="Seats used"
          value={limit ? `${active.length} of ${limit}` : String(active.length)}
          sub={limit ? (s?.can_add_user ? `${Math.max(limit - active.length - (s?.open_invitations ?? 0), 0)} free` : "All seats in use") : "Active people"}
          tone={s?.seats_over_limit ? "danger" : undefined}
        />
        <StatTile label="Open invitations" value={String(s?.open_invitations ?? invites.data?.length ?? 0)} sub="Waiting to join" />
        <StatTile label={ws.terms.WorkerPlural} value={String(fieldWorkers.length)} sub="Use the iPhone app" />
      </div>

      {s?.seats_over_limit && (
        <p className="mb-6 rounded-xl bg-destructive/10 px-4 py-3 text-sm text-destructive">
          Your plan covers {limit} people and {active.length} are active. Suspend {s.users_to_deactivate} to stay within your plan, or the owner can
          choose a bigger plan.
        </p>
      )}
      {s && !s.can_add_user && !s.seats_over_limit && canManage && (
        <p className="mb-6 rounded-xl bg-brand-orange-tint px-4 py-3 text-sm text-brand-orange-text">
          Every seat on your plan is in use. {ws.me.role === "owner" ? "Choose a bigger plan under Billing to invite more people." : "Ask the owner to choose a bigger plan."}
        </p>
      )}

      <Section title="People">
        {team.isLoading ? (
          <LoadingRows count={5} />
        ) : team.error ? (
          <p className="p-6 text-sm text-destructive">{(team.error as Error).message}</p>
        ) : list.length === 0 ? (
          <EmptyState icon={UsersRound} title="No one here yet" />
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full min-w-[760px] text-sm">
              <thead className="bg-secondary/50">
                <tr className="text-left">
                  <th className="section-label px-4 py-3">Name</th>
                  <th className="section-label w-40 px-4 py-3">Role</th>
                  <th className="section-label w-32 px-4 py-3">Status</th>
                  <th className="section-label w-40 px-4 py-3">Last active</th>
                  <th className="w-12 px-4 py-3" />
                </tr>
              </thead>
              <tbody className="divide-y divide-border">
                {list.map((m) => {
                  const self = m.id === ws.me.id;
                  const editable = canManage && !self && m.role !== "owner";
                  return (
                    <tr key={m.id} className={m.status === "suspended" ? "opacity-60" : undefined}>
                      <td className="px-4 py-3">
                        <div className="flex items-center gap-3">
                          <WorkerAvatar name={m.name} id={m.id} size={34} />
                          <div className="min-w-0">
                            <p className="truncate font-medium">
                              {m.name} {self && <span className="text-xs font-normal text-meta">(you)</span>}
                            </p>
                            <p className="truncate text-xs text-muted-foreground">
                              {m.email}
                              {m.phone ? ` · ${m.phone}` : ""}
                            </p>
                          </div>
                        </div>
                      </td>
                      <td className="px-4 py-3">
                        {editable ? (
                          <Select value={m.role} onValueChange={(r) => void run(() => setMemberRole(m.id, r as Role), `${m.name} is now ${ROLE_TITLE[r as Role]}.`)}>
                            <SelectTrigger className="h-9 w-36">
                              <SelectValue />
                            </SelectTrigger>
                            <SelectContent>
                              {INVITABLE_ROLES.map((r) => (
                                <SelectItem key={r} value={r}>
                                  {ROLE_TITLE[r]}
                                </SelectItem>
                              ))}
                            </SelectContent>
                          </Select>
                        ) : (
                          <span className="font-medium">{ROLE_TITLE[m.role]}</span>
                        )}
                      </td>
                      <td className="px-4 py-3">
                        <ToneBadge tone={m.status === "active" ? "success" : m.status === "invited" ? "info" : "neutral"}>
                          {m.status === "active" ? "Active" : m.status === "invited" ? "Invited" : "Suspended"}
                        </ToneBadge>
                      </td>
                      <td className="px-4 py-3 text-muted-foreground">{m.last_active_at ? relativeAgo(m.last_active_at) : "—"}</td>
                      <td className="px-4 py-3 text-right">
                        {(editable || (canManage && self)) && (
                          <DropdownMenu>
                            <DropdownMenuTrigger className="rounded-lg p-1.5 text-muted-foreground hover:bg-secondary" aria-label="More">
                              <MoreHorizontal className="h-4 w-4" />
                            </DropdownMenuTrigger>
                            <DropdownMenuContent align="end">
                              <DropdownMenuItem onClick={() => setEditing(m)}>Edit name and phone</DropdownMenuItem>
                              {editable && (
                                <>
                                  <DropdownMenuSeparator />
                                  {m.status === "suspended" ? (
                                    <DropdownMenuItem
                                      disabled={s ? !s.can_add_user : false}
                                      onClick={() => void run(() => setMemberStatus(m.id, "active"), `${m.name} can sign in again.`)}
                                    >
                                      Reactivate
                                    </DropdownMenuItem>
                                  ) : (
                                    <DropdownMenuItem className="text-destructive" onClick={() => setSuspend(m)}>
                                      Suspend access
                                    </DropdownMenuItem>
                                  )}
                                </>
                              )}
                            </DropdownMenuContent>
                          </DropdownMenu>
                        )}
                      </td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        )}
      </Section>

      {canManage && (
        <Section title="Open invitations" className="mt-6" action={<span className="text-xs text-meta">Links expire automatically</span>}>
          {invites.isLoading ? (
            <LoadingRows count={2} />
          ) : (invites.data ?? []).length === 0 ? (
            <p className="px-5 py-4 text-sm text-muted-foreground">No invitations waiting.</p>
          ) : (
            <ul className="divide-y divide-border">
              {(invites.data ?? []).map((i) => {
                const expired = new Date(i.expires_at).getTime() < Date.now();
                return (
                  <li key={i.id} className="flex items-center gap-4 px-5 py-3 text-sm">
                    <Mail className="h-4 w-4 shrink-0 text-primary" />
                    <div className="min-w-0 flex-1">
                      <p className="truncate font-medium">{i.email}</p>
                      <p className="text-xs text-muted-foreground">
                        {ROLE_TITLE[i.role]} · sent {shortDate(i.created_at)} · {expired ? "expired" : `expires ${shortDate(i.expires_at)}`}
                      </p>
                    </div>
                    {expired && <ToneBadge tone="warning">Expired</ToneBadge>}
                    <Button variant="ghost" size="sm" className="text-destructive" onClick={() => setRevoke(i.id)}>
                      Revoke
                    </Button>
                  </li>
                );
              })}
            </ul>
          )}
        </Section>
      )}

      {fieldWorkers.length > 0 && (
        <Section title={`What ${ws.terms.workerPlural} can do with money`} className="mt-6">
          <p className="border-b border-border px-5 py-3 text-sm text-muted-foreground">
            By default {ws.terms.workerPlural} can't create invoices or take payments in the iPhone app. Turn these on per person.
          </p>
          <ul className="divide-y divide-border">
            {fieldWorkers.map((m) => {
              const g = grants.data?.get(m.id);
              const inv = g?.can_invoice ?? false;
              const col = g?.can_collect_payments ?? false;
              return (
                <li key={m.id} className="flex flex-wrap items-center gap-4 px-5 py-3 text-sm">
                  <WorkerAvatar name={m.name} id={m.id} size={30} />
                  <p className="min-w-[160px] flex-1 font-medium">{m.name}</p>
                  <label className="flex items-center gap-2 text-muted-foreground">
                    <Switch
                      checked={inv}
                      disabled={!canManage}
                      onCheckedChange={(v) => void run(() => setFinancialGrant(m.id, v, col), "Saved.")}
                    />
                    Create invoices
                  </label>
                  <label className="flex items-center gap-2 text-muted-foreground">
                    <Switch
                      checked={col}
                      disabled={!canManage}
                      onCheckedChange={(v) => void run(() => setFinancialGrant(m.id, inv, v), "Saved.")}
                    />
                    Take payments
                  </label>
                </li>
              );
            })}
          </ul>
        </Section>
      )}

      {canManage && <InviteDialog open={inviting} onOpenChange={setInviting} onDone={() => void refresh()} />}
      {editing && <EditDialog member={editing} onClose={() => setEditing(null)} onSaved={() => void refresh()} />}
      <Confirm
        open={!!suspend}
        onOpenChange={(o) => !o && setSuspend(null)}
        title={`Suspend ${suspend?.name ?? ""}?`}
        body="They'll be signed out and can't use the web or the iPhone app until you reactivate them. Their jobs and history stay."
        action="Suspend"
        onConfirm={() => suspend && void run(() => setMemberStatus(suspend.id, "suspended"), `${suspend.name} is suspended.`)}
      />
      <Confirm
        open={!!revoke}
        onOpenChange={(o) => !o && setRevoke(null)}
        title="Revoke this invitation?"
        body="The link stops working straight away."
        action="Revoke"
        onConfirm={() => revoke && void run(() => revokeInvitation(revoke), "Invitation revoked.")}
      />
    </Page>
  );
}

function InviteDialog({ open, onOpenChange, onDone }: { open: boolean; onOpenChange: (o: boolean) => void; onDone: () => void }) {
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [role, setRole] = useState<Role>("fieldWorker");
  const [days, setDays] = useState(7);
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState<InviteResult | null>(null);

  const close = (o: boolean) => {
    if (!o) {
      setName("");
      setEmail("");
      setRole("fieldWorker");
      setDays(7);
      setResult(null);
    }
    onOpenChange(o);
  };

  const submit = async () => {
    setBusy(true);
    try {
      const r = await invite(email, role, days, name);
      setResult(r);
      onDone();
      if (r.emailed) toast.success(r.detail);
    } catch (err) {
      toast.error((err as Error).message);
    } finally {
      setBusy(false);
    }
  };

  return (
    <Dialog open={open} onOpenChange={close}>
      <DialogContent className="sm:max-w-[480px]">
        <DialogHeader>
          <DialogTitle>{result ? "Invitation ready" : "Invite someone"}</DialogTitle>
          <DialogDescription>
            {result ? result.detail : "They'll get an email with a link to join your company. Field workers then use the iPhone app."}
          </DialogDescription>
        </DialogHeader>
        {result ? (
          result.link && (
            <div className="flex gap-2">
              <Input readOnly value={result.link} className="font-mono text-xs" />
              <Button
                variant="outline"
                className="gap-1.5"
                onClick={() => {
                  void navigator.clipboard.writeText(result.link!);
                  toast.success("Link copied.");
                }}
              >
                <Copy className="h-4 w-4" /> Copy
              </Button>
            </div>
          )
        ) : (
          <div className="grid gap-4">
            <Field label="Name (optional)">
              <Input value={name} onChange={(e) => setName(e.target.value)} placeholder="Jordan Ellis" />
            </Field>
            <Field label="Email">
              <Input type="email" value={email} onChange={(e) => setEmail(e.target.value)} placeholder="jordan@example.com" autoFocus />
            </Field>
            <Field label="Role" hint={ROLE_SUMMARY[role]}>
              <Select value={role} onValueChange={(r) => setRole(r as Role)}>
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {INVITABLE_ROLES.map((r) => (
                    <SelectItem key={r} value={r}>
                      {ROLE_TITLE[r]}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </Field>
            <Field label="Link expires after">
              <Select value={String(days)} onValueChange={(d) => setDays(Number(d))}>
                <SelectTrigger>
                  <SelectValue />
                </SelectTrigger>
                <SelectContent>
                  {EXPIRY_OPTIONS.map((d) => (
                    <SelectItem key={d} value={String(d)}>
                      {d} days
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </Field>
          </div>
        )}
        <DialogFooter>
          {result ? (
            <Button onClick={() => close(false)}>Done</Button>
          ) : (
            <>
              <Button variant="ghost" onClick={() => close(false)}>
                Cancel
              </Button>
              <Button onClick={() => void submit()} disabled={busy || !email.trim()} className="gap-1.5 bg-brand-orange hover:bg-brand-orange/90">
                <Plus className="h-4 w-4" /> {busy ? "Sending…" : "Send invitation"}
              </Button>
            </>
          )}
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}

function EditDialog({ member, onClose, onSaved }: { member: Member; onClose: () => void; onSaved: () => void }) {
  const [name, setName] = useState(member.name);
  const [phone, setPhone] = useState(member.phone ?? "");
  const [busy, setBusy] = useState(false);
  const save = async () => {
    setBusy(true);
    try {
      await saveMemberDetails(member.id, name, phone);
      toast.success("Saved.");
      onSaved();
      onClose();
    } catch (err) {
      toast.error((err as Error).message);
    } finally {
      setBusy(false);
    }
  };
  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent className="sm:max-w-[420px]">
        <DialogHeader>
          <DialogTitle>Edit {member.name}</DialogTitle>
          <DialogDescription>{member.email}</DialogDescription>
        </DialogHeader>
        <div className="grid gap-4">
          <Field label="Name">
            <Input value={name} onChange={(e) => setName(e.target.value)} />
          </Field>
          <Field label="Phone">
            <Input value={phone} onChange={(e) => setPhone(e.target.value)} placeholder="(555) 010-2030" />
          </Field>
        </div>
        <DialogFooter>
          <Button variant="ghost" onClick={onClose}>
            Cancel
          </Button>
          <Button onClick={() => void save()} disabled={busy}>
            Save
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
