import Foundation
import ProctorCore

// On-disk homes for the two rails, mirroring FlowStore: the policy is a small
// JSON document, the audit trail an append-only JSONL file. Both live under the
// agent's Application Support directory at 0700, so a locked, unattended run
// leaves a record on the same machine that produced it.

/// The persisted app policy. Loading a missing or unreadable file yields an empty
/// policy — no lists means the gate allows every app, which is the pre-feature
/// behaviour, so installing the tool changes nothing until an operator configures it.
enum PolicyStore {

    static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/\(Wire.bundleIdentifier)/policy",
                                    isDirectory: true)
    }

    static var url: URL { directory.appendingPathComponent("policy.json", isDirectory: false) }

    static func load() -> AppPolicy {
        guard let data = try? Data(contentsOf: url),
              let policy = try? JSONDecoder().decode(AppPolicy.self, from: data) else {
            return AppPolicy()
        }
        return policy
    }

    static func save(_ policy: AppPolicy) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(policy).write(to: url, options: .atomic)
    }
}

/// The append-only redacting audit trail, sealed at rest. One JSONL line per
/// event, each line encrypted on its own to a public key held beside the log, so
/// an append is still a single write and a file copied off the machine is
/// unreadable without the Keychain half (`AuditKeyStore`).
///
/// Appending is best-effort in one direction only: a write that fails must not
/// fail the action it was recording, but it must never fall back to plaintext.
/// A failure is remembered in `status` so a run that expected an audit and got
/// none can tell — before this the failure was silent.
enum AuditLog {

    /// What a stored line came back as. A line that cannot be opened is marked
    /// rather than dropped, so one bad or older entry does not blind the trail.
    enum Entry {
        case opened(String)
        case unreadable(kid: String?, reason: String)
    }

    /// Process-wide trail state, guarded the way the rest of the agent guards
    /// shared mutable state (`UnlockCoordinator`, `AXQuietTracker`).
    final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var migrationDone = false
        private var unavailable = false
        private var lastError: String?
        private var dropped = 0
        private var converted: Int?
        private var keyMismatch = false

        func withLock<T>(_ body: () -> T) -> T {
            lock.lock(); defer { lock.unlock() }
            return body()
        }

        // Callers below already hold the lock via `withLock`.
        var isUnavailable: Bool { unavailable }
        var error: String? { lastError }
        var droppedCount: Int { dropped }
        var convertedCount: Int? { converted }
        var hasMigrated: Bool { migrationDone }
        var hasKeyMismatch: Bool { keyMismatch }

