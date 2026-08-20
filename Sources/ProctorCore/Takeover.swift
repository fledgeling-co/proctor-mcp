import Foundation

// Taking the machine visibly, and — when an operator has asked for it — holding
// it.
//
// PRO-0019 made a foreground run legible before it starts and PRO-0018 made it
// let go when it notices somebody. Neither stops the person's input arriving in
// the first place, so while a synthetic step runs the person and Proctor are
// both driving one machine through one event stream.
//
// EVERYTHING HERE IS A PURE VALUE. The AppKit half — the panels, the event tap,
// its thread — lives in the agent and holds no policy, which is what makes the
// decisions testable without a window server.
//
// THE BLOCK IS OFF UNLESS AN OPERATOR ASKS FOR IT, and that is a decision with a
// precedent rather than a hedge. PRO-0018 declined to ship even a passive
// `NSEvent` global monitor by default: an agent that already holds Accessibility
// should not quietly acquire an input-observation capability nobody asked for. A
// `CGEventTap` is strictly more than an observer — it sits in the delivery path
// and can drop what it sees — and it needs no grant beyond the one Proctor
// already has, so macOS shows nobody a prompt when it starts. Turning the
// stronger capability on by default while the weaker one stays opt-in would
// reverse that decision in the direction of more power.
//
// WHAT WAS MEASURED, on macOS 26.6, 2026-08-15. T1 to T3 touched only
// `.mouseMoved` posted at the cursor's existing position, so nothing moved and
// nothing was clicked; T5 posted one F13, which almost nothing binds:
//
//   T1  A session tap DOES see events this process posts to `.cghidEventTap`,
//       and a `.headInsertEventTap` `.defaultTap` returning nil removes them: a
//       listener at the tail saw 0 of them. Disabling the tap restored delivery,
//       re-enabling swallowed again. So an unconditional swallow would eat
//       Proctor's own synthetic events and break every foreground step it was
//       drawn for. The pass-through rule below is load-bearing, not a nicety.
//   T2  At the tap, Proctor's own event carries our pid in
//       `.eventSourceUnixProcessID` and our tag in `.eventSourceUserData`;
//       hardware carries 0 and 0. Those two fields are the whole pass rule —
//       see `InputBlock.isOurs`, which is deliberately the MIRROR of
//       `PersonInput.isAPerson` rather than a reuse of it.
//   T3  A tap dies with its process, immediately and with no cleanup code. A
//       second process armed a swallow and exited after two seconds; a watcher
//       posting every 350ms saw five consecutive drops and then delivery
//       resuming the instant the armer exited. That is the whole of "the block
//       must never survive the process" — it is structural, because the tap is a
//       Mach port this process owns.
//
//   T5  Keyboard events reach a session tap in this process too, carrying the
//       same two fields: a posted F13 arrived at a listen-only tap as
//       `(key 105, our pid, our tag)`. T1 to T3 all used the mouse, so without
//       this the keyboard half of the mask would be an assumption. What none of
//       them shows is a HARDWARE key being swallowed — that needs a hand at the
//       keyboard and is stated as unverified rather than implied.
//
// T3 says nothing about a block left armed inside a process that is still
// alive, which is what the deadline exists for.
public enum Takeover {

    /// The overlay. On by default, the drawn pointer's and the run panel's
    /// switch shape exactly: a run that takes somebody's machine without saying
    /// so on the screen in front of them is the state opting out is opting out
    /// of.
    public static func overlayEnabled(in environment: [String: String]) -> Bool {
        OverlaySwitch.isOn("PROCTOR_TAKEOVER", in: environment)
    }

    /// The input block. OFF by default, and deliberately not the same shape as
    /// the switch above — this one is an opt-in, so an unset variable means no
    /// event tap is created on any code path. `PROCTOR_YIELD_INPUT`'s shape,
    /// for the same reason it has it.
    public static func blockEnabled(in environment: [String: String]) -> Bool {
        guard let raw = environment["PROCTOR_TAKEOVER_INPUT"] else { return false }
        let value = raw.trimmingCharacters(in: .whitespaces).lowercased()
        return !value.isEmpty && !OverlaySwitch.offValues.contains(value)
    }
}

