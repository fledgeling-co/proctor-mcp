import Foundation

// The Maestro flow lane, decision half. Everything here is pure: no Process, no
// FileManager, no clock it is not given. The subprocesses and the actor state
// live in ProctorAgent/Session/SessionMaestro.swift, which is what makes the
// whole verdict ladder, the score basis and the flow scan provable on a machine
// with no Maestro, no Xcode and no booted device.
//
// **This is a flow-level seam and deliberately not an ActuationBackend.** That
// protocol performs a step; Maestro executes a file. PRO-0044 left this item the
// warning and it is correct: nothing here implements, extends or registers an
// actuation backend, and nothing here turns a Maestro command into an ActionStep.
// PRO-0020 settled the second half for browser tools — a tool driving its own
// engine is not driving the window Proctor is attached to, so a routed step would
// report success against something Proctor never touched.
//
// The thing this file exists to prevent is a determinism score that measures the
// driver. Measured on 2026-08-15 with maestro 2.4.0: five identical passing runs
// of one flow produced an identical per-command status vector, and per-command
// durations that spread 7x on an unchanged command. One of those is a signal and
// the other would report a perfectly stable flow as 100% unstable.

// MARK: - One command, as Maestro reports it

/// A single entry from Maestro's `commands-*.json`.
///
/// `status` is carried through in Maestro's own vocabulary rather than remapped
/// onto an enum of ours: a value this build has not seen survives into the report
/// instead of being flattened into whichever case looked closest.
public struct MaestroCommand: Codable, Sendable, Equatable {
    /// The single key of the record's `command` object — `tapOnElement`,
    /// `assertConditionCommand`, `launchAppCommand`.
    public var type: String
    /// That key's body: what the command was actually asked to do.
    public var parameters: JSONValue
    /// `COMPLETED`, `FAILED`, or whatever else Maestro writes.
    public var status: String
    public var sequenceNumber: Int
    public var durationMs: Int
    public var timestampMs: Double
    public var errorMessage: String?
    /// Whether Maestro attached its own view hierarchy to the failure. The tree
    /// itself is evidence and is never read into a score, so only its presence
    /// travels here.
    public var hasHierarchy: Bool

    public init(type: String, parameters: JSONValue = .null, status: String,
                sequenceNumber: Int, durationMs: Int = 0, timestampMs: Double = 0,
                errorMessage: String? = nil, hasHierarchy: Bool = false) {
        self.type = type; self.parameters = parameters; self.status = status
        self.sequenceNumber = sequenceNumber; self.durationMs = durationMs
        self.timestampMs = timestampMs; self.errorMessage = errorMessage
        self.hasHierarchy = hasHierarchy
    }

    public static let completed = "COMPLETED"
    public static let failed = "FAILED"

    public var didFail: Bool { status == MaestroCommand.failed }

    /// Whether Maestro injected this command rather than reading it from the
    /// flow file. Measured: both are prepended at sequence 0 and 1 and appear in
    /// no YAML. They stay in the status vector because Maestro executed them and
    /// they were stable across all five measured runs; they are marked so a
    /// caller reading `firstDivergence: 2` does not take it for the second step
    /// of their own file.
    public var isInjected: Bool { MaestroRecord.injectedTypes.contains(type) }

    /// Whether a failure of this command is the harness failing rather than the
    /// application under test misbehaving.
    ///
    /// `launchApp` is a precondition: the app was not installed, the simulator
    /// was wrong, or SpringBoard was wedged. `runScript`, `evalScript` and
    /// `runFlow` are the harness itself. Out-of-family review named all four as
    /// driver faults that would otherwise be folded into the application's
    /// determinism score, and they are separable from data already parsed, so
    /// they are separated.
    public var isHarnessCommand: Bool {
        MaestroRecord.harnessTypes.contains(type)
    }
}

// MARK: - Reading the record

public enum MaestroRecord {

    /// Commands Maestro adds that are in no flow file. Measured 2026-08-15.
    public static let injectedTypes: Set<String> = [
        "defineVariablesCommand", "applyConfigurationCommand"
    ]

    /// Commands whose failure is the harness's rather than the app's.
    public static let harnessTypes: Set<String> = [
        "launchAppCommand", "runScriptCommand", "evalScriptCommand", "runFlowCommand"
    ]

