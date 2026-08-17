import Foundation
import ProctorCore

// Routing and argument decoding. The schemas in ToolCatalogue are the source of
// truth for names and defaults; this file is where they are read.

struct Dispatcher: Sendable {
    let session: Session

    func handle(_ request: AgentRequest) async -> AgentResponse {
        // One choke point for every request, so the recent-activity feed the UI
        // shows is recorded in exactly one place. Health and introspection polls
        // are excluded: the window polls doctor and recent-activity every couple
        // of seconds, and recording those would bury the tools a model drives.
        let track = Self.tracksActivity(request.tool)
        let short = Self.shortName(request.tool)
        if track { await session.activityBegin(tool: short) }
        // The same choke point mints the run identity every audit record written
        // during this call will carry, and the same exclusion applies: a poll is
        // not a run. It is set here rather than in each audited call site because
        // the records of one call are written from several places that do not
        // know about each other — the gate before the run, each step inside it,
        // a lane recommendation beside it — and a task local reaches all of them
        // without any of them having to remember.
        //
        // The retention cap is checked here too, at a run boundary and never
        // between the steps of a batch: a rotation in the middle of a run would
        // discard that run's own first half while the panel was still showing it.
        if track { AuditLog.rotateIfNeeded() }
        return await RunIdentity.$current.withValue(track ? RunIdentity.mint() : nil) {
            await complete(request, track: track, short: short)
        }
    }

    private func complete(_ request: AgentRequest, track: Bool, short: String) async -> AgentResponse {
        do {
            let result = try await route(request)
            if track { await session.activityEnd(tool: short, ok: true) }
            return AgentResponse(id: request.id, ok: true, result: result)
        } catch let error as AgentError {
            if track { await session.activityEnd(tool: short, ok: false) }
            return AgentResponse(id: request.id, ok: false, error: error)
        } catch let error as PixelCompare.Failure {
            if track { await session.activityEnd(tool: short, ok: false) }
            return AgentResponse(id: request.id, ok: false,
                                 error: AgentError(code: .internalError, message: error.reason))
        } catch {
            if track { await session.activityEnd(tool: short, ok: false) }
            return AgentResponse(id: request.id, ok: false,
                                 error: AgentError(code: .internalError,
                                                   message: "\(request.tool) failed: \(error)"))
        }
    }

    /// What counts as activity: the public, model-driven tools, minus the doctor
    /// health poll the UI runs every couple of seconds. Derived from the catalogue
    /// so a new tool is tracked automatically, while the internal verbs (resource,
    /// recent_activity) and any unknown or malformed tool — none of which are in
    /// the catalogue — are excluded without a hand-maintained list.
    private static let trackedTools: Set<String> =
        Set(ToolCatalogue.all.map(\.name)).subtracting(["proctor_doctor"])

    private static func tracksActivity(_ tool: String) -> Bool {
        trackedTools.contains(tool)
    }

    private static func shortName(_ tool: String) -> String {
        tool.hasPrefix("proctor_") ? String(tool.dropFirst("proctor_".count)) : tool
    }

