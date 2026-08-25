import Foundation
import ProctorCore

// proctor_ios action "flow": run a Maestro flow file against a targeted
// simulator, N times, and score the repeats. The impure half — this file runs the
// binary, reads the debug directory, takes Proctor's own device samples, and
// wires the gate, the busy guard and the audit trail. Every decision it makes is
// in ProctorCore/MaestroRun.swift.
//
// Three properties of this action differ from every other one on this tool, and
// each is deliberate:
//
// **The unit is the file.** Nothing here translates a Maestro command into an
// ActionStep or executes one command at a time. PRO-0020 settled that for browser
// tools: a tool driving its own engine is not driving the window Proctor is
// attached to, so a routed step would report success against something Proctor
// never touched.
//
// **The busy guard is held for the whole sweep, not per repeat.** A determinism
// measurement whose repeats can be interleaved with another call driving the same
// device is measuring the interleaving. `proctor_stability` takes its lanes once
// for the same reason.
//
// **A repeat that failed in the driver is dropped rather than scored.** It is not
// a sample of the application, and folding it in would score the driver's
// reliability as the app's non-determinism.

extension Session {

    // MARK: - Entry point

    func maestroFlow(path: String, device: String?, runs requestedRuns: Int,
                     pixelEvidence: Bool, timeoutMs: Int) async throws -> JSONValue {
        // 1. Is there a lane at all. Consumes PRO-0050's toolchain row rather
        //    than probing a second time, and never runs `maestro --version`,
        //    which measured 4.67 s of JVM start.
        let presence = tools.maestro.presence()
        guard presence.available, let binary = presence.path else {
            throw AgentError(
                code: .notImplemented,
                message: MaestroInvocation.absence.missing,
                remedy: MaestroInvocation.absence.askThePerson,
                detail: .object([
                    "searched": .array(presence.searched.map(JSONValue.string)),
                    "docs": .string(MaestroInvocation.absence.docs)
                ]))
        }

        // 2. The flow path is caller-supplied, so it passes the same jail every
        //    other caller path does.
        try enforceFSJail(path: path)
        let flowPath = (path as NSString).expandingTildeInPath
        guard let flowText = try? String(contentsOfFile: flowPath, encoding: .utf8) else {
            throw AgentError(
                code: .invalidArguments,
                message: "no readable flow file at \(flowPath.debugDescription)",
                remedy: "Pass an absolute path to a .maestro or .yaml flow file.")
        }

        let simctl = try simctlPath()
        let devices = try readDevices(simctl: simctl)
        let target = try resolveDevice(device, in: devices)
        guard target.isBooted else {
            throw AgentError(
                code: .actionFailed,
                message: "\(target.name) is \(target.state); a flow needs a booted device",
                remedy: "Boot it with proctor_ios action \"boot\", or name a device that is already "
                      + "booted. proctor_ios never boots a device as a side effect.")
        }

        // 3. What does this flow declare, and what can it not be read to declare.
        let declaration = MaestroFlowScan.resolve(
            rootPath: flowPath, rootText: flowText,
            siblingConfig: Session.adjacentConfig(of: flowPath),
            read: { [flowPath] target in Session.readInclude(target, relativeTo: flowPath) })

        // An openLink is gated on what the DEVICE resolves it to, never on
        // anything the file says — the same rule action "open" follows, for the
        // same reason: a flow could otherwise declare one app and open a link
        // belonging to another.
        let map = (try? schemeMap(simctl: simctl, udid: target.udid)) ?? [:]
        let resolvedLinks = declaration.openLinks.map { SchemeMap.handler(for: $0, in: map) }

        let auditTool = AuditTool.maestroFlow
        let declaredList = Array(declaration.declaredApps).sorted()
        let auditBundle = declaredList.first.map(IOSPolicy.key(for:))

        loadPolicyIfNeeded()
        // Token validity is read here, inside the actor, and handed to the gate
        // as data. The gate stays pure and synchronous, and the alternative — a
        // closure reaching back into the actor — is not expressible under strict
        // concurrency anyway.
        var tokenValid: [String: Bool] = [:]
        for candidate in declaration.declaredApps.union(resolvedLinks.compactMap { $0 }) {
            tokenValid[candidate] = approvalTokenIsValid(for: candidate)
        }
        let decision = MaestroGate.decide(declaration: declaration,
                                          resolvedOpenLinks: resolvedLinks,
                                          policy: policy,
                                          hasValidToken: { tokenValid[$0] ?? false })
        // The trail attests to the bytes that ran, not to a name: `script` is the
        // existing length-plus-hash redaction, so a flow edited between two runs
        // shows as two hashes rather than one filename. The declared ids are in
        // the clear, marked `declared` — Proctor's claim here is over what the
        // flow declares, and the word says so.
        let declaredClear = "declared " + (declaredList.isEmpty ? "no app"
                                                                : declaredList.joined(separator: ", "))
        if let refusal = decision.refusal {
            auditSink(AuditRecord(timestamp: clock(), tool: auditTool, bundleId: auditBundle,
                                  kind: "flow", outcome: AuditRecord.Outcome.refused,
                                  script: Redaction(of: flowText),
                                  reason: flowPath + " · " + declaredClear + " · " + refusal.reason))
            throw AgentError(code: .policyDenied, message: refusal.reason, remedy: refusal.remedy)
        }

        // 4. One flow sweep per device at a time, held across every repeat. No
        //    RunQueue lane is taken, for PRO-0048's reason: nothing here posts an
        //    event into the Mac's input system or raises a window, so blocking a
        //    Mac run would be contention that does not exist.
        guard !iosBusyDevices.contains(target.udid) else {
            throw AgentError(
                code: .queueBusy,
                message: "another proctor_ios call is already driving \(target.name)",
                remedy: "Wait for it to finish. A second call interleaved with a determinism sweep "
                      + "would make every repeat's evidence belong to whichever call was running.")
        }
        iosBusyDevices.insert(target.udid)
        defer { iosBusyDevices.remove(target.udid) }

        return try await runSweep(binary: binary, simctl: simctl, target: target,
                                  flowPath: flowPath, flowText: flowText,
                                  declaration: declaration, declaredClear: declaredClear,
                                  auditTool: auditTool, auditBundle: auditBundle,
                                  requestedRuns: max(requestedRuns, 1),
                                  pixelEvidence: pixelEvidence, timeoutMs: timeoutMs)
    }

