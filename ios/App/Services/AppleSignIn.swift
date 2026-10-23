import CryptoKit
import Foundation

/// Sign in with Apple nonce: the app sends Apple the SHA-256 of a random string, Apple puts that hash in
/// the identity token, and Supabase checks it against the raw string. A stolen token can't be replayed
/// without the raw nonce.
enum AppleSignInNonce {
    static func make(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in charset.randomElement(using: &generator)! })
    }

    static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
