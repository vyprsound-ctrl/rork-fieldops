import { useState } from "react";
import { Link } from "react-router-dom";
import { Eye, EyeOff, Loader2 } from "lucide-react";

import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { isConfigured, supabase } from "@/lib/supabase";
import { AuthLayout } from "./AuthLayout";

export default function SignIn() {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [show, setShow] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const submit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    setBusy(true);
    const { error } = await supabase.auth.signInWithPassword({ email: email.trim(), password });
    setBusy(false);
    if (error) {
      setError(
        /invalid/i.test(error.message)
          ? "That email and password don't match. Use the same login as the iPhone app."
          : /confirm/i.test(error.message)
            ? "Confirm your email address first, then sign in."
            : "Couldn't sign in right now. Try again in a moment.",
      );
    }
  };

  return (
    <AuthLayout>
      <h2 className="text-[28px] font-bold tracking-tight">Sign in</h2>
      <p className="mt-1.5 text-sm text-muted-foreground">Use the same email and password as the Harbour South app.</p>

      {!isConfigured && (
        <p className="mt-6 rounded-xl bg-[hsl(6_80%_95%)] px-3 py-2 text-sm text-destructive">The app isn't connected to its server.</p>
      )}

      <form onSubmit={submit} className="mt-8 space-y-5">
        <div className="space-y-2">
          <Label htmlFor="email">Email</Label>
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
          <div className="flex items-center justify-between">
            <Label htmlFor="password">Password</Label>
            <Link to="/forgot-password" className="text-sm font-medium text-primary hover:underline">
              Forgot password?
            </Link>
          </div>
          <div className="relative">
            <Input
              id="password"
              type={show ? "text" : "password"}
              autoComplete="current-password"
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
          {busy ? <Loader2 className="h-4 w-4 animate-spin" /> : "Sign in"}
        </Button>
      </form>

      <p className="mt-10 text-center text-xs text-muted-foreground">
        For owners, admins, dispatchers and accounts. Engineers use the iPhone app.
      </p>
    </AuthLayout>
  );
}
