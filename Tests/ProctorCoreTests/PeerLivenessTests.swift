import Foundation
import Testing
@testable import ProctorCore

// PRO-0093 / DEF-026 — reclaim on death, never on silence.
//
// The whole risk of clearing a stranded lane is clearing a live one, so the
// mapping from a probe to a verdict is the part that has to be provable without
// a process. Every row below is a way the answer could be wrong, and two of them
// — a pid reused after its owner died, and a probe that could not describe the
// process — are the ways this would cut off a run that was doing something.

@Suite("Peer liveness")
struct PeerLivenessTests {

    private func key(_ pid: Int32, _ started: UInt64) -> String { "\(pid):\(started)" }

    // MARK: - Reading the key the identity already carries

    @Test("the identity key parses into the pid and the start time it was minted from")
    func theKeyParses() {
        let peer = PeerLiveness.peer(fromKey: "4821:1755000000")
        #expect(peer == PeerLiveness.Peer(pid: 4821, startedAt: 1_755_000_000))
    }

    @Test("a key that is not a peer parses to nothing, which is what never reclaims")
    func aKeyThatIsNotAPeerParsesToNothing() {
        // `unattributed` is the identity every caller whose process the kernel
        // would not describe lands on, and it is the identity every test in this
        // package acquires a lane under. If it parsed, the suite itself would be
        // the population this feature reclaims.
        #expect(PeerLiveness.peer(fromKey: "unattributed") == nil)
        #expect(PeerLiveness.peer(fromKey: "12") == nil)
        #expect(PeerLiveness.peer(fromKey: "a:b") == nil)
        #expect(PeerLiveness.peer(fromKey: "-1:0") == nil)
        #expect(PeerLiveness.peer(fromKey: "0:1755000000") == nil)
        #expect(PeerLiveness.peer(fromKey: "12:34:56") == nil)
        #expect(PeerLiveness.peer(fromKey: "") == nil)
    }

    // MARK: - The verdict, one row per way it could be wrong

    @Test("a pid the kernel no longer knows is gone")
    func aPidTheKernelDoesNotKnowIsGone() {
        let verdict = PeerLiveness.verdict(key: key(4821, 1_755_000_000)) { _ in .noSuchProcess }
        #expect(verdict == .gone)
    }

    @Test("the same process with the same start time is alive")
    func theSameProcessIsAlive() {
        let verdict = PeerLiveness.verdict(key: key(4821, 1_755_000_000)) { _ in
            .running(startedAt: 1_755_000_000)
        }
        #expect(verdict == .alive)
    }

    @Test("a pid reused by a later process is gone, not alive")
    func aReusedPidIsGone() {
        // Pids are reused, which is why the key carries a start time at all. A
        // new process wearing a dead peer's number would otherwise keep that
        // peer's lane held forever — the same wedge, reached from the far side.
        let verdict = PeerLiveness.verdict(key: key(4821, 1_755_000_000)) { _ in
            .running(startedAt: 1_755_009_999)
        }
        #expect(verdict == .gone)
    }

    @Test("a process that cannot be described is unknown, so its lane is left alone")
    func anUndescribableProcessIsUnknown() {
        let verdict = PeerLiveness.verdict(key: key(4821, 1_755_000_000)) { _ in .unreadable }
        #expect(verdict == .unknown)
    }

    @Test("a key that does not parse is unknown without the probe being asked")
    func anUnparseableKeyNeverReachesTheProbe() {
        let asked = Asked()
        let verdict = PeerLiveness.verdict(key: "unattributed") { _ in
            asked.record()
            return .noSuchProcess
        }
        #expect(verdict == .unknown)
        // The probe costs a syscall per active run on every acquire, and an
        // identity that cannot be judged should not pay it.
        #expect(asked.count == 0)
    }

    @Test("two start times of zero are two failures agreeing, not a match")
    func zeroStartTimesDecideNothing() {
        // `SessionIdentity.startTime` returns 0 when `proc_pidinfo` fails, so an
        // identity minted from that failure carries 0 and a probe of a process it
        // cannot read would return 0 as well. Comparing them equal would read
        // "alive" out of two unrelated failures.
        #expect(PeerLiveness.verdict(key: key(4821, 0)) { _ in .running(startedAt: 0) } == .unknown)
        #expect(PeerLiveness.verdict(key: key(4821, 0)) { _ in
            .running(startedAt: 1_755_000_000)
        } == .unknown)
        // And a probe reporting no such process still decides, because that
        // answer does not depend on either start time.
        #expect(PeerLiveness.verdict(key: key(4821, 0)) { _ in .noSuchProcess } == .gone)
    }

    @Test("the probe is asked about the pid the key names")
    func theProbeIsAskedAboutTheRightPid() {
        let seen = Seen()
        _ = PeerLiveness.verdict(key: key(4821, 1_755_000_000)) { pid in
            seen.record(pid)
            return .noSuchProcess
        }
        #expect(seen.value == 4821)
    }
}

/// Counts calls without a captured `var` crossing a Sendable boundary.
private final class Asked: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return stored }
    func record() { lock.lock(); stored += 1; lock.unlock() }
}

private final class Seen: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Int32 = 0
    var value: Int32 { lock.lock(); defer { lock.unlock() }; return stored }
    func record(_ pid: Int32) { lock.lock(); stored = pid; lock.unlock() }
}
