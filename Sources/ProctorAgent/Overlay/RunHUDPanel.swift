import AppKit
import QuartzCore
import ProctorCore

// The run HUD: the panel a person reads to see what Proctor is doing, and the
// only place they can stop it.
//
// Design reference is `mocks/run-hud.html`, which is settled and binding. What
// it decided, and what this file therefore does not get to revisit:
//
//   NEUTRAL GROUND. The panel floats over somebody else's application, so it is
//   neutral graphite / neutral white with vermilion as the only colour on it. A
//   warm palette borrowed from Proctor's own window reads as brown mud against
//   anything cool.
//
//   ONE LINE, ONE SIZE. The verb carries the state — "Pressing", "About to
//   press", "Paused before" — so there is no status chip, no second line and no
//   apparent type-size change between states. Every numeric slot is drawn in a
//   monospaced face so a changing count cannot move its neighbour.
//
//   THE EXCEPTION, NOT THE RULE. Accessibility is the normal plane and is never
//   announced. A synthetic step says so, in words, once.
//
//   TWO CONTROLS, TWO WORDS. Pause and Stop act on the run. Hold and Clear will
//   act on the queue (PRO-0016) and live in the bar that goes between the trail
//   and the footer. They are never adjacent and never share a word.
//
// THE PANEL IS SIZED TO ITSELF, NEVER TO THE SCREENS. `CursorOverlay.swift`'s
// header carries the measurement: a panel sized to the union of the displays is
// a 26-megapixel backing store that the window server accepts, reports
// `onscreen = 1, alpha = 1`, and never presents. At 352pt this panel cannot span
// displays; `RunHUDPlacement` decides which screen it belongs on, as arithmetic
// that is testable without one.
//
// AND IT CAN TAKE A CLICK, which nothing else this process draws has ever had
// to. `main.swift` runs `NSApplication.run()` rather than a bare
// `CFRunLoopRun()` for exactly this reason. Three details make the click land on
// an app that is never frontmost: the panel is `.nonactivatingPanel`, so
// clicking it does not activate the agent or take focus from the application
// under test; `canBecomeKey` is overridden, because a borderless window
// otherwise refuses key status; and the content view accepts first mouse, which
// is what an inactive application needs to receive the very first click rather
// than swallowing it as an activation.

/// Whether the panel is on screen, readable from off the main actor so
/// `proctor_doctor` can report its absence. A silent absence would leave
/// somebody believing they have a stop button they do not have.
final class RunHUDAvailability: @unchecked Sendable {
    static let shared = RunHUDAvailability()
    private let lock = NSLock()
    private var reason: String?
    private var built = false

    func record(built: Bool, reason: String?) {
        lock.lock(); defer { lock.unlock() }
        self.built = built
        self.reason = reason
    }

    var status: (available: Bool, reason: String?) {
        lock.lock(); defer { lock.unlock() }
        return (built, reason)
    }
}

@MainActor
final class RunHUDPanel {

    static let shared = RunHUDPanel()

    /// The reference's own width.
    static let width: CGFloat = 352

    /// The state lives in `RunHUDFeed`, not here. This panel renders it and owns
    /// nothing but pixels — see that file's header for why the view stopped being
    /// the source of truth.
    private var feed: RunHUDFeed { .shared }
    private var panel: HUDPanel?
    private var content: RunHUDContentView?
    /// Where a drag left it, remembered for the life of the process and never
    /// written to disk — a panel that stays where it was put for the session,
    /// without leaving a settings file behind.
    private var draggedOrigin: CGPoint?
    private var runStarted: Date?
    private var clockTimer: Timer?
    private var linger: DispatchWorkItem?
    private var themeObserver: NSObjectProtocol?
    /// Latched once the panel's drawing has raised. Never cleared: a fault that
    /// happened once will happen again on the next display pass.
    private var drawingFaulted = false
    /// The scheduler's latest state, held with absolute timestamps so the 1 Hz
    /// redraw can age the wait times without the scheduler having to tick.
    private var queue = RunQueueSnapshot()
    /// Whether the list is open. A person's choice about this panel, so it lives
    /// here and never in the scheduler.
    private var queueExpanded = false
    /// Which run is on the live line, so it is not repeated in the list below it.
    private var liveRun: Int?
    /// The keeper the queue's controls act on, handed over at start-up. Nil until
    /// then, and a nil keeper means there is nothing queued for a button to act
    /// on — the scheduler and the session are created together.
    private var scheduler: RunScheduler?

