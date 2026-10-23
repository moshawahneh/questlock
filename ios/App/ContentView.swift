import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "sun.max") }
            FeedView()
                .tabItem { Label("Feed", systemImage: "photo.on.rectangle") }
            GroupsView()
                .tabItem { Label("Groups", systemImage: "person.3") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

/// Shared placeholder for tabs that aren't built yet.
struct ComingSoonView: View {
    let title: String
    let systemImage: String
    let phase: String

    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text("Coming in \(phase)"))
    }
}

#Preview {
    let locks = LockModel()
    ContentView()
        .environment(locks)
        .environment(ScheduleModel(locks: locks))
        .environment(SessionModel())
        .environment(GroupsModel())
        .environment(CheckInModel(locks: locks))
}
