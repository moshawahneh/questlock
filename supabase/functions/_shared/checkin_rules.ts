// Pure check-in rules used by verify-checkin. No I/O, so they are unit-tested with `deno test`.

export const MAX_ATTEMPTS = 5;

export type StubDecision =
  | { ok: true; status: "verified" | "late" }
  | { ok: false; code: "too_early" | "too_many_attempts"; message: string; httpStatus: number };

/**
 * Phase 3 stub decision (no AI yet): inside the lock window → verified, after the deadline → late,
 * before the window opens or after 5 attempts → rejected.
 */
export function decideStub(input: { now: Date; opensAt: Date; deadlineAt: Date; attemptsSoFar: number }): StubDecision {
  if (input.now < input.opensAt) {
    return {
      ok: false,
      code: "too_early",
      message: "Check-in opens when your apps lock.",
      httpStatus: 409,
    };
  }
  if (input.attemptsSoFar >= MAX_ATTEMPTS) {
    return {
      ok: false,
      code: "too_many_attempts",
      message: `You've used all ${MAX_ATTEMPTS} attempts for today.`,
      httpStatus: 429,
    };
  }
  return { ok: true, status: input.now <= input.deadlineAt ? "verified" : "late" };
}

/** Where the app must have uploaded the two photos (lowercase ids, matching auth.uid()::text). */
export function expectedPhotoPaths(userId: string, localDate: string, checkinId: string): { front: string; back: string } {
  const base = `${userId.toLowerCase()}/${localDate}/${checkinId.toLowerCase()}`;
  return { front: `${base}_front.jpg`, back: `${base}_back.jpg` };
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export function isUuid(value: unknown): value is string {
  return typeof value === "string" && UUID.test(value);
}

/**
 * The app sends the 64-bit perceptual hash as 16 hex digits. Postgres `bigint` is signed, so values
 * with the top bit set are stored as negative numbers (same bits). Returns the decimal string, or null.
 */
export function phashToBigint(hex: unknown): string | null {
  if (typeof hex !== "string" || !/^[0-9a-f]{16}$/i.test(hex)) return null;
  let value = BigInt("0x" + hex);
  if (value >= 1n << 63n) value -= 1n << 64n;
  return value.toString();
}
