import Foundation
import Testing
@testable import ProctorCore

// PRO-0021 — the character's second home.
//
// Everything a menu bar rendition decides that is not drawing: which states move
// there and which hold still, which frame is up at a given moment, what the item
// shows when Proctor cannot work at all, and whether the pictures are actually in
// the bundle at every density.
//
// What is NOT testable here, and is not pretended to be: the item appearing in
// the menu bar, the character being legible there, the animation playing, and a
// click landing on a menu item. `swift test` has no window server.

@Suite("Menu bar character")
struct RunHUDMenuBarMotionTests {

    @Test("only travelling and acting move in the menu bar")
    func onlyRunningStatesMove() {
        #expect(RunHUDMotion.menuBarMoving == [.travelling, .acting])
        for phase in RunHUDPhase.allCases {
            let frames = RunHUDMotion.menuBar(for: phase, reduceMotion: false)
            let moves = frames.count > 1
            #expect(moves == RunHUDMotion.menuBarMoving.contains(phase), "\(phase)")
        }
    }

    @Test("idle is still in the menu bar even though it bobs in the panel")
    func idleIsStillHereAndNotThere() {
        // The panel is only on screen during a run, so its slow bob costs
        // nothing. The menu bar is on screen for as long as the Mac is.
        #expect(RunHUDCharacter.frames(for: .idle).count > 1)
        #expect(RunHUDMotion.menuBar(for: .idle, reduceMotion: false).count == 1)
    }

    @Test("reduced motion leaves exactly one frame everywhere")
    func reducedMotionIsOneFrame() {
        for phase in RunHUDPhase.allCases {
            #expect(RunHUDMotion.menuBar(for: phase, reduceMotion: true).count == 1, "\(phase)")
        }
    }

    @Test("every menu bar state rests on the same picture the panel rests on")
    func restingFramesAgree() {
        for phase in RunHUDPhase.allCases {
            #expect(RunHUDMotion.menuBar(for: phase, reduceMotion: true).first
                    == RunHUDCharacter.frames(for: phase).first, "\(phase)")
        }
    }

    @Test("a still sequence asks for no timer at all")
    func stillStatesCostNothing() {
        for phase in RunHUDPhase.allCases where !RunHUDMotion.menuBarMoving.contains(phase) {
            let frames = RunHUDMotion.menuBar(for: phase, reduceMotion: false)
            #expect(RunHUDMotion.menuBarTick(for: frames) == nil, "\(phase)")
        }
        let acting = RunHUDMotion.menuBar(for: .acting, reduceMotion: false)
        #expect(RunHUDMotion.menuBarTick(for: acting) == 0.13)
    }

    @Test("the frame index walks the sequence and wraps")
    func frameIndexWalksAndWraps() {
        let frames = RunHUDMotion.menuBar(for: .acting, reduceMotion: false)
        #expect(frames.count == 4)
        // Four frames at 130ms each: 520ms a loop.
        #expect(RunHUDMotion.frameIndex(in: frames, elapsed: 0) == 0)
        #expect(RunHUDMotion.frameIndex(in: frames, elapsed: 0.12) == 0)
        #expect(RunHUDMotion.frameIndex(in: frames, elapsed: 0.13) == 1)
        #expect(RunHUDMotion.frameIndex(in: frames, elapsed: 0.39) == 3)
        #expect(RunHUDMotion.frameIndex(in: frames, elapsed: 0.52) == 0)
        #expect(RunHUDMotion.frameIndex(in: frames, elapsed: 0.65) == 1)
    }

    @Test("a clock set backwards shows the first frame rather than a negative one")
    func negativeElapsedIsTheStart() {
        let frames = RunHUDMotion.menuBar(for: .travelling, reduceMotion: false)
        #expect(RunHUDMotion.frameIndex(in: frames, elapsed: -12) == 0)
    }

    @Test("a single-frame sequence is always frame zero")
    func stillSequenceIsFrameZero() {
        let frames = RunHUDMotion.menuBar(for: .paused, reduceMotion: false)
        #expect(RunHUDMotion.frameIndex(in: frames, elapsed: 900) == 0)
    }
}

@Suite("Menu bar phase")
struct RunHUDMenuBarPhaseTests {

    @Test("while the panel is up the menu bar shows the panel's phase")
    func liveRunShowsItsPhase() {
        var state = RunHUDState()
        state.apply(.runBegan(total: 3, app: "Acme"))
        #expect(state.model.menuBarPhase == .travelling)
        state.apply(.stepActing(step: ActionStep(kind: .press, node: "n"), node: nil,
                                synthetic: false))
        #expect(state.model.menuBarPhase == .acting)
    }

    @Test("an ending is held for the linger and then the menu bar rests")
    func endingRestsAfterTheLinger() {
        var state = RunHUDState()
        state.apply(.runBegan(total: 1, app: nil))
        state.apply(.runEnded(.failed))
        // Still holding the cross while the panel would still be showing it.
        #expect(state.model.menuBarPhase == .error)
        state.apply(.lingerElapsed)
        // And then it goes. A red cross left in the menu bar until the next run
        // is a machine reporting a fault that is over.
        #expect(state.model.menuBarPhase == .idle)
    }

