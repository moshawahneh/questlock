import Foundation
import Observation
import Supabase

/// The user's weekly schedule on the server, and the copy the phone enforces.
/// The server is the source of truth: `save_schedule` stores a new version that starts tomorrow.
@MainActor
@Observable
final class ScheduleModel {
    private(set) var current = WeeklySchedule(days: [:])
    private(set) var pending: PendingSchedule?
    private(set) var hasAnySchedule = false
    var errorMessage: String?

    private let locks: LockModel

    init(locks: LockModel) {
        self.locks = locks
    }

    /// What the editor should start from: the newest saved version.
    var latest: WeeklySchedule { pending?.schedule ?? current }

    /// Downloads every version, works out which is in force today and which (if any) is pending,
    /// then hands both to the lock model.
    func pull() async {
        guard let client = Backend.client else { return }
        do {
            let rows: [ScheduleRow] = try await client.from("habit_schedules")
                .select("weekday, deadline, lock_lead_minutes, effective_from")
                .order("effective_from", ascending: false)
                .execute()
                .value
            apply(rows: rows)
        } catch {
            errorMessage = Backend.message(for: error)
        }
    }

    private func apply(rows: [ScheduleRow]) {
        hasAnySchedule = !rows.isEmpty
        let today = ScheduleMath.localDate(.now, calendar: .current)
        let versions = Dictionary(grouping: rows, by: \.effective_from)
        let currentDate = versions.keys.filter { $0 <= today }.max()
        let pendingDate = versions.keys.filter { $0 > today }.max()
        current = currentDate.map { WeeklySchedule(rows: versions[$0] ?? []) } ?? WeeklySchedule(days: [:])
        pending = pendingDate.map { PendingSchedule(effectiveFrom: $0, schedule: WeeklySchedule(rows: versions[$0] ?? [])) }
        locks.applySchedule(current: current, pending: pending)
    }

    /// Saves a new week. Returns the date it takes effect, or nil on failure.
    func save(_ schedule: WeeklySchedule) async -> String? {
        guard let client = Backend.client else { return nil }
        for (weekday, day) in schedule.days {
            do {
                _ = try ScheduleMath.lockStart(deadline: day.deadline, leadMinutes: day.leadMinutes)
            } catch {
                errorMessage = "\(weekday.name): " + Self.describe(error)
                return nil
            }
        }
        let days = schedule.days.map { weekday, day in
            SaveScheduleParams.Day(weekday: weekday.iso, deadline: day.deadline.formatted, lead_minutes: day.leadMinutes)
        }
        do {
            let effectiveFrom: String = try await client.rpc("save_schedule", params: SaveScheduleParams(p_days: days))
                .execute()
                .value
            await pull()
            return effectiveFrom
        } catch {
            errorMessage = Backend.message(for: error)
            return nil
        }
    }

    private static func describe(_ error: ScheduleError) -> String {
        switch error {
        case .leadTooShort: "apps must lock at least 15 minutes before the deadline."
        case .leadTooLong: "apps can lock at most 6 hours before the deadline."
        case .crossesMidnight: "the lock would start before midnight. Use a later deadline or a shorter lead."
        }
    }
}

private struct SaveScheduleParams: Encodable {
    let p_days: [Day]

    struct Day: Encodable {
        let weekday: Int
        let deadline: String
        let lead_minutes: Int
    }
}
