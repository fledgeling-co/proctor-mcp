import Foundation
import AppKit
import ProctorCore

// process_kill, agent half. The selection and the authorisation decision are pure
// and tested in ProctorCore (ProcessMatcher, AppPolicy); this file enumerates the
// running processes, applies those decisions, writes the audit trail, and delivers
// the signal. It reuses the PRO-0005 rails rather than a parallel mechanism: the
// same `policy.decide` that gates driving an app gates killing it, and the same
// `AuditLog` records every attempt.

/// PRO-0092. The bare-pid rule, lifted out of `killProcesses` so it can be
/// stated without enumerating the machine's running applications first.
///
/// A query naming a pid need not name a GUI application, and a pid that is not
/// among the GUI candidates must still be selectable and signallable — with no
/// bundle id, so an allow list in force refuses it and the path fails closed.
/// The mutation this exists for turned `$0.pid == pid` into `$0.pid != pid`,
/// which appends nothing whenever any other process is running, and 1,818 tests
/// did not notice that a bare pid had stopped being reachable.
enum KillCandidates {

    static func includingBarePid(_ candidates: [ProcessInfoLite],
                                 query: KillQuery) -> [ProcessInfoLite] {
        guard let pid = query.pid,
              !candidates.contains(where: { $0.pid == pid }) else { return candidates }
        return candidates + [ProcessInfoLite(pid: pid, name: "", bundleId: nil)]
    }
}

extension Session {

    func killProcesses(query: KillQuery, perform: Bool, force: Bool) throws -> JSONValue {
        let selfPid = ProcessInfo.processInfo.processIdentifier

        // GUI applications carry the identity a query and the policy gate need.
        let running = NSWorkspace.shared.runningApplications.map {
            ProcessInfoLite(pid: $0.processIdentifier,
                            name: $0.localizedName ?? "",
                            bundleId: $0.bundleIdentifier)
        }
        // A bare pid target need not be a GUI app; synthesise a candidate so it can
        // still be selected and signalled (with no bundle id, so an allow list in
        // force refuses it — fail closed). The rule itself is `KillCandidates`.
        let candidates = KillCandidates.includingBarePid(running, query: query)

        let matched = ProcessMatcher.select(candidates, query: query)
            .filter { !ProcessMatcher.isProtected(pid: $0.pid, selfPid: selfPid) }

        if !perform {
            return .object([
                "action": .string("list"),
                "matched": .number(Double(matched.count)),
                "processes": .array(matched.map(processJSON))
            ])
        }

        loadPolicyIfNeeded()
        let now = Date().timeIntervalSince1970
        let signal: KillSignal = force ? .kill : .term
        var results: [JSONValue] = []
        var terminated = 0, refused = 0, failed = 0

        for target in matched {
            let hasToken = approvalToken?.isValid(at: now, for: target.bundleId) ?? false
            switch policy.decide(bundleId: target.bundleId, hasValidToken: hasToken) {
            case .allow:
                let ok = deliverSignal(signal, to: target)
                if ok { terminated += 1 } else { failed += 1 }
                AuditLog.append(ProcessMatcher.killAudit(
                    target, tool: "proctor_kill", signal: signal,
                    outcome: ok ? "ok" : "failed", reason: ok ? nil : "signal delivery failed",
                    timestamp: now))
                results.append(outcomeJSON(target, outcome: ok ? "terminated" : "failed",
                                           signal: signal, reason: ok ? nil : "signal delivery failed"))
            case .blocked(let reason), .needsApproval(let reason):
                refused += 1
                AuditLog.append(ProcessMatcher.killAudit(
                    target, tool: "proctor_kill", signal: signal,
                    outcome: "refused", reason: reason, timestamp: now))
                results.append(outcomeJSON(target, outcome: "refused", signal: signal, reason: reason))
            }
        }

        return .object([
            "action": .string("kill"),
            "matched": .number(Double(matched.count)),
            "terminated": .number(Double(terminated)),
            "refused": .number(Double(refused)),
            "failed": .number(Double(failed)),
            "results": .array(results)
        ])
    }

    /// Deliver a signal to one target. A GUI application is asked through
    /// NSRunningApplication so it gets its normal termination path; a non-GUI pid
    /// falls back to kill(2).
    private func deliverSignal(_ signal: KillSignal, to target: ProcessInfoLite) -> Bool {
        if let app = NSRunningApplication(processIdentifier: target.pid) {
            return signal == .kill ? app.forceTerminate() : app.terminate()
        }
        return kill(target.pid, signal == .kill ? SIGKILL : SIGTERM) == 0
    }

    private func processJSON(_ p: ProcessInfoLite) -> JSONValue {
        var obj: [String: JSONValue] = [
            "pid": .number(Double(p.pid)),
            "name": .string(p.name)
        ]
        if let bundleId = p.bundleId { obj["bundleId"] = .string(bundleId) }
        return .object(obj)
    }

    private func outcomeJSON(_ p: ProcessInfoLite, outcome: String,
                             signal: KillSignal, reason: String?) -> JSONValue {
        var obj = processJSON(p).objectValue ?? [:]
        obj["outcome"] = .string(outcome)
        obj["signal"] = .string(signal.rawValue)
        if let reason { obj["reason"] = .string(reason) }
        return .object(obj)
    }
}
