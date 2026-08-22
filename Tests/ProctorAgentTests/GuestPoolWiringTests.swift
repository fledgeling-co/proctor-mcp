import Foundation
import Testing
import ProctorCore
@testable import ProctorAgent

// PRO-0076 — the pool, against the real scheduler.
//
// `GuestPoolLaneTests` proves the admission arithmetic; this proves the agent
// actually consults it, that slots come back on every path that can free one,
// and that nothing here can stop a guest to make room.

@Suite("PRO-0076 · the guest pool, wired")
struct GuestPoolWiringTests {

    private static func macRecord(_ name: String, running: Bool = true) -> GuestRecord {
        GuestRecord(name: name, provider: "tart", state: running ? "running" : "stopped",
                    running: running, platform: .macos, identifier: name)
    }

    /// Three macOS guests, so the third has somewhere to queue.
    private static let three = [macRecord("one"), macRecord("two"), macRecord("three")]

    private func session(records: [GuestRecord] = three, waitLimit: TimeInterval = 5)
        async -> (session: Session, provider: FakeGuestProvider, audit: AuditCollector) {
        let session = Session(ax: FakeAX(bundleId: "com.example.target"),
                              capture: FakeCapture(),
                              scheduler: RunScheduler.stoppedClock(waitLimit: waitLimit),
                              secureInputProbe: { false })
        let provider = FakeGuestProvider(id: "tart", records: records)
        let audit = AuditCollector()
        await session.setAuditSink(audit.sink)
        await session.setDrawsHUD(false)
        await session.setGuestProviders([provider])
        await session.setGuestLinkFactory { socket in FakeGuestLink(localSocket: socket) }
        return (session, provider, audit)
    }

    /// Attach as a named caller, so the per-identity keying is exercised rather
    /// than every attach sharing one identity.
    ///
    /// **The keys are deliberately not `pid:startTime` shaped.** A real identity
    /// key is parsed by `Session.peerIsAlive`, and a key like "sessA" names pid 1 —
    /// launchd, which exists, with a start time that does not match — so the
    /// reclaim would correctly judge every one of these attachments abandoned
    /// and free its slot before the next assertion ran. A key this build cannot
    /// parse reads as alive, which is the right default for a test's own name.
    private func attach(_ session: Session, _ guest: String, as key: String) async throws {
        let identity = RunSessionIdentity(project: "p", connection: String(key.prefix(4)), key: key)
        try await SessionIdentity.$current.withValue(identity) {
            _ = try await session.guest(action: "attach", guest: guest,
                                        provider: nil, newName: nil)
        }
    }

    // MARK: - A7

