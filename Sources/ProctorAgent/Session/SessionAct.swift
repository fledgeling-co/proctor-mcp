import Foundation
import ProctorCore

// Actuation and waiting.

extension Session {

    /// The step kinds that can only travel through CGEventPost. They enter the
    /// single WindowServer event stream, so they need the target foreground and
    /// they are what Secure Event Input blocks.
    static let syntheticKinds: Set<ActionStep.Kind> = [.dragPath, .hover, .click, .key]

    /// The kinds that *may* end up there. Both prefer the accessibility plane
    /// and fall to a synthetic event only when the element refuses — `type` into
    /// a field whose value cannot be set, `scroll` with no scroll action to
    /// perform. That is a property of the element, so it is not knowable until
    /// the step is reached, which is why an up-front disclosure counts these
    /// separately and a finished run reports what actually travelled.
    static let conditionalKinds: Set<ActionStep.Kind> = [.type, .scroll]

    /// What this batch will do to the foreground, from its own steps, before any
    /// of them runs. One value, read by the scheduler, the panel and the menu
    /// bar alike.
    static func foregroundDemand(for steps: [ActionStep], foreground: Bool) -> ForegroundDemand {
        ForegroundDemand.forBatch(kinds: steps.map(\.kind), synthetic: syntheticKinds,
                                  conditional: conditionalKinds, foreground: foreground)
    }

    struct StepRun: Sendable {
        var results: [StepResult] = []
        /// What each captured step produced, typed rather than as JSON, so the
        /// determinism instrument can read the file locations without re-parsing
        /// its own output. `StepArtifact.json` in ProctorCore fixes the shape act
        /// and flow replay have always emitted, with golden coverage there.
        var stepArtifacts: [StepArtifact] = []
        var failedAt: Int?
        var completed: Int = 0
        var finalHash: String?
        var hashes: [String] = []
        /// Every time this run was held because somebody was using the machine.
        var yields: [YieldRecord] = []

        var captures: [JSONValue] { stepArtifacts.map(\.json) }
    }

    // MARK: - proctor_act

    func act(window id: String, steps: [ActionStep], settle: SettlePolicy, foreground: Bool,
             captureEach: Bool, diffEach: Bool, record: String?,
             pointerMarks: Bool = false) async throws -> JSONValue {
        let window = try windowHandle(id)
        // The policy gate runs before anything is actuated: a blocked app, or a
        // sensitive one with no current token, is refused here (and the refusal is
        // audited) rather than driven. The returned context names the target for
        // the per-step audit records.
        let audit = try enforcePolicy(tool: "proctor_act", window: window)
        loadFlowsIfNeeded()

        // The lanes for this batch, taken once and held to the last step. Which
        // ones it needs is knowable from the steps and from `foreground` before
        // anything runs, and it never asks for another after it starts.
        let demand = lanes(for: steps, window: window, foreground: foreground)
        let summary = StepDescription.runLine(.act(steps: steps.count),
                                              app: appHandle(forWindow: window)?.name)
        return try await scheduled(lanes: demand, summary: summary) {
            try await actInLane(window: id, handle: window, steps: steps, settle: settle,
                                foreground: foreground, captureEach: captureEach,
                                diffEach: diffEach, record: record,
                                pointerMarks: pointerMarks, audit: audit)
        }
    }

