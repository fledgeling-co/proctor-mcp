import Foundation
import Testing
@testable import ProctorCore

// PRO-0074. The rules the supervision surface holds, asserted without a
// terminal and without a live agent.

@Suite("Supervision surface")
struct TUISupervisionTests {

    // MARK: - Stop is reachable (the reason this surface exists)

    @Test("A4 · Stop is offered on every pane a run can be running under")
    func stopIsReachable() {
        #expect(TUISurface.offersStop(.run))
        #expect(TUISurface.offersStop(.queue))
    }

    @Test("every pane is one keystroke away, so a person is never more than one from Stop")
    func everyPaneHasItsOwnKey() {
        let keys = TUISurface.Pane.allCases.map(\.key)
        #expect(keys == ["1", "2", "3", "4", "5"])
        #expect(Set(keys).count == keys.count)
    }

    @Test("the pane you are on is the only one in upper case, which survives losing colour")
    func theCurrentPaneIsMarkedByCaseNotColour() {
        for current in TUISurface.Pane.allCases {
            let upper = TUISurface.Pane.allCases
                .filter { $0.tabLabel(current: current) == $0.rawValue.uppercased() }
            #expect(upper == [current])
        }
    }

    // MARK: - A6: an absence that says which absence it is

    @Test("A6 · an unreachable agent names the reason and offers the remedy as a key")
    func unreachableNamesTheRemedy() {
        let model = TUISurface.model(pane: .run, frame: nil, receivedAt: nil, now: Date(),
                                     failure: "Connection refused on the agent socket.")
        guard case .unreachable(let reason, _) = model.connection else {
            Issue.record("expected the unreachable state"); return
        }
        #expect(reason == "Connection refused on the agent socket.")
        let drawn = TUISurface.render(model, cols: 100, rows: 30).lines.joined(separator: "\n")
        #expect(drawn.contains("Connection refused on the agent socket."))
        #expect(drawn.contains("[a] start the agent"))
    }

    @Test("A6 · an agent that answers but is too old is a different state, with a different remedy")
    func anOlderAgentIsNotAMissingOne() {
        let model = TUISurface.model(pane: .run, frame: nil, receivedAt: nil, now: Date(),
                                     outdated: "unknown tool \"proctor.watch\"")
        guard case .tooOld = model.connection else {
            Issue.record("expected the too-old state"); return
        }
        let drawn = TUISurface.render(model, cols: 100, rows: 30).lines.joined(separator: "\n")
        // Telling somebody to start a process that is already running is the
        // kind of wrong advice that costs an hour.
        #expect(!drawn.contains("start the agent"))
        #expect(drawn.contains("upgrade the agent"))
        #expect(drawn.contains("answering but cannot be watched"))
    }

    @Test("A6 · a frame that stopped arriving is reported stale, not drawn as current")
    func staleFramesAreNotDrawnAsLive() {
        let frame = SupervisionFrame(at: 0, lanes: [
            .init(lane: "app:Mail", holder: "mcp claude-code", state: "holding", seconds: 3),
        ], waiting: 0)
        let taken = Date()
        let fresh = TUISurface.model(pane: .run, frame: frame, receivedAt: taken, now: taken)
        #expect(fresh.connection == .connected)
        #expect(fresh.lanes.count == 1)

        let later = taken.addingTimeInterval(SupervisionFrame.staleAfter + 1)
        let stale = TUISurface.model(pane: .run, frame: frame, receivedAt: taken, now: later)
        guard case .unreachable(_, let seconds) = stale.connection else {
            Issue.record("a frame older than the stale bound must not read as connected"); return
        }
        #expect(seconds >= Int(SupervisionFrame.staleAfter))
        // The lanes are dropped rather than drawn: the whole point is that the
        // screen does not show a queue nobody has confirmed.
        #expect(stale.lanes.isEmpty)
    }

    @Test("nothing yet is 'connecting', which is not the same as nothing there")
    func silenceBeforeTheFirstFrameIsNotAFailure() {
        let model = TUISurface.model(pane: .run, frame: nil, receivedAt: nil, now: Date())
        #expect(model.connection == .connecting)
    }

    // MARK: - The wire, read the same way by any surface

    @Test("a free lane reads as a dash rather than as zero seconds waited")
    func aFreeLaneHasNoWait() {
        let frame = SupervisionFrame(at: 0, lanes: [
            .init(lane: "event-stream", holder: "free", state: "free", seconds: 0),
            .init(lane: "app:Mail", holder: "mcp claude-code", state: "waiting", seconds: 7),
        ])
        let lanes = frame.lanesForSurface()
        #expect(lanes[0].wait == "-")
        #expect(lanes[1].wait == "7s")
        #expect(lanes[1].isWaiting)
    }

    @Test("a held run says who is holding it, in Proctor's own words")
    func aHeldRunNamesItsHold() {
        let frame = SupervisionFrame(at: 0, run: .init(
            summary: "Act x6 · Mail", held: true,
            holdReason: "Paused — you used the keyboard or mouse",
            seconds: 74, machine: "host"))
        let run = frame.runForSurface()
        #expect(run?.phase == .paused)
        #expect(run?.facts.contains { $0.value == "Paused — you used the keyboard or mouse" } == true)
        #expect(run?.facts.contains { $0.label == "elapsed" && $0.value == "01:14.0" } == true)
    }

    // MARK: - The floor

    @Test("A1 · the design's floor is the one that still exists everywhere")
    func theFloorIsEightyByTwentyFour() {
        #expect(TUISurface.floor == (cols: 80, rows: 24))
    }

    @Test("A7 · the surface reads the wire and holds nothing, so it needs no grant")
    func itHoldsNothingItWouldNeedAGrantFor() throws {
        // Structural rather than behavioural: the supervision client links only
        // Core, and a frame carries no window handle, no pixels and no
        // accessibility node — so there is nothing on this path that a TCC grant
        // would gate, on a machine with or without a window server.
        let frame = SupervisionFrame(at: 1, run: .init(summary: "Act x6", held: false,
                                                       seconds: 1, machine: "host"))
        let encoded = try JSONEncoder().encode(frame)
        let text = String(data: encoded, encoding: .utf8) ?? ""
        for forbidden in ["window", "pixels", "node", "screenshot", "element"] {
            #expect(!text.contains(forbidden), "the wire frame carries \(forbidden)")
        }
    }
}