    @Test("every ending rests, not only the loud ones")
    func everyEndingRests() {
        for ending in [RunHUDEnding.completed, .stoppedByPerson, .blocked, .failed] {
            var state = RunHUDState()
            state.apply(.runBegan(total: 1, app: nil))
            state.apply(.runEnded(ending))
            state.apply(.lingerElapsed)
            #expect(state.model.menuBarPhase == .idle, "\(ending)")
        }
    }

    @Test("a fresh model is idle before anything has ever run")
    func freshModelIsIdle() {
        #expect(RunHUDModel().menuBarPhase == .idle)
    }
}

@Suite("Menu bar icon")
struct MenuBarIconTests {

    @Test("a run taking the foreground outranks the phase, and readiness outranks it")
    func foregroundSitsBetweenReadinessAndThePhase() {
        // Decided at the merge of PRO-0019 and PRO-0021, which arrived with two
        // rules for one glyph: readiness outranks the character, and a foreground
        // step outranks everything. Both are kept, in this order, and the order is
        // the argument — a Proctor that cannot work must not wear a calm face, but
        // between "acting" and "the next event goes into your keyboard", the
        // second is what somebody needs from across the room.
        #expect(MenuBarIcon.decide(reachable: true, block: nil, phase: .acting,
                                   takingForeground: true) == .symbol("cursorarrow.rays"))
        #expect(MenuBarIcon.decide(reachable: true, block: nil, phase: .acting,
                                   takingForeground: false) == .character(.acting))
        // Both guards still win, because a broken agent that looks busy is a
        // picture telling you something untrue about your Mac.
        #expect(MenuBarIcon.decide(reachable: false, block: nil, phase: .acting,
                                   takingForeground: true) == .symbol("bolt.horizontal.circle"))
        #expect(MenuBarIcon.decide(reachable: true, block: .missingGrant, phase: .acting,
                                   takingForeground: true) == .symbol("exclamationmark.triangle"))
        // And the default keeps every existing caller on the old behaviour.
        #expect(MenuBarIcon.decide(reachable: true, block: nil, phase: .idle)
                == .character(.idle))
    }

    @Test("an unreachable agent keeps its status symbol, whatever the phase says")
    func unreachableKeepsTheSymbol() {
        for phase in RunHUDPhase.allCases {
            #expect(MenuBarIcon.decide(reachable: false, block: .missingGrant, phase: phase)
                    == .symbol("bolt.horizontal.circle"), "\(phase)")
            #expect(MenuBarIcon.decide(reachable: false, block: nil, phase: phase)
                    == .symbol("bolt.horizontal.circle"), "\(phase)")
        }
    }

    @Test("a missing permission outranks the character")
    func notReadyKeepsTheWarning() {
        // A calm idle character over an agent missing Accessibility is a picture
        // telling somebody a falsehood about their machine.
        #expect(MenuBarIcon.decide(reachable: true, block: .missingGrant, phase: .idle)
                == .symbol("exclamationmark.triangle"))
        #expect(MenuBarIcon.decide(reachable: true, block: .missingGrant, phase: .acting)
                == .symbol("exclamationmark.triangle"))
    }

    @Test("a working agent shows the character in the run's own state")
    func readyShowsTheCharacter() {
        for phase in RunHUDPhase.allCases {
            #expect(MenuBarIcon.decide(reachable: true, block: nil, phase: phase)
                    == .character(phase), "\(phase)")
        }
    }
}

@Suite("Run HUD control vocabulary")
struct RunHUDControlTests {

    @Test("the words are the run's, never the queue's")
    func neverTheQueuesWords() {
        // Pause and Stop act on the run; Hold and Clear act on the queue and live
        // on the panel. The two pairs never share a word, because calling both
        // "pause" is how somebody stops the wrong thing.
        let words = Set(RunHUDControl.allCases.map(\.rawValue))
        #expect(words == ["show", "hide", "pause", "resume", "stop"])
        #expect(words.isDisjoint(with: ["hold", "clear", "drop", "release"]))
    }

    @Test("parsing is forgiving about case and space and strict about the rest")
    func parsing() {
        #expect(RunHUDControl.parse("hide") == .hide)
        #expect(RunHUDControl.parse("  SHOW ") == .show)
        #expect(RunHUDControl.parse("Stop") == .stop)
        #expect(RunHUDControl.parse("hold") == nil)
        #expect(RunHUDControl.parse("") == nil)
        #expect(RunHUDControl.parse(nil) == nil)
    }

    @Test("only the run's controls need a run")
    func whichNeedARun() {
        #expect(RunHUDControl.pause.needsRun)
        #expect(RunHUDControl.resume.needsRun)
        #expect(RunHUDControl.stop.needsRun)
        #expect(!RunHUDControl.show.needsRun)
        #expect(!RunHUDControl.hide.needsRun)
    }
}

@Suite("Menu bar sprite assets")
struct MenuBarAssetTests {