// MARK: - When the overlay is up

public extension Takeover {

    /// Whether a batch has anything to announce. Knowable up front for a certain
    /// synthetic step, and only afterwards for a `type` or `scroll` that fell
    /// back — so the overlay goes up on the first step that is certainly
    /// synthetic, or on the first measured `syntheticEvent` plane, whichever
    /// arrives first.
    ///
    /// `requestWasInert` is honoured: a `foreground: true` with nothing to spend
    /// it on takes nothing (PRO-0025 A1) and so announces nothing.
    static func shows(demand: ForegroundDemand, sawSynthetic: Bool) -> Bool {
        if demand.requestWasInert { return false }
        return demand.certainSteps > 0 || sawSynthetic
    }
}

// MARK: - What it says

/// The overlay's two lines. One statement of what is happening and one of what
/// to do about it, in the run panel's settled vocabulary: neutral, one size, and
/// never claiming something that is not true of this moment.
public struct TakeoverLabel: Equatable, Sendable {
    public var title: String
    public var line: String

    public init(title: String, line: String) {
        self.title = title
        self.line = line
    }
}

public extension Takeover {

    /// `blocking` is whether input is genuinely being held right now — not
    /// whether it was asked for, and not whether a tap was created at some
    /// point. A label that claims a block macOS disabled is worse than no label.
    ///
    /// The unblocked wording says so in as many words rather than leaving a
    /// dimmed screen to imply it. A full-screen veil reads as a modal sheet, and
    /// somebody who clicks it expecting to dismiss it is clicking into the
    /// application Proctor is driving — so the line tells them that is what will
    /// happen.
    static func label(app: String?, blocking: Bool) -> TakeoverLabel {
        let name = StepDescription.sanitised(app)
        let title = name.map { "Proctor is driving \"\($0)\"" } ?? "Proctor is driving this Mac"
        // Worded for the batch rather than for the instant. The block arms and
        // releases around each posting moment, so a line that said "held" only
        // while genuinely armed would flicker several times a second across a
        // run of fast steps, and a message that flickers is one people learn to
        // ignore. "While it acts" is true either way and never strobes.
        let line = blocking
            ? "Your keyboard and mouse are held while it acts — press Esc to stop"
            : "Your clicks and keys still reach it — Pause and Stop are in Proctor's run panel"
        return TakeoverLabel(title: title, line: line)
    }
}

// MARK: - How it is drawn

/// Everything the panels need that is a decision rather than a pixel. Held as a
/// value so the settings a window server would otherwise be the only witness to
/// are testable: a panel that quietly stopped setting `sharingType` would put
/// the tint into every capture this tool exists to make.
public struct TakeoverSurfaceSpec: Equatable, Sendable {
    /// Fraction of the screen the tint covers, 0 to 1. Never 1: somebody
    /// watching Proctor drive their Mac has to be able to see what it is doing,
    /// which is the whole point of drawing anything.
    public var alpha: Double
    /// Whether the label sits on an opaque plate. Reduce Transparency asks for
    /// legibility rather than for an opaque screen, and this is what that means
    /// here.
    public var labelPlate: Bool
    /// Whether appearing and disappearing are animated.
    public var fades: Bool
    /// Below the run panel, so Pause and Stop stay visible and clickable above
    /// the tint. Stated as a relationship rather than as a second magic number.
    public var level: Int
    /// Always true. The tint is a statement, not a control: the block is what
    /// holds input, and a panel that could take a click would be a panel that
    /// could eat the one landing on Stop.
    public var ignoresMouseEvents: Bool
    /// Always true, for the same reason the run panel does it: evidence must not
    /// change because somebody was watching.
    public var excludedFromCapture: Bool

