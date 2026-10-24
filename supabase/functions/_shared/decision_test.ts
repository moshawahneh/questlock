import { assertEquals } from "jsr:@std/assert@1";
import {
  decide,
  hammingDistance,
  isDuplicate,
  type Observations,
  parseObservations,
  rejectionMessage,
} from "./decision.ts";

const good: Observations = {
  front_has_face: true,
  target_confidence: 0.62,
  target_label: "bench",
  screen_confidence: 0.02,
  top_labels: ["outdoor:0.71", "bench:0.62"],
};

Deno.test("a clear photo of the target with a face is accepted", () => {
  assertEquals(decide(good, false), "accept");
});

Deno.test("each failed check gives its own reason, in priority order", () => {
  assertEquals(decide({ ...good, front_has_face: false }, false), "no_face");
  assertEquals(decide({ ...good, screen_confidence: 0.4 }, false), "looks_like_screen");
  assertEquals(decide({ ...good, target_confidence: 0.1 }, false), "target_not_seen");
  assertEquals(decide(good, true), "duplicate");
  // A bench on a laptop screen: the screen wins even though the bench is clearly visible.
  assertEquals(decide({ ...good, screen_confidence: 0.5, target_confidence: 0.9 }, false), "looks_like_screen");
});

Deno.test("thresholds: target needs ≥ 0.3, screen must be < 0.3", () => {
  assertEquals(decide({ ...good, target_confidence: 0.3 }, false), "accept");
  assertEquals(decide({ ...good, target_confidence: 0.29 }, false), "target_not_seen");
  assertEquals(decide({ ...good, screen_confidence: 0.29 }, false), "accept");
  assertEquals(decide({ ...good, screen_confidence: 0.3 }, false), "looks_like_screen");
});

Deno.test("the fan photo from 23 Oct would now be refused", () => {
  // Water-bottle target, but the classifier saw an electric fan and no bottle.
  const fan: Observations = { ...good, target_confidence: 0, target_label: null, top_labels: ["electric_fan:0.81"] };
  assertEquals(decide(fan, false), "target_not_seen");
  assertEquals(rejectionMessage("target_not_seen", "a bottle of water"), "That doesn't look like a bottle of water. Try another angle.");
});

Deno.test("parseObservations rejects missing or out-of-range values", () => {
  assertEquals(parseObservations(good), good);
  assertEquals(parseObservations(null), null);
  assertEquals(parseObservations({ ...good, target_confidence: 1.5 }), null);
  assertEquals(parseObservations({ ...good, screen_confidence: -0.1 }), null);
  assertEquals(parseObservations({ ...good, front_has_face: "yes" }), null);
  assertEquals(parseObservations({ ...good, target_confidence: Number.NaN }), null);
  // Extra or oversized labels are trimmed rather than rejected.
  const parsed = parseObservations({ ...good, top_labels: ["a", "b", "c", "d", "e", "f", 7] });
  assertEquals(parsed?.top_labels, ["a", "b", "c", "d", "e"]);
});

Deno.test("hamming distance works on signed 64-bit values", () => {
  assertEquals(hammingDistance(0n, 0n), 0);
  assertEquals(hammingDistance(0n, -1n), 64); // -1 is all 64 bits set
  assertEquals(hammingDistance(-9223372036854775808n, 0n), 1); // only the top bit
  assertEquals(hammingDistance(0b1011n, 0b0001n), 2);
});

Deno.test("a reused photo is a duplicate; a different one isn't", () => {
  const hash = 0x0f0f0f0f0f0f0f0fn;
  assertEquals(isDuplicate(hash, [hash ^ 0b111n]), true); // 3 bits off: same picture
  assertEquals(isDuplicate(hash, [hash ^ 0xffn]), false); // 8 bits off: different
  assertEquals(isDuplicate(hash, []), false);
});
