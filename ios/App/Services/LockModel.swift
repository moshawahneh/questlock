import DeviceActivity
import FamilyControls
import Foundation
import Observation
import UserNotifications

/// Screen Time state for the UI: permission, chosen apps, schedules and the current lock.
/// Registers DeviceActivity schedules (only the app can do that); the Monitor extension reacts to them.
@MainActor
@Observable
final class LockModel {
    private(set) var authorization: AuthorizationStatus = AuthorizationCenter.shared.authorizationStatus
    private(set) var selection = SharedStore.selection
    private(set) var weeklyEnabled = SharedStore.weeklyEnabled
    private(set) var schedule = SharedStore.weeklySchedule
    private(set) var pendingSchedule = SharedStore.pendingSchedule
    private(set) var isLocked = false
    private(set) var lockedUntil: Date?
    private(set) var debugLock = SharedStore.debugLock
    private(set) var testSchedule = SharedStore.testSchedule
    private(set) var events: [LockEvent] = []
    var errorMessage: String?

    private let center = DeviceActivityCenter()

    var isAuthorized: Bool {
        switch authorization {
        case .approved: true
        case .notDetermined, .denied: false
        default: true // .approvedWithDataAccess (iOS 26.4+) is also an approval
        }
    }

    var hasSelection: Bool {
        !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty || !selection.webDomainTokens.isEmpty
    }

    var selectionSummary: String {
        let apps = selection.applicationTokens.count, categories = selection.categoryTokens.count, sites = selection.webDomainTokens.count
        guard apps + categories + sites > 0 else { return "None chosen" }
        return [plural(apps, "app"), plural(categories, "category", "categories"), plural(sites, "website")]
            .compactMap { $0 }.joined(separator: ", ")
    }

    // MARK: - Permissions

