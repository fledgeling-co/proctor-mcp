import Foundation
import ProctorCore

// Actuation and waiting.

extension Session {

    /// The step kinds the NATIVE planes can only travel through CGEventPost. They
    /// enter the single WindowServer event stream, so they need the target
    /// foreground and they are what Secure Event Input blocks.
    ///
    /// Kept as a constant because it is a true description of Proctor's own
    /// actuator, which several places still reason about directly. It is no
    /// longer what the run consults: since PRO-0044 the question is asked of the
    /// selected backend, because "a click needs the foreground" is a fact about
    /// this actuator rather than about clicking, and a delegated backend that
    /// routes an event to one process answers differently.
    static let syntheticKinds: Set<ActionStep.Kind> = [.dragPath, .hover, .click, .key]

    /// The kinds that *may* end up there. Both prefer the accessibility plane
    /// and fall to a synthetic event only when the element refuses — `type` into
    /// a field whose value cannot be set, `scroll` with no scroll action to
    /// perform. That is a property of the element, so it is not knowable until
    /// the step is reached, which is why an up-front disclosure counts these
    /// separately and a finished run reports what actually travelled.
    static let conditionalKinds: Set<ActionStep.Kind> = [.type, .scroll]

    /// The kinds the SELECTED backend can only deliver through the shared event
    /// stream, and the ones it decides at the element.
    ///
    /// One walk of the step kinds, answered by the backend. For the native
    /// backend these are byte-identical to the two constants above, so nothing
    /// about a native run changes; for a delegated one they are what stops a
    /// background-capable click being refused before it is ever attempted.
    var backendSyntheticKinds: Set<ActionStep.Kind> {
        Set(ActionStep.Kind.allCases.filter {
            actuator.backgroundCapability(for: $0) == .never
        })
    }

    var backendConditionalKinds: Set<ActionStep.Kind> {
        Set(ActionStep.Kind.allCases.filter {
            actuator.backgroundCapability(for: $0) == .maybe
        })
    }

