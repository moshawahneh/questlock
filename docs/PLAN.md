# QuestLock — Execution Plan for Claude Code

> **Name decided: QuestLock.** Bundle IDs `com.mohammadshaw.questlock`, `.monitor`, `.shieldconfig`, `.shieldaction`; App Group `group.com.mohammadshaw.questlock`. See `docs/decisions/001-app-name-and-bundle-ids.md`.

> **Working mode changed 2026-10-22: build mode.** Mo asked Claude Code to build the app for him. The teach-back questions, "Mo writes" items and per-phase plan approvals below are skipped, and Claude merges each phase's PR. See `CLAUDE.md`.

---

## 0. How to use this file

1. Create an empty GitHub repo and put this file at `docs/PLAN.md`.
2. Open Claude Code in the repo and paste:

   ```
   Read docs/PLAN.md fully. Do Phase 0 only. Start in plan mode: show me your
   plan for Phase 0 and wait for my approval before writing anything. Follow
   section 5 ("Standing rules") for the whole project.
   ```

3. At the end of each phase: test on your iPhone, answer that phase's teach-back questions, merge the branch, run `/clear`, then:

   ```
   Read docs/PLAN.md and docs/PROGRESS.md. Start Phase N in plan mode.
   ```

   `/clear` keeps context small; everything Claude Code needs to carry over lives in `PLAN.md`, `PROGRESS.md` and `CLAUDE.md`.

---

## 1. What we're building

An iOS app for small friend groups. Each person sets a **deadline per weekday** (e.g. Mon–Fri 10:00, Sat–Sun 12:00) and a **lock lead** (e.g. 2 h).

- At `deadline − lead`, the apps they chose (TikTok, Instagram…) are **blocked** with Apple's Screen Time API, and the app issues **today's AI-picked target** ("a bench", "a tree", "a bus stop") that fits where they are.
- To unlock, they take a **simultaneous front + back photo** (BeReal-style): back camera shows the target, front shows their face.
- Claude checks the photo. **Verified** → apps unlock, streak +1, friends notified.
- **Nothing verified by the deadline** → apps unlock anyway, a **miss** is logged, streak resets to 0, friends see it.
- You **can't see friends' posts for a day until you've posted yours**.
- Photos are **deleted after 24 hours**.
- Each group has a **leaderboard ranked by current streak**. A person can be in several groups.
- Weekly **AI coaching** summary per person.
- v1 has one habit type (morning check-in), but the data model supports more.

---

## 2. Decisions

### 2a. From Mo's answers

| Area | Decision |
|---|---|
| Platform | iOS only (everyone has an iPhone) → **native Swift + SwiftUI** (Screen Time APIs are Swift-only) |
| Enforcement | **Block chosen apps** during the lock window (FamilyControls + ManagedSettings + DeviceActivity) |
| Timing | Per-person, per-weekday **deadline**; apps lock a configurable lead time before it |
| Missed deadline | Apps **unlock at the deadline**, day logged as a **miss** |
| AI | Verify selfie · pick daily target · anti-cheat · weekly coaching |
| AI setup | **Apple Vision on-device** (face check, free) + **Claude API** (target check, cheating, target choice, coaching) |
| Social | No peeking until you've posted; leaderboard |
| Leaderboard | **Current streak only** |
| Groups | **Multiple groups per person**, joined by invite code |
| Camera | **Front + back simultaneously** (`AVCaptureMultiCamSession`), sequential fallback on older phones |
| Location | **Only used to pick realistic targets**, never pass/fail |
| Photos | **Deleted after 24 h** |
| Backend | **Supabase** (Postgres, Auth, Storage, Edge Functions, pg_cron) |
| Apple account | Paid Apple Developer Program account ✅ |
| Build style | **Phase by phase**, Claude Code explains each phase, Mo tests on device before moving on |

### 2b. Defaults chosen for you (change these before Phase 0 if you disagree)

