# 003 — One lock engine shared by the app and the Monitor extension

**Status:** accepted · 2026-10-22

## Context

Two separate processes decide whether the chosen apps are shielded:

```
iOS scheduler ──intervalDidStart/End──▶ Monitor extension ─┐
                                                           ├─▶ LockEngine ──▶ ManagedSettingsStore("questlock")
app comes to foreground ──reconcile()──▶ QuestLock app ────┘        ▲
                                                                     └── reads SharedStore (App Group)
```

The Monitor extension is known to miss callbacks occasionally, so the app re-checks on every foreground. If the two processes used different rules, they would fight: the app could re-lock what the Monitor just unlocked, or the reverse.

## Decision

- All lock decisions live in `ios/Shared/LockEngine.swift`, which is compiled into both targets. `shouldBeLocked(now:)` is the only rule. It returns false if the user unlocked until later or no apps are chosen, and otherwise true if any lock window (test lock, weekly schedule, tomorrow-only test) contains `now`.
- Every input lives in the App Group (`SharedStore`): the selection, the schedules, the test lock, `unlockedUntil`, and today's target.
- Shields go into a **named** `ManagedSettingsStore` (`"questlock"`), so clearing it never removes restrictions set by anything else.
- "Unlock now", and from Phase 3 a verified check-in, set `unlockedUntil` to the end of the current window. Without it, the next reconcile would re-lock straight away.
- When a weekly callback fires, the Monitor checks that today's weekday matches the activity's weekday before locking.
- `intervalDidEnd` keeps the shields up if another window is still running (for example, a test lock that overlaps the weekly schedule).

## Alternatives considered

- **Let only the Monitor decide, with the app just displaying state**: simpler, but a missed `intervalDidStart` would leave the apps open for the whole morning.
- **Use the default (unnamed) store**: the code is shorter, but it shares the store with any other restriction source and gives less control over what gets cleared.