    /// Decode `commands-*.json`, in sequence order.
    ///
    /// The sort is not cosmetic. Measured: the array arrived as sequence
    /// [2, 0, 1, 3], so reading it positionally attributes each command's status
    /// to the wrong command — and every determinism cell would then compare two
    /// different commands across repeats.
    ///
    /// A document that decodes to zero commands is an error rather than an empty
    /// run: "Maestro produced no record" is the driver failure this whole lane
    /// turns on, and it must not arrive dressed as a flow with nothing in it.
    public static func parse(_ data: Data) throws -> [MaestroCommand] {
        struct Entry: Decodable {
            var command: [String: JSONValue]
            var metadata: Metadata
            struct Metadata: Decodable {
                var status: String
                var timestamp: Double?
                var duration: Double?
                var sequenceNumber: Int
                var error: ErrorBody?
            }
            struct ErrorBody: Decodable {
                var message: String?
                var hierarchyRoot: JSONValue?
            }
        }
        let entries = try JSONDecoder().decode([Entry].self, from: data)
        guard !entries.isEmpty else {
            throw MaestroParseFailure.empty
        }
        let commands = entries.map { entry -> MaestroCommand in
            // A command object carries exactly one key. Sorting makes the choice
            // deterministic if Maestro ever writes two, rather than letting
            // dictionary order decide what a command is called.
            let key = entry.command.keys.sorted().first ?? "unknownCommand"
            let hierarchy: Bool = {
                guard let root = entry.metadata.error?.hierarchyRoot else { return false }
                if case .null = root { return false }
                return true
            }()
            return MaestroCommand(
                type: key,
                parameters: entry.command[key] ?? .null,
                status: entry.metadata.status,
                sequenceNumber: entry.metadata.sequenceNumber,
                durationMs: Int(entry.metadata.duration ?? 0),
                timestampMs: entry.metadata.timestamp ?? 0,
                errorMessage: entry.metadata.error?.message,
                hasHierarchy: hierarchy)
        }
        return commands.sorted { $0.sequenceNumber < $1.sequenceNumber }
    }

    /// Which files in a debug directory are per-command records, newest first.
    ///
    /// Pure over a supplied listing so the rule is testable without a filesystem.
    /// The rule is **glob, never construct**: the same flow produced
    /// `commands-(settings).json` on one invocation and
    /// `commands-(settings.yaml).json` on others, and one failing run left two
    /// timestamped directories where only the second held a record. A path built
    /// from the flow's name finds nothing on at least one of those shapes.
    ///
    /// `paths` is expected to be a recursive listing; ordering by descending
    /// modification time is the caller's job, which is why this preserves the
    /// order it is given.
    public static func records(in paths: [String]) -> [String] {
        paths.filter { path in
            let name = (path as NSString).lastPathComponent
            return name.hasPrefix("commands-") && name.hasSuffix(".json")
        }
    }
}

public enum MaestroParseFailure: Error, Equatable {
    /// The document decoded but held no commands.
    case empty
}

// MARK: - The determinism cell

public enum MaestroScore {

    /// One command's contribution to one repeat's hash vector.
    ///
    /// Identity **and** status, and identity means the command's parameters as
    /// well as its type: `tapOn: "General"` and `tapOn: "About"` are both
    /// `tapOnElement`, and a flow with a `when:` branch genuinely executes
    /// different commands on different repeats — which is the divergence most
    /// worth catching.
    ///
    /// Nothing else is here, and the omissions are by construction rather than by
    /// filtering, so a later edit cannot leak one in:
    ///
    /// - **duration** — measured 634 / 91 / 88 / 96 / 91 ms for one unchanged
    ///   command across five repeats. Hashing it reports every stable flow as
    ///   totally unstable.
    /// - **timestamp** — unique per command per run by construction.
    /// - **exit code** — 0 or 1, and 1 covers an assertion failure, an absent
    ///   device and a malformed flow alike.
    /// - **the error message and Maestro's hierarchy dump** — present only on
    ///   failure, uncanonicalised, full of geometry and identifiers. They would
    ///   flake the hash on exactly the runs worth reading. Carried as evidence.
    public static func cell(for command: MaestroCommand) -> String {
        Canonical.hash(command.type + "|" + canonicalParameters(command.parameters)
                       + "|" + command.status)
    }