    /// What this batch will do to the foreground, from its own steps and from
    /// what the selected backend can do with them, before any of them runs. One
    /// value, read by the scheduler, the panel and the menu bar alike.
    func foregroundDemand(for steps: [ActionStep], foreground: Bool) -> ForegroundDemand {
        ForegroundDemand.forBatch(kinds: steps.map(\.kind), synthetic: backendSyntheticKinds,
                                  conditional: backendConditionalKinds, foreground: foreground)
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
        /// What the run said on the screen, and whether it held the machine.
        /// Nil when it drew nothing.
        var takeover: TakeoverReport?
        /// Which of two pointers drew for this run. Decided once, from this
        /// run's own backend, so a concurrent run on the other lane cannot flip
        /// it mid-batch.
        var pointerOwner: PointerOwner = .proctor

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
        let demand = await lanes(for: steps, window: window, foreground: foreground)
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

        let demandForReport = foregroundDemand(for: steps, foreground: foreground)
        let result = ActResult(window: id, steps: run.results, completed: run.completed,
                               failedAt: run.failedAt, finalHash: run.finalHash,
                               foreground: ForegroundReport.from(demandForReport,
                                                                 results: run.results),
                               yields: run.yields.isEmpty ? nil : run.yields,
                               takeover: run.takeover,
                               // Unconditionally, including a run in which nothing
                               // actuated: those steps carry no backend of their own,
                               // so this is the only thing that says which lane
                               // refused them.
                               backend: actuator.id,
                               // Nil when Proctor drew, which is every native run
                               // and every delegated one whose driver could be
                               // asked to stand down — so an existing result
                               // encodes exactly as it did before this existed.
                               pointerDrawnBy: run.pointerOwner == .proctor
                                   ? nil : run.pointerOwner.rawValue)
        var out = try JSONValue.encode(result).objectValue ?? [:]
        // One sentence beside the records, so a caller reading prose knows why
        // the run took longer than its work did. Alongside rather than inside,
        // exactly as `captures` and `browser` already ride alongside.
        if let note = YieldRecord.note(for: run.yields) { out["yieldNote"] = .string(note) }
        // And the same for the foreground, which is where a `foreground: true`
        // nothing could use gets said in words. The flag is in the block; the
        // sentence is what a caller reading prose actually reads, and without
        // this it had no surface on `act` at all.
        if let note = result.foreground?.note { out["foregroundNote"] = .string(note) }
        // And the same again for the machine having been taken visibly, and
        // perhaps held. Alongside rather than inside, exactly as the other two.
        if let note = run.takeover?.note { out["takeoverNote"] = .string(note) }
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
                                        targets: browserTargets(for: steps, window: window),
                                        tool: "proctor_act") {
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
        let demand = foregroundDemand(for: steps, foreground: foreground)
        await hudRunBegan(total: steps.count, window: window, demand: demand,
                          delegated: actuator.id != .native)
        // The same fact, reachable without the panel: the menu bar mirrors this
        // and is on every display, where the panel is on one.
        let foregroundRun = foregroundBegan(demand: demand, app: app?.name,
                                            window: window.frame)
        // A run that is going to take the machine watches for the person whose
        // machine it is. One that is not never arms anything: an accessibility
        // run takes nothing, so holding it would be noise about a contention
        // that cannot happen. `takesForeground` is PRO-0019's value, not a
        // second derivation of the same question.
        if demand.takesForeground {
            armContention(run: foregroundRun, because: "the batch takes the foreground")
        }
        // The block reaches this run's latch rather than a stale one, and the
        // statement starts down however the last run ended.
        takeoverShown = false
        takeoverBind()
        // What the actuator says the moment it is about to enter the event
        // stream, rather than what it reports when `perform` returns. Two
        // consumers could not have known before this existed, and both were
        // wrong about a `type` or `scroll` that fell back: the grace window,
        // which without this never opened for a fallback post at all — so the
        // application's echo of Proctor's own wheel event could read as a person
        // and yield the run — and the statement on the screen, which went up
        // only once the step had settled, claiming the machine after it was
        // taken. It is called on the actuation thread with a post about to
        // happen, so it touches only lock-guarded state and hands the drawing
        // over without waiting for it.
        let monitor = contentionMonitor
        let driver = takeover
        let declaredApp = app?.name
        // ONLY A RUN THAT MIGHT POST TOUCHES THE DECLARATION PROTOCOL, and this
        // is the invariant that makes the rest of it safe rather than lucky.
        //
        // `SyntheticPost` is process-wide, and it must be: the event tap has to
        // decline to read Stop while ANY post is open, whoever opened it. What
        // was wrong is that every run drove it, including runs that could never
        // post. Two sessions on different apps run genuinely in parallel — see
        // `RunLane` — so a background run's `beginStep()` at its own step
        // boundary cleared the posting run's state underneath it: `declared`, so
        // the poster never raised the statement for a `type` or `scroll` that
        // fell back and under-reported having taken the machine (PRO-0026); and
        // `declaredAt`, so the in-flight window closed early and the tap went
        // back to reading the Stop rectangle while Proctor's own click was still
        // travelling (PRO-0033). The single handler slot had the same shape.
        //
        // `mightPost` is the scheduler's own predicate, not a second derivation:
        // a batch that might post takes the exclusive `.global` lane, and there
        // is one `Session` in production and therefore one scheduler. So at most
        // one run at a time is inside this protocol, which is exactly the scope
        // the shared instance already assumes.
        //
        // AND `foreground`, which is not redundant. `mightPost` counts a certain
        // synthetic kind whatever the batch asked for, but `refusal(for:
        // foreground:)` above turns away every synthetic step when `foreground`
        // is false, so such a batch is refused before it can post and has
        // nothing to declare. Without this half the invariant has a hole on one
        // real path: a stability sweep buys its lanes from the FLOW's steps, then
        // runs `resetBetween` through here as its own batch. An accessibility-only
        // flow takes no global lane, so a reset containing a `click` would have
        // joined the protocol holding nothing exclusive and cleared a genuine
        // poster's state — the very defect this gate exists to close.
        //
        // AND THE BACKEND, which PRO-0046 adds and which is that rule stated at
        // its actual width. The predicate above was "the runs that can post";
        // a delegated run cannot, because `SyntheticPost.declare()` is reached
        // only from `Actuator.requireEventPlaneAvailable()` and another process
        // does the posting. Left in, such a run would install a handler nothing
        // can fire and clear `declaredAt`/`declared` at every step boundary while
        // having nothing of its own to record there. What recognises a delegated
        // actuation instead is `DelegatedPost`, which touches none of this.
        let participates = demand.mightPost && foreground && actuator.id == .native
        if participates {
            syntheticPost.onDeclare {
                monitor.noteSyntheticPost()
                driver.show(app: declaredApp)
            }
        }
        defer { if participates { syntheticPost.onDeclare(nil) } }
        // Which of two pointers draws, decided ONCE for this run rather than
        // consulted per step. Two runs on different applications genuinely
        // overlap, so a machine-wide decision would flip between a native run's
        // step and a delegated one's — which is how a pointer ends up annotating
        // the wrong action, or two end up on one screen.
        let delegatedLane = actuator.id != .native
        let pointerOwner = PointerOwnership.decide(
            delegated: delegatedLane,
            driverSuppressible: await actuator.cursorSuppressible)
        run.pointerOwner = pointerOwner
        // The pid whose events the guards should treat as this run's own doing,
        // read once for the batch. Nil is not a failure — it is what made this
        // batch take the exclusive lane, so nothing else is holding the block.
        let delegatedPid = delegatedLane ? await actuator.actuatingPid : nil
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
                if let audit { auditStep(step, context: audit,
                                         outcome: AuditRecord.Outcome.failed,
                                         postStateHash: nil,
                                         reason: refusal.message, seq: index, ms: 0) }
                run.failedAt = index
                ending = .stoppedByPerson
                break
            }

