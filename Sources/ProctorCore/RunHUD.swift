import Foundation

// What the run HUD is showing, as a value.
//
// The panel is the surface a person reads to decide whether to stop a run, so
// what it says has to be derivable and checkable without a window. Everything
// here is pure: events in, a model out. `RunHUDPanel` in the agent renders this
// and nothing else, which is what keeps the wording, the counting and the state
// transitions testable when the drawing is not.
//
// Every word comes from `StepDescription`. There is deliberately no second
// wording table: the audit trail, the step records and this panel all describe a
// step the same way, and a panel that phrased things its own way would be a
// second thing to keep true.
//
// Design reference: `mocks/run-hud.html`, which is settled and binding. One live
// line at one type size — the verb carries the state, so there is no status chip
// and no second line. Every numeric slot is fixed-width. Accessibility is the
// normal plane and is never announced; a synthetic step says so in words, once.

/// The seven states the mock draws. `idle` is modelled because the reference
/// draws it and because the queue (PRO-0016) makes it reachable — this build
/// shows the panel only while a run is in flight, so nothing reaches it here.
public enum RunHUDPhase: String, Sendable, Equatable, CaseIterable {
    case idle, travelling, acting, blocked, paused, finished, error
}

/// The colour the run is currently wearing. One variable drives the character
/// bay, the rail and the emphasised words together, so the panel changes as one
/// object rather than in pieces.
public enum RunHUDTone: String, Sendable, Equatable {
    case accent   // vermilion — running
    case amber    // blocked
    case red      // error
    case green    // finished
    case quiet    // paused, idle, and a person's own stop
}

public extension RunHUDPhase {
    var tone: RunHUDTone {
        switch self {
        case .blocked: return .amber
        case .error: return .red
        case .finished: return .green
        case .paused, .idle: return .quiet
        case .acting, .travelling: return .accent
        }
    }
}

/// How a run ended. A person's own stop is not a fault and is not drawn as one.
public enum RunHUDEnding: String, Sendable, Equatable {
    case completed
    case stoppedByPerson
    case blocked
    case failed
}

public enum RunHUDEvent: Sendable {
    /// A batch is starting. `total` is known before the first step runs, which is
    /// what lets the counter and the rail mean anything — and so is how much of
    /// it will need the foreground, which is what lets the panel say so before
    /// the machine is taken rather than as it goes.
    case runBegan(total: Int, app: String?, foreground: ForegroundDemand = ForegroundDemand())
    /// Travelling to a step's target, before it actuates.
    case stepApproaching(step: ActionStep, node: AXNode?, synthetic: Bool,
                         stepsAside: Bool = false)
    /// Actuating it.
    case stepActing(step: ActionStep, node: AXNode?, synthetic: Bool,
                    stepsAside: Bool = false)
    /// It finished, with how long it took to settle and which plane it actually
    /// travelled — a `type` or `scroll` that fell back to the event stream is
    /// only knowable here, and the notice revises upward when one does.
    case stepSettled(step: ActionStep, node: AXNode?, settleMs: Int?,
                     plane: ActuationPlane? = nil)
    /// It was refused — a synthetic step with the app behind, a blocked app.
    case stepRefused(step: ActionStep, node: AXNode?)
    /// It failed or never settled.
    case stepFailed(step: ActionStep, node: AXNode?)
    /// A person pressed Pause; the step named is the one being held before.
    case paused(step: ActionStep?, node: AXNode?)
    /// Nobody pressed anything: the run noticed somebody using the machine and
    /// got out of the way. The same held state a person's Pause produces — quiet,
    /// resumable, not a fault — with the reason stated instead of the step.
    case yielded(reason: YieldReason)
    /// The contention cleared by itself and the run carries on.
    case unyielded
    case resumed
    case runEnded(RunHUDEnding)
    /// The linger is over and the panel goes.
    case lingerElapsed
}

/// What the queue bar shows, as a value.
///
/// The bar sits between the trail and the run controls and expands in place. It
/// is absent entirely when nothing is waiting — the queue costs nothing until
/// there is contention.
///
/// Two controls, and they are deliberately not the run's two. Pause and Stop act
/// on the run; Hold and Clear act on the list, live in its header, and never sit
/// beside the run controls or share a word with them. Calling both "pause" is
/// how somebody stops the wrong thing.
public struct RunQueueModel: Sendable, Equatable {

