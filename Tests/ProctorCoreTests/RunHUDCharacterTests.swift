import Testing
import Foundation
@testable import ProctorCore

// PRO-0017. Which pictures a state plays, and what a person's Reduce Motion
// setting does to them.
//
// The character carries tone and never says anything the words on the panel do
// not already say, so a wrong answer here is not a person misled about a run.
// What it does cost is the two things the design record is built on: that every
// state is distinguishable at 38pt from its screen alone, and that the character
// holds one footprint so it does not jump as the run changes. Both are decided
// by the table in this file and by the pictures the build script cuts, so both
// are tested — the table here, the pictures where they are loaded.

@Suite("Run HUD character")
struct RunHUDCharacterTests {

    @Test("every state has a picture, so no run state draws an empty bay")
    func total() {
        for phase in RunHUDPhase.allCases {
            #expect(!RunHUDCharacter.frames(for: phase).isEmpty, "\(phase) has no frames")
        }
    }

    @Test("the seven states are exactly the design record's — none added, none dropped")
    func sevenStates() {
        #expect(RunHUDPhase.allCases.count == 7)
        #expect(Set(RunHUDPhase.allCases.map { RunHUDCharacter.frames(for: $0)[0].asset })
                == ["idle-0", "travelling-0", "acting-0", "blocked", "paused", "finished", "error"])
    }

    @Test("no two states rest on the same picture, so a glance tells them apart")
    func distinctRestingFrames() {
        let resting = RunHUDPhase.allCases.map { RunHUDCharacter.frames(for: $0)[0].asset }
        #expect(Set(resting).count == resting.count)
    }

    @Test("idle, travelling and acting move; the other four hold still")
    func whatMoves() {
        #expect(RunHUDCharacter.moving == [.idle, .travelling, .acting])
        for phase in RunHUDPhase.allCases where !RunHUDCharacter.moving.contains(phase) {
            #expect(RunHUDCharacter.frames(for: phase).count == 1,
                    "\(phase) is not a moving state and should be one picture")
        }
    }

    @Test("a moving state's loop has frames and a duration for each of them")
    func loopsAreWellFormed() {
        for phase in RunHUDCharacter.moving {
            let frames = RunHUDCharacter.frames(for: phase)
            #expect(frames.count >= 2, "\(phase) claims to move on one frame")
            for frame in frames {
                #expect(frame.durationMs > 0, "\(phase) holds \(frame.asset) for no time")
            }
        }
    }

    @Test("travelling and acting carry four drawn frames each, as the brief asks")
    func drawnLoops() {
        #expect(RunHUDCharacter.frames(for: .travelling).count == 4)
        #expect(RunHUDCharacter.frames(for: .acting).count == 4)
    }

    @Test("the manifest lists every picture once")
    func manifest() {
        let assets = RunHUDCharacter.assets
        #expect(Set(assets).count == assets.count)
        let referenced = Set(RunHUDPhase.allCases.flatMap { RunHUDCharacter.frames(for: $0) }
                                                 .map(\.asset))
        #expect(Set(assets) == referenced)
        // Two idle, four travelling, four acting, and one each for the four
        // states that hold still.
        #expect(assets.count == 14)
    }

    @Test("standard and double density ship; triple is produced as the brief asks")
    func densities() {
        #expect(RunHUDCharacter.densities == [1, 2, 3])
        #expect(RunHUDCharacter.bay == 38)
    }
}

@Suite("Run HUD motion")
struct RunHUDMotionTests {

    @Test("with motion reduced every state is a single still picture")
    func reducedIsStill() {
        for phase in RunHUDPhase.allCases {
            let frames = RunHUDMotion.sprite(for: phase, reduceMotion: true)
            #expect(frames.count == 1, "\(phase) still moves with motion reduced")
        }
    }

    @Test("the still it falls back to is the state's own resting picture, not another state's")
    func reducedKeepsTheState() {
        for phase in RunHUDPhase.allCases {
            #expect(RunHUDMotion.sprite(for: phase, reduceMotion: true).first
                    == RunHUDCharacter.frames(for: phase).first)
        }
        // Which is what makes stopping the loop safe: the design rule is that
        // each state reads from its screen glyph alone, so the resting frame
        // says everything the loop does.
        let resting = RunHUDPhase.allCases.map {
            RunHUDMotion.sprite(for: $0, reduceMotion: true)[0].asset
        }
        #expect(Set(resting).count == RunHUDPhase.allCases.count)
    }

    @Test("with motion allowed the moving states play their whole loop")
    func allowedPlaysTheLoop() {
        for phase in RunHUDPhase.allCases {
            let frames = RunHUDMotion.sprite(for: phase, reduceMotion: false)
            #expect(frames == RunHUDCharacter.frames(for: phase), "\(phase)")
        }
    }

    @Test("the rail glows only while a run is moving")
    func railGlowsWhileMoving() {
        #expect(RunHUDMotion.railGlow(for: .travelling, reduceMotion: false) != nil)
        #expect(RunHUDMotion.railGlow(for: .acting, reduceMotion: false) != nil)
        for phase in [RunHUDPhase.idle, .blocked, .paused, .finished, .error] {
            #expect(RunHUDMotion.railGlow(for: phase, reduceMotion: false) == nil, "\(phase)")
        }
    }

    @Test("with motion reduced the rail never glows, in any state")
    func railStillWhenReduced() {
        for phase in RunHUDPhase.allCases {
            #expect(RunHUDMotion.railGlow(for: phase, reduceMotion: true) == nil, "\(phase)")
        }
    }

    @Test("the glow is the reference's pulse: dimmed, not blinked, over 1.6s")
    func glowShape() {
        let glow = RunHUDMotion.railGlow(for: .acting, reduceMotion: false)
        #expect(glow?.periodSeconds == 1.6)
        #expect(glow?.minimumOpacity == 0.65)
        // A pulse that reached zero would read as the rail vanishing rather than
        // as the run breathing, and the rail is what says how far along it is.
        #expect((glow?.minimumOpacity ?? 0) > 0.5)
    }
}
