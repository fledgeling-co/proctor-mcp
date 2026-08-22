import Foundation

// Is a person using this Mac while Proctor drives it?
//
// A run that posts synthetic events holds the one WindowServer event stream the
// person's own keyboard and mouse go into. While it does, the person is fighting
// it: they click, the run clicks somewhere else. This is the value that decides
// the machine is contended, so that the run can hold on the latch a person's own
// Pause already uses.
//
// EVERYTHING HERE IS A PURE VALUE. The AppKit half — the frontmost cache and the
// optional input monitor — lives in the agent and holds no policy at all, which
// is what makes the interesting part testable without a window server.
//
// The failure that matters is not missing a person. It is Proctor reading its
// OWN events as somebody else's and pausing itself forever, which would halt
// every synthetic run on its first step. Three independent filters keep them
// apart, and each fails toward "this was ours":
//
//   1. WHAT HARDWARE LOOKS LIKE. Measured on 2026-08-14: an event Proctor posts
//      carries Proctor's own pid in `.eventSourceUnixProcessID`, and a real
//      hardware event carries 0. So a person's input is not "an event that is
//      not ours" — it is an event that came from the hardware. Anything with a
//      pid on it came from some process, and a process using the machine is not
//      a person taking it back. Stating the rule the other way round is the
//      inversion this comment exists to prevent: it compiles, it passes a test
//      written against it, and in production it reads the driven application's
//      own echoes as a person and never lets go.
//   2. OUR TAG. Every `CGEventSource` the actuator builds carries
//      `ProctorEventTag.value` in its user data, and it survives to the event
//      (measured, same date). Independent of (1), so a macOS that stops
//      attributing a pid does not silently switch the separation off.
//   3. A GRACE WINDOW. An input monitor delivers asynchronously, and an
//      application can emit its own events in response to one of ours. Anything
//      arriving within `graceSeconds` of Proctor's last synthetic post is
//      discarded whatever it looks like.
//
// What does NOT separate them, and was measured rather than assumed:
//   `CGEventSource.secondsSinceLastEventType(.hidSystemState, …)` is reset by
//   Proctor's own posts (3.108s → 0.298s across one posted mouseMoved), so the
//   cheap idle timer cannot be used at all, and
//   `.eventSourceStateID` reads 1 for a posted event exactly as it does for
//   hardware, so the source's state id cannot be used either.

/// Why a run is being held. Declaration order is precedence: when more than one
/// holds at once, the earlier one is the one the panel names.
///
/// Secure input first because it is the sharpest — a password field has focus,
/// which is the one moment injected keystrokes are least welcome. Then a
/// person's own hand, which is an observation rather than an inference. Then the
/// frontmost reading, which is the weakest: it says what happened to the front,
/// not who did it.
public enum YieldReason: String, Codable, Sendable, CaseIterable {
    case secureInput
    case userInput
    case frontmostChanged

    /// The panel's one line. One size, one row, in the settled vocabulary: a
    /// person using their own Mac is not a fault and is not worded as one.
    public var line: String {
        switch self {
        case .secureInput: return "Paused — secure keyboard entry is on"
        case .userInput: return "Paused — you used the keyboard or mouse"
        case .frontmostChanged: return "Paused — you moved to another app"
        }
    }

    /// What the audit trail and the result record say.
    public var detail: String {
        switch self {
        case .secureInput:
            return "the run was held because Secure Event Input turned on, which means a password "
                 + "field somewhere has focus"
        case .userInput:
            return "the run was held because somebody used the keyboard or mouse while it was "
                 + "posting synthetic events"
        case .frontmostChanged:
            return "the run was held because the application Proctor brought to the front is no "
                 + "longer in front"
        }
    }
}

/// The tag every event Proctor posts carries, so an input monitor can throw its
/// own back. Arbitrary and constant; its only property is that nothing else
/// writes it.
public enum ProctorEventTag {
    public static let value: Int64 = 0x5052_4F43_544F_5200   // "PROCTOR\0"
}