    /// One row in the expanded list. Every run the scheduler knows about except
    /// the one on the live line appears here — a run in another lane is not
    /// queued, and listing it as queued would understate what the scheduler can
    /// actually do — so a row is either running or waiting at a position.
    public struct Row: Sendable, Equatable {
        /// Its place in the line, or nil when it is already running.
        public var position: Int?
        public var session: String
        public var connection: String
        public var summary: String
        /// How long it has waited, `m:ss`, tabular where it is drawn.
        public var waited: String
        /// The scheduler's own id, so a drop removes the run a person pointed at
        /// rather than whatever is at that index a moment later.
        public var run: Int
        /// Whether this run is being held because somebody is using the machine.
        /// A mark rather than a sentence: the bar above already carries the
        /// reason once, and a row is one line at one size.
        public var held: Bool

        public init(position: Int?, session: String, connection: String,
                    summary: String, waited: String, run: Int, held: Bool = false) {
            self.position = position; self.session = session; self.connection = connection
            self.summary = summary; self.waited = waited; self.run = run; self.held = held
        }

        public var isWaiting: Bool { position != nil }
    }

    public var rows: [Row] = []
    /// Only the waiting ones. Counting the running ones would overstate how
    /// blocked the machine is.
    public var waitingCount: Int = 0
    public var held: Bool = false
    /// Whose the automatic hold is, when a run is being held because somebody is
    /// using the machine.
    ///
    /// Deliberately not the same thing as `held` above, which is a person having
    /// pressed Hold on the queue. One is a decision somebody made about what
    /// starts next; the other is Proctor getting out of somebody's way. They
    /// read differently because they are answered differently — Hold is released
    /// by pressing Hold again, a contention hold releases itself.
    public var hold: HoldAttribution?
    /// Whether the list is open. A person's choice, so it lives with the panel
    /// and is passed in rather than derived from the scheduler.
    public var expanded: Bool = false

    public init() {}

    /// Absent entirely when nothing is waiting — the queue costs nothing until
    /// there is contention — with two exceptions, and neither is decoration. A
    /// held queue starts nothing, and Hold lives inside this bar, so a bar that
    /// vanished when the last waiter left would hold the machine with no way on
    /// screen to release it: every later run would wait out its ceiling and
    /// nothing would say why. A contention hold is the same shape of problem
    /// read the other way — a run stopped for a reason nobody can see, on a
    /// machine that looks idle.
    public var visible: Bool { waitingCount > 0 || held || hold != nil }

    public var label: String {
        // Whose the hold is outranks how many are waiting, because it is the one
        // that explains why nothing is moving. The count is still a row away.
        if let hold { return hold.line }
        guard waitingCount > 0 else { return "Queue held — nothing will start" }
        return "\(waitingCount) session\(waitingCount == 1 ? "" : "s") waiting"
    }

    /// The button says what it is, and what it says changes when it is on. Never
    /// "pause".
    public var holdLabel: String { held ? "Held" : "Hold" }

    public static func waited(seconds: Double) -> String {
        let whole = max(0, Int(seconds))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }

    /// Fold a scheduler snapshot into the rows the panel draws. `live` is the run
    /// on the live line, which is shown there and not repeated in the list.
    public static func from(_ snapshot: RunQueueSnapshot, live: Int?, now: Double,
                            expanded: Bool) -> RunQueueModel {
        var out = RunQueueModel()
        out.held = snapshot.held
        out.expanded = expanded
        out.waitingCount = snapshot.waitingCount
        // At most one run can be held at a time — arming implies the batch takes
        // the foreground, which takes the exclusive global lane — so the first
        // one found is the one, and there is never a second reading to lose.
        out.hold = snapshot.active.compactMap(\.held).first
        let running = snapshot.active.filter { $0.id != live }.map { run in
            Row(position: nil, session: run.identity.project, connection: run.identity.connection,
                summary: run.summary, waited: waited(seconds: now - run.since), run: run.id,
                held: run.held != nil)
        }
        let queued = snapshot.waiting.enumerated().map { index, run in
            Row(position: index + 1, session: run.identity.project,
                connection: run.identity.connection, summary: run.summary,
                waited: waited(seconds: now - run.since), run: run.id,
                held: run.held != nil)
        }
        out.rows = running + queued
        return out
    }
}

