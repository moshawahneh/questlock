# Progress

## Phase 0 — Repo, skeleton, and the slow external requests

**Status:** built and checked on the Mac · waiting for Mo's device test, CI run and merge · branch `phase-0-skeleton`

### What was built

- Repo layout from PLAN §3: `CLAUDE.md` (standing rules + project facts), `docs/PLAN.md`, `docs/decisions/`, `.gitignore`, stub `README.md`.
- `ios/project.yml` (XcodeGen) with 5 targets:

  ```
  QuestLock.app  (com.mohammadshaw.questlock)        ← App/ + Shared/
   └─ PlugIns/
       ├─ Monitor.appex       (.monitor)       DeviceActivityMonitor   ← Extensions/Monitor/ + Shared/
       ├─ ShieldConfig.appex  (.shieldconfig)  ShieldConfiguration     ← Extensions/ShieldConfig/ + Shared/
       └─ ShieldAction.appex  (.shieldaction)  ShieldAction            ← Extensions/ShieldAction/ + Shared/
  QuestLockTests (.tests)  — Swift Testing, runs inside the app
  ```

  All four app/extension targets get the Family Controls entitlement + App Group `group.com.mohammadshaw.questlock`.
  The extension point identifiers come from Xcode 27's own extension templates.
- SwiftUI app with 4 placeholder tabs (Today · Feed · Groups · Settings). Settings shows an **App Group: OK/Missing** diagnostic.
- Extension stubs that compile against the iOS 27 SDK signatures; they do nothing yet (Phase 1).
- `supabase/`: `config.toml` (project `questlock`, Postgres 17), an empty first migration, empty `seed.sql`, `tests/` and `functions/` placeholders.
- `.github/workflows/ci.yml`: unsigned Simulator build on `macos-26`, and `supabase db lint` on `ubuntu-latest`.

### Checked on the Mac

- `xcodegen generate` ✅
- Simulator build ✅, no warnings. `QuestLock.app/PlugIns/` contains all 3 `.appex` with the right bundle IDs and `NSExtensionPointIdentifier`s; `MinimumOSVersion` 17.0.
- `xcodebuild test` on iPhone 18 Pro simulator ✅ (2/2).
- `supabase start` ✅ (OrbStack): API `http://127.0.0.1:54321`, Studio `http://127.0.0.1:54323`, DB on port 54322.
- `supabase db lint --local --level warning --fail-on error` ✅ ("No schema errors found").

### Deviations from the plan

1. **Name: QuestLock** — "Wakeproof" is already used by several App Store apps. ADR 001.
2. **Sign in with Apple and Push entitlements are added later** (Phase 2 and Phase 5), when first used. The App IDs still get those capabilities in the portal now. This keeps Phase 0 device builds from failing on capabilities nothing uses yet.
3. **Generated files are gitignored**: `ios/QuestLock.xcodeproj` and `ios/Generated/` (Info.plists, `.entitlements`). XcodeGen recreates them. ADR 002.
4. **Release uses `Debug.xcconfig`** until Phase 7 (TestFlight) needs its own settings.
5. **Unit-test target added now** (with a smoke test) so Phase 1 starts with the wiring done.
6. **CI uses Xcode 26.x** (the `macos-26` runner's default); local is Xcode 27. Fine while we target iOS 17 and avoid iOS 27-only APIs.

### Open issues

- **Unsigned Simulator builds can't launch** on Apple Silicon (the app must be at least ad-hoc signed). CI only *builds* with `CODE_SIGNING_ALLOWED=NO`; run tests with default signing (command in `CLAUDE.md`).
- Device build not done yet: the Mac has no Apple Development certificate until Mo signs in to Xcode (step 1 below).
- CI hasn't run yet: the GitHub repo doesn't exist / isn't pushed.
- Family Controls (Distribution) request: not submitted yet.

### Mo does (Phase 0 checklist)

- [ ] Xcode → Settings → Accounts → **+** → Apple ID → sign in with your developer account.
- [ ] Developer portal → Identifiers → **App Groups** → register `group.com.mohammadshaw.questlock`.
- [ ] Developer portal → Identifiers: check the 4 App IDs exist (`com.mohammadshaw.questlock`, `.monitor`, `.shieldconfig`, `.shieldaction`). Xcode may create them on the first device build. Enable **Family Controls (Development)** + **App Groups** (assign the group) on all 4, plus **Push Notifications** + **Sign in with Apple** on the app.
- [ ] **Submit the Family Controls (Distribution) request for all 4 bundle IDs** (Apple doc linked in PLAN §9). Note the date here: ____
- [ ] Create a free Supabase project. Note the project ref (not the keys) here: ____
- [ ] Anthropic Console: create an API key with a monthly spend limit. Don't put it anywhere in the repo; it goes into `supabase secrets` in Phase 4.
- [ ] Create an empty **public** GitHub repo `questlock`, or run `gh auth login` and let Claude Code create it.

### Manual test steps (device)

1. Do the first checklist item (sign in to Xcode).
2. Connect your iPhone by cable, unlock it, tap **Trust This Computer**.
3. iPhone: Settings → Privacy & Security → **Developer Mode** → On → restart → confirm.
4. Mac terminal: `cd ~/Developer/questlock/ios && xcodegen generate && open QuestLock.xcodeproj`
5. Xcode toolbar: scheme **QuestLock**, destination **your iPhone**.
6. Click the blue project icon → each of the 4 targets → **Signing & Capabilities**: "Automatically manage signing" is ticked and Team is your team. If one shows a red error, click **Try Again**. That's Xcode registering the App ID and profile.
7. Press **Run** (⌘R). Expected: the app opens with 4 tabs.
8. Open the **Settings** tab. Expected: **App Group: OK**. ("Missing" means the signed build lacks the App Group entitlement; check step 6.)
9. Tell Claude Code it ran. It will check the device build's signed entitlements (`codesign -d --entitlements`) for all 3 extensions.
10. `supabase start` (OrbStack running) → `supabase status` lists the local API URL, DB URL and Studio URL.
11. After pushing: GitHub → Actions → both CI jobs green.

### Teach-back (answer before Phase 1)

1. What's an app extension, and why does this app need three?
2. What is an App Group for?
3. Why XcodeGen instead of clicking in Xcode?
