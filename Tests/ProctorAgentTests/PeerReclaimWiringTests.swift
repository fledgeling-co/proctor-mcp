import Foundation
import Testing
import ProctorCore
@testable import ProctorAgent

// PRO-0093 / DEF-026 — a lane whose holder has exited comes back.
//
// The pure mapping is proved in `PeerLivenessTests` without a process. What is
// proved here is the thing that mapping is for: a real child process takes a
// lane, dies, and the next call gets the lane rather than `queueBusy`. The
// recorder is the scheduler's own snapshot and the refusal the second caller
// actually receives — never a value this test wrote.
//
// The twin matters as much as the fix. A peer that is merely slow, stopped at a
// breakpoint or blocked leaves its process in the table, so reclaiming on
// silence would cut off a live run. The live child keeps its lane, and that is
// asserted rather than assumed.

@Suite("Peer reclaim", .serialized)
struct PeerReclaimWiringTests {

    /// A real process, and the identity Proctor would mint for it.
    ///
    /// The key is built exactly as `SessionIdentity.fromPeer` builds it — the
    /// pid and `proc_pidinfo`'s start time — so what the reclaim reads here is
    /// the same string a live shim would put in the queue.
    private final class Peer {
        let process = Process()
        let identity: RunSessionIdentity

        init(project: String) throws {
            process.executableURL = URL(fileURLWithPath: "/bin/sleep")
            process.arguments = ["120"]
            try process.run()
            let pid = process.processIdentifier
            let started = SessionIdentity.startTime(of: pid)
            identity = RunSessionIdentity(project: project, connection: "0000",
                                          key: "\(pid):\(UInt64(started))", frontEnd: "mcp")
        }

        var pid: pid_t { process.processIdentifier }

        /// Kill it and wait for the kernel to forget it. `waitUntilExit` reaps
        /// the child, which is what turns `kill(pid, 0)` into `ESRCH` — an
        /// unreaped zombie still answers, and this test would then be measuring
        /// the zombie rule rather than the death rule.
        func kill() {
            process.terminate()
            process.waitUntilExit()
        }
    }

    private static let deadLane = LaneDemand(lanes: [.app("app:reclaim:1")])

    // MARK: - A1: the dead peer's lane comes back

    @Test("the start time in the identity key is a real one, so the probe can disagree with it")
    func theKeyCarriesARealStartTime() throws {
        // Arming the instrument before believing anything it says. If
        // `startTime` returned 0 here, every key in this suite would carry 0 and
        // the zero rule — not the death rule — would decide every test below.
        let peer = try Peer(project: "proctor-mcp")
        defer { peer.kill() }
        let parsed = try #require(PeerLiveness.peer(fromKey: peer.identity.key))
        #expect(parsed.pid == peer.pid)
        #expect(parsed.startedAt > 0)
        #expect(SessionIdentity.liveness(ofKey: peer.identity.key) == .alive)
    }

    @Test("a live peer that says nothing keeps its lane, and the next caller waits")
    func aLivePeerKeepsItsLane() async throws {
        let peer = try Peer(project: "diolog-web")
        defer { peer.kill() }
        let scheduler = RunScheduler(waitLimit: 0.2)
        let held = try await scheduler.acquire(lanes: Self.deadLane, identity: peer.identity,
                                               summary: "Act ×4")

        // The child is doing nothing at all — it is asleep for two minutes — and
        // that is the whole point: silence is not death.
        let other = RunSessionIdentity(project: "armada", connection: "1111",
                                       key: "999999999:1", frontEnd: "mcp")
        await #expect(throws: AgentError.self) {
            _ = try await scheduler.acquire(lanes: Self.deadLane, identity: other,
                                            summary: "Act ×1")
        }

