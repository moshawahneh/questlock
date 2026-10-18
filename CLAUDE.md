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
# Supabase (needs OrbStack/Docker running)
supabase start      # local stack
supabase db lint    # same as CI
supabase test db    # pgTAP tests (from Phase 2)
```

## Standing rules (copied from `docs/PLAN.md` section 5)

**Workflow**
- One phase at a time. Start each phase in plan mode and wait for Mo's approval. Stop at the end of the phase; don't start the next one.
- Branch per phase (`phase-1-screen-time`), small commits with Conventional Commit messages (`feat:`, `fix:`, `test:`…). Mo merges.
- At the end of every phase, update `docs/PROGRESS.md`: what was built, deviations from the plan, open issues, exact manual test steps.
- Record non-obvious choices as short ADRs (Architecture Decision Records) in `docs/decisions/` — context, decision, alternatives considered.
- Before using an Apple, Supabase or Claude API you're not certain of, check the current official docs. Screen Time APIs change between iOS versions; don't guess signatures.
- Don't add dependencies without asking. Pre-approved: `supabase-swift` (iOS); `@supabase/supabase-js`, `jose`, Deno std (Edge Functions).

**Explaining to Mo**
- Mo is a 2nd-year CS student: solid Java, some Python, SQL, some SwiftUI from a macOS side project. New to iOS extensions, Screen Time APIs, Supabase, Deno.
- After each meaningful step, explain what you did and why in plain English. Use Java analogies where they help (Swift `protocol` ≈ Java `interface`; RLS ≈ a `WHERE` clause the database adds to every query for you).
- Expand every acronym the first time it appears in a phase.
- Use ASCII diagrams for flows and data movement.
- Flag any code Mo would struggle to defend in an interview, and offer to walk through it.
- Never use the word "genuinely".
- Each phase has **"Mo writes"** items: write the tests and a stub, leave the implementation to Mo, then review his code. Don't fill them in unless he asks.

**Secrets and safety**
- The repo is public. Never commit secrets. Claude API key, APNs key and Supabase service-role key live only in Supabase secrets (`supabase secrets set`). Supabase URL + anon key go in a gitignored `.xcconfig` with a committed `.example`.
- The anon key is safe in the app *only because* RLS is on for every table. Every new table gets RLS enabled in the same migration.
- Ask before: pushing migrations to the remote Supabase project, deploying functions, anything that costs money, deleting data.

**iOS specifics**
- Never hand-edit `.pbxproj`. Edit `ios/project.yml` and run `xcodegen generate`. Entitlements are defined in `project.yml` too (XcodeGen regenerates `.entitlements` files and overwrites manual edits).
- Screen Time, multi-camera and push don't work properly in the Simulator. When a phase needs a device test, give Mo exact numbered steps.
- Swift 6 language mode. When you fix a concurrency error (`@MainActor`, `Sendable`), explain the fix rather than silencing it.

**Testing**
- Pure logic (schedule maths, decision rule, hashing) gets unit tests.
- Every RLS policy gets a pgTAP test (`supabase test db`) — especially the no-peeking rule.
- Edge Functions: Deno tests for logic; the Claude call is behind an interface so tests can use a fake.
