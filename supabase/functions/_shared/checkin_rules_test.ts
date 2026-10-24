import { assertEquals } from "jsr:@std/assert@1";
import { checkTiming, expectedPhotoPaths, isUuid, MAX_ATTEMPTS, phashToBigint } from "./checkin_rules.ts";
import { pickRandomTarget, TARGETS } from "./targets.ts";

const opensAt = new Date("2026-10-24T08:00:00Z");
const deadlineAt = new Date("2026-10-24T11:00:00Z");

Deno.test("before the lock opens → too_early", () => {
  const d = checkTiming({ now: new Date("2026-10-24T07:59:59Z"), opensAt, deadlineAt, attemptsSoFar: 0 });
  assertEquals(d.ok ? null : d.code, "too_early");
});

Deno.test("inside the window → verified (both edges)", () => {
  for (const now of [opensAt, new Date("2026-10-24T09:30:00Z"), deadlineAt]) {
    assertEquals(checkTiming({ now, opensAt, deadlineAt, attemptsSoFar: 0 }), { ok: true, status: "verified" });
  }
});

Deno.test("after the deadline → late", () => {
  const d = checkTiming({ now: new Date("2026-10-24T11:00:01Z"), opensAt, deadlineAt, attemptsSoFar: 2 });
  assertEquals(d, { ok: true, status: "late" });
});

Deno.test("the 6th attempt is refused", () => {
  const now = new Date("2026-10-24T09:00:00Z");
  assertEquals(checkTiming({ now, opensAt, deadlineAt, attemptsSoFar: MAX_ATTEMPTS - 1 }).ok, true);
  const d = checkTiming({ now, opensAt, deadlineAt, attemptsSoFar: MAX_ATTEMPTS });
  assertEquals(d.ok ? null : d.code, "too_many_attempts");
});

Deno.test("photo paths are lowercase and per user/date/check-in", () => {
  assertEquals(expectedPhotoPaths("AB-CD", "2026-10-24", "EF-01"), {
    front: "ab-cd/2026-10-24/ef-01_front.jpg",
    back: "ab-cd/2026-10-24/ef-01_back.jpg",
  });
});

Deno.test("isUuid", () => {
  assertEquals(isUuid("11111111-1111-1111-1111-111111111111"), true);
  assertEquals(isUuid("not-a-uuid"), false);
  assertEquals(isUuid(42), false);
});

Deno.test("phash hex → signed bigint keeps the same 64 bits", () => {
  assertEquals(phashToBigint("0000000000000001"), "1");
  assertEquals(phashToBigint("7fffffffffffffff"), "9223372036854775807");
  assertEquals(phashToBigint("8000000000000000"), "-9223372036854775808");
  assertEquals(phashToBigint("ffffffffffffffff"), "-1");
  assertEquals(phashToBigint("xyz"), null);
  assertEquals(phashToBigint("123"), null);
});

Deno.test("random target avoids recent ones while it can", () => {
  const allButBench = new Set(TARGETS.filter((t) => t.key !== "bench").map((t) => t.key));
  assertEquals(pickRandomTarget(allButBench).key, "bench");
  // Everything used recently: still returns something from the list.
  const everything = new Set(TARGETS.map((t) => t.key));
  assertEquals(TARGETS.includes(pickRandomTarget(everything, () => 0.999)), true);
});