            // Resolved once and handed to every line about this step, so the
            // live line, the trail row and any refusal all name the same thing.
            let node = drawsHUD ? hudNode(for: step) : nil
            let capability = actuator.backgroundCapability(for: step.kind)
            let synthetic = capability == .never
            // Whether this panel is standing where this step is about to post.
            // The plane and the geometry together, which is the whole of
            // PRO-0033: the gate exists because the window at a posted point
            // wins, so a step posting anywhere else leaves Stop clickable
            // throughout. A `type` or `scroll` picks its plane at the element,
            // so it is taken as possible here and the pessimism is confined to
            // the case where being wrong costs anything — the target lying under
            // the panel.
            let mayPost = capability != .yes
            let stepsAside = mayPost && RunHUDGate.stepsAside(
                points: gatePoints(for: step), panel: RunHUDGeometry.shared.panelFrame)
            if participates { syntheticPost.beginStep() }

            let refusal = Self.refusal(for: step, foreground: foreground,
                                       capability: capability)
            // The pointer travels before the clock starts, so the drawing does
            // not land inside the step's own elapsed time, and only for a step
            // that is actually going to run — animating toward something about
            // to be refused would show an action that never happened.
            if refusal == nil {
                await hud(.stepApproaching(step: step, node: node, synthetic: synthetic,
                                           stepsAside: stepsAside))
                // The statement goes up before the first event is posted, on
                // every display, and stays up for the rest of the batch.
                if synthetic || stepsAside { takeoverShow(app: app?.name) }
                await showCursor(for: step, window: window, owner: pointerOwner)
            }

            let started = DispatchTime.now().uptimeNanoseconds
            func elapsed() -> Int {
                Int((DispatchTime.now().uptimeNanoseconds &- started) / 1_000_000)
            }

            if let refusal {
                run.results.append(StepResult(index: index, step: step, ok: false, plane: nil,
                                              error: refusal, settle: nil, stateHash: nil,
                                              diff: nil, elapsedMs: elapsed()))
                if let audit { auditStep(step, context: audit,
                                         outcome: AuditRecord.Outcome.failed,
                                         postStateHash: nil,
                                         reason: refusal.message, seq: index, ms: elapsed(),
                                         node: node) }
                run.failedAt = index
                await hud(.stepRefused(step: step, node: node))
                ending = .blocked
                break
            }