    private func route(_ request: AgentRequest) async throws -> JSONValue {
        let args = Args(tool: request.tool, raw: request.arguments)
        switch request.tool {
        case "proctor_apps":      return try await apps(args)
        case "proctor_snapshot":  return try await snapshot(args)
        case "proctor_find":      return try await find(args)
        case "proctor_act":       return try await act(args)
        case "proctor_capture":   return try await capture(args)
        case "proctor_zoom":      return try await zoom(args)
        case "proctor_wait":      return try await wait(args)
        case "proctor_assert":    return try await assert(args)
        case "proctor_flow":      return try await flow(args)
        case "proctor_stability": return try await stability(args)
        case "proctor_inspect":   return try await inspect(args)
        case "proctor_doctor":    return try await doctor(args)
        case "proctor_unlock":    return try await unlock(args)
        case "proctor_computer":         return try await computer(args)
        case "proctor_openai_computer":  return try await openaiComputer(args)
        case "proctor_menu":      return try await menu(args)
        case "proctor_dictionary":       return try await dictionary(args)
        case "proctor_policy":           return try await policy(args)
        case "proctor_kill":             return try await kill(args)
        case "proctor_ios":              return try await ios(args)
        case "proctor_guest":            return try await guest(args)
        // Internal verb behind the MCP resources surface. Never in ToolCatalogue,
        // so a host cannot reach it as a tool; the shim forwards resources/read to
        // it. It only re-projects state the agent already holds or reads without a
        // TCC grant — no new capability.
        case "proctor_resource":  return try await resource(args)
        // Internal read-only verb the UI polls for the "what is it doing now"
        // feed. Like proctor_resource it is never in ToolCatalogue, so the public
        // tool count is unchanged and no host can reach it as a tool.
        case "proctor_recent_activity":
            return await session.recentActivity(limit: args.int("limit") ?? 12)
        // Internal verbs behind Proctor's own History window: the projection a
        // person reads, and the clear that rotates the trail. Never in
        // ToolCatalogue, so the shim — which gates tools/call on the catalogue —
        // cannot reach either, and no MCP host can read a person's history
        // through this path or shred it.
        //
        // Worth stating plainly, because "not in the catalogue" is easy to
        // over-read: it keeps a model out of *this surface*, not out of the
        // trail. `proctor_policy` action `audit` is a catalogue tool that already
        // opens the trail and returns whole records. This projection is strictly
        // narrower than that one.
        case "proctor_history":
            return await session.history(limit: args.int("limit") ?? 20)
        case "proctor_history_clear":
            return await session.clearHistory()
        // Internal verb behind Proctor's menu bar: the show/hide switch for the
        // run panel and the run's own Pause, Resume and Stop, so hiding the panel
        // never hides the kill switch. Never in ToolCatalogue either, so the shim
        // — which gates tools/call on the catalogue — cannot reach it and no MCP
        // host can put a person's stop button away.
        case "proctor_hud":
            return try await session.hudControl(RunHUDControl.parse(args.string("action")))
        default:
            throw AgentError(
                code: .invalidArguments,
                message: "unknown tool \(request.tool.debugDescription)",
                remedy: "The agent serves: " + ToolCatalogue.all.map(\.name).joined(separator: ", "))
        }
    }

    // MARK: - proctor_apps

    private func apps(_ args: Args) async throws -> JSONValue {
        switch try args.enumeration("action", of: ["list", "attach", "activate", "detach"]) {
        case "list":
            return try await session.listApps(includeWindowless: args.bool("includeWindowless", false))
        case "attach":
            return try await session.attach(bundleId: args.string("bundleId"),
                                            pid: args.int("pid").map(Int32.init),
                                            name: args.string("name"))
        case "activate":
            return try await session.activate(bundleId: args.string("bundleId"),
                                              pid: args.int("pid").map(Int32.init),
                                              name: args.string("name"),
                                              app: args.string("app"),
                                              timeoutMs: args.int("timeoutMs") ?? 5000)
        default:
            return try await session.detach(app: try args.requiredString("app"))
        }
    }

    // MARK: - proctor_snapshot

    private func snapshot(_ args: Args) async throws -> JSONValue {
        var options = Session.SnapshotOptions()
        options.root = args.string("root")
        options.maxDepth = args.int("maxDepth") ?? 24
        options.maxNodes = args.int("maxNodes") ?? 2000
        options.includeInvisible = args.bool("includeInvisible", false)
        let result = try await session.snapshot(window: try args.requiredString("window"),
                                                options: options,
                                                sinceRevision: args.int("sinceRevision"))
        return try JSONValue.encode(result)
    }

    // MARK: - proctor_find

    private func find(_ args: Args) async throws -> JSONValue {
        // The find arguments are flat on this tool and nested under `find` on
        // wait and assert, so the same decoder serves both.
        let predicate = FindPredicate(json: args.raw)
        guard !predicate.isEmpty else {
            throw AgentError(code: .invalidArguments,
                             message: "proctor_find needs at least one condition",
                             remedy: "Supply role, subrole, title, label, identifier, valueContains, "
                                   + "enabled, focused or hasAction. Prefer identifier where the app "
                                   + "sets accessibilityIdentifier.")
        }
        return try await session.find(window: try args.requiredString("window"),
                                      predicate: predicate,
                                      limit: args.int("limit") ?? 25)
    }

    // MARK: - proctor_act

