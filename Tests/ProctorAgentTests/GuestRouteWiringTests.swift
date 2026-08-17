import Foundation
import Testing
import ProctorCore
@testable import ProctorAgent

// PRO-0061 — the gate reaches act.
//
// A click on the host with PROCTOR_GUEST set is refused before anything
// posts. A press on the same session is not, because it would not take
// the Mac. A click on a session already marked as a guest is not refused
// here: that session is already elsewhere.

@Suite("PRO-0061 · a takeover batch on a configured host is refused")
struct GuestRouteWiringTests {

    private static let target = "com.example.target"

    private func harness(environment: [String: String] = [:],
                         machine: Machine = .host) async throws
        -> (session: Session, ax: FakeAX) {
        let ax = FakeAX(bundleId: Self.target)
        let session = Session(
            ax: ax, capture: FakeCapture(),
            tools: ToolProbes(environment: environment),
            secureInputProbe: { false })
        await session.setAuditSink({ _ in })
        await session.setDrawsHUD(false)
        if machine != .host { await session.setMachine(machine) }
        _ = try await session.attachResolved(bundleId: Self.target, pid: nil, name: nil)
        return (session, ax)
    }

    @Test("a click on the host with PROCTOR_GUEST set is refused and posts nothing")
    func clickOnAConfiguredHostIsRefused() async throws {
        let h = try await harness(environment: [GuestRouteConfig.env: "sequoia-seed"])
        do {
            _ = try await h.session.act(window: h.ax.window.id,
                                        steps: [ActionStep(kind: .click, node: "node-1")],
                                        settle: .default, foreground: false,
                                        captureEach: false, diffEach: false, record: nil)
            Issue.record("a click must not take the host when a guest is configured")
        } catch let error as AgentError {
            #expect(error.code == .notImplemented)
            #expect(error.message.contains("sequoia-seed"))
            #expect(error.message.contains("wrong machine"))
            #expect(error.remedy?.contains("Unset PROCTOR_GUEST") == true)
        }
        #expect(h.ax.performed.isEmpty)
    }

    @Test("a press on the same session is not refused — it would not take the Mac")
    func aBackgroundPressIsNotRouted() async throws {
        let h = try await harness(environment: [GuestRouteConfig.env: "sequoia-seed"])
        let result = try await h.session.act(window: h.ax.window.id,
                                             steps: [ActionStep(kind: .press, node: "node-1")],
                                             settle: .default, foreground: false,
                                             captureEach: false, diffEach: false, record: nil)
        #expect(result["completed"]?.intValue == 1)
        #expect(h.ax.performed.count == 1)
    }

    @Test("unset, a click takes the host as it always did")
    func unsetIsTheHost() async throws {
        let h = try await harness()
        _ = try await h.session.act(window: h.ax.window.id,
                                    steps: [ActionStep(kind: .click, node: "node-1")],
                                    settle: .default, foreground: true,
                                    captureEach: false, diffEach: false, record: nil)
        #expect(h.ax.performed.count == 1)
    }

    @Test("a session already on a guest is not refused by this gate")
    func alreadyOnAGuestRuns() async throws {
        let guest = Machine(kind: .guest, name: "sequoia-seed",
                            provider: "lume", platform: .macos, tier: .native)
        let h = try await harness(environment: [GuestRouteConfig.env: "other"],
                                  machine: guest)
        _ = try await h.session.act(window: h.ax.window.id,
                                    steps: [ActionStep(kind: .click, node: "node-1")],
                                    settle: .default, foreground: true,
                                    captureEach: false, diffEach: false, record: nil)
        #expect(h.ax.performed.count == 1)
    }
}