/// One reading of the machine. Everything the decision needs and nothing that
/// only means something to AppKit.
public struct ContentionSample: Sendable, Equatable {
    /// The pid Proctor has DEMONSTRABLY put in front — set from a step whose
    /// reported plane was `syntheticEvent`, or a settled `raise`, never from a
    /// prediction. Nil until then, and while it is nil there is nothing to take
    /// back, so the frontmost reading cannot fire.
    public var expectedPid: Int32?
    /// What is in front now.
    public var frontmostPid: Int32?
    /// Proctor's own processes. The agent and the menu-bar app are not a person
    /// taking the machine; somebody reaching for Pause must not trip the very
    /// thing they are reaching for.
    public var proctorPids: Set<Int32>
    public var secureInput: Bool
    /// When a person's own input last arrived, on the same monotonic clock as
    /// `now`. Nil when the input monitor is off, which is the default.
    public var lastUserInputAt: Double?
    /// A person's input arrived since the PREVIOUS sample, however long ago that
    /// was. An edge rather than an age, and the two are not the same reading.
    ///
    /// The decay below asks how old the last input is, which is the right
    /// question for deciding when a hold ends and the wrong one for deciding
    /// whether it ever begins. Nothing samples while a step is in flight, and a
    /// step here routinely outlives the window: measured at
    /// `docs/test-campaign/evidence/witness/a4-act.json`, three drag steps of
    /// 18.6s, 20.2s and 17.7s against a 10-second window, with 24 events
    /// swallowed by the takeover block and no yield recorded for any of them.
    /// An age that expires unread is a signal that was never delivered, so the
    /// arrival is carried as a flag until something reads it.
    public var userInputSince: Bool
    public var now: Double

    public init(expectedPid: Int32? = nil, frontmostPid: Int32? = nil,
                proctorPids: Set<Int32> = [], secureInput: Bool = false,
                lastUserInputAt: Double? = nil, userInputSince: Bool = false,
                now: Double = 0) {
        self.expectedPid = expectedPid
        self.frontmostPid = frontmostPid
        self.proctorPids = proctorPids
        self.secureInput = secureInput
        self.lastUserInputAt = lastUserInputAt
        self.userInputSince = userInputSince
        self.now = now
    }
}

/// The decision, as a value: samples in, a change out.
///
/// Contention is a STATE, not an edge. The hold lasts while the condition lasts
/// and ends when it ends — the app comes back to the front, secure input goes
/// off — rather than for a guessed number of seconds. The one exception is a
/// person's own input, which genuinely is an edge: a keystroke is an instant, so
/// it decays over `inputWindow` instead.
public struct ContentionWatch: Sendable, Equatable {

    /// How long after a person's last keystroke or click the machine still
    /// counts as theirs.
    public var inputWindow: Double = 10
    /// How long a condition has to have been clear before the hold lifts. A
    /// dampener, not a timer: without it, an application that flickers the front
    /// for one sample would release a hold it had just taken.
    public var releaseDelay: Double = 2

    /// Every reason that currently holds. Kept as a set rather than as one
    /// reason because they overlap: somebody who clicks and then switches app
    /// has caused two, and releasing the one that happens to be showing would
    /// forget the other.
    public private(set) var active: Set<YieldReason> = []
    /// Reasons a person has explicitly resumed past. They cannot fire again
    /// until they have gone away and come back — otherwise Resume is a dead
    /// button, pressed and undone on the next poll, which is the "pause nobody
    /// can undo" this whole feature exists to avoid.
    public private(set) var overridden: Set<YieldReason> = []
    /// The expected pid Proctor has actually seen in front. Until it has, "the
    /// front changed" is not a claim it can make: Proctor asked for an app to be
    /// raised, and whether that worked is something to observe rather than to
    /// assume. Without this the condition reads "the front is not what I asked
    /// for", which is true from the first sample when the raise silently failed,
    /// and reports a person moving an app that never arrived.
    private var confirmedFront: Int32?
    /// When every reason went quiet, for the release delay. Nil while any holds.
    private var clearSince: Double?

    public init(inputWindow: Double = 10, releaseDelay: Double = 2) {
        self.inputWindow = inputWindow
        self.releaseDelay = releaseDelay
    }

    /// The reason the panel names: the highest-precedence one that holds.
    public var reason: YieldReason? { YieldReason.allCases.first { active.contains($0) } }
    public var isYielded: Bool { reason != nil }

    public enum Change: Equatable, Sendable {
        case yielded(YieldReason)
        case released(YieldReason)
        case none
    }

    /// What holds in this sample, before any override is applied.
    ///
    /// `confirmedFront` is the pid Proctor has been observed to have in front;
    /// pass nil and the frontmost reading cannot fire at all.
    public static func conditions(_ s: ContentionSample, inputWindow: Double,
                                  confirmedFront: Int32?) -> Set<YieldReason> {
        var out: Set<YieldReason> = []
        if s.secureInput { out.insert(.secureInput) }
        // Two readings of the same fact, and the run needs both. The flag is the
        // arrival, which must not be missed; the window is the age, which is what
        // lets the hold end. A swallow from a minute ago opens a hold here and is
        // released on the next sample after `releaseDelay`, so it is recorded
        // without parking the run on evidence that has gone cold.
        if s.userInputSince { out.insert(.userInput) }
        if let last = s.lastUserInputAt, s.now - last < inputWindow { out.insert(.userInput) }
        // Four things must all be true, and each removes a way for Proctor to
        // pause itself. There has to be an app Proctor demonstrably put in
        // front; it has to have actually been in front at some point, or there
        // is nothing to have been taken back; something else has to be in front
        // now; and that something must not be Proctor — a person opening
        // Proctor's own menu to press Resume is not a reason to hold the run
        // they are trying to release.
        if let expected = s.expectedPid, confirmedFront == expected,
           let front = s.frontmostPid, front != expected, !s.proctorPids.contains(front) {
            out.insert(.frontmostChanged)
        }
        return out
    }