    /// A stable string for an arbitrary JSON body: keys sorted at every level, so
    /// two encodings of the same command hash the same.
    public static func canonicalParameters(_ value: JSONValue) -> String {
        switch value {
        case .null: return "null"
        case .bool(let b): return b ? "true" : "false"
        case .number(let n):
            // Integral values print without a fractional part so 1 and 1.0 are
            // one command rather than two.
            return n == n.rounded() && n.magnitude < 1e15
                ? String(Int64(n)) : String(n)
        case .string(let s): return "\"" + s + "\""
        case .array(let items):
            return "[" + items.map(canonicalParameters).joined(separator: ",") + "]"
        case .object(let fields):
            return "{" + fields.keys.sorted().map {
                "\"" + $0 + "\":" + canonicalParameters(fields[$0] ?? .null)
            }.joined(separator: ",") + "}"
        }
    }

    /// The hash vector for one repeat.
    public static func vector(for commands: [MaestroCommand]) -> [String] {
        commands.map(cell(for:))
    }
}

// MARK: - Evidence and verdict

/// What was observed around one Maestro invocation. Every field is what a channel
/// reported, never an inference from another channel.
public struct MaestroEvidence: Codable, Sendable, Equatable {
    public var exitCode: Int32
    public var timedOut: Bool
    /// Whether a per-command record was found at all. **This, not the exit code,
    /// is what separates a driver failure from an application failure** — all
    /// three measured driver-side failures exit 1 exactly as a failed assertion
    /// does, and none of them writes a record.
    public var recordFound: Bool
    public var commands: [MaestroCommand]
    /// Whether the app under test's job was present before and after. Nil means
    /// **the channel did not answer**, which is not the same as "not running" and
    /// is never read as one — a device that went away mid-flow reports exactly
    /// this.
    public var targetRunningBefore: Bool?
    public var targetRunningAfter: Bool?
    public var failureReason: String?

    public init(exitCode: Int32, timedOut: Bool = false, recordFound: Bool,
                commands: [MaestroCommand] = [], targetRunningBefore: Bool? = nil,
                targetRunningAfter: Bool? = nil, failureReason: String? = nil) {
        self.exitCode = exitCode; self.timedOut = timedOut
        self.recordFound = recordFound; self.commands = commands
        self.targetRunningBefore = targetRunningBefore
        self.targetRunningAfter = targetRunningAfter
        self.failureReason = failureReason
    }

    public var failedCommands: [MaestroCommand] { commands.filter(\.didFail) }
}

/// The verdict vocabulary. Every value is a claim this lane can defend from the
/// channels it actually has, following the ladder PRO-0048 established for deep
/// links rather than inventing a second one.
public enum MaestroVerdict: String, Codable, Sendable, Equatable {
    /// A record exists and every command reported COMPLETED. Claims that the
    /// driver executed the sequence and reported success — not that Proctor
    /// observed the application reach any state.
    case flowPassed
    /// A record exists and an app-facing command reported FAILED. Maestro's view
    /// says the flow did not hold; which of the app and the driver is responsible
    /// is not established, and the note says so.
    case flowFailed
    /// A command failed and Proctor's own liveness channel says the app was
    /// running before and is gone after. Outranks `flowFailed` exactly as
    /// PRO-0048's `targetGone` outranks a screen change: an app that died must
    /// never be filed as a failed assertion.
    case appGone
    /// The flow never reached the application: no record was written, the only
    /// failure was a harness command, or the liveness channel stopped answering.
    /// **Excluded from the determinism fold** — a repeat that never sampled the
    /// app is not a sample of the app.
    case driverFailed
    /// Proctor refused before invoking anything.
    case refused

    /// Whether this verdict is a positive claim about the app under test.
    public var isAttributed: Bool { self == .flowPassed }
    /// Whether this verdict reports a fault in the app under test.
    public var isAppFault: Bool { self == .appGone }
    /// Whether this repeat may be folded into a determinism score.
    public var isScoreable: Bool { self == .flowPassed || self == .flowFailed }

