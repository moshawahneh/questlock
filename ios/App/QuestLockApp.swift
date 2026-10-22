import SwiftUI

@main
struct QuestLockApp: App {
    @State private var lockModel = LockModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(lockModel)
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            // Reconcile on launch: the Monitor extension occasionally misses a callback,
            // so every time the app comes to the foreground it re-checks whether it should be locked.
            if phase == .active {
                lockModel.reconcile()
            }
        }
    }
}