public struct RunHUDModel: Sendable, Equatable {

    /// One finished step in the trail.
    public struct Row: Sendable, Equatable {
        public enum Outcome: String, Sendable, Equatable { case done, refused, failed }
        public var text: String
        /// How long it took to settle. Nil for a step that never ran to a settle,
        /// which the mock prints as an em dash.
        public var settleMs: Int?
        public var outcome: Outcome
        public init(text: String, settleMs: Int?, outcome: Outcome) {
            self.text = text; self.settleMs = settleMs; self.outcome = outcome
        }
    }

    public var phase: RunHUDPhase = .idle
    /// The single live line. One size, one row, never truncated — the cap lives
    /// in `StepDescription` at the source.
    public var line: String = ""
    public var completed: Int = 0
    public var total: Int = 0
    /// The three most recent finished steps, oldest first so the newest is at the
    /// bottom, as the reference draws it.
    public var trail: [Row] = []
    /// The exception, stated in words. Nil for a run that leaves the machine
    /// alone — the accessibility plane is the rule and is never announced, only
    /// the exception is. It says what the batch *contains* from the moment the
    /// run appears, and swaps to the present tense while such a step is
    /// actually in flight.
    public var exception: String?
    /// Whether the step being actuated *right now* travels the event stream.
    ///
    /// Separate from `exception` because the two answer different questions and
    /// only this one may gate the panel's mouse handling. `exception` is now
    /// non-nil for the whole of a batch that contains a synthetic step; a panel
    /// that ignored mouse events for as long as that text was on screen would
    /// leave Pause and Stop dead for the entire run.
    public var syntheticInFlight: Bool = false
    /// Whether the panel must let mouse events through to whatever is under it,
    /// which is the ONLY thing that may drive `ignoresMouseEvents`.
    ///
    /// Not the same question as `syntheticInFlight`, and PRO-0033 separated
    /// them because conflating the two cost the kill switch. That one is about
    /// the plane and drives the words on screen. This one is about the plane AND
    /// the geometry: the panel only has to move out of the way when the step is
    /// going to post at a point the panel occupies, because the reason the gate
    /// exists is that the window at the posted point wins. Everywhere else the
    /// panel stays live and Stop stays clickable through the step.
    public var stepsAside: Bool = false
    public var visible: Bool = false
    /// The queue bar's state. It belongs to the machine rather than to this run,
    /// so it survives a run beginning and ending.
    public var queue = RunQueueModel()
    /// Set when a run ends: how long the panel stays before it goes.
    public var lingerSeconds: Double?

    public init() {}

    public var tone: RunHUDTone { phase.tone }

    /// `3/7`, tabular and fixed-width at the point it is drawn, so a value change
    /// never moves its neighbour.
    public var counter: String { "\(completed)/\(total)" }

    public var progress: Double {
        total > 0 ? min(1, max(0, Double(completed) / Double(total))) : 0
    }

    /// The run control's own label. Pause and Resume are the same button; Hold
    /// and Clear belong to the queue and are never adjacent to these.
    public var pauseLabel: String { phase == .paused ? "Resume" : "Pause" }
}

/// The reducer. Sendable and valueless of any window.
public struct RunHUDState: Sendable {

    /// The reference draws three rows.
    public static let trailDepth = 3
    /// A run that finished or was stopped is read at a glance; one that ended
    /// blocked or in error is the ending somebody actually needs to read, and a
    /// three-second fade would take it away on an unattended machine.
    public static let quietLinger: Double = 3
    public static let loudLinger: Double = 15

    public private(set) var model = RunHUDModel()
    /// The app under test, for the synthetic-plane exception line.
    private var app: String?
    /// What this batch is going to do to the foreground, known before its first
    /// step runs. Held for the run so the notice can go back up after a step
    /// that was not itself synthetic.
    private var demand = ForegroundDemand()
    /// How many steps are now known to need the front. Starts at the demand's
    /// certain count and rises when a conditional step turns out to have fallen
    /// back, so the number on screen never lags what has already happened.
    private var knownForeground = 0
    /// How many conditional steps have run. Each one that has spends the doubt
    /// it carried, whichever plane it took, so the hedge on the wording comes
    /// off as the batch resolves rather than staying up to the last step.
    private var resolvedConditional = 0
    /// The step being held, so a pause can name what it is holding before.
    private var pending: (step: ActionStep, node: AXNode?)?

