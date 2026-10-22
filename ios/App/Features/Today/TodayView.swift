import FamilyControls
import SwiftUI

struct TodayView: View {
    @Environment(LockModel.self) private var model
    @State private var showingPicker = false
    @State private var testTime = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: .now) ?? .now

    var body: some View {
        NavigationStack {
            List {
                statusSection
                setupSection
                if model.isAuthorized {
                    testingSection
                    logSection
                }
            }
            .navigationTitle("Today")
            .refreshable { model.reconcile() }
            .familyActivityPicker(
                headerText: "Choose the apps QuestLock locks until you check in.",
                isPresented: $showingPicker,
                selection: Binding(get: { model.selection }, set: { model.updateSelection($0) })
            )
            .alert("Something went wrong", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "")
            }
        }
    }

    // MARK: - Sections

    private var statusSection: some View {
        Section {
            HStack(spacing: 14) {
                Image(systemName: model.isLocked ? "lock.fill" : "lock.open.fill")
                    .font(.title)
                    .foregroundStyle(model.isLocked ? .red : .green)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.isLocked ? "Apps locked" : "Apps unlocked").font(.headline)
                    if let until = model.lockedUntil {
                        Text("Until \(until.formatted(date: .omitted, time: .shortened)), or until you check in")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 4)
            LabeledContent("Today's quest", value: SharedStore.todayTarget)
        }
    }

    private var setupSection: some View {
        Section("Setup") {
            if model.isAuthorized {
                LabeledContent("Screen Time access", value: "Allowed")
            } else {
                Button("Allow Screen Time access") {
                    Task { await model.requestAuthorization() }
                }
                if model.authorization == .denied {
                    Text("Access was turned off. Allow it again here or in Settings → Screen Time.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            if model.isAuthorized {
                Button {
                    showingPicker = true
                } label: {
                    LabeledContent("Apps to block", value: model.selectionSummary)
                }
                Toggle(isOn: Binding(get: { model.weeklyEnabled }, set: { model.setWeeklyEnabled($0) })) {
                    VStack(alignment: .leading) {
                        Text("Weekly schedule")
                        Text("Mon–Fri check in by 10:00, Sat–Sun by 12:00. Apps lock 2 h before.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var testingSection: some View {
        Section {
            Button("Lock in 1 minute for 15 minutes") { model.startDebugLock() }
            if let debug = model.debugLock {
                LabeledContent("Test lock", value: "\(debug.start.formatted(date: .omitted, time: .shortened))–\(debug.end.formatted(date: .omitted, time: .shortened))")
            }
            DatePicker("Tomorrow-only test at", selection: $testTime, displayedComponents: .hourAndMinute)
            Button("Lock tomorrow at that time (15 min)") {
                let parts = Calendar.current.dateComponents([.hour, .minute], from: testTime)
                model.scheduleTomorrowTest(at: TimeOfDay(hour: parts.hour ?? 12, minute: parts.minute ?? 0))
            }
            if let test = model.testSchedule.days.first,
               let start = try? ScheduleMath.lockStart(deadline: test.value.deadline, leadMinutes: test.value.leadMinutes) {
                LabeledContent("Tomorrow test", value: "\(test.key.shortName) \(start.formatted)–\(test.value.deadline.formatted)")
                Button("Remove tomorrow test", role: .destructive) { model.clearTomorrowTest() }
            }
            Button("Unlock now") { model.unlockNow() }
        } header: {
            Text("Testing")
        } footer: {
            Text("Lock windows can't be shorter than 15 minutes: that's Apple's minimum.")
        }
    }

    private var logSection: some View {
        Section("Lock log") {
            if model.events.isEmpty {
                Text("Nothing yet").foregroundStyle(.secondary)
            }
            ForEach(model.events) { event in
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.message).font(.subheadline)
                    Text(event.date.formatted(date: .abbreviated, time: .standard))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