    private func act(_ args: Args) async throws -> JSONValue {
        let raw = try args.array("steps")
        guard !raw.isEmpty else {
            throw AgentError(code: .invalidArguments, message: "proctor_act needs at least one step")
        }
        let settle = Args.settlePolicy(args.value("settle"), base: .default)
        let steps = try raw.enumerated().map { try Args.step($1, at: $0, defaultSettle: settle) }

        return try await session.act(window: try args.requiredString("window"),
                                     steps: steps,
                                     settle: settle,
                                     foreground: args.bool("foreground", false),
                                     captureEach: args.bool("captureEach", false),
                                     diffEach: args.bool("diffEach", true),
                                     record: args.string("record"),
                                     pointerMarks: args.bool("pointerMarks", false))
    }

    // MARK: - proctor_capture

    private func capture(_ args: Args) async throws -> JSONValue {
        var annotate = Session.AnnotateOptions()
        annotate.marks = args.bool("annotate", false)
        annotate.all = args.bool("annotateAll", false)
        annotate.grid = args.bool("grid", false)
        annotate.gridSpacing = args.double("gridSpacing") ?? 100
        annotate.maxMarks = args.int("maxMarks") ?? SetOfMarks.defaultMaxMarks
        // Normalisation is on by default on the model-facing path. An oversized
        // frame is downsampled by the vision API anyway, so the choice is not
        // "full resolution or not" — it is whether the shrink happens here, where
        // the factor is measured and reported, or there, where it is silent and
        // every coordinate the model returns is in a space Proctor cannot invert.
        // Callers that genuinely need native pixels (pixel-plane assertions) pass
        // normalize: false; the internal capture paths — settle, act/assert/flow
        // evidence, tri-observer — never reach here and stay native regardless.
        var normalize: CaptureNormalizeOptions?
        if args.bool("normalize", true) {
            // What the frame is for decides how many pixels it needs, and there
            // are three ways a caller can say so, in descending order of how
            // specific they were being.
            //
            // An explicit pixel ceiling wins outright and clears the tier label,
            // because once a caller has named the numbers no tier describes them
            // and reporting one would be a label rather than a fact.
            //
            // Otherwise a named purpose wins. Otherwise `annotate` decides it: a
            // frame carrying numbered marks is being used to pick a target, not
            // to read anything, so it drops to `targeting` on its own. That rule
            // is the whole reason marks and a small frame belong together — the
            // model is matching a numeral, and a numeral survives a downscale
            // that body text would not.
            let explicitEdge = args.int("normalizeMaxLongEdge")
            let explicitPixels = args.int("normalizeMaxPixels")
            let named = VisionCapture.Purpose.parse(args.string("purpose"))
            let annotating = args.bool("annotate", false) || args.bool("annotateAll", false)
            let purpose = named ?? (annotating ? .targeting : .default)
            let explicit = explicitEdge != nil || explicitPixels != nil
            normalize = CaptureNormalizeOptions(
                maxLongEdge: explicitEdge ?? purpose.maxLongEdge,
                maxPixels: explicitPixels ?? purpose.maxPixels,
                purpose: explicit ? nil : purpose)
        }
        return try await session.captureWindow(try args.requiredString("window"),
                                        path: args.string("path"),
                                        waitForComplete: args.bool("waitForComplete", true),
                                        timeoutMs: args.int("timeoutMs") ?? 3000,
                                        scale: args.double("scale"),
                                        tileHashes: args.bool("tileHashes", false),
                                        includeCursor: args.bool("includeCursor", false),
                                        normalize: normalize,
                                        encoding: try Self.encoding(args),
                                        annotate: annotate)
    }

    /// Parse the shared `format` / `quality` pair. An unrecognised format is an
    /// error naming what is accepted rather than a silent fall back to PNG — a
    /// caller who asked for WebP needs to learn macOS cannot write it, not to
    /// receive a PNG and wonder why the file is large.
    private static func encoding(_ args: Args) throws -> ImageEncodingOptions {
        guard let raw = args.string("format"), !raw.isEmpty else {
            return ImageEncodingOptions(format: .png, quality: args.int("quality"))
        }
        guard let format = ImageFormat.parse(raw) else {
            throw AgentError(
                code: .invalidArguments,
                message: "format \"\(raw)\" is not a container Proctor can write",
                remedy: "Use \"png\" (lossless, the default) or \"jpeg\". macOS ships no WebP "
                      + "encoder, so WebP is not available.")
        }
        return ImageEncodingOptions(format: format, quality: args.int("quality"))
    }

    // MARK: - proctor_zoom

