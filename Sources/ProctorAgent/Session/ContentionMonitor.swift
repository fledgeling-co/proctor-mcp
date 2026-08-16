import AppKit
import Foundation
import ProctorCore

// The AppKit half of noticing that a person is using this Mac.
//
// It holds NO policy. It caches three facts — what is in front, whether secure
// keyboard entry is on, and when a person's own input last arrived — and hands
// them to `ContentionWatch`, which is a pure value in Core and is where every
// decision is made. Splitting it this way is what makes the interesting part
// testable without a window server: a test drives the watch with samples, and
// this class is substituted by a fake through `ContentionSampling`.
//
// THE INPUT MONITOR IS OFF UNLESS SOMEBODY ASKS FOR IT.
//
// PRO-0015 declined a global mouse monitor for the panel's click-through, and
// the reasoning holds: an agent that already holds Accessibility should not
// quietly acquire an input-observation capability nobody asked for. A run-scoped,
// foreground-only monitor genuinely is a different proposition — it exists only
// while Proctor is already posting into the person's session, a moment the panel
// and the menu bar are both already announcing, and it is torn down when the run
// ends — but different is not free, so it ships off and `PROCTOR_YIELD_INPUT`
// turns it on.
//
// What it records when it is on is one timestamp. Not a keycode, not a
// character, not a modifier, not a location: there is no field on this class
// that could reconstruct anything anybody typed, which is a property of the code
// rather than a promise.

/// What the decision needs, so a test can supply it without AppKit.
protocol ContentionSampling: Sendable {
    func arm(observeInput: Bool)
    func disarm()
    /// The pid Proctor has demonstrably put in front. Set only from a measured
    /// synthetic plane or a settled raise, never from a prediction.
    func setExpectedPid(_ pid: Int32?)
    /// Proctor just posted a synthetic event, for the grace window.
    func noteSyntheticPost()
    /// Somebody used the machine, from a source that has already decided it was
    /// a person. PRO-0026's block calls this for every event it swallows: a
    /// swallowed event never reaches an `NSEvent` monitor, so without this the
    /// two features would cancel — the block would eat the very input the yield
    /// exists to notice.
    func noteUserInput()
    func sample() -> ContentionSample
}

/// A machine nobody is using, which is what a `Session` watches unless somebody
/// hands it the real one.
///
/// WHY THIS IS THE DEFAULT AND THE LIVE MONITOR IS NOT. `ContentionMonitor.shared`
/// reads the actual Mac: which application is in front, whether secure input is
/// on. That is right for the agent and wrong for every other process, and a test
/// process is the case that proves it — a test can never satisfy "the application
/// under test is frontmost", because there is no such application and the front
/// belongs to whatever the developer last clicked. Sampled from inside
/// `RunControl.checkpoint`'s poll, that reading yields the run, and then yields
/// it again on the next poll, and again, until the 900-second backstop gives up.
/// Measured: five suites reached that state and the whole run wedged with no
/// verdict line, because the poll never returns and the queue is behind it.
///
/// So the safe reading is the default and the live machine is opted into, at the
/// one place that genuinely wants it. Getting that wrong now costs a run that
/// politely refuses to get out of a person's way, which is visible; getting the
/// old default wrong cost a silent hang, which is not.
final class NullContentionMonitor: ContentionSampling {
    func arm(observeInput: Bool) {}
    func disarm() {}
    func setExpectedPid(_ pid: Int32?) {}
    func noteSyntheticPost() {}
    func noteUserInput() {}
    /// Nothing expected in front, nothing in front, no secure input and no
    /// keystroke. `expectedPid` nil is the load-bearing field: the frontmost
    /// reading cannot fire while Proctor has not demonstrably put anything in
    /// front, so this samples as a quiet machine rather than as a contended one
    /// whose cause happens to be unset.
    func sample() -> ContentionSample { ContentionSample() }
}

final class ContentionMonitor: ContentionSampling, @unchecked Sendable {

    static let shared = ContentionMonitor()

    /// The events a person's hand makes. Deliberately discrete downs and the
    /// wheel, and deliberately NOT `.mouseMoved`: Proctor warps the cursor
    /// before every pointer step, a hand brushing a trackpad is not somebody
    /// taking the machine back, and the narrower mask is also the narrower thing
    /// to be observing.
    static let inputMask: NSEvent.EventTypeMask =
        [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel]

    private let lock = NSLock()
    private var expectedPid: Int32?
    private var frontmostPid: Int32?
    private var lastUserInputAt: Double?
    private var lastSyntheticPostAt: Double?
    private var armedCount = 0
    private var inputMonitor: Any?
    private var workspaceObserver: NSObjectProtocol?

    /// Substitutable so the grace window and the clock are testable in
    /// milliseconds rather than by waiting.
    var now: @Sendable () -> Double = { Date().timeIntervalSince1970 }
    var grace: Double = PersonInput.graceSeconds

    // MARK: - Switches

    /// The whole feature. On by default, the pointer overlay's and the panel's
    /// switch shape exactly: a run that takes somebody's machine and does not
    /// notice them is the state opting out is opting out of.
    static func enabled(in environment: [String: String]) -> Bool {
        OverlaySwitch.isOn("PROCTOR_YIELD", in: environment)
    }