    /// Decide, and say why. Pure, total, and never computed from exit status
    /// alone — which is the whole point of the lane.
    public static func decide(_ evidence: MaestroEvidence) -> (verdict: MaestroVerdict, note: String) {
        // First, and before the exit code is consulted at all. Exit 1 covers an
        // assertion failure, a device that does not exist and a YAML that does
        // not parse; only the first of those writes a record.
        guard evidence.recordFound, !evidence.commands.isEmpty else {
            let why = evidence.failureReason ?? (evidence.timedOut
                ? "Maestro did not finish within the bound and was terminated"
                : "Maestro exited \(evidence.exitCode) and wrote no per-command record")
            return (.driverFailed,
                    "\(why). The flow never reached the application, so this repeat is not a "
                    + "sample of the app's behaviour and is excluded from the determinism score. "
                    + "An absent device, an unparseable flow and a driver that failed to start all "
                    + "look like this, and all exit 1 exactly as a failed assertion does — the "
                    + "record's absence is what separates them.")
        }

        let failures = evidence.failedCommands

        // A device that went away makes liveness unavailable rather than false.
        // PRO-0048 keeps that distinction and it earns its keep here: it is
        // evidence about the device rather than about the app.
        if !failures.isEmpty, evidence.targetRunningBefore != nil, evidence.targetRunningAfter == nil {
            return (.driverFailed,
                    "A command failed and the process-liveness channel stopped answering, which is "
                    + "what a device going away mid-flow looks like. Attributing this to the "
                    + "application would score the simulator's disappearance as the app's "
                    + "behaviour, so the repeat is excluded from the score.")
        }

        // An app that was running and is not running now outranks everything else,
        // for the reason PRO-0048 gives: reporting a crash as a failed assertion
        // files the most useful finding this lane can make under the least useful
        // heading.
        if !failures.isEmpty,
           evidence.targetRunningBefore == true, evidence.targetRunningAfter == false {
            return (.appGone,
                    "The app under test was running before the flow and is not running after it. "
                    + "The app went away while the flow was executing, which a failed assertion "
                    + "alone would have reported as an ordinary flow failure.")
        }

        if !failures.isEmpty {
            // Every failure is the harness's own: the app was never put in a
            // position to misbehave.
            if failures.allSatisfy(\.isHarnessCommand) {
                let names = failures.map(\.type).joined(separator: ", ")
                return (.driverFailed,
                        "The only failing command was the harness's own (\(names)). A launch that "
                        + "did not happen or a script that did not run is a precondition failing, "
                        + "not the application under test misbehaving, so this repeat is excluded "
                        + "from the determinism score rather than counted against the app.")
            }
            let first = failures.first!
            return (.flowFailed,
                    "Maestro reported \(first.type) at sequence \(first.sequenceNumber) as FAILED"
                    + (first.errorMessage.map { ": \($0)" } ?? "") + ". Proctor did not run this "
                    + "command and has no independent observation of it: a command that failed "
                    + "because the app did not show what it should and one that failed because the "
                    + "driver's hit test missed or its hierarchy dump timed out are "
                    + "indistinguishable here. The command's duration is reported beside it, and "
                    + "is characteristic rather than discriminating.")
        }

        return (.flowPassed,
                "Every command Maestro executed reported COMPLETED. This says the driver executed "
                + "the sequence and reported success; it does not say Proctor observed the "
                + "application reach any particular state, because Proctor did not run these steps "
                + "and the only observer of them is Maestro itself.")
    }
}

// MARK: - Scanning a flow for what it declares

/// What a flow file declares, and what it hides.
///
/// The gate has to judge the apps a run will drive. `proctor_ios` action `open`
/// judges the app the **device** resolves the URL to, never a name the caller
/// supplied, because gating on a caller-supplied name lets a caller allow-list
/// one app and drive another. A Maestro flow cannot offer that: which app it
/// drives is declared in a file, and a file is caller content. So the claim this
/// makes is deliberately weaker, and every field name says `declared`.
public struct MaestroDeclaration: Sendable, Equatable {
    /// Every reverse-DNS-shaped token found anywhere in the scanned files.
    public var declaredApps: Set<String>
    /// URLs an `openLink` will hand to the device. These are gated on what the
    /// **device** resolves them to, not on the file, because that is the exact
    /// substitution PRO-0048 closed.
    public var openLinks: [String]
    /// Flow files pulled in, already resolved and scanned.
    public var includes: [String]
    public var unresolved: [MaestroUnresolved]

    public init(declaredApps: Set<String> = [], openLinks: [String] = [],
                includes: [String] = [], unresolved: [MaestroUnresolved] = []) {
        self.declaredApps = declaredApps; self.openLinks = openLinks
        self.includes = includes; self.unresolved = unresolved
    }
}

