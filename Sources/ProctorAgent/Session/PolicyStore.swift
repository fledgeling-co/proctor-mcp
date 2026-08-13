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

/// The append-only redacting audit trail. One JSONL line per event, written under
/// a directory the process owns. Appending is best-effort: a write that fails must
/// not fail the action it was recording, but the failure is surfaced to the caller
/// through `lastError` so a run that expected an audit and got none can tell.
enum AuditLog {

    static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/\(Wire.bundleIdentifier)/audit",
                                    isDirectory: true)
    }

    static var url: URL { directory.appendingPathComponent("audit.jsonl", isDirectory: false) }

    /// Append one record. Creates the file and directory on first use. The write is
    /// a single `write(2)` of the line plus a newline, so concurrent appends from
    /// the actor serialise into whole lines rather than interleaving.
    @discardableResult
    static func append(_ record: AuditRecord) -> Bool {
        let line = record.jsonLine() + "\n"
        guard let data = line.data(using: .utf8) else { return false }
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true,
                                   attributes: [.posixPermissions: 0o700])
            if !fm.fileExists(atPath: url.path) {
                fm.createFile(atPath: url.path, contents: nil,
                              attributes: [.posixPermissions: 0o600])
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            return true
        } catch {
            return false
        }
    }

    /// The most recent `limit` lines, oldest first. Reads the whole file, which is
    /// acceptable for an operator reading a tail; the file is a session's worth of
    /// actions, not an unbounded log.
    static func tail(_ limit: Int) -> [String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        return Array(lines.suffix(max(0, limit)))
    }

    static func lineCount() -> Int {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return 0 }
        return text.split(separator: "\n", omittingEmptySubsequences: true).count
    }
}
