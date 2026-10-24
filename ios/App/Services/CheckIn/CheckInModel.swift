import Foundation
import Observation
import Supabase
import UIKit

/// Today's challenge and the check-in flow: face check → resize → hash → upload → verify → unlock.
@MainActor
@Observable
final class CheckInModel {
    struct Challenge: Decodable, Equatable, Sendable {
        let id: UUID
        let local_date: String
        let target_key: String
        let target_label: String
        let hint: String?
        let opens_at: String
        let deadline_at: String

        var opensAt: Date { ISODate.parse(opens_at) ?? .distantFuture }
        var deadlineAt: Date { ISODate.parse(deadline_at) ?? .distantPast }
    }

    enum Status: Equatable {
        case loading
        case restDay
        case notOpenYet(opens: Date)
        case open(deadline: Date)
        case verified
        case late
        case pastDeadline
    }

    enum Outcome: Equatable {
        case verified
        case late
        /// Caught on the phone before uploading: no attempt used.
        case retake(String)
        /// The server said no: this used one of the 5 attempts.
        case rejected(String)
        case failed(String)
    }

    private(set) var challenge: Challenge?
    private(set) var status: Status = .loading
    private(set) var verifiedAt: Date?
    var errorMessage: String?

    private let locks: LockModel

    init(locks: LockModel) {
        self.locks = locks
    }

    // MARK: - Today's challenge

    func load(now: Date = .now) async {
        guard let client = Backend.client else { return }
        do {
            let response: ChallengeResponse = try await client.functions.invoke(
                "issue-challenge", options: FunctionInvokeOptions(method: .post, body: [String: String]()))
            challenge = response.challenge
            if let challenge = response.challenge {
                SharedStore.todayTarget = challenge.target_label
                let latest: [CheckinStatusRow] = try await client.from("checkins")
                    .select("status, created_at")
                    .eq("challenge_id", value: challenge.id)
                    .in("status", values: ["verified", "late"])
                    .order("created_at", ascending: false)
                    .limit(1)
                    .execute()
                    .value
                if let row = latest.first {
                    verifiedAt = ISODate.parse(row.created_at)
                    status = row.status == "verified" ? .verified : .late
                    return
                }
            }
            updateStatus(now: now)
        } catch {
            errorMessage = Self.message(for: error)
            updateStatus(now: now)
        }
    }

    func updateStatus(now: Date = .now) {
        guard let challenge else { status = .restDay; return }
        if status == .verified || status == .late { return }
        if now < challenge.opensAt {
            status = .notOpenYet(opens: challenge.opensAt)
        } else if now <= challenge.deadlineAt {
            status = .open(deadline: challenge.deadlineAt)
        } else {
            status = .pastDeadline
        }
    }

    // MARK: - Submit

    /// Runs the whole check-in. Problems Apple's on-device checks can see (no face, target not seen,
    /// photo of a screen) are caught before uploading and don't use an attempt.
    func submit(_ photos: CameraController.Photos, userID: UUID) async -> Outcome {
        guard let client = Backend.client, let challenge else { return .failed("No check-in is open right now.") }

        // 1. On-device checks and encoding, off the main thread.
        let targetKey = challenge.target_key
        let prepared = await Task.detached(priority: .userInitiated) { () -> Prepared? in
            let front = PhotoEncoding.downscaled(photos.front)
            let back = PhotoEncoding.downscaled(photos.back)
            guard let frontImage = front.cgImage, let backImage = back.cgImage,
                  let hash = PerceptualHash.dHash(backImage),
                  let frontData = PhotoEncoding.jpeg(front), let backData = PhotoEncoding.jpeg(back) else { return nil }
            let observations = PhotoClassifier.observe(front: frontImage, back: backImage, targetKey: targetKey)
            return Prepared(front: frontData, back: backData, phash: PerceptualHash.hex(hash), observations: observations)
        }.value
        guard let prepared else { return .failed("Couldn't process the photos. Try again.") }

        switch CheckInDecision.verdict(prepared.observations) {
        case .accept:
            break
        case .noFace:
            return .retake("We couldn't see your face in the front photo. Retake it. This didn't use an attempt.")
        case .targetNotSeen:
            return .retake("That doesn't look like \(challenge.target_label). Get closer or try another angle. This didn't use an attempt.")
        case .looksLikeScreen:
            return .retake("That looks like a photo of a screen. Photograph the real thing. This didn't use an attempt.")
        }

        // 2. Upload both photos into the user's own folder (ids lowercased to match auth.uid()::text).
        let checkinID = UUID().uuidString.lowercased()
        let base = "\(userID.uuidString.lowercased())/\(challenge.local_date)/\(checkinID)"
        let paths = (front: "\(base)_front.jpg", back: "\(base)_back.jpg")
        do {
            let bucket = client.storage.from("checkins")
            _ = try await bucket.upload(paths.front, data: prepared.front, options: FileOptions(contentType: "image/jpeg"))
            _ = try await bucket.upload(paths.back, data: prepared.back, options: FileOptions(contentType: "image/jpeg"))
        } catch {
            // Nothing was submitted, so this doesn't use one of the 5 attempts.
            return .failed("Upload failed: \(Self.message(for: error)) Your attempt wasn't used, so try again.")
        }

        // 3. The server applies the same rule, plus checks it can do itself (time, attempts, reused photos).
        do {
            let result: VerifyResponse = try await client.functions.invoke(
                "verify-checkin",
                options: FunctionInvokeOptions(method: .post, body: VerifyRequest(
                    challenge_id: challenge.id.uuidString.lowercased(), checkin_id: checkinID,
                    front_path: paths.front, back_path: paths.back, phash: prepared.phash,
                    observations: prepared.observations)))
            switch result.status {
            case "verified":
                verifiedAt = .now
                unlock(until: ISODate.parse(result.deadline_at) ?? challenge.deadlineAt)
                status = .verified
                return .verified
            case "late":
                verifiedAt = .now
                status = .late
                return .late
            default:
                return .rejected(result.message ?? "The check-in wasn't accepted. Try again.")
            }
        } catch {
            return .failed(Self.message(for: error))
        }
    }

    /// Verified: no shields until the end of today's window (the Monitor and reconcile both respect this).
    private func unlock(until end: Date) {
        SharedStore.unlockedUntil = end
        SharedStore.log("Checked in: verified, apps unlocked")
        locks.reconcile()
    }

    // MARK: - Helpers

    private struct Prepared: Sendable {
        let front: Data
        let back: Data
        let phash: String
        let observations: PhotoObservations
    }

    private struct ChallengeResponse: Decodable { let challenge: Challenge? }
    private struct CheckinStatusRow: Decodable { let status: String; let created_at: String }
    private struct VerifyRequest: Encodable {
        let challenge_id: String
        let checkin_id: String
        let front_path: String
        let back_path: String
        let phash: String
        let observations: PhotoObservations
    }
    private struct VerifyResponse: Decodable {
        let status: String          // verified | late | rejected
        let message: String?
        let unlocked: Bool
        let deadline_at: String
    }
    private struct FunctionErrorBody: Decodable { let error: String; let message: String? }

    /// Edge Function errors come back as HTTP errors with a JSON body { error, message }.
    static func message(for error: any Error) -> String {
        if case let FunctionsError.httpError(_, data) = error,
           let body = try? JSONDecoder().decode(FunctionErrorBody.self, from: data) {
            return body.message ?? body.error
        }
        return Backend.message(for: error)
    }
}

/// Parses Postgres timestamps such as "2026-10-24T08:00:00+00:00" (with or without fractional seconds).
enum ISODate {
    static func parse(_ string: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: string) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }
}
