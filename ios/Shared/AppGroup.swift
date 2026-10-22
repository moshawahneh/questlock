import Foundation

/// The App Group is a shared container that the app and its three extensions can all read and write.
/// Each extension runs in its own process with its own sandbox, so this is the only way they share data
/// (the blocked-app selection, today's target, "verified today").
enum AppGroup {
    /// Must match `com.apple.security.application-groups` in ios/project.yml.
    static let id = "group.com.mohammadshaw.questlock"

    /// Shared key-value storage. Returns nil only for an invalid suite name, which is a programmer error.
    static var defaults: UserDefaults {
        guard let defaults = UserDefaults(suiteName: id) else {
            preconditionFailure("Invalid App Group suite name: \(id)")
        }
        return defaults
    }

    /// Shared folder on disk. Nil when the App Group entitlement is missing from the signed build.
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id)
    }
}
