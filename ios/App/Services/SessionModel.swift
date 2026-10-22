import AuthenticationServices
import Foundation
import Observation
import Supabase

/// Who is signed in, their profile, and whether onboarding is finished.
@MainActor
@Observable
final class SessionModel {
    enum State: Equatable {
        case notConfigured
        case loading
        case signedOut
        case onboarding
        case ready
    }

    private(set) var state: State = Backend.isConfigured ? .loading : .notConfigured
    private(set) var profile: Profile?
    private(set) var userID: UUID?
    var errorMessage: String?

    /// Raw nonce for the Sign in with Apple request in flight.
    private var currentNonce: String?
    private var listening = false

    private var client: SupabaseClient? { Backend.client }

    // MARK: - Session lifecycle

    /// Follows sign-in / sign-out events for the lifetime of the app.
    func start(schedules: ScheduleModel) async {
        guard let client, !listening else { return }
        listening = true
        for await (event, session) in client.auth.authStateChanges {
            switch event {
            case .initialSession, .signedIn, .tokenRefreshed, .userUpdated:
                if let session, !session.isExpired {
                    await signedIn(as: session.user.id, schedules: schedules)
                } else if event == .initialSession {
                    state = .signedOut
                }
            case .signedOut, .userDeleted:
                userID = nil
                profile = nil
                state = .signedOut
            default:
                break
            }
        }
    }

    private func signedIn(as id: UUID, schedules: ScheduleModel) async {
        guard userID != id || state == .loading || state == .signedOut else { return }
        userID = id
        await loadProfile()
        await syncTimezone()
        await schedules.pull()
        updateState(hasSchedule: schedules.hasAnySchedule)
    }

    func updateState(hasSchedule: Bool) {
        guard userID != nil else { state = .signedOut; return }
        state = (profile?.display_name?.isEmpty == false && hasSchedule) ? .ready : .onboarding
    }

    // MARK: - Sign in with Apple

    func prepare(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = AppleSignInNonce.make()
        currentNonce = nonce
        request.requestedScopes = [.fullName]
        request.nonce = AppleSignInNonce.sha256(nonce)
    }

    func complete(_ result: Result<ASAuthorization, any Error>) {
        switch result {
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled {
                errorMessage = "Sign in with Apple failed: \(error.localizedDescription)"
            }
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8),
                  let nonce = currentNonce else {
                errorMessage = "Sign in with Apple didn't return a usable token. Try again."
                return
            }
            // Apple only shares the name on the very first sign-in, so keep it if we get it.
            let name = [credential.fullName?.givenName, credential.fullName?.familyName]
                .compactMap { $0 }.joined(separator: " ")
            Task { await signIn(idToken: idToken, nonce: nonce, appleName: name) }
        }
    }

    private func signIn(idToken: String, nonce: String, appleName: String) async {
        guard let client else { return }
        do {
            _ = try await client.auth.signInWithIdToken(credentials: .init(provider: .apple, idToken: idToken, nonce: nonce))
            // authStateChanges delivers .signedIn and loads the profile; fill in the name if it's missing.
            if !appleName.isEmpty, let id = client.auth.currentUser?.id {
                _ = try? await client.from("profiles")
                    .update(["display_name": String(appleName.prefix(40))])
                    .eq("id", value: id)
                    .is("display_name", value: nil)
                    .execute()
                await loadProfile()
            }
        } catch {
            errorMessage = Backend.message(for: error)
        }
        currentNonce = nil
    }

    func signOut(locks: LockModel) async {
        locks.resetForSignOut()
        try? await client?.auth.signOut()
    }

    // MARK: - Profile

    func loadProfile() async {
        guard let client, let userID else { return }
        do {
            profile = try await client.from("profiles")
                .select("id, display_name, timezone, current_streak, longest_streak")
                .eq("id", value: userID)
                .single()
                .execute()
                .value
        } catch {
            errorMessage = Backend.message(for: error)
        }
    }

    func updateDisplayName(_ name: String) async -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let client, let userID, (1...40).contains(trimmed.count) else {
            errorMessage = "Names need 1–40 characters."
            return false
        }
        do {
            try await client.from("profiles").update(["display_name": trimmed]).eq("id", value: userID).execute()
            profile?.display_name = trimmed
            return true
        } catch {
            errorMessage = Backend.message(for: error)
            return false
        }
    }

    /// Keeps the server's time zone in step with the phone, so "tomorrow" and deadlines match.
    private func syncTimezone() async {
        guard let client, let userID, let profile else { return }
        let current = TimeZone.current.identifier
        guard profile.timezone != current else { return }
        do {
            try await client.from("profiles").update(["timezone": current]).eq("id", value: userID).execute()
            self.profile?.timezone = current
        } catch {
            errorMessage = Backend.message(for: error)
        }
    }
}
