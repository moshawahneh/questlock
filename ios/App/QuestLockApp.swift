import SwiftUI

@main
struct QuestLockApp: App {
    @State private var lockModel: LockModel
    @State private var scheduleModel: ScheduleModel
    @State private var checkInModel: CheckInModel
    @State private var sessionModel = SessionModel()
    @State private var groupsModel = GroupsModel()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let locks = LockModel()
        _lockModel = State(initialValue: locks)
        _scheduleModel = State(initialValue: ScheduleModel(locks: locks))
        _checkInModel = State(initialValue: CheckInModel(locks: locks))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(lockModel)
                .environment(scheduleModel)
                .environment(sessionModel)
                .environment(groupsModel)
                .environment(checkInModel)
                .task { await sessionModel.start(schedules: scheduleModel) }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard phase == .active else { return }
            // Reconcile on launch: the Monitor extension occasionally misses a callback,
            // so every time the app comes to the foreground it re-checks whether it should be locked.
            lockModel.reconcile()
            if sessionModel.state == .ready {
                Task {
                    await scheduleModel.pull()
                    await checkInModel.load()
                }
            }
        }
    }
}
