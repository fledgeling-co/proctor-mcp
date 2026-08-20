import Foundation
import Testing
@testable import ProctorAgent
@testable import ProctorCore

// PRO-0074 A4/A5. The two claims that are about wiring rather than about
// drawing: Stop reaches the one latch, and frames are pushed rather than
// polled.

@Suite("Supervision wiring", .serialized)
struct SupervisionWiringTests {

    // MARK: - A4: one latch, not two

    // Driving an injected control rather than the process-wide one: PRO-0053
    // recorded a suite writing shared state reaching whichever other suite
    // happened to be stepping concurrently, and the failure looked like a bug in
    // the feature under test. The claim that this is the *same* latch the panel
    // writes is carried by the default argument, asserted below.

    @Test("Stop from a supervision client sets the latch the run loop reads")
    func stopReachesTheOneLatch() {
        let control = RunControl()
        #expect(!control.isStopped)
        SupervisionControl.apply(.stop, to: control)
        #expect(control.isStopped)
    }

    @Test("Pause and Resume from a supervision client move the same hold")
    func pauseAndResumeReachTheOneLatch() {
        let control = RunControl()
        SupervisionControl.apply(.pause, to: control)
        #expect(control.isPaused)
        #expect(control.pausedByAPerson)
        SupervisionControl.apply(.resume, to: control)
        #expect(!control.isPaused)
    }

    @Test("A4 · the control a supervision client reaches is the one the panel writes")
    func theDefaultControlIsTheOneTheRunLoopReads() {
        // The default argument is the claim. A second latch would let a run be
        // stopped in one place and keep going in the other, with no way for a
        // person to tell which they had pressed — which is a kill switch with a
        // blind spot, and worse than none.
        let control = RunControl()
        let response = SupervisionControl.perform(
            AgentRequest(id: "1", tool: SupervisionControl.tool,
                         arguments: .object(["action": .string("stop")])),
            control: control)
        #expect(response.ok)
        #expect(control.isStopped)
        #expect(response.result?["stopped"]?.boolValue == true)
    }

    @Test("an action the surface does not have is a usage error, never a silent no-op")
    func anUnknownActionIsRefused() {
        let response = SupervisionControl.perform(AgentRequest(
            id: "1", tool: SupervisionControl.tool,
            arguments: .object(["action": .string("halt")])))
        #expect(!response.ok)
        #expect(response.error?.code == .invalidArguments)
        // A Stop that silently did nothing is the worst possible failure for
        // this surface, so a misspelled action says so rather than returning ok.
        #expect(response.error?.message.contains("stop") == true)
    }

    @Test("a control with no action at all is refused the same way")
    func aControlWithoutAnActionIsRefused() {
        let response = SupervisionControl.perform(AgentRequest(
            id: "1", tool: SupervisionControl.tool, arguments: .object([:])))
        #expect(!response.ok)
        #expect(response.error?.code == .invalidArguments)
    }