        func markMigrated() { migrationDone = true }
        func markConverted(_ n: Int) { converted = n }
        func markKeyMismatch() { keyMismatch = true }
        func fail(_ reason: String, unavailable: Bool = false, dropped: Bool = true) {
            lastError = reason
            if dropped { self.dropped += 1 }
            if unavailable { self.unavailable = true }
        }
        /// Clears the *current* error only. The dropped count is monotonic on
        /// purpose: a later success must not erase the fact that entries were lost,
        /// which is exactly the silence this feature was asked to remove.
        func clearError() { lastError = nil }
    }

    static let state = State()

    static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/\(Wire.bundleIdentifier)/audit",
                                    isDirectory: true)
    }

    static var url: URL { directory.appendingPathComponent("audit.jsonl", isDirectory: false) }

    private static var convertingURL: URL {
        directory.appendingPathComponent("audit.jsonl.converting", isDirectory: false)
    }

    /// Append one record, sealed. Creates the file and directory on first use, and
    /// converts any plaintext trail it finds before writing anything new. The write
    /// is a single `write(2)` of the sealed line plus a newline, so concurrent
    /// appends serialise into whole lines rather than interleaving.
    ///
    /// Returns false — and writes nothing at all — when the trail cannot be sealed.
    /// There is deliberately no plaintext path out of here: a readable fallback
    /// would silently undo the feature.
    @discardableResult
    static func append(_ record: AuditRecord) -> Bool {
        state.withLock {
            // The whole append, migration included, runs under a cross-process
            // advisory lock: the migration reads the file and then replaces it, so
            // a second agent appending in between would have its line dropped by
            // the swap. The in-process lock alone cannot see that.
            let result: Bool? = withAuditFileLock {
                migrateIfNeededLocked()
                if state.isUnavailable { return false }
                guard let pub = AuditKeyStore.shared.publicKey() else {
                    state.fail("The audit key could not be reached, so nothing is being written to the trail.")
                    return false
                }
                guard let sealed = AuditSeal.seal(line: record.jsonLine(), to: pub) else {
                    state.fail("An audit entry could not be sealed, so it was dropped rather than written readable.")
                    return false
                }
                guard appendRawLocked(sealed) else {
                    state.fail("The audit trail could not be written to.")
                    return false
                }
                state.clearError()
                return true
            }
            guard let result else {
                state.fail("The audit trail could not be locked for writing, so the entry was dropped.")
                return false
            }
            return result
        }
    }

    /// Serialise every writer, in this process and any other, around the trail.
    /// The lock is a sidecar file rather than the trail itself, because the
    /// conversion replaces the trail's inode and a lock held on the old one would
    /// stop excluding anybody. Returns nil when the lock could not be taken, which
    /// the caller treats as a dropped entry rather than a licence to write.
    private static func withAuditFileLock<T>(_ body: () -> T) -> T? {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o700])
        let path = directory.appendingPathComponent("audit.lock", isDirectory: false).path
        let fd = Darwin.open(path, O_RDWR | O_CREAT, 0o600)
        guard fd >= 0 else { return nil }
        defer { Darwin.close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { return nil }
        defer { flock(fd, LOCK_UN) }
        return body()
    }

    /// One append, opened `O_APPEND` so the kernel places the write at the end of
    /// the file atomically. Seeking to the end and writing is not the same thing:
    /// two writers can seek to the same offset and overwrite each other's line.
    private static func appendRawLocked(_ line: String) -> Bool {
        guard let data = (line + "\n").data(using: .utf8) else { return false }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        let fd = Darwin.open(url.path, O_WRONLY | O_APPEND | O_CREAT, 0o600)
        guard fd >= 0 else { return false }
        defer { Darwin.close(fd) }
        return data.withUnsafeBytes { buffer -> Bool in
            guard let base = buffer.baseAddress else { return false }
            var written = 0
            while written < buffer.count {
                let n = Darwin.write(fd, base.advanced(by: written), buffer.count - written)
                if n <= 0 { return false }
                written += n
            }
            return true
        }
    }

    // MARK: - One-time in-place conversion

    /// Convert a readable trail in place, once per run, before the first new entry.
    ///
    /// This is destructive on purpose and by the product owner's explicit choice:
    /// when it succeeds, the only readable copy of the history that existed is
    /// gone, and there is no backup, sidecar or export. Leaving a plaintext copy
    /// beside a sealed one would keep exactly the exposure the feature removes.
    ///
    /// It is all-or-nothing. If any part fails, the original is left byte for byte
    /// as it was, the trail is marked unavailable and nothing more is appended for
    /// the rest of the run — which stops both a half-converted file and new entries
    /// landing in a still-readable one.
    private static func migrateIfNeededLocked() {
        guard !state.hasMigrated else { return }
        state.markMigrated()

        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return }
        // A file that exists but cannot be read is not the same as no file: reading
        // past it would append sealed lines to a trail that may still hold readable
        // ones, which is the exposure this conversion exists to end.
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            fail(conversion: "the existing trail could not be read")
            return
        }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        let plaintext = lines.filter { !AuditSeal.isSealed($0) }
        guard !plaintext.isEmpty else { return }

        guard let pub = AuditKeyStore.shared.publicKey() else {
            fail(conversion: "the audit key could not be reached")
            return
        }
        var out: [String] = []
        out.reserveCapacity(lines.count)
        for line in lines {
            if AuditSeal.isSealed(line) {
                out.append(line)
            } else if let sealed = AuditSeal.seal(line: line, to: pub) {
                out.append(sealed)
            } else {
                fail(conversion: "an existing entry could not be sealed")
                return
            }
        }

        let temp = convertingURL
        try? fm.removeItem(at: temp)
        do {
            let body = out.joined(separator: "\n") + "\n"
            try body.write(to: temp, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temp.path)
            // An atomic same-directory replace: either the whole converted trail is
            // in place or the original still is. No backup item is requested, so no
            // readable copy survives the swap.
            _ = try fm.replaceItemAt(url, withItemAt: temp)
        } catch {
            try? fm.removeItem(at: temp)
            fail(conversion: "the converted trail could not replace the original (\(error.localizedDescription))")
            return
        }

        state.markConverted(plaintext.count)
        note("audit trail converted to encrypted-at-rest: \(plaintext.count) "
             + "previously readable \(plaintext.count == 1 ? "entry is" : "entries are") now sealed at "
             + "\(url.path). The readable copy is gone and there is no backup; the trail can only be "
             + "read on this Mac with this login keychain.")
    }

    private static func fail(conversion reason: String) {
        state.fail("The existing readable audit trail could not be converted (\(reason)), so it was "
                   + "left untouched and nothing further is being written to it.",
                   unavailable: true, dropped: false)
        note("audit trail NOT being written: conversion failed because \(reason). The existing trail "
             + "is unchanged at \(url.path).")
    }

    /// The conversion is loud rather than silent — it destroys the only readable
    /// copy of the history, so the run that does it says so.
    private static func note(_ message: String) {
        FileHandle.standardError.write(Data("proctor-agent: \(message)\n".utf8))
    }

    // MARK: - Reading

    /// The most recent `limit` stored lines, oldest first, exactly as they sit on
    /// disk. Reads the whole file, which is acceptable for an operator reading a
    /// tail; the file is a session's worth of actions, not an unbounded log.
    static func tail(_ limit: Int) -> [String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        return Array(lines.suffix(max(0, limit)))
    }

    /// The same tail, opened. Needs the Keychain half, which is the attended
    /// operation. A line sealed to a key this Mac no longer holds comes back
    /// marked rather than throwing, so one unreadable entry costs one entry.
    ///
    /// This is also the only moment the two halves can be checked against each
    /// other, so it is where a `audit.pub` that no longer matches the stored key is
    /// caught: sealing needs only that file, so a replaced one would send every
    /// future entry to a key nobody holds while every write still reported success.
    static func openedTail(_ limit: Int) -> [Entry] {
        let lines = tail(limit)
        guard lines.contains(where: { AuditSeal.isSealed($0) }) else {
            return lines.map { .opened($0) }
        }
        guard let priv = AuditKeyStore.shared.privateKey() else {
            return lines.map { line in
                AuditSeal.isSealed(line)
                    ? .unreadable(kid: keyId(of: line),
                                  reason: "The audit key is not available in this login keychain.")
                    : .opened(line)
            }
        }
        if AuditKeyStore.shared.cachedPublicKeyMatches(priv) == false {
            state.withLock { state.markKeyMismatch() }
        }
        return lines.map { line in
            guard AuditSeal.isSealed(line) else { return .opened(line) }
            if let plain = AuditSeal.open(line, with: priv) { return .opened(plain) }
            return .unreadable(kid: keyId(of: line),
                               reason: "This entry was sealed with a key this Mac no longer holds.")
        }
    }

    private static func keyId(of line: String) -> String? {
        guard let data = line.data(using: .utf8),
              let sealed = try? JSONDecoder().decode(AuditSeal.SealedLine.self, from: data)
        else { return nil }
        return sealed.kid
    }

    /// Where the trail is and how many entries it holds — both answerable without
    /// the key, so an operator who cannot read it can still see it is growing.
    static func lineCount() -> Int {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return 0 }
        return text.split(separator: "\n", omittingEmptySubsequences: true).count
    }

    /// Whether the trail is being written, why not when it is not, how many entries
    /// have been lost this run, which key seals it, whether the sealing key on disk
    /// still matches the one this Mac holds, and whether this run performed the
    /// one-time conversion.
    static func status() -> (writable: Bool, error: String?, dropped: Int,
                             keyId: String?, keyMismatch: Bool, converted: Int?) {
        state.withLock {
            let kid: String? = AuditKeyStore.shared.hasCachedPublicKey()
                ? AuditKeyStore.shared.publicKey().map(AuditSeal.keyId(for:))
                : nil
            return (writable: !state.isUnavailable && state.error == nil,
                    error: state.error, dropped: state.droppedCount, keyId: kid,
                    keyMismatch: state.hasKeyMismatch, converted: state.convertedCount)
        }
    }
}
