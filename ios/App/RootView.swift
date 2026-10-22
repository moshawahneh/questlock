import SwiftUI

/// Picks the screen for the current session state.
struct RootView: View {
    @Environment(SessionModel.self) private var session

    var body: some View {
        Group {
            switch session.state {
            case .notConfigured:
                NotConfiguredView()
            case .loading:
                ProgressView("Loading…")
            case .signedOut:
                SignInView()
            case .onboarding:
                OnboardingView()
            case .ready:
                ContentView()
            }
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { session.errorMessage != nil },
            set: { if !$0 { session.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(session.errorMessage ?? "")
        }
    }
}

/// Shown when the build has no Supabase URL/key (see ios/Config/Debug.xcconfig.example).
private struct NotConfiguredView: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("This build isn't connected to a QuestLock server yet.", systemImage: "icloud.slash")
                    Text("Set SUPABASE_URL and SUPABASE_ANON_KEY in ios/Config/Debug.xcconfig and rebuild.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    NavigationLink("Test the app lock") { TodayView() }
                }
            }
            .navigationTitle("QuestLock")
        }
    }
}