    @Test("two macOS guests attach; the third waits rather than being refused")
    func theThirdGuestWaits() async throws {
        let h = await session()
        try await attach(h.session, "one", as: "sessA")
        try await attach(h.session, "two", as: "sessB")

        let occupancy = RunQueuePlan.occupancy(of: await h.session.runScheduler.snapshot().active)
        #expect(occupancy["macos"] == 2, "both slots are held")

        // The third cannot start. With a stopped clock its wait never resolves,
        // so it is raced against a short deadline: the point is that it QUEUES
        // rather than coming back immediately with a refusal.
        let third = Task {
            try await self.attach(h.session, "three", as: "sessC")
        }
        var sawWaiting = false
        for _ in 0..<200 {
            if await h.session.runScheduler.snapshot().waiting.count > 0 { sawWaiting = true; break }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        #expect(sawWaiting, "a third macOS guest joins the queue instead of being refused")
        third.cancel()
    }

    @Test("a queued attach carries position and depth when it gives up")
    func theWaitSaysWhereItStood() async throws {
        // A7's second half, on a refusal a real queued attach produced.
        //
        // The earlier version of this test constructed the `RunQueueRefusal`
        // itself and asserted on its rendering, so it would have passed just as
        // happily if a queued attach never produced one — presence, not outcome.
        // What makes the real thing reachable is the sleeper: the give-up timer
        // waits on `RunScheduler.sleep`, which is injectable, so the ceiling is
        // opened on command rather than after forty-five seconds of wall clock.
        let gate = WaitGate()
        let scheduler = RunScheduler(waitLimit: 45, now: { 0 },
                                     sleep: { _ in await gate.wait() })
        let session = Session(ax: FakeAX(bundleId: "com.example.target"),
                              capture: FakeCapture(), scheduler: scheduler,
                              secureInputProbe: { false })
        let records = ["one", "two", "three", "four", "five"].map { Self.macRecord($0) }
        await session.setAuditSink(AuditCollector().sink)
        await session.setDrawsHUD(false)
        await session.setGuestProviders([FakeGuestProvider(id: "tart", records: records)])
        await session.setGuestLinkFactory { socket in FakeGuestLink(localSocket: socket) }

        // Apple's two, spoken for.
        try await attach(session, "one", as: "sessA")
        try await attach(session, "two", as: "sessB")

        // Three more, each a different caller so no per-session cap fires. They
        // queue rather than being refused — that is `theThirdGuestWaits` — and
        // this is what they are told when the ceiling runs out.
        let queued = ["three", "four", "five"].enumerated().map { index, name in
            Task { () -> Error? in
                do {
                    try await self.attach(session, name, as: "waiting\(index)")
                    return nil
                } catch {
                    return error
                }
            }
        }
        var joined = 0
        for _ in 0..<400 {
            joined = await scheduler.snapshot().waiting.count
            if joined == 3 { break }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        #expect(joined == 3, "all three are in the line before the ceiling is opened")

        gate.release()

        var messages: [String] = []
        for task in queued {
            let error = try #require(await task.value, "a queued attach must give up, not hang")
            let refusal = try #require(error as? AgentError)
            #expect(refusal.code == .queueBusy)
            messages.append(refusal.message)
        }
        #expect(messages.count == 3)
        #expect(messages.allSatisfy { $0.contains("without running any step") },
                "the caller is told nothing ran, so a retry is safe")
        // Depth, read back out of what the queue actually said. Three waiters
        // give up one after another, so the depths are 3, 2 and 1 whichever
        // order the give-up timers happen to fire in — a literal could not have
        // produced that, and a queue that never queued could not either.
        let depths = messages.compactMap { message -> Int? in
            guard let range = message.range(of: #"of (\d+) after"#, options: .regularExpression)
            else { return nil }
            return Int(message[range].dropFirst(3).dropLast(6))
        }
        #expect(depths.sorted() == [1, 2, 3], "the depth is the line as it stood, counted")
        #expect(messages.contains { $0.contains("first") },
                "the one at the head of the line is told it was first")
    }

    // MARK: - A8

    @Test("the pool honours the per-session waiting cap")
    func theCapBindsTheAttachPath() async throws {
        // The attach goes through the same `acquire` every other lane uses, so
        // the cap and the ceiling bind it with no new switch. Proved against the
        // scheduler directly, so it does not depend on three guests existing.
        let scheduler = RunScheduler.stoppedClock()
        await scheduler.setCapacities(["macos": 1])
        let holder = RunSessionIdentity(project: "p", connection: "h", key: "h:1")
        let demand = LaneDemand.forGuest(provider: "tart", name: "one", platform: .macos)
        // The ticket is BOUND, not discarded. `LaneTicket.deinit` releases as a
        // backstop for a holder that went away, so `_ = try await acquire(...)`
        // gives the slot straight back and the pool would look empty.
        let held = try await scheduler.acquire(lanes: demand, identity: holder, summary: "hold")

        let waiter = RunSessionIdentity(project: "p", connection: "w", key: "w:1")
        var queued: [Task<Void, Error>] = []
        for index in 0..<RunQueuePlan.perSessionWaitingCap {
            queued.append(Task {
                _ = try await scheduler.acquire(
                    lanes: LaneDemand.forGuest(provider: "tart", name: "g\(index)",
                                               platform: .macos),
                    identity: waiter, summary: "wait \(index)")
            })
        }
        // Let them all join the line.
        for _ in 0..<200 {
            if await scheduler.snapshot().waiting.count >= RunQueuePlan.perSessionWaitingCap { break }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        await #expect(throws: AgentError.self) {
            _ = try await scheduler.acquire(
                lanes: LaneDemand.forGuest(provider: "tart", name: "one-too-many",
                                           platform: .macos),
                identity: waiter, summary: "the fourth")
        }
        for task in queued { task.cancel() }
        withExtendedLifetime(held) {}
    }

    @Test("the holder's idle ceiling is its own, not the queue's wait limit")
    func theIdleCeilingIsSeparate() async throws {
        // A wait ceiling of 45s applied to a HOLDER would tear down a healthy
        // attachment in the middle of a campaign. These are different questions
        // with different right answers, and conflating them was the leak.
        let idle = Session.attachIdleLimit(from: [:])
        #expect(idle == Session.defaultAttachIdleLimit)
        #expect(idle > RunQueuePlan.defaultWaitLimit * 10,
                "a holder is bounded far more generously than a waiter")
        #expect(Session.attachIdleLimit(from: [Session.attachIdleLimitEnv: "120"]) == 120)
        #expect(Session.attachIdleLimit(from: [Session.attachIdleLimitEnv: "0"]) == idle,
                "a nonsense value falls back rather than disabling the ceiling")
    }

    @Test("a slot whose holder went away is reclaimed, and the guest it started is stopped")
    func aDeadPeerReleasesItsSlot() async throws {
        let h = await session()
        try await attach(h.session, "one", as: "sessA")
        #expect(await h.session.runScheduler.snapshot().active.count == 1)

        // The peer behind key "sessA" is not a live process, so the reclaim finds
        // it gone. There is no detach and no timer: this is the rule that stops
        // a dead attachment holding one of Apple's two forever.
        let reclaimed = await h.session.reclaimAbandonedAttachments(peerIsAlive: { _ in false })
        #expect(reclaimed == ["one"])
        #expect(await h.session.runScheduler.snapshot().active.isEmpty,
                "the slot must come back")
    }

    @Test("a live peer keeps its slot")
    func aLivePeerIsNotReclaimed() async throws {
        let h = await session()
        try await attach(h.session, "one", as: "sessA")
        let reclaimed = await h.session.reclaimAbandonedAttachments(peerIsAlive: { _ in true })
        #expect(reclaimed.isEmpty)
        #expect(await h.session.runScheduler.snapshot().active.count == 1)
    }

    // MARK: - A10

    @Test("a full pool queues rather than stopping anybody's guest")
    func theQueueNeverEvicts() async throws {
        let h = await session()
        // "one" was already running when the first session attached, so Proctor
        // did not start it -- a person did. "two" likewise.
        try await attach(h.session, "one", as: "sessA")
        try await attach(h.session, "two", as: "sessB")

        let third = Task { try await self.attach(h.session, "three", as: "sessC") }
        for _ in 0..<200 {
            if await h.session.runScheduler.snapshot().waiting.count > 0 { break }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        third.cancel()

        // The whole claim: nothing was stopped to make room.
        #expect(!h.provider.calls.contains { $0.0 == "stop" },
                "no guest may be stopped to free a slot: stopping a running VM discards its state")
    }

    @Test("a guest another session holds is waited for, never taken")
    func anotherSessionsGuestIsNotTaken() async throws {
        let h = await session()
        try await attach(h.session, "one", as: "sessA")
        // A second session naming the SAME guest: it waits on the guest lane
        // even though a pool slot is free.
        let second = Task { try await self.attach(h.session, "one", as: "sessB") }
        for _ in 0..<200 {
            if await h.session.runScheduler.snapshot().waiting.count > 0 { break }
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        #expect(await h.session.runScheduler.snapshot().waiting.count == 1)
        second.cancel()
        #expect(!h.provider.calls.contains { $0.0 == "stop" })
    }

    // MARK: - A11

    @Test("a guest that vanished releases the slot and names the disappearance")
    func aVanishedGuestReleasesItsSlot() async throws {
        let h = await session()
        try await attach(h.session, "one", as: "sessA")
        #expect(await h.session.runScheduler.snapshot().active.count == 1)

        // Stopped from outside Proctor: the provider now says it is not running.
        h.provider.records[0].running = false
        h.provider.records[0].state = "stopped"

        let identity = RunSessionIdentity(project: "p", connection: "A", key: "sessA")
        let error = await SessionIdentity.$current.withValue(identity) {
            await h.session.guestVanishedError()
        }
        let named = try #require(error)
        #expect(named.message.contains("one"), "the guest must be named")
        #expect(named.message.contains("no longer running"), "the disappearance must be named")
        #expect(named.message.contains("Nothing ran on this Mac"))
        #expect(await h.session.runScheduler.snapshot().active.isEmpty,
                "a slot held by nothing is what this closes")
    }

    @Test("a link failure over a guest that went away names the disappearance, not the tunnel")
    func aVanishDuringAForwardIsNamedAsSuch() async throws {
        // The two failures want different answers and a reader sent to check an
        // SSH forward that is fine has been sent to the wrong place. This is
        // also what gives `guestVanishedError` a production caller: without it
        // the vanish path is only ever reached by a test calling it directly.
        let h = await session()
        try await attach(h.session, "one", as: "sessA")

        // The guest is stopped from outside, so the next forward fails.
        h.provider.records[0].running = false
        h.provider.records[0].state = "stopped"

        let identity = RunSessionIdentity(project: "p", connection: "A", key: "sessA")
        await SessionIdentity.$current.withValue(identity) {
            let link = await h.session.guestLinks["sessA"] as? FakeGuestLink
            link?.sendError = AgentError(code: .agentUnavailable, message: "broken pipe")
            let request = AgentRequest(id: "1", tool: "proctor_act", arguments: .object([:]))
            do {
                _ = try await h.session.forwardToGuestIfAttached(request)
                Issue.record("a forward onto a vanished guest must refuse")
            } catch let error as AgentError {
                #expect(error.message.contains("no longer running"),
                        "the disappearance is what happened, not a dead tunnel")
                #expect(error.message.contains("one"))
            } catch {
                Issue.record("unexpected error: \(error)")
            }
        }
        #expect(await h.session.runScheduler.snapshot().active.isEmpty)
    }

    @Test("releasing twice decrements the pool once")
    func releaseIsIdempotent() async throws {
        // Detach, a failed link, a vanish, a dead peer and a start timeout can
        // all fire on one attachment. A second decrement would admit two waiters
        // where one slot freed, and would resume a continuation twice.
        let h = await session()
        try await attach(h.session, "one", as: "sessA")
        try await attach(h.session, "two", as: "sessB")
        #expect(await h.session.runScheduler.snapshot().active.count == 2)

        let identity = RunSessionIdentity(project: "p", connection: "A", key: "sessA")
        await SessionIdentity.$current.withValue(identity) {
            let first = await h.session.releaseGuestAttachment(reason: "first").released
            let second = await h.session.releaseGuestAttachment(reason: "second").released
            #expect(first, "the first release does the work")
            #expect(!second, "the second must be a no-op")
        }
        #expect(await h.session.runScheduler.snapshot().active.count == 1,
                "exactly one slot came back")
    }

    @Test("two releases racing across an await still decrement the pool once")
    func concurrentReleasesDecrementOnce() async throws {
        // THE CASE THE SEQUENTIAL TEST CANNOT SEE. `Session` is an actor and
        // `releaseGuestAttachment` awaits inside — stopping the guest, closing
        // the link, releasing the ticket — so isolation drops mid-release and a
        // second caller can enter before the first has removed the attachment.
        // Without a latch written BEFORE the first await, both would proceed:
        // the pool would decrement twice, admitting two waiters where one slot
        // freed, and the second continuation resume would trap the process.
        let h = await session()
        try await attach(h.session, "one", as: "sessA")
        try await attach(h.session, "two", as: "sessB")
        #expect(await h.session.runScheduler.snapshot().active.count == 2)

        let identity = RunSessionIdentity(project: "p", connection: "A", key: "sessA")
        async let first = SessionIdentity.$current.withValue(identity) {
            await h.session.releaseGuestAttachment(reason: "racer one").released
        }
        async let second = SessionIdentity.$current.withValue(identity) {
            await h.session.releaseGuestAttachment(reason: "racer two").released
        }
        let outcomes = await [first, second]
        #expect(outcomes.filter { $0 }.count == 1,
                "exactly one of two racing releases may claim the release")
        #expect(await h.session.runScheduler.snapshot().active.count == 1,
                "the other attachment's slot must be untouched")
    }

    @Test("detach reports whether the guest actually stopped, not what it intended")
    func detachReportsTheMeasuredOutcome() async throws {
        // `guestStopped` used to be computed from `startedByThisAgent` BEFORE
        // the stop ran, so a stop that failed still reported success while the
        // VM kept running and was no longer in anybody's count.
        let h = await session(records: [Self.macRecord("one", running: false)])
        try await attach(h.session, "one", as: "sessA")

        // The provider will refuse the stop.
        h.provider.failNext = GuestProviderError.commandFailed(
            tool: "tart", action: "stop", exit: 1, stderr: "busy")

        let identity = RunSessionIdentity(project: "p", connection: "A", key: "sessA")
        let out = try await SessionIdentity.$current.withValue(identity) {
            try await h.session.guest(action: "detach", guest: nil, provider: nil, newName: nil)
        }
        #expect(out["guestStopped"]?.boolValue == false,
                "a stop that failed must not be reported as a stop")
        // The slot still comes back: the attachment is over either way, and a
        // slot held by a guest nobody is driving helps nobody.
        #expect(await h.session.runScheduler.snapshot().active.isEmpty)
    }

    @Test("an attached session polling a host-only tool is not treated as idle")
    func hostOnlyCallsCountAsLife() async throws {
        // The idle ceiling reclaims a slot whose holder has stopped working. A
        // session driving the guest through `proctor_doctor` polls only host
        // tools, and touching the attachment solely on forwarded calls made it
        // look abandoned while it was plainly alive.
        let h = await session()
        try await attach(h.session, "one", as: "sessA")
        let identity = RunSessionIdentity(project: "p", connection: "A", key: "sessA")
        let before = await h.session.guestAttachments["sessA"]?.lastUsedAt

        await SessionIdentity.$current.withValue(identity) {
            let request = AgentRequest(id: "1", tool: "proctor_doctor", arguments: .object([:]))
            _ = try? await h.session.forwardToGuestIfAttached(request)
        }
        let after = await h.session.guestAttachments["sessA"]?.lastUsedAt
        // PRO-0100, DEF-140. `#expect` records and returns — it does not stop
        // the test — so a nil here used to reach the unwrap and abort the runner
        // with no verdict line, which is the failure this class is about.
        let first = try #require(before, "no lastUsedAt before the host-only call")
        let second = try #require(after, "no lastUsedAt after the host-only call")
        #expect(second >= first, "a host-only call from an attached session is a sign of life")
    }

    @Test("a provider that is gone is a vanish, not an all-clear")
    func aMissingProviderIsAVanish() async throws {
        // A11 names "the provider died" as a way a guest disappears. Returning
        // nil there reported everything fine and left the slot held by a machine
        // nothing could see any more.
        let h = await session()
        try await attach(h.session, "one", as: "sessA")
        // The provider is no longer resolvable at all.
        await h.session.setGuestProviders([])

        let identity = RunSessionIdentity(project: "p", connection: "A", key: "sessA")
        let error = await SessionIdentity.$current.withValue(identity) {
            await h.session.guestVanishedError()
        }
        let named = try #require(error, "a vanished provider must not read as all-well")
        #expect(named.message.contains("one"))
        #expect(await h.session.runScheduler.snapshot().active.isEmpty,
                "the slot must come back")
    }

    @Test("a release reports its own outcome, not the last release anywhere in the agent")
    func releaseOutcomeIsNotShared() async throws {
        // The outcome used to be stashed on one field of a Session shared by
        // every identity, so a concurrent release of another attachment could
        // overwrite it between this stop and the caller reading it -- reporting
        // a guest this call had just stopped as still running.
        let h = await session(records: [Self.macRecord("one", running: false),
                                        Self.macRecord("two", running: false)])
        try await attach(h.session, "one", as: "sessA")
        try await attach(h.session, "two", as: "sessB")

        let a = RunSessionIdentity(project: "p", connection: "A", key: "sessA")
        let b = RunSessionIdentity(project: "p", connection: "B", key: "sessB")
        async let first = SessionIdentity.$current.withValue(a) {
            await h.session.releaseGuestAttachment(reason: "a", stopGuest: true)
        }
        async let second = SessionIdentity.$current.withValue(b) {
            await h.session.releaseGuestAttachment(reason: "b", stopGuest: true)
        }
        let outcomes = await [first, second]
        // Both started their own guest, so both stopped it. The point is that
        // each answer is its own rather than whichever finished last.
        #expect(outcomes.allSatisfy { $0.released })
        #expect(outcomes.allSatisfy { $0.stoppedGuest })
    }

    @Test("an attach that starts a guest and then fails stops it again")
    func aFailedAttachDoesNotOrphanTheGuestItStarted() async throws {
        // The one path that has just consumed Apple's cap. A probe that fails
        // after a successful start used to swallow the stop and write an ok row,
        // leaving a macOS guest running, uncounted, with its slot given back.
        let h = await session(records: [Self.macRecord("one", running: false)])
        await h.session.setGuestLinkFactory { socket in
            let link = FakeGuestLink(localSocket: socket)
            link.probeError = AgentError(code: .agentUnavailable, message: "no tunnel")
            return link
        }
        await #expect(throws: AgentError.self) {
            try await self.attach(h.session, "one", as: "sessA")
        }
        #expect(h.provider.calls.contains { $0.0 == "start" }, "it started the guest")
        #expect(h.provider.calls.contains { $0.0 == "stop" },
                "and it must stop what it started when the attach fails")
        #expect(await h.session.runScheduler.snapshot().active.isEmpty)
    }

    // MARK: - A12

    @Test("the pool report says capacity, who holds what, and how many wait")
    func thePoolIsReportable() async throws {
        let h = await session()
        try await attach(h.session, "one", as: "sessA")

        let report = await h.session.poolStatus()
        let pools = try #require(report["pools"]?.arrayValue)
        let macos = try #require(pools.first { $0["platform"]?.stringValue == "macos" })
        #expect(macos["capacity"]?.intValue == 2, "capacity is stated")
        #expect(macos["held"]?.intValue == 1, "slots held is stated")
        #expect(macos["waiting"]?.intValue == 0, "waiting is stated")
        #expect(macos["reason"]?.stringValue?.contains("Apple's rule") == true)

        let held = try #require(report["held"]?.arrayValue)
        #expect(held.count == 1)
        #expect(held[0]["guest"]?.stringValue == "tart:one", "which guest")
        #expect(held[0]["session"]?.stringValue?.isEmpty == false, "which session")
    }

    @Test("reading the pool runs no provider, so a health check still costs no VM")
    func thePoolReportExecutesNothing() async throws {
        let h = await session()
        try await attach(h.session, "one", as: "sessA")
        let before = h.provider.calls.count
        _ = await h.session.poolStatus()
        _ = await h.session.poolStatus()
        #expect(h.provider.calls.count == before,
                "the report is counted from this agent's own scheduler, never by asking a provider")
    }

    // MARK: - The clone refusal

    @Test("cloning a guest that holds a slot is refused, with the reason")
    func cloneWhileHeldIsRefused() async throws {
        // The spec's third assumption: cloning a stopped guest touches no slot,
        // cloning a running one is not something the providers agree about, so
        // a guest holding a slot is refused rather than cloned.
        let h = await session()
        try await attach(h.session, "one", as: "sessA")
        do {
            _ = try await h.session.guest(action: "clone", guest: "one",
                                          provider: nil, newName: "copy")
            Issue.record("a guest holding a slot must not be cloned")
        } catch let error as AgentError {
            #expect(error.message.contains("one"))
            #expect(error.message.lowercased().contains("attach"))
        }
        #expect(!h.provider.calls.contains { $0.0 == "clone" })
    }

    @Test("cloning a guest nobody holds still works")
    func cloneOtherwiseUnchanged() async throws {
        let h = await session()
        _ = try await h.session.guest(action: "clone", guest: "one",
                                      provider: nil, newName: "copy")
        #expect(h.provider.calls.contains { $0.0 == "clone" })
    }
}

/// Holds the scheduler's give-up timer until a test lets it go.
///
/// The ceiling sleeps on `RunScheduler.sleep`, which exists so a wait limit is
/// provable in milliseconds rather than in forty-five seconds. A sleeper that
/// returned immediately would expire each waiter as it joined, and the depth
/// this test is about would always read one.
final class WaitGate: @unchecked Sendable {
    private let lock = NSLock()
    private var open = false

    func release() { lock.lock(); open = true; lock.unlock() }

    private var isOpen: Bool { lock.lock(); defer { lock.unlock() }; return open }

    func wait() async {
        while !isOpen { try? await Task.sleep(nanoseconds: 2_000_000) }
    }
}
