// The check-in decision rule. The phone runs a mirror of it (ios/App/Services/CheckIn/PhotoChecks.swift,
// CheckInDecision) to warn before uploading, but this copy is the one that counts.
//
// The observations come from Apple's on-device classifier (docs/decisions/004). The server can't
// re-check them, so a modified app could lie about them. What the server CAN check itself: the time
// window, the attempt count, and whether the photo is a reused one (perceptual hash).

/** Provisional thresholds: tune with tools/eval-photos on real check-in photos (keep in sync with Swift). */
export const MIN_TARGET_CONFIDENCE = 0.3;
export const MAX_SCREEN_CONFIDENCE = 0.3;
/** Two photos whose 64-bit hashes differ in this many bits or fewer count as the same picture. */
export const DUPLICATE_MAX_DISTANCE = 6;
/** How many of the user's recent photo hashes to compare against. */
export const DUPLICATE_LOOKBACK = 30;

export interface Observations {
  front_has_face: boolean;
  target_confidence: number;
  target_label: string | null;
  screen_confidence: number;
  top_labels: string[];
}

export type Verdict = "accept" | "no_face" | "looks_like_screen" | "target_not_seen" | "duplicate";

export function decide(o: Observations, duplicate: boolean): Verdict {
  if (!o.front_has_face) return "no_face";
  if (o.screen_confidence >= MAX_SCREEN_CONFIDENCE) return "looks_like_screen";
  if (o.target_confidence < MIN_TARGET_CONFIDENCE) return "target_not_seen";
  if (duplicate) return "duplicate";
  return "accept";
}

export function rejectionMessage(verdict: Exclude<Verdict, "accept">, targetLabel: string): string {
  switch (verdict) {
    case "no_face":
      return "We couldn't see your face in the front photo.";
    case "looks_like_screen":
      return "That looks like a photo of a screen. Photograph the real thing.";
    case "target_not_seen":
      return `That doesn't look like ${targetLabel}. Try another angle.`;
    case "duplicate":
      return "That photo looks like one you've already used. Take a new one.";
  }
}

/** Validates the JSON the app sent. Returns null if anything is missing or out of range. */
export function parseObservations(value: unknown): Observations | null {
  if (typeof value !== "object" || value === null) return null;
  const o = value as Record<string, unknown>;
  const inRange = (n: unknown) => typeof n === "number" && Number.isFinite(n) && n >= 0 && n <= 1;
  if (typeof o.front_has_face !== "boolean" || !inRange(o.target_confidence) || !inRange(o.screen_confidence)) {
    return null;
  }
  const label = typeof o.target_label === "string" ? o.target_label.slice(0, 64) : null;
  const top = Array.isArray(o.top_labels)
    ? o.top_labels.filter((l): l is string => typeof l === "string").slice(0, 5).map((l) => l.slice(0, 64))
    : [];
  return {
    front_has_face: o.front_has_face,
    target_confidence: o.target_confidence as number,
    target_label: label,
    screen_confidence: o.screen_confidence as number,
    top_labels: top,
  };
}

const MASK_64 = (1n << 64n) - 1n;

/** Bits that differ between two 64-bit hashes, given as Postgres bigints (signed). */
export function hammingDistance(a: bigint, b: bigint): number {
  let x = (a ^ b) & MASK_64;
  let count = 0;
  while (x > 0n) {
    count += Number(x & 1n);
    x >>= 1n;
  }
  return count;
}

export function isDuplicate(hash: bigint, recent: readonly bigint[], maxDistance = DUPLICATE_MAX_DISTANCE): boolean {
  return recent.some((other) => hammingDistance(hash, other) <= maxDistance);
}
