import Foundation
import CryptoKit

// Encryption-at-rest for the redacting audit trail, pure half. PRO-0005 proved
// what was done without storing what was typed; this makes the proof itself
// unreadable to anyone who can read the file but cannot reach the key.
//
// Two constraints shape the construction, and both come from how the agent runs
// rather than from cryptographic taste:
//
//   Writing must not need the protected key. The agent records while nobody is
//   present — between a restart and the first time the Mac is unlocked is exactly
//   when it is working alone — so a scheme that needs the secret to append would
//   let the trail go dark in the case the trail exists for. Sealing therefore
//   takes a *public* key, which is not a secret and lives in a file beside the
//   log; opening takes the private key, which lives in the Keychain and is needed
//   only to read. Reading is the attended half.
//
//   The file stays append-only JSONL. Each line is sealed on its own with its own
//   ephemeral key, so an append is still one write(2) of one line and two
//   concurrent appends can never share a nonce. Sealing the whole file instead
//   would mean rewriting it on every event, which breaks both.
//
// What this does not claim: it hides content, not the fact that entries exist.
// The number of lines, their timing and their rough size stay visible to anyone
// with file access, and nothing here detects a deleted or reordered line.
//
// Authenticity is not claimed *by this file*, and that follows directly from the
// first constraint above: sealing needs only the public key, which sits in a file
// beside the log, so anyone who can write that directory can append a well-formed
// entry that opens cleanly. `AuditChain` (PRO-0032) is what closes that — it
// chains each record to the one before it and signs the link with a key held in
// the Mac's secure element, so an entry appended by anything else is detected.
// The two are deliberately separate: sealing hides content and needs no secret to
// write, signing proves authorship and does. A line that carries no chain fields
// is one written before signing existed, and is reported as such rather than as
// forged.

public enum AuditSeal {

    /// On-disk format version. `open` refuses anything else rather than guessing,
    /// so a future format cannot be silently mis-decoded by an older build.
    public static let version = 1

    private static let salt = Data("proctor-audit-seal-v1".utf8)

    /// One sealed line. Compact, sorted-key JSON with no newline in it, so the
    /// file it lands in is still one-record-per-line and `tail`/`wc -l` still work
    /// for an operator who cannot read the contents.
    ///
    /// The five chain fields (PRO-0032) are **optional and outside the sealed
    /// box**, which is what lets this format be extended without invalidating a
    /// single line already on disk: an entry written before signing existed
    /// decodes with them nil and is reported as predating the chain, and the
    /// sealed box, its version and its additional-data binding are untouched. It
    /// also means the trail can be *checked* without being *opened* — the two are
    /// different privileges and stay so.
    public struct SealedLine: Codable, Sendable, Equatable {
        public let v: Int
        public let kid: String     // which key sealed this, so a later key change stays possible
        public let epk: String     // base64 raw ephemeral X25519 public key
        public let ct: String      // base64 AES-GCM combined box (nonce ‖ ciphertext ‖ tag)

        /// Lowercase hex SHA-256 of the previous record's bytes; for the first
        /// chained record, of the whole file prefix before it. See `AuditChain`.
        public let prev: String?
        /// Which trail this entry belongs to, so a genuinely signed entry cannot
        /// be lifted into another trail and land there intact.
        public let tid: String?
        /// Which key signed it.
        public let skid: String?
        /// Which kind of key signed it — never trusted from here, always checked
        /// against how the key is actually stored.
        public let cls: String?
        /// Base64 of the 64-byte P1363 signature over `AuditChain.signedMaterial`.
        public let sig: String?

        public init(v: Int, kid: String, epk: String, ct: String,
                    prev: String? = nil, tid: String? = nil, skid: String? = nil,
                    cls: String? = nil, sig: String? = nil) {
            self.v = v; self.kid = kid; self.epk = epk; self.ct = ct
            self.prev = prev; self.tid = tid; self.skid = skid; self.cls = cls; self.sig = sig
        }

        /// The same line with the chain fields attached. Sealing and signing are
        /// two steps against one record: the seal is made first and the signature
        /// covers it, so this is how the second step lands on the first.
        public func signed(prev: String, tid: String, skid: String,
                           cls: String, sig: String) -> SealedLine {
            SealedLine(v: v, kid: kid, epk: epk, ct: ct,
                       prev: prev, tid: tid, skid: skid, cls: cls, sig: sig)
        }
    }

