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

/// The concrete engines are constructed here so the rest of the agent depends
/// only on the protocols in Contracts.swift.
func makeAXEngine() -> any AXEngine { AXEngineImpl() }

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

let session = Session(ax: makeAXEngine(),
                      capture: captureEngine,
                      reflector: NullReflectorBridge(),
                      tri: makeTriObserver(capture: captureEngine))

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

FileHandle.standardError.write(Data("proctor-agent \(AgentBuild.version) listening on \(server.path)\n".utf8))

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
if Session.hudEnabledByDefault {
    RunHUDPanel.markEventLoopRunning()
    NSApplication.shared.run()
} else {
    CFRunLoopRun()
}
