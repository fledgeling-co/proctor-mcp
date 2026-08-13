import Foundation
import CoreFoundation
import ProctorCore

// Entry point.
//
// AXObservers only deliver notifications to a live CFRunLoop, and only the main
// thread has one by default, so the run loop owns main and the socket accept
// loop runs on its own threads. Inverting that gives a server that answers
// every call and never sees an accessibility notification, which then presents
// as settling that always times out.

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

CFRunLoopRun()
