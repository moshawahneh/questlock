import SwiftUI

/// Per-weekday deadline + lock lead, or a rest day. Saving stores a new version that starts tomorrow.
struct ScheduleEditorView: View {
    let initial: WeeklySchedule
    var saveTitle = "Save schedule"
    let onSave: (WeeklySchedule) async -> Bool

    @State private var drafts: [Weekday: DayDraft] = [:]
    @State private var saving = false

    struct DayDraft: Equatable {
        var enabled: Bool
        var deadline: Date
        var leadMinutes: Int

        var time: TimeOfDay {
            let parts = Calendar.current.dateComponents([.hour, .minute], from: deadline)
            return TimeOfDay(hour: parts.hour ?? 10, minute: parts.minute ?? 0)
        }
    }

    var body: some View {
        Form {
            Section {
                Button("Weekdays by 10:00, weekends by 12:00") { applyPreset() }
            } footer: {
                Text("Pick a check-in deadline for each day. Your apps lock for a set time before it, until you post your photo.")
            }
            ForEach(Weekday.mondayFirst, id: \.self) { weekday in
                daySection(weekday)
            }
            Section {
                Button {
                    Task { await save() }
                } label: {
                    HStack {
                        Text(saveTitle)
                        if saving { Spacer(); ProgressView() }
                    }
                }
                .disabled(saving || validationMessage != nil)
            } footer: {
                if let validationMessage {
                    Text(validationMessage).foregroundStyle(.red)
                } else {
                    Text("Changes start tomorrow, so you can't move today's deadline once it's close.")
                }
            }
        }
        .onAppear { if drafts.isEmpty { load(initial) } }
    }

    private func daySection(_ weekday: Weekday) -> some View {
        let binding = Binding(get: { drafts[weekday] ?? Self.defaultDraft(for: weekday, enabled: false) },
                              set: { drafts[weekday] = $0 })
        return Section(weekday.name) {
            Toggle("Lock day", isOn: binding.enabled)
            if binding.wrappedValue.enabled {
                DatePicker("Check in by", selection: binding.deadline, displayedComponents: .hourAndMinute)
                Stepper(value: binding.leadMinutes, in: ScheduleMath.minimumLeadMinutes...ScheduleMath.maximumLeadMinutes, step: 15) {
                    LabeledContent("Lock before", value: Self.duration(binding.wrappedValue.leadMinutes))
                }
                if let start = try? ScheduleMath.lockStart(deadline: binding.wrappedValue.time, leadMinutes: binding.wrappedValue.leadMinutes) {
                    Text("Apps lock \(start.formatted)–\(binding.wrappedValue.time.formatted)")
                        .font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text("The lock would start before midnight. Pick a later deadline or a shorter lock.")
                        .font(.footnote).foregroundStyle(.red)
                }
            } else {
                Text("Rest day: no lock, and your streak isn't affected.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Data

    private var schedule: WeeklySchedule {
        WeeklySchedule(days: drafts.reduce(into: [:]) { result, entry in
            guard entry.value.enabled else { return }
            result[entry.key] = DaySchedule(deadline: entry.value.time, leadMinutes: entry.value.leadMinutes)
        })
    }

    private var validationMessage: String? {
        if schedule.days.isEmpty { return "Pick at least one lock day." }
        for weekday in Weekday.mondayFirst {
            if let day = schedule.days[weekday], (try? ScheduleMath.lockStart(deadline: day.deadline, leadMinutes: day.leadMinutes)) == nil {
                return "\(weekday.name): the lock would start before midnight."
            }
        }
        return nil
    }

    private func save() async {
        saving = true
        defer { saving = false }
        _ = await onSave(schedule)
    }

    private func load(_ schedule: WeeklySchedule) {
        for weekday in Weekday.allCases {
            if let day = schedule.days[weekday] {
                drafts[weekday] = DayDraft(enabled: true, deadline: Self.date(day.deadline), leadMinutes: day.leadMinutes)
            } else {
                drafts[weekday] = Self.defaultDraft(for: weekday, enabled: false)
            }
        }
    }

    private func applyPreset() {
        for weekday in Weekday.allCases {
            drafts[weekday] = Self.defaultDraft(for: weekday, enabled: true)
        }
    }

    private static func defaultDraft(for weekday: Weekday, enabled: Bool) -> DayDraft {
        let weekend = weekday == .saturday || weekday == .sunday
        return DayDraft(enabled: enabled, deadline: date(TimeOfDay(hour: weekend ? 12 : 10, minute: 0)), leadMinutes: 120)
    }

    private static func date(_ time: TimeOfDay) -> Date {
        Calendar.current.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: .now) ?? .now
    }

    static func duration(_ minutes: Int) -> String {
        let h = minutes / 60, m = minutes % 60
        switch (h, m) {
        case (0, _): return "\(m) min"
        case (_, 0): return "\(h) h"
        default: return "\(h) h \(m) min"
        }
    }
}