    // MARK: - The sweep

    private func runSweep(binary: String, simctl: String, target: IOSDevice,
                          flowPath: String, flowText: String,
                          declaration: MaestroDeclaration, declaredClear: String,
                          auditTool: String, auditBundle: String?,
                          requestedRuns: Int, pixelEvidence: Bool,
                          timeoutMs: Int) async throws -> JSONValue {
        // The liveness channel needs a bundle id. With several declared, the
        // sorted first is used and named in the result rather than guessed at
        // silently — a flow driving two apps has no single "app under test".
        let livenessTarget = Array(declaration.declaredApps).sorted().first

        var perRun: [[String]] = []
        var verdicts: [(verdict: MaestroVerdict, note: String, commands: [MaestroCommand])] = []
        var notes: [String] = []
        var endFrames: [String] = []
        var lastCommands: [MaestroCommand] = []
        var durationsBySequence: [Int: [Int]] = [:]
        var excluded = 0

        for runIndex in 0..<requestedRuns {
            let before = livenessTarget.map {
                Session.appLiveness(simctl: simctl, udid: target.udid, bundleId: $0)
            } ?? (running: nil, pid: nil)
            let beforeFrame = pixelEvidence
                ? Session.captureFrame(simctl: simctl, udid: target.udid, label: "flow-before")
                : nil

            let debugDirectory = Session.maestroDebugDirectory(run: runIndex)
            let arguments = MaestroInvocation.arguments(flowPath: flowPath, udid: target.udid,
                                                        debugDirectory: debugDirectory)
            let run = Session.runBounded(binary, arguments, timeoutMs: timeoutMs,
                                         environment: MaestroInvocation.environment)

            let record = Session.readMaestroRecord(in: debugDirectory)
            let after = livenessTarget.map {
                Session.appLiveness(simctl: simctl, udid: target.udid, bundleId: $0)
            } ?? (running: nil, pid: nil)
            let afterFrame = pixelEvidence
                ? Session.captureFrame(simctl: simctl, udid: target.udid, label: "flow-after")
                : nil
            if let afterFrame { endFrames.append(afterFrame) }

            let evidence = MaestroEvidence(
                exitCode: run.exitCode, timedOut: run.timedOut,
                recordFound: record.commands != nil,
                commands: record.commands ?? [],
                targetRunningBefore: livenessTarget == nil ? nil : before.running,
                targetRunningAfter: livenessTarget == nil ? nil : after.running,
                failureReason: record.failureReason)
            let outcome = MaestroVerdict.decide(evidence)
            verdicts.append((outcome.verdict, outcome.note, evidence.commands))

            auditSink(AuditRecord(
                timestamp: clock(), tool: runIndex == 0 ? auditTool : AuditTool.maestroRepeat,
                bundleId: auditBundle, kind: "flow",
                outcome: outcome.verdict == .flowPassed ? AuditRecord.Outcome.ok
                                                        : AuditRecord.Outcome.failed,
                script: Redaction(of: flowText),
                reason: flowPath + " · " + declaredClear + " · " + outcome.verdict.rawValue))

            if outcome.verdict.isScoreable {
                perRun.append(MaestroScore.vector(for: evidence.commands))
                lastCommands = evidence.commands
                for command in evidence.commands {
                    durationsBySequence[command.sequenceNumber, default: []].append(command.durationMs)
                }
            } else {
                excluded += 1
                notes.append("Run \(runIndex) ended as \(outcome.verdict.rawValue) and was excluded "
                           + "from the score: \(outcome.note)")
            }
            _ = beforeFrame
        }

        // A repeat that never sampled the app is not a sample of the app, so the
        // sweep is truncated rather than scored on fewer repeats without saying
        // so — the shape proctor_stability already uses when permission is
        // withdrawn between repeats.
        let truncated = excluded > 0
        if truncated {
            notes.append(
                "\(excluded) of \(requestedRuns) repeats failed in the driver rather than in the "
                + "application and were excluded. Two things follow and both are stated rather than "
                + "left to be worked out: the surviving instability figures are computed over the "
                + "repeats that got far enough to be compared, which makes them an optimistic bound; "
                + "and this sweep is never reported deterministic, so driver flake can deny the "
                + "label to an application that was in fact stable.")
        }

        let stepCount = perRun.map(\.count).max() ?? 0
        if perRun.map(\.count).contains(where: { $0 != stepCount }) {
            notes.append(
                "The repeats executed different numbers of commands, which is what a conditional "
                + "flow taking a different branch looks like. firstDivergence names where they first "
                + "differed; every position after it is an artefact of the length change rather than "
                + "an independent divergence.")
        }
        if perRun.count < 2 {
            notes.append("A single scored repeat cannot measure divergence; firstDivergence is null "
                       + "and the run is not reported deterministic because nothing was compared.")
        }

        let score = StabilityScore.fold(perRun: perRun, stepCount: stepCount, runs: perRun.count)
        for (index, samples) in score.undersampled.sorted(by: { $0.key < $1.key }) {
            notes.append("Command position \(index) was measured on \(samples) of \(perRun.count) "
                       + "scored repeats.")
        }
        notes.append(
            "Comparison is over Maestro's own per-command status vector: for each command, its type, "
            + "its parameters and whether it completed. Durations are reported beside the score and "
            + "never folded into it — one unchanged command measured 634, 91, 88, 96 and 91 ms "
            + "across five repeats, so hashing a duration reports every stable flow as unstable.")
        notes.append(
            "This lane has one observer of the steps, and it is Maestro. Proctor did not run these "
            + "commands and holds no independent observation of any of them; the process-liveness "
            + "and device-frame channels bound the run rather than its individual commands.")
        if Session.maestroTelemetryEnabled() { notes.append(MaestroInvocation.telemetryNote) }

        return try Self.maestroReport(
            flowPath: flowPath, flowText: flowText, target: target,
            verdicts: verdicts, lastCommands: lastCommands,
            durations: durationsBySequence, score: score, scoredRuns: perRun.count,
            requestedRuns: requestedRuns, stepCount: stepCount, truncated: truncated,
            declaration: declaration, livenessTarget: livenessTarget,
            endFrames: endFrames, pixelEvidence: pixelEvidence, notes: notes)
    }