    private func zoom(_ args: Args) async throws -> JSONValue {
        let region = args.value("region")?.arrayValue?.compactMap(\.doubleValue)
        return try await session.zoom(window: try args.requiredString("window"),
                                      region: region,
                                      node: args.string("node"),
                                      padding: args.double("padding") ?? 0,
                                      path: args.string("path"),
                                      waitForComplete: args.bool("waitForComplete", true),
                                      timeoutMs: args.int("timeoutMs") ?? 3000,
                                      scale: args.double("scale"),
                                      includeCursor: args.bool("includeCursor", false),
                                      encoding: try Self.encoding(args))
    }

    // MARK: - proctor_wait
    private func wait(_ args: Args) async throws -> JSONValue {
        let condition = try args.enumeration("condition", of: [
            "nodeExists", "nodeGone", "valueEquals", "valueContains",
            "enabled", "focused", "regionQuiet", "reflectorIdle"
        ])
        let find = args.value("find").map { FindPredicate(json: $0) }
        let region = args.value("region")?.arrayValue?.compactMap(\.doubleValue)
        return try await session.wait(window: try args.requiredString("window"),
                                      condition: condition,
                                      node: args.string("node"),
                                      find: find,
                                      value: args.value("value"),
                                      region: region,
                                      timeoutMs: args.int("timeoutMs") ?? 10000,
                                      pollMs: args.int("pollMs") ?? 100)
    }

    // MARK: - proctor_assert

    private func assert(_ args: Args) async throws -> JSONValue {
        let assertions = try args.array("assertions")
        guard !assertions.isEmpty else {
            throw AgentError(code: .invalidArguments,
                             message: "proctor_assert needs at least one assertion")
        }
        return try await session.assertAll(window: try args.requiredString("window"),
                                           assertions: assertions,
                                           captureEvidence: args.bool("captureEvidence", true))
    }

    // MARK: - proctor_flow

    private func flow(_ args: Args) async throws -> JSONValue {
        let action = try args.enumeration("action", of: ["start", "stop", "replay", "list",
                                                         "show", "delete"])
        switch action {
        case "start":
            return try await session.flowStart(name: try args.requiredString("name"),
                                               window: args.string("window"),
                                               description: args.string("description"))
        case "stop":
            return try await session.flowStop()
        case "list":
            return try await session.flowList()
        case "show":
            return try await session.flowShow(name: try args.requiredString("name"))
        case "delete":
            return try await session.flowDelete(name: try args.requiredString("name"))
        default:
            return try await session.flowReplay(
                name: try args.requiredString("name"),
                window: args.string("window"),
                captureEach: args.bool("captureEach", false),
                settle: Args.settlePolicy(args.value("settle"), base: .default),
                pointerMarks: args.bool("pointerMarks", false))
        }
    }

    // MARK: - proctor_stability

    private func stability(_ args: Args) async throws -> JSONValue {
        let report = try await session.stability(
            flow: try args.requiredString("flow"),
            runs: args.int("runs") ?? 5,
            window: args.string("window"),
            resetBetween: try Args.steps(args.value("resetBetween"), field: "resetBetween"),
            includeTiles: args.bool("includeTiles", false),
            captureEach: args.bool(StabilityCaptureOptions.captureEachArg, false),
            pointerMarks: args.bool(StabilityCaptureOptions.pointerMarksArg, false))
        return try JSONValue.encode(report)
    }

    // MARK: - proctor_inspect

    private func inspect(_ args: Args) async throws -> JSONValue {
        try await session.inspect(window: try args.requiredString("window"),
                                  node: args.string("node"),
                                  maxDepth: args.int("maxDepth") ?? 24,
                                  includeConstraints: args.bool("includeConstraints", false),
                                  presentation: args.bool("presentation", true))
    }

    // MARK: - proctor_doctor

