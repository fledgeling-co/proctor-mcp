import Foundation
import CryptoKit
@testable import ProctorAgent
@testable import ProctorCore

// One trail at a time, across suites.
//
// `AuditLog`'s state, seams, clock and cross-process file lock are all
// process-wide, and `.serialized` only serializes the tests *inside* one suite —
// two suites that each redirect the trail run in parallel and stamp on each
// other. That showed up as entries appearing in another suite's file, a key
// mismatch against a public key a different suite had cached, and counts that
// depended on what else happened to be running.
//
// So every suite that redirects the trail takes this lock for the whole of its
// setup, body and teardown. It is a real interlock rather than tidiness: the
// alternative is a test that passes alone and fails in the suite, which is the
// kind of flake that gets a real finding dismissed later.
enum TrailIsolation {
    nonisolated(unsafe) private static let mutex = NSLock()

    /// Wrapped in ordinary synchronous functions because `NSLock.lock()` is
    /// unavailable from an async context, and several of these tests are async.
    /// The lock is held across an `await` on purpose: what it is protecting is a
    /// process-wide seam that stays redirected for the whole of the test body.
    static func acquire() { mutex.lock() }
    static func release() { mutex.unlock() }
}

/// A sealing pair held in memory, so a test can read back what it wrote.
///
/// The live store keeps the public half in a file beside the trail and the
/// private half in the login Keychain, which a test process must never touch —
/// so before this, a test could prove the trail was written and never that it
/// could be opened. A history projection is entirely a question about what comes
/// back out, so it needs both halves in hand.
final class TestSealKeys: AuditSealKeys, @unchecked Sendable {
    private let key: Curve25519.KeyAgreement.PrivateKey?

    init(available: Bool = true) {
        key = available ? Curve25519.KeyAgreement.PrivateKey() : nil
    }

    func publicKey() -> Curve25519.KeyAgreement.PublicKey? { key?.publicKey }
    func privateKey() -> Curve25519.KeyAgreement.PrivateKey? { key }
    func hasCachedPublicKey() -> Bool { key != nil }
    func cachedPublicKeyMatches(_ privateKey: Curve25519.KeyAgreement.PrivateKey) -> Bool? {
        guard let key else { return nil }
        return key.publicKey.rawRepresentation == privateKey.publicKey.rawRepresentation
    }
}