    // MARK: - The report

    private static func maestroReport(
        flowPath: String, flowText: String, target: IOSDevice,
        verdicts: [(verdict: MaestroVerdict, note: String, commands: [MaestroCommand])],
        lastCommands: [MaestroCommand], durations: [Int: [Int]],
        score: StabilityScore.Fold, scoredRuns: Int, requestedRuns: Int, stepCount: Int,
        truncated: Bool, declaration: MaestroDeclaration, livenessTarget: String?,
        endFrames: [String], pixelEvidence: Bool, notes: [String]) throws -> JSONValue {

        let headline = verdicts.last?.verdict ?? .driverFailed
        var out: [String: JSONValue] = [
            // PRO-0051: a score is unreadable without the path that produced it.
            "lane": .string(MaestroInvocation.lane),
            "flowPath": .string(flowPath),
            "flowHash": .string(Redaction(of: flowText).sha256),
            "device": try JSONValue.encode(target),
            "verdict": .string(headline.rawValue),
            "verdictNote": .string(verdicts.last?.note ?? ""),
            "attributed": .bool(headline.isAttributed),
            "runs": .number(Double(scoredRuns)),
            "requestedRuns": .number(Double(requestedRuns)),
            "truncated": .bool(truncated),
            "perRunVerdicts": .array(verdicts.map { .string($0.verdict.rawValue) }),
            "commands": .array(lastCommands.map { command in
                .object([
                    "sequenceNumber": .number(Double(command.sequenceNumber)),
                    "type": .string(command.type),
                    "status": .string(command.status),
                    // Maestro prepends two commands that are in no flow file, so
                    // a sequence number is not a line in the caller's YAML.
                    "injected": .bool(command.isInjected),
                    "durationMs": .number(Double(command.durationMs)),
                    "error": command.errorMessage.map(JSONValue.string) ?? .null,
                    "hierarchyAttached": .bool(command.hasHierarchy)
                ])
            }),
            "durations": .object(Dictionary(uniqueKeysWithValues:
                durations.map { (String($0.key), summarise($0.value)) })),
            "score": .object([
                "firstDivergence": score.firstDivergence.map { JSONValue.number(Double($0)) } ?? .null,
                // Stated rather than inferred: this is repeat-versus-repeat, and
                // the position is a Maestro sequence number. It is NOT the
                // replay-versus-recording comparison proctor_flow performs —
                // Proctor did not run these steps and holds no recording of them.
                "divergenceBasis": .string("repeats"),
                "divergenceIndexIs": .string("maestro sequenceNumber"),
                "stepInstability": .array(score.stepInstability.map { .number($0) }),
                "deterministic": .bool(score.deterministic && !truncated),
                "commandCount": .number(Double(stepCount)),
                "divergenceDetail": score.divergenceDetail.isEmpty ? .null
                    : .object(score.divergenceDetail.mapValues { .array($0.map(JSONValue.string)) })
            ]),
            "declaredApps": .array(Array(declaration.declaredApps).sorted().map(JSONValue.string)),
            "declaredNote": .string(
                "These are the applications the flow file DECLARES, not the ones a device resolved. "
                + "A Maestro flow can in principle reach an app it does not declare, so this is a "
                + "weaker claim than the one action \"open\" makes, and it is named for what it is."),
            "notes": .array(notes.map(JSONValue.string))
        ]
        if let livenessTarget {
            out["appUnderTest"] = .string(livenessTarget)
        }
        if !declaration.unresolved.isEmpty {
            out["unresolvedConstructs"] = .array(declaration.unresolved.compactMap {
                try? JSONValue.encode($0)
            })
        }
        if !declaration.includes.isEmpty {
            out["includedFlows"] = .array(declaration.includes.map(JSONValue.string))
        }
        if pixelEvidence, !endFrames.isEmpty {
            out["endStateAgreement"] = endStateAgreement(frames: endFrames)
            out["frameCaveat"] = .string(Session.deviceFrameCaveat)
        }
        return .object(out)
    }

