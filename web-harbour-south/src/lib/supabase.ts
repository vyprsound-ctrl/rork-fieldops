import { createClient } from "@supabase/supabase-js";

const url = import.meta.env.EXPO_PUBLIC_SUPABASE_URL as string | undefined;
const anonKey = import.meta.env.EXPO_PUBLIC_SUPABASE_ANON_KEY as string | undefined;

export const isConfigured = Boolean(url && anonKey);

/**
 * The same Supabase project the iPhone app uses. Only the public anon key is
 * shipped; every row is protected by the database's row-level security, so the
 * web app can only ever see what the signed-in person's role allows.
 */
export const supabase = createClient(url ?? "https://invalid.supabase.co", anonKey ?? "missing", {
  auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true },
});
