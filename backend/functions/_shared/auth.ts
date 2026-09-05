import { createClient, type SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

/// This project uses native Supabase Auth, so tokens are verified with
/// supabase.auth.getUser() rather than against Rork's JWKS.

export const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

export class AuthError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "AuthError";
  }
}

export interface AuthedRequest {
  userId: string;
  /// Scoped to the caller: every read through this client is subject to RLS,
  /// so it is the tenant boundary, not a convenience.
  supabase: SupabaseClient;
}

export function createUserClient(req: Request): SupabaseClient {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } } },
  );
}

/// Bypasses RLS. Only ever used for writes the caller has already been
/// authorised to make but whose policy belongs to another role (the delivery
/// ledger), and for the public invoice page, which has no caller at all.
export function createAdminClient(): SupabaseClient {
  return createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );
}

export async function requireAuth(req: Request): Promise<AuthedRequest> {
  const supabase = createUserClient(req);
  const { data, error } = await supabase.auth.getUser();
  if (error || !data.user) throw new AuthError("Unauthorized");
  return { userId: data.user.id, supabase };
}

export function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
