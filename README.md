# QuestLock

An iOS app for small friend groups. Each morning your chosen apps (TikTok, Instagram…) stay locked until you go outside, find today's AI-picked target ("a bench", "a bus stop") and post a front + back photo of it. Friends see your streak, and you can't see their posts until you've posted yours.

**Status:** work in progress — Phase 0 (project skeleton). See [`docs/PLAN.md`](docs/PLAN.md) for the full plan and [`docs/PROGRESS.md`](docs/PROGRESS.md) for where things stand.

Stack: Swift + SwiftUI (Screen Time APIs: FamilyControls, ManagedSettings, DeviceActivity) · Supabase (Postgres + Row Level Security, Storage, Edge Functions) · Claude API for photo verification and daily targets.