    func requestAuthorization() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
        } catch {
            errorMessage = "Screen Time access wasn't granted: \(error.localizedDescription)"
        }
        // The shield's "Check in" button posts a notification, so ask for that too.
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        refresh()
    }

    // MARK: - Apps to block

    func updateSelection(_ newValue: FamilyActivitySelection) {
        // The picker calls this on every tick while it's open; only save real changes.
        guard newValue != SharedStore.selection else { return }
        SharedStore.selection = newValue
        SharedStore.log("Blocked apps changed: \(summary(of: newValue))")
        reconcile()
    }

    // MARK: - Schedules

    /// Pause or resume enforcing the weekly schedule on this phone (Testing section).
    func setWeeklyEnabled(_ enabled: Bool) {
        SharedStore.weeklyEnabled = enabled
        SharedStore.log(enabled ? "Weekly schedule on" : "Weekly schedule paused")
        registerWeeklySchedules()
        reconcile()
    }

    /// Stores the schedule from the server (current + pending) and re-registers it with iOS.
    func applySchedule(current: WeeklySchedule, pending: PendingSchedule?) {
        let changed = current != SharedStore.weeklySchedule || pending != SharedStore.pendingSchedule
        SharedStore.weeklySchedule = current
        SharedStore.pendingSchedule = pending
        if !current.days.isEmpty || pending.map({ !$0.schedule.days.isEmpty }) == true, !SharedStore.weeklyEnabled, changed {
            SharedStore.weeklyEnabled = true
        }
        if changed {
            SharedStore.log("Schedule updated" + (pending.map { " (changes start \($0.effectiveFrom))" } ?? ""))
        }
        registerWeeklySchedules()
        reconcile()
    }

    /// Registers one repeating DeviceActivity per lock weekday, using the rule for that weekday's next
    /// window, plus a repeating "Apps locked" notification at each lock start.
    func registerWeeklySchedules(now: Date = .now) {
        promotePendingScheduleIfDue(now: now)
        center.stopMonitoring(LockActivity.allWeekly)
        let notifications = UNUserNotificationCenter.current()
        notifications.removePendingNotificationRequests(withIdentifiers: Weekday.allCases.map { "lock-start-\($0.rawValue)" })
        guard SharedStore.weeklyEnabled else { return }

        let calendar = Calendar.current
        var failures: [String] = []
        for weekday in Weekday.allCases {
            guard let day = ScheduleMath.nextDaySchedule(for: weekday, now: now, current: SharedStore.weeklySchedule,
                                                          pending: SharedStore.pendingSchedule, calendar: calendar) else { continue }
            do {
                let (start, end) = try ScheduleMath.weeklyIntervalComponents(for: day, on: weekday)
                try center.startMonitoring(LockActivity.weekly(weekday).name,
                                           during: DeviceActivitySchedule(intervalStart: start, intervalEnd: end, repeats: true))
                notifications.add(Self.lockStartNotification(weekday: weekday, start: start, deadline: day.deadline))
            } catch {
                failures.append("\(weekday.shortName): \(error.localizedDescription)")
            }
        }
        if !failures.isEmpty {
            errorMessage = "Couldn't register the schedule for \(failures.joined(separator: ", "))"
        }
    }

    /// Once a pending schedule's start date arrives it becomes the current one.
    private func promotePendingScheduleIfDue(now: Date) {
        guard let pending = SharedStore.pendingSchedule,
              ScheduleMath.localDate(now, calendar: .current) >= pending.effectiveFrom else { return }
        SharedStore.weeklySchedule = pending.schedule
        SharedStore.pendingSchedule = nil
        SharedStore.log("New schedule in force from \(pending.effectiveFrom)")
    }

    private static func lockStartNotification(weekday: Weekday, start: DateComponents, deadline: TimeOfDay) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = "Apps locked"
        content.body = "Check in by \(deadline.formatted) to unlock. Today's quest: \(SharedStore.todayTarget)."
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: start, repeats: true)
        return UNNotificationRequest(identifier: "lock-start-\(weekday.rawValue)", content: content, trigger: trigger)
    }

    /// Signing out: stop every lock and forget this phone's schedule and app choice.
    func resetForSignOut() {
        center.stopMonitoring()
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        LockEngine.clearShields()
        SharedStore.weeklySchedule = WeeklySchedule(days: [:])
        SharedStore.pendingSchedule = nil
        SharedStore.weeklyEnabled = false
        SharedStore.testSchedule = WeeklySchedule(days: [:])
        SharedStore.debugLock = nil
        SharedStore.unlockedUntil = nil
        SharedStore.selection = FamilyActivitySelection()
        SharedStore.log("Signed out: locks removed")
        refresh()
    }

    /// One-off lock starting at the next whole minute + 1 (so 1–2 minutes from now), lasting 15 minutes,
    /// the shortest interval DeviceActivity accepts.
    func startDebugLock(now: Date = .now) {
        let calendar = Calendar.current
        guard let nextMinute = calendar.nextDate(after: now, matching: DateComponents(second: 0), matchingPolicy: .nextTime) else { return }
        let start = nextMinute.addingTimeInterval(60)
        let end = start.addingTimeInterval(TimeInterval(ScheduleMath.minimumLeadMinutes * 60))
        let parts: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute]
        let schedule = DeviceActivitySchedule(intervalStart: calendar.dateComponents(parts, from: start),
                                              intervalEnd: calendar.dateComponents(parts, from: end),
                                              repeats: false)
        center.stopMonitoring([LockActivity.debug.name])
        do {
            try center.startMonitoring(LockActivity.debug.name, during: schedule)
            SharedStore.debugLock = DebugLock(start: start, end: end)
            SharedStore.unlockedUntil = nil
            SharedStore.log("Test lock set: \(start.formatted(date: .omitted, time: .shortened))–\(end.formatted(date: .omitted, time: .shortened))")
        } catch {
            errorMessage = "Couldn't set the test lock: \(error.localizedDescription)"
        }
        refresh()
    }

    /// A 15-minute weekly lock on tomorrow's weekday only, to prove weekday schedules fire on the right day.
    func scheduleTomorrowTest(at time: TimeOfDay, now: Date = .now) {
        let calendar = Calendar.current
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) else { return }
        let weekday = Weekday(of: tomorrow, calendar: calendar)
        let deadline = TimeOfDay(minutesSinceMidnight: min(time.minutesSinceMidnight + ScheduleMath.minimumLeadMinutes, 24 * 60 - 1))
        let day = DaySchedule(deadline: deadline, leadMinutes: deadline.minutesSinceMidnight - time.minutesSinceMidnight)
        center.stopMonitoring(LockActivity.allTest)
        do {
            let (start, end) = try ScheduleMath.weeklyIntervalComponents(for: day, on: weekday)
            try center.startMonitoring(LockActivity.test(weekday).name,
                                       during: DeviceActivitySchedule(intervalStart: start, intervalEnd: end, repeats: true))
            SharedStore.testSchedule = WeeklySchedule(days: [weekday: day])
            SharedStore.log("Tomorrow test set: \(weekday.shortName) \(time.formatted)–\(deadline.formatted)")
        } catch {
            errorMessage = "Couldn't set the tomorrow test: \(error.localizedDescription)"
        }
        refresh()
    }

    func clearTomorrowTest() {
        center.stopMonitoring(LockActivity.allTest)
        SharedStore.testSchedule = WeeklySchedule(days: [:])
        SharedStore.log("Tomorrow test removed")
        reconcile()
    }

    /// Unlocks until the end of the current lock window. Phase 3 replaces this with a verified check-in.
    func unlockNow(now: Date = .now) {
        SharedStore.unlockedUntil = LockEngine.lockedUntil(now: now) ?? now
        if let debug = SharedStore.debugLock, now < debug.start {
            // A test lock that hasn't started yet: cancel it entirely.
            center.stopMonitoring([LockActivity.debug.name])
            SharedStore.debugLock = nil
        }
        LockEngine.clearShields()
        SharedStore.log("Unlocked now")
        refresh()
    }

    // MARK: - Reconcile

    /// Called whenever the app comes to the foreground. Corrects the shields if the Monitor extension
    /// missed a callback, then refreshes what the UI shows.
    func reconcile() {
        authorization = AuthorizationCenter.shared.authorizationStatus
        if let pending = SharedStore.pendingSchedule,
           ScheduleMath.localDate(.now, calendar: .current) >= pending.effectiveFrom {
            registerWeeklySchedules() // promotes it and re-registers with the new times
        }
        if isAuthorized {
            LockEngine.reconcile()
        }
        refresh()
    }

    private func refresh(now: Date = .now) {
        authorization = AuthorizationCenter.shared.authorizationStatus
        selection = SharedStore.selection
        weeklyEnabled = SharedStore.weeklyEnabled
        schedule = SharedStore.weeklySchedule
        pendingSchedule = SharedStore.pendingSchedule
        debugLock = SharedStore.debugLock
        testSchedule = SharedStore.testSchedule
        lockedUntil = LockEngine.lockedUntil(now: now)
        isLocked = lockedUntil != nil
        events = SharedStore.events
    }

    // MARK: - Helpers

    private func summary(of selection: FamilyActivitySelection) -> String {
        "\(selection.applicationTokens.count) apps, \(selection.categoryTokens.count) categories, \(selection.webDomainTokens.count) websites"
    }

    private func plural(_ count: Int, _ singular: String, _ pluralForm: String? = nil) -> String? {
        guard count > 0 else { return nil }
        return "\(count) \(count == 1 ? singular : (pluralForm ?? singular + "s"))"
    }
}
