# 001 — App name and bundle IDs

**Status:** accepted · 2026-10-18

## Context

The bundle IDs go into Apple's Family Controls (Distribution) entitlement request, which is approved per bundle ID and takes weeks. Changing a bundle ID later means a new request, so the name had to be fixed before Phase 0. The working name "Wakeproof" turned out to be taken: several App Store alarm-clock apps are called "WakeProof".

## Decision

- Name: **QuestLock**: your apps stay locked until you complete today's "quest" (photograph the target). It also fits future habit types (gym, reading), which `habits.type` already allows for.
- Bundle IDs: `com.mohammadshaw.questlock`, `com.mohammadshaw.questlock.monitor`, `.shieldconfig`, `.shieldaction` (extensions must be prefixed by the app's ID). Test bundle: `.tests`.
- App Group: `group.com.mohammadshaw.questlock`.
- Prefix `com.mohammadshaw` comes from Mo's name (and his former GitHub handle `MohammadShaw`; the account is now `moshawahneh`). Bundle IDs don't have to match the GitHub account.

## Alternatives considered

Checked against the App Store search API (US and UK stores) and a web search on 2026-10-18:

| Name | Result |
|---|---|
| Wakeproof | Taken (several alarm apps) |
| Upcheck | Taken (several "UpCheck" apps) |
| Proofpact | Free, but the habit space is full of "Pact" apps (Pact, Daily Pact, Tiny Pact, PactPic) |
| Riseproof | Free, but only about mornings |
| Proofday | Free, but too close to "Proofs: Photo Habit Tracker" |

This was a store and web search, not a trademark search. The App Store display name can be changed with any update; only the bundle IDs are permanent.