    private func doctor(_ args: Args) async throws -> JSONValue {
        // The consent dialog is only ever shown to the process macOS holds
        // responsible for asking — this one. Triggering it from the UI would
        // put the request on the wrong identity, and calling it unasked would
        // pop a dialog during an ordinary health check, so it is opt-in.
        if args.bool("requestAccessibility", false), !Grants.accessibility() {
            Grants.promptAccessibility()
        }
        if args.bool("requestScreenRecording", false) {
            Grants.promptScreenRecording()
        }
        // `session.doctor()` already carries a `policy` block: PRO-0050's posture,
        // which reports mode, counts, token liveness, jail shape and audit posture
        // and deliberately names no bundle id, path, key id or token.
        //
        // This line used to overwrite it with `policyStatus()`, the full ungated
        // status, and that overwrite did two things neither item wanted. It put
        // every allow, block and sensitive entry, the filesystem roots, the trail's
        // path and the key id back into the first call a model makes, so PRO-0050's
        // clause 12 was true of the type and false on the wire. And because the
        // replacement has none of the posture's keys, `DoctorReport` could no longer
        // decode its own agent's reply, so the status window reported a perfectly
        // healthy agent as "not answering" — found by building this feature and
        // looking at it, which no test in either item could have caught.
        //
        // `proctor_policy` action `status` is unchanged and still answers in full.
        var report = try JSONValue.encode(await session.doctor(verbose: args.bool("verbose", false)))
            .objectValue ?? [:]
        // The run HUD carries the only stop control a person has, so its absence
        // is reported rather than left silent: a run still proceeds without the
        // panel, and refusing to drive because an annotation failed would be
        // worse, but somebody who believes they have a stop button and does not
        // is the state this block exists to prevent.
        report["hud"] = await session.hudStatus()
        // Contention, per lane. The scheduler runs whether or not the panel is on
        // screen — taking turns is correctness, not decoration — so a wedged lane
        // has to be answerable from the health report rather than only from a
        // window somebody may have switched off.
        report["queue"] = await session.queueStatus()
        // Whether a foreground step says so on the screen, and whether it holds
        // input. The second one is an opt-in and can be asked for and still not
        // be there, because a keyboard tap is gated on a grant Proctor does not
        // otherwise need, so it reports what is actually true rather than what
        // was asked for.
        report["takeover"] = await session.takeoverStatus()
        return .object(report)
    }

    /// Screen-unlock turn control. Actions:
    ///   status  — turn/lock state and whether the login-path plugin is armed
    ///   open    — open a turn without touching the screen (proves the handshake)
    ///   close   — end a turn
    ///   unlock  — open a turn and ask macOS to evaluate the unlock right
    ///   relock  — relock immediately and end the turn
    private func unlock(_ args: Args) async throws -> JSONValue {
        let action = args.string("action") ?? "status"
        let ttlMs = args.int("ttlMs") ?? 15_000
        let coord = UnlockCoordinator.shared
        switch action {
        case "open":
            coord.openTurn(ttlMs: ttlMs)
            return .object(["opened": .bool(true), "ttlMs": .number(Double(ttlMs))])
        case "close":
            coord.closeTurn()
            return .object(["closed": .bool(true)])
        case "unlock":
            return try JSONValue.encode(coord.requestUnlock(ttlMs: ttlMs))
        case "relock":
            coord.relock()
            return .object(["relocked": .bool(true)])
        case "lock":
            coord.lockOnly()
            return .object(["locked": .bool(true)])
        case "status":
            let info = UnlockTurn.shared.contactInfo()
            var out: [String: JSONValue] = [
                "screenLocked": .bool(UnlockCoordinator.screenIsLocked()),
                "turnAuthorized": .bool(UnlockTurn.shared.authorized()),
                "pluginInstalled": .bool(FileManager.default.fileExists(
                    atPath: "/Library/Security/SecurityAgentPlugins/ProctorUnlock.bundle")),
                "brokerSocket": .string(UnlockBroker.socketPath),
                "brokerContactCount": .number(Double(info.contactCount))
            ]
            // Proof the login-path mechanism reached the broker, readable after
            // a locked test without having watched the screen.
            if let at = info.lastContact { out["brokerLastContact"] = .string(ISO8601DateFormatter().string(from: at)) }
            if let reply = info.lastReply { out["brokerLastReply"] = .string(reply) }
            if let ok = info.lastPeerVerified { out["brokerLastPeerVerified"] = .bool(ok) }
            return .object(out)
        default:
            throw AgentError(code: .invalidArguments,
                             message: "unknown unlock action \(action.debugDescription)",
                             remedy: "Use status, open, close, unlock or relock.")
        }
    }

    // MARK: - proctor_computer (Anthropic façade)