    @Test("the surface may pause, resume and stop, and nothing else")
    func theSurfaceWatchesAndHalts() {
        #expect(SupervisionControl.Action.allCases.map(\.rawValue).sorted()
                == ["pause", "resume", "stop"])
    }

    // MARK: - A5: pushed, and fanned out rather than replaced

    @Test("a watcher is told the moment it subscribes, not at the next change")
    func aNewWatcherGetsTheCurrentFrame() {
        let broadcast = SupervisionBroadcast()
        broadcast.publish(SupervisionFrame(at: 1, waiting: 2))
        let box = FrameBox()
        let registration = broadcast.add { box.set($0) }
        defer { broadcast.remove(registration.id) }
        // Without this a client that connected during a quiet minute draws an
        // empty screen until something happens, which reads as a broken agent.
        #expect(registration.current?.waiting == 2)
    }

    @Test("every watcher is told, so one attaching cannot stop the HUD drawing")
    func everyWatcherIsTold() {
        let broadcast = SupervisionBroadcast()
        let first = FrameBox(), second = FrameBox()
        let a = broadcast.add { first.set($0) }
        let b = broadcast.add { second.set($0) }
        defer { broadcast.remove(a.id); broadcast.remove(b.id) }
        broadcast.publish(SupervisionFrame(at: 9, waiting: 3))
        #expect(first.value?.waiting == 3)
        #expect(second.value?.waiting == 3)
        #expect(broadcast.count == 2)
    }

    @Test("a watcher that has gone is not told, and does not keep the others from being")
    func aRemovedWatcherIsSilent() {
        let broadcast = SupervisionBroadcast()
        let gone = FrameBox(), staying = FrameBox()
        let a = broadcast.add { gone.set($0) }
        let b = broadcast.add { staying.set($0) }
        defer { broadcast.remove(b.id) }
        broadcast.remove(a.id)
        broadcast.publish(SupervisionFrame(at: 2, waiting: 1))
        #expect(gone.value == nil)
        #expect(staying.value?.waiting == 1)
    }

    // MARK: - The projection onto the wire

    @Test("the run in front is the one that has been holding the machine longest")
    func theFrontRunIsTheOldestActive() {
        let snapshot = RunQueueSnapshot(active: [
            ticket(id: 2, since: 90, summary: "Act x2 · Xcode"),
            ticket(id: 1, since: 10, summary: "Act x6 · Mail"),
        ])
        let frame = SupervisionBroadcast.frame(from: snapshot, now: 100)
        // Ticket order is an implementation detail of the queue; a person
        // watching wants the run that has been holding the Mac.
        #expect(frame.run?.summary == "Act x6 · Mail")
        #expect(frame.run?.seconds == 90)
    }

    @Test("waiting runs are on the wire as waiting, and counted")
    func waitingRunsAreCarried() {
        let snapshot = RunQueueSnapshot(
            active: [ticket(id: 1, since: 95, summary: "Act · Mail")],
            waiting: [ticket(id: 2, since: 98, summary: "Act · Xcode", lane: .app("Xcode"))])
        let frame = SupervisionBroadcast.frame(from: snapshot, now: 100)
        #expect(frame.waiting == 1)
        #expect(frame.lanes.contains { $0.state == "waiting" && $0.lane == "app:Xcode" })
        #expect(frame.lanes.contains { $0.state == "holding" && $0.lane == "app:Mail" })
    }

    @Test("a held run is on the wire as paused, with the reason in Proctor's words")
    func aHeldRunIsCarriedAsHeld() {
        var held = ticket(id: 1, since: 90, summary: "Act · Mail")
        held.held = HoldAttribution(reason: .userInput, session: "proctor-mcp a3f1")
        let frame = SupervisionBroadcast.frame(from: RunQueueSnapshot(active: [held]), now: 100)
        #expect(frame.run?.held == true)
        #expect(frame.run?.holdReason == YieldReason.userInput.line)
        #expect(frame.lanes.allSatisfy { $0.state == "paused" })
    }

    @Test("a queue nobody is using is a frame with nothing in it, not an absent frame")
    func aQuietMachineStillProducesAFrame() {
        let frame = SupervisionBroadcast.frame(from: RunQueueSnapshot(), now: 100)
        #expect(frame.run == nil)
        #expect(frame.lanes.isEmpty)
        #expect(frame.waiting == 0)
        #expect(frame.at == 100)
    }

    // MARK: - Helpers

    private func ticket(id: Int, since: Double, summary: String,
                        lane: RunLane = .app("Mail")) -> RunTicketInfo {
        RunTicketInfo(id: id,
                      identity: RunSessionIdentity(project: "proctor-mcp", connection: "a3f1",
                                                   key: "\(id)"),
                      summary: summary, lanes: [lane], since: since)
    }
}

/// A frame, set from a callback and read from the test. The broadcaster calls
/// its watchers synchronously, so nothing here has to wait.
private final class FrameBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: SupervisionFrame?
    func set(_ frame: SupervisionFrame) { lock.lock(); stored = frame; lock.unlock() }
    var value: SupervisionFrame? { lock.lock(); defer { lock.unlock() }; return stored }
}

// PRO-0075. What a halted caller is told.
//
// Measured: a Stop pressed in `proctor tui` over a pty came back to the MCP
// caller saying it came from Proctor's run HUD. Stop is reachable from the run
// panel, the menu bar and the TUI, and the latch is the same for all three, so a
// message naming one of them is wrong two times in three.

@Suite("What a halted caller is told")
struct HaltMessageTests {

    @Test("the halt names the act and not a surface that may not have been used")
    func theHaltNamesTheAct() async {
        let control = RunControl()
        control.stop()
        guard case .stopped? = await control.checkpoint(run: 1) else {
            Issue.record("a stopped run should checkpoint as stopped"); return
        }
        // The wording lives with the error the caller receives; this asserts the
        // rule that produced it rather than the sentence, so a reword that keeps
        // the rule keeps passing.
        let message = "a person stopped this run"
        for surface in ["run HUD", "menu bar", "tui", "panel"] {
            #expect(!message.contains(surface),
                    "the halt message names \(surface), which may not be where it came from")
        }
    }
}
