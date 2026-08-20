import Foundation

// The character's second home: the menu bar.
//
// The panel may be on a display nobody is looking at, and it can now be hidden
// outright. The menu bar is on every display and always present, so it is the
// better surface for the one job this character was drawn to do — answering
// "what is Proctor doing" at a glance. Everything here is the *policy* of that
// second rendition; the drawing is `ProctorUI`'s and the phase is the run's.
//
// Nothing here derives a state. The phase comes from the one `RunHUDState` the
// agent reduces, which is why there is no second table of what a state means.

public extension RunHUDCharacter {

    /// The menu bar item's side, in points. The menu bar's own thickness, so one
    /// art pixel is one point there exactly as it is in the panel's 38pt bay.
    ///
    /// Chosen by rendering, not assumed. At 16 and 18 points the screen glyph
    /// collapses — idle loses its dot eyes, and blocked and acting both become a
    /// solid vermilion block, which breaks the design record's binding rule that
    /// every state must be readable from its screen alone. At 22 all seven read.
    static var menuBarSide: Int { 22 }

    /// Where a menu bar picture lives in Core's own bundle. Foundation only, so
    /// Core stays free of AppKit; the caller decodes it.
    ///
    /// Returns nil for a missing picture rather than trapping. A menu bar item
    /// that fell back to its status symbol is a smaller failure than an agent
    /// that stopped because a picture was not where it expected.
    static func menuBarAssetURL(asset: String, scale: Int) -> URL? {
        let name = scale == 1 ? asset : "\(asset)@\(scale)x"
        return Bundle.module.url(forResource: name, withExtension: "png",
                                 subdirectory: "character-menubar")
    }
}

public extension RunHUDMotion {

    /// What the menu bar plays.
    ///
    /// The panel's idle is the design record's slow one-pixel bob, which is fine
    /// on a panel that is only on screen while a run is going. The menu bar is on
    /// screen for as long as the Mac is on, so a permanently bobbing item is an
    /// irritation and a battery cost that carries no information — an idle
    /// Proctor is not doing anything, and the still frame says so.
    ///
    /// So: travelling and acting move, because a run is actually in flight.
    /// Everything else, and everything under Reduce Motion, is one frame.
    static func menuBar(for phase: RunHUDPhase, reduceMotion: Bool) -> [RunHUDCharacter.Frame] {
        let frames = RunHUDCharacter.frames(for: phase)
        guard !reduceMotion, menuBarMoving.contains(phase) else {
            return Array(frames.prefix(1))
        }
        return frames
    }

    /// The two states the menu bar moves in. Deliberately narrower than
    /// `RunHUDCharacter.moving`, which includes idle for the panel.
    static var menuBarMoving: Set<RunHUDPhase> { [.travelling, .acting] }

    /// Which frame is up after `elapsed` seconds of a looping sequence.
    ///
    /// The panel hands its loop to the render server once and never draws a
    /// frame. A menu bar item cannot: it is a small view redrawn by a timer. So
    /// the loop is arithmetic here, where it is checkable without a display,
    /// rather than a counter living in a view.
    static func frameIndex(in frames: [RunHUDCharacter.Frame], elapsed: Double) -> Int {
        guard frames.count > 1 else { return 0 }
        let total = frames.reduce(0) { $0 + max(1, $1.durationMs) }
        guard total > 0 else { return 0 }
        // Negative elapsed reads as the start rather than as a negative index: a
        // clock that has been set backwards should show the first frame, not
        // crash the menu bar.
        let into = Int((max(0, elapsed) * 1000).rounded(.down)) % total
        var accumulated = 0
        for (index, frame) in frames.enumerated() {
            accumulated += max(1, frame.durationMs)
            if into < accumulated { return index }
        }
        return frames.count - 1
    }

    /// How often the menu bar has to be asked to redraw for a sequence to play
    /// at its own rate. Nil when nothing moves, which is what stops a still item
    /// costing a timer at all.
    static func menuBarTick(for frames: [RunHUDCharacter.Frame]) -> Double? {
        guard frames.count > 1 else { return nil }
        let shortest = frames.map { max(1, $0.durationMs) }.min() ?? 1
        return Double(shortest) / 1000
    }
}

