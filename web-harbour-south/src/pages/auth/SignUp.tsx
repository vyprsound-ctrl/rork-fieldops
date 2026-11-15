import { useState } from "react";
import { Link } from "react-router-dom";
import { Eye, EyeOff, Loader2, MailCheck } from "lucide-react";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { supabase } from "@/lib/supabase";
import { APP_BASE } from "@/lib/site";
import { localTimeZone } from "@/lib/signup";
import { AuthLayout } from "./AuthLayout";
import { CompanyFields, EMPTY_COMPANY, setupFrom } from "./CompanyFields";

export default function SignUp() {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [show, setShow] = useState(false);
  const [company, setCompany] = useState(EMPTY_COMPANY);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [sentTo, setSentTo] = useState<string | null>(null);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    if (password.length < 8) return setError("Use at least 8 characters for your password.");
    if (!company.companyName.trim() || !company.ownerName.trim()) return setError("Add your name and your company's name.");
    setBusy(true);
    const address = email.trim();
    // Same pending-setup metadata as the iPhone app, so whichever device
    // signs in first after confirming creates the company.
    const { data, error } = await supabase.auth.signUp({
      email: address,
      password,
      options: {
        data: { pending_company_setup: true, ...setupFrom(company, localTimeZone()) },
        emailRedirectTo: `${window.location.origin}${APP_BASE}/billing`,
      },
    });
    setBusy(false);
    if (error) {
      setError(
        /already/i.test(error.message)
          ? "There's already an account with that email. Sign in instead."
          : /password/i.test(error.message)
            ? "Choose a stronger password: at least 8 characters, mixing letters and numbers."
            : "Couldn't create your account right now. Try again in a moment.",
      );
      return;
    }
    // With email confirmation on, there's no session until they click the link.
    if (!data.session) setSentTo(address);
  };

  if (sentTo) {
    return (
      <AuthLayout>
        <div className="mb-5 flex h-14 w-14 items-center justify-center rounded-2xl bg-primary-tint text-primary">
          <MailCheck className="h-6 w-6" />
        </div>
        <h2 className="text-[28px] font-bold tracking-tight">Check your email</h2>
        <p className="mt-2 text-[15px] leading-relaxed text-muted-foreground">
          We sent a confirmation link to <span className="font-semibold text-foreground">{sentTo}</span>. Open it to finish
          setting up {company.companyName.trim() || "your company"} and choose a plan.
        </p>
        <Button asChild variant="outline" className="mt-8">
          <Link to="/">Back to sign in</Link>
        </Button>
      </AuthLayout>
    );
  }

  return (
    <AuthLayout>
      <h2 className="text-[28px] font-bold tracking-tight">Create your company</h2>
      <p className="mt-1.5 text-sm text-muted-foreground">
        You'll be the owner. Choose a plan next, then invite your team.
      </p>

      <form onSubmit={submit} className="mt-8 space-y-5">
        <CompanyFields value={company} onChange={setCompany} />
        <div className="space-y-2">
          <Label htmlFor="email">Work email</Label>
          <Input
            id="email"
            type="email"
            autoComplete="email"
            required
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            className="h-12 bg-card text-[15px]"
            placeholder="you@company.com"
          />
        </div>
        <div className="space-y-2">
          <Label htmlFor="password">Password</Label>
          <div className="relative">
            <Input
              id="password"
              type={show ? "text" : "password"}
              autoComplete="new-password"
              required
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              className="h-12 bg-card pr-11 text-[15px]"
            />
            <button
              type="button"
              onClick={() => setShow((s) => !s)}
              className="absolute right-3 top-1/2 -translate-y-1/2 text-meta hover:text-foreground"
              aria-label={show ? "Hide password" : "Show password"}
            >
              {show ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
            </button>
          </div>
        </div>

        {error && <p className="rounded-xl bg-[hsl(6_80%_95%)] px-3 py-2.5 text-sm text-destructive">{error}</p>}

        <Button type="submit" disabled={busy} className="press h-12 w-full bg-brand-orange text-[15px] font-semibold hover:bg-brand-orange/90">
          {busy ? <Loader2 className="h-4 w-4 animate-spin" /> : "Create account"}
        </Button>
      </form>

      <p className="mt-6 text-center text-sm text-muted-foreground">
        Already use Harbour South?{" "}
        <Link to="/" className="font-medium text-primary hover:underline">
          Sign in
        </Link>
      </p>
      <p className="mt-4 text-center text-xs text-muted-foreground">
        Joining an existing company? Ask the owner to invite you instead.
      </p>
    </AuthLayout>
  );
}
