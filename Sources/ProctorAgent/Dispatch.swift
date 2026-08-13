import Foundation
import ProctorCore

// Routing and argument decoding. The schemas in ToolCatalogue are the source of
// truth for names and defaults; this file is where they are read.

struct Dispatcher: Sendable {
    let session: Session

    func handle(_ request: AgentRequest) async -> AgentResponse {
        do {
            let result = try await route(request)
            return AgentResponse(id: request.id, ok: true, result: result)
        } catch let error as AgentError {
            return AgentResponse(id: request.id, ok: false, error: error)
        } catch let error as PixelCompare.Failure {
            return AgentResponse(id: request.id, ok: false,
                                 error: AgentError(code: .internalError, message: error.reason))
        } catch {
            return AgentResponse(id: request.id, ok: false,
                                 error: AgentError(code: .internalError,
                                                   message: "\(request.tool) failed: \(error)"))
        }
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
        // Internal verb behind the MCP resources surface. Never in ToolCatalogue,
        // so a host cannot reach it as a tool; the shim forwards resources/read to
        // it. It only re-projects state the agent already holds or reads without a
        // TCC grant — no new capability.
        case "proctor_resource":  return try await resource(args)
        default:
            throw AgentError(
                code: .invalidArguments,
                message: "unknown tool \(request.tool.debugDescription)",
                remedy: "The agent serves: " + ToolCatalogue.all.map(\.name).joined(separator: ", "))
        }
    }

    // MARK: - proctor_apps

    private func apps(_ args: Args) async throws -> JSONValue {
        switch try args.enumeration("action", of: ["list", "attach", "detach"]) {
        case "list":
            return try await session.listApps(includeWindowless: args.bool("includeWindowless", false))
        case "attach":
            return try await session.attach(bundleId: args.string("bundleId"),
                                            pid: args.int("pid").map(Int32.init),
                                            name: args.string("name"))
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
                                     record: args.string("record"))
    }

    // MARK: - proctor_capture

    private func capture(_ args: Args) async throws -> JSONValue {
        var annotate = Session.AnnotateOptions()
        annotate.marks = args.bool("annotate", false)
        annotate.all = args.bool("annotateAll", false)
        annotate.grid = args.bool("grid", false)
        annotate.gridSpacing = args.double("gridSpacing") ?? 100
        annotate.maxMarks = args.int("maxMarks") ?? SetOfMarks.defaultMaxMarks
        var normalize: CaptureNormalizeOptions?
        if args.bool("normalize", false) {
            normalize = CaptureNormalizeOptions(
                maxLongEdge: args.int("normalizeMaxLongEdge") ?? VisionCapture.defaultMaxLongEdge,
                maxPixels: args.int("normalizeMaxPixels") ?? VisionCapture.defaultMaxPixels)
        }
        return try await session.captureWindow(try args.requiredString("window"),
                                        path: args.string("path"),
                                        waitForComplete: args.bool("waitForComplete", true),
                                        timeoutMs: args.int("timeoutMs") ?? 3000,
                                        scale: args.double("scale"),
                                        tileHashes: args.bool("tileHashes", false),
                                        includeCursor: args.bool("includeCursor", false),
                                        normalize: normalize,
                                        annotate: annotate)
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
                                      includeCursor: args.bool("includeCursor", false))
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
                settle: Args.settlePolicy(args.value("settle"), base: .default))
        }
    }

    // MARK: - proctor_stability

    private func stability(_ args: Args) async throws -> JSONValue {
        let report = try await session.stability(
            flow: try args.requiredString("flow"),
            runs: args.int("runs") ?? 5,
            window: args.string("window"),
            resetBetween: try Args.steps(args.value("resetBetween"), field: "resetBetween"),
            includeTiles: args.bool("includeTiles", false))
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
        // The policy gate is part of readiness: an operator checking health should
        // see the lists in force and whether an approval token is live, alongside
        // the grants. The doctor output schema is an open object, so this extra
        // block validates without a schema change.
        var report = try JSONValue.encode(await session.doctor(verbose: args.bool("verbose", false)))
            .objectValue ?? [:]
        report["policy"] = await session.policyStatus()
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
