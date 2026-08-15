import AppKit
import CoreGraphics
import Foundation
import ProctorCatch
import ProctorCore

// The full-screen statement that Proctor has the machine, and the tap that
// holds it.
//
// Two halves that fail independently, deliberately. The overlay is a claim on
// the screen and nothing else: it is click-through, non-activating, excluded
// from capture, and it never touches an event. The block is a `CGEventTap` that
// exists only when an operator set `PROCTOR_TAKEOVER_INPUT`, and only for the
// moments a synthetic step is genuinely being posted. Either can be absent and
// the other still does its job.
//
// ONE PANEL PER SCREEN. `CursorOverlay.swift`'s header carries the measurement
// and it applies here unchanged: a panel sized to the union of the displays is a
// 26-megapixel backing store the window server accepts, reports `onscreen = 1,
// alpha = 1`, and never presents. A takeover overlay that never presents is the
// worst possible version of this feature — it would claim the machine was held
// while showing nobody anything.
//
// IT DOES NOT ENTER A CAPTURE, and that is measured rather than argued, because
// a full-screen tint quietly poisoning every visual assertion is the worst thing
// this repository could ship. Measured on macOS 26.6, 2026-08-15, against a real
// Ghostty window, comparing mean per-channel levels (0-255) with the panels up
// against a two-capture noise floor taken with them down:
//
//                        noise    overlay .readOnly   overlay .none
//   display-scoped       0.000          5.979              0.116
//   window-scoped        0.002          0.010              0.004
//
// Two facts fall out of one A/B, and neither could be had from the window list
// alone — that list reports the union panel above as perfectly healthy. First,
// the tint GENUINELY PRESENTS: as `.readOnly` it moves a display capture by six
// levels against a floor of nothing. Second, `sharingType = .none` is what keeps
// it out of one. And the property the tool actually depends on is the bottom
// row: a window-scoped capture of the application under test is unchanged either
// way, at the level of a terminal's own cursor blink. Window scoping excludes it
// on its own; `.none` is the belt, and both were true at once.
//
// THE TAP RUNS ON ITS OWN THREAD, which is not a style choice. A `.defaultTap`
// must answer promptly or macOS disables it, and the agent's main thread is
// where these panels draw and where AppKit work already queues. A tap serviced
// behind a draw pass would be disabled by timeout at exactly the moment it was
// holding somebody's keyboard. That thread also owns the deadline, so a run that
// throws between arming and releasing cannot leave input held.

// MARK: - The block

/// The event tap. Holds no policy: every decision is `InputBlock.decide` in
/// Core, and everything here is ports, threads and counters.
final class InputBlocker: @unchecked Sendable {

    static let shared = InputBlocker()

    /// Whether an operator asked for this at all. Read once: a tap that could
    /// switch itself on mid-process would be a tap nobody agreed to.
    nonisolated static let isEnabled: Bool =
        Takeover.blockEnabled(in: ProcessInfo.processInfo.environment)

    /// Somebody pressed the release chord. Set by the session at run start.
    var onStop: (@Sendable () -> Void)?
    /// Somebody used the machine and it was swallowed. The event is gone; this
    /// timestamp is what PRO-0018 yields on, so a swallowed keystroke is not a
    /// discarded one.
    var onPersonInput: (@Sendable () -> Void)?
    /// The hold ended on this thread rather than on the caller's — a deadline,
    /// secure input, a tap macOS gave up on. The label has to follow, or the
    /// overlay goes on claiming a hold that ended, which is the one thing it
    /// must never do.
    var onReleased: (@Sendable () -> Void)?

    private let lock = NSLock()
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var loop: CFRunLoop?
    private var thread: Thread?
    private var armedCount = 0
    private var deadline: Double?
    private var heldSince: Double?
    private var gate = InputBlock.Gate()
    private let ourPid = Int64(ProcessInfo.processInfo.processIdentifier)

    private(set) var heldMs = 0
    private(set) var swallowed = 0
    private(set) var everHeld = false
    private(set) var release: TakeoverRelease?
    /// Set when the tap could not be created, or when macOS disabled it and it
    /// did not come back. The label stops claiming a block the moment this is
    /// true, and `proctor_doctor` reports it.
    private(set) var unavailable: String?

    var now: @Sendable () -> Double = { Date().timeIntervalSince1970 }
    /// Substituted in tests; in the agent it is the real reading.
    var secureInputActive: @Sendable () -> Bool = { Grants.secureEventInputActive() }

