import Foundation

enum ScheduleError: Error, Equatable {
    /// DeviceActivity rejects intervals shorter than 15 minutes (`intervalTooShort`).
    case leadTooShort
    case leadTooLong
    /// The lock would have to start the day before the deadline. Not supported, to keep date maths simple.
    case crossesMidnight
}

/// Pure schedule calculations shared by the app and the Monitor extension. No storage, no side effects.
enum ScheduleMath {
    static let minimumLeadMinutes = 15
    static let maximumLeadMinutes = 6 * 60

    /// When the apps lock: `deadline − lead`, on the same day.
    static func lockStart(deadline: TimeOfDay, leadMinutes: Int) throws(ScheduleError) -> TimeOfDay {
        guard leadMinutes >= minimumLeadMinutes else { throw .leadTooShort }
        guard leadMinutes <= maximumLeadMinutes else { throw .leadTooLong }
        let start = deadline.minutesSinceMidnight - leadMinutes
        guard start >= 0 else { throw .crossesMidnight }
        return TimeOfDay(minutesSinceMidnight: start)
    }

    /// The lock window `[lockStart, deadline)` on the calendar day of `date`, or nil on a rest day
    /// or for an invalid schedule.
    static func lockWindow(on date: Date, schedule: WeeklySchedule, calendar: Calendar) -> DateInterval? {
        guard let day = schedule.days[Weekday(of: date, calendar: calendar)],
              let start = try? lockStart(deadline: day.deadline, leadMinutes: day.leadMinutes),
              let startDate = calendar.date(bySettingHour: start.hour, minute: start.minute, second: 0, of: date),
              let endDate = calendar.date(bySettingHour: day.deadline.hour, minute: day.deadline.minute, second: 0, of: date),
              startDate < endDate
        else { return nil }
        return DateInterval(start: startDate, end: endDate)
    }

    /// True from the lock start (inclusive) up to the deadline (exclusive).
    static func isInsideLockWindow(now: Date, schedule: WeeklySchedule, calendar: Calendar) -> Bool {
        guard let window = lockWindow(on: now, schedule: schedule, calendar: calendar) else { return false }
        return window.start <= now && now < window.end
    }

    /// The local calendar date of `date` as "yyyy-MM-dd" (sorts correctly as a string).
    static func localDate(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// The schedule in force on `date`: the pending one once its start date is reached, otherwise the current one.
    static func schedule(on date: Date, current: WeeklySchedule, pending: PendingSchedule?, calendar: Calendar) -> WeeklySchedule {
        if let pending, localDate(date, calendar: calendar) >= pending.effectiveFrom {
            return pending.schedule
        }
        return current
    }

    /// What to register with DeviceActivity for `weekday`: the rule for that weekday's next lock window.
    /// Today counts if its window hasn't ended yet; otherwise it's the same weekday next week, which may
    /// fall under the pending schedule. Nil means a rest day (register nothing).
    static func nextDaySchedule(for weekday: Weekday, now: Date, current: WeeklySchedule, pending: PendingSchedule?, calendar: Calendar) -> DaySchedule? {
        let today = calendar.startOfDay(for: now)
        for offset in 0...7 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: today),
                  Weekday(of: date, calendar: calendar) == weekday else { continue }
            let inForce = schedule(on: date, current: current, pending: pending, calendar: calendar)
            if offset == 0 {
                // Today: only if there's a window that hasn't finished.
                guard let window = lockWindow(on: now, schedule: inForce, calendar: calendar), now < window.end else { continue }
            }
            return inForce.days[weekday]
        }
        return nil
    }

    /// Repeating-weekly `DateComponents` for `DeviceActivitySchedule(intervalStart:intervalEnd:repeats: true)`.
    static func weeklyIntervalComponents(for day: DaySchedule, on weekday: Weekday) throws(ScheduleError) -> (start: DateComponents, end: DateComponents) {
        let start = try lockStart(deadline: day.deadline, leadMinutes: day.leadMinutes)
        return (
            DateComponents(hour: start.hour, minute: start.minute, weekday: weekday.rawValue),
            DateComponents(hour: day.deadline.hour, minute: day.deadline.minute, weekday: weekday.rawValue)
        )
    }
}
