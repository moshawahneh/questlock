import FamilyControls
import SwiftUI

struct SettingsView: View {
    @Environment(SessionModel.self) private var session
    @Environment(LockModel.self) private var locks
    @Environment(ScheduleModel.self) private var schedules
    @State private var editingName = false
    @State private var showingPicker = false
    @State private var savedNote: String?

    var body: some View {
        NavigationStack {
            List {
                Section("You") {
                    Button {
                        editingName = true
                    } label: {
                        LabeledContent("Name", value: session.profile?.display_name ?? "Not set")
                    }
                    LabeledContent("Time zone", value: session.profile?.timezone ?? TimeZone.current.identifier)
                }

                Section {
                    NavigationLink("Weekly schedule") {
                        ScheduleEditorView(initial: schedules.latest) { schedule in
                            guard let starts = await schedules.save(schedule) else {
                                session.errorMessage = schedules.errorMessage
                                return false
                            }
                            savedNote = "Saved. Your new schedule starts \(Self.friendlyDate(starts))."
                            return true
                        }
                        .navigationTitle("Weekly schedule")
                    }
                    if let pending = locks.pendingSchedule {
                        Text("Changes start \(Self.friendlyDate(pending.effectiveFrom)).")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Button {
                        showingPicker = true
                    } label: {
                        LabeledContent("Apps to block", value: locks.selectionSummary)
                    }
                    .disabled(locks.isLocked)
                    if locks.isLocked {
                        Text("You can't change blocked apps while they're locked.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Lock")
                } footer: {
                    if let savedNote { Text(savedNote) }
                }

                Section {
                    Button("Sign out", role: .destructive) {
                        Task { await session.signOut(locks: locks) }
                    }
                }

                Section("Diagnostics") {
                    // Proves the signed build has the App Group entitlement.
                    LabeledContent("App Group", value: AppGroup.containerURL == nil ? "Missing" : "OK")
                    LabeledContent("Screen Time", value: locks.isAuthorized ? "Allowed" : "Not allowed")
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $editingName) {
                TextEntrySheet(title: "Your name", prompt: "Name", actionTitle: "Save",
                               initial: session.profile?.display_name ?? "") { name in
                    await session.updateDisplayName(name)
                }
            }
            .familyActivityPicker(
                headerText: "Choose the apps QuestLock locks until you check in.",
                isPresented: $showingPicker,
                selection: Binding(get: { locks.selection }, set: { locks.updateSelection($0) })
            )
        }
    }

    /// "2026-10-24" → "tomorrow" / "Saturday 24 October".
    static func friendlyDate(_ isoDate: String) -> String {
        let parser = DateFormatter()
        parser.calendar = Calendar(identifier: .gregorian)
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: isoDate) else { return isoDate }
        if Calendar.current.isDateInTomorrow(date) { return "tomorrow" }
        if Calendar.current.isDateInToday(date) { return "today" }
        return date.formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}