    public init(alpha: Double, labelPlate: Bool, fades: Bool, level: Int,
                ignoresMouseEvents: Bool = true, excludedFromCapture: Bool = true) {
        self.alpha = alpha
        self.labelPlate = labelPlate
        self.fades = fades
        self.level = level
        self.ignoresMouseEvents = ignoresMouseEvents
        self.excludedFromCapture = excludedFromCapture
    }
}

public extension Takeover {

    /// The tint at its ordinary weight, and under Reduce Transparency.
    static let ordinaryAlpha = 0.16
    static let reducedTransparencyAlpha = 0.28

    /// `hudLevel` is `RunHUDPanel`'s own level, passed in so the two cannot
    /// drift apart into two numbers that happen to be ordered today.
    static func surface(reduceTransparency: Bool, reduceMotion: Bool,
                        hudLevel: Int,
                        excludedFromCapture: Bool = true) -> TakeoverSurfaceSpec {
        TakeoverSurfaceSpec(alpha: reduceTransparency ? reducedTransparencyAlpha : ordinaryAlpha,
                            labelPlate: reduceTransparency,
                            fades: !reduceMotion,
                            level: hudLevel - 1,
                            excludedFromCapture: excludedFromCapture)
    }
}

// MARK: - The block

/// What the tap decides about one event. `stopRun` swallows as well as stopping:
/// an Escape that halted the run and then also reached the application would
/// have done two things when a person meant one.
public enum InputBlockDecision: String, Equatable, Sendable {
    case pass
    case swallow
    case stopRun
    /// Delivered AND stops the run. The panic chords that mean "make this
    /// stop" — Force Quit and lock the screen — must reach the system, and it
    /// would be a strange reading of somebody pressing them to go on posting
    /// events afterwards. Locking the screen is the sharper case: it raises
    /// Secure Event Input, which releases the block, and an agent that kept
    /// posting into a locked session with the hold gone is the worst end state
    /// this feature has.
    case passAndStop

    /// Whether the event continues to the application.
    public var delivers: Bool { self == .pass || self == .passAndStop }
    /// Whether the run ends here.
    public var stops: Bool { self == .stopRun || self == .passAndStop }
}

/// The classes of event the block reasons about. A Core-side enum rather than
/// `CGEventType` so the decision stays a pure value; the agent maps one to the
/// other in one place.
public enum InputEventKind: String, Equatable, Sendable, CaseIterable {
    case keyDown
    case keyUp
    case modifier
    case mouseDown
    case mouseUp
    case mouseDragged
    case scroll
    /// Anything else that reaches the tap, including the two disable
    /// notifications macOS delivers through it.
    case other
}

/// The modifier keys the block cares about, so a chord is a value rather than a
/// `CGEventFlags` the agent has to reason about.
public struct InputModifiers: OptionSet, Equatable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let command = InputModifiers(rawValue: 1 << 0)
    public static let option = InputModifiers(rawValue: 1 << 1)
    public static let control = InputModifiers(rawValue: 1 << 2)
    public static let shift = InputModifiers(rawValue: 1 << 3)
}

/// A key plus the modifiers that must be held with it.
public struct InputChord: Equatable, Sendable {
    public var keyCode: Int64
    public var modifiers: InputModifiers
    /// Whether pressing it also ends the run. True for the two that mean "make
    /// this stop" and false for the ones that mean "let me look at something
    /// else for a moment".
    public var stopsRun: Bool
    public init(_ keyCode: Int64, _ modifiers: InputModifiers, stopsRun: Bool = false) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.stopsRun = stopsRun
    }
    /// Exact rather than superset: Cmd-Tab is Cmd-Tab, and Cmd-Shift-Tab is its
    /// own entry, so a chord list cannot quietly widen into "anything with
    /// Command held".
    public func matches(keyCode: Int64?, modifiers: InputModifiers) -> Bool {
        keyCode == self.keyCode && modifiers == self.modifiers
    }
}

public enum InputBlock {