    private func actInLane(window id: String, handle window: WindowHandle, steps: [ActionStep],
                           settle: SettlePolicy, foreground: Bool, captureEach: Bool,
                           diffEach: Bool, record: String?, pointerMarks: Bool,
                           audit: AuditContext) async throws -> JSONValue {
        // Re-read the gate now that the lane is ours. The check before the queue
        // is what stops a refused run taking a place in the line; this one is the
        // authority at the moment of driving, which is not the same thing when a
        // run waited forty seconds for its turn and the approval token that let
        // it through was TTL-bounded. The same principle a repeated sweep already
        // follows between its repeats. It reads settings and a token and touches
        // no window, so re-running it costs nothing.
        let audit = try enforcePolicy(tool: audit.tool, window: window)
        hudRunControlBegin()

        let target = record ?? recording
        let run = await runSteps(steps, window: window, settle: settle, foreground: foreground,
                                 captureEach: captureEach, diffEach: diffEach, audit: audit,
                                 pointerMarks: pointerMarks)

        if let target {
            try appendToFlow(named: target, window: window, run: run, steps: steps)
        }

        let demandForReport = Self.foregroundDemand(for: steps, foreground: foreground)
        let result = ActResult(window: id, steps: run.results, completed: run.completed,
                               failedAt: run.failedAt, finalHash: run.finalHash,
                               foreground: ForegroundReport.from(demandForReport,
                                                                 planes: run.results.map(\.plane)),
                               yields: run.yields.isEmpty ? nil : run.yields)
        var out = try JSONValue.encode(result).objectValue ?? [:]
        // One sentence beside the records, so a caller reading prose knows why
        // the run took longer than its work did. Alongside rather than inside,
        // exactly as `captures` and `browser` already ride alongside.
        if let note = YieldRecord.note(for: run.yields) { out["yieldNote"] = .string(note) }
        // StepResult has no slot for a capture, so per-step frames are returned
        // alongside the step list rather than dropped.
        if captureEach { out["captures"] = .array(run.captures) }
        if let target { out["recordedInto"] = .string(target) }
        // Once per call, never per step. Emitted only when a step this batch
        // actually addressed lies inside the page, so driving the reload button is
        // not told to use a different tool. Nothing here refuses anything and no
        // step's plane changes: the batch ran, and it arrives carrying a note that
        // the page belongs to Obscura.
        if let handoff = browserHandoff(window: window,
                                        targets: browserTargets(for: steps, window: window)) {
            out["browser"] = try JSONValue.encode(handoff)
        }
        return .object(out)
    }

    /// The screen-space frames this batch addressed, for the browser boundary
    /// check. A step naming an element contributes that element's frame; a step
    /// naming a coordinate contributes the point, converted from the window
    /// coordinates the tool takes into the screen coordinates accessibility frames
    /// are in. A batch of steps that name neither — a menu path, a keystroke —
    /// contributes nothing, so the question falls back to the window itself.
    ///
    /// Every step is considered rather than a prefix of them, because a batch that
    /// opens a menu and then clicks something on the page reaches the page. Element
    /// ids are resolved once each, so a twenty-step batch against one field costs
    /// one accessibility round trip rather than twenty.
    private func browserTargets(for steps: [ActionStep], window: WindowHandle) -> [Rect] {
        var out: [Rect] = []
        var resolved: [String: Rect?] = [:]
        for step in steps {
            if let id = step.node {
                let frame = resolved[id] ?? { () -> Rect? in
                    let frame = (try? ax.node(id: id))?.frame
                    resolved[id] = frame
                    return frame
                }()
                if let frame { out.append(frame) }
            } else if let point = step.point, point.count >= 2 {
                out.append(Rect(x: window.frame.x + point[0], y: window.frame.y + point[1],
                                w: 0, h: 0))
            }
        }
        return out
    }

