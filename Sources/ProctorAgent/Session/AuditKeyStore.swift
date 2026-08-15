import Foundation
import Security
import CryptoKit
import ProctorCore

// Where the trail's two halves live. The split is the whole point of the design:
// the half needed to *write* is not a secret and sits in a file the agent owns,
// so an unattended run keeps recording between a restart and the first unlock;
// the half needed to *read* is a Keychain item bound to this Mac and this login,
// so a copied file, a backup or another account is useless.
//
// There is deliberately no export, no escrow and no recovery copy of the private
// key. The product owner chose that knowingly (spec PRO-0013, answer (a)): losing
// it — a new Mac, a Keychain reset, a rebuilt account — permanently ends access to
// the history. Adding a way out would be the guarantee this design was chosen for,
// weakened, so do not add one.

/// The two halves, behind a seam.
///
/// The seam exists because PRO-0047 made *reading* the trail a path worth testing.
/// Before it, only writing was exercised — a test wrote `audit.pub` beside its own
/// trail and asserted on the raw lines — and the unsealing half was reachable only
/// through the login Keychain, which a test process must never touch. A history
/// projection cannot be checked that way: the whole question is what comes back
/// out, so the pair has to be substitutable.
///
/// The live implementation is unchanged and remains the default, so nothing about
/// the shipped key handling moves.
protocol AuditSealKeys: Sendable {
    func publicKey() -> Curve25519.KeyAgreement.PublicKey?
    func privateKey() -> Curve25519.KeyAgreement.PrivateKey?
    func hasCachedPublicKey() -> Bool
    func cachedPublicKeyMatches(_ privateKey: Curve25519.KeyAgreement.PrivateKey) -> Bool?
}

final class AuditKeyStore: AuditSealKeys, @unchecked Sendable {

    static let shared = AuditKeyStore()

    private let lock = NSLock()
    private var cachedPublic: Curve25519.KeyAgreement.PublicKey?

    private let service = "\(Wire.bundleIdentifier).audit"
    private let account = "audit-x25519-v1"

    private var publicKeyURL: URL {
        AuditLog.directory.appendingPathComponent("audit.pub", isDirectory: false)
    }

    /// The sealing half. Read from the on-disk cache first, which is what keeps the
    /// write path free of the Keychain entirely — no unlock, no prompt, no
    /// user-presence requirement while the agent works alone. Only the very first
    /// use on a machine falls through to creating the Keychain item.
    func publicKey() -> Curve25519.KeyAgreement.PublicKey? {
        lock.lock()
        defer { lock.unlock() }
        if let cachedPublic { return cachedPublic }
        if let raw = try? Data(contentsOf: publicKeyURL),
           let key = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: raw) {
            cachedPublic = key
            return key
        }
        guard let priv = loadOrCreatePrivateKeyLocked() else { return nil }
        let pub = priv.publicKey
        cacheLocked(pub)
        cachedPublic = pub
        return pub
    }

    /// The unsealing half. Reaches the Keychain every time, which is the attended
    /// operation: reading the trail is something a person does, and needing the
    /// login keychain unlocked for it is the property being bought.
    func privateKey() -> Curve25519.KeyAgreement.PrivateKey? {
        lock.lock()
        defer { lock.unlock() }
        return loadPrivateKeyLocked()
    }

    /// True when the trail can be written without touching the Keychain at all.
    func hasCachedPublicKey() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if cachedPublic != nil { return true }
        return FileManager.default.fileExists(atPath: publicKeyURL.path)
    }

    /// Whether the sealing key on disk is still the public half of the key this Mac
    /// holds. Nothing on the write path can answer this — that is the point of the
    /// split — so it is checked on the attended read path, where the private half is
    /// in hand. A false answer means every new entry is being sealed to a key nobody
    /// here can open, which every write would otherwise report as a success.
    /// Nil when the cached key cannot be read at all.
    func cachedPublicKeyMatches(_ privateKey: Curve25519.KeyAgreement.PrivateKey) -> Bool? {
        lock.lock()
        defer { lock.unlock() }
        guard let raw = try? Data(contentsOf: publicKeyURL) else { return nil }
        return raw == privateKey.publicKey.rawRepresentation
    }

    // MARK: - Keychain

    private func query(_ extra: [CFString: Any] = [:]) -> [CFString: Any] {
        var q: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            // ThisDeviceOnly is the load-bearing half: the item is never included in
            // an iCloud Keychain sync and never restored onto another Mac from a
            // backup, which is what makes a stolen backup of the log worthless.
            kSecAttrSynchronizable: false
        ]
        for (k, v) in extra { q[k] = v }
        return q
    }

    private func loadPrivateKeyLocked() -> Curve25519.KeyAgreement.PrivateKey? {
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query([
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]) as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data)
    }

    private func loadOrCreatePrivateKeyLocked() -> Curve25519.KeyAgreement.PrivateKey? {
        if let existing = loadPrivateKeyLocked() { return existing }
        let fresh = Curve25519.KeyAgreement.PrivateKey()
        let attributes = query([
            kSecValueData: fresh.rawRepresentation,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrLabel: "Proctor audit trail key",
            kSecAttrDescription: "Unseals the Proctor audit trail. There is no copy; "
                               + "deleting this item makes the existing trail permanently unreadable."
        ])
        let status = SecItemAdd(attributes as CFDictionary, nil)
        if status == errSecSuccess { return fresh }
        // A duplicate means another process won the race; take theirs so both
        // halves agree on one key rather than sealing to a key nobody stored.
        if status == errSecDuplicateItem { return loadPrivateKeyLocked() }
        return nil
    }

    private func cacheLocked(_ pub: Curve25519.KeyAgreement.PublicKey) {
        let fm = FileManager.default
        try? fm.createDirectory(at: AuditLog.directory, withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o700])
        try? pub.rawRepresentation.write(to: publicKeyURL, options: .atomic)
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: publicKeyURL.path)
    }
}
