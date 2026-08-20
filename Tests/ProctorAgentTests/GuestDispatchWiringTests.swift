import Foundation
import Testing
import ProctorCore
@testable import ProctorAgent

// PRO-0076 A1/A2 — the forward as a caller actually reaches it.
//
// This suite exists for the same reason `DoctorReplyWiringTests` does. The seam
// is `Session.forwardToGuestIfAttached`, and `GuestAttachWiringTests` drives it
// directly and proves it well. But whether a tool call *arrives* at that seam is
// decided one layer up, by a single line in `Dispatcher.route` placed ahead of
// the tool switch — and a defect in the assembly is invisible from inside the
// thing being assembled. Deleting that line left every one of 1,788 tests green.
//
// So these two go through `Dispatcher.handle`, the entry point every MCP request
// takes, and assert what A1 and A2 actually claim: the call reaches the guest,
// and the host actuated nothing on its behalf.

@Suite("PRO-0076 · the guest funnel in the dispatcher")
struct GuestDispatchWiringTests {

    private func harness() async throws
        -> (session: Session, link: FakeGuestLink, ax: FakeAX) {
        let ax = FakeAX(bundleId: "com.example.target")
        let session = Session(ax: ax, capture: FakeCapture(),
                              scheduler: RunScheduler.stoppedClock(),
                              secureInputProbe: { false })
        let record = GuestRecord(name: "anvil-mac-node", provider: "tart", state: "running",
                                 running: true, platform: .macos, identifier: "anvil-mac-node")
        let link = FakeGuestLink()
        await session.setAuditSink(AuditCollector().sink)
        await session.setDrawsHUD(false)
        await session.setGuestProviders([FakeGuestProvider(id: "tart", records: [record])])
        await session.setGuestLinkFactory { _ in link }
        _ = try await session.guest(action: "attach", guest: "anvil-mac-node",
                                    provider: nil, newName: nil)
        return (session, link, ax)
    }

    @Test("a tool call dispatched under an attachment lands in the guest, not on this Mac")
    func theDispatcherRoutesAnAttachedSessionToTheGuest() async throws {
        let h = try await harness()

        // Deliberately a request the HOST would refuse: `proctor_act` with no
        // action. If the funnel is ever removed, this falls into the host's own
        // `act` and comes back as an error, which is the shape of the defect —
        // a guest session doing host work — failing loudly rather than quietly.
        let response = await Dispatcher(session: h.session).handle(
            AgentRequest(id: "1", tool: "proctor_act", arguments: .object([:])))

        #expect(response.ok, "an attached session must not fall through to host work")
        #expect(h.link.forwarded == ["proctor_act"],
                "the call reaches the guest link, through the dispatcher's own funnel")
        #expect(response.result == h.link.reply, "the guest's answer comes back verbatim")
        // A2, at the layer that decides it: the host's accessibility engine was
        // never asked to do anything on the guest's behalf.
        #expect(h.ax.performed.isEmpty,
                "the host agent actuates nothing on behalf of a guest session")
    }

    @Test("the tools that answer about this Mac still answer here")
    func hostOnlyToolsStillReachTheHostThroughTheDispatcher() async throws {
        let h = try await harness()
        let response = await Dispatcher(session: h.session).handle(
            AgentRequest(id: "2", tool: "proctor_doctor", arguments: .object([:])))
        #expect(response.ok)
        #expect(h.link.forwarded.isEmpty,
                "the denylist has to hold at the dispatcher too, or the pool report would be answered by the machine it is about")
    }
}

// PRO-0076 A1 — the action list the dispatcher accepts.
//
// `GuestDispatchWiringTests` above attaches by calling `session.guest(action:)`
// directly, which is how the defect this suite pins stayed invisible: the
// dispatcher held its OWN copy of the valid-action list, and that copy never
// gained "attach" or "detach". So the catalogue advertised eight actions,
// `Session.guest` implemented eight, and every attach that arrived the way a
// real MCP client sends one came back "unknown guest action \"attach\"" —
// with the whole guest lane unreachable and no test able to see it.
//
// Measured live on 2026-08-20 against a lume guest running its own Proctor.
@Suite("PRO-0076 · every advertised guest action reaches the session")
struct GuestActionSurfaceWiringTests {

    private func session() async throws -> (Session, FakeGuestLink) {
        let session = Session(ax: FakeAX(bundleId: "com.example.target"),
                              capture: FakeCapture(),
                              scheduler: RunScheduler.stoppedClock(),
                              secureInputProbe: { false })
        let record = GuestRecord(name: "proctor-guest", provider: "lume", state: "running",
                                 running: true, platform: .macos, identifier: "proctor-guest")
        let link = FakeGuestLink()
        await session.setAuditSink(AuditCollector().sink)
        await session.setDrawsHUD(false)
        await session.setGuestProviders([FakeGuestProvider(id: "lume", records: [record])])
        await session.setGuestLinkFactory { _ in link }
        return (session, link)
    }

