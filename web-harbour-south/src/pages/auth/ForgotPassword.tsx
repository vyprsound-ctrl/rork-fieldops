import { useState } from "react";
import { Link } from "react-router-dom";
import { ArrowLeft, Loader2, MailCheck } from "lucide-react";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { supabase } from "@/lib/supabase";
import { AuthLayout } from "./AuthLayout";

export default function ForgotPassword() {
  const [email, setEmail] = useState("");
  const [busy, setBusy] = useState(false);
  const [sent, setSent] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setBusy(true);
    setError(null);
    const { error } = await supabase.auth.resetPasswordForEmail(email.trim(), {
      redirectTo: `${window.location.origin}/reset-password`,
    });
    setBusy(false);
    // Don't reveal whether an account exists; only surface rate limits.
    if (error && /rate|seconds/i.test(error.message)) setError("Too many requests. Wait a minute and try again.");
    else setSent(true);
  };

  return (
    <AuthLayout>
      <Link to="/" className="mb-8 inline-flex items-center gap-1.5 text-sm font-medium text-primary hover:underline">
        <ArrowLeft className="h-4 w-4" /> Back to sign in
      </Link>
      {sent ? (
        <div>
          <div className="mb-5 flex h-14 w-14 items-center justify-center rounded-2xl bg-[hsl(147_55%_93%)] text-success">
            <MailCheck className="h-6 w-6" />
          </div>
          <h2 className="text-[28px] font-bold tracking-tight">Check your email</h2>
          <p className="mt-2 text-sm text-muted-foreground">
            If {email} has a Harbour South account, a link to set a new password is on its way. It works for the iPhone app too.
          </p>
        </div>
      ) : (
        <>
          <h2 className="text-[28px] font-bold tracking-tight">Reset your password</h2>
          <p className="mt-1.5 text-sm text-muted-foreground">We'll email you a link to choose a new one.</p>
          <form onSubmit={submit} className="mt-8 space-y-5">
            <div className="space-y-2">
              <Label htmlFor="email">Email</Label>
              <Input id="email" type="email" required value={email} onChange={(e) => setEmail(e.target.value)} className="h-12 bg-card" />
            </div>
            {error && <p className="text-sm text-destructive">{error}</p>}
            <Button type="submit" disabled={busy} className="h-12 w-full bg-brand-orange text-[15px] font-semibold hover:bg-brand-orange/90">
              {busy ? <Loader2 className="h-4 w-4 animate-spin" /> : "Send reset link"}
            </Button>
          </form>
        </>
      )}
    </AuthLayout>
  );
}
