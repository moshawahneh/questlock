import Foundation

/// Rows as the Supabase REST API returns them. Property names match the database columns.

struct Profile: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    var display_name: String?
    var timezone: String
    var current_streak: Int
    var longest_streak: Int
}

struct GroupSummary: Decodable, Identifiable, Hashable, Sendable {
    let id: UUID
    var name: String
    var invite_code: String
    var group_members: [Member]

    struct Member: Decodable, Identifiable, Hashable, Sendable {
        let user_id: UUID
        var role: String
        var joined_at: Date
        var profiles: MemberProfile

        var id: UUID { user_id }
        var isAdmin: Bool { role == "admin" }
    }

    struct MemberProfile: Decodable, Hashable, Sendable {
        var display_name: String?
        var current_streak: Int
        var longest_streak: Int
    }

    /// Leaderboard order: current streak, then longest-ever streak as the tie-break.
    var rankedMembers: [Member] {
        group_members.sorted {
            ($0.profiles.current_streak, $0.profiles.longest_streak) > ($1.profiles.current_streak, $1.profiles.longest_streak)
        }
    }
}

/// What `create_group` / `join_group` return.
struct GroupRow: Decodable, Hashable, Sendable {
    let id: UUID
    var name: String
    var invite_code: String
}

struct ScheduleRow: Decodable, Hashable, Sendable {
    var weekday: Int          // ISO: 1 = Monday … 7 = Sunday
    var deadline: String?     // "HH:MM:SS"; nil = rest day
    var lock_lead_minutes: Int?
    var effective_from: String // "yyyy-MM-dd"
}

extension WeeklySchedule {
    /// Builds a week from the rows of one schedule version.
    init(rows: [ScheduleRow]) {
        var days: [Weekday: DaySchedule] = [:]
        for row in rows {
            guard let weekday = Weekday(iso: row.weekday), let deadline = row.deadline,
                  let lead = row.lock_lead_minutes else { continue }
            let parts = deadline.split(separator: ":").compactMap { Int($0) }
            guard parts.count >= 2 else { continue }
            days[weekday] = DaySchedule(deadline: TimeOfDay(hour: parts[0], minute: parts[1]), leadMinutes: lead)
        }
        self.init(days: days)
    }
}
