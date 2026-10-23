# Progress

## Phase 3 — Dual-camera capture and upload (stub verification)

**Status:** done · first real check-ins on the iPhone 11 Pro Max (2026-10-23) · branch `phase-3-camera`

### Checked on device (iPhone 11 Pro Max, second account, one-off test lock 23:06–23:40 on 23 Oct)

- 23:06:01 the Monitor locked the chosen app on time. 23:06:49 a check-in with a **water bottle** was verified on the live server: both photos stored, phash saved, `daily_results` = verified, and the app unlocked.
- After a reset, a photo of a **fan** was also verified. Expected for the stub: what's in the photo isn't checked until Phase 4. Mo also pointed out that a target shown on another screen would pass. Phase 4's `looks_like_screen_or_printed_photo` observation, the decision rule and the screen-photo eval cases cover this.
- The front-camera face check works: a photo with no face was refused on the phone, without using an attempt.
- **Bug found in the lock log and fixed:** the app re-registered the weekly schedule every time it came to the foreground. iOS ends a running interval on `stopMonitoring`, so the shields dropped for a moment each time ("End … unlocked → Start … locked" 3× in 30 s). Now the app only re-registers on a real change, and `intervalDidEnd` keeps the shields while a window has more than a minute left (4 new unit tests from the real timeline).

### What was built

- **Database** (`…_phase3_checkins.sql`): a private `checkins` photo bucket (JPEG only, 2 MB max). Each user can upload only into `{their id}/…` and can't update or delete photos. `challenge_window(user, date)` gives the lock window as real timestamps in the user's time zone (tested across the 25 Oct clock change). `ensure_challenge(…)` creates today's challenge once. Both are service-role only.
- **Edge Functions** (Deno):
  - `issue-challenge` returns today's challenge (a random allowlist target, avoiding the last 7 days), or `null` on a rest day.
  - `verify-checkin` (stub, no AI) checks that the challenge is yours, the time window (too early → refused, after the deadline → `late`), the 5-attempt limit, and that both photos exist at the expected paths. It then records the check-in and the day's result.
  - The rules live in `_shared/checkin_rules.ts`, with 8 Deno tests.
- **iOS:**
  - `CameraController` takes both photos at once with `AVCaptureMultiCamSession`; older phones take back then front.
  - BeReal-style capture screen. Camera only, with no photo library anywhere.
  - Before uploading: an on-device face check (Vision), resizing to ≤1024 px with JPEG quality 0.7, and a 64-bit dHash of the back photo.
  - Upload, then verify. A verified check-in unlocks until the deadline (`unlockedUntil`), which the Monitor respects.
  - Today tab: today's quest, "opens at", **Check in now**, checked in, late.
- Tests: 26 iOS unit tests (including the dHash), 43 pgTAP tests, 8 Deno tests, and 12 end-to-end checks against the local stack.

### Deviations from the plan

1. **The server writes the `checkins` row**, not the app. The app uploads the photos and calls `verify-checkin`, which counts attempts and inserts the row, so a client can't fake attempt numbers.
2. **dHash averages the 9×8 cells itself.** CoreGraphics' high-quality downscale corrupts the last 4 pixels of the bottom row when drawing straight into a tiny bitmap (found by a unit test and confirmed on the Mac).
3. Failed uploads and "no face" don't use one of the 5 attempts (the plan's Phase 6 behaviour, done early).

### Open issues

