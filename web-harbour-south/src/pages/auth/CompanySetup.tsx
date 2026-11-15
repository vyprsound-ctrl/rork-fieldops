import { useState } from "react";
import { Building2, Loader2 } from "lucide-react";

import { Button } from "@/components/ui/button";
import { createCompany, useSession } from "@/lib/session";
import { localTimeZone } from "@/lib/signup";
import { AuthLayout } from "./AuthLayout";
import { CompanyFields, EMPTY_COMPANY, setupFrom } from "./CompanyFields";

/** A login with no company: wait for an invite, or found a new company as its owner. */
export default function CompanySetup({ email }: { email: string }) {
  const { signOut, reload } = useSession();
  const [creating, setCreating] = useState(false);
  const [company, setCompany] = useState(EMPTY_COMPANY);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!company.companyName.trim() || !company.ownerName.trim()) return setError("Add your name and your company's name.");
    setError(null);
    setBusy(true);
    try {
      await createCompany(setupFrom(company, localTimeZone()));
      reload();
    } catch (err) {
      setError((err as Error).message);
      setBusy(false);
    }
  };

  return (
    <AuthLayout>
      <div className="mb-5 flex h-14 w-14 items-center justify-center rounded-2xl bg-primary-tint text-primary">
        <Building2 className="h-6 w-6" />
      </div>
      {creating ? (
        <>
          <h2 className="text-[28px] font-bold tracking-tight">Create your company</h2>
          <p className="mt-1.5 text-sm text-muted-foreground">You'll be the owner. Choose a plan next.</p>
          <form onSubmit={submit} className="mt-8 space-y-5">
            <CompanyFields value={company} onChange={setCompany} />
            {error && <p className="rounded-xl bg-[hsl(6_80%_95%)] px-3 py-2.5 text-sm text-destructive">{error}</p>}
            <div className="flex gap-2">
              <Button type="submit" disabled={busy} className="press h-12 flex-1 bg-brand-orange text-[15px] font-semibold hover:bg-brand-orange/90">
                {busy ? <Loader2 className="h-4 w-4 animate-spin" /> : "Create company"}
              </Button>
              <Button type="button" variant="outline" className="h-12" onClick={() => setCreating(false)}>
                Back
              </Button>
            </div>
          </form>
        </>
      ) : (
        <>
          <h2 className="text-[28px] font-bold tracking-tight">No company found</h2>
          <p className="mt-2 text-[15px] leading-relaxed text-muted-foreground">
            <span className="font-semibold text-foreground">{email}</span> isn't part of a company yet. If you work for a
            company that already uses Harbour South, ask the owner to invite you. Otherwise, create your own.
          </p>
          <div className="mt-8 flex gap-2">
            <Button onClick={() => setCreating(true)} className="press bg-brand-orange hover:bg-brand-orange/90">
              Create a company
            </Button>
            <Button variant="outline" onClick={() => void signOut()}>
              Sign out
            </Button>
          </div>
        </>
      )}
    </AuthLayout>
  );
}
