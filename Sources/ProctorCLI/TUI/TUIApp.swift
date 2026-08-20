import Foundation
import ProctorCore

// PRO-0074. The render loop.
//
// Two things happen: a frame arrives from the agent, or a key arrives from the
// operator. Neither polls the other — the watch pushes and the keyboard blocks
// with a bound, so a quiet machine costs nothing and a busy one redraws the
// moment the queue moves.

enum TUIApp {

    /// A run of the supervision surface. Returns the exit code.
    static func run(client: SocketClient = SocketClient()) -> CLISurface.Exit {
        guard Terminal.isInteractive else {
            FileHandle.standardError.write(Data(
                ("proctor tui needs a terminal. Redirected output has no size and no keys, "
                 + "so there would be nothing to supervise with.\n").utf8))
            return .usage
        }
        let state = TUIState()
        Terminal.enterRawMode()
        Terminal.enterAltScreen()
        defer { Terminal.restore() }

        // The watch runs on its own thread and hands frames to the state. The
        // main thread owns the keyboard and the paint, so a frame arriving mid
        // keystroke cannot interleave two writers onto the terminal.
        let watching = Thread {
            while !state.isFinished {
                do {
                    try client.watch { frame in
                        state.received(frame)
                        return state.isFinished
                    }
                } catch let error as AgentError {
                    // An agent that answers and does not know the request is a
                    // different situation from one that is not running, and the
                    // remedy a person acts on differs.
                    if error.code == .invalidArguments {
                        state.agentTooOld(error.message)
                    } else {
                        state.lostAgent(error.message)
                    }
                } catch {
                    state.lostAgent("\(error)")
                }
                // A dropped stream is retried rather than fatal: an agent that
                // restarts should not take the operator's window with it.
                if !state.isFinished { Thread.sleep(forTimeInterval: 1) }
            }
        }
        watching.stackSize = 512 * 1024
        watching.start()

        // Filled once at start-up so the panes that read a health report or the
        // history projection are not empty until somebody presses r.
        refreshReadiness(state: state, client: client)
        refreshHistory(state: state, client: client)

        let theme = TUITheme()
        while !state.isFinished {
            let size = Terminal.size()
            Terminal.paint(TUISurface.render(state.model(), cols: size.cols, rows: size.rows),
                           theme: theme)
            guard let key = Terminal.key(timeout: 0.25) else { continue }
            handle(key, state: state, client: client)
        }
        return .ok
    }

    static func handle(_ key: String, state: TUIState, client: SocketClient) {
        if let pane = TUISurface.Pane.allCases.first(where: { $0.key == key }) {
            state.show(pane)
            return
        }
        switch key {
        case "q", "esc": state.finish()
        case "tab": state.nextPane()
        // Pause, Resume and Stop reach the agent's own latch. The TUI holds no
        // run state of its own to stop, which is why it can be trusted from a
        // machine that is not the one being driven.
        case "p": control(state.isPaused ? "resume" : "pause", state: state, client: client)
        case "s": control("stop", state: state, client: client)
        case "r":
            state.requestRefresh()
            refreshReadiness(state: state, client: client)
            refreshHistory(state: state, client: client)
        default: break
        }
    }

    /// Ask the agent for a health report and fill the panes that read one.
    ///
    /// On its own connection, and on demand rather than on a timer: a person
    /// pressing `r` knows when they last had a real answer, and a pane that
    /// refreshed itself would leave them unable to say.
    static func refreshReadiness(state: TUIState, client: SocketClient) {
        let probe = SocketClient(path: client.path)
        defer { probe.disconnect() }
        guard let response = try? probe.send(AgentRequest(id: UUID().uuidString,
                                                          tool: "proctor_doctor",
                                                          arguments: .object([:]))),
              response.ok, let report = response.result else { return }
        state.received(report: report)
    }

