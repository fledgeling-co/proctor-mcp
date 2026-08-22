import Foundation
import AppKit
import ProctorCore

/// Everything stateful in the agent lives here, behind one actor.
///
/// The state is the point rather than an optimisation. A retained
/// AXUIElementRef keeps resolving when its window moves to another Space; a
/// fresh enumeration does not find it. Electron trees stay empty until
/// AXManualAccessibility is set on the application element and the tree has
/// warmed. AXObservers have to be long-lived. A server that re-enumerated on
/// every call would pass against one frontmost window and then fail on
/// background windows, other Spaces and Electron apps — reported as "element
/// not found", which a model papers over by retrying.
///
/// An actor rather than a lock because the operations are async (capture and
/// settle both await) and because serialising them is correct anyway: two
/// concurrent actions against the same window would each settle on the other's
/// changes.
actor Session {

    let ax: any AXEngine
    /// What performs a step. Separate from `ax` since PRO-0044: observation and
    /// actuation are two halves with two owners, and this is the one that can be
    /// somebody else's.
    let actuator: any ActuationBackend
    let capture: any CaptureEngine
    let reflector: any ReflectorBridge
    let tri: (any TriObserving)?
    let settler: Settler
    /// Whether the tool the browser handoff names is actually installed. Owned
    /// here rather than reached for as a shared singleton, so a test drives its
    /// own and leaves nothing behind.
    let tools: ToolProbes
    /// The bounded Screen Recording probe. Injected for the same reason
    /// `ToolProbes` is: the real one asks the platform, and a suite that let it
    /// would answer differently on a granted machine than on a denied one — and,
    /// measured, would hang outright inside a test host.
    let screenRecordingProbe: ScreenRecordingProbe
    /// Reads Accessibility, injectable for the same reason `screenRecordingProbe`
    /// is. `AXIsProcessTrusted()` answers for whatever process asks it, so a
    /// suite that leaves this at its default is asserting on whether the
    /// terminal that launched `swift test` happens to hold the grant, which is
    /// ambient machine state the test neither controls nor declares.
    let accessibilityProbe: @Sendable () -> Bool
    /// Whether `/usr/bin/shortcuts` is on this Mac, injectable for exactly the
    /// reason the two probes either side of it are: it is a fact about the
    /// machine running the suite rather than about the code under test.
    ///
    /// PRO-0082 added the seam because the clause it needed to prove — that the
    /// health report never files a tool under `grants` — is only interesting on a
    /// Mac that is MISSING the CLI, since that was the only condition under which
    /// the old code appended it. Every Mac in this fleet has it, so without this
    /// the test would pass on a case it never reached and its arming would be
    /// vacuous.
    let shortcutsProbe: @Sendable () -> Bool
    /// Reads Secure Event Input, injectable for exactly the reason above, and
    /// added because fixing only the Accessibility half left the same test
    /// failing on the other one. Secure input is on whenever anything anywhere
    /// on the Mac holds a password field, so a suite that leaves this at its
    /// default passes or fails on what the person at the keyboard is doing.
    let secureInputProbe: @Sendable () -> Bool

    /// How many past trees are retained per window to serve a sinceRevision
    /// diff. A caller more than this far behind is diffed from the oldest tree
    /// still held, and the diff says which revision that was.
    static let historyDepth = 5

    struct TreeRevision: Sendable {
        let revision: Int
        let node: AXNode
        let hash: String
    }

    struct WalkOutcome: Sendable {
        let root: AXNode
        let provenance: TreeProvenance
        let revision: Int
        let hash: String
        let previous: TreeRevision?
        let history: [TreeRevision]
    }

    struct SnapshotOptions: Sendable {
        var root: String?
        var maxDepth: Int = 24
        // 2000 returns promptly on an ordinary window and takes tens of seconds
        // on a large icon-view list, where the target's own accessibility
        // implementation is the cost. 600 covers the windows a test actually
        // drives; raise it deliberately when a wide tree is the subject.
        var maxNodes: Int = 600
        var includeInvisible: Bool = false
    }

    private var apps: [String: AppHandle] = [:]
    private var provenanceByApp: [String: TreeProvenance] = [:]
    private var windowsByID: [String: WindowHandle] = [:]
    private var revisions: [String: Int] = [:]
    private var history: [String: [TreeRevision]] = [:]

    private(set) var flows: [String: RecordedFlow] = [:]
    private(set) var recording: String?
    private var flowsLoaded = false

    /// Parsed scripting dictionaries, keyed by app handle id. The id carries the
    /// launch epoch, so a relaunched app is a different key and its stale entry
    /// is never served — per-PID caching that invalidates on relaunch for free.
    var dictionaryCache = ScriptingDictionaryCache()

    /// The simulators **this session** booted, by udid.
    ///
    /// Session-scoped on purpose and named that way on the wire: it lives in
    /// memory and does not survive the agent restarting, so a device booted by an
    /// earlier session is indistinguishable from one a person booted. Proctor
    /// never shuts a device down, so this is not a cleanup list — it is what makes
    /// "Proctor left this running" answerable by the person who has to decide
    /// about it.
    var bootedDevices: Set<String> = []

    /// Injected guest adapters. Nil means "build them from the filesystem
    /// probes". An empty array is a machine with neither CLI, which the
    /// session reports as a missing-tool refusal rather than an empty listing.
    var injectedGuestProviders: [any GuestProvider]?

    /// Scheme → bundle id per device, with the fingerprint of the installed-app
    /// set it was built from. Rebuilt when that set changes; a map costs one
    /// Info.plist read per installed app, which is worth caching and not worth
    /// serving stale after an install.
    var iosSchemeMaps: [String: (fingerprint: String, map: [String: String])] = [:]

    /// Devices with an iOS operation in flight, by udid.
    ///
    /// A deep link's before/after samples are only evidence if nothing else drove
    /// the device between them, and this actor is reentrant — isolation drops at
    /// every `await`, so a boot's poll loop or a second `open` would otherwise
    /// interleave and the pixels would belong to whichever call happened to be
    /// running. This bounds what Proctor itself did; a person tapping the
    /// simulator is outside anybody's control, which is why the verdict states
    /// what it cannot attribute rather than pretending to a closed world.
    var iosBusyDevices: Set<String> = []

    /// The app policy gate and the live approval token. The policy is loaded from
    /// disk on first use; an absent file is an empty policy, which allows every
    /// app, so the gate is inert until an operator configures it. The token is
    /// session-only and TTL-bounded — nothing persists a standing authority to
    /// drive a sensitive app across a restart.
    var policy = AppPolicy()
    var approvalToken: ApprovalToken?
    var policyLoadedFlag = false

    /// Where every audit record goes, and what time it is when the approval
    /// token's TTL is judged. Both are the real thing by default; they are
    /// substitutable so the gate's wiring can be exercised without writing to the
    /// operator's trail or sleeping across a token expiry. See SessionPolicy.
    ///
    /// **The default writes nothing in a test process.** `AuditLog` already
    /// redirects a test's trail away from the operator's, and that interlock is
    /// the floor; this is the second half of it. A session built without an
    /// injected sink used to append to whatever trail was current, which let one
    /// suite's entries land in another suite's file and made a count-based
    /// assertion depend on what else happened to be running. A test that wants to
    /// exercise the append path calls `AuditLog.append` directly, which is
    /// deliberate rather than incidental.
    var auditSink: @Sendable (AuditRecord) -> Void = { record in
        guard !AuditLog.isTestProcess else { return }
        _ = AuditLog.append(record)
    }
    var clock: @Sendable () -> Double = { Date().timeIntervalSince1970 }

    /// Where the app policy is read from and written to. `.live` is the operator's
    /// own policy on a real Mac and a per-process temporary directory in a test
    /// process, so a suite that forgets to inject still cannot reach the operator's
    /// file; a suite that means to exercise `configure` injects one and reads back
    /// what it wrote. See `PolicyStore` and `SessionPolicy.setPolicyStore`.
    var policyStore: PolicyStore = .live

    /// The recommendations already recorded this run, keyed by application, lane,
    /// rule and scheme. A repeat of the same advice is the same act: the advisory
    /// rides every listing, attach, snapshot, find and step batch, so recording
    /// each one would make the trail mostly recommendations and would time-stamp
    /// somebody's browsing minute by minute. PRO-0024 set the precedent when it
    /// emitted the full advisory once at attach, for the same reason.
    var recordedRecommendations: Set<String> = []

    /// The filesystem jail: the declared roots any caller-supplied path must stay
    /// within, resolved on first use from PROCTOR_FS_ROOTS. Nil-then-empty until
    /// loaded; an unset environment variable yields an empty jail, which admits
    /// every path, so the containment convention is dormant until configured.
    var fsJail: FSJail?
    var fsJailLoadedFlag = false

    /// Whether this session feeds the run HUD at all.
    ///
    /// Not the same question as whether a panel is on screen. That one belongs to
    /// `RunHUDFeed`, is seeded from `PROCTOR_HUD`, and can be moved from the menu
    /// bar mid-run — and the events reduce either way, because the menu bar's
    /// character reads the same phase and has to stay truthful with no panel
    /// anywhere. This flag exists so a unit test can keep the whole HUD path out
    /// of its way.
    var drawsHUD = true
    func setDrawsHUD(_ on: Bool) { drawsHUD = on }

    /// Where the HUD's state actually lives. The shared one in production, so the
    /// panel, the run and Proctor's menu bar are all talking about one run;
    /// substitutable so a test can drive the switch and read the phase without
    /// reaching into a singleton another test is also using.
    nonisolated let hudFeedBox = HUDFeedBox()
    var hudFeed: RunHUDFeed { hudFeedBox.feed }
    func setHUDFeed(_ feed: RunHUDFeed) { hudFeedBox.feed = feed }

    /// Whether a panel this process drew actually came up, and why not.
    ///
    /// The same reasoning as `hudFeedBox` one line above, applied to the other
    /// input `hudStatus` reads. `RunHUDAvailability.shared` is process-wide and
    /// mutable, so a test that substituted its feed still had its answer decided
    /// by whichever *other* test last called `record`. That made the four-absence
    /// case fail about one full-suite run in five, always on the row that expects
    /// nothing to be wrong, and always with another test's reason in it.
    var hudAvailability: @Sendable () -> (available: Bool, reason: String?) = {
        RunHUDAvailability.shared.status
    }
    func setHUDAvailability(_ probe: @escaping @Sendable () -> (available: Bool, reason: String?)) {
        hudAvailability = probe
    }

    /// Which machine THIS CALLER's runs happen on.
    ///
    /// PRO-0076 made this a lookup rather than a stored value, and the reason is
    /// that there is exactly one `Session` in this agent. `main.swift` builds it
    /// once; callers are told apart by `SessionIdentity.current`, a task-local
    /// read from the peer process. So an attach that wrote a shared field would
    /// move every connected client onto the guest at once.
    ///
    /// The stored `fallbackMachine` is kept rather than removed. It is what
    /// `setMachine` writes, which is how a test declares a whole session's
    /// machine without standing up an attachment; deleting it would silently
    /// revert four suites' guest coverage to the host.
    var machine: Machine {
        guestAttachments[SessionIdentity.current.key]?.machine ?? fallbackMachine
    }
    private var fallbackMachine: Machine = .host
    func setMachine(_ machine: Machine) { self.fallbackMachine = machine }

    /// Attachments, one per session identity. See `GuestAttachment`.
    var guestAttachments: [String: GuestAttachment] = [:]

    /// Window ids minted inside a guest, and which session minted them.
    ///
    /// Kept beside the attachments rather than inside one because the refusal in
    /// `GuestHandleScope` has to answer for a handle whose owning session has
    /// already detached — otherwise the id would fall through to the host's own
    /// window map and resolve against the wrong computer.
    var guestMintedHandles: [String: GuestHandleScope.Origin] = [:]

    /// This caller's attachment, or nil.
    var currentAttachment: GuestAttachment? {
        guestAttachments[SessionIdentity.current.key]
    }

    /// The open channel to each attached guest.
    var guestLinks: [String: any GuestLink] = [:]

    /// The pool slot each attachment holds.
    ///
    /// Held for the ATTACHMENT rather than for a batch, which is the spec's
    /// recorded assumption: booting a macOS guest costs tens of seconds, and
    /// releasing per batch would re-pay that across a campaign. The consequence
    /// is that the slot needs its own release rule, since nothing about a run
    /// ending frees it — see `releaseGuestAttachment`.
    var guestTickets: [String: LaneTicket] = [:]

    /// Injected so a test can attach without a socket. Nil means the live link.
    var injectedGuestLink: (@Sendable (String) -> any GuestLink)?
    func setGuestLinkFactory(_ make: @escaping @Sendable (String) -> any GuestLink) {
        injectedGuestLink = make
    }

    /// The pause/stop latch the panel's buttons write to.
    ///
    /// NOT `RunControl.shared` BY DEFAULT, and the inversion is the whole of
    /// PRO-0055. The panel writes the process-wide latch directly, so the agent
    /// must hand this session that same one or Pause and Stop would reach
    /// nothing — and it does, at `main.swift`, which is the one construction that
    /// wants process-wide state and now says so. Every other construction gets a
    /// latch of its own.
    ///
    /// The old default was the singleton, on the reasoning that production is
    /// the case that matters. It is, and it was still wrong: a default is taken
    /// by whoever does not think about it, so the dangerous value must be the
    /// one somebody has to name. Measured before the change, five test suites
    /// parked the shared latch and every later run inherited the park.
    var runControl: RunControl
    func setRunControl(_ control: RunControl) { runControl = control }

    /// Where "is a person using this Mac" is read from. Defaulted to a quiet
    /// machine for the reason on `NullContentionMonitor`, and given the live one
    /// by the agent.
    var contentionMonitor: any ContentionSampling
    func setContentionMonitor(_ monitor: any ContentionSampling) { contentionMonitor = monitor }

    /// The full-screen statement, and the block behind it. Substitutable for the
    /// same reason: neither a panel nor an event tap exists in a test process.
    var takeover: any TakeoverDriving = LiveTakeover()
    func setTakeover(_ driver: any TakeoverDriving) { takeover = driver }
    /// Whether this run has raised the statement. Per batch, not per step.
    var takeoverShown = false

    /// The declaration seam, injected for the same reason as the two above.
    ///
    /// The default is the shared instance and production never calls the setter,
    /// because the two ends of this protocol are reached statically: the real
    /// actuator declares on `SyntheticPost.shared` from
    /// `requireEventPlaneAvailable`, and the event tap reads `.shared.inFlight`.
    /// A session pointed anywhere else would never hear a real post.
    ///
    /// What it buys is the test process, where several `Session`s exist at once.
    /// Each has its own `RunScheduler`, so the exclusive-global-lane invariant
    /// that makes one shared instance safe in production does not hold there,
    /// and two suites driving posting batches otherwise clear each other's
    /// declarations.
    var syntheticPost = SyntheticPost.shared
    func setSyntheticPost(_ post: SyntheticPost) { syntheticPost = post }

    /// Both switches, read once. `PROCTOR_YIELD` is on unless turned off;
    /// `PROCTOR_YIELD_INPUT` is off unless turned on, and the asymmetry is the
    /// point — the input monitor is an opt-in, not a default with an escape.
    var yieldEnabled = ContentionMonitor.enabled(in: ProctorEnvironment.current)
    var yieldInputObserved = ContentionMonitor.inputObserved(in: ProctorEnvironment.current)
    func setYieldSwitches(enabled: Bool, observesInput: Bool) {
        yieldEnabled = enabled
        yieldInputObserved = observesInput
    }

    /// The keeper that holds a run's lanes for the length of a call.
    ///
    /// Owned by the session rather than reached for as a global, and that is the
    /// right shape rather than a convenience: there is exactly one `Session` in
    /// the agent and every connection goes through it, so one session is one
    /// machine's worth of lanes. `nonisolated` because it is an actor of its own
    /// and the panel reads it before hopping anywhere.
    nonisolated let runScheduler: RunScheduler

    /// The most recent capture's encoded metadata, served cache-only by the
    /// screenshot/latest resource. Holding the metadata (not the bytes) keeps the
    /// resource readable without a Screen Recording grant and without triggering a
    /// new capture.
    private var lastCapture: JSONValue?

    /// A small ring of the tools most recently dispatched, plus whichever is
    /// in flight, so the menu bar and status window can answer "what is Proctor
    /// doing right now". Only the model-driven tools land here — the UI's own
    /// health and activity polls are filtered out at the dispatch choke point so
    /// they don't drown the real work. Names are stored without the `proctor_`
    /// prefix, the way the surfaces show them.
    struct ActivityEntry: Sendable {
        let tool: String
        let at: Date
        let ok: Bool
    }
    private var activityRing: [ActivityEntry] = []
    private var activityCurrent: String?
    private static let activityDepth = 20

    /// A tool started. Recorded as in-flight until `activityEnd` completes it.
    func activityBegin(tool: String) { activityCurrent = tool }

    /// A tool finished; move it from in-flight into the completed ring.
    func activityEnd(tool: String, ok: Bool) {
        if activityCurrent == tool { activityCurrent = nil }
        activityRing.append(ActivityEntry(tool: tool, at: Date(), ok: ok))
        if activityRing.count > Self.activityDepth {
            activityRing.removeFirst(activityRing.count - Self.activityDepth)
        }
    }

    /// The recent-activity feed for the internal `proctor_recent_activity` verb
    /// the UI polls: the tool in flight now (if any) and the completed ring,
    /// newest first. Never a ToolCatalogue tool, so a host cannot reach it.
    func recentActivity(limit: Int = 12) -> JSONValue {
        let iso = ISO8601DateFormatter()
        let recent = activityRing.suffix(limit).reversed().map { entry in
            JSONValue.object([
                AgentVerbs.Activity.tool: .string(entry.tool),
                AgentVerbs.Activity.at: .string(iso.string(from: entry.at)),
                AgentVerbs.Activity.ok: .bool(entry.ok)
            ])
        }
        return .object([
            AgentVerbs.Activity.current: activityCurrent.map(JSONValue.string) ?? .null,
            AgentVerbs.Activity.recent: .array(Array(recent)),
            // The menu bar mirrors the waiting count, so the queue is answerable
            // without the run panel being on screen at all.
            AgentVerbs.Activity.queueWaiting: .number(Double(queueWaitingMirror)),
            // And the run HUD's phase, which is what lets the menu bar draw the
            // same character in the same state — the one `RunHUDState` reduced,
            // never a second one derived here.
            AgentVerbs.Activity.hud: hudFeed.wire,
            AgentVerbs.Activity.foreground: foregroundJSON
        ])
    }

    // MARK: - Whether a run is taking the machine

    /// The live answer to "is Proctor about to take the foreground, or taking it
    /// right now", mirrored here for the menu bar.
    ///
    /// The run panel already says this, and says it the instant it changes — but
    /// it lands on one display, and the person whose machine it is may be
    /// looking at another. The menu bar is on every display's menu bar and is
    /// already Proctor's, so the same fact is readable there whichever screen
    /// the panel went to, and readable with the panel switched off entirely.
    ///
    /// The UI polls at a fixed interval, so `active` is a sample rather than a
    /// trace: a synthetic step shorter than one poll can begin and end between
    /// two of them and never be seen there. The panel is the instantaneous
    /// surface; this is the one that does not depend on which screen you are
    /// looking at. Neither replaces the other.
    struct ForegroundState: Sendable {
        var demand = ForegroundDemand()
        var app: String?
        /// A step is travelling the event stream at this moment.
        var active = false
    }

    /// Keyed by run, not held as one value. Two runs driving DIFFERENT
    /// applications are not serialised — that is the point of the app lanes —
    /// so a single slot would let a background-safe run finishing wipe the state
    /// of a foreground run still posting events, and the menu bar would say the
    /// machine was free while it was being taken.
    private var foregroundRuns: [Int: ForegroundState] = [:]
    private var nextForegroundRun = 0

    /// A batch is starting, and what it is going to do to the foreground is
    /// already known from its steps. The token is the run's own; hand it back to
    /// `foregroundStep` and `foregroundEnded` so a run only ever edits its own
    /// entry.
    func foregroundBegan(demand: ForegroundDemand, app: String?, window: Rect? = nil) -> Int {
        nextForegroundRun += 1
        let token = nextForegroundRun
        foregroundRuns[token] = ForegroundState(demand: demand, app: app)
        // The yield watch is keyed by the same token for the same reason: two
        // runs on different applications overlap, and a harmless one ending must
        // not throw away what a contending one is holding.
        var yield = YieldRun()
        // Carried now rather than looked up later: a hold has to be able to name
        // the application and the display it belongs to at the instant it
        // latches, and re-resolving a window handle mid-hold is a read against
        // an application somebody has just walked away from.
        yield.app = app
        yield.window = window
        yieldRuns[token] = yield
        return token
    }

    /// One step travelled. `active` is set from the plane it actually used, so a
    /// `type` that fell back to the event stream shows here exactly as a click
    /// does — the menu bar reports what happened, not what was predicted.
    func foregroundStep(run token: Int, plane: ActuationPlane?) {
        foregroundRuns[token]?.active = plane == .syntheticEvent
    }

    func foregroundEnded(run token: Int) {
        foregroundRuns.removeValue(forKey: token)
    }

    // MARK: - Whether a person is taking it back

    /// One run's contention bookkeeping: the decision value, what it is holding
    /// now, and every hold it has already finished.
    struct YieldRun: Sendable {
        var watch = ContentionWatch()
        var records: [YieldRecord] = []
        var armed = false
        /// The open hold, if any: when it started and what it is holding before.
        var openedAt: Double?
        var openReason: YieldReason?
        var openStep: Int?
        /// The app and the window this run is driving, kept so a hold can be
        /// attributed without re-resolving a handle at the moment it is read.
        var app: String?
        var window: Rect?
        /// Whose the open hold is, for every surface that can carry a name.
        var openHold: HoldAttribution?
    }

    private var yieldRuns: [Int: YieldRun] = [:]

    func yieldRun(_ token: Int) -> YieldRun? { yieldRuns[token] }
    func setYieldWatch(_ watch: ContentionWatch, run token: Int) {
        yieldRuns[token]?.watch = watch
    }

    /// Arm the watch for a run that is actually going to contend. An
    /// accessibility-plane run samples nothing, installs nothing, and can never
    /// be held — holding it would be noise about a run that never took anything.
    func armContention(run token: Int, because reason: String) {
        guard yieldEnabled, yieldRuns[token]?.armed == false else { return }
        yieldRuns[token]?.armed = true
        contentionMonitor.arm(observeInput: yieldInputObserved)
        _ = reason
    }

    func disarmContention(run token: Int) async {
        guard let run = yieldRuns[token] else { return }
        if run.armed { contentionMonitor.disarm() }
        // A hold still open when the run ends is closed against the run rather
        // than left dangling, so the record accounts for the whole of it. Read
        // from the latch rather than passed in, because the panel's own Stop
        // writes `RunControl.shared` directly and never comes through here.
        if var run = yieldRuns[token], run.openReason != nil {
            closeOpenHold(&run, endedBy: runControl.isStopped ? .stopped : .runEnded)
            yieldRuns[token] = run
        }
        // The RECORD is closed above; the LATCH is closed here, and they were not
        // the same thing. A run that ended while yielded left its entry in
        // `RunControl.yields` forever: `paused` stayed true, `pausedAt` was never
        // cleared, and `heldBy` went on naming a run that had finished, so the
        // next run's `begin` could not clear the clock either. An automatic hold
        // belongs to one run, so it ends when that run does.
        runControl.release(run: RunScheduler.currentRun)
        // The three endings the probe never sees — a person's Stop, the
        // backstop giving up, and the run simply finishing — all unwind through
        // here, so this is where the published copy is cleared for them. Without
        // it a ticket would carry a hold that the latch had already dropped, and
        // the panel would show a machine held by nothing.
        await runScheduler.unhold(run: RunScheduler.currentRun)
    }

    /// What the run reports afterwards. Removes the run's entry, so this is
    /// called once, at the end.
    func takeYieldRecords(run token: Int) -> [YieldRecord] {
        let records = yieldRuns.removeValue(forKey: token)?.records ?? []
        return records
    }

    /// Proctor has demonstrably put an application in front — a step whose
    /// measured plane was the event stream, or a settled raise. Only now is
    /// there something for a person to take back, which is why this is set from
    /// what happened rather than from what was predicted.
    func noteTookForeground(pid: Int32?) {
        contentionMonitor.setExpectedPid(pid)
        contentionMonitor.noteSyntheticPost()
    }

    /// The probe `RunControl` runs at every checkpoint and on every poll while
    /// the run is parked. It is the only place contention policy lives: sample,
    /// decide, and move the same latch a person's Pause moves.
    func contentionProbe(run token: Int, step: Int) async {
        guard var run = yieldRuns[token], run.armed else { return }
        // A person's decision is read first and consumed here, whichever surface
        // took it. Doing it before the sample is what stops the same still-true
        // condition re-yielding in the very poll that followed the Resume.
        if runControl.takePersonResume() {
            run.watch.resumedByPerson()
            closeOpenHold(&run, endedBy: .person)
            // A person's Resume ends the hold, so the copy the panel reads has
            // to end with it. One of the five paths A2 pins.
            await runScheduler.unhold(run: RunScheduler.currentRun)
        }
        let change = run.watch.sample(contentionMonitor.sample())
        switch change {
        case .none:
            yieldRuns[token] = run
        case .yielded(let reason):
            // A hold already open under a different reason is closed and a new
            // one opened, so the record says what actually held it and for how
            // long rather than blaming the last reason for the whole wait.
            closeOpenHold(&run, endedBy: .released)
            let hold = attribution(reason, run: token)
            run.openReason = reason
            run.openedAt = monotonicNow()
            run.openStep = step
            run.openHold = hold
            yieldRuns[token] = run
            // The latch first, because it is the decision and the buttons write
            // it synchronously; the scheduler second, because it is the copy
            // every surface reads. `RunScheduler.currentRun` is this call's own
            // ticket, carried by task-local through the actor's reentrancy.
            let ticket = RunScheduler.currentRun
            runControl.yield(run: ticket, hold: hold)
            await runScheduler.hold(run: ticket, hold)
            await hud(.yielded(reason: reason))
            RunHUDPanel.audit("run.yielded", detail: reason.detail)
            // Gated exactly as `hud()` is. A hop to the main actor to redraw a
            // panel this session is not feeding is a dependency the run does
            // not need, and one it can be made to wait on.
            if drawsHUD { await RunHUDPanel.shared.refresh() }
        case .released(let reason):
            closeOpenHold(&run, endedBy: .released)
            yieldRuns[token] = run
            let ticket = RunScheduler.currentRun
            runControl.release(run: ticket)
            await runScheduler.unhold(run: ticket)
            // A person's own Pause is not lifted by a contention clearing. The
            // latch keeps both causes apart; this only says so on the panel when
            // the run is actually carrying on again.
            if !runControl.isParked(run: ticket) {
                await hud(.unyielded)
                RunHUDPanel.audit("run.resumed",
                                  detail: "the run carried on: \(reason.rawValue) cleared")
                if drawsHUD { await RunHUDPanel.shared.refresh() }
            }
        }
    }

    private func closeOpenHold(_ run: inout YieldRun, endedBy: YieldEnd) {
        guard let reason = run.openReason, let at = run.openedAt else { return }
        run.records.append(YieldRecord(reason: reason, step: run.openStep,
                                       heldMs: Int(max(0, monotonicNow() - at) * 1000),
                                       endedBy: endedBy))
        run.openReason = nil
        run.openedAt = nil
        run.openStep = nil
        run.openHold = nil
    }

    /// Whose a hold is: the reason, the session, the application under test and
    /// the display that application is on.
    ///
    /// Every part is derived. The session label comes from the peer process the
    /// connection belongs to and never from anything a client said about itself,
    /// because a connection that could name itself could impersonate another one
    /// in the very UI a person uses to decide whether to stop it. The display
    /// comes from the driven window's own frame.
    func attribution(_ reason: YieldReason, run token: Int) -> HoldAttribution {
        let run = yieldRuns[token]
        return HoldAttribution(reason: reason,
                               session: SessionIdentity.current.label,
                               app: run?.app,
                               display: HoldAttribution.display(for: run?.window,
                                                                in: Self.screenBounds(),
                                                                mainIndex: Self.mainScreenIndex()))
    }

    /// The screens, from CoreGraphics rather than NSScreen — which is main-actor
    /// bound while this actor is not, the same reason the display resource and
    /// `StreamCapture` read CoreGraphics directly.
    ///
    /// `CGDisplayBounds` and an accessibility window frame are both Quartz global
    /// space (y down from the top of the primary display), so the overlap
    /// arithmetic compares like with like. `RunHUDPlacement` is documented in
    /// AppKit space because that is what the panel needs; the containment
    /// question it answers is space-agnostic as long as both sides agree, and
    /// here they do.
    nonisolated static func screenBounds() -> [Rect] {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        guard count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        return ids.prefix(Int(count)).map { id in
            let bounds = CGDisplayBounds(id)
            return Rect(x: bounds.origin.x, y: bounds.origin.y,
                        w: bounds.size.width, h: bounds.size.height)
        }
    }

    nonisolated static func mainScreenIndex() -> Int? {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        guard count > 0 else { return nil }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &ids, &count)
        return ids.prefix(Int(count)).firstIndex(of: CGMainDisplayID())
    }

    /// Substitutable so a held-for-N-milliseconds assertion does not need to
    /// wait N milliseconds.
    var monotonicNow: @Sendable () -> Double = { Date().timeIntervalSince1970 }
    func setMonotonicNow(_ clock: @escaping @Sendable () -> Double) { monotonicNow = clock }

    /// What the menu bar reads: whether anything is held right now, why, and
    /// whose it is.
    ///
    /// The menu bar's ICON is one glyph and cannot carry a name, so it is not
    /// asked to — its ladder is untouched and still shows precedence alone. This
    /// is the menu bar's *words*, which can, and the status window reads the
    /// same block. A person seeing a hold indicator and not knowing whose run it
    /// is has the wrong half of the information on a machine running three
    /// sessions.
    private var yieldJSON: JSONValue {
        let holds = yieldRuns.values.compactMap(\.openHold)
        // Highest precedence first, the same order the reasons are declared in,
        // so the one shown is the one that most explains why injected input is
        // least welcome right now.
        guard let hold = YieldReason.allCases.lazy
            .compactMap({ reason in holds.first { $0.reason == reason } }).first else {
            return .object([AgentVerbs.Foreground.active: .bool(false),
                            "reason": .null, AgentVerbs.Foreground.line: .null,
                            "session": .null, "app": .null, "display": .null])
        }
        return .object([AgentVerbs.Foreground.active: .bool(true),
                        "reason": .string(hold.reason.rawValue),
                        AgentVerbs.Foreground.line: .string(hold.line),
                        "session": .string(hold.session),
                        "app": hold.app.map(JSONValue.string) ?? .null,
                        "display": hold.display.map { .string($0.name) } ?? .null])
    }

    /// The whole machine's answer, folded over every run in flight. Any run
    /// posting an event means the machine is being taken; the notice shown is
    /// the one from a run that will take it, since that is the one worth
    /// reading when a harmless run is going on beside it.
    private var foregroundJSON: JSONValue {
        let runs = foregroundRuns.values
        let taking = runs.filter(\.demand.takesForeground)
        let subject = taking.first ?? runs.first
        return .object([
            AgentVerbs.Foreground.running: .bool(!runs.isEmpty),
            AgentVerbs.Foreground.active: .bool(runs.contains { $0.active }),
            AgentVerbs.Foreground.takesForeground: .bool(!taking.isEmpty),
            AgentVerbs.Foreground.mayTakeForeground:
                .bool(runs.contains { $0.demand.mayTakeForeground }),
            "certain": .number(Double(subject?.demand.certainSteps ?? 0)),
            "conditional": .number(Double(subject?.demand.conditionalSteps ?? 0)),
            "total": .number(Double(subject?.demand.totalSteps ?? 0)),
            "runs": .number(Double(runs.count)),
            "app": subject?.app.map(JSONValue.string) ?? .null,
            // Which lane is performing the steps, so the fact does not depend on
            // which display the run panel landed on. Proctor's own enum, never a
            // string the driver supplied.
            "backend": .string(actuator.id.rawValue),
            AgentVerbs.Foreground.notice: subject.flatMap {
                $0.demand.notice(app: $0.app, delegated: actuator.id != .native)
            }.map(JSONValue.string) ?? .null,
            // Held, and why. Read ahead of `active` by the menu bar: a run that
            // has got out of somebody's way is not taking the machine, and
            // saying both at once would be two claims about one instant.
            AgentVerbs.Foreground.yield: yieldJSON
        ])
    } /// The waiting count, kept here so the UI's own poll answers without hopping
    /// to the scheduler. Written by the scheduler's observer at start-up.
    private var queueWaitingMirror = 0
    func setQueueWaiting(_ count: Int) { queueWaitingMirror = count }

    init(ax: any AXEngine,
         capture: any CaptureEngine,
         reflector: any ReflectorBridge = NullReflectorBridge(),
         tri: (any TriObserving)? = nil,
         scheduler: RunScheduler = RunScheduler(),
         tools: ToolProbes = ToolProbes(),
         screenRecordingProbe: ScreenRecordingProbe = .live,
         accessibilityProbe: @escaping @Sendable () -> Bool = { Grants.accessibility() },
         shortcutsProbe: @escaping @Sendable () -> Bool = {
             FileManager.default.isExecutableFile(atPath: "/usr/bin/shortcuts")
         },
         secureInputProbe: @escaping @Sendable () -> Bool = { Grants.secureEventInputActive() },
         actuator: (any ActuationBackend)? = nil,
         runControl: RunControl = RunControl(),
         contentionMonitor: any ContentionSampling = NullContentionMonitor()) {
        self.runScheduler = scheduler
        self.ax = ax
        self.capture = capture
        self.reflector = reflector
        self.tri = tri
        self.tools = tools
        self.screenRecordingProbe = screenRecordingProbe
        self.runControl = runControl
        self.contentionMonitor = contentionMonitor
        self.accessibilityProbe = accessibilityProbe
        self.shortcutsProbe = shortcutsProbe
        self.secureInputProbe = secureInputProbe
        self.settler = Settler(capture: capture)
        // Defaulted to the native planes wrapping the same engine, so every
        // existing construction — and every existing test — builds a session
        // that actuates exactly as it did before this seam existed.
        self.actuator = actuator ?? NativeActuationBackend(ax: ax)
    }

    // MARK: - Handles

    func windowHandle(_ id: String) throws -> WindowHandle {
        // A4. A window handle belongs to the machine that minted it, and to the
        // session that was attached when it did. Checked BEFORE the cache,
        // because a host id under a guest session would otherwise hit the host's
        // own map and drive the wrong computer while the result said "guest".
        //
        // **Scoped to handles that actually crossed a machine boundary**, which
        // is narrower than "any guest session" and is the honest reading of the
        // rule. A session can be marked as a guest without an attachment — that
        // is what PRO-0056 and PRO-0057 built, and what four suites still model
        // — and such a session drives its own engine, so its own window map is
        // definitionally the machine it says it is on. There is no second
        // machine's handles to confuse, and refusing there would be a rule about
        // nothing. What is checked is: a handle minted inside a guest (wherever
        // it turns up), and any handle used by a session holding an attachment,
        // whose windows come over a link rather than from this Mac.
        let origin = guestMintedHandles[id]
        if origin != nil || currentAttachment != nil,
           let refusal = GuestHandleScope.refusal(
               handle: id, callerMachine: machine,
               callerSession: SessionIdentity.current.key,
               origin: origin ?? .host) {
            throw AgentError(code: .windowNotFound, message: refusal.message,
                             remedy: refusal.remedy)
        }
        if let cached = windowsByID[id] { return cached }
        // A device handle is refused by name rather than falling through to
        // "unknown window". Proctor's model is windows and a simulator is a device
        // holding apps, so a caller holding a `dev-` handle has not mistyped a
        // window id — it has a category error, and telling it the window was not
        // found would send it round a retry loop looking for one that will never
        // exist. The refusal names the ceiling and the route that does work.
        if IOSHandle.isDeviceHandle(id) {
            let rejection = IOSHandle.rejection(handle: id, tool: "this tool")
            throw AgentError(code: .windowNotFound, message: rejection.message,
                             remedy: rejection.remedy)
        }
        if GuestHandle.isGuestHandle(id) {
            let rejection = GuestHandle.rejection(handle: id, tool: "this tool")
            throw AgentError(code: .windowNotFound, message: rejection.message,
                             remedy: rejection.remedy)
        }
        refreshWindows()
        if let cached = windowsByID[id] { return cached }
        throw AgentError(
            code: .windowNotFound,
            message: "no window with handle \(id)",
            remedy: apps.isEmpty
                ? "Nothing is attached. Call proctor_apps with action \"attach\" first — window handles only exist for attached apps."
                : "Call proctor_apps with action \"list\" to re-read the windows of the attached apps; the window may have closed.")
    }

    func appHandle(forWindow window: WindowHandle) -> AppHandle? { apps[window.app] }

    // MARK: - Browser handoff

    /// The advisory for an application that is a browser, without a window in hand.
    /// Emitted where the instrument is chosen — listing and attaching — and it says
    /// so: no window was named, so no page URL was read.
    func browserHandoff(bundleId: String?, detail: BrowserTarget.Detail,
                        tool: String) -> BrowserHandoff? {
        guard let browser = BrowserCatalogue.identify(bundleId: bundleId) else { return nil }
        recordRecommendation(for: browser, probe: nil, tool: tool, window: nil)
        return BrowserTarget.handoff(for: browser, probe: nil, detail: detail,
                                     lanes: tools.lanes)
    }

    /// The advisory for a window that is showing a page, or nil.
    ///
    /// The catalogue lookup runs first, so a native application costs one dictionary
    /// lookup and no accessibility traffic — a web view inside a Mac app is never
    /// routed, because reaching it means attaching to the host process.
    ///
    /// `targets` are the frames the call actually addressed, in screen coordinates.
    /// Empty means the question is about the window as a whole. Non-empty means the
    /// advisory is emitted only when one of them lies inside a web area, which is
    /// what keeps a click on the reload button from being told to use Obscura.
    func browserHandoff(window: WindowHandle, targets: [Rect] = [],
                        detail: BrowserTarget.Detail = .brief,
                        tool: String) -> BrowserHandoff? {
        guard let browser = BrowserCatalogue.identify(bundleId: appHandle(forWindow: window)?.bundleId)
        else { return nil }
        guard let probe = try? ax.webContent(window: window.id), !probe.areas.isEmpty
        else { return nil }
        if !targets.isEmpty, !targets.contains(where: { probe.contains($0) }) { return nil }
        recordRecommendation(for: browser, probe: probe, tool: tool, window: window.id)
        return BrowserTarget.handoff(for: browser, probe: probe, detail: detail,
                                     lanes: tools.lanes)
    }

    /// Record that Proctor named a lane, once per distinct application, lane,
    /// rule and scheme per run.
    ///
    /// What goes in is the set of facts the decision was made on and nothing
    /// more: PRO-0024 routes on the address's scheme alone, so the scheme is
    /// recorded and the address itself never is. `BrowserTarget.recommendation`
    /// is what derives it, so the only code that touches a URL here is the code
    /// that already decided on one.
    ///
    /// A handoff that names no lane writes nothing. No lane is no recommendation,
    /// so there is no act to record — and the case where Proctor most visibly
    /// decided, declining to point any lane at the browser's own password
    /// surface, is exactly the entry that would say where the person was.
    private func recordRecommendation(for browser: KnownBrowser, probe: WebContentProbe?,
                                      tool: String, window: String?) {
        guard let advice = BrowserTarget.recommendation(for: browser, probe: probe,
                                                        lanes: tools.lanes) else { return }
        let key = [browser.bundleId, advice.lane.rawValue, advice.rule.rawValue,
                   advice.scheme ?? "-"].joined(separator: "|")
        guard recordedRecommendations.insert(key).inserted else { return }
        auditSink(AuditRecord(
            timestamp: clock(), tool: tool, bundleId: browser.bundleId, window: window,
            outcome: AuditRecord.Outcome.recommended,
            recommendation: LaneRecommendation(lane: advice.lane.rawValue,
                                               rule: advice.rule.rawValue,
                                               scheme: advice.scheme),
            run: RunIdentity.current))
    }

    /// An attached app by its handle id, or nil if nothing is attached under it.
    func appHandle(id: String) -> AppHandle? { apps[id] }

    private func refreshWindows() {
        for appID in apps.keys {
            guard let windows = try? ax.windows(app: appID) else { continue }
            for window in windows { windowsByID[window.id] = window }
        }
    }

    // MARK: - proctor_apps

    func listApps(includeWindowless: Bool) throws -> JSONValue {
        let running = try ax.listApps(includeWindowless: includeWindowless)
        refreshWindows()

        var entries: [JSONValue] = []
        for app in running {
            var obj: [String: JSONValue] = [
                "id": .string(app.id),
                "pid": .number(Double(app.pid)),
                "name": .string(app.name),
                "attached": .bool(apps[app.id] != nil)
            ]
            if let bundleId = app.bundleId { obj["bundleId"] = .string(bundleId) }
            if let handoff = browserHandoff(bundleId: app.bundleId, detail: .brief, tool: "proctor_apps") {
                obj["browser"] = try JSONValue.encode(handoff)
            }
            if apps[app.id] != nil {
                let windows = windowsByID.values.filter { $0.app == app.id }
                obj["windows"] = .array(try windows.sorted { $0.id < $1.id }
                                                   .map { try JSONValue.encode($0) })
                if let provenance = provenanceByApp[app.id] {
                    obj["provenance"] = try JSONValue.encode(provenance)
                }
            }
            entries.append(.object(obj))
        }

        return .object([
            "apps": .array(entries),
            "attached": .array(apps.keys.sorted().map { .string($0) }),
            // Enumerating the windows of every running application costs an AX
            // round trip per app and warms trees nobody asked about, so window
            // lists are only returned for what is attached.
            "note": .string("Window handles are listed for attached applications only. Attach an app to see its windows.")
        ])
    }

    func attach(bundleId: String?, pid: Int32?, name: String?) throws -> JSONValue {
        guard bundleId != nil || pid != nil || name != nil else {
            throw AgentError(code: .invalidArguments,
                             message: "attach needs one of bundleId, pid or name",
                             remedy: "Call proctor_apps with action \"list\" to find one.")
        }
        let (app, windows, provenance) = try attachResolved(bundleId: bundleId, pid: pid, name: name)

        var out: [String: JSONValue] = [
            "app": try JSONValue.encode(app),
            "windows": .array(try windows.map { try JSONValue.encode($0) }),
            "provenance": try JSONValue.encode(provenance)
        ]
        // Attaching is the moment the instrument is chosen, so this is the one
        // place the full advisory is emitted — the measured Obscura edges and the
        // command templates. Everywhere else carries the brief form, because
        // repeating seven caveats on every step of a batch is noise that is skimmed.
        if let handoff = browserHandoff(bundleId: app.bundleId, detail: .full, tool: "proctor_apps") {
            out["browser"] = try JSONValue.encode(handoff)
        }
        return .object(out)
    }

    /// Attach and record the bookkeeping, returning the handles rather than the
    /// wire shape. Shared with activate, which attaches repeatedly while it waits
    /// for a window to appear and needs the handles rather than encoded JSON.
    func attachResolved(bundleId: String?, pid: Int32?,
                        name: String?) throws -> (AppHandle, [WindowHandle], TreeProvenance) {
        let (app, provenance) = try ax.attach(bundleId: bundleId, pid: pid, name: name)
        apps[app.id] = app
        provenanceByApp[app.id] = provenance

        let windows = (try? ax.windows(app: app.id)) ?? []
        for window in windows { windowsByID[window.id] = window }
        return (app, windows, provenance)
    }

    /// The attached app whose process matches `pid`, if any. Activation needs it
    /// to name the target in an audit record before anything is brought forward.
    func attachedApp(pid: Int32) -> AppHandle? {
        apps.values.first { $0.pid == pid }
    }

    func detach(app id: String) throws -> JSONValue {
        guard apps[id] != nil else {
            throw AgentError(code: .appNotFound,
                             message: "\(id) is not attached",
                             remedy: "Call proctor_apps with action \"list\" to see what is attached.")
        }
        try ax.detach(app: id)
        apps.removeValue(forKey: id)
        provenanceByApp.removeValue(forKey: id)
        dictionaryCache.dropHandle(id)
        let dropped = windowsByID.filter { $0.value.app == id }.map(\.key)
        for window in dropped {
            windowsByID.removeValue(forKey: window)
            revisions.removeValue(forKey: window)
            history.removeValue(forKey: window)
        }
        return .object(["detached": .string(id), "windowsReleased": .number(Double(dropped.count))])
    }

    // MARK: - Trees

    /// Walk a window and fold the result into the revision history. The
    /// revision only advances when the tree actually differs, so a caller that
    /// polls does not see motion that did not happen.
    @discardableResult
    func walk(window id: String, options: SnapshotOptions = SnapshotOptions()) throws -> WalkOutcome {
        let (root, provenance) = try ax.snapshot(window: id,
                                                 root: options.root,
                                                 maxDepth: options.maxDepth,
                                                 maxNodes: options.maxNodes,
                                                 includeInvisible: options.includeInvisible)
        let hash = Canonical.hash(root)

        // A walk rooted at a subtree is not the window's state, so it is
        // reported without disturbing the window's revision line.
        guard options.root == nil else {
            return WalkOutcome(root: root, provenance: provenance,
                               revision: revisions[id] ?? 0, hash: hash,
                               previous: nil, history: history[id] ?? [])
        }

        var entries = history[id] ?? []
        let previous = entries.last
        var revision = revisions[id] ?? 0
        if previous?.hash != hash {
            revision += 1
            revisions[id] = revision
            entries.append(TreeRevision(revision: revision, node: root, hash: hash))
            if entries.count > Session.historyDepth {
                entries.removeFirst(entries.count - Session.historyDepth)
            }
            history[id] = entries
        }
        return WalkOutcome(root: root, provenance: provenance, revision: revision,
                           hash: hash, previous: previous, history: entries)
    }

    func snapshot(window id: String, options: SnapshotOptions, sinceRevision: Int?) throws -> Snapshot {
        let handle = try windowHandle(id)
        let outcome = try walk(window: id, options: options)
        let browser = browserHandoff(window: handle, tool: "proctor_snapshot")

        guard let since = sinceRevision else {
            return Snapshot(window: id, revision: outcome.revision, root: outcome.root,
                            diff: nil, provenance: outcome.provenance, stateHash: outcome.hash,
                            browser: browser)
        }

        // The diff is taken from the retained tree closest to what was asked
        // for, and fromRevision names the one actually used, because a diff
        // against a tree the caller did not ask for is only safe if it says so.
        let base = outcome.history.last { $0.revision <= since } ?? outcome.history.first
        let diff = SnapshotDiffer.diff(from: base?.node, to: outcome.root,
                                       fromRevision: base?.revision ?? 0)
        return Snapshot(window: id, revision: outcome.revision, root: nil, diff: diff,
                        provenance: outcome.provenance, stateHash: outcome.hash,
                        browser: browser)
    }

    func find(window id: String, predicate: FindPredicate, limit: Int) throws -> JSONValue {
        let handle = try windowHandle(id)
        let nodes = try ax.find(window: id, predicate: predicate, limit: limit)
        var out: [String: JSONValue] = [
            "window": .string(id),
            "predicate": predicate.described,
            "count": .number(Double(nodes.count)),
            "truncated": .bool(nodes.count >= limit),
            "nodes": .array(try nodes.map { try JSONValue.encode($0) })
        ]
        // The matched nodes already carry their frames, so deciding whether this
        // find reached page content costs no extra accessibility traffic — every
        // match is considered, not a prefix of them. A predicate that ranks the
        // toolbar first and the page fifth still reaches the page.
        let targets = nodes.compactMap(\.frame)
        if let handoff = browserHandoff(window: handle, targets: targets, tool: "proctor_find") {
            out["browser"] = try JSONValue.encode(handoff)
        }
        return .object(out)
    }

    // MARK: - proctor_capture

    struct AnnotateOptions: Sendable {
        var marks: Bool = false
        var all: Bool = false          // mark every framed node, not just actionable ones
        var grid: Bool = false
        var gridSpacing: Double = 100
        var maxMarks: Int = SetOfMarks.defaultMaxMarks
        var requested: Bool { marks || all || grid }
    }

    func captureWindow(_ id: String, path: String?, waitForComplete: Bool, timeoutMs: Int,
                       scale: Double?, tileHashes: Bool, includeCursor: Bool,
                       normalize: CaptureNormalizeOptions? = nil,
                       encoding: ImageEncodingOptions = .default,
                       annotate: AnnotateOptions = AnnotateOptions()) async throws -> JSONValue {
        let window = try windowHandle(id)
        // A caller redirecting the write outside the declared filesystem roots is
        // refused before the frame is taken. Enforced only on a supplied path; the
        // default session directory is the agent's own and trusted.
        try enforceFSJail(path: path)
        var result = try await capture.capture(window: window, to: path,
                                               waitForComplete: waitForComplete,
                                               timeoutMs: timeoutMs, scale: scale,
                                               tileHashes: tileHashes,
                                               includeCursor: includeCursor,
                                               normalize: normalize,
                                               encoding: encoding)
        // Freshness metadata passes through untouched. Rewriting or defaulting
        // any of it would erase the only thing separating a stale frame from a
        // correct one. Annotation is layered on top: it reads the geometry the
        // AX tree already reports and the PNG capture already wrote, and adds a
        // marked sibling image plus the mark→node map, leaving every field above
        // describing the original frame.
        if annotate.requested {
            result.annotation = try annotateCapture(window: window, result: result,
                                                     options: annotate)
        }
        let encoded = try JSONValue.encode(result)
        lastCapture = encoded
        return encoded
    }

    /// Walk the window for element geometry, place the marks, and composite them.
    /// The tree walk is allowed to throw — a caller who asked for marks and hit a
    /// missing Accessibility grant needs the error, not a quietly un-marked image.
    private func annotateCapture(window: WindowHandle, result: CaptureResult,
                                 options: AnnotateOptions) throws -> MarkAnnotation {
        let elements: [SetOfMarks.Element]
        if options.marks || options.all {
            let outcome = try walk(window: window.id)
            elements = Session.markableElements(from: outcome.root, all: options.all)
        } else {
            elements = []   // a grid was asked for on its own; no tree walk needed
        }

        let plan = SetOfMarks.plan(
            elements: elements,
            window: window.frame,
            imageWidth: result.width,
            imageHeight: result.height,
            scale: result.scale,
            grid: SetOfMarks.GridOptions(enabled: options.grid, spacingPoints: options.gridSpacing),
            maxMarks: options.maxMarks)

        let annotatedPath = try MarkRenderer.render(basePath: result.path,
                                                    width: result.width, height: result.height,
                                                    scale: result.scale, plan: plan)
        return MarkAnnotation(annotatedPath: annotatedPath,
                              marks: plan.marks,
                              grid: plan.grid,
                              elementsConsidered: plan.elementsConsidered,
                              markedCount: plan.markedCount,
                              truncated: plan.truncated)
    }

    /// Flatten a tree to the nodes worth marking. Nodes with no frame carry no
    /// place to draw a box, so they are dropped whichever mode is on; otherwise
    /// `all` keeps everything framed and the default keeps only the interactable
    /// elements a vision model actually actuates against.
    static func markableElements(from root: AXNode, all: Bool) -> [SetOfMarks.Element] {
        var out: [SetOfMarks.Element] = []
        TriObserver.walk(node: root, parent: nil) { node, _ in
            guard let frame = node.frame else { return }
            guard all || TriObserver.isActionable(node) else { return }
            let label = node.title ?? node.label ?? node.identifier
            out.append(SetOfMarks.Element(node: node.id, role: node.role,
                                          label: label, frame: frame))
        }
        return out
    }

    // MARK: - proctor_inspect

    func inspect(window id: String, node: String?, maxDepth: Int,
                 includeConstraints: Bool, presentation: Bool) throws -> JSONValue {
        let window = try windowHandle(id)
        guard let app = apps[window.app] else {
            throw AgentError(code: .appNotFound,
                             message: "the app owning \(id) is no longer attached",
                             remedy: "Re-attach with proctor_apps.")
        }
        guard reflector.isConnected(pid: app.pid) else {
            throw AgentError(
                code: .reflectorUnavailable,
                message: "\(app.name) does not have a ProctorReflector connection",
                remedy: "Embed the ProctorReflector package in the app under test behind #if DEBUG. "
                      + "There is no cross-process equivalent of computed styles on macOS, so for an app "
                      + "you do not own the ceiling is proctor_snapshot plus proctor_capture.")
        }
        let payload = try reflector.inspect(pid: app.pid, window: window, node: node,
                                            maxDepth: maxDepth,
                                            includeConstraints: includeConstraints,
                                            presentation: presentation)
        var out: [String: JSONValue] = ["window": .string(id), "hierarchy": payload]
        if let revision = reflector.renderRevision(pid: app.pid) {
            out["renderRevision"] = .number(Double(revision))
        }
        return .object(out)
    }

    // MARK: - Flow state

    func loadFlowsIfNeeded() {
        guard !flowsLoaded else { return }
        flows = FlowStore.loadAll()
        flowsLoaded = true
    }

    func setRecording(_ name: String?) { recording = name }
    func putFlow(_ flow: RecordedFlow) { flows[flow.name] = flow }
    func removeFlow(_ name: String) { flows.removeValue(forKey: name) }

    /// Install a recorded flow in memory without reading or writing the flow
    /// directory. Replay's gating is only checkable against a known flow, and a
    /// test must not leave one behind in the operator's own store to get it.
    func installFlow(_ flow: RecordedFlow) {
        flowsLoaded = true
        flows[flow.name] = flow
    }

    // MARK: - Health inputs

    func healthSnapshot() -> (apps: [DoctorReport.AttachedAppHealth], observers: Int) {
        (ax.health(), ax.observersLive)
    }

    // MARK: - MCP resources

    /// Read-only state re-projected as an MCP resource. Every branch reads state
    /// the agent already holds or that needs no TCC grant, so a resource is never
    /// a new capability — only a second door onto what a tool already exposes.
    func resource(key: String) throws -> JSONValue {
        switch key {
        case "windows":
            return try listApps(includeWindowless: false)
        case "frontmost":
            return frontmostResource()
        case "display":
            return displayResource()
        case "screenshot.latest":
            if let last = lastCapture {
                return .object(["cached": .bool(true), "capture": last])
            }
            return .object([
                "cached": .bool(false),
                "note": .string("No capture has been taken this session. Call proctor_capture; "
                              + "reading this resource never triggers one.")
            ])
        default:
            throw AgentError(code: .invalidArguments,
                             message: "unknown resource key \(key.debugDescription)")
        }
    }

    private func frontmostResource() -> JSONValue {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return .object(["frontmost": .null,
                            "note": .string("No application currently reports as frontmost.")])
        }
        var obj: [String: JSONValue] = [
            "pid": .number(Double(app.processIdentifier)),
            "name": .string(app.localizedName ?? "")
        ]
        if let bundleId = app.bundleIdentifier { obj["bundleId"] = .string(bundleId) }
        // If this app is attached, hand back its handle and main window so a caller
        // can act on it without re-listing.
        if let attached = apps.values.first(where: { $0.pid == app.processIdentifier }) {
            obj["attached"] = .bool(true)
            obj["app"] = .string(attached.id)
            let windows = windowsByID.values.filter { $0.app == attached.id }
            if let main = windows.first(where: { $0.isMain }) ?? windows.first,
               let encoded = try? JSONValue.encode(main) {
                obj["mainWindow"] = encoded
            }
        } else {
            obj["attached"] = .bool(false)
        }
        return .object(["frontmost": .object(obj)])
    }

    /// Displays via CoreGraphics rather than NSScreen, which is main-actor bound
    /// while this actor is not — the same reason StreamCapture reads scale from
    /// CGDisplayMode.
    private func displayResource() -> JSONValue {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        if count > 0 { CGGetActiveDisplayList(count, &ids, &count) }
        let main = CGMainDisplayID()
        let displays: [JSONValue] = ids.prefix(Int(count)).map { id in
            let bounds = CGDisplayBounds(id)
            var obj: [String: JSONValue] = [
                "displayID": .number(Double(id)),
                "frame": rectJSON(bounds),
                "isMain": .bool(id == main)
            ]
            if let mode = CGDisplayCopyDisplayMode(id), mode.width > 0 {
                let scale = Double(mode.pixelWidth) / Double(mode.width)
                obj["backingScaleFactor"] = .number(scale > 0 ? scale : 1)
                obj["pixelWidth"] = .number(Double(mode.pixelWidth))
                obj["pixelHeight"] = .number(Double(mode.pixelHeight))
            }
            return .object(obj)
        }
        return .object(["displays": .array(displays),
                        "count": .number(Double(displays.count))])
    }

    private func rectJSON(_ r: CGRect) -> JSONValue {
        .object(["x": .number(Double(r.origin.x)), "y": .number(Double(r.origin.y)),
                 "w": .number(Double(r.size.width)), "h": .number(Double(r.size.height))])
    }
}
