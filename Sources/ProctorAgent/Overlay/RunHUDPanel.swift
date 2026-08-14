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

    private var state = RunHUDState()
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
    /// Bumped every time the panel is presented. A fade started for one run must
    /// not order the panel out from under the next one — a stability sweep can
    /// start its next pass well inside the fade it just triggered.
    private var presentation = 0

    // MARK: - The run's side

    /// A batch is starting: place the panel on the screen holding the driven
    /// window and show it.
    func begin(total: Int, app: String?, window: Rect) {
        state.apply(.runBegan(total: total, app: app))
        runStarted = Date()
        linger?.cancel(); linger = nil
        present(for: window)
        startClock()
        render()
    }

    func apply(_ event: RunHUDEvent) {
        state.apply(event)
        if case .runEnded = event { scheduleLinger() }
        render()
    }

    // MARK: - Presenting

    /// Set by `main.swift` immediately before it enters AppKit's event loop.
    /// A panel drawn by a process that dequeues no events is a stop button
    /// nobody can press, which is worse than no panel at all, so the panel is
    /// simply not drawn and `proctor_doctor` says why.
    nonisolated(unsafe) private static var eventLoopRunning = false

    nonisolated static func markEventLoopRunning() {
        eventLoopRunning = true
    }

    private func present(for window: Rect) {
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
        let frames = screens.map {
            Rect(x: Double($0.frame.minX), y: Double($0.frame.minY),
                 w: Double($0.frame.width), h: Double($0.frame.height))
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
        return created
    }

    // MARK: - Rendering

    private func render() {
        guard let panel, let content else { return }
        content.model = state.model
        content.elapsed = runStarted.map { Date().timeIntervalSince($0) } ?? 0
        content.needsDisplay = true

        // The exception line adds a row, so the panel grows upward from a
        // bottom-docked corner and the live line never moves.
        let wanted = height()
        if abs(panel.frame.height - wanted) > 0.5 {
            panel.setFrame(CGRect(x: panel.frame.minX, y: panel.frame.minY,
                                  width: Self.width, height: wanted), display: true)
        }
        if !state.model.visible { hide() }
    }

    private func height() -> CGFloat {
        RunHUDLayout.height(exception: state.model.exception != nil)
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
        guard let seconds = state.model.lingerSeconds else { return }
        linger?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.state.apply(.lingerElapsed)
                self.render()
            }
        }
        linger = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    /// The panel goes on the linger, fading rather than vanishing — except under
    /// reduced motion, where it simply goes. This is the only thing on the panel
    /// that moves, which is why it is also the only thing that setting gates.
    private func hide() {
        clockTimer?.invalidate(); clockTimer = nil
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
        if state.model.phase == .paused {
            RunControl.shared.resume()
            state.apply(.resumed)
        } else {
            RunControl.shared.pause()
            state.apply(.paused(step: nil, node: nil))
        }
        render()
    }

    func stop() {
        RunControl.shared.stop()
        // The panel says a person stopped it and ends in the quiet grey. Red is
        // for something going wrong; this went right.
        state.apply(.runEnded(.stoppedByPerson))
        scheduleLinger()
        render()
    }

    func drag(by delta: CGSize) {
        guard let panel else { return }
        let origin = CGPoint(x: panel.frame.minX + delta.width,
                             y: panel.frame.minY + delta.height)
        panel.setFrameOrigin(origin)
        draggedOrigin = origin
    }
}

/// Key status is refused by a borderless window by default, which is one of the
/// two reasons a HUD button silently never fires. The panel still never
/// activates the application — that is what `.nonactivatingPanel` is for.
/// Click-through is the safety story. Everything but the grip and the two
/// controls passes to the application underneath, and that has to be decided at
/// the top of the view tree: a root view that answered a hit test for its whole
/// bounds would put a sheet of glass over somebody's work whatever the content
/// view said, and the blur behind it would do the same.
private final class RunHUDRootView: NSView {
    weak var content: RunHUDContentView?
    override func hitTest(_ point: NSPoint) -> NSView? { content?.hitTest(point) }
}

private final class HUDPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