    private func computer(_ args: Args) async throws -> JSONValue {
        let window = try args.requiredString("window")
        guard let action = args.value("action"), action.objectValue != nil else {
            throw AgentError(
                code: .invalidArguments,
                message: "proctor_computer requires an `action` object",
                remedy: "Send a stock Anthropic computer action, e.g. "
                      + "{\"action\":\"left_click\",\"coordinate\":[x,y]}.")
        }
        return try await session.computerUse(schema: .anthropic, window: window, payload: action,
                                             scale: args.double("scale") ?? 1,
                                             foreground: args.bool("foreground", true))
    }

    // MARK: - proctor_openai_computer (OpenAI façade)

    private func openaiComputer(_ args: Args) async throws -> JSONValue {
        let window = try args.requiredString("window")
        guard let actions = args.value("actions"),
              actions.arrayValue != nil || actions.objectValue != nil else {
            throw AgentError(
                code: .invalidArguments,
                message: "proctor_openai_computer requires `actions`",
                remedy: "Send an array of OpenAI computer actions, or a single action object, e.g. "
                      + "[{\"type\":\"click\",\"button\":\"left\",\"x\":10,\"y\":20}].")
        }
        return try await session.computerUse(schema: .openai, window: window, payload: actions,
                                             scale: args.double("scale") ?? 1,
                                             foreground: args.bool("foreground", true))
    }

    // MARK: - proctor_menu

    private func menu(_ args: Args) async throws -> JSONValue {
        try await session.menuBar(app: args.string("app"), window: args.string("window"))
    }

    // MARK: - proctor_dictionary

    private func dictionary(_ args: Args) async throws -> JSONValue {
        // Either an app handle or a window handle identifies the target; the
        // window's owning app is used when only a window is given.
        guard args.string("app") != nil || args.string("window") != nil else {
            throw AgentError(
                code: .invalidArguments,
                message: "proctor_dictionary requires app or window",
                remedy: "Pass an app handle from proctor_apps (action \"attach\"), or a window "
                      + "handle whose owning app should be read.")
        }
        return try await session.dictionary(app: args.string("app"),
                                            window: args.string("window"),
                                            summaryOnly: args.bool("summaryOnly", false),
                                            refresh: args.bool("refresh", false))
    }

    // MARK: - proctor_policy (audit trail + policy gate)

    /// Policy gate configuration and audit-trail reads. Actions:
    ///   status    — the current lists, whether a token is live, and the audit path
    ///   configure — replace any of the allow/block/sensitive sets supplied
    ///   approve   — mint a TTL-bounded approval token, optionally scoped to a bundle id
    ///   revoke    — drop the live token
    ///   audit     — the most recent JSONL records
    private func policy(_ args: Args) async throws -> JSONValue {
        let action = args.string("action") ?? "status"
        switch action {
        case "status":
            return await session.policyStatus()
        case "configure":
            return try await session.configurePolicy(
                allow: args.value("allow")?.arrayValue?.compactMap(\.stringValue),
                block: args.value("block")?.arrayValue?.compactMap(\.stringValue),
                sensitive: args.value("sensitive")?.arrayValue?.compactMap(\.stringValue))
        case "approve":
            return await session.approve(bundleId: args.string("bundleId"),
                                         ttlMs: args.int("ttlMs") ?? 15_000)
        case "revoke":
            return await session.revokeApproval()
        case "audit":
            return await session.auditTail(limit: args.int("limit") ?? 50)
        default:
            throw AgentError(code: .invalidArguments,
                             message: "unknown policy action \(action.debugDescription)",
                             remedy: "Use status, configure, approve, revoke or audit.")
        }
    }

    // MARK: - proctor_kill (process list + terminate)

    /// Process listing and termination. Actions:
    ///   list — enumerate the processes the query names, touching nothing
    ///   kill — terminate them, gated by the app policy and recorded in the audit trail
    private func kill(_ args: Args) async throws -> JSONValue {
        let action = args.string("action") ?? "list"
        guard action == "list" || action == "kill" else {
            throw AgentError(code: .invalidArguments,
                             message: "unknown kill action \(action.debugDescription)",
                             remedy: "Use list or kill.")
        }
        let match = KillQuery.Match(rawValue: args.string("match") ?? "substring") ?? .substring
        let query = KillQuery(pid: args.int("pid").map(Int32.init),
                              bundleId: args.string("bundleId"),
                              name: args.string("name"),
                              match: match)
        guard !query.isEmpty else {
            throw AgentError(code: .invalidArguments,
                             message: "proctor_kill needs a target",
                             remedy: "Supply pid, bundleId or name. An empty selector would name every "
                                   + "process, which is never what a teardown step intends.")
        }
        return try await session.killProcesses(query: query,
                                               perform: action == "kill",
                                               force: args.bool("force", false))
    }

