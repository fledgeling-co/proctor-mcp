import Foundation

// PRO-0073. The operator CLI's surface, as a value.
//
// Not built until now: `proctor-shim` has seven commands and every one is
// install-or-serve plumbing, so no capability of the product is reachable from a
// shell. Debugging a selector needs a model in the loop; CI cannot assert
// without embedding an MCP client; and a defect report cannot carry a
// reproduction command, which the 28-case campaign paid for by driving every
// case through an MCP session by hand.
//
// **A CLI call is not a privilege bypass.** Same socket, same policy gate, same
// queue lane, same audit trail, same HUD disclosure. The only thing that differs
// is who called.

public enum CLISurface {

    /// What a run's exit code means.
    ///
    /// 1 and 3 must never be confused: one is a check that failed, the other is
    /// nothing measured. CI reads an exit code rather than prose, and collapsing
    /// them turns "the app is broken" and "the agent is not running" into the
    /// same signal.
    public enum Exit: Int32, Sendable, CaseIterable, Error {
        /// The call succeeded and any assertion passed.
        case ok = 0
        /// The call succeeded and a verdict failed.
        case verdictFailed = 1
        /// Usage error.
        case usage = 2
        /// The agent is not answering. Nothing was measured.
        case agentUnreachable = 3
        /// Refused by the policy gate or the guest-route gate.
        case refused = 4
        /// Refused for a missing grant or an unavailable lane.
        case notReady = 5

        public var meaning: String {
            switch self {
            case .ok: return "the call succeeded and any assertion passed"
            case .verdictFailed: return "the call succeeded and a verdict failed"
            case .usage: return "usage error"
            case .agentUnreachable: return "the agent is not answering — nothing was measured"
            case .refused: return "refused by a gate"
            case .notReady: return "a grant is missing or a lane is unavailable"
            }
        }
    }

    /// Map an agent error to an exit code.
    ///
    /// Every code the wire can produce lands somewhere deliberate. A default of
    /// `verdictFailed` would report "the agent is missing a grant" as "your
    /// check failed", which is the confusion this enum exists to prevent.
    public static func exit(for code: AgentError.Code) -> Exit {
        switch code {
        case .agentUnavailable:
            return .agentUnreachable
        case .policyDenied, .haltedByPerson, .queueBusy:
            return .refused
        case .permissionAccessibility, .permissionScreenRecording, .permissionAutomation,
             .reflectorUnavailable, .secureInputActive, .notImplemented:
            return .notReady
        case .invalidArguments:
            return .usage
        default:
            return .verdictFailed
        }
    }

    /// A verb, one per tool.
    public struct Verb: Sendable, Equatable {
        public let name: String
        public let tool: String
        /// Whether the call takes a queue lane. Reads never join the line, so a
        /// `proctor snapshot` cannot serialise a person's debugging behind a
        /// model's run.
        public let queues: Bool
        public let destructive: Bool
    }

    /// Derived from `ToolCatalogue`, never listed by hand.
    ///
    /// A tool added without a verb is a red test rather than a gap somebody
    /// notices later, and the verb name is mechanical: `proctor_snapshot`
    /// becomes `snapshot`.
    public static var verbs: [Verb] {
        ToolCatalogue.all.map { spec in
            Verb(name: verbName(for: spec.name),
                 tool: spec.name,
                 // The three-lane model: reads never queue. A read-only tool
                 // never reaches the step loop, so it never takes a lane.
                 queues: !spec.readOnly,
                 destructive: spec.destructive)
        }
    }

    public static func verbName(for tool: String) -> String {
        tool.hasPrefix("proctor_") ? String(tool.dropFirst("proctor_".count)) : tool
    }

    public static func verb(named name: String) -> Verb? {
        verbs.first { $0.name == name }
    }

    /// The service verbs, which are not tools. `proctor-shim` keeps working as
    /// an alias so existing host configurations are untouched.
    public static let serviceVerbs = ["install", "uninstall", "status", "serve", "tui"]

    public static var allVerbNames: [String] { verbs.map(\.name) + serviceVerbs }

    // MARK: - Reading a verdict out of a reply
    //
    // Lives here rather than in the CLI target so it can be asserted against
    // replies written by hand. The decision it makes is the one CI reads, and a
    // decision only reachable through a live agent is a decision nothing checks.

    /// The exit code a successful call earns, from what came back.
    ///
    /// A call that worked and a check that passed are two different facts, and
    /// this is where they are separated. `--lane` narrows the question to one
    /// lane: a person asking whether the Mac lane is ready does not want a
    /// non-zero code because the iOS lane has no simulator booted.
    public static func exit(forReply reply: JSONValue, lane: String?) -> Exit {
        if let lane {
            let lanes = reply["lanes"]?.arrayValue ?? []
            guard let match = lanes.first(where: { $0["lane"]?.stringValue == lane }),
                  match["state"]?.stringValue == "ready" else { return .notReady }
            return .ok
        }
        if reply["ready"]?.boolValue == false { return .notReady }
        if let failed = reply["failedAt"], failed != .null { return .verdictFailed }
        if let assertions = reply["assertions"]?.arrayValue,
           assertions.contains(where: { $0["ok"]?.boolValue == false }) {
            return .verdictFailed
        }
        return .ok
    }

    /// What to say on stderr when a named lane is not ready. `absent` rather
    /// than a blank: a lane the reply never mentioned is a different situation
    /// from one that answered and said it was not ready.
    public static func laneState(_ reply: JSONValue, lane: String) -> String {
        let lanes = reply["lanes"]?.arrayValue ?? []
        return lanes.first { $0["lane"]?.stringValue == lane }?["state"]?.stringValue ?? "absent"
    }

    // MARK: - Completion
    //
    // Generated from the catalogue, so it cannot drift from what the binary
    // actually accepts.

    public static func completionScript(shell: String) -> String? {
        let names = allVerbNames.sorted().joined(separator: " ")
        switch shell {
        case "zsh":
            return """
            #compdef proctor
            # Generated from ToolCatalogue. Do not edit.
            _proctor() { _arguments '1:verb:(\(names))' '*::arg:->args' }
            _proctor "$@"
            """
        case "bash":
            return """
            # Generated from ToolCatalogue. Do not edit.
            _proctor() {
              COMPREPLY=( $(compgen -W "\(names)" -- "${COMP_WORDS[COMP_CWORD]}") )
            }
            complete -F _proctor proctor
            """
        default:
            return nil
        }
    }

    /// Every binary the bundle ships, by the filename it ships under.
    ///
    /// Kept as a value because of a defect found while building this feature: a
    /// SwiftPM product named `proctor` and the UI product `Proctor` are the same
    /// file on a case-insensitive volume, which APFS is by default. `swift build`
    /// reported success and the binary at `.build/…/proctor` was the SwiftUI app,
    /// which launched a window instead of printing usage. Nothing in the toolchain
    /// said so — the collision is silent at every stage — so the invariant is
    /// asserted here instead.
    public static let shippedBinaries = ["proctor-agent", "proctor-shim", "Proctor", "proctor-cli"]

    /// The name the CLI is invoked under, which is not the name it ships under.
    /// A symlink on the caller's PATH bridges the two; Proctor does not create it.
    public static let invokedAs = "proctor"

    /// Proctor installs nothing, and the CLI is the surface where that rule is
    /// easiest to break. Kept as a value so the test can assert no verb, usage
    /// line or completion script carries one.
    public static let forbiddenInstallMarkers = [
        "brew install", "curl ", "npm install", "pip install", "sudo ", "| sh", "wget ",
    ]
}