    public init() {}

    public mutating func apply(_ event: RunHUDEvent) {
        switch event {
        case .runBegan(let total, let app, let foreground):
            var fresh = RunHUDModel()
            fresh.total = max(0, total)
            fresh.visible = true
            fresh.phase = .travelling
            fresh.line = "Starting"
            // The queue is a property of the machine, not of this run: other
            // sessions are still waiting on the far side of a run beginning, and
            // a bar that emptied itself every time one started would be lying.
            fresh.queue = model.queue
            self.app = app
            self.demand = foreground
            self.knownForeground = foreground.certainSteps
            self.resolvedConditional = 0
            self.pending = nil
            // Before anything runs, and stated as what the batch contains rather
            // than as a prediction about what will happen. A batch can end before
            // it reaches its first synthetic step; it cannot stop containing one.
            fresh.exception = foreground.notice(app: app, known: knownForeground,
                                                resolvedConditional: resolvedConditional)
            model = fresh

        case .stepApproaching(let step, let node, let synthetic, let stepsAside):
            pending = (step, node)
            model.phase = .travelling
            model.line = StepDescription.line(for: step, node: node, timing: .prospective)
            setPlaneStatement(synthetic: synthetic, stepsAside: stepsAside)

        case .stepActing(let step, let node, let synthetic, let stepsAside):
            pending = (step, node)
            model.phase = .acting
            model.line = StepDescription.line(for: step, node: node, timing: .present)
            setPlaneStatement(synthetic: synthetic, stepsAside: stepsAside)

        case .stepSettled(let step, let node, let settleMs, let plane):
            pending = nil
            model.completed += 1
            // The gate closes here and not at the next step. The settle is the
            // signal that the events this step posted have landed and the
            // application has stopped moving, so the panel can take clicks again
            // — where holding the gate to the next step, which is what
            // `syntheticInFlight` does, leaves Stop dead across the settle and
            // the gap between steps, which is exactly when somebody reaches for
            // it. The statement is left alone: the words are about the plane and
            // the batch is not over.
            model.stepsAside = false
            // A `type` or `scroll` that could not be written through the
            // accessibility plane has just taken the machine, and nothing before
            // this moment could have known it would. Count it, so the notice
            // that goes back up says the larger, truer number.
            // Only a conditional step can move the number. A certain one was
            // already counted before the run and counting it again on its way
            // out would double it — the count is what is KNOWN to need the
            // front, not a tally of events posted.
            if demand.conditionalKinds.contains(step.kind) {
                resolvedConditional += 1
                if plane == .syntheticEvent {
                    knownForeground = min(knownForeground + 1, demand.totalSteps)
                }
            }
            push(RunHUDModel.Row(text: StepDescription.completedLine(for: step, node: node),
                                 settleMs: settleMs, outcome: .done))

        case .stepRefused(let step, let node):
            pending = nil
            model.syntheticInFlight = false
            model.stepsAside = false
            model.phase = .blocked
            model.line = StepDescription.line(for: step, node: node, outcome: .refused)
            push(RunHUDModel.Row(text: model.line, settleMs: nil, outcome: .refused))

        case .stepFailed(let step, let node):
            pending = nil
            model.syntheticInFlight = false
            model.stepsAside = false
            model.phase = .error
            model.line = StepDescription.line(for: step, node: node, outcome: .failed)
            push(RunHUDModel.Row(text: model.line, settleMs: nil, outcome: .failed))

        case .paused(let step, let node):
            model.phase = .paused
            let held = step.map { ($0, node) } ?? pending
            if let held, let object = StepDescription.objectText(for: held.0, node: held.1) {
                model.line = "Paused before \(object)"
            } else {
                model.line = "Paused"
            }

        case .resumed:
            model.phase = pending == nil ? .travelling : .acting
            if let pending {
                model.line = StepDescription.line(for: pending.step, node: pending.node,
                                                  timing: .present)
            }

        case .yielded(let reason):
            // The same held state Pause produces, and deliberately the same
            // phase: a person using their own Mac is not a fault, so it wears
            // the quiet tone and the Resume label rather than a new colour or a
            // second control. The line is the ask — Resume and Stop are its two
            // answers, and both are already on the panel.
            model.phase = .paused
            model.line = reason.line
            // Nothing is being posted while the run is held, and the panel's
            // mouse gate reads this: leaving it set would make Resume itself
            // unclickable, which is the one thing a held run must never be.
            model.syntheticInFlight = false
            model.stepsAside = false

        case .unyielded:
            model.phase = pending == nil ? .travelling : .acting
            if let pending {
                model.line = StepDescription.line(for: pending.step, node: pending.node,
                                                  timing: .present)
            } else {
                model.line = "Carrying on"
            }

        case .runEnded(let ending):
            pending = nil
            model.exception = nil
            model.syntheticInFlight = false
            model.stepsAside = false
            switch ending {
            case .completed:
                model.phase = .finished
                model.line = "Run complete"
                model.lingerSeconds = Self.quietLinger
            case .stoppedByPerson:
                // Grey, not red. Red is for something going wrong; this went
                // right — somebody decided, and the panel says so.
                model.phase = .paused
                model.line = "Stopped by a person"
                model.lingerSeconds = Self.quietLinger
            case .blocked:
                model.phase = .blocked
                model.lingerSeconds = Self.loudLinger
            case .failed:
                model.phase = .error
                model.lingerSeconds = Self.loudLinger
            }

        case .lingerElapsed:
            // Only an ending can be lingered away, and `lingerSeconds` is set by
            // exactly the four endings and cleared by the fresh model a new run
            // starts from. So this is "the run this timer was armed for is still
            // the run on screen".
            //
            // The panel already cancels the pending timer when a run begins, and
            // that covers the ordinary case. It cannot cover a timer that had
            // already been dequeued and was waiting its turn on the main queue
            // behind the very call that starts the next run: cancelling an item
            // that has begun does nothing. Without this guard that ordering
            // hides the panel a few milliseconds into a live run, which is a run
            // with no visible stop button — the one state this panel exists to
            // prevent. Cheap to refuse here, and it makes the reducer safe on its
            // own rather than only in company with a correct caller.
            guard model.lingerSeconds != nil else { break }
            model.visible = false
        }
    }

