import Foundation
import Testing
import ProctorCore
@testable import ProctorAgent

// PRO-0021 — the menu bar's side of the run panel.
//
// The panel can now be put away from the menu bar, which takes Pause and Stop
// off the screen, so what has to hold is that the stop path survives and that
// `proctor_doctor` says which of the several absences this is. The character's
// reach is the other half: the phase has to stay truthful with no panel anywhere,
// including on a launch where none is ever built.
//
// What is NOT testable here: the menu bar item drawing, the character appearing
// in it, a click landing on a menu item, and the panel leaving or returning the
// screen. `swift test` has no window server, so those are code-complete and
// stated as such rather than dressed up as verified.

@Suite("Run HUD feed")
struct RunHUDFeedTests {

    private func step() -> ActionStep { ActionStep(kind: .press, node: "node-1") }

    @Test("the phase is reduced with no panel anywhere")
    func reducesWithoutAPanel() {
        // The launch that most needs a truthful menu bar is the one with no panel
        // at all, so reduction cannot be something only a drawn panel does.
        let feed = RunHUDFeed(drawing: false)
        #expect(feed.snapshot.phase == .idle)
        #expect(!feed.snapshot.running)

        feed.apply(.runBegan(total: 2, app: "Acme"))
        #expect(feed.snapshot.phase == .travelling)
        #expect(feed.snapshot.running)

        feed.apply(.stepActing(step: step(), node: nil, synthetic: false))
        #expect(feed.snapshot.phase == .acting)

        feed.apply(.runEnded(.completed))
        #expect(feed.snapshot.phase == .finished)
        feed.apply(.lingerElapsed)
        #expect(feed.snapshot.phase == .idle)
        #expect(!feed.snapshot.running)
    }

    @Test("the switch starts where the environment put it")
    func switchStartsFromTheEnvironment() {
        #expect(RunHUDFeed(drawing: false).drawing == false)
        #expect(RunHUDFeed(drawing: true).drawing == true)
        // The same words `PROCTOR_HUD` is read with, so the two cannot drift.
        #expect(OverlaySwitch.isOn("0") == false)
        #expect(OverlaySwitch.isOn(nil) == true)
    }

    @Test("Show is refused, with its reason, where no click could be delivered")
    func showRefusedWithoutAnEventLoop() {
        let feed = RunHUDFeed(drawing: false)
        let refusal = feed.showRefusal
        #expect(refusal != nil)
        #expect(refusal?.contains("event loop") == true)
        #expect(refusal?.contains("PROCTOR_HUD") == true)

        feed.setCanShow(true)
        #expect(feed.showRefusal == nil)
    }

    @Test("the wire shape carries everything the menu bar needs and nothing else")
    func wireShape() throws {
        let feed = RunHUDFeed(drawing: true)
        feed.setCanShow(true)
        feed.apply(.runBegan(total: 1, app: nil))
        let wire = try #require(feed.wire.objectValue)
        #expect(wire["phase"]?.stringValue == "travelling")
        #expect(wire["running"]?.boolValue == true)
        #expect(wire["drawing"]?.boolValue == true)
        #expect(wire["canShow"]?.boolValue == true)
        #expect(Set(wire.keys) == ["phase", "running", "drawing", "canShow"])
    }
}

// Serialized: `RunHUDPanel.auditSink` is one static, and two tests replacing it
// at once would file each other's records.
@Suite("Menu bar switch wiring", .serialized)
struct MenuBarSwitchWiringTests {

    private static let target = "com.example.target"

    private func harness()
    async throws -> (session: Session, feed: RunHUDFeed, control: RunControl,
                     audit: HUDAuditCollector) {
        let session = Session(ax: FakeAX(bundleId: Self.target), capture: FakeCapture())
        let feed = RunHUDFeed(drawing: true)
        feed.setCanShow(true)
        let control = RunControl(pauseLimit: 900, now: { 0 })
        control.pollNanoseconds = 1_000_000
        await session.setDrawsHUD(false)
        await session.setHUDFeed(feed)
        await session.setRunControl(control)
        let audit = HUDAuditCollector()
        RunHUDPanel.auditSink = audit.sink
        return (session, feed, control, audit)
    }

    @Test("hiding takes effect at once, and showing brings it back")
    func hideAndShowAreImmediate() async throws {
        let h = try await harness()
        h.feed.apply(.runBegan(total: 3, app: "Acme"))

        let hidden = try #require(await h.session.hudControl(.hide).objectValue)
        #expect(hidden["hud"]?["drawing"]?.boolValue == false)
        #expect(h.feed.drawing == false)
        // Not at the next relaunch and not at the next run: the run in flight is
        // the one that loses its panel.
        #expect(h.feed.snapshot.running)

        let shown = try #require(await h.session.hudControl(.show).objectValue)
        #expect(shown["hud"]?["drawing"]?.boolValue == true)
        #expect(h.feed.drawing == true)
    }