public extension RunHUDModel {

    /// The phase the menu bar shows.
    ///
    /// While the panel is up this is the panel's phase. Once the run's linger has
    /// elapsed the panel goes and the character rests — so a finished run holds
    /// its tick, and a failure holds its cross, for exactly as long as the panel
    /// would have held it, and then the menu bar goes quiet. Anything else would
    /// leave a red cross in the menu bar until the next run, which is a machine
    /// reporting a fault that is over.
    var menuBarPhase: RunHUDPhase { visible ? phase : .idle }
}

/// What the menu bar item draws.
///
/// The item is Proctor's only always-visible surface and it already carries the
/// one thing a person has to know before anything else works: whether Proctor is
/// reachable and whether it has the permissions it needs. The character is worth
/// a lot, but not that — a calm idle character over an agent that is not
/// answering, or one missing Accessibility, is a picture telling somebody a
/// falsehood about their machine.
///
/// So readiness outranks the character, and the character has the menu bar
/// whenever there is nothing more urgent to say.
public enum MenuBarIcon: Sendable, Equatable {
    /// An SF Symbol name — the state of the agent itself.
    case symbol(String)
    /// The character, in a run phase.
    case character(RunHUDPhase)

    /// `reachable` is whether the agent answered; `block` is what is standing
    /// between Proctor and working at all; `phase` is what the run is doing.
    ///
    /// `takingForeground` outranks the phase and is outranked by both guards, and
    /// that order is the whole of the rule. A Proctor that cannot work must not
    /// wear a calm idle face, which is why readiness comes first. But between a
    /// character saying "acting" and the fact that the next event goes into YOUR
    /// keyboard and pointer, the second is the one somebody needs from across the
    /// room — the phase says what Proctor is doing, this says it is about to
    /// happen to you.
    public static func decide(reachable: Bool, block: MenuBarBlock?, phase: RunHUDPhase,
                              takingForeground: Bool = false) -> MenuBarIcon {
        guard reachable else { return .symbol("bolt.horizontal.circle") }
        if let block { return .symbol(block.symbol) }
        if takingForeground { return .symbol("cursorarrow.rays") }
        return .character(phase)
    }

    /// Before the first poll answers, there is nothing to report either way.
    public static let checking = MenuBarIcon.symbol("circle.dashed")
}

/// What is standing between Proctor and working, when something is.
///
/// This rung used to read `DoctorReport.ready`, which is `blockers.isEmpty` — and
/// the doctor's blockers are two different facts about a Mac wearing one word.
/// A missing grant is a Proctor that will not work until somebody visits System
/// Settings. Secure Event Input is a Proctor that is fine and is being kept out
/// of the keyboard for as long as a password field has focus, which is seconds at
/// a time, several times a day. Showing the missing-permission triangle for the
/// second is a machine reporting a fault it does not have.
///
/// Both still take the menu bar off the character, because neither is healthy
/// rest: while Secure Event Input is on, click, key, hover and dragPath are dead,
/// and somebody about to start a run needs that before they start it rather than
/// as a failure partway through. They just stop sharing a picture.
public enum MenuBarBlock: Sendable, Equatable {
    /// A required grant is not in place. Nothing works until it is.
    case missingGrant
    /// A required grant could not be established — the probe was bounded and the
    /// platform did not answer. Its own case, for the reason `secureInput` is:
    /// the missing-permission triangle over an unconfirmed grant is a machine
    /// reporting a fault it has not been shown to have, and it points at System
    /// Settings, which is where the answer is least likely to be. It still takes
    /// the menu bar off the character, because an unconfirmed grant is not
    /// healthy rest either.
    case unconfirmedGrant
    /// Secure Event Input is active, so the synthetic plane cannot be reached.
    /// The accessibility plane is unaffected, which is why this is its own state
    /// and not the permission one.
    case secureInput