    func bind(scheduler: RunScheduler) { self.scheduler = scheduler }
    private var motionObserver: NSObjectProtocol?
    /// Bumped every time the panel is presented. A fade started for one run must
    /// not order the panel out from under the next one — a stability sweep can
    /// start its next pass well inside the fade it just triggered.
    private var presentation = 0

    // MARK: - The run's side

    /// A batch is starting: place the panel on the screen holding the driven
    /// window and show it.
    func begin(total: Int, app: String?, window: Rect,
               foreground: ForegroundDemand = ForegroundDemand()) {
        feed.apply(.runBegan(total: total, app: app, foreground: foreground))
        feed.rememberWindow(window)
        runStarted = Date()
        linger?.cancel(); linger = nil
        // Hidden panels still reduce — that is the whole point of the feed — but
        // nothing here draws or ticks a clock for a window nobody can see.
        guard feed.drawing else { return }
        present(for: window)
        startClock()
        render()
    }

    func apply(_ event: RunHUDEvent) {
        feed.apply(event)
        if case .runEnded = event { scheduleLinger() }
        render()
    }

    // MARK: - The queue's side

    /// The scheduler's state changed. Pushed rather than polled, so the bar is
    /// right the moment somebody else's run joins the line.
    func queueChanged(_ snapshot: RunQueueSnapshot) {
        queue = snapshot
        // The live line shows the most recently started run, and Pause and Stop
        // act on that one — one panel, one run in focus. So the newest active id
        // is the run already on screen, and it is not repeated in the list below.
        liveRun = snapshot.active.map(\.id).max()
        // A list nobody can see is not open. Collapsing it when the bar goes
        // means the next contention opens at the resting footprint rather than
        // at whatever height the last one was left at.
        if snapshot.waitingCount == 0 { queueExpanded = false }
        render()
    }

    /// The bar expands in place. Nothing else on the panel moves: the footer is
    /// docked and the panel grows upward, so Pause and Stop stay where they are
    /// under the cursor of somebody reaching for them.
    func toggleQueue() {
        queueExpanded.toggle()
        render()
    }

    /// Hold stops any waiting run starting — including the active session's own
    /// next one, because a hold a session can jump by sending its next batch is
    /// not a control. The run in flight is untouched and finishes.
    func toggleHold() {
        guard let scheduler else { return }
        let wanted = !queue.held
        Task {
            let held = await scheduler.setHeld(wanted)
            RunHUDPanel.audit(held ? "proctor_queue.hold" : "proctor_queue.release",
                                    detail: held
                                        ? "a person held Proctor's queue, so no waiting run starts"
                                        : "a person released Proctor's queue")
            _ = held
        }
    }

    /// Every waiting run goes and every one of their calls returns saying a
    /// person did it. The active run is untouched — that is what Stop is for, and
    /// it is deliberately a different word on a different row.
    func clearQueue() {
        guard let scheduler else { return }
        Task {
            let removed = await scheduler.clear()
            guard removed > 0 else { return }
            RunHUDPanel.audit("proctor_queue.clear",
                                    detail: "a person cleared Proctor's queue, removing \(removed) "
                                          + "waiting run\(removed == 1 ? "" : "s")")
        }
    }

    /// One waiting run goes; everything else keeps its position. Immediate, with
    /// no undo window: the removed caller is being held open on this decision, so
    /// a delay would be paid by that caller rather than by the person deciding.
    func dropFromQueue(_ run: Int) {
        guard let scheduler else { return }
        Task {
            guard await scheduler.drop(id: run) else { return }
            RunHUDPanel.audit("proctor_queue.drop",
                                    detail: "a person removed a waiting run from Proctor's queue")
        }
    }

