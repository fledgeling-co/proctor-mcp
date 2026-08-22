import Foundation
import CoreFoundation
import AppKit
import ProctorCore

// Entry point.
//
// AXObservers only deliver notifications to a live CFRunLoop, and only the main
// thread has one by default, so the run loop owns main and the socket accept
// loop runs on its own threads. Inverting that gives a server that answers
// every call and never sees an accessibility notification, which then presents
// as settling that always times out.

// The activation policy is claimed before anything else runs, and it has to be.
// This binary lives in Proctor.app/Contents/MacOS, so it inherits the bundle's
// Info.plist — where LSUIElement is false, because the UI app deliberately
// starts as a regular app so its first-run window can appear. The agent is not
// that app. The moment it touches the window server (NSWorkspace on activate,
// ScreenCaptureKit on capture) the Dock reads the enclosing bundle, gives this
// process a tile, and then waits for a launch that never completes, because
// nothing here ever runs an NSApplication event loop. The tile bounces forever.
//
// Accessory rather than prohibited: prohibited is documented as not permitting
// windows, and the cursor overlay is a window. Accessory keeps the process out
// of the Dock and out of the app switcher while still allowing a panel to be
// ordered in, which is exactly the shape of a background agent that draws.
NSApplication.shared.setActivationPolicy(.accessory)

// PRO-0029. Fold the saved switch preferences into the environment every switch
// is read from, BEFORE anything reads one.
//
// The ordering is the one real hazard in that feature. `CursorOverlay.isEnabled`,
// `InputBlocker.isEnabled` and `TakeoverOverlay.isEnabled` are `static let`s that
// resolve on first touch, so a read before this line would capture the raw process
// environment. That fails safely — preference-blind, never wrong — but it fails,
// so this sits at the top with nothing above it but the activation policy, which
// reads no environment at all.
//
// Precedence lives in `SwitchResolver` and is not one rule: the environment wins
// for the drawing switches and the two lanes, and OFF wins from either source for
// the two capability switches, so a person can always decline an event tap over
// their own keyboard. A corrupt or missing file resolves every switch to its
// built-in default, which reads OFF for both capabilities and both lanes.
ProctorEnvironment.install(saved: SwitchStore.load(from: SwitchStore.defaultURL))

/// The concrete engines are constructed here so the rest of the agent depends
/// only on the protocols in Contracts.swift.
func makeAXEngine() -> any AXEngine { AXEngineImpl() }

/// Which backend performs a step.
///
/// **Proctor's own planes are the default, and PRO-0051 settled that rather than
/// deferring it.** Three facts decided it, and each would have been enough on its
/// own: `appleScript` and `shortcut` have no Cua equivalent and are refused on the
/// delegated lane, so deleting the native planes would delete two published verbs;
/// Cua returns only a menu bar for a window on another Space, where a retained
/// `AXUIElement` keeps resolving, so the delegated lane cannot drive windows this
/// one can; and `cua-driver` has never executed on this machine, so delegation is
/// a path argued rather than exercised.
///
/// The delegated lane is chosen deliberately, by an operator, and is never entered
/// by falling into it — no failure here selects the other backend. The choice is
/// read once, here, and `Session.actuator` is immutable, so a lane is fixed for the
/// life of a session and every record it produces can name it honestly.
///
/// There is deliberately no condition that flips this default on its own. A default
/// that changes when some condition becomes true contaminates a determinism score
/// across runs exactly as a mid-flight fallback contaminates one within a run, and
/// worse, because nobody chose it. Moving the default is a release with notes
/// saying so.
///
/// Nothing here executes the driver. Locating it reads the filesystem, exactly as
/// it does for every other tool Proctor knows about; the version, signature,
/// vocabulary and grant checks all run in preflight, on the first delegated step.
func makeActuationBackend(ax: any AXEngine) -> any ActuationBackend {
    let environment = ProctorEnvironment.current
    guard CuaDriverTool.laneSelected(environment) else {
        return NativeActuationBackend(ax: ax)
    }
    let presence = ToolLocator.locate(binary: CuaDriverTool.binary,
                                      companions: [],
                                      pathEnvironment: environment["PATH"],
                                      home: NSHomeDirectory(),
                                      extraDirectories: CuaDriverTool.extraDirectories,
                                      isExecutable: ToolProbe.executableRegularFile)
    let path = presence.path ?? ""
    let transport: any CuaTransport =
        environment[CuaDriverTool.transportEnv]?.lowercased() == "oneshot"
            ? CuaOneShotTransport(path: path)
            : CuaEndpointTransport(path: path)
    return CuaActuationBackend(transport: transport, path: presence.path,
                               environment: environment)
}

func makeCaptureEngine() -> any CaptureEngine { CaptureEngineImpl() }

/// Assertions that need pixels or layer geometry go through the capture side's
/// tri-observer. It returns an optional because those assertions report
/// `skipped` when nothing is wired, which is the honest state and not something
/// a stand-in should paper over.
func makeTriObserver(capture: any CaptureEngine) -> (any TriObserving)? {
    TriObserverAdapter(capture: capture)
}

