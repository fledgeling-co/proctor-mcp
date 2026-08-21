import Foundation

// The run HUD's character, as a value.
//
// The panel's 38pt bay holds a compact-Mac pixel sprite whose screen changes
// with the run. `docs/design/run-hud-character.md` is settled and binding, and
// the rule it turns on is that THE SCREEN IS THE EXPRESSION: arms and lean are
// secondary and are expected to disappear at small sizes, so every state has to
// be readable from its screen glyph alone. That is what makes the character
// legible at 38px, and it is also what makes reduced motion safe — a still
// frame of any state says everything the moving one does.
//
// The frame table lives here rather than beside the drawing for the same reason
// `RunHUDState` does: which pictures a state plays, how long they play for, and
// what happens when somebody has asked the system to stop moving things are all
// decisions, and decisions in this panel are checkable without a window.
//
// The pictures themselves are cut from one regenerated sheet by
// `design/character/build-sprites.py`. Generating the states separately did not
// hold the character's identity — measured — so the whole grid is drawn at once
// and sliced to a common footprint.

public enum RunHUDCharacter {

    /// One drawn picture and how long it is held.
    public struct Frame: Sendable, Equatable {
        /// The asset's name, without a density suffix or an extension. The
        /// loader adds `@2x` / `@3x`; a test walks the same names.
        public let asset: String
        public let durationMs: Int

        public init(asset: String, durationMs: Int) {
            self.asset = asset
            self.durationMs = durationMs
        }
    }

    /// The bay's side, in points. One art pixel is one point at standard
    /// density, so the pixel grid stays visible rather than being resampled
    /// onto a fraction of one.
    public static let bay: Int = 38

    /// The densities that ship. macOS never asks for more than double; triple
    /// is produced because the brief asks for it and costs a rescale.
    public static let densities: [Int] = [1, 2, 3]

    /// The three states that move. Everything else holds still — a blocked,
    /// paused, finished or errored run is being read, not watched.
    public static let moving: Set<RunHUDPhase> = [.idle, .travelling, .acting]

    /// The first idle cell. Named because it is the picture two other things
    /// point at: the animation's first frame, and `AgentModel.appPaths`, which
    /// stamps it to notice a reinstall that replaced only the resource bundle —
    /// the shape of failure PRO-0030 was actually reported for. PRO-0090.
    public static let idleAsset = "idle-0"

    /// What a phase plays, in order, looping.
    public static func frames(for phase: RunHUDPhase) -> [Frame] {
        switch phase {
        case .idle:
            // The design record's slow one-pixel bob, carried as frames like the
            // rest: the second picture is the first lifted a pixel. The sheet's
            // four idle cells are four attempts at the same still, and cycling
            // them boils rather than bobs.
            return [Frame(asset: idleAsset, durationMs: 1800),
                    Frame(asset: "idle-1", durationMs: 1800)]
        case .travelling:
            // Four drawn frames; the speed lines grow behind it and reset.
            return (0..<4).map { Frame(asset: "travelling-\($0)", durationMs: 160) }
        case .acting:
            // Four drawn frames; the arm reaches out and comes back.
            return (0..<4).map { Frame(asset: "acting-\($0)", durationMs: 130) }
        case .blocked:
            return [Frame(asset: "blocked", durationMs: 0)]
        case .paused:
            return [Frame(asset: "paused", durationMs: 0)]
        case .finished:
            return [Frame(asset: "finished", durationMs: 0)]
        case .error:
            return [Frame(asset: "error", durationMs: 0)]
        }
    }

    /// Every asset that ships, deduplicated and ordered. The loader reads this
    /// and so does the test that proves each one is actually in the bundle at
    /// every density — a manifest nobody checks is how a state ends up drawing
    /// an empty bay in a build nobody ran.
    public static var assets: [String] {
        var seen = Set<String>()
        return RunHUDPhase.allCases
            .flatMap { frames(for: $0) }
            .map(\.asset)
            .filter { seen.insert($0).inserted }
    }
}

/// What moves on the panel, and what a person's Reduce Motion setting does to
/// it. The panel's fade already reads that setting; the sprite's loop and the
/// reference's rail glow are the first things here that need more than a fade,
/// so the rule is written once, here, and both read it.
public enum RunHUDMotion {

    /// The frames to play. With motion reduced this is exactly one frame — the
    /// state's own resting picture — because the design rule guarantees each
    /// state is readable from its screen alone, so nothing has to move for the
    /// panel to be understood.
    public static func sprite(for phase: RunHUDPhase, reduceMotion: Bool) -> [RunHUDCharacter.Frame] {
        let frames = RunHUDCharacter.frames(for: phase)
        guard !reduceMotion, RunHUDCharacter.moving.contains(phase) else {
            return Array(frames.prefix(1))
        }
        return frames
    }

    /// The reference's pulse on the filled part of the progress rail: it
    /// breathes while a run is moving and is still otherwise.
    public struct RailGlow: Sendable, Equatable {
        /// The dim end of the pulse; the bright end is full opacity.
        public let minimumOpacity: Double
        /// One dim-to-bright-to-dim cycle.
        public let periodSeconds: Double
    }

    public static func railGlow(for phase: RunHUDPhase, reduceMotion: Bool) -> RailGlow? {
        guard !reduceMotion else { return nil }
        switch phase {
        case .travelling, .acting:
            return RailGlow(minimumOpacity: 0.65, periodSeconds: 1.6)
        case .idle, .blocked, .paused, .finished, .error:
            return nil
        }
    }
}
