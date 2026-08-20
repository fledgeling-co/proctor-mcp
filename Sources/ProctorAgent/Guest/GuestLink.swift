import Foundation
import ProctorCore

// PRO-0076. How a host-side session talks to the Proctor running inside a guest.
//
// **Proctor does not open the tunnel.** `proctor_guest reach` returns a recipe —
// localSocket, remoteSocket, host — and a person opens the SSH StreamLocal
// forward, for the reason PRO-0060 records: a tool result carrying `ssh -L` is an
// instruction a model with a shell would run. So this connects to the end of a
// forward that already exists, and a socket nothing is listening on is a refusal
// rather than an attempt to create one.
//
// THE HOST AGENT ACTUATES NOTHING FOR A GUEST SESSION. The whole point of the
// forward is that the guest's own Proctor holds the guest's TCC grants and talks
// to the guest's window server. This side does not translate steps, does not
// re-implement the tool surface, and does not inspect the payload: the request
// goes over verbatim and the guest's answer comes back verbatim. There is
// nothing here that could accidentally strike this Mac.

/// One session's channel to a guest's agent. A protocol for the same reason
/// `GuestProvider` and `ActuationBackend` are: the production type is the only
/// one that opens a socket.
protocol GuestLink: AnyObject, Sendable {
    /// The socket this link talks through, for the refusal to name.
    var localSocket: String { get }
    /// Establish and confirm the guest's agent is answering. Called once at
    /// attach, so a dead tunnel is found before a batch is sent into it.
    func probe() async throws
    /// Forward one request and return what the guest said.
    func send(_ request: AgentRequest) async throws -> AgentResponse
    func close() async
}

/// Which tools stay on this Mac when a session is attached to a guest.
///
/// **A DENYLIST, AND THAT IS THE LOAD-BEARING CHOICE.** An allowlist of
/// "machine-facing" tools fails OPEN: add a new actuation tool later, forget to
/// list it, and it runs on the host under a guest session — which is exactly the
/// verdict-about-the-wrong-machine this feature exists to prevent. A denylist
/// fails closed. A new tool forwards by default, and the mistake is a guest
/// refusing something it cannot do rather than this Mac quietly doing it.
enum GuestForwarding {

    /// The tools that answer about THIS Mac and are therefore never forwarded.
    ///
    /// Each is here because the question it answers is a fact about the host:
    /// the pool and its slots, the audit trail this agent seals, the health of
    /// this machine's own toolchain, and the surfaces a person is looking at.
    static let hostOnly: Set<String> = [
        "proctor_guest",            // the pool lives here; attaching from inside is nonsense
        "proctor_doctor",           // A12: the pool report is host state
        "proctor_policy",           // this agent's gate and its trail
        "proctor_history",
        "proctor_history_clear",
        "proctor_recent_activity",
        "proctor_queue",            // the queue being reported IS this scheduler
        "proctor_hud",              // the panel a person is looking at is on this Mac
        SupervisionFrame.watchTool
    ]

    static func isHostOnly(_ tool: String) -> Bool { hostOnly.contains(tool) }

    /// Everything else goes to the guest. Stated as its own function so the
    /// default direction is written down rather than implied by a negation at
    /// the call site.
    static func shouldForward(_ tool: String) -> Bool { !isHostOnly(tool) }
}

// MARK: - The live link

/// A link over the unix socket a person forwarded.
///
/// `SocketClient` is the same client the shim uses, pointed at the local end of
/// the tunnel instead of at this agent's own socket. No new transport: that was
/// PRO-0060's decision and nothing here revisits it.
final class SocketGuestLink: GuestLink, @unchecked Sendable {

    let localSocket: String
    private let lock = NSLock()
    private var client: SocketClient?
    private let makeClient: @Sendable (String) -> SocketClient

    init(localSocket: String,
         makeClient: @escaping @Sendable (String) -> SocketClient = { SocketClient(path: $0) }) {
        self.localSocket = localSocket
        self.makeClient = makeClient
    }

    func probe() async throws {
        // A doctor call is the cheapest question that proves an agent is alive
        // and answering, and it actuates nothing inside the guest.
        let request = AgentRequest(id: UUID().uuidString, tool: "proctor_doctor",
                                   arguments: .object([:]))
        _ = try await send(request)
    }

    func send(_ request: AgentRequest) async throws -> AgentResponse {
        let client = try connected()
        return try client.send(request)
    }

    private func connected() throws -> SocketClient {
        lock.lock(); defer { lock.unlock() }
        if let client, client.isConnected { return client }
        let fresh = makeClient(localSocket)
        try fresh.connect()
        client = fresh
        return fresh
    }

    func close() async { closeNow() }

    /// Synchronous, because `NSLock` is unavailable from an async context and
    /// the close itself does not suspend.
    private func closeNow() {
        lock.lock(); defer { lock.unlock() }
        client?.disconnect()
        client = nil
    }
}

// MARK: - What a caller is told when the guest cannot be reached

/// A2. A run whose machine is a guest never executes a step on this Mac.
///
/// This is PRO-0051's rejected fallback and it fails closed, exactly as
/// `GuestRoute.refuseHost` already reads. There is no branch anywhere that runs
/// the batch here instead — the absence is the guarantee, and the refusal is what
/// makes the absence legible to whoever receives it.
enum GuestLinkRefusal {

    static func unreachable(machine: Machine, socket: String,
                            underlying: String?) -> AgentError {
        var message = "this session is attached to \(machine.line) and the link to the Proctor "
                    + "inside it is not answering at \(socket), so the batch was refused. Nothing "
                    + "ran on this Mac."
        if let underlying, !underlying.isEmpty {
            message += " The link said: \(underlying)"
        }
        return AgentError(
            code: .agentUnavailable,
            message: message,
            remedy: "Running these steps here while naming that guest would hand back a verdict "
                  + "about the wrong machine, so it is refused rather than taken. Check the SSH "
                  + "StreamLocal tunnel onto \(socket) is still up and that Proctor is running "
                  + "inside the guest, then attach again. Detach with proctor_guest action "
                  + "\"detach\" to drive this Mac instead.")
    }

    /// A11. The guest went away under its holder.
    static func vanished(machine: Machine, reason: String) -> AgentError {
        AgentError(
            code: .agentUnavailable,
            message: "\(machine.line) is no longer running, so this session's attachment to it "
                   + "ended and its slot was released. \(reason) Nothing ran on this Mac.",
            remedy: "The guest was stopped from outside Proctor, the host slept, or the provider "
                  + "went away. Start it again with proctor_guest action \"start\" and attach "
                  + "again; the slot it held is free for another session in the meantime.")
    }
}