    /// Escape's virtual keycode. The release chord is a single key because,
    /// while the block is armed, every other key is being swallowed anyway — so
    /// no chord costs the application under test anything, which leaves
    /// memorability as the only criterion worth optimising.
    public static let releaseKeyCode: Int64 = 53

    /// The ways out of a Mac that is doing something by itself. These are passed
    /// whoever sent them: somebody must be able to switch application, force
    /// quit, lock the screen, and photograph what is happening to their machine
    /// while Proctor holds it. `systemDefined` — media, brightness, power — is
    /// not in the tap's mask at all, for the same reason.
    public static let panicChords: [InputChord] = [
        InputChord(48, [.command]),                              // Cmd-Tab
        InputChord(48, [.command, .shift]),                      // Cmd-Shift-Tab
        InputChord(53, [.command, .option], stopsRun: true),     // Cmd-Opt-Esc, Force Quit
        InputChord(12, [.command, .control], stopsRun: true),    // Ctrl-Cmd-Q, lock the screen
        InputChord(20, [.command, .shift]),                      // Cmd-Shift-3
        InputChord(21, [.command, .shift]),                      // Cmd-Shift-4
        InputChord(23, [.command, .shift])                       // Cmd-Shift-5
    ]

    /// Whether Proctor posted this. The ONLY pass rule, and deliberately the
    /// mirror of `PersonInput.isAPerson` rather than a reuse of it.
    ///
    /// The two answer different questions. `isAPerson` asks whether an event
    /// should HOLD THE RUN, and is conservative in the direction of "this was
    /// ours": only hardware counts, so Proctor can never pause itself forever.
    /// This asks whether an event should REACH THE APPLICATION, where
    /// conservative points the other way: only what Proctor demonstrably posted
    /// goes through, so a remapper, a vendor driver or another agent carrying
    /// its own pid is held rather than waved past. Collapsing them into one
    /// predicate makes one of the two wrong, and the out-of-family gate caught
    /// this spec's first draft doing exactly that: with `pid != 0` as a pass
    /// rule, a Mac running Karabiner delivers the person's own keystrokes with
    /// Karabiner's pid and the block passes precisely what it exists to hold.
    ///
    /// There is no grace window here either. In `isAPerson` the window stops an
    /// application's echo of our click reading as a person; as a *pass* rule it
    /// would open the gate to real hardware for a quarter of a second after
    /// every post, which on steps shorter than that is most of the time the
    /// block claims to be closed.
    ///
    /// `delegated` is PRO-0046's one widening, and it is one identity rather
    /// than a class: the pid of the driver Proctor is *currently* delegating to,
    /// corroborated against the signed program the lane already verified, and
    /// supplied only while a delegated actuation is in flight. It defaults to
    /// empty, which is this rule exactly as it was — so the native lane is
    /// byte-identical and every existing caller keeps its behaviour.
    ///
    /// Without it, a native run's armed tap swallows a *concurrent* delegated
    /// run's events, because `.global` and an app lane are disjoint and the tap
    /// is one for the whole process. With anything broader it would fail the way
    /// the first draft of this rule did: `sourcePid != 0` passes a Mac running
    /// Karabiner, whose remapper delivers the person's own keystrokes carrying
    /// the remapper's pid.
    ///
    /// A `sourcePid` of `0` can never match, whatever the set contains. Zero is
    /// what hardware carries, so admitting it would pass every keystroke a
    /// person makes while the label claimed input was held — the exact inversion
    /// of what this rule is for. The set is filtered at its source too; this is
    /// the belt, and it is here because this is the layer with the tests.
    public static func isOurs(sourcePid: Int64?, userData: Int64?, ourPid: Int64,
                              delegated: Set<Int64> = []) -> Bool {
        if userData == ProctorEventTag.value { return true }
        if let sourcePid, sourcePid == ourPid { return true }
        if let sourcePid, sourcePid != 0, delegated.contains(sourcePid) { return true }
        return false
    }