    /// A person's hold, clear or drop is recorded the way a stop already is:
    /// these decide whether somebody's agent runs, which is the same class of
    /// event and worth the same accounting.
    /// The first argument is the whole verb, not a suffix: the queue's decisions
    /// and the panel's own are different surfaces and an audit trail that filed
    /// "hide the panel" under the queue would be one to argue with later.
    nonisolated(unsafe) static var auditSink: @Sendable (String, String) -> Void = { tool, detail in
        _ = AuditLog.append(AuditRecord(timestamp: Date().timeIntervalSince1970,
                                        tool: tool,
                                        outcome: "refused", reason: detail))
    }

    /// Not private and not async: the menu bar's hide, show and stop are the same
    /// class of decision as the panel's own hold and clear, and they arrive on the
    /// socket rather than on the main thread.
    nonisolated static func audit(_ tool: String, detail: String) {
        auditSink(tool, detail)
    }

    // MARK: - Presenting

    /// Set by `main.swift` immediately before it enters AppKit's event loop.
    /// A panel drawn by a process that dequeues no events is a stop button
    /// nobody can press, which is worse than no panel at all, so the panel is
    /// simply not drawn and `proctor_doctor` says why.
    nonisolated(unsafe) private static var eventLoopRunning = false

    nonisolated static func markEventLoopRunning() {
        eventLoopRunning = true
        RunHUDFeed.shared.setCanShow(true)
    }

    /// The switch moved. Take the panel down, or bring it back mid-run.
    ///
    /// The switch itself lives in `RunHUDFeed`, seeded from `PROCTOR_HUD` and
    /// moved from the menu bar — one switch, not two, because a person who set
    /// `PROCTOR_HUD=0` and a person who chose Hide want the same thing. Nothing
    /// is written to disk, so the environment is still the default at the next
    /// launch, which is what "for the current run, not at the next relaunch"
    /// means.
    ///
    /// Hiding takes Pause and Stop off the screen, which is why Proctor's menu
    /// bar carries them for as long as the panel is hidden, and why
    /// `proctor_doctor` keeps reporting the absence with its reason.
    func drawingChanged() {
        guard feed.drawing else {
            clockTimer?.invalidate(); clockTimer = nil
            linger?.cancel(); linger = nil
            panel?.orderOut(nil)
            RunHUDGeometry.shared.clear()
            RunHUDAvailability.shared.record(
                built: false,
                reason: "a person hid the run panel from Proctor's menu bar. Pause and Stop are "
                      + "in the menu bar while a run is going, and Show Run Panel brings it back.")
            return
        }
        // Coming back mid-run: put it where it would have been, against the
        // window this run is driving, and start the clock the hide stopped.
        guard feed.model.visible, let window = feed.window else { return }
        present(for: window)
        startClock()
        render()
    }

    /// Redraw from whatever the feed now holds. What the menu bar's own Pause,
    /// Resume and Stop reach when they have already reduced their event.
    func refresh() { render() }

    private func present(for window: Rect) {
        // Hidden from the menu bar. Not a fault and not an absence to explain
        // twice — `setDrawing(false)` already recorded the reason, and the menu
        // bar is holding the stop path while this is off.
        guard feed.drawing else { return }
        // A panel whose drawing raised does not come back. The reason recorded at
        // the fault stays in `proctor_doctor`, so this reads as an explained
        // absence rather than a panel that quietly stopped appearing.
        guard !drawingFaulted else { return }
        guard Self.eventLoopRunning else {
            RunHUDAvailability.shared.record(
                built: false,
                reason: "this process is not running an application event loop, so the panel's "
                      + "Pause and Stop could not receive a click")
            return
        }
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            RunHUDAvailability.shared.record(built: false, reason: "no display is attached")
            return
        }
        let panel = ensurePanel()
        let size = RunHUDPlacement.Size(w: Double(Self.width), h: Double(height()))
        let primaryMaxY = Double(screens[0].frame.maxY)
        let target = RunHUDPlacement.appKit(from: window, primaryMaxY: primaryMaxY)
        // `visibleFrame`, not `frame`: the usable area, with the Dock and the menu
        // bar already taken out. The panel docks 34pt off the bottom-right corner,
        // and on this machine the laptop's Dock is 67pt tall — so measuring from
        // `frame` put the panel's lower third behind the Dock on every screen that
        // has one. The external display reports the two rects as identical, which
        // is exactly why the fault showed on one screen and not the other.
        let frames = screens.map {
            Rect(x: Double($0.visibleFrame.minX), y: Double($0.visibleFrame.minY),
                 w: Double($0.visibleFrame.width), h: Double($0.visibleFrame.height))
        }

