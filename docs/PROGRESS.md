# Progress

## Phase 1 — Screen Time lock spike

**Status:** built, 15/15 unit tests pass, core lock flow confirmed on iPhone Sh (2026-10-23) · branch `phase-1-screen-time`

### Checked on device (iPhone Sh, 2026-10-23, from the phone's lock log)

| Time | Event |
|---|---|
| 00:11:02 | Scheduled test lock fired in the Monitor extension. No apps chosen yet, so no shield (correct) |
| 00:13:45 | Instagram chosen during a running lock → reconcile locked it straight away |
| 00:14:47 | Starting a new test lock stopped the old one; `stopMonitoring` triggers `intervalDidEnd`, which unlocked |
| 00:16:02 | Monitor applied the shield on schedule (new 00:16–00:31 lock) |
| 00:16:44 | **Unlock now** cleared the shield |

Mo saw the QuestLock shield on Instagram and the "Tap to check in" notification. Found on device and fixed: the app picker saved and logged once per tick (6× for one pick). It now saves only real changes. **Check in** taps are now logged too.

### What was built

- **Shared (app + all 3 extensions):**
  - `ScheduleModels.swift` (`TimeOfDay`, `Weekday`, `DaySchedule`, `WeeklySchedule`).
  - `ScheduleMath.swift`: `lockStart(deadline:leadMinutes:)` rejects leads under 15 min or over 6 h, and windows crossing midnight. `lockWindow(on:…)` / `isInsideLockWindow(now:…)` treat the window as start-inclusive, end-exclusive.
  - `SharedStore.swift`: typed App Group storage.
  - `LockEngine.swift`: the single lock rule, used by both the Monitor and reconcile (ADR 003).
- **Monitor extension:** `intervalDidStart` applies shields from the stored selection to the named store `questlock`; `intervalDidEnd` clears them.
- **ShieldConfig:** custom shield "Locked until you check in / Today's quest: find a bench" with a **Check in** button.
- **ShieldAction:** **Check in** closes the blocked app and posts a "Tap to check in" notification that opens QuestLock.
- **Today tab:** Screen Time permission, app picker (`FamilyActivityPicker`), a weekly schedule toggle, a 1-min/15-min test lock, a tomorrow-only test, Unlock now, and a lock log. The log shows what the Monitor and reconcile did, with times.
- **Reconcile on launch:** every time the app comes to the foreground it recomputes "should I be locked?" and fixes the shields.

### Deviations from the plan

1. **Weekly schedule is off until you switch it on.** Otherwise picking apps would start real daily locks (Mon–Fri 08:00–10:00, Sat–Sun 10:00–12:00) straight away.
2. **"Unlock now" unlocks until the end of the current window** (`unlockedUntil`), so reconcile doesn't re-lock immediately. Phase 3's verified check-in reuses this.
3. **The Monitor ignores a weekly callback that fires on the wrong weekday**, as a safety net. It logs "fired on …, ignored" if that ever happens.
4. **A lock log on the Today tab**, so missed or unexpected callbacks can be seen on the phone.
5. All Phase 1 code was written by Claude (build mode; no "Mo writes" items).

### Open issues

- Not yet confirmed on the phone: that weekly `DateComponents(weekday:)` schedules fire only on their weekday. The tomorrow-only test checks this, and the Monitor's weekday guard means a wrong-day callback can't lock anyway.
- Not yet seen on the phone: a lock ending on its own at the scheduled time (both test locks so far were ended early by Unlock now or a new test lock).
- The shield's notification is posted fire-and-forget. If it doesn't show up on the phone, it needs another approach.
- Overlapping test locks are only handled roughly (debug-only).

### Manual test steps (iPhone Sh, cable not needed)

1. Open **QuestLock** → **Today** → **Allow Screen Time access** → **Continue**. Approve with Face ID or your passcode if asked. When it asks about notifications, tap **Allow**.
2. **Apps to block** → search for **Instagram** (or any app you use) → tick it → **Done**. The row shows "1 app".
3. Tap **Lock in 1 minute for 15 minutes**. "Test lock" shows a start and end time.
4. Before the start time, **force-quit QuestLock**: swipe up from the bottom, hold, then swipe QuestLock away.
5. After the start time, open **Instagram**. Expected: the QuestLock shield, saying "Locked until you check in / Today's quest: find a bench".
6. Tap **Check in**. Expected: Instagram closes and a **"Tap to check in"** notification appears. Tap it and QuestLock opens.
7. Today shows **Apps locked, until HH:MM**. The lock log shows "Start debug-lock: apps locked".
8. Tap **Unlock now** → open Instagram. Expected: it opens normally.
9. Tap **Lock in 1 minute for 15 minutes** again and **don't** unlock. After the end time, Instagram opens normally and the log shows "End debug-lock: apps unlocked".
10. **Tomorrow-only test:** set **Tomorrow-only test at** to a time later today, e.g. one hour from now, then tap **Lock tomorrow at that time**. Today at that time, Instagram should **not** lock. Tomorrow at that time it **should**, and the log should show "Start test-weekday-N: apps locked" with tomorrow's date.

Report back: which steps worked, and a screenshot of anything that didn't (the lock log helps).