    /// A short stable fingerprint of the sealing key: the first 16 hex of SHA-256
    /// over its raw bytes. Recorded on every line for two reasons — a line sealed
    /// to a key you do not hold is *detected* rather than fed to the wrong key,
    /// and re-sealing an old trail under a new key stays possible later without a
    /// format change.
    public static func keyId(for publicKey: Curve25519.KeyAgreement.PublicKey) -> String {
        let hex = SHA256.hash(data: publicKey.rawRepresentation)
            .map { String(format: "%02x", $0) }.joined()
        return String(hex.prefix(16))
    }

    /// The authenticated-but-not-encrypted header. Binding it as AES-GCM
    /// additional data is what makes a swapped `kid` or `epk` fail to open instead
    /// of quietly producing a different plaintext.
    private static func header(kid: String, epk: Data) -> Data {
        Data("proctor-audit-seal-v1|\(version)|\(kid)|".utf8) + epk
    }

    private static func derive(_ shared: SharedSecret, kid: String, epk: Data) -> SymmetricKey {
        shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: salt,
                                       sharedInfo: Data(kid.utf8) + epk,
                                       outputByteCount: 32)
    }

    /// Seal one line to the trail's public key. A fresh ephemeral key pair per
    /// line means every line has an independent symmetric key, so there is no
    /// nonce counter for concurrent appends to coordinate — the append stays a
    /// single write with no shared state.
    ///
    /// Returns nil rather than throwing, and the caller's contract on nil is to
    /// write *nothing*: a plaintext fallback would silently undo the feature.
    public static func seal(line: String, to publicKey: Curve25519.KeyAgreement.PublicKey) -> String? {
        guard let sealed = sealLine(line: line, to: publicKey) else { return nil }
        return encode(sealed)
    }

    /// The same seal, stopping one step short of the wire so the caller can
    /// attach the chain fields before the record's bytes are fixed. The
    /// signature covers values rather than the encoded document, but the *link*
    /// is a hash of the bytes, so the bytes must not change after signing.
    public static func sealLine(line: String,
                                to publicKey: Curve25519.KeyAgreement.PublicKey) -> SealedLine? {
        let kid = keyId(for: publicKey)
        let ephemeral = Curve25519.KeyAgreement.PrivateKey()
        let epk = ephemeral.publicKey.rawRepresentation
        guard let shared = try? ephemeral.sharedSecretFromKeyAgreement(with: publicKey) else {
            return nil
        }
        let key = derive(shared, kid: kid, epk: epk)
        guard let box = try? AES.GCM.seal(Data(line.utf8), using: key,
                                          authenticating: header(kid: kid, epk: epk)),
              let combined = box.combined else { return nil }
        return SealedLine(v: version, kid: kid,
                          epk: epk.base64EncodedString(),
                          ct: combined.base64EncodedString())
    }

    /// One record's JSON, compact with sorted keys. The only place a sealed line
    /// is turned into bytes, so the bytes a link hashes are produced one way.
    public static func encode(_ sealed: SealedLine) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(sealed),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return text
    }

    /// One record, back. Nil for anything that is not a sealed record at all.
    public static func decode(_ line: String) -> SealedLine? {
        guard let data = line.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(SealedLine.self, from: data)
    }

    /// Open one sealed line. Nil on anything that is not a line this key sealed —
    /// a malformed line, an unknown version, another key's `kid`, a tampered
    /// ciphertext or header. Never throws into the read path: one bad line must
    /// not blind the whole trail, so the reader marks it and carries on.
    public static func open(_ line: String,
                            with privateKey: Curve25519.KeyAgreement.PrivateKey) -> String? {
        guard let sealed = decode(line),
              sealed.v == version,
              keyId(for: privateKey.publicKey) == sealed.kid,
              let epk = Data(base64Encoded: sealed.epk),
              let ct = Data(base64Encoded: sealed.ct),
              let ephemeralPublic = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: epk),
              let shared = try? privateKey.sharedSecretFromKeyAgreement(with: ephemeralPublic)
        else { return nil }
        let key = derive(shared, kid: sealed.kid, epk: epk)
        guard let box = try? AES.GCM.SealedBox(combined: ct),
              let plain = try? AES.GCM.open(box, using: key,
                                            authenticating: header(kid: sealed.kid, epk: epk)),
              let text = String(data: plain, encoding: .utf8) else { return nil }
        return text
    }

    /// Whether a stored line is sealed. This is the migration's discriminator: a
    /// plaintext `AuditRecord` line carries none of these four keys, so a trail
    /// can be told apart from a converted one without the key.
    public static func isSealed(_ line: String) -> Bool { decode(line) != nil }
}
