import Foundation
import Observation
import Supabase

/// The user's groups and their members. All changes go through the database RPCs, which enforce
/// the limits (20 members, 5 groups) and admin-only actions.
@MainActor
@Observable
final class GroupsModel {
    private(set) var groups: [GroupSummary] = []
    private(set) var isLoading = false
    var errorMessage: String?

    private static let columns = """
        id, name, invite_code, \
        group_members(user_id, role, joined_at, profiles(display_name, current_streak, longest_streak))
        """

    func load() async {
        guard let client = Backend.client else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            groups = try await client.from("groups")
                .select(Self.columns)
                .order("created_at")
                .execute()
                .value
        } catch {
            errorMessage = Backend.message(for: error)
        }
    }

    func group(_ id: UUID) -> GroupSummary? {
        groups.first { $0.id == id }
    }

    @discardableResult
    func create(named name: String) async -> GroupRow? {
        await call { client in
            try await client.rpc("create_group", params: ["p_name": name.trimmingCharacters(in: .whitespaces)]).execute().value
        }
    }

    @discardableResult
    func join(code: String) async -> GroupRow? {
        await call { client in
            try await client.rpc("join_group", params: ["p_invite_code": code.trimmingCharacters(in: .whitespaces)]).execute().value
        }
    }

    func leave(_ groupID: UUID) async -> Bool {
        await perform { client in
            _ = try await client.rpc("leave_group", params: ["p_group_id": groupID]).execute()
        }
    }

    func rename(_ groupID: UUID, to name: String) async -> Bool {
        await perform { client in
            _ = try await client.rpc("rename_group", params: RenameParams(p_group_id: groupID, p_name: name.trimmingCharacters(in: .whitespaces))).execute()
        }
    }

    func regenerateCode(_ groupID: UUID) async -> Bool {
        await perform { client in
            _ = try await client.rpc("regenerate_invite_code", params: ["p_group_id": groupID]).execute()
        }
    }

    func remove(member userID: UUID, from groupID: UUID) async -> Bool {
        await perform { client in
            _ = try await client.rpc("remove_member", params: MemberParams(p_group_id: groupID, p_user_id: userID)).execute()
        }
    }

    // MARK: - Helpers

    /// Runs an RPC that returns a value, then reloads the list.
    private func call<T: Sendable>(_ body: (SupabaseClient) async throws -> T) async -> T? {
        guard let client = Backend.client else { return nil }
        do {
            let value = try await body(client)
            await load()
            return value
        } catch {
            errorMessage = Backend.message(for: error)
            return nil
        }
    }

    /// Runs an RPC with no result, then reloads the list.
    private func perform(_ body: (SupabaseClient) async throws -> Void) async -> Bool {
        guard let client = Backend.client else { return false }
        do {
            try await body(client)
            await load()
            return true
        } catch {
            errorMessage = Backend.message(for: error)
            return false
        }
    }
}

private struct RenameParams: Encodable {
    let p_group_id: UUID
    let p_name: String
}

private struct MemberParams: Encodable {
    let p_group_id: UUID
    let p_user_id: UUID
}