/// Something the scan could not resolve, in two classes because they are not the
/// same risk.
public struct MaestroUnresolved: Sendable, Equatable, Codable {
    public enum Kind: String, Sendable, Codable {
        /// Proctor cannot tell which app this drives.
        case opaqueTarget
        /// The flow can execute JavaScript, which reaches the network. That is an
        /// egress capability, and the app allow list does not govern it at all —
        /// so it is never reported to a reader as "could not resolve an app id".
        case capability
    }
    public var kind: Kind
    public var construct: String
    public var detail: String

    public init(kind: Kind, construct: String, detail: String) {
        self.kind = kind; self.construct = construct; self.detail = detail
    }
}

/// The conservative textual scan.
///
/// **Not a Maestro parser, and it says so.** The package has no YAML dependency,
/// and reimplementing Maestro's command language would go stale the first time
/// Maestro shipped a command. Two rules keep that honest:
///
/// 1. **Over-detect rather than enumerate.** Out-of-family review broke an
///    enumeration of app-id-bearing keys immediately — `onFlowStart`, `stopApp`,
///    `killApp`, `clearState`, `setPermission` — so the scan collects every
///    reverse-DNS-shaped token instead. An extra app id can only cause a refusal;
///    it can never authorise one. That asymmetry is what makes over-detection the
///    safe direction.
/// 2. **Where a YAML construct structurally defeats a textual scan, say so rather
///    than guess.** An anchor, an alias, a merge key or a block scalar is reported
///    as unresolved, which turns an under-detection into an over-refusal.
public enum MaestroFlowScan {

    /// Constructs whose presence means the file's text is not the whole story.
    static let defeatingSyntax: [(marker: String, name: String, detail: String)] = [
        ("<<:", "YAML merge key",
         "a merge key pulls keys in from another mapping, so what this file drives is not "
         + "determined by its own text"),
        ("&", "YAML anchor",
         "an anchor defines content that an alias elsewhere substitutes in, which a textual scan "
         + "cannot follow"),
        ("*", "YAML alias",
         "an alias substitutes content defined elsewhere in the document, which a textual scan "
         + "cannot follow")
    ]

    /// A single file's declarations, before includes are followed.
    public static func scan(text: String, source: String) -> MaestroDeclaration {
        var declaration = MaestroDeclaration()
        var sawBlockScalar = false

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            // Comments are stripped before anything else. A commented-out
            // construct does not execute, and leaving it in would add app ids
            // that are never driven — harmless for the gate, but noise in a
            // refusal a person has to act on.
            let line = String(stripComment(String(rawLine)))
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }

            for token in bundleIdTokens(in: line) { declaration.declaredApps.insert(token) }

            if let url = value(ofKey: "openLink", in: line) {
                if url.contains("${") {
                    declaration.unresolved.append(MaestroUnresolved(
                        kind: .opaqueTarget, construct: "openLink",
                        detail: "\(source): an openLink URL built by interpolation cannot be "
                              + "resolved to the app the device would hand it to."))
                } else {
                    declaration.openLinks.append(url)
                }
            }

            if let target = value(ofKey: "runFlow", in: line), !target.isEmpty {
                declaration.includes.append(target)
            }
            if let target = value(ofKey: "file", in: line), target.hasSuffix(".yaml")
                || target.hasSuffix(".yml") {
                declaration.includes.append(target)
            }

            for key in ["runScript", "evalScript"] where value(ofKey: key, in: line) != nil {
                declaration.unresolved.append(MaestroUnresolved(
                    kind: .capability, construct: key,
                    detail: "\(source): \(key) executes JavaScript, which reaches the network. "
                          + "An application allow list does not govern egress, so this is reported "
                          + "as a capability the flow carries rather than as an app it drives."))
            }

            // An interpolated value anywhere an app id could live.
            if line.contains("${"), containsAppKey(line) {
                declaration.unresolved.append(MaestroUnresolved(
                    kind: .opaqueTarget, construct: "interpolated app id",
                    detail: "\(source): an app id built by interpolation is substituted at run "
                          + "time, so the file's text does not say which app runs."))
            }

            if isBlockScalarIntroducer(line) { sawBlockScalar = true }