    /// The input monitor alone. OFF by default, and deliberately not the same
    /// shape as the switch above — this one is an opt-in, so an unset variable
    /// means no monitor is installed on any code path.
    static func inputObserved(in environment: [String: String]) -> Bool {
        guard let raw = environment["PROCTOR_YIELD_INPUT"] else { return false }
        let value = raw.trimmingCharacters(in: .whitespaces).lowercased()
        return !value.isEmpty && !OverlaySwitch.offValues.contains(value)
    }

    // MARK: - Arming

    /// Nested, because two runs driving different applications genuinely overlap
    /// and one of them ending must not tear down the other's watch.
    func arm(observeInput: Bool) {
        lock.lock()
        armedCount += 1
        let first = armedCount == 1
        lock.unlock()
        guard first else { return }
        DispatchQueue.main.async { [weak self] in
            self?.installOnMain(observeInput: observeInput)
        }
    }

    func disarm() {
        lock.lock()
        armedCount = max(0, armedCount - 1)
        let last = armedCount == 0
        if last {
            expectedPid = nil
            lastUserInputAt = nil
        }
        lock.unlock()
        guard last else { return }
        DispatchQueue.main.async { [weak self] in
            self?.removeOnMain()
        }
    }

    deinit { removeOnMain() }

    /// AppKit's own two facts, both read on main.
    private func installOnMain(observeInput: Bool) {
        let workspace = NSWorkspace.shared
        setFrontmost(workspace.frontmostApplication?.processIdentifier)
        workspaceObserver = workspace.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                self?.setFrontmost(app?.processIdentifier)
            }
        guard observeInput else { return }
        // `addGlobalMonitorForEvents` is a passive observer: it cannot swallow
        // an event, cannot rewrite one, and cannot delay one. That is why it is
        // this rather than a `CGEventTap` — a tap sits in the delivery path of
        // the person's own input, and a bug in it costs them their keyboard.
        inputMonitor = NSEvent.addGlobalMonitorForEvents(matching: Self.inputMask) {
            [weak self] event in
            self?.considerInput(event)
        }
    }

    private func removeOnMain() {
        if let observer = workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            workspaceObserver = nil
        }
        if let monitor = inputMonitor {
            NSEvent.removeMonitor(monitor)
            inputMonitor = nil
        }
    }

    // MARK: - The three filters

    /// Was that a person? The filters and their direction live in
    /// `PersonInput.isAPerson`; this reads the two fields it needs off the event
    /// and nothing else.
    private func considerInput(_ event: NSEvent) {
        let cg = event.cgEvent
        let sourcePid = cg?.getIntegerValueField(.eventSourceUnixProcessID)
        let userData = cg?.getIntegerValueField(.eventSourceUserData)
        lock.lock(); defer { lock.unlock() }
        let since = lastSyntheticPostAt.map { now() - $0 }
        guard PersonInput.isAPerson(sourcePid: sourcePid, userData: userData,
                                    sinceSyntheticPost: since, grace: grace) else { return }
        lastUserInputAt = now()
    }

    // MARK: - The facts

    private func setFrontmost(_ pid: Int32?) {
        lock.lock(); defer { lock.unlock() }
        frontmostPid = pid
    }

    func setExpectedPid(_ pid: Int32?) {
        lock.lock(); defer { lock.unlock() }
        expectedPid = pid
    }

    func noteSyntheticPost() {
        lock.lock(); defer { lock.unlock() }
        lastSyntheticPostAt = now()
    }

    /// Recorded without going through `considerInput`'s filters, because the
    /// caller has already applied a stricter one: the block swallows only what
    /// Proctor did not post, so anything it hands over is by definition somebody
    /// else driving this machine. One timestamp, as ever — no keycode, no
    /// character, no location.
    func noteUserInput() {
        lock.lock(); defer { lock.unlock() }
        lastUserInputAt = now()
    }

    func sample() -> ContentionSample {
        lock.lock()
        let expected = expectedPid
        let front = frontmostPid
        let input = lastUserInputAt
        let mine = ourOwnPids()
        lock.unlock()
        return ContentionSample(expectedPid: expected, frontmostPid: front,
                                proctorPids: mine,
                                secureInput: Grants.secureEventInputActive(),
                                lastUserInputAt: input, now: now())
    }

    /// Proctor's own processes: this agent, and the menu-bar application that
    /// carries Pause and Resume. Somebody opening Proctor's own menu to release
    /// a held run must not be read as taking the machine — the run they are
    /// releasing would hold itself again on the way.
    ///
    /// Cached, and refreshed at most once a second. `sample()` is called on
    /// every poll of a parked run, and enumerating every running application
    /// sixteen times a second to answer a question whose answer changes when
    /// Proctor is launched would be a real cost for no information.
    private var ownPids: Set<Int32> = []
    private var ownPidsAt: Double = -1

    private func ourOwnPids() -> Set<Int32> {
        let stamp = now()
        guard stamp - ownPidsAt >= 1 else { return ownPids }
        ownPidsAt = stamp
        var out: Set<Int32> = [ProcessInfo.processInfo.processIdentifier]
        // Proctor's identity is named, not inferred. `Bundle.main.bundleIdentifier`
        // used to work here only because the agent inherited the app's Info.plist;
        // since PRO-0040 it carries its own, so reading it back would return the
        // agent's identity, match no running application, and quietly drop the
        // menu-bar app out of this set. The run would then hold itself again the
        // moment somebody opened Proctor's menu to release it.
        for app in NSWorkspace.shared.runningApplications
        where Wire.isProctor(bundleIdentifier: app.bundleIdentifier) {
            out.insert(app.processIdentifier)
        }
        ownPids = out
        return out
    }
}