- The sequential-camera fallback is untested on a real device (both of Mo's phones support multi-cam).

### Manual test steps (tomorrow, 09:00–12:00)

1. After 09:00 Instagram should be locked (Phase 2 schedule). Open **QuestLock → Today**. It shows **Find …** and **Check in now**.
2. Tap **Check in now** → allow camera access → the back camera fills the screen with your face in the corner. Find the target and press the shutter.
3. **Post check-in.** Expected: the screen closes, Today shows **Checked in at …**, and Instagram opens normally.
4. Optional checks: cover the front camera and post (expect "We couldn't see your face", with no attempt used); try the shield's **Check in** button.

---

## Phase 2 — Supabase foundation: auth, groups, schedules

**Status:** done · merged in PR 3 (2026-10-23) · branch `phase-2-supabase`

**Checked live (2026-10-23):** migrations pushed (with Mo's OK) and the live schema lints clean. Sign in with Apple works on iPhone Sh after the Apple provider was switched on in the dashboard. Two-phone test: iPhone Sh created a group, and the iPhone 11 Pro Max (a second Apple ID, registered in the developer account) signed in and joined with the code. The live database shows 2 profiles, 1 group, 2 members and 2 saved schedules. The schedule saved on iPhone Sh came back from the server as "pending from 2026-10-24".

### What was built

- **Database** (`supabase/migrations/…_phase2_schema.sql`): every table from PLAN §4, with RLS (Row Level Security) on for all of them.
  - Profiles are created automatically on sign-up. Users can only edit their name, time zone and `screen_time_ok`; streaks are written by the server only, enforced with column privileges.
  - Groups and members can only be changed through RPCs (Remote Procedure Calls): `create_group`, `join_group`, `leave_group`, `rename_group`, `regenerate_invite_code`, `remove_member`. They enforce 20 members per group, 5 groups per person and admin-only actions. When the last admin leaves, the longest-standing member takes over; when the last member leaves, the group is deleted.
  - `save_schedule` stores a full week as a new version that **starts tomorrow** in the user's time zone. Rest days are stored explicitly, and `schedule_for(habit, date)` returns the rule in force on a date.
  - Scoring and feed tables (challenges, checkins, daily_results, …) are read-only for clients. Later phases add their write paths.
- **32 pgTAP tests** (`supabase test db`): non-members can't see groups, members or profiles; nobody can write someone else's schedule or their own streak; a bad invite code fails; admin-only actions; the group limit; leaving; signed-out access.
- **iOS:** Sign in with Apple → `signInWithIdToken` (with a nonce); onboarding (name → Screen Time + apps → schedule); groups (create, join by code, share, leaderboard by streak, admin rename / new code / remove, leave); Settings (name, weekly schedule editor, blocked apps, which can't be changed while locked, sign out).
- **Schedules on the phone:** the server's current and pending versions are kept side by side. Each weekday's DeviceActivity is registered with the rule for its *next* window, so a pending edit takes over once today's window has ended. Every lock start gets a repeating local notification ("Apps locked — check in by 10:00").
- **Monitor safety check:** a weekly callback only locks if today's schedule has a window starting about then, so a stale registration can't lock at the old time.
- 19 iOS unit tests.

### Deviations from the plan

1. All code written by Claude (build mode). `join_group` was a "Mo writes" item.
2. A user's **first** schedule also starts tomorrow, the same rule as edits, so the first day is a rest day.
3. The weekly schedule is on as soon as one is saved. Testing → "Use my schedule on this phone" pauses it (a testing aid; Phase 6 reports escapes).
4. supabase-swift is pinned to an exact version (2.55.4), because `Package.resolved` lives in the gitignored, generated Xcode project.

### Open issues

- Pushing the migration to the live project needs Mo's OK (standing rule).

### Mo does

1. Create the Supabase project ([dashboard](https://supabase.com/dashboard) → New project → `questlock`, region London, free plan). Keep the database password in your password manager.
2. Run `supabase login` in a terminal.
3. Supabase dashboard → Authentication → Sign In / Providers → **Apple** → on → Client IDs: `com.mohammadshaw.questlock` → Save.
4. Tell Claude Code, which then links the project, asks before pushing the migration, puts the URL and anon key in `ios/Config/Debug.xcconfig`, and reinstalls the app.
5. Two-phone test (once the app is connected): on your phone, sign in → onboarding → **Groups** → **Create a group** → share the code. On a friend's iPhone (cable to this Mac, Developer Mode on; Claude Code installs it): sign in → **Join with a code** → both phones show both people on the leaderboard. Each sets a schedule, and the next day it locks the chosen apps on time.

---

## Phase 1 — Screen Time lock spike

**Status:** done · core lock flow confirmed on iPhone Sh (2026-10-23) · merged in PR 2 · branch `phase-1-screen-time`

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