    /// Whether every repeat left the device looking the same.
    ///
    /// **Evidence, and deliberately not a score input.** A device frame carries no
    /// SCFrameStatus, so its freshness cannot be established; letting an
    /// unconfirmable frame decide a field named `deterministic` would be exactly
    /// the blending PRO-0048 refused. Reported beside the score so a caller can
    /// see when the two disagree — "every command completed identically" and "the
    /// device did not end up in the same place" is one of the more interesting
    /// things this lane can produce.
    private static func endStateAgreement(frames: [String]) -> JSONValue {
        guard frames.count >= 2, let first = frames.first else {
            return .object([
                "agreed": .null,
                "note": .string("Fewer than two repeats produced a device frame, so there was "
                              + "nothing to compare.")
            ])
        }
        var fractions: [Double] = []
        for frame in frames.dropFirst() {
            let compared = Session.compareDeviceFrames(first, frame)
            if let changed = compared.changedFraction { fractions.append(changed) }
        }
        let agreed: JSONValue = fractions.isEmpty
            ? .null
            : .bool(fractions.allSatisfy { $0 < IOSPixel.changeThreshold })
        return .object([
            "agreed": agreed,
            "changedFractions": .array(fractions.map { .number($0) }),
            "threshold": .number(IOSPixel.changeThreshold),
            "note": .string(
                "Proctor's own comparison of the device screen at the end of each repeat, against "
                + "the first. Evidence beside the determinism score and never folded into it: a "
                + "device frame carries no ScreenCaptureKit frame status, so an unconfirmable frame "
                + "must not decide a verdict named deterministic.")
        ])
    }