            let outcome: Actuation
            // The state before the step, read only when something else is going
            // to perform it. A delegated backend can report that it suspects its
            // action did nothing, and that claim is worth little on its own —
            // crossed with an independent before-and-after reading from Proctor's
            // own tree it becomes two observers agreeing. The native backend
            // reports no effect and judges its writes by reading them back, so it
            // pays nothing for this.
            let hashBefore = actuator.id == .native ? nil : stateHashNow(window: window.id)
            do {
                // Awaited, and that await is load-bearing rather than
                // stylistic: it is the hop to the main actor that applies the
                // panel's mouse gate, and it has to complete before the post
                // below or the panel is still opaque when Proctor's own click
                // arrives at it.
                await hud(.stepActing(step: step, node: node, synthetic: synthetic,
                                      stepsAside: stepsAside))
                // The grace window has to be open BEFORE the post, not after it.
                // An input monitor delivers asynchronously, so an event Proctor
                // posts at T can be considered before `perform` returns; opening
                // the window only afterwards would leave exactly that arrival
                // looking like a person's. Marked again after the step, from the
                // measured plane, to cover a late delivery.
                //
                // NOT WIDENED TO THE DELEGATED LANE, and that is a decision
                // rather than an omission. A time window is not an identity: if
                // the driver's events ever arrived looking like hardware, the
                // window would stop the run YIELDING while the pass rule still
                // swallowed them, so the step would fail with the one signal
                // that explains it switched off. And `ContentionMonitor` is a
                // singleton, so a delegated batch of fast steps would hold the
                // window open continuously and blind a CONCURRENT native run's
                // input signal — the cross-run clobber PRO-0053 fixed. What
                // covers the delegated lane is `DelegatedPost`, below.
                if synthetic || stepsAside {
                    noteSyntheticPost()
                }
                // Armed before the post and released after it, whatever the
                // step did. Arming follows the GATE rather than the step's
                // kind, so the armed window is never narrower than the window
                // the panel is transparent for — a gate open wider than the
                // block is this feature's own hole in miniature, with the
                // panel letting a click through and nothing holding it.
                //
                // On the delegated lane it follows the STATEMENT instead, once
                // one has been raised. Nothing on that lane is knowable in
                // advance — every kind decides at the element — so there is no
                // gate to follow, and the safe direction once the machine has
                // demonstrably been taken is to hold. The pairing is unchanged:
                // one arm here, one release in the `defer`.
                let armsThisStep = synthetic || stepsAside || (delegatedLane && takeoverShown)
                if armsThisStep { takeoverArm(for: step) }
                // A delegated actuation is about to happen, so the guards can
                // tell the driver's own events from a person's for as long as it
                // lasts. Opened BEFORE the request goes out: an event posted
                // between the request leaving and this opening would be read as
                // foreign, swallowed by an armed block, and reported to the
                // contention monitor as somebody using the machine.
                let delegation = delegatedLane
                    ? DelegatedPost.shared.begin(pid: delegatedPid) : nil
                defer {
                    if let delegation { DelegatedPost.shared.end(delegation) }
                    if armsThisStep { takeoverRelease(.stepEnded) }
                    // Closed however the step ended, including a throw between
                    // the declaration and here.
                    if participates { syntheticPost.endStep() }
                }
                outcome = try await actuator.perform(
                    step: step,
                    target: stepTarget(step, window: window, app: app),
                    foreground: foreground)
            } catch let error as AgentError {
                // The backend's own judgment, carried on the error. Never a code
                // match: only the thing that failed knows whether its request may
                // already have been delivered, and a code can arrive from another
                // domain — including from the native backend, whose throws always
                // do mean nothing was posted.
                if let event = error.lane, audit != nil { auditLane(event) }
                // With the backend gone, Proctor's own reading of the window is
                // the only evidence left about what the machine did — so it is
                // taken here, on a path that has already failed, rather than
                // skipped. It is evidence and not proof: an event the driver had
                // already posted can land after this walk, which is part of why
                // the row stays indeterminate rather than being resolved by it.
                let after = error.indeterminate ? stateHashNow(window: window.id) : nil
                let observed = error.indeterminate
                    ? Self.observation(before: hashBefore, after: after) : nil
                run.results.append(StepResult(index: index, step: step, ok: false, plane: nil,
                                              error: error, settle: nil, stateHash: after,
                                              diff: nil, elapsedMs: elapsed()))
                if let audit {
                    auditStep(step, context: audit,
                              outcome: error.indeterminate
                                  ? AuditRecord.Outcome.indeterminate
                                  : AuditRecord.Outcome.failed,
                              postStateHash: after, reason: error.message,
                              seq: index, ms: elapsed(), node: node,
                              observation: observed)
                }
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
                if let audit { auditStep(step, context: audit,
                                         outcome: AuditRecord.Outcome.failed,
                                         postStateHash: nil,
                                         reason: wrapped.message, seq: index, ms: elapsed(),
                                         node: node) }
                run.failedAt = index
                await hud(.stepFailed(step: step, node: node))
                ending = .failed
                break
            }
            // Written before the step's own row so the trail reads in causal
            // order: the lane opened, then the step it opened for.
            if audit != nil { for event in outcome.laneEvents { auditLane(event) } }

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
            //
            // A delegated backend adds a second reason a step might not have
            // worked, and it is the one this whole product exists to catch: the
            // driver itself suspecting it did nothing. That claim is crossed with
            // an independent reading of the window taken before and after, and
            // only when both observers agree does the step stop being a success.
            let noOp = Self.noOpVerdict(outcome, before: hashBefore, after: stateHash)
            var result = StepResult(index: index, step: step, ok: noOp == nil, plane: plane,
                                    error: noOp ?? postStateError, settle: report,
                                    stateHash: stateHash, diff: diff,
                                    elapsedMs: elapsed(), route: outcome.route)
            result.carry(outcome)
            run.results.append(result)
            if let audit {
                let observed = Self.observation(before: hashBefore, after: stateHash)
                auditStep(step, context: audit,
                          outcome: noOp == nil ? AuditRecord.Outcome.ok
                                               : AuditRecord.Outcome.failed,
                          postStateHash: stateHash,
                          reason: (noOp ?? postStateError)?.message
                              // A passing row still says so when the two observers
                              // point different ways. Without this the outcome
                              // people filter on is silent about an over-claiming
                              // driver, and the disagreement is only reachable by
                              // crossing two fields nobody queries.
                              ?? Self.disagreement(outcome, observed),
                          seq: index,
                          ms: elapsed(), plane: plane, node: node,
                          actuation: outcome,
                          // The verdict above is the crossing of these two; they
                          // are persisted beside it so a reader can audit the
                          // crossing rather than trust it. There is deliberately
                          // no third field restating it.
                          observation: observed)
            }