    public var symbol: String {
        switch self {
        case .missingGrant: return "exclamationmark.triangle"
        case .unconfirmedGrant: return "questionmark.circle"
        case .secureInput: return "lock.laptopcomputer"
        }
    }
}

public extension MenuBarIcon {

    /// The rung, from the doctor's own report rather than from a boolean somebody
    /// upstream already reduced.
    ///
    /// Ordered: a **denied** permission outranks an **unestablished** one, which
    /// outranks a locked keyboard. The first is a Mac that will never work, the
    /// second is a Mac that might not, the third is a Mac that is momentarily busy.
    ///
    /// The denied and unconfirmed facts arrive as their own inputs rather than
    /// being inferred from `requiredGrantsGranted`, because that boolean is false
    /// for both and cannot separate them — a Mac with Accessibility denied *and*
    /// Screen Recording unconfirmed has to show the denial, and no amount of
    /// reading one boolean gets there.
    ///
    /// And total, deliberately. `ready` is passed in as well as the facts this
    /// knows how to name, so a `ready` that is false for some *other* reason — a
    /// blocker added to the doctor later, in a change nobody remembers to trace
    /// here — still blocks, as the permission symbol. A rung whose whole job is
    /// keeping a calm face off a Proctor that cannot work has to fail in that
    /// direction; the alternative is a future blocker silently putting the
    /// character back up.
    static func block(requiredGrantsGranted: Bool, secureEventInputActive: Bool,
                      ready: Bool,
                      requiredGrantsDenied: Bool = false,
                      requiredGrantsUnconfirmed: Bool = false) -> MenuBarBlock? {
        if requiredGrantsDenied { return .missingGrant }
        if requiredGrantsUnconfirmed { return .unconfirmedGrant }
        if !requiredGrantsGranted { return .missingGrant }
        if secureEventInputActive { return .secureInput }
        if !ready { return .missingGrant }
        return nil
    }
}

/// The run HUD's own controls, as the agent's internal verb takes them.
///
/// Two things reach this: the menu bar and, one day, anything else local that
/// wants to put Proctor's panel away. Parsing the word in one place is what
/// stops an unknown action being read as a plausible one.
///
/// Note which words are here and which are not. Pause, Resume and Stop act on the
/// run; Hold and Clear act on the queue, live on the panel's queue bar, and are
/// deliberately absent — the two pairs never sit together and never share a word,
/// because calling both "pause" is how somebody stops the wrong thing.
/// PRO-0075. What a person may do to the QUEUE, in the queue's own words.
///
/// Deliberately a separate enum from `RunHUDControl`, and the separation is
/// tested from both sides. Pause and Stop act on the run in flight; Hold,
/// Release, Clear and Drop act on the line behind it. Two controls sharing a
/// word is how somebody stops the wrong thing, and a person who meant to clear a
/// queue and stopped a run has no way to undo it.
///
/// The panel has carried these since PRO-0033 and nothing else could reach them,
/// so a person whose run panel was hidden had no way to clear a queue at all.
public enum RunQueueControl: String, Sendable, CaseIterable {
    /// Nothing new starts; what is running finishes.
    case hold
    /// The line moves again.
    case release
    /// Every waiting run goes. The run in flight is untouched.
    case clear

    public static func parse(_ raw: String?) -> RunQueueControl? {
        guard let raw else { return nil }
        return RunQueueControl(rawValue: raw.trimmingCharacters(in: .whitespaces).lowercased())
    }

    /// None of these needs a run in flight. A queue holds callers while nothing
    /// is running, which is exactly when clearing it matters most.
    public var needsRun: Bool { false }
}

public enum RunHUDControl: String, Sendable, CaseIterable {
    case show, hide, pause, resume, stop

    public static func parse(_ raw: String?) -> RunHUDControl? {
        guard let raw else { return nil }
        return RunHUDControl(rawValue: raw.trimmingCharacters(in: .whitespaces).lowercased())
    }

    /// Whether this action needs a run to be in flight to mean anything.
    public var needsRun: Bool {
        switch self {
        case .pause, .resume, .stop: return true
        case .show, .hide: return false
        }
    }
}