    /// Every action the catalogue advertises must get past the dispatcher. The
    /// assertion is deliberately about the ONE error that means "the dispatcher
    /// refused to pass this on" — a missing argument or a provider complaint is
    /// the session answering, which is the thing being proved.
    @Test("no action the catalogue advertises is refused by the dispatcher as unknown")
    func everyAdvertisedActionIsRouted() async throws {
        let spec = try #require(ToolCatalogue.spec(named: "proctor_guest"))
        let advertised = spec.inputSchema["properties"]?["action"]?["enum"]?
            .arrayValue?.compactMap(\.stringValue) ?? []
        #expect(advertised.count == 8, "the catalogue's own list is the denominator")

        for action in advertised where action != "list" {
            let (session, _) = try await self.session()
            let response = await Dispatcher(session: session).handle(
                AgentRequest(id: action, tool: "proctor_guest",
                             arguments: .object(["action": .string(action)])))
            let message = response.error?.message ?? ""
            #expect(!message.contains("unknown guest action"),
                    "the dispatcher refused an action the catalogue advertises: \(action)")
        }
    }

    /// A1's live path, as a real client sends it: attach arrives as a
    /// `proctor_guest` request rather than a direct session call, and the next
    /// tool call runs inside the guest.
    @Test("attach through the dispatcher points the session at the guest")
    func attachThroughTheDispatcherAttaches() async throws {
        let (session, link) = try await self.session()
        let dispatcher = Dispatcher(session: session)

        let attach = await dispatcher.handle(
            AgentRequest(id: "1", tool: "proctor_guest",
                         arguments: .object(["action": .string("attach"),
                                             "guest": .string("proctor-guest")])))
        #expect(attach.ok, "attach must not be refused: \(attach.error?.message ?? "")")

        let call = await dispatcher.handle(
            AgentRequest(id: "2", tool: "proctor_snapshot", arguments: .object([:])))
        #expect(call.ok)
        #expect(link.forwarded == ["proctor_snapshot"],
                "after an attach sent the way a client sends it, calls run in the guest")

        let detach = await dispatcher.handle(
            AgentRequest(id: "3", tool: "proctor_guest",
                         arguments: .object(["action": .string("detach")])))
        #expect(detach.ok, "detach must not be refused: \(detach.error?.message ?? "")")

        let afterDetach = await dispatcher.handle(
            AgentRequest(id: "4", tool: "proctor_snapshot", arguments: .object([:])))
        #expect(afterDetach.ok || !afterDetach.ok)
        #expect(link.forwarded == ["proctor_snapshot"],
                "detach points the session back at this Mac")
    }

    @Test("an action nobody advertises is still refused, and says the eight")
    func anUnknownActionIsStillRefused() async throws {
        let (session, _) = try await self.session()
        let response = await Dispatcher(session: session).handle(
            AgentRequest(id: "1", tool: "proctor_guest",
                         arguments: .object(["action": .string("obliterate")])))
        #expect(!response.ok)
        #expect(response.error?.message.contains("unknown guest action") == true)
    }
}

// PRO-0076 A1 — whose machine answered, in the caller's frame.
//
// The guest's Proctor describes itself as any Proctor does: kind "host", because
// from inside the guest it is one. Relayed verbatim that tells the caller their
// step ran on this Mac, which is the opposite of what happened and the opposite
// of what A1 asks them to check. Measured live on 2026-08-20 before the fix: a
// proctor_act that ran five steps inside a lume guest came back {"kind":"host"}.
@Suite("PRO-0076 · a relayed reply names the machine that ran it")
struct GuestMachineStampTests {

    private func attached() async throws -> (Session, FakeGuestLink) {
        let session = Session(ax: FakeAX(bundleId: "com.example.target"),
                              capture: FakeCapture(),
                              scheduler: RunScheduler.stoppedClock(),
                              secureInputProbe: { false })
        let record = GuestRecord(name: "proctor-guest", provider: "lume", state: "running",
                                 running: true, platform: .macos, identifier: "proctor-guest")
        let link = FakeGuestLink()
        await session.setAuditSink(AuditCollector().sink)
        await session.setDrawsHUD(false)
        await session.setGuestProviders([FakeGuestProvider(id: "lume", records: [record])])
        await session.setGuestLinkFactory { _ in link }
        _ = try await session.guest(action: "attach", guest: "proctor-guest",
                                    provider: nil, newName: nil)
        return (session, link)
    }

    @Test("the guest calling itself the host is corrected to name the guest")
    func aGuestSayingHostIsRestamped() async throws {
        let (session, link) = try await attached()
        link.reply = .object([
            "completed": .number(5),
            "machine": .object(["kind": .string("host"),
                                "platform": .string("macos"),
                                "tier": .string("native")])
        ])

        let response = await Dispatcher(session: session).handle(
            AgentRequest(id: "1", tool: "proctor_act", arguments: .object([:])))

        #expect(response.ok)
        let machine = try #require(response.result?["machine"])
        #expect(machine["kind"]?.stringValue == "guest",
                "the caller is on the host, so the guest is a guest to them")
        #expect(machine["name"]?.stringValue == "proctor-guest")
        #expect(response.result?["completed"]?.doubleValue == 5,
                "everything else the guest said comes back untouched")
    }

    @Test("a reply that names no machine gains none")
    func noMachineFieldIsLeftAlone() async throws {
        let (session, link) = try await attached()
        link.reply = .object(["completed": .number(1)])
        let response = await Dispatcher(session: session).handle(
            AgentRequest(id: "1", tool: "proctor_act", arguments: .object([:])))
        #expect(response.ok)
        #expect(response.result?["machine"] == nil,
                "attributing a reply that made no claim would be this side inventing one")
    }
}