    /// One code path for act, flow replay and stability, so a step behaves
    /// identically however it was reached. When an audit context is supplied,
    /// every step it runs is recorded — secrets redacted — so a completed run
    /// leaves a trail that accounts for each action.
    func runSteps(_ steps: [ActionStep], window: WindowHandle, settle: SettlePolicy,
                  foreground: Bool, captureEach: Bool, diffEach: Bool,
                  audit: AuditContext? = nil, pointerMarks: Bool = false) async -> StepRun {
        var run = StepRun()
        let app = appHandle(forWindow: window)
        // The panel goes up for the batch about to run, and the same is true
        // however the batch was reached — act, a replayed flow, one pass of a
        // stability sweep, the CUA façade. A stop control that is present for
        // some kinds of run and absent for others is worse than none.
        let demand = Self.foregroundDemand(for: steps, foreground: foreground)
        await hudRunBegan(total: steps.count, window: window, demand: demand)
        // The same fact, reachable without the panel: the menu bar mirrors this
        // and is on every display, where the panel is on one.
        let foregroundRun = foregroundBegan(demand: demand, app: app?.name)
        // A run that is going to take the machine watches for the person whose
        // machine it is. One that is not never arms anything: an accessibility
        // run takes nothing, so holding it would be noise about a contention
        // that cannot happen. `takesForeground` is PRO-0019's value, not a
        // second derivation of the same question.
        if demand.takesForeground {
            armContention(run: foregroundRun, because: "the batch takes the foreground")
        }
        var ending: RunHUDEnding = .completed

        for (index, step) in steps.enumerated() {
            // A person's own decision, read before each step and never during
            // one. Killing a step mid-flight would leave the application in a
            // state nobody can describe; the step in flight finishes settling
            // and the run stops before the next one. The refusal lands on the
            // first step that never ran, so everything already done is still
            // reported alongside it.
            if let halt = await haltCheckpoint(probe: { [weak self] in
                await self?.contentionProbe(run: foregroundRun, step: index)
            }) {
                let refusal = halt.refusal
                run.results.append(StepResult(index: index, step: step, ok: false, plane: nil,
                                              error: refusal, settle: nil, stateHash: nil,
                                              diff: nil, elapsedMs: 0))
                if let audit { auditStep(step, context: audit, ok: false, postStateHash: nil,
                                         reason: refusal.message) }
                run.failedAt = index
                ending = .stoppedByPerson
                break
            }

            // Resolved once and handed to every line about this step, so the
            // live line, the trail row and any refusal all name the same thing.
            let node = drawsHUD ? hudNode(for: step) : nil
            let synthetic = Self.isSynthetic(step)

            let refusal = Self.refusal(for: step, foreground: foreground)
            // The pointer travels before the clock starts, so the drawing does
            // not land inside the step's own elapsed time, and only for a step
            // that is actually going to run — animating toward something about
            // to be refused would show an action that never happened.
            if refusal == nil {
                await hud(.stepApproaching(step: step, node: node, synthetic: synthetic))
                await showCursor(for: step, window: window)
            }

            let started = DispatchTime.now().uptimeNanoseconds
            func elapsed() -> Int {
                Int((DispatchTime.now().uptimeNanoseconds &- started) / 1_000_000)
            }

            if let refusal {
                run.results.append(StepResult(index: index, step: step, ok: false, plane: nil,
                                              error: refusal, settle: nil, stateHash: nil,
                                              diff: nil, elapsedMs: elapsed()))
                if let audit { auditStep(step, context: audit, ok: false, postStateHash: nil,
                                         reason: refusal.message) }
                run.failedAt = index
                await hud(.stepRefused(step: step, node: node))
                ending = .blocked
                break
            }

            let outcome: Actuation
            do {
                await hud(.stepActing(step: step, node: node, synthetic: synthetic))
                // The grace window has to be open BEFORE the post, not after it.
                // An input monitor delivers asynchronously, so an event Proctor
                // posts at T can be considered before `perform` returns; opening
                // the window only afterwards would leave exactly that arrival
                // looking like a person's. Marked again after the step, from the
                // measured plane, to cover a late delivery.
                if synthetic { noteSyntheticPost() }
                outcome = try ax.perform(step: step, window: window.id, foreground: foreground)
            } catch let error as AgentError {
                run.results.append(StepResult(index: index, step: step, ok: false, plane: nil,
                                              error: error, settle: nil, stateHash: nil,
                                              diff: nil, elapsedMs: elapsed()))
                if let audit { auditStep(step, context: audit, ok: false, postStateHash: nil,
                                         reason: error.message) }
                run.failedAt = index
                await hud(.stepFailed(step: step, node: node))
                ending = .failed
                break
            } catch {
                let wrapped = AgentError(code: .actionFailed,
                                         message: "\(step.kind.rawValue) failed: \(error)",
                                         remedy: nil)
                run.results.append(StepResult(index: index, step: step, ok: false, plane: nil,
                                              error: wrapped, settle: nil, stateHash: nil,
                                              diff: nil, elapsedMs: elapsed()))
                if let audit { auditStep(step, context: audit, ok: false, postStateHash: nil,
                                         reason: wrapped.message) }
                run.failedAt = index
                await hud(.stepFailed(step: step, node: node))
                ending = .failed
                break
            }

            let plane = outcome.plane
            let policy = step.settle ?? settle
            let report = await settleNow(window: window, pid: app?.pid, policy: policy)

            var stateHash: String?
            var diff: SnapshotDiff?
            var postStateError: AgentError?
            do {
                let outcome = try walk(window: window.id)
                stateHash = outcome.hash
                if diffEach {
                    diff = SnapshotDiffer.diff(from: outcome.previous?.node, to: outcome.root,
                                               fromRevision: outcome.previous?.revision ?? 0)
                }
            } catch let error as AgentError {
                postStateError = error
            } catch {
                postStateError = AgentError(code: .internalError,
                                            message: "reading the post-state failed: \(error)")
            }

            // The action succeeded even when the post-state read did not — a
            // `close` step ends with no window to walk. Conflating the two would
            // report a working step as a failure, so the step stays ok and the
            // read failure is carried alongside it.
            run.results.append(StepResult(index: index, step: step, ok: true, plane: plane,
                                          error: postStateError, settle: report,
                                          stateHash: stateHash, diff: diff,
                                          elapsedMs: elapsed(), route: outcome.route))
            if let audit { auditStep(step, context: audit, ok: true, postStateHash: stateHash,
                                     reason: postStateError?.message) }
            run.completed += 1
            await hud(.stepSettled(step: step, node: node, settleMs: report.elapsedMs,
                                   plane: plane))
            foregroundStep(run: foregroundRun, plane: plane)
            // Measured, not predicted. Only now is there an application Proctor
            // has demonstrably put in front, so only now can "somebody moved it
            // to the back" mean anything — and a `type` that fell back to the
            // event stream arms the watch exactly as a click does, which is a
            // batch that turned out to contend and could not have been known to
            // in advance.
            if plane == .syntheticEvent {
                noteTookForeground(pid: app?.pid)
                armContention(run: foregroundRun, because: "a step travelled the event stream")
            }
            if let stateHash {
                run.finalHash = stateHash
                run.hashes.append(stateHash)
            }

            if captureEach {
                run.stepArtifacts.append(await captureForStep(index: index, window: window,
                                                              step: step, pointerMarks: pointerMarks))
            }
        }
        // The batch is over, whether it completed or broke early, so the
        // pointer has nothing left to point at and may fade on the short timer,
        // and the panel says how it ended and starts its own linger.
        await restCursor()
        await hud(.runEnded(ending))
        disarmContention(run: foregroundRun)
        run.yields = takeYieldRecords(run: foregroundRun)
        foregroundEnded(run: foregroundRun)
        return run
    }