    @Test("nothing is written to disk, so the environment is still the default")
    func nothingIsPersisted() async throws {
        let h = try await harness()
        _ = try await h.session.hudControl(.hide)
        // A fresh feed reads the environment, not a stored preference — which is
        // what makes this one switch rather than two a person has to reconcile.
        #expect(RunHUDFeed(drawing: true).drawing == true)
        #expect(h.feed.drawing == false)
    }

    @Test("Show is refused where the panel could never take a click, and says why")
    func showRefusedOnALaunchWithNoLoop() async throws {
        let session = Session(ax: FakeAX(bundleId: Self.target), capture: FakeCapture())
        let feed = RunHUDFeed(drawing: false)
        await session.setDrawsHUD(false)
        await session.setHUDFeed(feed)

        let result = try #require(await session.hudControl(.show).objectValue)
        #expect(result["refused"]?.stringValue?.contains("event loop") == true)
        #expect(feed.drawing == false)
        // And hiding is always available, so the two are never both stuck.
        _ = try await session.hudControl(.hide)
        #expect(feed.drawing == false)
    }

    @Test("hiding the panel leaves a stop path")
    func hidingLeavesAStopPath() async throws {
        let h = try await harness()
        h.feed.apply(.runBegan(total: 3, app: "Acme"))
        _ = try await h.session.hudControl(.hide)

        // The panel is gone from the screen and Stop still reaches the same latch
        // the panel's own button writes to. The panel is the kill switch, so
        // putting it away must not put the kill switch away.
        #expect(!h.control.isStopped)
        _ = try await h.session.hudControl(.stop)
        #expect(h.control.isStopped)
        #expect(await h.control.checkpoint(run: 0) == .stopped)
        // And it ends grey, as a person's decision, never red.
        #expect(h.feed.snapshot.phase == .paused)
    }

    @Test("Pause and Resume from the menu bar are the run's own latch")
    func pauseAndResume() async throws {
        let h = try await harness()
        h.feed.apply(.runBegan(total: 3, app: "Acme"))

        _ = try await h.session.hudControl(.pause)
        #expect(h.control.isPaused)
        #expect(h.feed.snapshot.phase == .paused)

        _ = try await h.session.hudControl(.resume)
        #expect(!h.control.isPaused)
        #expect(h.feed.snapshot.phase != .paused)
    }

    @Test("the run's controls are refused when there is no run to act on")
    func runControlsNeedARun() async throws {
        let h = try await harness()
        // Nothing has begun. A Stop latched against nothing would carry into the
        // next run, and the panel would report an ending nobody caused.
        for action in [RunHUDControl.pause, .resume, .stop] {
            let result = try #require(await h.session.hudControl(action).objectValue)
            #expect(result["refused"]?.stringValue?.contains("no run in flight") == true,
                    "\(action)")
        }
        #expect(!h.control.isStopped)
        #expect(!h.control.isPaused)
        #expect(h.feed.snapshot.phase == .idle)

        // The switch is not a run control and works either way.
        _ = try await h.session.hudControl(.hide)
        #expect(h.feed.drawing == false)
    }

    @Test("an unknown action is refused rather than read as a plausible one")
    func unknownActionRefused() async throws {
        let h = try await harness()
        await #expect(throws: AgentError.self) {
            _ = try await h.session.hudControl(RunHUDControl.parse("hold"))
        }
        #expect(h.feed.drawing == true)
    }

    @Test("putting the panel away is accounted for, like holding the queue is")
    func hideAndShowAreAudited() async throws {
        let h = try await harness()
        _ = try await h.session.hudControl(.hide)
        _ = try await h.session.hudControl(.show)
        let entries = h.audit.entries
        #expect(entries.contains { $0.tool == "proctor_hud.hide" })
        #expect(entries.contains { $0.tool == "proctor_hud.show" })
        // Filed under the panel, not under the queue: they are different surfaces
        // and different decisions.
        #expect(!entries.contains { $0.tool.hasPrefix("proctor_queue") })
    }

    @Test("a second hide changes nothing and is not accounted for twice")
    func idempotentHide() async throws {
        let h = try await harness()
        _ = try await h.session.hudControl(.hide)
        _ = try await h.session.hudControl(.hide)
        #expect(h.audit.entries.filter { $0.tool == "proctor_hud.hide" }.count == 1)
    }
}

@Suite("Menu bar surface")
struct MenuBarSurfaceTests {

