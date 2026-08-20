import Foundation
import Testing
@testable import ProctorCore

// PRO-0076 — the counted lane, as arithmetic.
//
// The pool is the one lane that admits more than one holder, and there are two
// wrong ways to build it that both look right from the outside. Each has a test
// here that fails on that specific mistake:
//
//   putting `.pool` into the mutex `taken` set     -> capacity collapses to 1
//   counting only `active`, no in-scan increment   -> one scan admits three
//
// Everything is pure. No guest, no scheduler, no VM.

@Suite("PRO-0076 · the guest pool")
struct GuestPoolLaneTests {

    private func ticket(_ id: Int, _ lanes: Set<RunLane>,
                        session: String = "s\(UUID().uuidString.prefix(4))") -> RunTicketInfo {
        RunTicketInfo(id: id,
                      identity: RunSessionIdentity(project: "p", connection: session,
                                                   key: session),
                      summary: "attach", lanes: lanes, since: 0)
    }

    private func macGuest(_ id: Int, _ name: String, session: String) -> RunTicketInfo {
        ticket(id, LaneDemand.forGuest(provider: "tart", name: name, platform: .macos).lanes,
               session: session)
    }

    // MARK: - A5

    @Test("two is Apple's number, and it is a parameter rather than a property of the case")
    func capacityIsAParameter() {
        let waiting = [macGuest(1, "a", session: "s1"),
                       macGuest(2, "b", session: "s2"),
                       macGuest(3, "c", session: "s3")]
        let capacities = ["macos": 2]

        let granted = RunQueuePlan.grantable(waiting: waiting, busy: [], held: false,
                                             occupancy: [:], capacities: capacities)
        #expect(granted == [1, 2], "two macOS guests start; the third waits")

        // The same lanes at a different capacity admit a different number, which
        // is what "the capacity is a parameter" has to mean to be true. A pool
        // built as a mutex would return [1] here AND above.
        #expect(RunQueuePlan.grantable(waiting: waiting, busy: [], held: false,
                                       occupancy: [:], capacities: ["macos": 1]) == [1])
        #expect(RunQueuePlan.grantable(waiting: waiting, busy: [], held: false,
                                       occupancy: [:], capacities: ["macos": 3]) == [1, 2, 3])
    }

    @Test("one scan cannot admit three into two slots")
    func theScanIncrementsAsItGrants() {
        // The failure this pins: build occupancy from `active` alone and never
        // increment inside the loop, and every waiter reads the same "0 held"
        // and all three are granted at once. The cap would then be enforced
        // only between scans, which is to say not at all under load.
        let waiting = [macGuest(1, "a", session: "s1"),
                       macGuest(2, "b", session: "s2"),
                       macGuest(3, "c", session: "s3")]
        let granted = RunQueuePlan.grantable(waiting: waiting, busy: [], held: false,
                                             occupancy: [:], capacities: ["macos": 2])
        #expect(granted.count == 2, "granted \(granted.count) into a pool of 2")
    }

    @Test("a slot already held counts against the cap")
    func activeOccupancyCounts() {
        let active = [macGuest(9, "already", session: "s0")]
        let occupancy = RunQueuePlan.occupancy(of: active)
        #expect(occupancy == ["macos": 1])

        let waiting = [macGuest(1, "a", session: "s1"), macGuest(2, "b", session: "s2")]
        let granted = RunQueuePlan.grantable(waiting: waiting, busy: [], held: false,
                                             occupancy: occupancy, capacities: ["macos": 2])
        #expect(granted == [1], "one slot was free, so one starts")
    }

    @Test("a linux guest is not counted against the macOS cap")
    func poolsAreKeyedByPlatform() {
        // The cap being honoured is Apple's rule about macOS guests, not a
        // property of virtualisation, so a Linux guest must not consume one of
        // the two. A pool keyed by anything other than the platform — the
        // provider, say — would fail this.
        let active = [macGuest(9, "m1", session: "s0"), macGuest(8, "m2", session: "s9")]
        let linux = ticket(1, LaneDemand.forGuest(provider: "tart", name: "l1",
                                                  platform: .linux).lanes, session: "s1")
        let granted = RunQueuePlan.grantable(waiting: [linux], busy: [],
                                             held: false,
                                             occupancy: RunQueuePlan.occupancy(of: active),
                                             capacities: GuestPool.capacities)
        #expect(granted == [1], "the macOS pool being full says nothing about a linux guest")
    }

    @Test("the macOS capacity is 2 and other platforms are not capped by Proctor")
    func capacityTable() {
        #expect(GuestPool.capacity(for: .macos) == 2)
        #expect(GuestPool.capacity(for: .linux) == GuestPool.unbounded)
        #expect(GuestPool.capacity(for: .windows) == GuestPool.unbounded)
        #expect(GuestPool.key(for: .macos) == "macos")
    }

    // MARK: - A6

    @Test("two sessions naming the same guest serialise even with a slot free")
    func oneSessionPerNamedGuest() {
        // Capacity 2 with only one guest named: the pool has room, and the
        // guest lane is still a mutex. Two campaigns cannot drive one VM.
        let waiting = [macGuest(1, "anvil-mac-node", session: "s1"),
                       macGuest(2, "anvil-mac-node", session: "s2")]
        let granted = RunQueuePlan.grantable(waiting: waiting, busy: [], held: false,
                                             occupancy: [:], capacities: ["macos": 2])
        #expect(granted == [1], "the second waits on the guest, not on the pool")
    }

    @Test("a different guest starts while one is held")
    func differentGuestsDoNotContend() {
        let waiting = [macGuest(1, "one", session: "s1"), macGuest(2, "two", session: "s2")]
        let granted = RunQueuePlan.grantable(waiting: waiting, busy: [], held: false,
                                             occupancy: [:], capacities: ["macos": 2])
        #expect(granted == [1, 2])
    }

    // MARK: - A7 / D2

    @Test("a full pool marks rather than breaking the scan, so host runs behind it start")
    func fullPoolIsNotABarrier() {
        // `.global` is a barrier; a full pool is not. A pool that broke the scan
        // would let a busy guest lane starve every Mac run queued behind it.
        let occupancy = ["macos": 2]
        let waiting = [macGuest(1, "third", session: "s1"),
                       ticket(2, [.app("app:7")], session: "s2")]
        let granted = RunQueuePlan.grantable(waiting: waiting, busy: [], held: false,
                                             occupancy: occupancy, capacities: ["macos": 2])
        #expect(granted == [2], "the queued third guest waits; the unrelated app run starts")
    }

    @Test("FIFO holds within the pool: a later guest does not overtake an earlier one")
    func fifoWithinThePool() {
        let occupancy = ["macos": 2]
        let waiting = [macGuest(1, "third", session: "s1"),
                       macGuest(2, "fourth", session: "s2")]
        let granted = RunQueuePlan.grantable(waiting: waiting, busy: [], held: false,
                                             occupancy: occupancy, capacities: ["macos": 2])
        #expect(granted.isEmpty, "no slot is free, so neither starts")
    }

    // MARK: - A10

    @Test("the plan has no way to evict, so a full pool queues rather than freeing a slot")
    func neverEvicts() {
        // A10 is an absence, and this is what makes the absence checkable: the
        // only thing `grantable` returns is a list of waiters to START. There is
        // no channel through which it could ask for a holder to be stopped, so a
        // scheduler built on it cannot evict even by mistake.
        let active = [macGuest(9, "person-started", session: "s0"),
                      macGuest(8, "other-session", session: "s9")]
        let waiting = [macGuest(1, "third", session: "s1")]
        let granted = RunQueuePlan.grantable(waiting: waiting, busy: [],
                                             held: false,
                                             occupancy: RunQueuePlan.occupancy(of: active),
                                             capacities: ["macos": 2])
        #expect(granted.isEmpty)
        // And the returned ids are all drawn from the waiting list — never from
        // the active one, which is the only shape an eviction could take.
        let waitingIDs = Set(waiting.map(\.id))
        #expect(granted.allSatisfy { waitingIDs.contains($0) })
    }

    // MARK: - The lanes themselves

    @Test("an attachment takes its guest and its pool together, never one at a time")
    func demandIsTakenWhole() {
        // Holding a slot while waiting for the guest, or the guest while waiting
        // for a slot, is the deadlock this shape makes unrepresentable.
        let demand = LaneDemand.forGuest(provider: "tart", name: "anvil-mac-node",
                                         platform: .macos)
        #expect(demand.lanes == [.guest("tart:anvil-mac-node"), .pool("macos")])
        #expect(!demand.needsGlobal, "a guest attachment does not take this Mac's event stream")
    }

    @Test("the lanes print themselves for the panel and the health report")
    func descriptions() {
        #expect(RunLane.guest("tart:anvil-mac-node").description == "guest:tart:anvil-mac-node")
        #expect(RunLane.pool("macos").description == "pool:macos")
        #expect(RunLane.pool("macos").isCounted)
        #expect(!RunLane.guest("tart:x").isCounted)
        #expect(!RunLane.app("a").isCounted)
        #expect(!RunLane.global.isCounted)
        #expect(RunLane.pool("macos").poolKey == "macos")
        #expect(RunLane.guest("tart:x").poolKey == nil)
    }

    // MARK: - Nothing about the existing two lanes moved

    @Test("the mutex lanes behave exactly as they did, with the pool parameters absent")
    func mutexLanesUnchanged() {
        // The regression guard for widening a load-bearing function: every
        // existing caller passes no occupancy and no capacities.
        let a = ticket(1, [.app("app:1")], session: "s1")
        let b = ticket(2, [.app("app:1")], session: "s2")
        let c = ticket(3, [.app("app:2")], session: "s3")
        #expect(RunQueuePlan.grantable(waiting: [a, b, c], busy: [], held: false) == [1, 3])

        let whole = ticket(4, [.app("app:1"), .global], session: "s4")
        let behind = ticket(5, [.app("app:9")], session: "s5")
        #expect(RunQueuePlan.grantable(waiting: [whole, behind], busy: [.global], held: false)
                    == [], "a run needing the whole machine is still a barrier")
        #expect(RunQueuePlan.grantable(waiting: [a], busy: [], held: true) == [],
                "a held queue still starts nothing")
    }
}