    /// The AX signal is supplied per settle rather than held on the session:
    /// each wait counts notifications from the action that started it, so a
    /// tracker created here starts its clock in the right place.
    func settleNow(window: WindowHandle, pid: Int32?, policy: SettlePolicy) async -> SettleReport {
        let tracker = AXQuietTracker(ax: ax, app: window.app)
        let reflector = self.reflector
        return await settler.settle(
            window: window,
            policy: policy,
            axQuiet: { tracker.sample() },
            reflectorIdle: { pid.flatMap { reflector.isIdle(pid: $0) } })
    }

    private func captureForStep(index: Int, window: WindowHandle,
                                step: ActionStep, pointerMarks: Bool) async -> StepArtifact {
        do {
            var frame = try await capture.capture(window: window, to: nil, waitForComplete: true,
                                                  timeoutMs: 3000, scale: nil, tileHashes: false,
                                                  includeCursor: false)
            // Composite the marker at the point this step acted on, when asked. It
            // annotates the intended target, not a live cursor.
            if pointerMarks {
                frame.pointer = pointerOverlay(for: step, window: window, capture: frame)
            }
            return StepArtifact(step: index, capture: frame)
        } catch let error as AgentError {
            return StepArtifact(step: index, error: error)
        } catch {
            return StepArtifact(step: index, errorText: "\(error)")
        }
    }

    /// Refuse a synthetic-event step rather than quietly satisfying it. Both
    /// refusals exist because the silent alternative — activating the app, or
    /// posting an event that Secure Event Input swallows — produces a result
    /// that looks background-safe or successful and is neither.
    static func refusal(for step: ActionStep, foreground: Bool) -> AgentError? {
        guard syntheticKinds.contains(step.kind) else { return nil }

        // The foreground contradiction is checked first: it is a property of
        // the request, fixable by the caller, where Secure Event Input is a
        // property of the machine at this instant. Reporting the machine state
        // as the reason for a malformed request sends the caller after the
        // wrong thing.
        if !foreground {
            return AgentError(
                code: .invalidArguments,
                message: "step kind \(step.kind.rawValue) is injected as a synthetic event, which "
                       + "requires the target application to be frontmost, but foreground is false",
                remedy: "Set foreground: true for this batch, or express the step through the "
                      + "accessibility plane instead — press, setValue, focus, menu or type all reach "
                      + "background and other-Space windows without stealing focus.")
        }
        if Grants.secureEventInputActive() {
            return AgentError(
                code: .secureInputActive,
                message: "Secure Event Input is active, so a synthetic \(step.kind.rawValue) event "
                       + "cannot be delivered",
                remedy: "Secure Event Input blocks event injection but not the accessibility plane. "
                      + "An equivalent press or setValue step will work now. Otherwise close whatever "
                      + "holds secure input — a focused password field, or a terminal in secure "
                      + "keyboard entry mode — and retry.")
        }
        return nil
    }