    private static let target = "com.example.target"

    @Test("the switch is not a tool, so no host can put a person's stop button away")
    func verbIsInternal() {
        // The shim gates tools/call on the catalogue, so a verb that is not in it
        // cannot be reached over MCP at all.
        #expect(ToolCatalogue.spec(named: "proctor_hud") == nil)
        #expect(ToolCatalogue.spec(named: "proctor_recent_activity") == nil)
        #expect(!ToolCatalogue.all.map(\.name).contains("proctor_hud"))
    }

    @Test("the activity feed carries the phase the panel reduced")
    func activityCarriesThePhase() async throws {
        let session = Session(ax: FakeAX(bundleId: Self.target), capture: FakeCapture())
        let feed = RunHUDFeed(drawing: true)
        await session.setDrawsHUD(false)
        await session.setHUDFeed(feed)
        feed.apply(.runBegan(total: 2, app: "Acme"))
        feed.apply(.stepActing(step: ActionStep(kind: .press, node: "n"), node: nil,
                               synthetic: false))

        let activity = try #require(await session.recentActivity().objectValue)
        let hud = try #require(activity["hud"]?.objectValue)
        // The same phase, not a second one derived from the tool name.
        #expect(hud["phase"]?.stringValue == "acting")
        #expect(hud["running"]?.boolValue == true)
    }

    @Test("the health report tells the four absences apart")
    func doctorTellsTheAbsencesApart() async throws {
        // The drawn-panel probe is substituted for the same reason the feed is:
        // `RunHUDAvailability.shared` is process-wide and mutable, so without
        // this the answer is decided by whichever OTHER test last recorded into
        // it. That made this case fail about one full-suite run in five, always
        // on the row that expects nothing to be wrong, and always carrying a
        // reason string this test never set. Here the panel is stipulated to
        // have come up, so the four notes below are the only variable.
        func note(drawing: Bool, canShow: Bool) async throws -> String {
            let session = Session(ax: FakeAX(bundleId: Self.target), capture: FakeCapture())
            let feed = RunHUDFeed(drawing: drawing)
            feed.setCanShow(canShow)
            await session.setHUDFeed(feed)
            await session.setHUDAvailability { (true, nil) }
            let status = try #require(await session.hudStatus().objectValue)
            #expect(status["available"]?.boolValue == (drawing && canShow))
            return status["note"]?.stringValue ?? ""
        }

        // Launched with it off: no panel this launch, and the menu bar cannot
        // bring one back.
        let off = try await note(drawing: false, canShow: false)
        #expect(off.contains("PROCTOR_HUD"))
        #expect(off.contains("restart"))

        // Hidden from the menu bar: the controls are still reachable there, and
        // saying so is the difference between a missing stop button and a moved
        // one.
        let hidden = try await note(drawing: false, canShow: true)
        #expect(hidden.contains("menu bar"))
        #expect(hidden.contains("Show Run Panel"))

        // No event loop to deliver a click.
        let noLoop = try await note(drawing: true, canShow: false)
        #expect(noLoop.contains("event loop"))

        // Drawing, nothing wrong: nothing to explain.
        let fine = try await note(drawing: true, canShow: true)
        #expect(fine.isEmpty)

        // The fourth absence the comment names but nothing asserted: the switch
        // is on, the process could show a panel, and the drawing itself failed.
        // It comes from the availability probe rather than the feed, which is
        // why it needed the probe to be substitutable before it could be stated.
        let session = Session(ax: FakeAX(bundleId: Self.target), capture: FakeCapture())
        let feed = RunHUDFeed(drawing: true)
        feed.setCanShow(true)
        await session.setHUDFeed(feed)
        await session.setHUDAvailability { (false, "no display is attached") }
        let faulted = try #require(await session.hudStatus().objectValue)
        #expect(faulted["available"]?.boolValue == false,
                "a panel that could not be drawn has no Pause or Stop on screen")
        let note = faulted["note"]?.stringValue ?? ""
        #expect(note.contains("no display is attached"))
        #expect(note.contains("could not be drawn"))
    }
}

/// The panel's audit sink, collected. Separate from `AuditCollector` because
/// this one is a static on the panel rather than a per-session injection.
final class HUDAuditCollector: @unchecked Sendable {
    struct Entry: Sendable { let tool: String; let detail: String }
    private let lock = NSLock()
    private var recorded: [Entry] = []

    var entries: [Entry] {
        lock.lock(); defer { lock.unlock() }
        return recorded
    }

    var sink: @Sendable (String, String) -> Void {
        { [self] tool, detail in
            lock.lock(); defer { lock.unlock() }
            recorded.append(Entry(tool: tool, detail: detail))
        }
    }
}
