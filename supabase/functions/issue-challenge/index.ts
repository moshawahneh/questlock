// POST /functions/v1/issue-challenge
// Returns today's challenge for the signed-in user, creating it on first call.
// Response: { challenge: Challenge | null }. null = rest day or no schedule yet.
//
// Phase 3: random target from the allowlist. Phase 4: Claude picks one that fits the user's area.

import { pickRandomTarget } from "../_shared/targets.ts";
import { adminClient, json, requireUser } from "../_shared/supabase.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const admin = adminClient();
  const user = await requireUser(req, admin);
  if (user instanceof Response) return user;

  // Avoid repeating a target from the last week.
  const { data: recent, error: recentError } = await admin
    .from("challenges")
    .select("target_key")
    .eq("user_id", user.id)
    .order("local_date", { ascending: false })
    .limit(7);
  if (recentError) return json({ error: "server_error", message: recentError.message }, 500);

  const target = pickRandomTarget(new Set((recent ?? []).map((r) => r.target_key as string)));
  const { data, error } = await admin.rpc("ensure_challenge", {
    p_user_id: user.id,
    p_target_key: target.key,
    p_target_label: target.label,
    p_hint: target.hint,
  });
  if (error) return json({ error: "server_error", message: error.message }, 500);

  const challenge = Array.isArray(data) ? data[0] ?? null : data;
  return json({ challenge });
});
