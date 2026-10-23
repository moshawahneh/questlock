import Foundation
import Testing
@testable import QuestLock

/// The rule that decides whether an `intervalDidEnd` really ends the lock.
/// Cases come from the iPhone 11 lock log of 23 Oct 2026 (window 23:06–23:40).
struct LockEngineTests {
    static let start = Date(timeIntervalSince1970: 1_792_879_560) // any fixed instant works
    static let end = start.addingTimeInterval(34 * 60)
    static let weekly = LockEngine.Window(activity: .weekly(.friday), interval: DateInterval(start: start, end: end))

    @Test func endFromReRegisteringMidWindowKeepsTheLock() {
        // 23:06:17: the app re-registered the schedule; iOS sent "End" 16 seconds into a 34-minute window.
        let now = Self.start.addingTimeInterval(16)
        #expect(LockEngine.keepLockedAfterEnd(now: now, windows: [Self.weekly], unlockedUntil: nil, hasSelection: true))
    }

    @Test func realEndUnlocks() {
        #expect(!LockEngine.keepLockedAfterEnd(now: Self.end, windows: [], unlockedUntil: nil, hasSelection: true))
        // A callback a few seconds early still counts as the real end.
        let early = Self.end.addingTimeInterval(-10)
        #expect(!LockEngine.keepLockedAfterEnd(now: early, windows: [Self.weekly], unlockedUntil: nil, hasSelection: true))
    }

    @Test func checkedInOrNothingChosenUnlocks() {
        let now = Self.start.addingTimeInterval(60)
        #expect(!LockEngine.keepLockedAfterEnd(now: now, windows: [Self.weekly], unlockedUntil: Self.end, hasSelection: true))
        #expect(!LockEngine.keepLockedAfterEnd(now: now, windows: [Self.weekly], unlockedUntil: nil, hasSelection: false))
    }

    @Test func anOverlappingLockKeepsShieldsWhenOneEnds() {
        // A test lock ends while the weekly window still has 20 minutes left.
        let now = Self.end.addingTimeInterval(-20 * 60)
        let debug = LockEngine.Window(activity: .debug, interval: DateInterval(start: now.addingTimeInterval(-15 * 60), end: now))
        #expect(LockEngine.keepLockedAfterEnd(now: now, windows: [debug, Self.weekly], unlockedUntil: nil, hasSelection: true))
        #expect(!LockEngine.keepLockedAfterEnd(now: now, windows: [debug], unlockedUntil: nil, hasSelection: true))
    }
}
