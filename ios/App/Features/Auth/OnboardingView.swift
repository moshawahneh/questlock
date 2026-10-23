import FamilyControls
import SwiftUI

/// First run: name → Screen Time + apps to block → schedule.
struct OnboardingView: View {
    @Environment(SessionModel.self) private var session
    @Environment(LockModel.self) private var locks
    @Environment(ScheduleModel.self) private var schedules

    private enum Step { case name, apps, schedule }
    @State private var step: Step?
    @State private var name = ""
    @State private var showingPicker = false

    var body: some View {
        NavigationStack {
            Group {
                switch step ?? initialStep {
                case .name: nameStep
                case .apps: appsStep
                case .schedule: scheduleStep
                }
            }
            .navigationBarTitleDisplayMode(.large)
        }
        .onAppear { name = session.profile?.display_name ?? "" }
    }

    private var initialStep: Step {
        session.profile?.display_name?.isEmpty == false ? (locks.isAuthorized && locks.hasSelection ? .schedule : .apps) : .name
    }

    // MARK: - Steps

    private var nameStep: some View {
        Form {
            Section {
                TextField("Your name", text: $name)
                    .textContentType(.givenName)
                    .submitLabel(.continue)
            } footer: {
                Text("This is what your friends see on the leaderboard.")
            }
            Section {
                Button("Continue") {
                    Task {
                        if await session.updateDisplayName(name) { step = .apps }
                    }
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .navigationTitle("What should we call you?")
    }

    private var appsStep: some View {
        Form {
            Section {
                if locks.isAuthorized {
                    LabeledContent("Screen Time access", value: "Allowed")
                    Button {
                        showingPicker = true
                    } label: {
                        LabeledContent("Apps to block", value: locks.selectionSummary)
                    }
                } else {
                    Button("Allow Screen Time access") {
                        Task { await locks.requestAuthorization() }
                    }
                }
            } footer: {
                Text("QuestLock uses Screen Time to lock the apps you pick each morning. It never sees which apps they are, only Apple does.")
            }
            Section {
                Button("Continue") { step = .schedule }
                    .disabled(!locks.isAuthorized || !locks.hasSelection)
                if !locks.isAuthorized || !locks.hasSelection {
                    Button("Skip for now") { step = .schedule }
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Pick apps to lock")
        .familyActivityPicker(
            headerText: "Choose the apps QuestLock locks until you check in.",
            isPresented: $showingPicker,
            selection: Binding(get: { locks.selection }, set: { locks.updateSelection($0) })
        )
    }

    private var scheduleStep: some View {
        ScheduleEditorView(initial: schedules.latest, saveTitle: "Finish") { schedule in
            guard await schedules.save(schedule) != nil else {
                session.errorMessage = schedules.errorMessage
                return false
            }
            session.updateState(hasSchedule: true)
            return true
        }
        .navigationTitle("Your mornings")
    }
}
