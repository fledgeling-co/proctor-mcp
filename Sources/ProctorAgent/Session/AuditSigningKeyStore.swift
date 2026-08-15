import Foundation
import Security
import CryptoKit
import ProctorCore

// The signing half of the audit trail, agent side. `AuditChain` decides what is
// signed and what a verdict means; this file holds the key that signs and the
// mark of how far the trail has got, and it is the only place either touches the
// Mac.
//
// The key lives in the **secure element** wherever there is one. That is not
// belt-and-braces: a 32-byte secret fetched into process memory can be carried
// off this Mac and used to forge a whole trail offline, which would make the
// feature's central claim — that a trail edited anywhere else is detected —
// false against anyone who ever read it once. A secure-element key cannot be
// copied at all; what is stored is a wrapped blob that means nothing on another
// machine. An attacker who is *here* can still ask it to sign, and that limit is
// stated in the spec rather than papered over.
//
// A Mac with no secure element signs with an ordinary protected key, and every
// entry records which of the two signed it, so a clean verdict never means less
// than it appears to on some machines. The class is taken from how the key is
// actually stored and is never believed from a record.
//
// The same terms as `AuditKeyStore`, deliberately: created here, bound to this
// Mac, never synced, and **no export, escrow or recovery copy anywhere**. Losing
// it does not make the history unreadable — it makes it unverifiable, which is
// the same trade the product owner already accepted for reading.

/// What `AuditLog` needs from a signer. A protocol so a test can drive the write
/// path with an in-process key: `swift test` runs with no live key store, and
/// must never create one.
protocol AuditSigning: Sendable {
    /// Nil when the key store cannot be reached at all, which is the difference
    /// between "unconfirmed" and "forged" in a verdict.
    var signingKeyId: String? { get }
    var signingKeyClass: AuditChain.KeyClass? { get }
    /// The 64-byte P1363 signature, or nil. Nil drops the entry: there is no
    /// unsigned path, because an unsigned entry could not be told from a forged
    /// one.
    func sign(_ material: Data) -> Data?
    func verifySignature(_ signature: Data, over material: Data) -> Bool
}

/// Where the mark of how far the trail has got is kept. In the key store rather
/// than beside the trail, because a marker on disk is restored together with the
/// trail from any snapshot, and the restored pair verifies perfectly — which
/// makes rolling the trail back to an earlier version free.
protocol AuditAnchoring: Sendable {
    func loadAnchor() -> AuditChain.Anchor?
    @discardableResult func saveAnchor(_ anchor: AuditChain.Anchor) -> Bool
}

final class AuditSigningKeyStore: AuditSigning, AuditAnchoring, @unchecked Sendable {

    static let shared = AuditSigningKeyStore()

    private let lock = NSLock()
    private var cached: Signer?
    private var resolved = false

    private let service = "\(Wire.bundleIdentifier).audit.signing"
    private let secureAccount = "audit-p256-se-v1"
    private let softwareAccount = "audit-p256-sw-v1"
    private let anchorAccount = "audit-anchor-v1"

    /// One key, either kind, behind one set of operations.
    private enum Signer {
        case secureElement(SecureEnclave.P256.Signing.PrivateKey)
        case software(P256.Signing.PrivateKey)

        var publicKeyRaw: Data {
            switch self {
            case .secureElement(let key): return key.publicKey.rawRepresentation
            case .software(let key): return key.publicKey.rawRepresentation
            }
        }

        var keyClass: AuditChain.KeyClass {
            switch self {
            case .secureElement: return .secureElement
            case .software: return .software
            }
        }

        func signature(for material: Data) -> Data? {
            switch self {
            case .secureElement(let key):
                return try? key.signature(for: material).rawRepresentation
            case .software(let key):
                return try? key.signature(for: material).rawRepresentation
            }
        }
    }

    // MARK: - AuditSigning

    var signingKeyId: String? {
        guard let signer = signer() else { return nil }
        return AuditChain.keyId(forPublicKey: signer.publicKeyRaw)
    }

    var signingKeyClass: AuditChain.KeyClass? { signer()?.keyClass }

    func sign(_ material: Data) -> Data? { signer()?.signature(for: material) }