    @discardableResult
    public mutating func sample(_ s: ContentionSample) -> Change {
        // Seeing the target in front is what turns the frontmost reading on. It
        // is recorded per pid, so a run that moves to a different application
        // starts again rather than inheriting the last one's confirmation.
        if let expected = s.expectedPid, s.frontmostPid == expected { confirmedFront = expected }
        let raw = Self.conditions(s, inputWindow: inputWindow, confirmedFront: confirmedFront)
        // An override is spent the moment its own condition goes away. That is
        // what "re-arms only once it has cleared and recurred" means, and it is
        // why the override is per reason rather than one flag: resuming past an
        // app switch must not also blind Proctor to a password field.
        overridden.formIntersection(raw)
        let wanted = raw.subtracting(overridden)

        let before = reason
        if wanted.isEmpty {
            guard let held = before else { active = []; clearSince = nil; return .none }
            // Nothing holds. Wait out the release delay before letting go, so a
            // one-sample flicker in the front does not release a real hold.
            let since = clearSince ?? s.now
            clearSince = since
            guard s.now - since >= releaseDelay else { return .none }
            active = []
            clearSince = nil
            return .released(held)
        }

        active = wanted
        clearSince = nil
        guard let now = reason else { return .none }
        return now == before ? .none : .yielded(now)
    }

    /// A person pressed Resume. Everything currently holding is overridden, so
    /// the same still-true condition does not re-yield on the next poll.
    public mutating func resumedByPerson() {
        overridden.formUnion(active)
        active = []
        clearSince = nil
    }

    /// A new run starts with nothing held and nothing overridden.
    public mutating func reset() {
        active = []
        overridden = []
        clearSince = nil
        confirmedFront = nil
    }
}

// MARK: - Was that event ours?

/// The three filters, as one predicate over what an input monitor can see.
///
/// Read the direction carefully. It returns true only for something that looks
/// like HARDWARE — pid 0 — that carries no tag of ours and did not arrive on the
/// heels of one of our posts. Anything else is some process's event, and a
/// process is not a person.
public enum PersonInput {

    /// How long after Proctor's own synthetic post an arriving event is
    /// discarded whatever it looks like.
    public static let graceSeconds: Double = 0.25

    /// `sourcePid` is `.eventSourceUnixProcessID`; `userData` is
    /// `.eventSourceUserData`; both nil when the event carried no CGEvent at
    /// all, which is not evidence of a person either.
    public static func isAPerson(sourcePid: Int64?, userData: Int64?,
                                 sinceSyntheticPost: Double?,
                                 grace: Double = graceSeconds) -> Bool {
        guard let sourcePid, sourcePid == 0 else { return false }
        guard userData != ProctorEventTag.value else { return false }
        if let sinceSyntheticPost, sinceSyntheticPost < grace { return false }
        return true
    }
}

// MARK: - What a finished run reports

/// One hold, for the run's result and for the audit trail. A slow suite has a
/// reason in a field rather than a mystery somebody has to reconstruct.
public struct YieldRecord: Codable, Sendable, Equatable {
    public var reason: String
    /// The step index the run was held before, when it was held between steps.
    public var step: Int?
    public var heldMs: Int
    /// `released` (the condition cleared), `person` (somebody pressed Resume),
    /// `stopped`, `backstop` (the pause limit gave up), `runEnded`.
    public var endedBy: String

    public init(reason: YieldReason, step: Int?, heldMs: Int, endedBy: YieldEnd) {
        self.reason = reason.rawValue
        self.step = step
        self.heldMs = heldMs
        self.endedBy = endedBy.rawValue
    }

    /// One sentence for a caller that reads prose rather than fields. Nil when
    /// nothing was held, because there is nothing to say.
    public static func note(for records: [YieldRecord]) -> String? {
        guard !records.isEmpty else { return nil }
        let total = records.reduce(0) { $0 + $1.heldMs }
        let times = records.count == 1 ? "once" : "\(records.count) times"
        let reasons = Set(records.map(\.reason)).sorted().joined(separator: ", ")
        return "This run was held \(times) for \(total)ms because somebody was using the machine "
             + "(\(reasons)). The steps still ran in order; the run took longer than its work did."
    }
}

public enum YieldEnd: String, Codable, Sendable {
    case released, person, stopped, backstop, runEnded
}
