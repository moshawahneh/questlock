import DeviceActivity
import Foundation
import Testing
@testable import QuestLock

struct ScheduleMathTests {
    /// Fixed calendar and time zone so results don't depend on the machine running the tests.
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        return calendar
    }()

    static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
    }

    /// Monday–Friday 10:00 deadline, 2 h lead; weekends are rest days.
    static let weekdaysOnly = WeeklySchedule(days: [
        .monday: DaySchedule(deadline: TimeOfDay(hour: 10, minute: 0), leadMinutes: 120),
        .tuesday: DaySchedule(deadline: TimeOfDay(hour: 10, minute: 0), leadMinutes: 120),
        .wednesday: DaySchedule(deadline: TimeOfDay(hour: 10, minute: 0), leadMinutes: 120),
        .thursday: DaySchedule(deadline: TimeOfDay(hour: 10, minute: 0), leadMinutes: 120),
        .friday: DaySchedule(deadline: TimeOfDay(hour: 10, minute: 0), leadMinutes: 120),
    ])

    // MARK: lockStart

    @Test func lockStartSubtractsLead() throws {
        #expect(try ScheduleMath.lockStart(deadline: TimeOfDay(hour: 10, minute: 0), leadMinutes: 120) == TimeOfDay(hour: 8, minute: 0))
        #expect(try ScheduleMath.lockStart(deadline: TimeOfDay(hour: 9, minute: 5), leadMinutes: 20) == TimeOfDay(hour: 8, minute: 45))
    }

    @Test func lockStartAcceptsLimits() throws {
        #expect(try ScheduleMath.lockStart(deadline: TimeOfDay(hour: 7, minute: 0), leadMinutes: 15) == TimeOfDay(hour: 6, minute: 45))
        #expect(try ScheduleMath.lockStart(deadline: TimeOfDay(hour: 7, minute: 0), leadMinutes: 360) == TimeOfDay(hour: 1, minute: 0))
        // Starting exactly at midnight is fine; starting before it isn't.
        #expect(try ScheduleMath.lockStart(deadline: TimeOfDay(hour: 0, minute: 15), leadMinutes: 15) == TimeOfDay(hour: 0, minute: 0))
    }

    @Test func lockStartRejectsLeadUnder15Minutes() {
        #expect(throws: ScheduleError.leadTooShort) {
            try ScheduleMath.lockStart(deadline: TimeOfDay(hour: 10, minute: 0), leadMinutes: 14)
        }
    }

    @Test func lockStartRejectsLeadOver6Hours() {
        #expect(throws: ScheduleError.leadTooLong) {
            try ScheduleMath.lockStart(deadline: TimeOfDay(hour: 10, minute: 0), leadMinutes: 361)
        }
    }

    @Test func lockStartRejectsWindowCrossingMidnight() {
        #expect(throws: ScheduleError.crossesMidnight) {
            try ScheduleMath.lockStart(deadline: TimeOfDay(hour: 1, minute: 0), leadMinutes: 120)
        }
        #expect(throws: ScheduleError.crossesMidnight) {
            try ScheduleMath.lockStart(deadline: TimeOfDay(hour: 0, minute: 10), leadMinutes: 15)
        }
    }

    // MARK: isInsideLockWindow

    @Test func insideWindowIsStartInclusiveEndExclusive() {
        // 2026-10-19 is a Monday.
        let s = Self.weekdaysOnly, c = Self.calendar
        #expect(!ScheduleMath.isInsideLockWindow(now: Self.date(2026, 10, 19, 7, 59, second: 59), schedule: s, calendar: c))
        #expect(ScheduleMath.isInsideLockWindow(now: Self.date(2026, 10, 19, 8, 0), schedule: s, calendar: c))
        #expect(ScheduleMath.isInsideLockWindow(now: Self.date(2026, 10, 19, 9, 59, second: 59), schedule: s, calendar: c))
        #expect(!ScheduleMath.isInsideLockWindow(now: Self.date(2026, 10, 19, 10, 0), schedule: s, calendar: c))
    }

    @Test func restDayIsNeverLocked() {
        // 2026-10-18 is a Sunday, which has no entry.
        #expect(!ScheduleMath.isInsideLockWindow(now: Self.date(2026, 10, 18, 9, 0), schedule: Self.weekdaysOnly, calendar: Self.calendar))
        #expect(ScheduleMath.lockWindow(on: Self.date(2026, 10, 18, 9, 0), schedule: Self.weekdaysOnly, calendar: Self.calendar) == nil)
    }

    @Test func weekdayBoundaryUsesTheRightDay() {
        // Friday locks; the Saturday right after doesn't, even at the same time.
        let s = Self.weekdaysOnly, c = Self.calendar
        #expect(ScheduleMath.isInsideLockWindow(now: Self.date(2026, 10, 23, 9, 0), schedule: s, calendar: c))
        #expect(!ScheduleMath.isInsideLockWindow(now: Self.date(2026, 10, 24, 9, 0), schedule: s, calendar: c))
        // Sunday 23:59 → Monday 00:00: neither is inside the 08:00–10:00 window.
        #expect(!ScheduleMath.isInsideLockWindow(now: Self.date(2026, 10, 18, 23, 59), schedule: s, calendar: c))
        #expect(!ScheduleMath.isInsideLockWindow(now: Self.date(2026, 10, 19, 0, 0), schedule: s, calendar: c))
    }

    @Test func differentDeadlinesPerWeekday() {
        let schedule = WeeklySchedule.phase1Default // Sat/Sun 12:00, weekdays 10:00, 2 h lead
        let c = Self.calendar
        #expect(!ScheduleMath.isInsideLockWindow(now: Self.date(2026, 10, 24, 9, 0), schedule: schedule, calendar: c)) // Sat, before 10:00
        #expect(ScheduleMath.isInsideLockWindow(now: Self.date(2026, 10, 24, 11, 0), schedule: schedule, calendar: c)) // Sat, 10:00–12:00
        #expect(!ScheduleMath.isInsideLockWindow(now: Self.date(2026, 10, 23, 11, 0), schedule: schedule, calendar: c)) // Fri, after 10:00
    }

    @Test func invalidDayScheduleNeverLocks() {
        let bad = WeeklySchedule(days: [.monday: DaySchedule(deadline: TimeOfDay(hour: 10, minute: 0), leadMinutes: 5)])
        #expect(!ScheduleMath.isInsideLockWindow(now: Self.date(2026, 10, 19, 9, 58), schedule: bad, calendar: Self.calendar))
    }

    @Test func windowFollowsTheCalendarsTimeZone() {
        var berlin = Calendar(identifier: .gregorian)
        berlin.timeZone = TimeZone(identifier: "Europe/Berlin")!
        let moment = Self.date(2026, 10, 19, 9, 15) // 09:15 London = 10:15 Berlin
        #expect(ScheduleMath.isInsideLockWindow(now: moment, schedule: Self.weekdaysOnly, calendar: Self.calendar))
        #expect(!ScheduleMath.isInsideLockWindow(now: moment, schedule: Self.weekdaysOnly, calendar: berlin))
    }

    // MARK: DeviceActivity components

    @Test func weeklyComponentsCarryWeekdayAndTimes() throws {
        let (start, end) = try ScheduleMath.weeklyIntervalComponents(
            for: DaySchedule(deadline: TimeOfDay(hour: 10, minute: 30), leadMinutes: 90), on: .tuesday)
        #expect(start == DateComponents(hour: 9, minute: 0, weekday: 3))
        #expect(end == DateComponents(hour: 10, minute: 30, weekday: 3))
    }

    // MARK: Weekday numbering

    @Test func isoWeekdaysMapToFoundationWeekdays() {
        #expect(Weekday(iso: 1) == .monday)
        #expect(Weekday(iso: 6) == .saturday)
        #expect(Weekday(iso: 7) == .sunday)
        #expect(Weekday(iso: 0) == nil)
        #expect(Weekday(iso: 8) == nil)
        for day in Weekday.allCases {
            #expect(Weekday(iso: day.iso) == day)
        }
    }

    // MARK: Pending schedules (edits apply from tomorrow)

    static let lateSchedule = WeeklySchedule(days: [
        .monday: DaySchedule(deadline: TimeOfDay(hour: 12, minute: 0), leadMinutes: 60),
        .tuesday: DaySchedule(deadline: TimeOfDay(hour: 12, minute: 0), leadMinutes: 60),
    ])

    @Test func pendingScheduleStartsOnItsDate() {
        let pending = PendingSchedule(effectiveFrom: "2026-10-20", schedule: Self.lateSchedule) // a Tuesday
        let c = Self.calendar
        // Monday 19th: still the current schedule (08:00–10:00).
        #expect(ScheduleMath.schedule(on: Self.date(2026, 10, 19, 9, 0), current: Self.weekdaysOnly, pending: pending, calendar: c) == Self.weekdaysOnly)
        // Tuesday 20th and later: the pending one (11:00–12:00).
        #expect(ScheduleMath.schedule(on: Self.date(2026, 10, 20, 0, 0), current: Self.weekdaysOnly, pending: pending, calendar: c) == Self.lateSchedule)
        #expect(ScheduleMath.schedule(on: Self.date(2026, 10, 27, 9, 0), current: Self.weekdaysOnly, pending: pending, calendar: c) == Self.lateSchedule)
    }

    @Test func localDateIsZeroPadded() {
        #expect(ScheduleMath.localDate(Self.date(2026, 3, 7, 23, 59), calendar: Self.calendar) == "2026-03-07")
    }

    @Test func nextDayScheduleKeepsTodaysRuleUntilItsWindowEnds() {
        // Monday 19th, schedule edited today → pending from Tuesday 20th.
        let pending = PendingSchedule(effectiveFrom: "2026-10-20", schedule: Self.lateSchedule)
        let c = Self.calendar
        let monday = Weekday.monday
        // 07:00, before today's 08:00–10:00 window: register today's (old) rule.
        #expect(ScheduleMath.nextDaySchedule(for: monday, now: Self.date(2026, 10, 19, 7, 0), current: Self.weekdaysOnly, pending: pending, calendar: c)?.deadline == TimeOfDay(hour: 10, minute: 0))
        // 10:30, after today's window: next Monday falls under the new rule.
        #expect(ScheduleMath.nextDaySchedule(for: monday, now: Self.date(2026, 10, 19, 10, 30), current: Self.weekdaysOnly, pending: pending, calendar: c)?.deadline == TimeOfDay(hour: 12, minute: 0))
        // Wednesday: a lock day now, a rest day in the new schedule.
        #expect(ScheduleMath.nextDaySchedule(for: .wednesday, now: Self.date(2026, 10, 19, 7, 0), current: Self.weekdaysOnly, pending: pending, calendar: c) == nil)
    }

    // MARK: Activity names

    @Test func activityNamesRoundTrip() {
        for activity in [LockActivity.debug, .weekly(.monday), .weekly(.saturday), .test(.sunday)] {
            #expect(LockActivity(activity.name) == activity)
        }
        #expect(LockActivity(.init("something-else")) == nil)
    }
}