    /// The decision, with the little state it needs to keep a gesture whole.
    ///
    /// An up is swallowed only when its own down was, and a dragged only while
    /// its button's down was. Without that, arming in the middle of somebody's
    /// drag strips the end off a gesture that started before the block existed
    /// and leaves the application holding a button nobody is pressing — a state
    /// that outlives the block, the run and the process, which is worse than the
    /// race being closed.
    public struct Gate: Sendable {
        private var swallowedKeys: Set<Int64> = []
        private var swallowedButtons: Set<Int64> = []
        /// Buttons whose down landed on the run panel's Stop control. The up is
        /// decided from this and re-tests nothing.
        ///
        /// It has to be a record made at the down, because everything the up
        /// could be re-tested against may have changed underneath it. A post
        /// beginning between somebody's down and their up would make
        /// `postInFlight` suppress the rectangle at the up, and the press would
        /// be swallowed and silently lost — somebody pressed Stop, watched the
        /// button go down, and the run carried on. This is PRO-0026's pair rule
        /// applied to the one gesture that ends a run.
        private var pendingStop: Set<Int64> = []

        public init() {}

        /// Forget everything. Called when the tap goes down, so nothing from one
        /// run decides anything in the next.
        public mutating func reset() {
            swallowedKeys.removeAll()
            swallowedButtons.removeAll()
            pendingStop.removeAll()
        }

        public mutating func decide(kind: InputEventKind, sourcePid: Int64?, userData: Int64?,
                                    ourPid: Int64, keyCode: Int64? = nil, button: Int64? = nil,
                                    modifiers: InputModifiers = [],
                                    location: RunHUDPlacement.Point? = nil,
                                    stopRect: Rect? = nil,
                                    postInFlight: Bool = false,
                                    delegated: Set<Int64> = []) -> InputBlockDecision {
            // Ours passes before anything else is considered, which is also what
            // stops a `key` step that types Escape from stopping the run that
            // typed it — and, since PRO-0046, what stops a delegated driver's
            // own click reaching the Stop rectangle below.
            if isOurs(sourcePid: sourcePid, userData: userData, ourPid: ourPid,
                      delegated: delegated) { return .pass }

            switch kind {
            case .keyDown:
                // The modifier set arrives already reduced to the four bits that
                // mean something here, so a resting Caps Lock, an Fn key or a
                // keyboard's own left/right device bits cannot stop a chord
                // matching. A panic chord that failed to match on somebody
                // else's keyboard would be the safety mechanism failing
                // silently, per-machine, having passed every test here.
                if let chord = panicChords.first(where: { $0.matches(keyCode: keyCode,
                                                                     modifiers: modifiers) }) {
                    return chord.stopsRun ? .passAndStop : .pass
                }
                if let keyCode { swallowedKeys.insert(keyCode) }
                return keyCode == releaseKeyCode ? .stopRun : .swallow

            case .keyUp:
                guard let keyCode, swallowedKeys.remove(keyCode) != nil else { return .pass }
                return .swallow

            case .mouseDown:
                if let button { swallowedButtons.insert(button) }
                // A person's press on Stop, remembered rather than acted on. The
                // rectangle is not consulted at all while Proctor has a post in
                // flight: Proctor's own click happens inside its own declared
                // post, so this makes "our own click can never press Stop"
                // structural rather than an identity check — it holds even if
                // both source fields were lost in transit, which is the right
                // footing for a kill switch.
                if !postInFlight, let button, let stopRect, let location,
                   RunHUDGate.contains(stopRect, location) {
                    pendingStop.insert(button)
                }
                return .swallow

            case .mouseUp:
                guard let button, swallowedButtons.remove(button) != nil else { return .pass }
                guard pendingStop.remove(button) != nil else { return .swallow }
                // Decided on the up, the way the panel's own control actuates,
                // so nothing tears the panel and the tap down while the button
                // is still held and leaves an orphaned up to land in the
                // application. An up away from the rectangle is a cancel, as it
                // is everywhere else on macOS, and is swallowed rather than
                // delivered.
                guard let stopRect, let location,
                      RunHUDGate.contains(stopRect, location) else { return .swallow }
                return .stopRun

            case .mouseDragged:
                guard let button, swallowedButtons.contains(button) else { return .pass }
                return .swallow

            case .scroll:
                return .swallow

            case .modifier, .other:
                // `flagsChanged` is not in the tap's mask, and would not be
                // swallowed if it were: half a modifier pair leaves an
                // application holding a Shift nobody is pressing, and a modifier
                // on its own actuates nothing worth holding.
                return .pass
            }
        }
    }
}