func installTerminationHandlers(_ server: Server) -> [DispatchSourceSignal] {
    [SIGTERM, SIGINT].map { number in
        // The default disposition has to go first, or the process dies before
        // the source ever runs and the socket is left behind for the next
        // start to trip over.
        signal(number, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
        source.setEventHandler {
            server.stop()
            Server.unlinkSocket(at: server.path)
            exit(0)
        }
        source.resume()
        return source
    }
}

let captureEngine = makeCaptureEngine()
let axEngine = makeAXEngine()

let session = Session(ax: axEngine,
                      capture: captureEngine,
                      reflector: NullReflectorBridge(),
                      tri: makeTriObserver(capture: captureEngine),
                      actuator: makeActuationBackend(ax: axEngine),
                      // The two process-wide seams, named here because this is
                      // the process that wants them. The panel's Pause and Stop
                      // write `RunControl.shared` directly, so the run has to be
                      // reading that same latch; and the yield watch is only
                      // worth anything against the actual machine. Every other
                      // construction of a `Session` gets a latch of its own and
                      // a quiet machine, which is what stopped a test process
                      // inheriting one run's park into every later run.
                      runControl: .shared,
                      contentionMonitor: ContentionMonitor.shared)

let server = Server(dispatcher: Dispatcher(session: session))

do {
    try server.start()
} catch let error as AgentError {
    FileHandle.standardError.write(Data("proctor-agent: \(error.message)\n".utf8))
    if let remedy = error.remedy {
        FileHandle.standardError.write(Data("proctor-agent: \(remedy)\n".utf8))
    }
    exit(1)
} catch {
    FileHandle.standardError.write(Data("proctor-agent: \(error)\n".utf8))
    exit(1)
}

let signalSources = installTerminationHandlers(server)
_ = signalSources

// The unlock broker answers the SecurityAgent authorization mechanism. It runs
// whether or not the login-path plugin is installed; with no plugin armed it
// simply never receives a connection, so starting it is free and keeps the
// answer ("is a turn authorized") in one place.
let unlockBroker = UnlockBroker()
unlockBroker.start()
_ = unlockBroker

// Touching the identity here is what captures it at startup: `builtAt` is a stored
// property of `BuildInfo.current`, so resolving it now describes the image that is
// running rather than whatever file is at this path by the time somebody asks.
let build = BuildInfo.captureAtLaunch()
FileHandle.standardError.write(Data("proctor-agent \(build.descriptor) listening on \(server.path)\n".utf8))

// The scheduler runs whether or not anything is drawn — taking turns is
// correctness, not decoration — so this only wires up who is *told* about it.
// The panel draws the bar; the session keeps the count so the menu bar can
// mirror it without the panel being on screen at all.
if Session.hudEnabledByDefault {
    Task { @MainActor in RunHUDPanel.shared.bind(scheduler: session.runScheduler) }
}
// A lane reclaimed from a dead peer takes that run's automatic hold with it.
// The scheduler owns the slot and `RunControl` owns the latch, and a hold left
// behind by a run that no longer exists would keep `heldBy` naming it and
// `pausedAt` running for the rest of the process's life.
Task {
    await session.runScheduler.setOnReclaim { ticket in
        RunControl.shared.release(run: ticket)
    }
}
Task {
    await session.runScheduler.observe { snapshot in
        Task { await session.setQueueWaiting(snapshot.waitingCount) }
        // PRO-0074. The one observer fans out here rather than being replaced,
        // so a supervision client attaching cannot stop the HUD drawing.
        SupervisionBroadcast.shared.publish(
            SupervisionBroadcast.frame(from: snapshot, now: Date().timeIntervalSince1970))
        guard Session.hudEnabledByDefault else { return }
        Task { @MainActor in
            RunHUDPanel.shared.queueChanged(snapshot)
        }
    }
}

// The event loop, and why it is AppKit's rather than a bare CFRunLoopRun().
//
// The run HUD carries Pause and Stop. A kill switch nobody can press is not a
// kill switch, and a click can only reach a button if something dequeues the
// NSEvent the window server delivered — which a bare `CFRunLoopRun()` never
// does. `NSApplication.run()` is the same main run loop, spun by AppKit, which
// additionally drains that queue.
//
// The regression to watch is settling, because the agent's whole notion of an
// application being done comes from AXObserver notifications delivered to this
// run loop. They are safe: `AXObservers` adds every source to
// `CFRunLoopMode.commonModes` (see Observers.swift), precisely so a modal or
// menu-tracking loop cannot starve them, and the default and tracking modes are
// both in that set. The panel's own drag is handled with mouseDragged and
// setFrameOrigin rather than performDrag, so this process never enters a nested
// tracking loop of its own making either.
//
// Everything else is unchanged: the socket accept loop runs on its own threads
// and was started above; the activation policy is still `.accessory`, so the
// agent stays out of the Dock and the app switcher; the HUD is a
// non-activating panel, so a click on it never activates this process and never
// takes focus from the application under test. Termination still goes through
// the signal sources, which call exit(0) directly rather than stopping a loop.
// And with the HUD switched off there are no buttons to receive a click, so the
// process keeps exactly the shape it shipped with. An unattended run that opted
// out of the drawing opts out of the event loop too.
// This process is the agent, so its surfaces may be drawn. Before the branch
// below rather than inside it: an agent that opted out of the run panel still
// tells somebody their Mac is being driven, and Esc still stops it.
AgentProcess.claimIsAgent()

if Session.hudEnabledByDefault {
    RunHUDPanel.markEventLoopRunning()
    NSApplication.shared.run()
} else {
    CFRunLoopRun()
}