---

## Phase 0 — Repo, skeleton, and the slow external requests

**Status:** done · device test passed on 2026-10-22 · merged in PR 1 · branch `phase-0-skeleton`

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

### Checked on device (2026-10-22, iPhone Sh — iPhone 16 Pro Max, iOS 27.0.1)

- Built, installed and launched from the command line (commands in `CLAUDE.md`). The app opens with 4 tabs, and Settings shows **App Group: OK**.
- `codesign --verify --strict` ✅ for the app and all 3 extensions. Each one's signed entitlements contain `com.apple.developer.family-controls = true` and the App Group.
- Each has its own development provisioning profile (team `7CC4SQ8T2L`) that lists iPhone Sh.

### Deviations from the plan

1. **Name: QuestLock** — "Wakeproof" is already used by several App Store apps. ADR 001.
2. **Sign in with Apple and Push entitlements are added later** (Phase 2 and Phase 5), when first used. The App IDs still get those capabilities in the portal now. This keeps Phase 0 device builds from failing on capabilities nothing uses yet.
3. **Generated files are gitignored**: `ios/QuestLock.xcodeproj` and `ios/Generated/` (Info.plists, `.entitlements`). XcodeGen recreates them. ADR 002.
4. **Release uses `Debug.xcconfig`** until Phase 7 (TestFlight) needs its own settings.
5. **Unit-test target added now** (with a smoke test) so Phase 1 starts with the wiring done.
6. **CI uses Xcode 26.x** (the `macos-26` runner's default); local is Xcode 27. Fine while we target iOS 17 and avoid iOS 27-only APIs.

### Open issues

- **Unsigned Simulator builds can't launch** on Apple Silicon (the app must be at least ad-hoc signed). CI only *builds* with `CODE_SIGNING_ALLOWED=NO`; run tests with default signing (command in `CLAUDE.md`).
- Family Controls (Distribution): requested for all 4 bundle IDs on 2026-10-18, waiting for Apple. Check: portal → Identifiers → each App ID → **Capability Requests** → **Status**. Approved = **Assigned**. TestFlight (Phase 7) is blocked until all 4 are assigned.

### Mo does (Phase 0 checklist)

- [x] Xcode → Settings → Accounts → **+** → Apple ID → sign in with your developer account.
- [x] iPhone Sh registered in the developer account (done by the first device build).
- [x] Developer portal → Identifiers → **App Groups** → register `group.com.mohammadshaw.questlock`.
- [x] Developer portal → Identifiers: register the 4 App IDs (`com.mohammadshaw.questlock`, `.monitor`, `.shieldconfig`, `.shieldaction`) with **Family Controls (Development)** + **App Groups** (assign the group) on all 4, plus **Push Notifications** + **Sign in with Apple** on the app.
- [x] **Family Controls (Distribution) requested for all 4 bundle IDs** (portal → App ID → **Capability Requests** tab) on **2026-10-18**.
- [ ] Create a free Supabase project. Note the project ref (not the keys) here: ____
- [ ] Anthropic Console: create an API key with a monthly spend limit. Don't put it anywhere in the repo; it goes into `supabase secrets` in Phase 4.
- [x] Public GitHub repo: https://github.com/moshawahneh/questlock (CI green on PR 1).

### Manual test steps (device)

1. Do the first checklist item (sign in to Xcode).
2. Connect your iPhone with a **data** cable (many cables only charge), plugged **straight into the Mac**. On the Mac, click **Allow** on "Allow accessory to connect?". On the iPhone, unlock it and tap **Trust This Computer**. To check it worked: `xcrun devicectl list devices` should list the phone as `physical`. If you only see **MacBook Pro** in Xcode's Devices window, that's the Mac itself, not the phone.
3. iPhone: Settings → Privacy & Security → (very bottom) **Developer Mode** → On → restart → **Turn On**. The switch only shows up after the phone has been connected to Xcode.
   - Steps 4–7 are the Xcode way. The command-line way (build → install → launch) is in `CLAUDE.md`. The first signed build asks for your **Mac login password** so `codesign` can use your signing key; click **Always Allow**.
4. Mac terminal: `cd ~/Developer/questlock/ios && xcodegen generate && open QuestLock.xcodeproj`
5. Xcode toolbar: scheme **QuestLock**, destination **your iPhone**.
6. Click the blue project icon → each of the 4 targets → **Signing & Capabilities**: "Automatically manage signing" is ticked and Team is your team. If one shows a red error, click **Try Again**. That's Xcode registering the App ID and profile.
7. Press **Run** (⌘R). Expected: the app opens with 4 tabs.
8. Open the **Settings** tab. Expected: **App Group: OK**. ("Missing" means the signed build lacks the App Group entitlement; check step 6.)
9. Tell Claude Code it ran. It will check the device build's signed entitlements (`codesign -d --entitlements`) for all 3 extensions.
10. `supabase start` (OrbStack running) → `supabase status` lists the local API URL, DB URL and Studio URL.
11. After pushing: GitHub → Actions → both CI jobs green.

### Teach-back

Skipped: Mo switched the project to build mode on 2026-10-22 (see `CLAUDE.md`).
