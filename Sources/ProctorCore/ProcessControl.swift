import Foundation

// process_kill, decision half. Listing and terminating processes is test-harness
// plumbing — reset state between runs by killing the app under test and relaunching
// it clean. Selecting which processes a query names, and deciding whether a kill is
// authorised, are pure and live here; the signal delivery (NSRunningApplication /
// kill(2)) is agent-side, over these tested units.
//
// Killing is destructive, so it reuses the two PRO-0005 rails rather than inventing
// a parallel one: authorisation goes through `AppPolicy.decide` (block wins,
// allow-list fails closed, sensitive needs a token) and every attempt is recorded
// as an `AuditRecord`.

/// The minimal identity of a running process a matcher needs. A GUI application
/// carries a bundle id and a localised name; a bare pid target carries neither.
public struct ProcessInfoLite: Sendable, Equatable {
    public let pid: Int32
    public let name: String
    public let bundleId: String?
    public init(pid: Int32, name: String, bundleId: String? = nil) {
        self.pid = pid; self.name = name; self.bundleId = bundleId
    }
}

/// A process selector. All supplied conditions must hold (a conjunction, like the
/// accessibility find predicate), so `{bundleId, name}` narrows rather than widens.
public struct KillQuery: Sendable, Equatable {
    public var pid: Int32?
    public var bundleId: String?
    public var name: String?
    public var match: Match

    public enum Match: String, Sendable, Equatable { case substring, exact }

    public init(pid: Int32? = nil, bundleId: String? = nil,
                name: String? = nil, match: Match = .substring) {
        self.pid = pid; self.bundleId = bundleId; self.name = name; self.match = match
    }

    /// A query with no condition names nothing. Killing on an empty selector would
    /// mean "every process", which is never what a test-teardown step intends.
    public var isEmpty: Bool { pid == nil && bundleId == nil && name == nil }
}

/// Which signal a kill delivers. `term` asks politely (SIGTERM / `terminate`);
/// `kill` forces (SIGKILL / `forceTerminate`) for a hung target that ignored the
/// first.
public enum KillSignal: String, Sendable, Equatable { case term, kill }

public enum ProcessMatcher {

    /// The processes a query names. Empty query → nothing; otherwise every
    /// candidate for which all supplied conditions hold. pid is exact; bundle id is
    /// an exact case-insensitive match; name honours the query's substring/exact
    /// mode, case-insensitively.
    public static func select(_ candidates: [ProcessInfoLite], query: KillQuery) -> [ProcessInfoLite] {
        guard !query.isEmpty else { return [] }
        return candidates.filter { candidate in
            if let pid = query.pid, candidate.pid != pid { return false }
            if let bundleId = query.bundleId,
               candidate.bundleId?.caseInsensitiveCompare(bundleId) != .orderedSame { return false }
            if let name = query.name, !matchName(candidate.name, name, mode: query.match) { return false }
            return true
        }
    }

    static func matchName(_ candidate: String, _ query: String, mode: KillQuery.Match) -> Bool {
        switch mode {
        case .exact:     return candidate.caseInsensitiveCompare(query) == .orderedSame
        case .substring: return candidate.range(of: query, options: .caseInsensitive) != nil
        }
    }

    /// Processes the agent must never signal: the kernel and launchd (pid 0 and 1),
    /// and the agent's own process — killing self would end the session mid-request.
    public static func isProtected(pid: Int32, selfPid: Int32) -> Bool {
        pid <= 1 || pid == selfPid
    }

    /// The audit record for one kill attempt. It names the target and the outcome
    /// and sets no redaction slot, because a kill carries no typed secret — which is
    /// the whole reason the trail can prove what was terminated without a value in
    /// the clear. Reuses the PRO-0005 `AuditRecord`, not a parallel log shape.
    public static func killAudit(_ target: ProcessInfoLite, tool: String, signal: KillSignal,
                                 outcome: String, reason: String?, timestamp: Double) -> AuditRecord {
        AuditRecord(timestamp: timestamp, tool: tool,
                    app: target.name.isEmpty ? "pid:\(target.pid)" : target.name,
                    bundleId: target.bundleId, window: nil, node: nil,
                    kind: signal == .kill ? "forceTerminate" : "terminate",
                    outcome: outcome, postStateHash: nil, value: nil, script: nil, reason: reason)
    }
}
