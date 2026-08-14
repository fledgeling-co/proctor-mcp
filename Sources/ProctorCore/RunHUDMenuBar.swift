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

    /// `reachable` is whether the agent answered; `ready` is whether every
    /// required grant is in place; `phase` is what the run is doing.
    public static func decide(reachable: Bool, ready: Bool, phase: RunHUDPhase) -> MenuBarIcon {
        guard reachable else { return .symbol("bolt.horizontal.circle") }
        guard ready else { return .symbol("exclamationmark.triangle") }
        return .character(phase)
    }

    /// Before the first poll answers, there is nothing to report either way.
    public static let checking = MenuBarIcon.symbol("circle.dashed")
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
