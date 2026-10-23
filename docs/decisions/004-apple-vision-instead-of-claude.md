# 004 — Photo checks with Apple's on-device classifier instead of Claude

**Status:** accepted · 2026-10-23

## Context

The plan (PLAN §6, Phase 4) has the server send both photos to Claude, which reports observations (face, target present and how sure, looks like a screen) that a code rule turns into a verdict. That needs an Anthropic API key with paid API credits. Mo decided not to set one up, and to use Apple's built-in image classifier instead.

Apple's classifier (`VNClassifyImageRequest`) ships with iOS and knows 1,303 labels. It's free, works offline and answers instantly. When we checked on 23 Oct 2026, it recognised 10 of the original 13 targets directly (tree, bench, street sign, post box, bicycle, lamp post, statue/monument, door, shop front, traffic light) and the other 3 only roughly (bus stop → "bus", park gate → "fence", plant pot → "plant"). It also has screen-like labels (`screenshot`, `computer_monitor`, `television`, `laptop`, `computer`, `phone`).

## Decision

- **The phone observes, the server decides.** The app runs the face check, the target check and the screen check (`ios/App/Services/CheckIn/PhotoChecks.swift`), then sends the numbers as `observations` to `verify-checkin`. The server applies the rule in `_shared/decision.ts`: accept only if there's a face, target confidence ≥ 0.3, screen confidence < 0.3, and the photo isn't a reuse.
- **The phone warns first.** A mirror of the rule runs on the phone, so a photo that would fail is caught before uploading and doesn't use an attempt. A Deno test (`sync_with_ios_test.ts`) fails if the two copies' targets or thresholds drift apart.
- **The server checks reused photos itself:** the photo's 64-bit perceptual hash against the user's last 30 (≤ 6 bits different = the same picture).
- **Targets are limited to what the classifier recognises.** Bus stop is dropped; park gate → "a fence"; plant pot → "a plant"; building entrance → "a front door".
- **The thresholds are provisional.** `tools/eval-photos` scores real photos with the app's own code, to tune them (target: no screen photos let through, ≥ 80% correct overall).

## Consequences

- **Weaker against determined cheaters.** The classifier runs on the phone, so a modified app could send made-up observations. The server can't check them; it still enforces the time window, the 5-attempt limit and reused photos. In Phase 5, friends see each other's photos, which is the human check.
- **Screen photos are caught only if the classifier sees a screen.** A close-up that fills the frame may not show a monitor or bezel. The tuning set must include such cases.
- No API costs, no photos sent to a third party, and verification works without a network until the upload.
- Claude can be added later as a server-side second opinion without changing the app: `verify-checkin` would call it after the current rule passes.

## Alternatives considered

- **Claude on the server** (the original plan): it can't be faked and it can explain rejections, but it needs a paid key, which Mo declined for now.
- **Training our own model with Create ML**: it would need hundreds of labelled photos per target, plus screen photos. Apple's classifier already covers the targets.
- **Both** (Apple's pre-check plus Claude as referee): the recommended option, waiting on an API key.
