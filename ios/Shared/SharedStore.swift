import FamilyControls
import Foundation

/// Typed access to the App Group storage shared by the app and its extensions.
/// Each value is stored as JSON under its own key in `AppGroup.defaults`.
enum SharedStore {
    private enum Key {
        static let selection = "selection"
        static let weeklySchedule = "weeklySchedule"
        static let weeklyEnabled = "weeklyEnabled"
        static let testSchedule = "testSchedule"
        static let debugLock = "debugLock"
        static let unlockedUntil = "unlockedUntil"
        static let todayTarget = "todayTarget"
        static let shieldsApplied = "shieldsApplied"
        static let events = "events"
    }

    /// The apps, categories and websites the user chose to block (opaque tokens, never app names).
    static var selection: FamilyActivitySelection {
        get { read(Key.selection) ?? FamilyActivitySelection() }
        set { write(newValue, Key.selection) }
    }

    static var weeklySchedule: WeeklySchedule {
        get { read(Key.weeklySchedule) ?? .phase1Default }
        set { write(newValue, Key.weeklySchedule) }
    }

    /// Off until the user turns it on, so picking apps doesn't immediately start daily locks.
    static var weeklyEnabled: Bool {
        get { read(Key.weeklyEnabled) ?? false }
        set { write(newValue, Key.weeklyEnabled) }
    }

    /// The "tomorrow only" test schedule from the Today tab (empty when unused).
    static var testSchedule: WeeklySchedule {
        get { read(Key.testSchedule) ?? WeeklySchedule(days: [:]) }
        set { write(newValue, Key.testSchedule) }
    }

    static var debugLock: DebugLock? {
        get { read(Key.debugLock) }
        set { write(newValue, Key.debugLock) }
    }

    /// Set by "Unlock now" (and from Phase 3 by a verified check-in): no shields until this time.
    static var unlockedUntil: Date? {
        get { read(Key.unlockedUntil) }
        set { write(newValue, Key.unlockedUntil) }
    }

    /// Today's target, shown on the shield. Hardcoded until the AI picks it in Phase 4.
    static var todayTarget: String {
        get { read(Key.todayTarget) ?? "find a bench" }
        set { write(newValue, Key.todayTarget) }
    }

    /// What this app last did to the shields, so reconcile can tell when it had to correct something.
    static var shieldsApplied: Bool {
        get { read(Key.shieldsApplied) ?? false }
        set { write(newValue, Key.shieldsApplied) }
    }

    /// Most recent first, capped at 40 entries.
    static var events: [LockEvent] {
        get { read(Key.events) ?? [] }
        set { write(Array(newValue.prefix(40)), Key.events) }
    }

    static func log(_ message: String, at date: Date = .now) {
        events = [LockEvent(date: date, message: message)] + events
    }

    // MARK: - JSON helpers

    private static func read<T: Decodable>(_ key: String) -> T? {
        guard let data = AppGroup.defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private static func write<T: Encodable>(_ value: T?, _ key: String) {
        guard let value, let data = try? JSONEncoder().encode(value) else {
            AppGroup.defaults.removeObject(forKey: key)
            return
        }
        AppGroup.defaults.set(data, forKey: key)
    }
}