    /// Ask the agent for the history projection and fill the pane that reads it.
    ///
    /// On demand and on its own connection, for the same two reasons the health
    /// read is: a person pressing `r` knows when they last had a real answer,
    /// and the watch connection is one-way once open.
    ///
    /// `proctor_history` is not in `ToolCatalogue`, so this is the same
    /// internal verb Proctor's own History window calls and no MCP host can
    /// route a `tools/call` to it. A trail this Mac cannot open answers with
    /// its entries counted as unreadable, which the pane says rather than
    /// drawing an empty history of a machine that was not quiet.
    static func refreshHistory(state: TUIState, client: SocketClient) {
        let probe = SocketClient(path: client.path)
        defer { probe.disconnect() }
        guard let response = try? probe.send(AgentRequest(id: UUID().uuidString,
                                                          tool: "proctor_history",
                                                          arguments: .object([:]))),
              response.ok, let history = response.result else { return }
        state.received(history: history)
    }

    static func control(_ action: String, state: TUIState, client: SocketClient) {
        // A separate connection, because the watch connection is one-way once
        // it is open. Reusing it would interleave a request into a stream of
        // pushed frames.
        let control = SocketClient(path: client.path)
        defer { control.disconnect() }
        do {
            _ = try control.send(AgentRequest(id: UUID().uuidString,
                                              tool: "proctor.control",
                                              arguments: .object(["action": .string(action)])))
        } catch let error as AgentError {
            state.lostAgent(error.message)
        } catch {
            state.lostAgent("\(error)")
        }
    }
}

/// What the surface is showing, shared between the watch thread and the render
/// loop.
///
/// Behind a lock rather than an actor: the render loop is a plain `while` on the
/// main thread, and a surface whose redraw has to await an actor is a surface
/// that redraws late — which is the whole failure this feature exists to
/// prevent.
final class TUIState: @unchecked Sendable {
    private let lock = NSLock()
    private var pane: TUISurface.Pane = .run
    private var frame: SupervisionFrame?
    private var lastFrameAt: Date?
    private var failure: String?
    private var outdated: String?
    private var report: JSONValue?
    private var history: JSONValue?
    private var finished = false

    var isFinished: Bool { lock.lock(); defer { lock.unlock() }; return finished }
    var isPaused: Bool {
        lock.lock(); defer { lock.unlock() }
        return frame?.run?.held ?? false
    }

    func finish() { lock.lock(); finished = true; lock.unlock() }

    func show(_ pane: TUISurface.Pane) { lock.lock(); self.pane = pane; lock.unlock() }

    func nextPane() {
        lock.lock()
        let all = TUISurface.Pane.allCases
        pane = all[(all.firstIndex(of: pane)! + 1) % all.count]
        lock.unlock()
    }

    func received(_ frame: SupervisionFrame) {
        lock.lock()
        self.frame = frame
        self.lastFrameAt = Date()
        self.failure = nil
        self.outdated = nil
        lock.unlock()
    }

    func lostAgent(_ reason: String) {
        lock.lock()
        failure = reason
        outdated = nil
        lock.unlock()
    }

    /// The last health report, for the panes that read one.
    func received(report: JSONValue) {
        lock.lock()
        self.report = report
        lock.unlock()
    }

    /// The last history reply.
    ///
    /// Held whole rather than pre-rendered, so the pane's rows and its
    /// could-not-be-opened count are read by the same pure function the tests
    /// drive, and this class keeps deciding nothing.
    func received(history: JSONValue) {
        lock.lock()
        self.history = history
        lock.unlock()
    }

    func agentTooOld(_ reason: String) {
        lock.lock()
        outdated = reason
        failure = nil
        lock.unlock()
    }

    /// Asking again is a key rather than a timer, because a re-check that
    /// happens on its own leaves the operator unable to say when they last had
    /// a real answer.
    func requestRefresh() {
        lock.lock()
        failure = nil
        outdated = nil
        lock.unlock()
    }

    /// Every rule about which absence is which lives in `TUISurface.model`, so
    /// this hands over facts rather than deciding anything.
    func model(now: Date = Date()) -> TUISurface.Model {
        lock.lock()
        defer { lock.unlock() }
        var model = TUISurface.model(pane: pane, frame: frame, receivedAt: lastFrameAt,
                                     now: now, failure: failure, outdated: outdated)
        if let report {
            let readiness = TUISurface.readiness(from: report)
            model.grants = readiness.grants
            model.readiness = readiness.lanes
            model.switches = TUISurface.switches(from: report)
        }
        if let history {
            let read = TUISurface.history(from: history)
            model.history = read.rows
            model.historyUnreadable = read.unreadable
        }
        return model
    }
}
