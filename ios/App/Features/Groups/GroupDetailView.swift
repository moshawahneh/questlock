import SwiftUI
import UIKit

struct GroupDetailView: View {
    let groupID: UUID

    @Environment(GroupsModel.self) private var groups
    @Environment(SessionModel.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var renaming = false
    @State private var confirmingLeave = false
    @State private var copied = false

    var body: some View {
        if let group = groups.group(groupID) {
            content(group)
        } else {
            ContentUnavailableView("Group not found", systemImage: "person.3")
        }
    }

    private func content(_ group: GroupSummary) -> some View {
        let isAdmin = group.group_members.contains { $0.user_id == session.userID && $0.isAdmin }
        return List {
            Section("Leaderboard") {
                ForEach(Array(group.rankedMembers.enumerated()), id: \.element.id) { index, member in
                    memberRow(member, rank: index + 1)
                        .swipeActions {
                            if isAdmin && member.user_id != session.userID {
                                Button("Remove", role: .destructive) {
                                    Task { _ = await groups.remove(member: member.user_id, from: group.id) }
                                }
                            }
                        }
                }
            }

            Section {
                HStack {
                    Text(group.invite_code)
                        .font(.title2.monospaced().bold())
                        .textSelection(.enabled)
                    Spacer()
                    Button(copied ? "Copied" : "Copy") {
                        UIPasteboard.general.string = group.invite_code
                        copied = true
                    }
                    .buttonStyle(.bordered)
                }
                ShareLink("Invite friends", item: "Join my QuestLock group \"\(group.name)\" with code \(group.invite_code)")
                if isAdmin {
                    Button("New invite code") {
                        Task { _ = await groups.regenerateCode(group.id); copied = false }
                    }
                }
            } header: {
                Text("Invite code")
            } footer: {
                Text(isAdmin ? "Making a new code stops the old one from working. Swipe left on a member to remove them."
                             : "Share this code with friends so they can join. Groups can have up to 20 people.")
            }

            Section {
                if isAdmin {
                    Button("Rename group") { renaming = true }
                }
                Button("Leave group", role: .destructive) { confirmingLeave = true }
            }
        }
        .navigationTitle(group.name)
        .refreshable { await groups.load() }
        .sheet(isPresented: $renaming) {
            TextEntrySheet(title: "Rename group", prompt: "Group name", actionTitle: "Save", initial: group.name) { name in
                await groups.rename(group.id, to: name)
            }
        }
        .confirmationDialog("Leave \(group.name)?", isPresented: $confirmingLeave, titleVisibility: .visible) {
            Button("Leave group", role: .destructive) {
                Task {
                    if await groups.leave(group.id) { dismiss() }
                }
            }
        } message: {
            Text("You can join again later with the invite code.")
        }
    }

    private func memberRow(_ member: GroupSummary.Member, rank: Int) -> some View {
        HStack(spacing: 12) {
            Text("\(rank)")
                .font(.headline.monospacedDigit())
                .frame(width: 24)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(member.profiles.display_name ?? "New member")
                    if member.user_id == session.userID {
                        Text("You").font(.caption).foregroundStyle(.secondary)
                    }
                    if member.isAdmin {
                        Text("Admin").font(.caption2.bold())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.indigo.opacity(0.15), in: Capsule())
                    }
                }
                Text("Best: \(member.profiles.longest_streak)").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Label("\(member.profiles.current_streak)", systemImage: "flame.fill")
                .foregroundStyle(member.profiles.current_streak > 0 ? .orange : .secondary)
                .font(.headline.monospacedDigit())
        }
    }
}
