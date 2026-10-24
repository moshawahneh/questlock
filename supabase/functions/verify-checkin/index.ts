// POST /functions/v1/verify-checkin
// Body: { challenge_id, checkin_id, front_path, back_path, phash }
// Body also carries `observations`: what Apple's on-device classifier saw (docs/decisions/004).
// The app uploads both photos first, then calls this. The server checks ownership, the time window,
// the attempt count and reused photos, then applies the decision rule and records the attempt.

import { checkTiming, expectedPhotoPaths, isUuid, phashToBigint } from "../_shared/checkin_rules.ts";
import { decide, DUPLICATE_LOOKBACK, isDuplicate, parseObservations, rejectionMessage } from "../_shared/decision.ts";
import { adminClient, json, requireUser } from "../_shared/supabase.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);
  const admin = adminClient();
  const user = await requireUser(req, admin);
  if (user instanceof Response) return user;

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "bad_request", message: "Expected a JSON body." }, 400);
  }
  const { challenge_id, checkin_id, front_path, back_path } = body;
  const phash = phashToBigint(body.phash);
  const observations = parseObservations(body.observations);
  if (!isUuid(challenge_id) || !isUuid(checkin_id) || phash === null || observations === null) {
    return json({ error: "bad_request", message: "Missing or invalid challenge_id, checkin_id, phash or observations." }, 400);
  }

  // 1. The challenge must be the caller's.
  const { data: challenge, error: challengeError } = await admin
    .from("challenges")
    .select("id, user_id, habit_id, local_date, target_label, opens_at, deadline_at")
    .eq("id", challenge_id)
    .eq("user_id", user.id)
    .maybeSingle();
  if (challengeError) return json({ error: "server_error", message: challengeError.message }, 500);
  if (!challenge) return json({ error: "not_found", message: "That challenge doesn't exist." }, 404);

  // Already verified today: nothing more to do.
  const { data: result } = await admin
    .from("daily_results")
    .select("status")
    .eq("user_id", user.id)
    .eq("habit_id", challenge.habit_id)
    .eq("local_date", challenge.local_date)
    .maybeSingle();
  if (result?.status === "verified") {
    return json({ status: "verified", already: true, unlocked: true, deadline_at: challenge.deadline_at });
  }

  // 2. Time window and attempt count.
  const { count, error: countError } = await admin
    .from("checkins")
    .select("id", { count: "exact", head: true })
    .eq("challenge_id", challenge.id);
  if (countError) return json({ error: "server_error", message: countError.message }, 500);
  const attemptsSoFar = count ?? 0;
  const timing = checkTiming({
    now: new Date(),
    opensAt: new Date(challenge.opens_at),
    deadlineAt: new Date(challenge.deadline_at),
    attemptsSoFar,
  });
  if (!timing.ok) return json({ error: timing.code, message: timing.message }, timing.httpStatus);

  // 3. Both photos must be in the caller's folder for this check-in.
  const expected = expectedPhotoPaths(user.id, challenge.local_date, checkin_id);
  if (front_path !== expected.front || back_path !== expected.back) {
    return json({ error: "bad_request", message: "Photo paths don't match this check-in." }, 400);
  }
  const folder = `${user.id}/${challenge.local_date}`;
  const { data: files, error: listError } = await admin.storage.from("checkins").list(folder, {
    search: checkin_id.toLowerCase(),
  });
  if (listError) return json({ error: "server_error", message: listError.message }, 500);
  const names = new Set((files ?? []).map((f) => `${folder}/${f.name}`));
  if (!names.has(expected.front) || !names.has(expected.back)) {
    return json({ error: "photos_missing", message: "Both photos need to finish uploading first." }, 400);
  }

  // 4. Reused photo? Compare with the user's recent hashes. Read as text: bigint loses precision as a JS number.
  const { data: recentRows, error: recentError } = await admin
    .from("checkins")
    .select("phash::text")
    .eq("user_id", user.id)
    .not("phash", "is", null)
    .order("created_at", { ascending: false })
    .limit(DUPLICATE_LOOKBACK);
  if (recentError) return json({ error: "server_error", message: recentError.message }, 500);
  const recent = (recentRows ?? []).map((r) => BigInt((r as { phash: string }).phash));
  const duplicate = isDuplicate(BigInt(phash), recent);

  // 5. The decision rule (in code, not in the classifier).
  const verdict = decide(observations, duplicate);
  const status = verdict === "accept" ? timing.status : "rejected";

  // 6. Record the attempt. The unique (challenge_id, attempt_no) stops two requests racing.
  const { error: insertError } = await admin.from("checkins").insert({
    id: checkin_id,
    challenge_id: challenge.id,
    user_id: user.id,
    local_date: challenge.local_date,
    attempt_no: attemptsSoFar + 1,
    status,
    front_path: expected.front,
    back_path: expected.back,
    phash,
    ai_result: { source: "apple_vision", verdict, observations },
    rejection_reason: verdict === "accept" ? null : verdict,
  });
  if (insertError) {
    const conflict = insertError.code === "23505";
    return json({ error: conflict ? "conflict" : "server_error", message: insertError.message }, conflict ? 409 : 500);
  }

  if (verdict !== "accept") {
    return json({
      status: "rejected",
      reason: verdict,
      message: `${rejectionMessage(verdict, challenge.target_label)} (${4 - attemptsSoFar} attempts left today)`,
      attempt_no: attemptsSoFar + 1,
      unlocked: false,
      deadline_at: challenge.deadline_at,
    });
  }

  // 7. The day's result. Streaks are recomputed from daily_results in Phase 5.
  const { error: resultError } = timing.status === "verified"
    ? await admin.from("daily_results").upsert(
      { user_id: user.id, habit_id: challenge.habit_id, local_date: challenge.local_date, status: "verified" },
      { onConflict: "user_id,habit_id,local_date" },
    )
    : await admin.from("daily_results").upsert(
      { user_id: user.id, habit_id: challenge.habit_id, local_date: challenge.local_date, status: "missed", late_posted: true },
      { onConflict: "user_id,habit_id,local_date" },
    );
  if (resultError) return json({ error: "server_error", message: resultError.message }, 500);

  return json({
    status: timing.status,
    attempt_no: attemptsSoFar + 1,
    unlocked: timing.status === "verified",
    deadline_at: challenge.deadline_at,
  });
});
