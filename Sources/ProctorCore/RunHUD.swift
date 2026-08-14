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
    /// what lets the counter and the rail mean anything.
    case runBegan(total: Int, app: String?)
    /// Travelling to a step's target, before it actuates.
    case stepApproaching(step: ActionStep, node: AXNode?, synthetic: Bool)
    /// Actuating it.
    case stepActing(step: ActionStep, node: AXNode?, synthetic: Bool)
    /// It finished, with how long it took to settle.
    case stepSettled(step: ActionStep, node: AXNode?, settleMs: Int?)
    /// It was refused — a synthetic step with the app behind, a blocked app.
    case stepRefused(step: ActionStep, node: AXNode?)
    /// It failed or never settled.
    case stepFailed(step: ActionStep, node: AXNode?)
    /// A person pressed Pause; the step named is the one being held before.
    case paused(step: ActionStep?, node: AXNode?)
    case resumed
    case runEnded(RunHUDEnding)
    /// The linger is over and the panel goes.
    case lingerElapsed
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
    /// The exception, stated once, in words. Nil on the accessibility plane —
    /// the rule is never announced, only the exception is.
    public var exception: String?
    public var visible: Bool = false
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
    /// The step being held, so a pause can name what it is holding before.
    private var pending: (step: ActionStep, node: AXNode?)?

    public init() {}

    public mutating func apply(_ event: RunHUDEvent) {
        switch event {
        case .runBegan(let total, let app):
            var fresh = RunHUDModel()
            fresh.total = max(0, total)
            fresh.visible = true
            fresh.phase = .travelling
            fresh.line = "Starting"
            self.app = app
            self.pending = nil
            model = fresh

        case .stepApproaching(let step, let node, let synthetic):
            pending = (step, node)
            model.phase = .travelling
            model.line = StepDescription.line(for: step, node: node, timing: .prospective)
            model.exception = synthetic ? Self.exceptionLine(app: app) : nil

        case .stepActing(let step, let node, let synthetic):
            pending = (step, node)
            model.phase = .acting
            model.line = StepDescription.line(for: step, node: node, timing: .present)
            model.exception = synthetic ? Self.exceptionLine(app: app) : nil

        case .stepSettled(let step, let node, let settleMs):
            pending = nil
            model.completed += 1
            push(RunHUDModel.Row(text: StepDescription.completedLine(for: step, node: node),
                                 settleMs: settleMs, outcome: .done))

        case .stepRefused(let step, let node):
            pending = nil
            model.phase = .blocked
            model.line = StepDescription.line(for: step, node: node, outcome: .refused)
            push(RunHUDModel.Row(text: model.line, settleMs: nil, outcome: .refused))

        case .stepFailed(let step, let node):
            pending = nil
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

        case .runEnded(let ending):
            pending = nil
            model.exception = nil
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
            model.visible = false
        }
    }

    private mutating func push(_ row: RunHUDModel.Row) {
        model.trail.append(row)
        if model.trail.count > Self.trailDepth {
            model.trail.removeFirst(model.trail.count - Self.trailDepth)
        }
    }

    /// The one sentence the panel ever says about a plane, and it is only ever
    /// said about the exception.
    public static func exceptionLine(app: String?) -> String {
        let who = StepDescription.sanitised(app) ?? "the app under test"
        return "Synthetic event — \(who) must stay in front"
    }
}