    @Test("the menu bar item is 22 points")
    func side() {
        // Measured rather than assumed: at 16 and 18 the screen glyph collapses
        // and blocked and acting become the same solid block, which breaks the
        // design record's rule that every state is readable from its screen
        // alone. 22 is also the menu bar's own thickness, so one art pixel is one
        // point there exactly as it is in the panel's 38pt bay.
        #expect(RunHUDCharacter.menuBarSide == 22)
    }

    @Test("every picture the frame table names ships at every density")
    func manifestIsComplete() throws {
        for asset in RunHUDCharacter.assets {
            for scale in RunHUDCharacter.densities {
                let url = RunHUDCharacter.menuBarAssetURL(asset: asset, scale: scale)
                let found = try #require(url, "\(asset)@\(scale)x is not in the bundle")
                #expect(FileManager.default.fileExists(atPath: found.path),
                        "\(asset)@\(scale)x is listed but not on disk")
            }
        }
    }

    @Test("every picture is one square footprint at its density")
    func oneFootprint() throws {
        // A character that changed size as the state changed would jump in the
        // menu bar, which is the drift the slicer's shared canvas exists to stop.
        for asset in RunHUDCharacter.assets {
            for scale in RunHUDCharacter.densities {
                let url = try #require(RunHUDCharacter.menuBarAssetURL(asset: asset, scale: scale))
                let data = try Data(contentsOf: url)
                let size = try #require(PNGHeader.size(of: data), "\(asset)@\(scale)x")
                let wanted = RunHUDCharacter.menuBarSide * scale
                #expect(size.width == wanted && size.height == wanted,
                        "\(asset)@\(scale)x is \(size.width)x\(size.height), wanted \(wanted)")
            }
        }
    }

    @Test("the menu bar set is a second size, not a second character")
    func sameNamesAsThePanel() throws {
        // The design record's rule is regenerate the grid rather than a cell. The
        // menu bar set is cut from the same committed sheet, so it answers to
        // exactly the same names — a name here that the frame table does not know
        // would mean somebody drew something new.
        let names = Set(RunHUDCharacter.assets)
        let directory = try #require(Bundle.module.url(forResource: "character-menubar",
                                                       withExtension: nil))
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        let bases = Set(files.filter { $0.hasSuffix(".png") }.map { file -> String in
            let stem = String(file.dropLast(4))
            guard let at = stem.lastIndex(of: "@") else { return stem }
            return String(stem[stem.startIndex..<at])
        })
        #expect(bases == names)
    }
}

/// Just enough of a PNG reader to check a picture's dimensions. The IHDR chunk
/// is the first one and its width and height are big-endian at a fixed offset,
/// so this needs no image framework and works wherever the tests run.
enum PNGHeader {
    static func size(of data: Data) -> (width: Int, height: Int)? {
        let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        guard data.count >= 24, Array(data.prefix(8)) == signature else { return nil }
        let bytes = [UInt8](data[16..<24])
        func word(_ offset: Int) -> Int {
            (Int(bytes[offset]) << 24) | (Int(bytes[offset + 1]) << 16)
                | (Int(bytes[offset + 2]) << 8) | Int(bytes[offset + 3])
        }
        return (word(0), word(4))
    }
}

// PRO-0075. The queue's controls, and the separation from the run's.
//
// Found by the campaign: three commands the catalogue declared for the menu bar
// were never rendered there, and `commandsMissingFromMenuBar` could not see it
// because it compares the catalogue against itself. `Clear Waiting Runs` was one
// of them, and nothing but the run panel could reach the queue at all — so a
// person who had hidden the panel could not clear a queue.

@Suite("Run queue control vocabulary")
struct RunQueueControlTests {

    @Test("the words are the queue's, never the run's")
    func neverTheRunsWords() {
        // The mirror of the run's own test, and it has to exist on both sides:
        // a word added to either enum has to be refused by the other, or the
        // separation only holds in the direction somebody happened to test.
        let queue = Set(RunQueueControl.allCases.map(\.rawValue))
        #expect(queue == ["hold", "release", "clear"])
        #expect(queue.isDisjoint(with: Set(RunHUDControl.allCases.map(\.rawValue))))
    }

    @Test("no queue control needs a run in flight")
    func aQueueHoldsWhileNothingRuns() {
        // A queue holds callers while nothing is running, which is exactly when
        // clearing it matters most. Refusing for want of a live run would leave
        // those callers waiting on a control that said there was nothing to do.
        #expect(RunQueueControl.allCases.allSatisfy { !$0.needsRun })
    }

    @Test("parsing is forgiving about case and space and strict about the rest")
    func parsing() {
        #expect(RunQueueControl.parse("  Clear ") == .clear)
        #expect(RunQueueControl.parse("HOLD") == .hold)
        #expect(RunQueueControl.parse("stop") == nil)
        #expect(RunQueueControl.parse("pause") == nil)
        #expect(RunQueueControl.parse(nil) == nil)
    }

    @Test("a queue control that names no action is refused with the list")
    func anUnnamedActionIsRefused() {
        // A control that silently did nothing is the failure this whole surface
        // exists to prevent, one level up.
        #expect(RunQueueControl.parse("") == nil)
    }
}
