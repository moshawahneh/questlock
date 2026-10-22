import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

extension ManagedSettingsStore.Name {
    /// Our own named store, so clearing it never touches restrictions set by anything else.
    /// Computed rather than `static let`: `Name` isn't `Sendable`, so a stored global would be shared mutable state.
    static var questLock: Self { Self("questlock") }
}

/// The DeviceActivity names this app registers.
enum LockActivity: Equatable {
    case debug
    case weekly(Weekday)
    case test(Weekday)

    var name: DeviceActivityName {
        switch self {
        case .debug: DeviceActivityName("debug-lock")
        case .weekly(let day): DeviceActivityName("weekday-\(day.rawValue)")
        case .test(let day): DeviceActivityName("test-weekday-\(day.rawValue)")
        }
    }

    init?(_ name: DeviceActivityName) {
        let raw = name.rawValue
        if raw == "debug-lock" {
            self = .debug
        } else if raw.hasPrefix("test-weekday-"), let n = Int(raw.dropFirst("test-weekday-".count)), let day = Weekday(rawValue: n) {
            self = .test(day)
        } else if raw.hasPrefix("weekday-"), let n = Int(raw.dropFirst("weekday-".count)), let day = Weekday(rawValue: n) {
            self = .weekly(day)
        } else {
            return nil
        }
    }

    static var allWeekly: [DeviceActivityName] { Weekday.allCases.map { LockActivity.weekly($0).name } }
    static var allTest: [DeviceActivityName] { Weekday.allCases.map { LockActivity.test($0).name } }
}

/// Decides whether the apps should be locked and applies or clears the shields.
/// Used by the Monitor extension (on schedule) and by the app (reconcile on every foreground).
enum LockEngine {
    struct Window: Equatable {
        let activity: LockActivity
        let interval: DateInterval
    }

    /// Every lock window that contains `now`.
    static func activeWindows(now: Date, calendar: Calendar = .current) -> [Window] {
        var windows: [Window] = []
        if let debug = SharedStore.debugLock, debug.start <= now, now < debug.end {
            windows.append(Window(activity: .debug, interval: DateInterval(start: debug.start, end: debug.end)))
        }
        let weekday = Weekday(of: now, calendar: calendar)
        if SharedStore.weeklyEnabled,
           let window = ScheduleMath.lockWindow(on: now, schedule: SharedStore.weeklySchedule, calendar: calendar),
           window.start <= now, now < window.end {
            windows.append(Window(activity: .weekly(weekday), interval: window))
        }
        if let window = ScheduleMath.lockWindow(on: now, schedule: SharedStore.testSchedule, calendar: calendar),
           window.start <= now, now < window.end {
            windows.append(Window(activity: .test(weekday), interval: window))
        }
        return windows
    }

    static func shouldBeLocked(now: Date, excluding excluded: LockActivity? = nil) -> Bool {
        if let until = SharedStore.unlockedUntil, now < until { return false }
        guard hasSelection else { return false }
        return activeWindows(now: now).contains { $0.activity != excluded }
    }

    /// When the current lock ends, if locked.
    static func lockedUntil(now: Date) -> Date? {
        guard shouldBeLocked(now: now) else { return nil }
        return activeWindows(now: now).map(\.interval.end).max()
    }

    static var hasSelection: Bool {
        let selection = SharedStore.selection
        return !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty || !selection.webDomainTokens.isEmpty
    }

    // MARK: - Monitor extension callbacks

    static func intervalDidStart(_ name: DeviceActivityName, now: Date = .now, calendar: Calendar = .current) {
        guard let activity = LockActivity(name) else {
            SharedStore.log("Start: unknown activity \(name.rawValue), ignored", at: now)
            return
        }
        switch activity {
        case .weekly(let day), .test(let day):
            // Belt and braces: never lock on the wrong day, even if iOS fires a weekly schedule early.
            guard Weekday(of: now, calendar: calendar) == day else {
                SharedStore.log("Start \(name.rawValue) fired on \(Weekday(of: now, calendar: calendar).shortName), ignored", at: now)
                return
            }
        case .debug:
            break
        }
        if let until = SharedStore.unlockedUntil, now < until {
            SharedStore.log("Start \(name.rawValue): already unlocked, no shield", at: now)
            return
        }
        guard hasSelection else {
            SharedStore.log("Start \(name.rawValue): no apps chosen, no shield", at: now)
            return
        }
        applyShields()
        SharedStore.log("Start \(name.rawValue): apps locked", at: now)
    }

    static func intervalDidEnd(_ name: DeviceActivityName, now: Date = .now) {
        let activity = LockActivity(name)
        if case .debug = activity { SharedStore.debugLock = nil }
        if shouldBeLocked(now: now, excluding: activity) {
            SharedStore.log("End \(name.rawValue): another lock still running, shields stay", at: now)
            return
        }
        clearShields()
        SharedStore.log("End \(name.rawValue): apps unlocked", at: now)
    }

    // MARK: - Reconcile (app, every foreground)

    /// The Monitor extension can miss callbacks, so the app re-checks whenever it comes to the foreground.
    @discardableResult
    static func reconcile(now: Date = .now) -> Bool {
        let wasLocked = SharedStore.shieldsApplied
        let locked = shouldBeLocked(now: now)
        if locked {
            applyShields()
        } else {
            clearShields()
        }
        if locked != wasLocked {
            SharedStore.log("Reconcile: \(locked ? "locked" : "unlocked") apps", at: now)
        }
        return locked
    }

    // MARK: - Shields

    static func applyShields() {
        let selection = SharedStore.selection
        let store = ManagedSettingsStore(named: .questLock)
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
        store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
        store.shield.webDomainCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
        SharedStore.shieldsApplied = true
    }

    static func clearShields() {
        ManagedSettingsStore(named: .questLock).clearAllSettings()
        SharedStore.shieldsApplied = false
    }
}