    func verifySignature(_ signature: Data, over material: Data) -> Bool {
        guard let signer = signer(),
              let parsed = try? P256.Signing.ECDSASignature(rawRepresentation: signature),
              let publicKey = try? P256.Signing.PublicKey(rawRepresentation: signer.publicKeyRaw)
        else { return false }
        return publicKey.isValidSignature(parsed, for: material)
    }

    /// Fetched once and kept for the run. The write path is on the hot side of
    /// every action, and re-reading the key store per entry would pay a keychain
    /// round trip for an answer that cannot change.
    private func signer() -> Signer? {
        lock.lock()
        defer { lock.unlock() }
        if resolved { return cached }
        resolved = true
        cached = loadOrCreateLocked()
        return cached
    }

    private func loadOrCreateLocked() -> Signer? {
        if let blob = read(account: secureAccount),
           let key = try? SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: blob) {
            return .secureElement(key)
        }
        if let raw = read(account: softwareAccount),
           let key = try? P256.Signing.PrivateKey(rawRepresentation: raw) {
            return .software(key)
        }
        if SecureEnclave.isAvailable, let key = try? SecureEnclave.P256.Signing.PrivateKey() {
            guard store(key.dataRepresentation, account: secureAccount) else { return nil }
            return .secureElement(key)
        }
        let key = P256.Signing.PrivateKey()
        guard store(key.rawRepresentation, account: softwareAccount) else { return nil }
        return .software(key)
    }

    // MARK: - AuditAnchoring

    func loadAnchor() -> AuditChain.Anchor? {
        guard let data = read(account: anchorAccount) else { return nil }
        return try? JSONDecoder().decode(AuditChain.Anchor.self, from: data)
    }

    @discardableResult
    func saveAnchor(_ anchor: AuditChain.Anchor) -> Bool {
        guard let data = try? JSONEncoder().encode(anchor) else { return false }
        return store(data, account: anchorAccount)
    }

    // MARK: - Keychain

    private func query(account: String, _ extra: [CFString: Any] = [:]) -> [CFString: Any] {
        var q: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            // Never synced, never restored onto another Mac. For the secure
            // element key the point is moot — the blob is useless elsewhere — and
            // for the anchor it is the whole point, since an anchor that travelled
            // with a backup would authorise the rollback it exists to catch.
            kSecAttrSynchronizable: false
        ]
        for (key, value) in extra { q[key] = value }
        return q
    }

    private func read(account: String) -> Data? {
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query(account: account, [
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]) as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }

    private func store(_ data: Data, account: String) -> Bool {
        let update = SecItemUpdate(query(account: account) as CFDictionary,
                                   [kSecValueData: data] as CFDictionary)
        if update == errSecSuccess { return true }
        guard update == errSecItemNotFound else { return false }
        let attributes = query(account: account, [
            kSecValueData: data,
            // After first unlock rather than while unlocked: the agent records
            // while nobody is present, and this is the most available class that
            // is still bound to this device. It is strictly easier to reach than
            // the key that reads the trail, so signing never becomes the reason a
            // trail goes dark first.
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrLabel: "Proctor audit trail signing key",
            kSecAttrDescription: "Proves the Proctor audit trail was written on this Mac. "
                               + "There is no copy; deleting this item makes the existing trail "
                               + "permanently unverifiable."
        ])
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }
}

/// A signer that cannot sign and an anchor that remembers nothing, used as the
/// default in a test process.
///
/// It exists because the honest default reaches the Mac's secure element, and a
/// test process reaching it creates a real key in the operator's real login
/// keychain — which one run of this suite did before this type existed. Its
/// answers are the same ones a machine whose key store cannot be reached gives,
/// so nothing has to special-case it: an append is dropped, and a verdict comes
/// back unconfirmed rather than clean.
struct InertSigner: AuditSigning, AuditAnchoring {
    var signingKeyId: String? { nil }
    var signingKeyClass: AuditChain.KeyClass? { nil }
    func sign(_ material: Data) -> Data? { nil }
    func verifySignature(_ signature: Data, over material: Data) -> Bool { false }
    func loadAnchor() -> AuditChain.Anchor? { nil }
    @discardableResult func saveAnchor(_ anchor: AuditChain.Anchor) -> Bool { false }
}