    // MARK: - proctor_wait

    func wait(window id: String, condition: String, node: String?, find: FindPredicate?,
              value: JSONValue?, region: [Double]?, timeoutMs: Int,
              pollMs: Int) async throws -> JSONValue {
        let window = try windowHandle(id)
        let started = DispatchTime.now().uptimeNanoseconds
        let deadline = started &+ UInt64(max(timeoutMs, 0)) &* 1_000_000
        var notes: [String] = []
        var polls = 0

        var watch: (any QuietWatch)?
        var regionRect: Rect?
        if condition == "regionQuiet" {
            if let region {
                guard region.count == 4, region[2] > 0, region[3] > 0 else {
                    throw AgentError(
                        code: .invalidArguments,
                        message: "region must be [x, y, w, h] with a positive width and height",
                        remedy: "Coordinates are points relative to the window's top-left corner.")
                }
                regionRect = Rect(x: region[0], y: region[1], w: region[2], h: region[3])
                notes.append("Dirty area was measured inside the supplied region only, so quiet "
                           + "here means the region was quiet; the rest of the window may have "
                           + "been changing.")
            }
            watch = try? await capture.beginQuietWatch(window: window)
            if watch == nil {
                throw AgentError(
                    code: .captureFailed,
                    message: "regionQuiet needs a capture stream on \(id) and one could not be started",
                    remedy: "Confirm the Screen Recording grant with proctor_doctor.")
            }
        }
        defer { watch?.stop() }

        var observed: JSONValue = .null
        var held = false
        var quietFrames = 0
        var lastFrameCount = -1

        while true {
            polls += 1
            let (result, sample) = try evaluateWaitCondition(condition, window: id, node: node,
                                                             find: find, value: value, watch: watch,
                                                             region: regionRect,
                                                             quietFrames: &quietFrames,
                                                             lastFrameCount: &lastFrameCount)
            observed = sample
            if result {
                held = true
                break
            }
            if DispatchTime.now().uptimeNanoseconds >= deadline { break }
            try? await Task.sleep(nanoseconds: UInt64(max(pollMs, 10)) * 1_000_000)
        }

        let elapsedMs = Int((DispatchTime.now().uptimeNanoseconds &- started) / 1_000_000)
        var out: [String: JSONValue] = [
            "window": .string(id),
            "condition": .string(condition),
            "ok": .bool(held),
            "timedOut": .bool(!held),
            "elapsedMs": .number(Double(elapsedMs)),
            "polls": .number(Double(polls)),
            "observed": observed
        ]
        if let outcome = try? walk(window: id) {
            out["revision"] = .number(Double(outcome.revision))
            out["stateHash"] = .string(outcome.hash)
        }
        if !notes.isEmpty { out["notes"] = .array(notes.map { .string($0) }) }
        return .object(out)
    }