            // A step nothing can show happened stops the batch, exactly as any
            // other failed step does. Continuing would run the rest of a plan on
            // a machine that is not in the state the plan assumes.
            if noOp != nil {
                run.failedAt = index
                await hud(.stepFailed(step: step, node: node))
                ending = .failed
                break
            }
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
            if participates, syntheticPost.declaredThisStep { takeoverShown = true }
            if plane == .syntheticEvent {
                // A `type` or `scroll` that fell back could not be known to need
                // the front until now. The statement goes up late rather than
                // not at all: the batch has more steps in it.
                takeoverShow(app: app?.name)
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
        // Both halves come down with the run, whatever the step-level accounting
        // says and whether the run completed, broke or was stopped.
        run.takeover = takeoverEnd(stopped: ending == .stoppedByPerson)
        await hud(.runEnded(ending))
        await disarmContention(run: foregroundRun)
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
    ///
    /// `capability` is the selected backend's answer for this kind, not a lookup
    /// in a table of kinds. The refusal below is only correct when the step
    /// genuinely cannot be delivered without the front; asserting that of a
    /// backend that can would refuse the very steps delegation exists to make
    /// possible.
    static func refusal(for step: ActionStep, foreground: Bool,
                        capability: BackgroundCapability) -> AgentError? {
        guard capability == .never else { return nil }

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

    /// What to hit, described so any backend can act on it.
    ///
    /// Resolved here, from Proctor's own tree, rather than inside a backend. That
    /// is the whole architecture of wave 7 in one function: observation did not
    /// move, so Proctor remains the thing that knows what an element is, and a
    /// backend is told what to strike rather than asked what is there.
    func stepTarget(_ step: ActionStep, window: WindowHandle,
                    app: AppHandle?) -> StepTarget {
        StepTarget(window: window, app: app, nodeId: step.node,
                   identity: step.node.flatMap { identity(ofNode: $0, window: window) })
    }

    /// The element's identity, as far as a second observer could also see it.
    ///
    /// Only computed for a delegated backend: the native one holds a retained
    /// `AXUIElement` that resolves across Spaces and occlusion, which is strictly
    /// better than any re-resolution, so paying for a tree search to hand it a
    /// description it will not read would be pure cost.
    func identity(ofNode id: String, window: WindowHandle) -> ElementIdentity? {
        guard actuator.id != .native else { return nil }
        // Read rather than walk, for the same reason `stateHashNow` does: the
        // session's revision line records what the window looked like after each
        // step, and resolving a target is not a step.
        let options = SnapshotOptions()
        guard let (root, _) = try? ax.snapshot(window: window.id, root: nil,
                                               maxDepth: options.maxDepth,
                                               maxNodes: options.maxNodes,
                                               includeInvisible: options.includeInvisible)
        else { return nil }
        return ElementIdentity.of(nodeID: id, in: root)
    }

    /// Did two independent observers agree that nothing happened?
    ///
    /// A backend suspecting its own no-op is a claim, and Proctor's unchanged
    /// state hash is a measurement; either alone is weak, and together they are
    /// the strongest thing a delegated step can say about itself. Only their
    /// agreement fails the step.
    ///
    /// The asymmetry is deliberate. A driver that suspects a no-op while the tree
    /// visibly moved has under-reported its own success, and failing that step
    /// would turn a working run red. A driver that suspects a no-op and is right
    /// must not report `ok: true`, because every existing reader checks `ok` and
    /// would see a success — the same defect as adding a field nobody reads.
    /// Proctor's own reading of the window across a step, from two hashes it took
    /// itself.
    ///
    /// Nil in, nil out — which is what keeps the native path free of this. Native
    /// takes no before-hash (`hashBefore` is read only for a non-native backend),
    /// so a native row carries no observation rather than one manufactured from
    /// the previous step's post-state, which would measure a different interval
    /// under the same name.
    ///
    /// Read the result narrowly wherever it is used: this is the accessibility
    /// tree as Proctor walked it, not the machine. A canvas repaint can leave the
    /// tree identical and an animation can move it for no reason, so `changed` is
    /// evidence rather than proof in both directions.
    static func observation(before: String?, after: String?) -> AuditRecord.Observation? {
        guard let before else { return nil }
        guard let after else { return .unread }
        return before == after ? .unchanged : .changed
    }

    /// The sentence a row gets when the driver's claim and Proctor's own reading
    /// point different ways, but not far enough apart to fail the step.
    ///
    /// The step stays `ok`, and it should: a `hover` moves nothing, a `focus` onto
    /// an already-focused element moves nothing, so failing every step whose tree
    /// did not change would be a false negative across most of the vocabulary.
    /// But "the driver said it worked and Proctor saw nothing move" is exactly the
    /// row somebody investigating a flaky run wants, and leaving it reconstructable
    /// only by crossing two fields means the outcome people actually filter on
    /// stays silent about it. So the disagreement is written down in words.
    static func disagreement(_ outcome: Actuation,
                             _ observation: AuditRecord.Observation?) -> String? {
        guard outcome.backend != .native, observation == .unchanged else { return nil }
        switch outcome.effect {
        case .confirmed:
            return "the backend reported this step confirmed, and Proctor's own reading of the "
                 + "window is unchanged. The step is not failed on that alone, because a step "
                 + "can legitimately move nothing, but the two observers do not agree."
        case .unverifiable:
            return "the backend could not verify this step landed, and Proctor's own reading of "
                 + "the window is unchanged. Nothing here establishes that anything happened."
        default:
            return nil
        }
    }

    static func noOpVerdict(_ outcome: Actuation, before: String?,
                            after: String?) -> AgentError? {
        guard outcome.effect == .suspectedNoOp else { return nil }
        guard let before, let after, before == after else { return nil }
        return AgentError(
            code: .actionNoOp,
            message: "the actuation backend reported that this step probably did nothing, and "
                   + "the window's accessibility state is unchanged, so two independent "
                   + "observers agree nothing happened",
            remedy: "This is the silent-failure case a delegated driver documents for itself — "
                  + "a minimized window swallowing a keyboard commit, or a canvas surface with "
                  + "no accessibility target under the point. Raise the window, or express the "
                  + "step against an element rather than a coordinate.",
            detail: .object(["reportedMode": .string(outcome.reportedMode ?? ""),
                             "stateHash": .string(after)]))
    }

    /// The window's state hash right now, without touching the revision line.
    ///
    /// Deliberately not `walk(window:)`. That one is the session's record of
    /// what the window looked like after each step: it advances the revision and
    /// appends to history when the hash moves, and the diff a caller asks for is
    /// computed against its previous entry. Reading it a second time per step,
    /// only on the delegated path, would make `diffEach` mean something subtly
    /// different depending on which backend was selected. This reads the same
    /// tree and hashes it, and records nothing.
    func stateHashNow(window id: String) -> String? {
        let options = SnapshotOptions()
        guard let (root, _) = try? ax.snapshot(window: id, root: nil,
                                               maxDepth: options.maxDepth,
                                               maxNodes: options.maxNodes,
                                               includeInvisible: options.includeInvisible)
        else { return nil }
        return Canonical.hash(root)
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