        let origin: CGPoint
        if let dragged = draggedOrigin {
            // A remembered position outlives the arrangement that produced it,
            // so it is clamped back onto a screen rather than left off the edge
            // of a display that has since been unplugged.
            let index = RunHUDPlacement.screenIndex(
                for: Rect(x: Double(dragged.x), y: Double(dragged.y),
                          w: size.w, h: size.h), in: frames) ?? 0
            let point = RunHUDPlacement.clamp(
                RunHUDPlacement.Point(x: Double(dragged.x), y: Double(dragged.y)),
                size: size, into: frames[index])
            origin = CGPoint(x: point.x, y: point.y)
        } else if let placement = RunHUDPlacement.place(panel: size, in: frames, target: target) {
            origin = CGPoint(x: placement.origin.x, y: placement.origin.y)
        } else {
            origin = CGPoint(x: screens[0].frame.minX + 34, y: screens[0].frame.minY + 34)
        }

        panel.setFrame(CGRect(origin: origin,
                              size: CGSize(width: Self.width, height: height())),
                       display: false)
        // Never `activate(_:)`. An agent that activates takes focus from the
        // application under test, which breaks settling and every synthetic step.
        presentation += 1
        // Replaces any fade still running rather than fighting it: assigning
        // through the animator with a zero duration cancels the old animation.
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            panel.animator().alphaValue = 1
        }
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        RunHUDAvailability.shared.record(built: true, reason: nil)
    }

    private func ensurePanel() -> HUDPanel {
        if let panel { return panel }
        let frame = CGRect(x: 0, y: 0, width: Self.width, height: height())
        let created = HUDPanel(contentRect: frame,
                               styleMask: [.borderless, .nonactivatingPanel],
                               backing: .buffered, defer: false)
        created.isOpaque = false
        created.backgroundColor = .clear
        created.hasShadow = true
        created.isFloatingPanel = true
        created.hidesOnDeactivate = false
        created.isReleasedWhenClosed = false
        // Above ordinary windows and the menu bar, below the screen-saver shield.
        // The shielding levels can swallow clicks and can sit over the lock
        // screen, and a stop button on a locked machine is not a stop button.
        created.level = .statusBar
        created.collectionBehavior = [.canJoinAllSpaces, .stationary,
                                      .ignoresCycle, .fullScreenAuxiliary]
        // Evidence must not change because somebody was watching. Captures are
        // window-scoped to the app under test already; this makes the exclusion a
        // property of the window rather than an argument about capture filters.
        created.sharingType = .none

        created.acceptsMouseMovedEvents = true

        let root = RunHUDRootView(frame: CGRect(origin: .zero, size: frame.size))
        root.wantsLayer = true
        root.layer?.cornerRadius = 16
        root.layer?.masksToBounds = true
        root.autoresizingMask = [.width, .height]

        if !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            let blur = NSVisualEffectView(frame: root.bounds)
            blur.blendingMode = .behindWindow
            blur.material = .hudWindow
            blur.state = .active
            blur.autoresizingMask = [.width, .height]
            root.addSubview(blur)
        }

        let view = RunHUDContentView(frame: root.bounds)
        view.autoresizingMask = [.width, .height]
        view.owner = self
        root.addSubview(view)

        root.content = view
        created.contentView = root
        panel = created
        content = view

        // Both appearances are authored in the reference, and the panel re-reads
        // the system's setting when it changes rather than keeping whichever one
        // it happened to start in.
        themeObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil, queue: .main) { [weak view] _ in
                MainActor.assumeIsolated { view?.needsDisplay = true }
            }

        // Reduce Motion is read at the moment a loop is handed over, so a run
        // already in flight when somebody turns it on would keep moving until
        // its next state change. The panel's fade was the only thing that read
        // this setting before the character and the rail glow arrived; both are
        // re-applied here rather than left to the next step.
        motionObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil, queue: .main) { [weak view] _ in
                MainActor.assumeIsolated {
                    view?.needsDisplay = true
                    view?.syncAccessories()
                }
            }
        return created
    }

    // MARK: - Rendering

    private func render() {
        guard let panel, let content, feed.drawing else { return }
        // Aged here rather than in the scheduler: the wait times are the only
        // thing on the panel that changes with nothing happening, and the 1 Hz
        // clock timer that draws the run clock already ticks.
        let model = feed.setQueue(RunQueueModel.from(queue, live: liveRun,
                                                     now: Date().timeIntervalSince1970,
                                                     expanded: queueExpanded))
        content.model = model
        content.elapsed = runStarted.map { Date().timeIntervalSince($0) } ?? 0
        content.needsDisplay = true
        // The character's loop and the rail's pulse are handed to the render
        // server, not redrawn: this pushes the state into them and they decide
        // whether anything actually changed.
        content.syncAccessories()

        // Get out of the way of the agent's own synthetic events. A `click`,
        // `hover` or `dragPath` step is posted into the WindowServer stream at a
        // screen point, and the window at that point wins — which, for a point
        // under this panel, is this panel. Left alone, a synthetic click aimed at
        // the application under test would be swallowed by the panel body, or
        // worse, would land on Stop and halt the run that posted it. So while a
        // synthetic step is in flight the whole window ignores mouse events and

        // the posted click reaches what it was aimed at.
        //
        // `syntheticInFlight` is exactly "the step in flight is synthetic", and
        // it is the only thing that may govern this. It used to be read off
        // `exception != nil`, which was the same fact while the exception row
        // only ever appeared during such a step; the row now also states what a
        // batch contains before it starts, so reading the text here would leave
        // Pause and Stop dead for the whole of any run holding a click.
        // `stepsAside` is the plane AND the geometry: the step in flight is
        // about to post an event, and it is about to post it where this panel is
        // standing. It used to be `syntheticInFlight`, which is only the plane —
        // so the panel went transparent for every synthetic step whether or not
        // that step went anywhere near it, and a person's click on Stop passed
        // through into the application under test for the whole of every one.
        panel.ignoresMouseEvents = feed.model.stepsAside

        // The exception line adds a row, so the panel grows upward from its
        // bottom-docked corner: the footer stays where it is and Pause and Stop
        // never move out from under the cursor of somebody reaching for them.
        let wanted = height()
        if abs(panel.frame.height - wanted) > 0.5 {
            panel.setFrame(CGRect(x: panel.frame.minX, y: panel.frame.minY,
                                  width: Self.width, height: wanted), display: true)
        }
        if !model.visible { hide() }
        publishGeometry()
    }

    /// Push the panel's frame and its Stop control to the two readers that
    /// cannot ask AppKit: the session, which decides before each step whether
    /// this panel is standing where the step is about to post, and the event
    /// tap's callback, which decides whether a click landed on Stop.
    ///
    /// Converted to Quartz screen space here, by the only party holding an
    /// `NSScreen`, and against the PRIMARY screen's `maxY` for the whole
    /// arrangement rather than the screen this panel happens to be on — a
    /// per-screen flip puts the rectangle on a display above the menu bar at a
    /// place nothing is drawn.
    private func publishGeometry() {
        guard let panel, panel.isVisible, feed.drawing,
              let primaryMaxY = NSScreen.screens.first?.frame.maxY else {
            RunHUDGeometry.shared.clear()
            return
        }
        let frame = panel.frame
        let appKit = Rect(x: Double(frame.minX), y: Double(frame.minY),
                          w: Double(frame.width), h: Double(frame.height))
        let stopAppKit = content?.stopRectInWindow.map {
            Rect(x: Double(frame.minX + $0.minX), y: Double(frame.minY + $0.minY),
                 w: Double($0.width), h: Double($0.height))
        }
        RunHUDGeometry.shared.publish(
            panel: RunHUDPlacement.quartz(from: appKit, primaryMaxY: Double(primaryMaxY)),
            stop: stopAppKit.map {
                RunHUDPlacement.quartz(from: $0, primaryMaxY: Double(primaryMaxY))
            })
    }

    private func height() -> CGFloat {
        let model = feed.model
        return RunHUDLayout.height(exception: model.exception != nil, queue: model.queue)
    }

    private func startClock() {
        clockTimer?.invalidate()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.render() }
        }
        RunLoop.main.add(timer, forMode: .common)
        clockTimer = timer
    }

    private func scheduleLinger() {
        guard let seconds = feed.model.lingerSeconds else { return }
        linger?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.feed.apply(.lingerElapsed)
                self.render()
            }
        }
        linger = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    /// Take the panel down for good after its drawing raised.
    ///
    /// Not a hide: a hidden panel comes back on the next run and would raise
    /// again on its first display pass, so a fault that is going to recur would
    /// have the panel flickering between half-drawn and caught for the life of
    /// the process. `drawingFaulted` latches, so nothing rebuilds it.
    ///
    /// The run is untouched. Losing the panel costs the Pause and Stop controls,
    /// which `proctor_doctor` now reports as absent along with the reason, and
    /// that is the trade PRO-0015's spec already chose for a panel that cannot be
    /// drawn: a run with no stop button beats no run and no agent.
    func takeDownAfterDrawingFault() {
        drawingFaulted = true
        RunHUDGeometry.shared.clear()
        clockTimer?.invalidate(); clockTimer = nil
        linger?.cancel(); linger = nil
        panel?.orderOut(nil)
        panel = nil
        content = nil
    }

    /// The panel goes on the linger, fading rather than vanishing — except under
    /// reduced motion, where it simply goes. This is the only thing on the panel
    /// that moves, which is why it is also the only thing that setting gates.
    private func hide() {
        clockTimer?.invalidate(); clockTimer = nil
        // The panel is going, so nothing may still be told where its Stop button
        // is. A rectangle that outlived the panel would let a click on empty
        // screen stop a run.
        RunHUDGeometry.shared.clear()
        // And it never goes away click-through. Every path through a run closes
        // the gate, but a run killed between its last step and its end event
        // reaches none of them — and a panel left transparent would pass every
        // later click into whatever is underneath it. This is the belt at the
        // one place AppKit knows the run is over.
        panel?.ignoresMouseEvents = false

        RunHUDAvailability.shared.record(built: false, reason: nil)
        guard let panel else { return }
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            panel.orderOut(nil)
            return
        }
        let generation = presentation
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.45
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.presentation == generation else { return }
                panel.orderOut(nil)
            }
        }
    }

    // MARK: - The controls

    /// Pause and Resume are the same button. The queue's Hold and Clear are a
    /// different pair of words on a different row, by design.
    func togglePause() {
        if feed.model.phase == .paused {
            RunControl.shared.resume()
            feed.apply(.resumed)
        } else {
            RunControl.shared.pause()
            feed.apply(.paused(step: nil, node: nil))
        }
        render()
    }

    func stop() {
        RunControl.shared.stop()
        // The panel says a person stopped it and ends in the quiet grey. Red is
        // for something going wrong; this went right.
        feed.apply(.runEnded(.stoppedByPerson))
        scheduleLinger()
        render()
    }

    func drag(by delta: CGSize) {
        guard let panel else { return }
        let origin = CGPoint(x: panel.frame.minX + delta.width,
                             y: panel.frame.minY + delta.height)
        panel.setFrameOrigin(origin)
        draggedOrigin = origin
        publishGeometry()
    }
}

/// Key status is refused by a borderless window by default, which is one of the
/// two reasons a HUD button silently never fires. The panel still never
/// activates the application — that is what `.nonactivatingPanel` is for.
/// Hit testing is decided at the top of the view tree: a root view that answered
/// for its whole bounds would make the blur and every decorative subview a
/// target, and a click meant for the grip would land on whichever of them
/// happened to be under it.
///
/// Note what this does and does not buy. Only the grip and the two controls are
/// live, so nothing else on the panel reacts. It is NOT the mock's
/// `pointer-events: none`: the panel's backing store is opaque, so the window
/// server routes a click on the body to this window and AppKit then discards it,
/// rather than passing it to the application underneath. Genuine pass-through
/// would need the window to ignore mouse events except while the pointer is over
/// a control, which needs a global mouse monitor — an always-on input observer
/// in an agent that already holds Accessibility, and not a thing to add without
/// asking. The panel is 352pt in a corner and can be dragged elsewhere.
private final class RunHUDRootView: NSView {
    weak var content: RunHUDContentView?
    override func hitTest(_ point: NSPoint) -> NSView? { content?.hitTest(point) }
}

private final class HUDPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