    // MARK: - proctor_ios (Simulator device lane)

    /// The iOS Simulator lane. Actions:
    ///   list       — enumerate simulators, touching nothing
    ///   boot       — start a named one and wait for it, gated and audited
    ///   open       — deliver a deep link to a booted one and report the evidence
    ///   screenshot — write the device surface to disk
    private func ios(_ args: Args) async throws -> JSONValue {
        let action = args.string("action") ?? "list"
        guard ["list", "boot", "open", "screenshot", "flow"].contains(action) else {
            throw AgentError(code: .invalidArguments,
                             message: "unknown ios action \(action.debugDescription)",
                             remedy: "Use list, boot, open, screenshot or flow.")
        }
        // A Maestro flow binds at the file level rather than the step level, so it
        // takes its own route rather than being threaded through the deep-link
        // signature. PRO-0044's warning: ActuationBackend performs a step, and
        // this executes a file.
        if action == "flow" {
            guard let path = args.string("path"), !path.isEmpty else {
                throw AgentError(code: .invalidArguments,
                                 message: "proctor_ios action \"flow\" requires path",
                                 remedy: "Pass the absolute path of the Maestro flow file to run.")
            }
            return try await session.maestroFlow(
                path: path,
                device: args.string("device"),
                runs: args.int("runs") ?? 1,
                pixelEvidence: args.bool("pixelEvidence", true),
                timeoutMs: args.int("timeoutMs") ?? 300_000)
        }
        return try await session.ios(action: action,
                                     device: args.string("device"),
                                     url: args.string("url"),
                                     bundleId: args.string("bundleId"),
                                     pixelEvidence: args.bool("pixelEvidence", true),
                                     changeThreshold: args.double("changeThreshold"),
                                     path: args.string("path"),
                                     timeoutMs: args.int("timeoutMs"),
                                     settleMs: args.int("settleMs"))
    }

    // MARK: - proctor_guest (VM lifecycle)

    /// Guest lifecycle. Actions:
    ///   list   — enumerate guests, touching nothing
    ///   status — read one
    ///   start  — power on, then re-read
    ///   stop   — power off, then re-read
    ///   clone  — copy a named guest to a new name
    ///
    /// Nothing provisions. A guest that does not already exist is refused.
    private func guest(_ args: Args) async throws -> JSONValue {
        let action = args.string("action") ?? "list"
        guard ["list", "status", "start", "stop", "clone"].contains(action) else {
            throw AgentError(code: .invalidArguments,
                             message: "unknown guest action \(action.debugDescription)",
                             remedy: "Use list, status, start, stop or clone.")
        }
        return try await session.guest(action: action,
                                       guest: args.string("guest"),
                                       provider: args.string("provider"),
                                       newName: args.string("newName"))
    }

    // MARK: - proctor_resource (MCP resources backing)
    private func resource(_ args: Args) async throws -> JSONValue {
        let key = try args.requiredString("key")
        guard ResourceCatalogue.spec(key: key) != nil else {
            throw AgentError(code: .invalidArguments,
                             message: "unknown resource key \(key.debugDescription)",
                             remedy: "Keys: " + ResourceCatalogue.all.map(\.key).joined(separator: ", "))
        }
        return try await session.resource(key: key)
    }
}

// MARK: - Arguments

struct Args: Sendable {
    let tool: String
    let raw: JSONValue

    func value(_ key: String) -> JSONValue? {
        guard let value = raw[key], value != .null else { return nil }
        return value
    }

    func string(_ key: String) -> String? { value(key)?.stringValue }
    func int(_ key: String) -> Int? { value(key)?.intValue }
    func double(_ key: String) -> Double? { value(key)?.doubleValue }
    func bool(_ key: String, _ fallback: Bool) -> Bool { value(key)?.boolValue ?? fallback }

    func requiredString(_ key: String) throws -> String {
        guard let out = string(key), !out.isEmpty else {
            throw AgentError(code: .invalidArguments,
                             message: "\(tool) requires \(key)",
                             remedy: hint(for: key))
        }
        return out
    }

