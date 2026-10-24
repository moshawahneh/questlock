// The phone and the server each have a copy of the target list and thresholds. This test fails if
// they drift apart. Run with: deno test --allow-read
import { assert, assertEquals } from "jsr:@std/assert@1";
import { MAX_SCREEN_CONFIDENCE, MIN_TARGET_CONFIDENCE } from "./decision.ts";
import { TARGETS } from "./targets.ts";

const swift = await Deno.readTextFile(
  new URL("../../../ios/App/Services/CheckIn/PhotoChecks.swift", import.meta.url),
);

Deno.test("every server target has accepted labels on the phone", () => {
  const block = swift.slice(swift.indexOf("static let accepted"), swift.indexOf("static let screen"));
  const phoneKeys = new Set([...block.matchAll(/"(\w+)":\s*\[/g)].map((m) => m[1]));
  for (const target of TARGETS) {
    assert(phoneKeys.has(target.key), `PhotoChecks.swift has no labels for target "${target.key}"`);
  }
});

Deno.test("thresholds match the phone's copy", () => {
  const value = (name: string) => Number(swift.match(new RegExp(`${name} = ([0-9.]+)`))?.[1]);
  assertEquals(value("minTargetConfidence"), MIN_TARGET_CONFIDENCE);
  assertEquals(value("maxScreenConfidence"), MAX_SCREEN_CONFIDENCE);
});