    // MARK: Arming

    /// Hold input for this step. `seconds` is the deadline the tap's own thread
    /// enforces; nothing the caller does afterwards can extend it.
    func arm(seconds: Double) {
        guard Self.isEnabled else { return }
        lock.lock()
        armedCount += 1
        let first = armedCount == 1
        deadline = max(deadline ?? 0, now() + seconds)
        if heldSince == nil { heldSince = now() }
        lock.unlock()
        guard first else { return }
        onTapThread { [weak self] in self?.enableOnThread(true) }
    }

    /// Let go. Fails open in every sense: an unbalanced release still lets go,
    /// because a block held by an accounting mistake is the failure this feature
    /// cannot have.
    func release(_ reason: TakeoverRelease) {
        guard Self.isEnabled else { return }
        lock.lock()
        armedCount = max(0, armedCount - 1)
        let last = armedCount == 0
        if last { finishHoldLocked(reason) }
        lock.unlock()
        guard last else { return }
        onTapThread { [weak self] in self?.enableOnThread(false) }
    }

    /// The run is over: let go whatever the count says, and take the tap down so
    /// nothing of this exists between runs.
    func stopAll(_ reason: TakeoverRelease) {
        guard Self.isEnabled else { return }
        lock.lock()
        armedCount = 0
        finishHoldLocked(reason)
        lock.unlock()
        onTapThread { [weak self] in self?.teardownOnThread() }
    }

    /// The counters for one run, and a reset. Read at run end.
    func takeReport(shown: Bool) -> TakeoverReport {
        lock.lock(); defer { lock.unlock() }
        let out = TakeoverReport(shown: shown, blocked: everHeld, blockedMs: heldMs,
                                 swallowed: swallowed, releasedBy: release?.rawValue)
        heldMs = 0
        swallowed = 0
        everHeld = false
        release = nil
        unavailable = nil
        return out
    }

    /// Whether input is being held at this instant, which is what the overlay's
    /// label may claim and nothing else.
    var isHolding: Bool {
        lock.lock(); defer { lock.unlock() }
        return armedCount > 0 && tap != nil && unavailable == nil
    }

    /// What `proctor_doctor` says about the block. Nil when nothing is wrong.
    var unavailableReason: String? {
        lock.lock(); defer { lock.unlock() }
        return unavailable
    }

    private func finishHoldLocked(_ reason: TakeoverRelease) {
        if let since = heldSince {
            heldMs += Int(max(0, now() - since) * 1000)
            heldSince = nil
            everHeld = everHeld || tap != nil
        }
        deadline = nil
        if release == nil || reason != .stepEnded { release = reason }
    }

    // MARK: The tap's thread

    private func onTapThread(_ work: @escaping @Sendable () -> Void) {
        lock.lock()
        if thread == nil {
            let started = Thread { [weak self] in
                self?.runLoopMain()
            }
            started.name = "app.fledgeling.procter.inputblock"
            started.qualityOfService = .userInteractive
            thread = started
            lock.unlock()
            started.start()
            // The loop is not up yet, so hand the work over through the same
            // queue everything else uses once it is.
            scheduleWhenLoopReady(work)
            return
        }
        let target = loop
        lock.unlock()
        if let target {
            CFRunLoopPerformBlock(target, CFRunLoopMode.commonModes.rawValue, work)
            CFRunLoopWakeUp(target)
        } else {
            scheduleWhenLoopReady(work)
        }
    }