// MARK: - How long a block may last

public extension Takeover {

    /// The longest any single arming may hold input, whatever the caller asked
    /// for. A `dragPath` is clamped to 30 seconds by the actuator and is the
    /// longest step there is, so this sits just above it: past this point the
    /// block is not holding a step, it is holding a person's Mac.
    static let ceilingSeconds: Double = 35

    /// Slack over the step's own bound, for the settle the actuator does inside
    /// `perform` and for the run loop hop that releases it.
    static let slackSeconds: Double = 2

    /// How long this arming may last. Enforced on the tap's own thread, not by
    /// whoever armed it, so a task that throws between arming and releasing
    /// cannot leave input held inside a process that is still alive.
    static func armSeconds(stepDurationMs: Int?) -> Double {
        let own = Double(max(stepDurationMs ?? 0, 0)) / 1000
        return min(ceilingSeconds, own + slackSeconds)
    }
}

// MARK: - What the run says afterwards

/// One run's account of holding the machine. Nil on `ActResult` when nothing was
/// drawn, so a result from a run that took nothing encodes exactly as it did
/// before this existed.
public struct TakeoverReport: Codable, Sendable, Equatable {
    /// The overlay was on screen for part of this run.
    public var shown: Bool
    /// Input was genuinely held for part of it — false when the block was off,
    /// could not be created, or was disabled by macOS before it held anything.
    public var blocked: Bool
    /// How long input was held, summed across every arming.
    public var blockedMs: Int
    /// How many of the person's events were swallowed. A count, never a content:
    /// this is what tells an operator somebody was trying to use the machine.
    public var swallowed: Int
    /// `runEnded`, `stopped` (somebody pressed Escape), `yielded`, `deadline`,
    /// `tapDisabled`, or nil when nothing was ever armed.
    public var releasedBy: String?

    public init(shown: Bool, blocked: Bool, blockedMs: Int, swallowed: Int,
                releasedBy: String?) {
        self.shown = shown
        self.blocked = blocked
        self.blockedMs = blockedMs
        self.swallowed = swallowed
        self.releasedBy = releasedBy
    }

    /// One sentence beside the fields, for a caller that reads prose. Nil when
    /// the run drew nothing, because there is nothing to say.
    public var note: String? {
        guard shown else { return nil }
        guard blocked else {
            return "Proctor took the front for part of this run and said so on every display. "
                 + "Input was not held: anything a person did during those steps reached the "
                 + "application as well."
        }
        let seconds = String(format: "%.1f", Double(blockedMs) / 1000)
        var out = "Proctor held the keyboard and mouse for \(seconds)s of this run, across the "
                + "steps it was posting events into the application."
        if swallowed > 0 {
            let times = swallowed == 1 ? "once" : "\(swallowed) times"
            out += " Somebody used the machine \(times) while it was held, and those events did "
                 + "not reach the application."
        }
        if let releasedBy, releasedBy != "runEnded" {
            out += " The hold ended: \(releasedBy)."
        }
        return out
    }
}

/// Why an arming ended, so the report says which of the six it was rather than
/// leaving a reader to infer it from a duration.
public enum TakeoverRelease: String, Sendable, Equatable, CaseIterable {
    case runEnded
    case stepEnded
    case stopped
    case yielded
    case deadline
    case tapDisabled
    /// Secure keyboard entry turned on while the block was armed.
    case secureInput
}