    func enumeration(_ key: String, of allowed: [String]) throws -> String {
        let value = try requiredString(key)
        guard allowed.contains(value) else {
            throw AgentError(code: .invalidArguments,
                             message: "\(key) must be one of \(allowed.joined(separator: ", ")), "
                                    + "not \(value.debugDescription)")
        }
        return value
    }

    func array(_ key: String) throws -> [JSONValue] {
        guard let array = value(key)?.arrayValue else {
            throw AgentError(code: .invalidArguments,
                             message: "\(tool) requires \(key) as an array")
        }
        return array
    }

    private func hint(for key: String) -> String? {
        switch key {
        case "window": return "Window handles come from proctor_apps with action \"attach\"."
        case "app": return "App handles come from proctor_apps."
        case "flow", "name": return "Flow names come from proctor_flow with action \"list\"."
        default: return nil
        }
    }

    /// SettlePolicy has no defaults in its Codable conformance, so a partial
    /// override cannot be decoded whole. Each field is merged over a base
    /// instead, which is what a caller sending only `timeoutMs` means.
    static func settlePolicy(_ value: JSONValue?, base: SettlePolicy) -> SettlePolicy {
        guard let value, value.objectValue != nil else { return base }
        return SettlePolicy(
            quietFrames: value["quietFrames"]?.intValue ?? base.quietFrames,
            dirtyThreshold: value["dirtyThreshold"]?.doubleValue ?? base.dirtyThreshold,
            axQuietMs: value["axQuietMs"]?.intValue ?? base.axQuietMs,
            timeoutMs: value["timeoutMs"]?.intValue ?? base.timeoutMs,
            requireReflectorIdle: value["requireReflectorIdle"]?.boolValue ?? base.requireReflectorIdle)
    }

    static func step(_ value: JSONValue, at index: Int, defaultSettle: SettlePolicy) throws -> ActionStep {
        // A bare string is accepted as shorthand for a step with only a kind.
        let raw: JSONValue = value.stringValue.map { .object(["kind": .string($0)]) } ?? value
        guard raw.objectValue != nil else {
            throw AgentError(code: .invalidArguments, message: "step \(index) is not an object")
        }
        guard let kindName = raw["kind"]?.stringValue else {
            throw AgentError(code: .invalidArguments, message: "step \(index) has no kind")
        }
        guard let kind = ActionStep.Kind(rawValue: kindName) else {
            throw AgentError(
                code: .invalidArguments,
                message: "step \(index) has unknown kind \(kindName.debugDescription)",
                remedy: "Known kinds: press, setValue, focus, menu, type, key, scroll, increment, "
                      + "decrement, pick, confirm, cancel, raise, close, resize, move, dragPath, "
                      + "hover, click, shortcut, appleScript, waitFor.")
        }
        let settleOverride = raw["settle"].flatMap { override -> SettlePolicy? in
            override.objectValue == nil ? nil : settlePolicy(override, base: defaultSettle)
        }
        return ActionStep(
            kind: kind,
            node: raw["node"]?.stringValue,
            value: raw["value"],
            menuPath: raw["menuPath"]?.arrayValue?.compactMap(\.stringValue),
            text: raw["text"]?.stringValue,
            key: raw["key"]?.stringValue,
            modifiers: raw["modifiers"]?.arrayValue?.compactMap(\.stringValue),
            delta: raw["delta"]?.arrayValue?.compactMap(\.doubleValue),
            point: raw["point"]?.arrayValue?.compactMap(\.doubleValue),
            path: raw["path"]?.arrayValue?.map { $0.arrayValue?.compactMap(\.doubleValue) ?? [] },
            durationMs: raw["durationMs"]?.intValue,
            settle: settleOverride,
            label: raw["label"]?.stringValue)
    }

    /// `resetBetween` is declared as an object in the schema but described as
    /// steps, so both shapes are accepted: an array of steps, or an object with
    /// a `steps` array.
    static func steps(_ value: JSONValue?, field: String) throws -> [ActionStep] {
        guard let value, value != .null else { return [] }
        let list: [JSONValue]
        if let array = value.arrayValue {
            list = array
        } else if let nested = value["steps"]?.arrayValue {
            list = nested
        } else {
            throw AgentError(code: .invalidArguments,
                             message: "\(field) must be an array of steps, or an object with a "
                                    + "`steps` array")
        }
        return try list.enumerated().map { try step($1, at: $0, defaultSettle: .default) }
    }
}