        let snapshot = await scheduler.snapshot()
        #expect(snapshot.active.count == 1)
        #expect(snapshot.active.first?.id == held.id)
        #expect(snapshot.active.first?.identity.key == peer.identity.key)
        await scheduler.release(held)
    }

    @Test("a peer that exits mid-run gives its lane back to the next caller")
    func aDeadPeerGivesItsLaneBack() async throws {
        let peer = try Peer(project: "diolog-web")
        let scheduler = RunScheduler(waitLimit: 0.2)
        let stranded = try await scheduler.acquire(lanes: Self.deadLane, identity: peer.identity,
                                                   summary: "Act ×4")
        #expect(await scheduler.snapshot().active.count == 1)

        // The shim exits while its run is in flight. Nothing tells the agent;
        // the task holding the ticket is still there, which is exactly why the
        // lane never came back on its own.
        peer.kill()
        #expect(SessionIdentity.liveness(ofKey: peer.identity.key) == .gone)

        let other = RunSessionIdentity(project: "armada", connection: "1111",
                                       key: "999999999:1", frontEnd: "mcp")
        let next = try await scheduler.acquire(lanes: Self.deadLane, identity: other,
                                               summary: "Act ×1")

        // The queue's own state is the recorder. The stranded run is gone from it
        // and the new one holds the lane it was refused before this existed.
        let snapshot = await scheduler.snapshot()
        #expect(snapshot.active.count == 1)
        #expect(snapshot.active.first?.id == next.id)
        #expect(snapshot.active.first?.identity.key == other.key)
        #expect(!snapshot.active.contains { $0.id == stranded.id })
        await scheduler.release(next)
    }

    @Test("the reclaimed run's hold leaves the latch with its slot")
    func theReclaimedRunsHoldGoesWithIt() async throws {
        // The scheduler owns the slot and `RunControl` owns the latch. A hold
        // left behind by a run that no longer exists keeps `heldBy` naming it and
        // `pausedAt` running for the life of the process, so the panel reports a
        // machine held by nobody.
        let peer = try Peer(project: "diolog-web")
        let scheduler = RunScheduler(waitLimit: 0.2)
        let control = RunControl(pauseLimit: 900)
        control.begin(run: 0)
        await scheduler.setOnReclaim { ticket in control.release(run: ticket) }

        let stranded = try await scheduler.acquire(lanes: Self.deadLane, identity: peer.identity,
                                                   summary: "Act ×4")
        control.yield(run: stranded.id,
                      hold: HoldAttribution(reason: .frontmostChanged, session: "diolog-web 0000",
                                            app: "TextEdit", display: nil))
        #expect(control.isYielded)

        peer.kill()
        let other = RunSessionIdentity(project: "armada", connection: "1111",
                                       key: "999999999:1", frontEnd: "mcp")
        let next = try await scheduler.acquire(lanes: Self.deadLane, identity: other,
                                               summary: "Act ×1")
        #expect(!control.isYielded)
        #expect(control.heldBy == nil)
        await scheduler.release(next)
    }

    // MARK: - A2: everything that is not proof of death is left alone

    @Test("a run whose identity cannot be judged keeps its lane")
    func anUnjudgeableIdentityKeepsItsLane() async throws {
        // `unattributed` is what a caller gets when the kernel will not describe
        // its process, and it is what every other test in this package acquires
        // a lane under. Reclaiming it would make this feature's population the
        // suite itself.
        let scheduler = RunScheduler(waitLimit: 0.2)
        let ticket = try await scheduler.acquire(lanes: Self.deadLane,
                                                 identity: .unattributed, summary: "Act ×1")
        #expect(await scheduler.reclaimDeadPeers().isEmpty)
        #expect(await scheduler.snapshot().active.count == 1)
        await scheduler.release(ticket)
    }

    @Test("a probe that cannot describe the process reclaims nothing")
    func anUnreadableProbeReclaimsNothing() async throws {
        let scheduler = RunScheduler(waitLimit: 0.2)
        await scheduler.setPeerProbe { _ in .unknown }
        let ticket = try await scheduler.acquire(lanes: Self.deadLane,
                                                 identity: Self.someone, summary: "Act ×1")
        #expect(await scheduler.reclaimDeadPeers().isEmpty)
        #expect(await scheduler.snapshot().active.count == 1)
        await scheduler.release(ticket)
    }

    @Test("the sweep reclaims only the dead run, leaving the live one holding its own lane")
    func onlyTheDeadRunIsSwept() async throws {
        // Both peers are alive when they take their lanes, and one of them dies
        // afterwards. Acquiring already sweeps, so a test that started one peer
        // dead would have it reclaimed by the second acquire and would never
        // reach the sweep it means to measure.
        let scheduler = RunScheduler(waitLimit: 0.2)
        let dead = RunSessionIdentity(project: "gone", connection: "0000", key: "1:1")
        let live = RunSessionIdentity(project: "here", connection: "1111", key: "2:2")
        let world = Liveness()
        await scheduler.setPeerProbe { key in world.verdict(for: key) }
        let one = try await scheduler.acquire(lanes: LaneDemand(lanes: [.app("a")]),
                                              identity: dead, summary: "Act ×1")
        let two = try await scheduler.acquire(lanes: LaneDemand(lanes: [.app("b")]),
                                              identity: live, summary: "Act ×1")
        #expect(await scheduler.snapshot().active.count == 2)

        world.kill(dead.key)
        #expect(await scheduler.reclaimDeadPeers() == [one.id])
        let snapshot = await scheduler.snapshot()
        #expect(snapshot.active.map(\.id) == [two.id])
        #expect(snapshot.active.first?.identity.key == live.key)
        await scheduler.release(two)
    }

    @Test("a run waiting behind a dead peer starts as soon as the lane is reclaimed")
    func aWaiterIsWokenByTheReclaim() async throws {
        // The reclaim goes through `forceRelease`, which publishes and promotes,
        // so a run already in the line is granted rather than left to time out.
        let scheduler = RunScheduler(waitLimit: 5)
        let dead = RunSessionIdentity(project: "gone", connection: "0000", key: "1:1")
        let live = RunSessionIdentity(project: "here", connection: "1111", key: "2:2")
        let world = Liveness()
        await scheduler.setPeerProbe { key in world.verdict(for: key) }
        let stranded = try await scheduler.acquire(lanes: Self.deadLane, identity: dead,
                                                   summary: "Act ×1")
        let waiting = Task {
            try await scheduler.acquire(lanes: Self.deadLane, identity: live, summary: "Act ×1")
        }
        try await Task.sleep(nanoseconds: 20_000_000)
        #expect(await scheduler.snapshot().waitingCount == 1)

        world.kill(dead.key)
        #expect(await scheduler.reclaimDeadPeers() == [stranded.id])
        let granted = try await waiting.value
        let snapshot = await scheduler.snapshot()
        #expect(snapshot.active.map(\.id) == [granted.id])
        #expect(snapshot.waitingCount == 0)
        await scheduler.release(granted)
    }

    private static let someone = RunSessionIdentity(project: "armada", connection: "0000",
                                                    key: "424242:1755000000")
}

/// A world whose processes can be killed between two reads, without a captured
/// `var` crossing a Sendable boundary.
private final class Liveness: @unchecked Sendable {
    private let lock = NSLock()
    private var dead: Set<String> = []
    func kill(_ key: String) { lock.lock(); dead.insert(key); lock.unlock() }
    func verdict(for key: String) -> PeerLiveness.Verdict {
        lock.lock(); defer { lock.unlock() }
        return dead.contains(key) ? .gone : .alive
    }
}
