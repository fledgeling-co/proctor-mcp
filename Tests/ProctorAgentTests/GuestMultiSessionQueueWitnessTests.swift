import Foundation
import Testing
import ProctorCore
@testable import ProctorAgent

// PRO-0117 · Guest VM Lifecycle and Multi-Session Attachment Oracle (REQ-037..REQ-040, REQ-195)
//
// Multi-session queue testing harness simulating concurrent session requests,
// non-evicting queue policies, fair slot release, and native witness tier derivation
// without requiring physical secondary VM boots.

@Suite("PRO-0117 · Guest VM Lifecycle & Multi-Session Queue Witness")
struct GuestMultiSessionQueueWitnessTests {

    private static func macRecord(_ name: String, running: Bool = true,
                                  provider: String = "tart",
                                  platform: MachinePlatform? = .macos) -> GuestRecord {
        GuestRecord(name: name, provider: provider, state: running ? "running" : "stopped",
                    running: running, platform: platform, identifier: name)
    }

    private func harness(records: [GuestRecord], waitLimit: TimeInterval = 10)
        async throws -> (session: Session, provider: FakeGuestProvider,
                         audit: AuditCollector, hostAX: FakeAX) {
        let ax = FakeAX(bundleId: "com.fledgeling.host-app")
        let session = Session(ax: ax,
                              capture: FakeCapture(),
                              scheduler: RunScheduler(waitLimit: waitLimit),
                              secureInputProbe: { false })
        let provider = FakeGuestProvider(id: "tart", records: records)
        let audit = AuditCollector()
        await session.setAuditSink(audit.sink)
        await session.setDrawsHUD(false)
        await session.setGuestProviders([provider])
        await session.setGuestLinkFactory { socket in FakeGuestLink(localSocket: socket) }
        return (session, provider, audit, ax)
    }

    private func attach(_ session: Session, _ guest: String, as key: String) async throws -> JSONValue {
        let identity = RunSessionIdentity(project: "pro-0117", connection: String(key.prefix(4)), key: key)
        return try await SessionIdentity.$current.withValue(identity) {
            try await session.guest(action: "attach", guest: guest,
                                    provider: nil, newName: nil)
        }
    }

    private func detach(_ session: Session, as key: String) async throws -> JSONValue {
        let identity = RunSessionIdentity(project: "pro-0117", connection: String(key.prefix(4)), key: key)
        return try await SessionIdentity.$current.withValue(identity) {
            try await session.guest(action: "detach", guest: nil,
                                    provider: nil, newName: nil)
        }
    }

    // MARK: - REQ-038 & REQ-039: 3 concurrent requests against 2-slot lane, fair acquire without eviction

