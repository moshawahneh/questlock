import { createClient, type SupabaseClient, type User } from "@supabase/supabase-js";

/** Service-role client: bypasses RLS. Only ever used inside Edge Functions, never sent to the app. */
export function adminClient(): SupabaseClient {
  return createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

/** The signed-in user from the request's `Authorization: Bearer <access token>`, or an error response. */
export async function requireUser(req: Request, admin: SupabaseClient): Promise<User | Response> {
  const token = req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "");
  if (!token) return json({ error: "not_signed_in", message: "Sign in again." }, 401);
  const { data, error } = await admin.auth.getUser(token);
  if (error || !data.user) return json({ error: "not_signed_in", message: "Sign in again." }, 401);
  return data.user;
}

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