    private static func summarise(_ values: [Int]) -> JSONValue {
        guard !values.isEmpty else { return .null }
        let sorted = values.sorted()
        return .object([
            "minMs": .number(Double(sorted.first ?? 0)),
            "medianMs": .number(Double(sorted[sorted.count / 2])),
            "maxMs": .number(Double(sorted.last ?? 0)),
            "samples": .number(Double(sorted.count))
        ])
    }
}

// MARK: - Filesystem and process, all static

extension Session {

    /// Maestro reads a `config.yaml` in the flow's workspace implicitly when
    /// `--config` is not passed, so content outside the named file steers the run
    /// and has to be scanned with it.
    static func adjacentConfig(of flowPath: String) -> String? {
        let directory = (flowPath as NSString).deletingLastPathComponent
        for name in ["config.yaml", "config.yml"] {
            let candidate = (directory as NSString).appendingPathComponent(name)
            if let text = try? String(contentsOfFile: candidate, encoding: .utf8) { return text }
        }
        return nil
    }

    /// Read a `runFlow` include, resolved against the including file's directory.
    /// Returns nil for anything unreadable, which the scan turns into an
    /// unresolved target rather than an error: one missing include must not make
    /// the whole gate throw.
    static func readInclude(_ target: String, relativeTo flowPath: String)
        -> (path: String, text: String)? {
        let directory = (flowPath as NSString).deletingLastPathComponent
        let resolved = target.hasPrefix("/")
            ? target
            : (directory as NSString).appendingPathComponent(target)
        let canonical = (resolved as NSString).standardizingPath
        guard let text = try? String(contentsOfFile: canonical, encoding: .utf8) else { return nil }
        return (canonical, text)
    }

    /// The operator's own maestro debug root, always — where a real run's
    /// artefacts land on a real Mac. Truthful in a test process so a test can
    /// name the directory it must not touch.
    static var operatorMaestroDirectory: String {
        NSHomeDirectory()
            + "/Library/Application Support/app.fledgeling.procter/maestro"
    }