    @Test("3 concurrent requests against 2-slot lane: first 2 acquire, 3rd waits cleanly and acquires upon release without eviction")
    func threeConcurrentRequestsAgainstTwoSlotLane() async throws {
        let records = [
            Self.macRecord("guest-alpha", running: true),
            Self.macRecord("guest-beta", running: true),
            Self.macRecord("guest-gamma", running: true)
        ]
        let h = try await harness(records: records, waitLimit: 15)

        // 1. First two sessions attach and acquire the 2 macOS slots.
        let attachA = try await attach(h.session, "guest-alpha", as: "session-A")
        let attachB = try await attach(h.session, "guest-beta", as: "session-B")

        #expect(attachA["attached"]?.boolValue == true)
        #expect(attachB["attached"]?.boolValue == true)

        let snapshotBefore = await h.session.runScheduler.snapshot()
        let occupancyBefore = RunQueuePlan.occupancy(of: snapshotBefore.active)
        #expect(occupancyBefore["macos"] == 2, "both slots are held by session-A and session-B")
        #expect(snapshotBefore.waiting.isEmpty, "no waiters initially")

        // 2. Third session requests attachment to guest-gamma against the full 2-slot lane.
        // It must cleanly enter the queue rather than being refused or causing eviction.
        let taskC = Task<JSONValue, Error> {
            try await self.attach(h.session, "guest-gamma", as: "session-C")
        }

        // Wait for session-C to join the waiting queue.
        var sawWaiting = false
        for _ in 0..<300 {
            if await h.session.runScheduler.snapshot().waiting.count == 1 {
                sawWaiting = true
                break
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        #expect(sawWaiting, "session-C joined the queue as waiting")

        // 3. Verify never-evicting queue policy: no guest was stopped to make room.
        let stopCallsBeforeRelease = h.provider.calls.filter { $0.0 == "stop" }
        #expect(stopCallsBeforeRelease.isEmpty, "no running guest may be stopped or evicted to free a slot")

        // 4. Session A releases its attachment (detaches).
        let detachA = try await detach(h.session, as: "session-A")
        #expect(detachA["attached"]?.boolValue == false)

        // 5. Session C acquires the released slot cleanly and finishes attachment.
        let attachC = try await taskC.value
        #expect(attachC["attached"]?.boolValue == true)
        #expect(attachC["guest"]?["name"]?.stringValue == "guest-gamma")

        let snapshotAfter = await h.session.runScheduler.snapshot()
        let occupancyAfter = RunQueuePlan.occupancy(of: snapshotAfter.active)
        #expect(occupancyAfter["macos"] == 2, "session-B and session-C now hold both slots")
        #expect(snapshotAfter.waiting.isEmpty, "waiting queue is now clear")

        // 6. Forward a step through session-C and verify host actuates nothing.
        let identityC = RunSessionIdentity(project: "pro-0117", connection: "sess", key: "session-C")
        let forwardResult = try await SessionIdentity.$current.withValue(identityC) {
            let request = AgentRequest(id: "c-act-1", tool: "proctor_act",
                                       arguments: .object(["window": .string("win-gamma-1"),
                                                           "steps": .array([])]))
            return try await h.session.forwardToGuestIfAttached(request)
        }
        #expect(forwardResult != nil, "call forwarded through session-C's attached guest link")
        #expect(h.hostAX.performed.isEmpty, "host AX performed 0 steps for forwarded guest action")

        // Clean up remaining attachments
        _ = try await detach(h.session, as: "session-B")
        _ = try await detach(h.session, as: "session-C")
    }

    // MARK: - REQ-039: Never-evicting policy under slot exhaustion & audit trail integrity

    @Test("never-evicting policy guarantees running VMs are never stopped to satisfy contention")
    func neverEvictingPolicyGuaranteesIntegrity() async throws {
        let records = [
            Self.macRecord("person-vm-1", running: true),
            Self.macRecord("person-vm-2", running: true),
            Self.macRecord("agent-vm-3", running: false)
        ]
        let h = try await harness(records: records, waitLimit: 5)

        // Attach two person-started running VMs
        _ = try await attach(h.session, "person-vm-1", as: "sess-1")
        _ = try await attach(h.session, "person-vm-2", as: "sess-2")

        // Third session attempts attach
        let task3 = Task<JSONValue, Error> {
            try await self.attach(h.session, "agent-vm-3", as: "sess-3")
        }

        var queued = false
        for _ in 0..<200 {
            if await h.session.runScheduler.snapshot().waiting.count > 0 {
                queued = true
                break
            }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        #expect(queued, "third attach queued cleanly")

        // Provider must have recorded zero stop invocations
        #expect(h.provider.calls.filter { $0.0 == "stop" }.isEmpty,
                "the scheduler never evicts running guests to service queued requests")

        task3.cancel()
        _ = try await detach(h.session, as: "sess-1")
        _ = try await detach(h.session, as: "sess-2")
    }

    // MARK: - REQ-040: Darwin platform provider reports native witness tier

    @Test("provider reporting darwin yields macOS platform and assigns native witness tier")
    func darwinProviderAssignsNativeWitnessTier() async throws {
        // 1. Pure platform inference
        let inferredPlatform = GuestPlatform.infer(os: "darwin", name: nil)
        #expect(inferredPlatform == .macos, "darwin os maps to macos platform")

        let darwinRecord = GuestRecord(name: "tahoe-guest", provider: "tart",
                                       state: "running", running: true,
                                       platform: inferredPlatform, identifier: "tahoe-guest")
        let macMachine = GuestAttachment.machine(for: darwinRecord)
        #expect(macMachine.platform == .macos)
        #expect(macMachine.tier == .native, "darwin platform must assign native witness tier")

        // 2. Native tier evaluates AX tree assertions without skipping
        for treeKind in ["exists", "absent", "valueEquals", "enabled", "focused", "hasLabel",
                         "frameEquals", "containedIn", "alignedWith", "horizontalAlignment",
                         "minHitSize", "contrast", "focusOrder", "agree"] {
            #expect(macMachine.tier.cannotEvaluate(treeKind) == nil,
                    "native tier evaluates \(treeKind)")
        }

        // 3. Contrast with delegated Linux guest
        let linuxRecord = GuestRecord(name: "ubuntu-guest", provider: "tart",
                                      state: "running", running: true,
                                      platform: .linux, identifier: "ubuntu-guest")
        let linuxMachine = GuestAttachment.machine(for: linuxRecord)
        #expect(linuxMachine.tier == .delegated, "linux guest yields delegated tier")
        #expect(linuxMachine.tier.cannotEvaluate("agree") != nil, "delegated tier skips agree")
        #expect(linuxMachine.tier.cannotEvaluate("regionMatches") == nil, "delegated tier permits pixel comparisons")
    }

    // MARK: - REQ-037: Multi-session socket forwarding isolation

    @Test("multi-session socket forwarding executes steps inside guest without host interference")
    func multiSessionSocketForwardingIsolation() async throws {
        let records = [
            Self.macRecord("guest-one", running: true),
            Self.macRecord("guest-two", running: true)
        ]
        let h = try await harness(records: records)

        _ = try await attach(h.session, "guest-one", as: "client-1")
        _ = try await attach(h.session, "guest-two", as: "client-2")

        let id1 = RunSessionIdentity(project: "pro-0117", connection: "cl1", key: "client-1")
        let id2 = RunSessionIdentity(project: "pro-0117", connection: "cl2", key: "client-2")

        // Send forwarded actions on both sessions
        let res1 = try await SessionIdentity.$current.withValue(id1) {
            try await h.session.forwardToGuestIfAttached(
                AgentRequest(id: "r1", tool: "proctor_find",
                             arguments: .object(["window": .string("win-1"), "predicate": .object([:])])))
        }
        let res2 = try await SessionIdentity.$current.withValue(id2) {
            try await h.session.forwardToGuestIfAttached(
                AgentRequest(id: "r2", tool: "proctor_act",
                             arguments: .object(["window": .string("win-2"), "steps": .array([])])))
        }

        #expect(res1 != nil)
        #expect(res2 != nil)

        // Host AX actuator must have executed zero steps
        #expect(h.hostAX.performed.isEmpty, "host actuator untouched during multi-session forwarded calls")

        // Clean detachment
        _ = try await detach(h.session, as: "client-1")
        _ = try await detach(h.session, as: "client-2")
    }
}
