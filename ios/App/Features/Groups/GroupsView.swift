import SwiftUI

struct GroupsView: View {
    @Environment(GroupsModel.self) private var groups
    @Environment(SessionModel.self) private var session
    @State private var sheet: Sheet?

    enum Sheet: String, Identifiable {
        case create, join
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(groups.groups) { group in
                    NavigationLink(value: group.id) {
                        GroupRowView(group: group, me: session.userID)
                    }
                }
            }
            .overlay {
                if groups.groups.isEmpty && !groups.isLoading {
                    ContentUnavailableView {
                        Label("No groups yet", systemImage: "person.3")
                    } description: {
                        Text("Create a group and share its code, or join a friend's group with theirs.")
                    } actions: {
                        Button("Create a group") { sheet = .create }
                        Button("Join with a code") { sheet = .join }
                    }
                }
            }
            .navigationTitle("Groups")
            .navigationDestination(for: UUID.self) { id in
                GroupDetailView(groupID: id)
            }
            .toolbar {
                Menu {
                    Button("Create a group", systemImage: "plus") { sheet = .create }
                    Button("Join with a code", systemImage: "ticket") { sheet = .join }
                } label: {
                    Image(systemName: "plus")
                }
            }
            .refreshable { await groups.load() }
            .task { await groups.load() }
            .sheet(item: $sheet) { sheet in
                switch sheet {
                case .create:
                    TextEntrySheet(title: "New group", prompt: "Group name", actionTitle: "Create") { name in
                        await groups.create(named: name) != nil
                    }
                case .join:
                    TextEntrySheet(title: "Join a group", prompt: "Invite code", actionTitle: "Join", uppercase: true) { code in
                        await groups.join(code: code) != nil
                    }
                }
            }
            .alert("Something went wrong", isPresented: Binding(
                get: { groups.errorMessage != nil },
                set: { if !$0 { groups.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(groups.errorMessage ?? "")
            }
        }
    }
}

private struct GroupRowView: View {
    let group: GroupSummary
    let me: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(group.name).font(.headline)
            HStack(spacing: 12) {
                Label("\(group.group_members.count)", systemImage: "person.2")
                if let rank = group.rankedMembers.firstIndex(where: { $0.user_id == me }) {
                    Label("You're #\(rank + 1)", systemImage: "trophy")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}

/// A one-field sheet used for creating, joining and renaming groups.
struct TextEntrySheet: View {
    let title: String
    let prompt: String
    let actionTitle: String
    var initial = ""
    var uppercase = false
    let action: (String) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var working = false

    var body: some View {
        NavigationStack {
            Form {
                TextField(prompt, text: $text)
                    .textInputAutocapitalization(uppercase ? .characters : .words)
                    .autocorrectionDisabled(uppercase)
                    .font(uppercase ? .title3.monospaced() : .body)
                    .onSubmit { Task { await run() } }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if working {
                        ProgressView()
                    } else {
                        Button(actionTitle) { Task { await run() } }
                            .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
            }
        }
        .presentationDetents([.height(200)])
        .onAppear { text = initial }
    }

    private func run() async {
        guard !working, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        working = true
        let ok = await action(text)
        working = false
        if ok { dismiss() }
    }
}