| Default | Why |
|---|---|
| Minimum iOS 17 | Gets `@Observable`; all friends' phones will be on 17+ |
| Sign in with Apple only | No passwords to manage; required anyway if you add other social logins |
| Lock lead: 15 min – 6 h; lock window can't cross midnight | Apple's minimum DeviceActivity interval is 15 min; midnight-crossing adds date bugs for little value |
| Challenge opens when the lock starts (can't post earlier) | Otherwise you could post at 00:01 and skip the point of the app |
| Days with no deadline are **rest days** and don't break streaks | e.g. turn off Sundays |
| Schedule edits apply **from tomorrow**; blocked-app list can't be edited **during** a lock | Stops "move my deadline to 23:59" or "unblock Instagram" mid-lock |
| Max 5 verification attempts/day, 1 target reroll/day | Caps API cost and brute-forcing |
| Late posts allowed after the deadline (badge "late", no streak) | Lets you still see friends' posts that day |
| Feed visible if you've posted today **or** it's your rest day | Rest days shouldn't lock you out of the feed |
| Exact coordinates never leave the phone | Phone sends only locality name + nearby place categories |
| Max 20 members per group, 5 groups per person | Keeps queries and push fan-out trivial |
| Leaderboard tie-break: longest-ever streak | Streak-only scoring needs a tie-break |
| Targets are per person, not per group | Different people are in different places |

---

## 3. Architecture

```
┌──────────────────────────── iPhone ─────────────────────────────┐
│  QuestLock app (SwiftUI)                                        │
│   ├─ Auth · Groups · Schedule editor · Feed · Leaderboard       │
│   ├─ Camera: dual capture + on-device face check (Vision)       │
│   └─ LockService ─┐                                             │
│                   ▼  App Group (shared UserDefaults/files)      │
│  DeviceActivityMonitor ext → applies / clears shields on time   │
│  ShieldConfiguration ext   → custom "Locked: find a bench" UI   │
│  ShieldAction ext          → button → local notification        │
└───────────────────────────┬─────────────────────────────────────┘
                            │ HTTPS · supabase-swift · user JWT
┌───────────────────────────▼─────────── Supabase ────────────────┐
│ Auth (Sign in with Apple)      Postgres + Row Level Security    │
│ Storage (private bucket)       pg_cron + pg_net → Edge Functions│
│ Edge Functions (Deno / TypeScript):                             │
│   issue-challenge  verify-checkin  process-deadlines            │
│   cleanup-photos   weekly-coaching  report-integrity            │
│   _shared/ (claude.ts, apns.ts, decision.ts)                    │
└──────────────┬──────────────────────────────┬───────────────────┘
               ▼                              ▼
     Claude API (vision, JSON)        APNs (push notifications)
```

**Core principle: the phone enforces, the server referees.** A user can always escape the lock (revoke Screen Time access, delete the app). So streaks, misses and feed visibility are decided only on the server, and escapes are reported to the group.

### Check-in flow

```
Phone                                Supabase                         Claude
  │ lock starts: extension shields apps, local notification fires
  │── issue-challenge(locality, place categories) ──▶│
  │                                                  │── choose target ──▶│
  │◀──────────────── "a bench" + hint ───────────────│◀── JSON (enum) ────│
  │ dual capture → Vision face check → perceptual hash
  │── upload front.jpg + back.jpg (private bucket) ─▶│
  │── verify-checkin(challenge_id, paths, hash) ────▶│ time window, attempts,
  │                                                  │ duplicate-hash checks
  │                                                  │── 2 images + schema ─▶│
  │                                                  │◀── observations JSON ─│
  │                                                  │ decision rule (code)
  │◀──────────── verified | rejected(reason) ────────│ streak+1, push friends
  │ clear shields
```

### Repo layout

```
/
├── CLAUDE.md                     # standing rules (from section 5)
├── README.md                     # portfolio-facing: demo GIF, diagram, decisions
├── docs/PLAN.md  docs/PROGRESS.md  docs/decisions/NNN-*.md
├── ios/
│   ├── project.yml               # XcodeGen spec — source of truth for targets
│   ├── Config/                   # Debug.xcconfig.example (real one gitignored)
│   ├── App/                      # main app: Features/, Services/, Models/
│   ├── Shared/                   # compiled into app + all extensions (App Group keys, selection storage, schedule math)
│   ├── Extensions/Monitor/  Extensions/ShieldConfig/  Extensions/ShieldAction/
│   └── Tests/
├── supabase/
│   ├── migrations/  functions/  tests/ (pgTAP)  seed.sql
│   └── functions/verify-checkin/eval/   # eval script; photos gitignored
└── .github/workflows/ci.yml
```

---

## 4. Data model (Postgres)

| Table | Key columns | Notes |
|---|---|---|
| `profiles` | `id` (= `auth.users.id`), `display_name`, `timezone` (IANA), `current_streak`, `longest_streak`, `screen_time_ok` bool | Timezone updated by the app on launch if it changes |
| `groups` | `id`, `name`, `invite_code` (unique, 6–8 chars), `created_by` | |
| `group_members` | `group_id`, `user_id`, `role` (`admin`/`member`), `joined_at` | PK `(group_id, user_id)` |
| `habits` | `id`, `user_id`, `type` (`morning_checkin`), `config` jsonb, `active` | Extensibility point for future habit types |
| `habit_schedules` | `id`, `habit_id`, `weekday` 1–7, `deadline` time, `lock_lead_minutes`, `effective_from` date | Versioned: edits insert a new row effective tomorrow |
| `challenges` | `id`, `user_id`, `habit_id`, `local_date`, `target_key` (enum), `target_label`, `hint`, `opens_at`, `deadline_at`, `rerolls_used` | Unique `(user_id, habit_id, local_date)` |
| `checkins` | `id`, `challenge_id`, `user_id`, `local_date`, `attempt_no`, `status` (`pending`/`verified`/`rejected`/`late`), `front_path`, `back_path`, `phash`, `ai_result` jsonb, `rejection_reason`, `created_at`, `photos_deleted_at` | One row per attempt. Keeps `phash` after photos are deleted |
| `daily_results` | `user_id`, `habit_id`, `local_date`, `status` (`verified`/`missed`), `late_posted` bool | Unique `(user_id, habit_id, local_date)`. **Streaks are computed from this table only.** Rest days have no row, so they're skipped automatically |
| `device_tokens` | `user_id`, `apns_token`, `updated_at` | |
| `coaching_reports` | `user_id`, `week_start`, `summary`, `suggestion` | |
| `integrity_events` | `user_id`, `type` (`screen_time_revoked`, …), `created_at` | |
| `ai_calls` | `id`, `user_id`, `function`, `model`, `input_tokens`, `output_tokens`, `created_at` | Service-role only; for cost tracking |

**Row Level Security (RLS) rules — the important ones:**

- `can_see_day(viewer, d)` SQL helper: true if the viewer has a `daily_results` row for `d` that is `verified` or `late_posted`, **or** has no schedule for `d` (rest day).
- `checkins` SELECT: own rows, **or** (poster shares a group with viewer **and** `can_see_day(viewer, poster.local_date)` **and** status in `verified`/`late`).
- Storage bucket `checkins` (private), path `{user_id}/{local_date}/{checkin_id}_{front|back}.jpg`: the same rule, enforced with a storage policy that parses the path.
- `daily_results`, `profiles.current_streak`: readable by group-mates, **writable only by Edge Functions** (service role). Clients never write streaks.
- `groups`: join only through an RPC (Remote Procedure Call — a Postgres function the client calls) `join_group(invite_code)`, never a direct insert.

Known v1 limitation (write it in an ADR): friends in different time zones compare by the poster's local date.

---

## 5. Standing rules for Claude Code

*(Phase 0 copies this section into `CLAUDE.md`.)*

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

---

## 6. Phases

Each phase lists: **Build** · **Mo does** (manual steps Claude Code can't do) · **Mo writes** · **Done when** · **Teach-back** (Mo should answer these out loud before moving on).

---

### Phase 0 — Repo, skeleton, and the slow external requests

**Build**
- `CLAUDE.md` from section 5; `docs/PROGRESS.md`; `.gitignore` (Xcode, DerivedData, `*.xcconfig`, `.env`, eval photos).
- `ios/project.yml` with 4 targets: app, `Monitor` (DeviceActivityMonitor extension), `ShieldConfig` (ShieldConfiguration extension), `ShieldAction` (ShieldAction extension). All share App Group `group.com.mohammadshaw.questlock` and the Family Controls capability. `Shared/` sources compiled into all four.
- Empty SwiftUI app with a tab bar placeholder (Today · Feed · Groups · Settings).
- `supabase init`, empty first migration, local stack runs.
- CI workflow: `xcodebuild build` for Simulator + `supabase db lint`.

**Mo does**
- Install: latest Xcode, Homebrew `xcodegen`, `supabase` CLI, `deno`, Docker Desktop or OrbStack (for local Supabase).
- Pick the final name. Bundle IDs: `com.mohammadshaw.questlock`, `.monitor`, `.shieldconfig`, `.shieldaction`.
- In the Apple Developer portal: register the App Group; make sure all 4 App IDs exist with Family Controls, App Groups, Push Notifications and Sign in with Apple (app only) enabled.
- **Submit the Family Controls (Distribution) request today, for all 4 bundle IDs.** Development builds work without it, but TestFlight doesn't, and approvals reportedly take weeks.
- Create a Supabase project (free tier) and an Anthropic Console API key with a monthly spend limit.

**Done when**: `xcodegen generate` → app builds and runs on your iPhone with all 3 extensions embedded; `supabase start` runs locally; CI is green.

**Teach-back**: What's an app extension, and why does this app need three? What is an App Group for? Why XcodeGen instead of clicking in Xcode?

---

### Phase 1 — Screen Time lock spike (riskiest part first)

No backend yet. Prove the lock works before building anything on top of it.

**Build**
- Request Screen Time authorization (`AuthorizationCenter.shared.requestAuthorization(for: .individual)`).
- `FamilyActivityPicker` to choose apps/categories; store the `FamilyActivitySelection` (it's `Codable`) as JSON in App Group storage. Note: the app only gets opaque tokens, never app names.
- `LockService`: registers one `DeviceActivitySchedule` per weekday (7 activities) from a local, hardcoded schedule; computes `lockStart = deadline − lead` in `Shared/ScheduleMath.swift`.
- Monitor extension: `intervalDidStart` → apply shields from the stored selection via a named `ManagedSettingsStore`; `intervalDidEnd` → clear shields.
- ShieldConfig extension: custom title/subtitle ("Locked until you check in — today: find a bench"), reading the target text from App Group storage.
- ShieldAction extension: it can't open the main app directly (check current docs), so its button posts a local notification "Tap to check in".
- **Reconcile on launch**: whenever the app comes to the foreground, recompute "should I be locked right now?" and apply/clear shields itself. The monitor extension is known to occasionally miss callbacks.
- Debug screen: "lock in 1 min for 15 min", "unlock now", current state.

**Mo writes**: `ScheduleMath.lockStart(deadline:lead:)` and `isInsideLockWindow(now:schedule:)` + make the provided unit tests pass (include weekday boundaries and rejecting leads under 15 min or windows crossing midnight).

**Done when** (on device): pick Instagram → schedule a 15-min lock starting in 2 min → Instagram shows your custom shield at the start and opens normally at the end. Force-quit the app before the window: the shield still appears. "Unlock now" clears it. A weekday-specific schedule fires on the right day (leave one set for tomorrow and check).

**Teach-back**: Why do shields get applied by an extension rather than the main app? Why can't the lock window be shorter than 15 minutes? What happens if the extension misses `intervalDidEnd`, and how does reconcile-on-launch cover it?

---

### Phase 2 — Supabase foundation: auth, groups, schedules

**Build**
- Migrations for all tables in section 4 with RLS on, plus `join_group(invite_code)` and `create_group(name)` RPCs.
- pgTAP tests: non-members can't read a group; you can't write another user's schedule; `join_group` with a bad code fails.
- iOS: Sign in with Apple → `supabase.auth.signInWithIdToken` (with nonce); onboarding (display name, timezone auto-detected, Screen Time permission, app picker).
- Groups: create, join by code, leave, list members; admin can rename, regenerate code, remove members.
- Schedule editor: per-weekday deadline + lead (or "rest day"). Saving inserts a `habit_schedules` version effective tomorrow. The phone applies the new schedule only after today's lock window has ended (store it as "pending" in App Group storage; Monitor or the app swaps it in).
- Local notifications at each lock start ("Apps locked — check in to unlock").

**Mo does**: Supabase dashboard → Auth → Apple provider → add bundle ID as an authorized client ID. Link local CLI to the remote project.

**Mo writes**: the `join_group` SQL function (Claude Code writes its pgTAP tests first).

**Done when**: two phones (yours + a friend's via Xcode, see section 7) can sign in, join the same group by code, and each set a schedule that drives Phase 1's lock.

**Teach-back**: Explain RLS with a Java analogy. Why is the anon key safe in the app but the service-role key isn't? Why do schedule edits apply tomorrow?

---

### Phase 3 — Dual-camera capture and upload (stub verification)

**Build**
- `CameraService` with `AVCaptureMultiCamSession`; if `isMultiCamSupported` is false (pre-iPhone XS), capture back then front within ~5 s.
- Camera-only — no photo library picker anywhere in the app.
- Capture screen: back camera full-screen, front inset (BeReal layout), shows today's target.
- On-device checks before upload: Vision face detection on the front image (no face → retake, no upload); downscale to ≤1024 px long edge, JPEG ~0.7; compute a 64-bit perceptual hash (dHash) of the back image.
- Upload both images to the private bucket; insert a `checkins` row (`pending`).
- `verify-checkin` Edge Function **stub**: validates ownership, time window and attempt count, then marks verified without AI. On success, the app clears shields and writes "verified today" to App Group storage (the Monitor extension skips re-shielding when it sees this).
- `issue-challenge` stub returns a random target from the allowlist (section 6 / Phase 4).

**Mo writes**: the dHash function in Swift (resize to 9×8 grayscale, compare adjacent pixels → 64 bits) + Hamming distance, against provided tests.

**Done when** (on device): lock starts → open app → see target → dual capture → upload → stub verifies → Instagram unlocks. Rejects posting before the lock starts and after 5 attempts.

**Teach-back**: Why the sequential fallback? How is a perceptual hash different from SHA-256, and why does this app need the perceptual kind? Why check for a face on-device before calling the server?

---

### Phase 4 — AI: daily target, verification, eval set

**Build**
- `_shared/claude.ts`: thin client for the Claude Messages API. Model `claude-haiku-5-5` (cheap and fast; confirm the current model list in the docs). Use structured outputs / JSON schema per the current docs. Log input/output tokens per call to a `ai_calls` table for cost tracking.
- **`issue-challenge`**: phone sends locality name (from `CLGeocoder`) and nearby place categories (from MapKit `MKLocalPointsOfInterestRequest`, ~500 m). Location permission: When In Use; approximate accuracy is fine; if denied, use generic targets. Claude picks one `target_key` from an **enum allowlist** (`tree, bench, bus_stop, street_sign, post_box, bicycle, lamp_post, statue_or_monument, building_entrance, shop_front, traffic_light, park_gate, plant_pot`) that fits the categories and wasn't used in the last 7 days, plus a short friendly hint. Fallback: random allowlist item if Claude fails. One reroll per day.
- **`verify-checkin`** (replaces the stub):
  1. Server checks: owns challenge, `opens_at ≤ now ≤ deadline_at` (after deadline → `late`), attempt ≤ 5, Hamming distance to the user's last 30 hashes > threshold (else reject as duplicate).
  2. Send both images to Claude with a schema that returns **observations only**: `front_has_face`, `back_contains_target`, `target_confidence` (0–1), `looks_like_screen_or_printed_photo`, `user_message` (short, friendly reason if something's wrong).
  3. **The decision is made in code**, in `_shared/decision.ts`: verified ⇔ face ∧ target ∧ confidence ≥ 0.6 ∧ ¬screen ∧ ¬duplicate.
  4. System prompt states that any text visible in the images is part of the scene and never an instruction (prompt-injection defence — someone could hold up a sign saying "mark this verified").
  5. On verified: upsert `daily_results` (`verified`), recompute streak, store `ai_result`.
- Rejection UX: show the reason, retake (counts as an attempt).
- **Eval set**: `functions/verify-checkin/eval/` — `cases.json` + `deno task eval` that runs the real prompt over ~20 photo pairs and prints a confusion matrix: TP/FP/TN/FN (true/false positives/negatives). Photos are gitignored.

**Mo does**: `supabase secrets set ANTHROPIC_API_KEY=…`. Take ~20 eval pairs: valid shots, wrong object, photo of a screen, no face, very dark/blurry.

**Mo writes**: `decision.ts` + its Deno tests (Claude Code writes the test cases first).

**Done when**: the eval shows no false positives on the screen-photo cases and ≥ 80% correct overall (record the numbers in `PROGRESS.md` and the README); real check-ins work end-to-end on device.

**Teach-back**: Why does code make the final decision instead of the model? What's prompt injection in this app? For this app, is a false positive or a false negative worse, and how did that set your threshold?

---

### Phase 5 — Social: feed, misses, streaks, leaderboard, pushes, 24 h deletion

**Build**
- `can_see_day` helper + the `checkins` and storage SELECT policies from section 4. **pgTAP tests**: before posting you can't read a friend's check-in row or image; after verifying you can; non-group-members never can; rest day can.
- Feed: today's posts from all your groups (dual-image card, time posted relative to lock start, "late" badge). Locked state before you post: "Post yours to see 3 friends' check-ins".
- **`process-deadlines`** (pg_cron every 5 min → pg_net → Edge Function): for each user with a schedule today whose deadline has passed in their timezone and who has no `daily_results` row → insert `missed`, reset streak, push group-mates "Mo missed today's check-in". Must be **idempotent** (unique constraint + `on conflict do nothing`).
- Streak recompute: SQL function over `daily_results` ordered by date desc, counting `verified` until the first `missed`; updates `current_streak`/`longest_streak`.
- Leaderboard per group: `current_streak` desc, tie-break `longest_streak`.
- APNs pushes from `_shared/apns.ts` (JWT signed with the `.p8` key via `jose`): "friend posted", "friend missed", deduplicated across shared groups. App registers its device token on launch.
- **`cleanup-photos`** (pg_cron every 30 min): delete storage objects older than 24 h via the **Storage API** with the service role (deleting rows from `storage.objects` in SQL doesn't remove the files), then set `photos_deleted_at`. Keep the row and `phash`.

**Mo does**: create an APNs auth key (`.p8`) in the developer portal; set `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_PRIVATE_KEY` as Supabase secrets.

**Mo writes**: the streak recompute SQL function (against provided pgTAP tests, including rest days and a late post).

**Done when**: on two phones — friend posts, you get a push, feed shows a locked card until you post, then shows theirs; leave a day unposted and see the miss + streak reset; photos disappear after 24 h (test with a temporary 10-minute threshold).

**Teach-back**: Why enforce no-peeking in the database rather than in the SwiftUI view? What does idempotent mean and what breaks if `process-deadlines` isn't? Why can't the phone just tell the server "I missed"?

---

### Phase 6 — Integrity, coaching, settings hardening

**Build**
- **Integrity**: on every foreground, check `AuthorizationCenter.shared.authorizationStatus`. If it was approved and now isn't → `report-integrity` → `integrity_events` row + push to group-mates ("Mo turned off Screen Time access"). Show a red badge next to that person on the leaderboard until it's re-enabled.
- **`weekly-coaching`** (pg_cron hourly, runs for users whose local time is Sunday 18:00): sends only metadata (post times relative to lock start, misses, rejections, reroll use) — never photos — and returns ≤ 80 words + one concrete suggestion. Stored in `coaching_reports`, shown on the Today tab, pushed.
- Settings: edit blocked apps (disabled during a lock), schedule, display name, leave groups, **delete account** (deletes storage, rows and auth user; Apple requires in-app account deletion).
- Error states everywhere: offline, upload failed (retry without burning an attempt), Claude timeout (retry once, then "try again in a minute").

**Done when**: revoking Screen Time in iOS Settings notifies a friend within a minute of reopening the app; a coaching report arrives (trigger manually for testing); account deletion leaves no rows or files behind (verify in the dashboard).

**Teach-back**: List every way a user can escape the lock and how the app responds to each. Why does coaching never see photos?

---

### Phase 7 — Ship to friends + portfolio polish

**Build**
- `PrivacyInfo.xcprivacy` (UserDefaults is a "required reason" API); camera and location usage strings in plain language.
- App icon, launch screen, empty states, onboarding copy.
- README: one-paragraph pitch, demo GIF, the architecture diagram, "How no-peeking is enforced (RLS)", "How verification works (observations vs decision)", eval results table, list of ADRs, known limitations.
- CI: add `supabase test db` and Deno tests.

**Mo does**
- Confirm Family Controls (Distribution) shows as assigned for **all 4** bundle IDs in Certificates, Identifiers & Profiles.
- App Store Connect: create the app, archive and upload, add friends as **external testers via a public TestFlight link** (first build goes through Beta App Review).

**Done when**: at least 3 friends are using the TestFlight build daily for a week.

**Teach-back**: Walk through the whole system in 2 minutes using the architecture diagram — this is your interview answer to "tell me about a project".

---

## 7. Known gotchas (checked against Apple/Supabase docs and forums)

- **Family Controls entitlement is per bundle ID.** The app *and every Screen Time extension* need the distribution entitlement; developers on Apple's forums report TestFlight blocked for weeks waiting on extension approvals. Submit in Phase 0.
- **Before approval**, development-signed builds can still be installed on friends' iPhones registered as devices in your account (connect them to your Mac and run from Xcode). Verify this in Phase 2; it's the stopgap until TestFlight works.
- **DeviceActivity intervals must be ≥ 15 minutes** (and ≤ 1 week). Shorter intervals fail with `intervalTooShort`.
- **The Monitor extension can miss callbacks.** Hence reconcile-on-launch (Phase 1) and server-side miss detection (Phase 5).
- **Simulator can't test Screen Time, multi-cam or push.** Device only.
- **Multi-cam needs iPhone XS/XR or later (A12)**; check `AVCaptureMultiCamSession.isMultiCamSupported`.
- **XcodeGen overwrites `.entitlements` files** from `project.yml`; edit entitlements there.
- **Sign in with Apple native flow**: pass Apple's identity token + nonce to `signInWithIdToken`; add the bundle ID as an authorized client in Supabase.
- **Supabase scheduled jobs** use pg_cron + pg_net to call Edge Functions. File deletion must go through the Storage API.

## 8. After v1 (not now)

More habit types (gym photo, reading timer) using the `habits.type` column · group vote to overturn an AI rejection · App Attest to prove requests come from the real app · Live Activity countdown on the lock screen · group-wide shared targets on weekends.

## 9. References

- Apple — Requesting the Family Controls entitlement: https://developer.apple.com/documentation/familycontrols/requesting-the-family-controls-entitlement
- Apple Forums — per-extension entitlement requirement: https://developer.apple.com/forums/thread/796550
- Apple Forums — 15-minute minimum interval: https://developer.apple.com/forums/thread/783153
- Supabase — Cron quickstart (pg_cron + Edge Functions): https://supabase.com/docs/guides/cron/quickstart
- Supabase — Swift `signInWithIdToken`: https://supabase.com/docs/reference/swift/auth-signinwithidtoken
- Claude — Structured outputs: https://platform.claude.com/docs/en/build-with-claude/structured-outputs
- WWDC19 — Multi-camera capture: https://developer.apple.com/videos/play/wwdc2019/249/