    private func scheduleWhenLoopReady(_ work: @escaping @Sendable () -> Void) {
        DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 0.02) {
            [weak self] in
            guard let self else { return }
            self.lock.lock()
            let target = self.loop
            self.lock.unlock()
            if let target {
                CFRunLoopPerformBlock(target, CFRunLoopMode.commonModes.rawValue, work)
                CFRunLoopWakeUp(target)
            } else {
                self.scheduleWhenLoopReady(work)
            }
        }
    }

    private func runLoopMain() {
        let current = CFRunLoopGetCurrent()
        lock.lock()
        loop = current
        lock.unlock()
        // The deadline is checked here rather than by the caller, so a task that
        // throws, hangs or forgets cannot leave input held inside a process that
        // is still alive. Four times a second is far finer than any step.
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.checkDeadline()
        }
        RunLoop.current.add(timer, forMode: .common)
        // A source keeps the loop alive between taps; without one `run()`
        // returns immediately and the thread dies before it can be used.
        while !Thread.current.isCancelled {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(1))
        }
    }

    private func checkDeadline() {
        // Secure keyboard entry appearing mid-step: let go rather than sit
        // between somebody and a password field. The synthetic step that armed
        // this is refused under secure input anyway, so nothing is lost.
        if secureInputActive() {
            lock.lock()
            guard armedCount > 0 else { lock.unlock(); return }
            armedCount = 0
            finishHoldLocked(.secureInput)
            lock.unlock()
            enableOnThread(false)
            onReleased?()
            return
        }
        lock.lock()
        guard let due = deadline, now() >= due, armedCount > 0 else { lock.unlock(); return }
        armedCount = 0
        finishHoldLocked(.deadline)
        lock.unlock()
        enableOnThread(false)
        onReleased?()
    }

    // MARK: Creating and enabling

    private func enableOnThread(_ on: Bool) {
        if on {
            guard ensureTap() else { return }
            lock.lock(); let port = tap; unavailable = nil; gate.reset(); lock.unlock()
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
        } else {
            lock.lock(); let port = tap; gate.reset(); lock.unlock()
            if let port { CGEvent.tapEnable(tap: port, enable: false) }
        }
    }

    private func teardownOnThread() {
        lock.lock()
        let port = tap
        let src = source
        tap = nil
        source = nil
        lock.unlock()
        if let port { CGEvent.tapEnable(tap: port, enable: false) }
        if let src { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), src, .commonModes) }
        if let port { CFMachPortInvalidate(port) }
    }

    private static let mask: CGEventMask = {
        // What it needs and no more. Three deliberate absences: `flagsChanged`,
        // because swallowing half a modifier pair leaves an application holding
        // a Shift nobody is pressing and that state outlives the process;
        // `mouseMoved`, because Proctor warps the cursor itself and a pointer
        // that stops moving reads as a hung Mac rather than a held one; and
        // `systemDefined`, because media, brightness and power keys are how
        // somebody makes a machine stop, and Proctor never stands in front of
        // that.
        let types: [CGEventType] = [.keyDown, .keyUp,
                                    .leftMouseDown, .leftMouseUp, .leftMouseDragged,
                                    .rightMouseDown, .rightMouseUp, .rightMouseDragged,
                                    .otherMouseDown, .otherMouseUp, .otherMouseDragged,
                                    .scrollWheel]
        return types.reduce(CGEventMask(0)) { $0 | CGEventMask(1 << $1.rawValue) }
    }()

    private func ensureTap() -> Bool {
        lock.lock()
        if tap != nil { lock.unlock(); return true }
        lock.unlock()

        let callback: CGEventTapCallBack = { _, type, event, info in
            guard let info else { return Unmanaged.passUnretained(event) }
            let blocker = Unmanaged<InputBlocker>.fromOpaque(info).takeUnretainedValue()
            return blocker.handle(type: type, event: event)
        }
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                           place: .headInsertEventTap,
                                           options: .defaultTap,
                                           eventsOfInterest: Self.mask,
                                           callback: callback,
                                           userInfo: Unmanaged.passUnretained(self).toOpaque())
        else {
            // Fail open and say so. A keyboard tap is gated on a grant that is
            // not the one Proctor already holds, so this is the ordinary way for
            // it to be unavailable rather than an exceptional one, and the label
            // must stop claiming a hold that is not there.
            lock.lock()
            unavailable = "the event tap could not be created, so input is not being held. On "
                        + "macOS this usually means Proctor is not approved in System Settings → "
                        + "Privacy & Security → Input Monitoring."
            lock.unlock()
            return false
        }
        // The source goes on this thread's run loop BEFORE anything enables the
        // tap: a tap enabled with nothing servicing it is disabled again by
        // macOS almost immediately.
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
        lock.lock(); tap = port; source = src; lock.unlock()
        return true
    }

    // MARK: The decision

    /// Nothing here may wait on anything. It writes counters under its own lock
    /// and calls two closures that do the same; it never hops to the main actor,
    /// never joins this thread, and never exits the process. A callback that
    /// blocked would freeze the deadline timer and the release chord, which live
    /// on this same run loop — the one way both invariants can fail without the
    /// process dying.
    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // macOS disabled the tap. Re-enable once — a timeout under momentary
        // load is recoverable — and on a second one give up and let go, because
        // a tap that cannot be serviced must not be the thing holding somebody's
        // keyboard. The run carries on exactly as it would at HEAD; what must
        // not happen is the overlay going on claiming a hold that ended.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            lock.lock()
            let firstTime = unavailable == nil
            let port = tap
            if firstTime {
                unavailable = nil
            } else {
                unavailable = "macOS disabled Proctor's event tap twice, so input is no longer "
                            + "being held."
                armedCount = 0
                finishHoldLocked(.tapDisabled)
            }
            lock.unlock()
            if firstTime, let port {
                CGEvent.tapEnable(tap: port, enable: true)
            } else {
                onReleased?()
            }
            return Unmanaged.passUnretained(event)
        }

        lock.lock()
        let armed = armedCount > 0
        lock.unlock()
        guard armed else { return Unmanaged.passUnretained(event) }

        let flags = event.flags
        var modifiers: InputModifiers = []
        if flags.contains(.maskCommand) { modifiers.insert(.command) }
        if flags.contains(.maskAlternate) { modifiers.insert(.option) }
        if flags.contains(.maskControl) { modifiers.insert(.control) }
        if flags.contains(.maskShift) { modifiers.insert(.shift) }

        let kind = Self.kind(of: type)
        let keyCode = (kind == .keyDown || kind == .keyUp)
            ? event.getIntegerValueField(.keyboardEventKeycode) : nil
        let button = (kind == .mouseDown || kind == .mouseUp || kind == .mouseDragged)
            ? event.getIntegerValueField(.mouseEventButtonNumber) : nil

        // The run panel's Stop button, and whether Proctor has a post open. Both
        // are read before the gate's own lock is taken and neither waits: this
        // callback may not block, or it freezes the deadline timer and the
        // release chord that live on this same run loop.
        let stopRect = RunHUDGeometry.shared.stopRect
        let postInFlight = SyntheticPost.shared.inFlight
        // The drivers Proctor is delegating to right now. Without this a native
        // run's armed tap swallows a CONCURRENT delegated run's events — the two
        // overlap, because `.global` and an app lane are disjoint and this tap
        // is one for the whole process — and the delegated step silently does
        // nothing while its own actuation is reported as somebody using the
        // machine. Read here, without waiting, like the two above it.
        let delegated = DelegatedPost.shared.recognisedPids
        let location = event.location

        lock.lock()
        let decision = gate.decide(kind: kind,
                                   sourcePid: event.getIntegerValueField(.eventSourceUnixProcessID),
                                   userData: event.getIntegerValueField(.eventSourceUserData),
                                   ourPid: ourPid, keyCode: keyCode, button: button,
                                   modifiers: modifiers,
                                   location: RunHUDPlacement.Point(x: Double(location.x),
                                                                   y: Double(location.y)),
                                   stopRect: stopRect,
                                   postInFlight: postInFlight,
                                   delegated: delegated)
        if !decision.delivers { swallowed += 1 }
        if decision.stops { release = .stopped }
        lock.unlock()

        if decision.stops { onStop?() }
        // A swallowed event feeds the yield — PRO-0026's A8 — but NEVER while a
        // delegated actuation is outstanding.
        //
        // This is the deadlock the completeness gate found, and it is a real one.
        // Everything about the driver's wire is a documentary reading: if its
        // events arrive looking like hardware rather than carrying its own pid,
        // `isOurs` is false, the armed tap swallows them, and each swallow is
        // handed to the contention monitor as somebody using the machine. The run
        // then yields on its OWN actuation and holds until the backstop — which
        // is exactly the 902-second failure PRO-0018 measured, reached by a new
        // road.
        //
        // Suppressing it costs the person nothing they had: their own input is
        // still swallowed, and the two default yield signals — the frontmost
        // reading and secure input — are untouched, so a person taking the
        // machine back is still noticed. What it removes is the one reading that
        // cannot tell a delegated actuation from a hand, at the only moments one
        // is in flight.
        if !decision.delivers, !DelegatedPost.shared.outstandingCall { onPersonInput?() }
        return decision.delivers ? Unmanaged.passUnretained(event) : nil
    }

    /// The one place a `CGEventType` becomes something Core reasons about.
    static func kind(of type: CGEventType) -> InputEventKind {
        switch type {
        case .keyDown: return .keyDown
        case .keyUp: return .keyUp
        case .flagsChanged: return .modifier
        case .leftMouseDown, .rightMouseDown, .otherMouseDown: return .mouseDown
        case .leftMouseUp, .rightMouseUp, .otherMouseUp: return .mouseUp
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged: return .mouseDragged
        case .scrollWheel: return .scroll
        default: return .other
        }
    }
}

