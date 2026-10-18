import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                Section("Diagnostics") {
                    // Proves the signed build has the App Group entitlement. Phase 0 device check.
                    LabeledContent("App Group", value: AppGroup.containerURL == nil ? "Missing" : "OK")
                }
                Section {
                    Text("Schedule, blocked apps and account settings arrive in Phases 2 and 6.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
