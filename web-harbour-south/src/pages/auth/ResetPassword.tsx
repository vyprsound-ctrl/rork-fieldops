import { useEffect, useState } from "react";
import { useNavigate } from "react-router-dom";
import { Loader2 } from "lucide-react";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { supabase } from "@/lib/supabase";
import { AuthLayout } from "./AuthLayout";

export default function ResetPassword() {
  const navigate = useNavigate();
  const [ready, setReady] = useState(false);
  const [password, setPassword] = useState("");
  const [confirm, setConfirm] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => setReady(!!data.session));
    const { data } = supabase.auth.onAuthStateChange((_e, session) => setReady(!!session));
    return () => data.subscription.unsubscribe();
  }, []);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (password.length < 8) return setError("Use at least 8 characters.");
    if (password !== confirm) return setError("The two passwords don't match.");
    setBusy(true);
    setError(null);
    const { error } = await supabase.auth.updateUser({ password });
    setBusy(false);
    if (error) setError(/same|different/i.test(error.message) ? "Choose a password you haven't used before." : "Couldn't update the password. Request a new link.");
    else navigate("/", { replace: true });
  };

  return (
    <AuthLayout>
      <h2 className="text-[28px] font-bold tracking-tight">Choose a new password</h2>
      <p className="mt-1.5 text-sm text-muted-foreground">It works on the web and the iPhone app.</p>
      {!ready ? (
        <p className="mt-8 rounded-xl bg-secondary px-4 py-3 text-sm text-muted-foreground">
          Open this page from the link in your reset email. Links expire after an hour.
        </p>
      ) : (
        <form onSubmit={submit} className="mt-8 space-y-5">
          <div className="space-y-2">
            <Label htmlFor="pw">New password</Label>
            <Input id="pw" type="password" autoComplete="new-password" value={password} onChange={(e) => setPassword(e.target.value)} className="h-12 bg-card" />
          </div>
          <div className="space-y-2">
            <Label htmlFor="pw2">Confirm password</Label>
            <Input id="pw2" type="password" autoComplete="new-password" value={confirm} onChange={(e) => setConfirm(e.target.value)} className="h-12 bg-card" />
          </div>
          {error && <p className="text-sm text-destructive">{error}</p>}
          <Button type="submit" disabled={busy} className="h-12 w-full bg-brand-orange text-[15px] font-semibold hover:bg-brand-orange/90">
            {busy ? <Loader2 className="h-4 w-4 animate-spin" /> : "Save password"}
          </Button>
        </form>
      )}
    </AuthLayout>
  );
}