// MARK: - The overlay

@MainActor
final class TakeoverOverlay {

    static let shared = TakeoverOverlay()

    nonisolated static let isEnabled: Bool =
        Takeover.overlayEnabled(in: ProcessInfo.processInfo.environment)

    private struct Surface {
        let panel: NSPanel
        let view: TakeoverView
    }

    private var surfaces: [Surface] = []
    private var builtFor: [CGRect] = []
    private var visible = false
    private var screenObserver: NSObjectProtocol?
    private var lastApp: String?

    /// Put the statement up for a batch that is taking the machine. Idempotent:
    /// a batch of ten clicks raises it once and leaves it up, because a
    /// full-screen tint flashing between every pair of steps is strobing, and
    /// strobing is worse than the thing it announces.
    func show(app: String?) {
        guard Self.isEnabled else { return }
        lastApp = app
        observeScreens()
        ensureSurfaces()
        let spec = Self.spec()
        let label = Takeover.label(app: app, blocking: InputBlocker.isEnabled
                                                      && InputBlocker.shared.isHolding)
        for surface in surfaces {
            surface.view.apply(label: label, spec: spec)
            surface.panel.level = NSWindow.Level(rawValue: spec.level)
            surface.panel.orderFrontRegardless()
            if visible { continue }
            surface.panel.alphaValue = spec.fades ? 0 : 1
            if spec.fades {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.18
                    surface.panel.animator().alphaValue = 1
                }
            }
        }
        visible = true
        // A tint and a line of text reach nobody using VoiceOver, and with the
        // block on that person meets a dead keyboard with no account of why or
        // how to get out of it. The announcement carries both.
        announce("\(label.title). \(label.line)")
    }

    private func announce(_ message: String) {
        NSAccessibility.post(element: NSApp as Any,
                             notification: .announcementRequested,
                             userInfo: [.announcement: message,
                                        .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    /// The label is re-read whenever the hold starts or stops, so it never
    /// claims a block that is not armed.
    func refresh() {
        guard Self.isEnabled, visible else { return }
        let spec = Self.spec()
        let label = Takeover.label(app: lastApp, blocking: InputBlocker.isEnabled
                                                          && InputBlocker.shared.isHolding)
        for surface in surfaces { surface.view.apply(label: label, spec: spec) }
    }

    func hide() {
        guard Self.isEnabled, visible else { return }
        visible = false
        let fades = Self.spec().fades
        for surface in surfaces {
            guard fades else { surface.panel.orderOut(nil); continue }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                surface.panel.animator().alphaValue = 0
            } completionHandler: { [weak panel = surface.panel] in
                MainActor.assumeIsolated { panel?.orderOut(nil) }
            }
        }
    }

    static func spec() -> TakeoverSurfaceSpec {
        let workspace = NSWorkspace.shared
        return Takeover.surface(
            reduceTransparency: workspace.accessibilityDisplayShouldReduceTransparency,
            reduceMotion: workspace.accessibilityDisplayShouldReduceMotion,
            hudLevel: Int(NSWindow.Level.statusBar.rawValue))
    }

    /// Displays come and go mid-run — a lid, a dock, a resolution change — and
    /// surfaces built for yesterday's arrangement leave a screen uncovered while
    /// the label on another one says the machine is held.
    private func observeScreens() {
        guard screenObserver == nil else { return }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, self.visible else { return }
                    let app = self.lastApp
                    self.ensureSurfaces()
                    self.visible = false
                    self.show(app: app)
                }
            }
    }

    private func ensureSurfaces() {
        let frames = NSScreen.screens.map(\.frame)
        guard frames != builtFor else { return }
        for surface in surfaces { surface.panel.orderOut(nil) }
        surfaces = frames.map { build(frame: $0) }
        builtFor = frames
        visible = false
    }

    private func build(frame: CGRect) -> Surface {
        let panel = NSPanel(contentRect: frame,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        // The tint is a statement, never a control: the block holds input, and a
        // panel that could take a click is a panel that could eat the one
        // landing on Stop.
        panel.ignoresMouseEvents = true
        panel.level = NSWindow.Level(rawValue: Self.spec().level)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary,
                                    .ignoresCycle, .fullScreenAuxiliary]
        // Evidence must not change because somebody was watching. Captures are
        // window-scoped to the app under test already; this makes the exclusion
        // a property of the window rather than an argument about filters.
        panel.sharingType = .none

        let view = TakeoverView(frame: CGRect(origin: .zero, size: frame.size))
        view.autoresizingMask = [.width, .height]
        // Not an accessibility element, so a hit test cannot land on Proctor's
        // own sheet instead of the window it is drawn over.
        view.setAccessibilityElement(false)
        view.setAccessibilityRole(.unknown)
        panel.contentView = view
        panel.setAccessibilityElement(false)
        return Surface(panel: panel, view: view)
    }
}

