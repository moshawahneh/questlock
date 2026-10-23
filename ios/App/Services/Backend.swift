import Foundation
import Supabase

/// The Supabase client, configured from Info.plist (filled in from `ios/Config/Debug.xcconfig`).
/// The anon key is safe to ship in the app only because every table has Row Level Security on.
enum Backend {
    static let client: SupabaseClient? = {
        guard let url = configuredURL, let key = configuredKey else { return nil }
        return SupabaseClient(
            supabaseURL: url,
            supabaseKey: key,
            options: SupabaseClientOptions(auth: .init(emitLocalSessionAsInitialSession: true))
        )
    }()

    static var isConfigured: Bool { client != nil }

    private static var configuredURL: URL? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "SupabaseURL") as? String,
              let url = URL(string: raw.trimmingCharacters(in: .whitespaces)),
              let host = url.host(), !host.isEmpty else { return nil }
        #if !targetEnvironment(simulator)
        // A real iPhone can't reach the Mac's local Supabase at 127.0.0.1.
        if host == "127.0.0.1" || host == "localhost" { return nil }
        #endif
        return url
    }

    private static var configuredKey: String? {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SupabaseAnonKey") as? String,
              !key.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return key
    }

    /// Turns database errors raised by our RPCs (see the phase 2 migration) into plain messages.
    static func message(for error: any Error) -> String {
        if let postgrest = error as? PostgrestError {
            switch postgrest.message {
            case "invalid_invite_code": return "That code doesn't match any group. Check it and try again."
            case "group_full": return "That group already has 20 members."
            case "group_limit_reached": return "You can be in at most 5 groups. Leave one first."
            case "not_group_admin": return "Only the group's admin can do that."
            default: return postgrest.hint ?? postgrest.message
            }
        }
        if let urlError = error as? URLError, urlError.code == .notConnectedToInternet {
            return "You're offline. Connect to the internet and try again."
        }
        return error.localizedDescription
    }
}
