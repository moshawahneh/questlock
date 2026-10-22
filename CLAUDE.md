# QuestLock — rules for Claude Code

Full plan: `docs/PLAN.md`. Where we are: `docs/PROGRESS.md`. Decisions: `docs/decisions/`.

## Project facts

| | |
|---|---|
| App name | QuestLock |
| Bundle IDs | `com.mohammadshaw.questlock` (app), `.monitor`, `.shieldconfig`, `.shieldaction`, `.tests` |
| App Group | `group.com.mohammadshaw.questlock` (the code reads it from `ios/Shared/AppGroup.swift`) |
| Apple team ID | `7CC4SQ8T2L` (set locally in `ios/Config/Debug.xcconfig`, not in `project.yml`) |
| Minimum iOS | 17.0 · Swift 6 language mode |

## Commands

```bash
# iOS — regenerate the Xcode project after any change to ios/project.yml or added/removed files
cd ios && xcodegen generate
# Simulator build (same as CI)
xcodebuild build -project ios/QuestLock.xcodeproj -scheme QuestLock -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO
# Unit tests
xcodebuild test -project ios/QuestLock.xcodeproj -scheme QuestLock -destination 'platform=iOS Simulator,name=<an installed iPhone simulator>'
# Device build + install + launch (phone connected by data cable, Developer Mode on).
# -allowProvisioningDeviceRegistration registers a new phone in the developer account on its first build.
xcrun devicectl list devices    # find the phone's UDID ("physical")
xcodebuild build -project ios/QuestLock.xcodeproj -scheme QuestLock -destination 'id=<UDID>' -derivedDataPath build/dd -allowProvisioningUpdates -allowProvisioningDeviceRegistration
xcrun devicectl device install app --device <UDID> build/dd/Build/Products/Debug-iphoneos/QuestLock.app
xcrun devicectl device process launch --device <UDID> com.mohammadshaw.questlock
# Supabase (needs OrbStack/Docker running)
supabase start      # local stack
supabase db lint    # same as CI
supabase test db    # pgTAP tests (from Phase 2)
```

## Standing rules

> **Build mode (Mo's decision, 2026-10-22).** Mo wants the app built for him, not a guided course. This replaces the learning-mode rules in `docs/PLAN.md` §5: no teach-back questions, no "Mo writes" items, and no plan-mode approval per phase. The secrets, safety, iOS and testing rules below still apply.

**Workflow**
- Work through the phases in order and continue to the next one without waiting for approval. Use `docs/PLAN.md` for each phase's scope and "Done when".
- Stop only for things Mo has to do himself: device tests (Screen Time, camera and push only work on a real iPhone), creating accounts and keys, App Store and TestFlight steps, and the "Ask before" items under Secrets and safety.
- Branch per phase (`phase-1-screen-time`), small commits with Conventional Commit messages (`feat:`, `fix:`, `test:`…), one PR per phase. **Claude merges the PR** once CI is green and the phase's device test (if any) has passed.
- At the end of every phase, update `docs/PROGRESS.md`: what was built, deviations from the plan, open issues, exact manual test steps.
- Record non-obvious choices as short ADRs (Architecture Decision Records) in `docs/decisions/`: context, decision, alternatives considered.
- Before using an Apple, Supabase or Claude API you're not certain of, check the current official docs or the SDK's `.swiftinterface`. Screen Time APIs change between iOS versions; don't guess signatures.
- Don't add dependencies without asking. Pre-approved: `supabase-swift` (iOS); `@supabase/supabase-js`, `jose`, Deno std (Edge Functions).

**Talking to Mo**
- Mo is a CS student who wants results, not lessons. Keep updates short and plain: what changed, what he has to do, and exact numbered steps for anything on his phone or in a web console.
- Expand acronyms the first time they appear. Never use the word "genuinely".

**Secrets and safety**
- The repo is public. Never commit secrets. Claude API key, APNs key and Supabase service-role key live only in Supabase secrets (`supabase secrets set`). Supabase URL + anon key go in a gitignored `.xcconfig` with a committed `.example`.
- The anon key is safe in the app *only because* RLS is on for every table. Every new table gets RLS enabled in the same migration.
- Ask before: pushing migrations to the remote Supabase project, deploying functions, anything that costs money, deleting data.

**iOS specifics**
- Never hand-edit `.pbxproj`. Edit `ios/project.yml` and run `xcodegen generate`. Entitlements are defined in `project.yml` too (XcodeGen regenerates `.entitlements` files and overwrites manual edits).
- Screen Time, multi-camera and push don't work properly in the Simulator. Install on Mo's iPhone from the command line (Commands above) and give him exact numbered steps for what to check.
- Swift 6 language mode. Fix concurrency errors (`@MainActor`, `Sendable`) properly rather than silencing them.

**Testing**
- Pure logic (schedule maths, decision rule, hashing) gets unit tests.
- Every RLS policy gets a pgTAP test (`supabase test db`) — especially the no-peeking rule.
- Edge Functions: Deno tests for logic; the Claude call is behind an interface so tests can use a fake.