/// The tint and the two lines. Every draw goes inside the barrier PRO-0022 put
/// there: an annotation must not be able to kill the thing it annotates, and
/// this one is drawn on every display at once.
final class TakeoverView: NSView {

    private var label = TakeoverLabel(title: "", line: "")
    private var spec = TakeoverSurfaceSpec(alpha: Takeover.ordinaryAlpha, labelPlate: false,
                                           fades: true,
                                           level: Int(NSWindow.Level.statusBar.rawValue) - 1)
    private var faulted = false

    func apply(label: TakeoverLabel, spec: TakeoverSurfaceSpec) {
        self.label = label
        self.spec = spec
        needsDisplay = true
    }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard !faulted else { return }
        guard let fault = ProctorCatchNSException({ self.paint() }) else { return }
        faulted = true
        RunHUDPanel.audit("takeover.drawFailed", detail: "the takeover overlay could not be drawn "
                        + "(\(fault)); the run is unaffected and the tint is not shown again this "
                        + "launch")
    }

    private func paint() {
        // sRGB throughout, never a calibrated colour: PRO-0022's crash came from
        // handing CoreText a colour it could not use.
        let graphite = NSColor(srgbRed: 0.06, green: 0.07, blue: 0.08, alpha: spec.alpha)
        graphite.setFill()
        bounds.fill()

        let title = NSFont.systemFont(ofSize: 22, weight: .semibold)
        let line = NSFont.systemFont(ofSize: 14, weight: .regular)
        let white = NSColor(srgbRed: 0.97, green: 0.97, blue: 0.97, alpha: 1)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center

        let titleText = NSAttributedString(string: label.title, attributes: [
            .font: title, .foregroundColor: white, .paragraphStyle: paragraph])
        let lineText = NSAttributedString(string: label.line, attributes: [
            .font: line, .foregroundColor: white.withAlphaComponent(0.86),
            .paragraphStyle: paragraph])

        let width = min(bounds.width - 80, 720)
        let titleSize = titleText.boundingRect(with: CGSize(width: width, height: 200),
                                               options: [.usesLineFragmentOrigin])
        let lineSize = lineText.boundingRect(with: CGSize(width: width, height: 200),
                                             options: [.usesLineFragmentOrigin])
        let plateHeight = titleSize.height + lineSize.height + 44
        let plate = CGRect(x: (bounds.width - width) / 2 - 24,
                           y: bounds.height * 0.16,
                           width: width + 48, height: plateHeight)

        // Reduce Transparency asks for legibility, not for an opaque screen: the
        // plate goes solid and the tint does not, because somebody watching
        // Proctor drive their Mac has to be able to see what it is doing.
        let plateColour = NSColor(srgbRed: 0.06, green: 0.07, blue: 0.08,
                                  alpha: spec.labelPlate ? 1 : 0.72)
        let rounded = NSBezierPath(roundedRect: plate, xRadius: 16, yRadius: 16)
        plateColour.setFill()
        rounded.fill()

        titleText.draw(with: CGRect(x: plate.minX + 24, y: plate.minY + 22,
                                    width: width, height: titleSize.height),
                       options: [.usesLineFragmentOrigin])
        lineText.draw(with: CGRect(x: plate.minX + 24, y: plate.minY + 22 + titleSize.height + 8,
                                   width: width, height: lineSize.height),
                      options: [.usesLineFragmentOrigin])
    }
}