    private func evaluateWaitCondition(_ condition: String, window id: String, node: String?,
                                       find: FindPredicate?, value: JSONValue?,
                                       watch: (any QuietWatch)?, region: Rect?,
                                       quietFrames: inout Int,
                                       lastFrameCount: inout Int) throws -> (Bool, JSONValue) {
        switch condition {
        case "nodeExists", "nodeGone":
            let found = resolveNode(window: id, node: node, find: find)
            let exists = found != nil
            return (condition == "nodeExists" ? exists : !exists,
                    found?.summary ?? .object(["found": .bool(false)]))

        case "valueEquals", "valueContains":
            guard let found = resolveNode(window: id, node: node, find: find) else {
                return (false, .object(["found": .bool(false)]))
            }
            let observed = found.value
            let hit = condition == "valueEquals"
                ? JSONText.equal(observed, value)
                : JSONText.describe(observed).contains(JSONText.describe(value))
            return (hit, .object(["node": .string(found.id), "value": observed ?? .null]))

        case "enabled", "focused":
            guard let found = resolveNode(window: id, node: node, find: find) else {
                return (false, .object(["found": .bool(false)]))
            }
            let flag = condition == "enabled" ? found.enabled : found.focused
            return (flag == true, .object(["node": .string(found.id),
                                           condition: flag.map(JSONValue.bool) ?? .null]))

        case "regionQuiet":
            guard let watch else { return (false, .null) }
            let threshold = SettlePolicy.default.dirtyThreshold
            let wanted = SettlePolicy.default.quietFrames

            guard let region else {
                let sample = watch.poll()
                let delivered = sample.frames != lastFrameCount
                lastFrameCount = sample.frames
                quietFrames = quiet(delivered: delivered, dirty: sample.dirtyArea,
                                    status: sample.status, threshold: threshold,
                                    soFar: quietFrames)
                return (quietFrames >= wanted,
                        .object(["dirtyArea": .number(sample.dirtyArea),
                                 "scope": .string("window"),
                                 "status": .string(sample.status.rawValue),
                                 "quietFrames": .number(Double(quietFrames)),
                                 "frames": .number(Double(sample.frames))]))
            }

            let sample = watch.poll(region: region)
            guard let dirtyArea = sample.dirtyArea else {
                let error = sample.error ?? AgentError(
                    code: .internalError,
                    message: "the region could not be measured and no reason was recorded")
                // A caller-fixable geometry error will not come right by waiting,
                // so it is raised now rather than spent as a timeout. Anything
                // else — no frame yet, a stream that has not settled — may still
                // resolve, so the wait continues and carries the reason with it.
                // Either way the region is not reported as quiet: a region that
                // could not be measured is not a region that was quiet.
                if error.code == .invalidArguments { throw error }
                quietFrames = 0
                return (false, .object([
                    "measured": .bool(false),
                    "scope": .string("region"),
                    "region": region.json,
                    "regionPixels": sample.regionPixels?.json ?? .null,
                    "status": .string(sample.status.rawValue),
                    "frames": .number(Double(sample.frames)),
                    "error": (try? JSONValue.encode(error)) ?? .string(error.message)
                ]))
            }
            let delivered = sample.frames != lastFrameCount
            lastFrameCount = sample.frames
            quietFrames = quiet(delivered: delivered, dirty: dirtyArea, status: sample.status,
                                threshold: threshold, soFar: quietFrames)
            return (quietFrames >= wanted,
                    .object(["dirtyArea": .number(dirtyArea),
                             "scope": .string("region"),
                             "region": region.json,
                             "regionPixels": sample.regionPixels?.json ?? .null,
                             "status": .string(sample.status.rawValue),
                             "quietFrames": .number(Double(quietFrames)),
                             "frames": .number(Double(sample.frames))]))

        case "reflectorIdle":
            guard let window = windowsByIDLookup(id), let app = appHandle(forWindow: window),
                  let idle = reflector.isIdle(pid: app.pid) else {
                return (false, .object(["reflector": .string("unavailable")]))
            }
            return (idle, .object(["idle": .bool(idle)]))

        default:
            return (false, .object(["error": .string("unknown condition \(condition)")]))
        }
    }

    private func windowsByIDLookup(_ id: String) -> WindowHandle? { try? windowHandle(id) }

    /// One frame's contribution to a run of quiet ones. A poll with no new frame
    /// counts as quiet for the same reason it does in the settler: the stream
    /// delivers a frame when something changes and then goes silent, so reading
    /// the last frame's dirty area again would hold a wait open forever on a
    /// window that stopped moving before the wait started.
    private func quiet(delivered: Bool, dirty: Double, status: FrameStatus,
                       threshold: Double, soFar: Int) -> Int {
        if status == .stopped { return 0 }
        if !delivered { return soFar + 1 }
        if status == .idle { return soFar + 1 }
        return dirty <= threshold ? soFar + 1 : 0
    }

    /// Resolve a subject either by node id or by predicate. A predicate is what
    /// a caller has before the element exists, which is exactly the case a wait
    /// is for.
    func resolveNode(window id: String, node: String?, find: FindPredicate?) -> AXNode? {
        if let node, let resolved = try? ax.node(id: node) { return resolved }
        if let find, !find.isEmpty {
            return (try? ax.find(window: id, predicate: find, limit: 1))?.first
        }
        return nil
    }
}
