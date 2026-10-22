import Foundation

/// A wall-clock time with minute precision, e.g. 10:00.
struct TimeOfDay: Codable, Hashable, Sendable, Comparable {
    var hour: Int
    var minute: Int

    init(hour: Int, minute: Int) {
        precondition((0..<24).contains(hour) && (0..<60).contains(minute), "Invalid time \(hour):\(minute)")
        self.hour = hour
        self.minute = minute
    }

    init(minutesSinceMidnight: Int) {
        self.init(hour: minutesSinceMidnight / 60, minute: minutesSinceMidnight % 60)
    }

    var minutesSinceMidnight: Int { hour * 60 + minute }

    static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        lhs.minutesSinceMidnight < rhs.minutesSinceMidnight
    }

    var formatted: String { String(format: "%02d:%02d", hour, minute) }
}

/// Uses Foundation's numbering (`Calendar.component(.weekday, from:)`): 1 = Sunday … 7 = Saturday.
enum Weekday: Int, Codable, CaseIterable, Sendable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    init(of date: Date, calendar: Calendar) {
        self.init(rawValue: calendar.component(.weekday, from: date))!
    }

    var shortName: String {
        ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][rawValue - 1]
    }
}

/// One day's rule: the check-in deadline, and how long before it the apps lock.
struct DaySchedule: Codable, Hashable, Sendable {
    var deadline: TimeOfDay
    var leadMinutes: Int
}

/// The full week. A weekday with no entry is a rest day: no lock, no streak change.
struct WeeklySchedule: Codable, Hashable, Sendable {
    var days: [Weekday: DaySchedule]

    /// Phase 1's hardcoded schedule (the schedule editor arrives in Phase 2):
    /// Mon–Fri deadline 10:00, Sat–Sun 12:00, apps lock 2 hours before.
    static let phase1Default = WeeklySchedule(days: Dictionary(uniqueKeysWithValues: Weekday.allCases.map { day in
        let weekend = day == .saturday || day == .sunday
        return (day, DaySchedule(deadline: TimeOfDay(hour: weekend ? 12 : 10, minute: 0), leadMinutes: 120))
    }))
}

/// A one-off lock started from the Today tab's testing section.
struct DebugLock: Codable, Hashable, Sendable {
    var start: Date
    var end: Date
}

/// A line in the on-screen log, written by the app and the Monitor extension.
struct LockEvent: Codable, Hashable, Sendable, Identifiable {
    var id = UUID()
    var date: Date
    var message: String
}
