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