            for syntax in defeatingSyntax where containsDefeatingMarker(line, marker: syntax.marker) {
                declaration.unresolved.append(MaestroUnresolved(
                    kind: .opaqueTarget, construct: syntax.name,
                    detail: "\(source): \(syntax.detail)."))
            }
        }

        if sawBlockScalar {
            declaration.unresolved.append(MaestroUnresolved(
                kind: .opaqueTarget, construct: "YAML block scalar",
                detail: "\(source): a block scalar carries multi-line content a line-oriented scan "
                      + "cannot attribute to a key."))
        }
        return declaration
    }

    /// Follow `runFlow` includes and the adjacent workspace config, bounded.
    ///
    /// `config.yaml` beside the flow is scanned because **Maestro reads it
    /// implicitly** when `--config` is not passed, so content outside the named
    /// file steers the run. A scan that stopped at the named file would report a
    /// declaration the run does not obey.
    ///
    /// `read` returns nil for anything it cannot or may not read — an unreadable
    /// include becomes an unresolved target rather than an error, because one
    /// missing include must not make the whole gate throw.
    public static func resolve(rootPath: String, rootText: String,
                               siblingConfig: String? = nil,
                               maxDepth: Int = 5,
                               read: (String) -> (path: String, text: String)?) -> MaestroDeclaration {
        var combined = scan(text: rootText, source: (rootPath as NSString).lastPathComponent)
        if let siblingConfig {
            let config = scan(text: siblingConfig, source: "config.yaml")
            merge(config, into: &combined, keepIncludes: false)
        }

        var visited: Set<String> = [rootPath]
        var frontier = combined.includes.map { (target: $0, depth: 1) }
        combined.includes = []

        while let next = frontier.popLast() {
            guard next.depth <= maxDepth else {
                combined.unresolved.append(MaestroUnresolved(
                    kind: .opaqueTarget, construct: "runFlow",
                    detail: "\(next.target): include nesting went deeper than \(maxDepth) levels "
                          + "and was not followed."))
                continue
            }
            guard let loaded = read(next.target) else {
                combined.unresolved.append(MaestroUnresolved(
                    kind: .opaqueTarget, construct: "runFlow",
                    detail: "\(next.target): this flow pulls in a file Proctor could not read, so "
                          + "what that file drives is unknown."))
                continue
            }
            guard !visited.contains(loaded.path) else { continue }
            visited.insert(loaded.path)
            combined.includes.append(loaded.path)
            var child = scan(text: loaded.text,
                             source: (loaded.path as NSString).lastPathComponent)
            for target in child.includes { frontier.append((target, next.depth + 1)) }
            child.includes = []
            merge(child, into: &combined, keepIncludes: false)
        }
        return combined
    }

    private static func merge(_ source: MaestroDeclaration, into target: inout MaestroDeclaration,
                              keepIncludes: Bool) {
        target.declaredApps.formUnion(source.declaredApps)
        target.openLinks.append(contentsOf: source.openLinks)
        target.unresolved.append(contentsOf: source.unresolved)
        if keepIncludes { target.includes.append(contentsOf: source.includes) }
    }

    // MARK: - Line-level helpers

    /// Everything before an unquoted `#`.
    static func stripComment(_ line: String) -> Substring {
        var inSingle = false, inDouble = false
        for (index, character) in zip(line.indices, line) {
            switch character {
            case "'" where !inDouble: inSingle.toggle()
            case "\"" where !inSingle: inDouble.toggle()
            case "#" where !inSingle && !inDouble: return line[line.startIndex..<index]
            default: continue
            }
        }
        return line[...]
    }

    /// Reverse-DNS-shaped tokens: at least three dot-separated segments, each
    /// starting with a letter. Deliberately broad — see the type's note on why
    /// over-detection is the safe direction.
    static func bundleIdTokens(in line: String) -> [String] {
        let separators = CharacterSet(charactersIn: " \t\"'`,[]{}()<>:=|")
        return line.components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".;")) }
            .filter(isBundleIdShaped)
    }

    static func isBundleIdShaped(_ token: String) -> Bool {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 3 else { return false }
        // A file name is not a bundle id, and neither is a version number.
        let fileish: Set<String> = ["yaml", "yml", "json", "js", "png", "jpg", "txt", "md"]
        if let last = parts.last, fileish.contains(String(last).lowercased()) { return false }
        return parts.allSatisfy { part in
            guard let first = part.first, first.isLetter else { return false }
            return part.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        }
    }

    /// The scalar value of `key:` on this line, whether written bare, quoted, or
    /// as the sole child of a list item. Nil when the key is not on the line.
    ///
    /// Tolerates a space before the colon, which YAML permits and a naive
    /// `contains("key:")` misses.
    static func value(ofKey key: String, in line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let body = trimmed.hasPrefix("- ") ? String(trimmed.dropFirst(2)) : trimmed
        for candidate in [key + ":", key + " :"] where body.hasPrefix(candidate) {
            let raw = String(body.dropFirst(candidate.count))
                .trimmingCharacters(in: .whitespaces)
            return unquote(raw)
        }
        return nil
    }

    static func containsAppKey(_ line: String) -> Bool {
        let lowered = line.lowercased()
        return lowered.contains("appid") || lowered.contains("launchapp")
            || lowered.contains("bundleid")
    }

    static func unquote(_ text: String) -> String {
        var out = text
        for quote in ["\"", "'"] where out.hasPrefix(quote) && out.hasSuffix(quote) && out.count >= 2 {
            out = String(out.dropFirst().dropLast())
        }
        return out
    }

    /// `key: |` or `key: >`, with or without a chomping indicator.
    static func isBlockScalarIntroducer(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let colon = trimmed.lastIndex(of: ":") else { return false }
        let tail = trimmed[trimmed.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        guard let first = tail.first, first == "|" || first == ">" else { return false }
        return tail.dropFirst().allSatisfy { $0 == "-" || $0 == "+" || $0.isNumber }
    }

    /// Whether a defeating YAML marker appears where it would be syntax rather
    /// than ordinary text. An anchor or alias sits at the start of a value; a `*`
    /// inside a quoted string or a glob is not one.
    static func containsDefeatingMarker(_ line: String, marker: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if marker == "<<:" { return trimmed.hasPrefix("<<:") || trimmed.contains(" <<:") }
        guard let colon = trimmed.firstIndex(of: ":") else {
            // A bare list item can carry an alias: `- *shared`.
            let body = trimmed.hasPrefix("- ") ? String(trimmed.dropFirst(2)) : trimmed
            return body.hasPrefix(marker) && body.count > marker.count
        }
        let tail = trimmed[trimmed.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        return tail.hasPrefix(marker) && tail.count > marker.count
    }
}

// MARK: - The gate

public enum MaestroGate {

    /// Whether any application policy is in force at all.
    ///
    /// The rule keys on this rather than on the allow list alone, and the
    /// difference is a real hole out-of-family review found: a **block** list with
    /// no allow list is a policy in force, and an unresolvable construct sailing
    /// past it would defeat the block. The sensitive set is included for the same
    /// reason — an unresolvable target could be the sensitive app.
    ///
    /// A completely empty policy runs the flow and reports the construct, which
    /// keeps the inert-until-configured convention `AppPolicy` and `FSJail` both
    /// already follow. Refusing unconditionally was considered and rejected: it
    /// would be stricter than every other path in this codebase on a default
    /// install, in a posture where everything is already permitted.
    public static func policyInForce(_ policy: AppPolicy) -> Bool {
        !policy.allow.isEmpty || !policy.block.isEmpty || !policy.sensitive.isEmpty
    }

    /// The decision for one flow.
    ///
    /// `resolvedOpenLinks` is what the **device** said each `openLink` URL
    /// resolves to, supplied by the caller because resolution needs the device.
    /// A nil entry is an unresolvable link and is treated as an opaque target,
    /// exactly as `IOSPolicy` treats a universal link.
    public static func decide(declaration: MaestroDeclaration,
                              resolvedOpenLinks: [String?],
                              policy: AppPolicy,
                              hasValidToken: (String) -> Bool) -> PolicyDecision {
        // Unresolvable first: refusing on an app id while an unscannable
        // construct sits in the same file would be answering the easy half.
        if policyInForce(policy), let blocker = declaration.unresolved.first {
            return .blocked(reason:
                "This flow carries a \(blocker.construct) that Proctor cannot resolve, and an "
                + "application policy is in force, so it is refused rather than run. "
                + blocker.detail
                + " Proctor's claim over a Maestro flow covers what the flow declares; a construct "
                + "it cannot read is outside that claim.")
        }

        // Every declared app, plus every app the device resolved an openLink to.
        var targets = Array(declaration.declaredApps).sorted()
        for resolved in resolvedOpenLinks {
            guard let resolved else {
                if !policy.allow.isEmpty {
                    return .blocked(reason:
                        "An allow list is in force and this flow opens a link that could not be "
                        + "resolved to an app on the device; actuation is refused. A universal link "
                        + "is routed through associated domains rather than a scheme claim, so "
                        + "which app receives it is not knowable here.")
                }
                continue
            }
            targets.append(resolved)
        }

        for target in targets {
            let decision = IOSPolicy.decide(handler: target, policy: policy,
                                            hasValidToken: hasValidToken(target))
            if decision.refusal != nil { return decision }
        }
        return .allow
    }
}

// MARK: - The invocation

public enum MaestroInvocation {

    /// The lane's name, carried on every result and every report. PRO-0051
    /// settled that a lane is deliberately selected and that every run record
    /// names the one that ran; this lane is selected by calling this action, with
    /// no automatic routing into it and no fallback out of it.
    public static let lane = "maestro"

    /// The argument vector, in one place so a test can assert what is and is not
    /// in it.
    ///
    /// `--flatten-debug-output` because the measured default nests artefacts
    /// under `.maestro/tests/<timestamp>/`, and one failing invocation left two
    /// such directories where only the second held a record.
    ///
    /// **`--analyze` is never passed.** It is Maestro's cloud AI feature and would
    /// send the run somewhere; a test asserts its absence.
    public static func arguments(flowPath: String, udid: String,
                                 debugDirectory: String) -> [String] {
        ["--device", udid,
         "test", flowPath,
         "--debug-output", debugDirectory,
         "--flatten-debug-output",
         "--no-ansi"]
    }

    /// What a caller is told when Maestro is not on the machine.
    ///
    /// PRO-0023's rule: Proctor detects and explains, it never installs, and a
    /// tool result carries no command text for a model to paste into a shell.
    public static let absence = (
        missing: "Maestro is not installed on this machine, so there is no flow lane here.",
        askThePerson: "Ask the person whose machine this is to install it. proctor_doctor carries a "
                    + "\"maestro\" toolchain row saying what was searched, and the iOS lane's note "
                    + "says the deep-link actions work without it.",
        docs: MaestroTool.docs
    )

    /// The environment Proctor gives its own Maestro subprocess.
    ///
    /// **Measured 2026-08-25, and the reason this exists.** `maestro --version`
    /// — an invocation that prints a string and does nothing else — opens TWO
    /// outbound TLS connections before returning: one to a Google Cloud address
    /// and one to an AWS one. With `MAESTRO_CLI_NO_ANALYTICS=1` the AWS
    /// connection does not happen and the Google Cloud one still does.
    ///
    /// So the lane is not network-isolated by default and cannot be made fully
    /// isolated from here. What Proctor can do is stop the half it controls, and
    /// say plainly that the other half remains.
    ///
    /// This is an environment variable on Proctor's OWN subprocess, not a change
    /// to `~/.maestro/analytics.json`. That file is the operator's configuration
    /// and silently rewriting third-party config is the overreach PRO-0023 rules
    /// out; setting a variable for a process Proctor is about to launch is not.
    public static let environment = ["MAESTRO_CLI_NO_ANALYTICS": "1"]

    /// Disclosed once per result, with the measurement behind it.
    ///
    /// The previous wording said telemetry runs "when it is enabled in its
    /// configuration", which is true and understates it: the traffic was
    /// measured on the most trivial invocation there is, before any flow runs,
    /// and one connection persists whatever the analytics setting says.
    public static let telemetryNote =
        "Maestro reaches the network when it is invoked, and this lane is not network-isolated. "
        + "Measured on `maestro --version`, an invocation that runs no flow: two outbound TLS "
        + "connections, one to a Google Cloud address and one to AWS. Proctor sets "
        + "MAESTRO_CLI_NO_ANALYTICS=1 on its own subprocess, which stops the AWS one; the other "
        + "still happens. Proctor does not touch ~/.maestro/analytics.json — that file belongs to "
        + "whoever set it up — so a flow run in a sensitive context should know what remains."
}