    /// The maestro debug root this process uses, and the interlock that keeps a
    /// test process out of the operator's own.
    ///
    /// PRO-0099, REQ-055. `PolicyStore.live`'s interlock applied to the fifth
    /// static computing a path under the operator's Application Support directory
    /// with no seam. `maestroDebugDirectory` below creates its directory
    /// unconditionally on every call, and `runFlow` calls it once per run, so a
    /// suite that reached a maestro run left a `run-<stamp>-<n>-<salt>` directory
    /// in the operator's own tree — and Maestro then wrote its per-command records
    /// into it.
    static var maestroDebugRoot: String {
        guard AuditLog.isTestProcess else { return operatorMaestroDirectory }
        return testFallbackMaestroRoot
    }

    /// Where an un-pathed maestro run lands in a test process. Named for what it
    /// is, so a stray directory in `/tmp` explains itself.
    static let testFallbackMaestroRoot = (NSTemporaryDirectory() as NSString)
        .appendingPathComponent("proctor-test-maestro-\(ProcessInfo.processInfo.processIdentifier)")

    static func maestroDebugDirectory(run: Int) -> String {
        let base = maestroDebugRoot
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        let salt = String(UInt32.random(in: 0..<0xFFFF), radix: 16)
        let directory = "\(base)/run-\(stamp)-\(run)-\(salt)"
        try? FileManager.default.createDirectory(atPath: directory,
                                                 withIntermediateDirectories: true)
        return directory
    }

    /// Find and parse the per-command record a run left behind.
    ///
    /// Globs rather than constructing a name: the same flow produced
    /// `commands-(settings).json` on one invocation and
    /// `commands-(settings.yaml).json` on others, and one failing run left two
    /// timestamped directories where only the second held a record. A path built
    /// from the flow's name finds nothing on at least one of those shapes.
    ///
    /// `--flatten-debug-output` is passed so the artefacts land directly in the
    /// directory, but the walk is recursive anyway: a Maestro that stops
    /// honouring the flag must not silently turn every run into a driver failure.
    static func readMaestroRecord(in directory: String)
        -> (commands: [MaestroCommand]?, failureReason: String?) {
        let fm = FileManager.default
        var found: [(path: String, modified: Date)] = []
        if let walker = fm.enumerator(atPath: directory) {
            for case let entry as String in walker {
                let full = (directory as NSString).appendingPathComponent(entry)
                guard !MaestroRecord.records(in: [full]).isEmpty else { continue }
                let modified = (try? fm.attributesOfItem(atPath: full)[.modificationDate] as? Date)
                    ?? nil
                found.append((full, modified ?? Date.distantPast))
            }
        }
        guard let newest = found.sorted(by: { $0.modified > $1.modified }).first else {
            return (nil, "Maestro wrote no per-command record")
        }
        guard let data = fm.contents(atPath: newest.path) else {
            return (nil, "Maestro's per-command record could not be read")
        }
        do {
            return (try MaestroRecord.parse(data), nil)
        } catch {
            return (nil, "Maestro's per-command record could not be parsed")
        }
    }

    /// Whether Maestro's own telemetry is switched on in its configuration.
    ///
    /// Read, never written. The file belongs to whoever set it up, and silently
    /// rewriting third-party configuration is the overreach PRO-0023 rules out;
    /// saying what the invocation carries is the part Proctor owes.
    static func maestroTelemetryEnabled() -> Bool {
        let path = NSHomeDirectory() + "/.maestro/analytics.json"
        guard let data = FileManager.default.contents(atPath: path),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let enabled = object["enabled"] as? Bool
        else { return false }
        return enabled
    }

    static func captureFrame(simctl: String, udid: String, label: String) -> String? {
        guard let path = try? Session.deviceFramePath(udid: udid, label: label),
              Session.captureDeviceScreen(simctl: simctl, udid: udid, path: path,
                                          timeoutMs: 10_000).ok
        else { return nil }
        return path
    }
}