    /// The queue's state, pushed in rather than reduced from an event: it is the
    /// scheduler's business and changes whether or not this run does anything.
    public mutating func setQueue(_ queue: RunQueueModel) { model.queue = queue }

    private mutating func push(_ row: RunHUDModel.Row) {
        model.trail.append(row)
        if model.trail.count > Self.trailDepth {
            model.trail.removeFirst(model.trail.count - Self.trailDepth)
        }
    }

    /// The one thing the panel ever says about a plane, and it is only ever said
    /// about the exception. Two tenses of the same fact: what this batch
    /// contains, and — while one of those steps is actually being posted — that
    /// it is happening now.
    ///
    /// `syntheticInFlight` tracks exactly the window the present-tense line used
    /// to occupy on its own: open from the moment a synthetic step is approached,
    /// through its whole gesture, until the next step that is not one.
    ///
    /// `stepsAside` is the panel's mouse gate and is a DIFFERENT window — the
    /// step must also be about to post where the panel is standing, and it closes
    /// on the settle rather than at the next step. It is what the panel gates its
    /// mouse handling on, and nothing else may.
    private mutating func setPlaneStatement(synthetic: Bool, stepsAside: Bool = false) {
        model.syntheticInFlight = synthetic
        model.stepsAside = stepsAside
        model.exception = synthetic
            ? Self.exceptionLine(app: app)
            : demand.notice(app: app, known: knownForeground,
                            resolvedConditional: resolvedConditional)
    }

    /// The one sentence the panel ever says about a plane, and it is only ever
    /// said about the exception.
    public static func exceptionLine(app: String?) -> String {
        let who = StepDescription.sanitised(app) ?? "the app under test"
        return "Synthetic event — \(who) must stay in front"
    }
}
