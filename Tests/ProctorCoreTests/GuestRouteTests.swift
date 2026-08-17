import Foundation
import Testing
@testable import ProctorCore

// PRO-0061 — auto-routing is a gate, not a silent host run.
//
// This process cannot yet perform a step inside a guest, so a configured
// guest plus a batch that would take this Mac is a refusal that names the
// guest. Unset is the host. A session already on a guest is not refused.

@Suite("PRO-0061 · placing a takeover batch")
struct GuestRouteTests {

    private let guest = Machine(kind: .guest, name: "sequoia-seed",
                                provider: "lume", platform: .macos, tier: .native)

    @Test("unset, or a batch that would not take the Mac, stays on the host")
    func hostWhenNothingToRoute() {
        #expect(GuestRouteConfig.decide(machine: .host, takesForeground: true,
                                        configured: nil) == .host)
        #expect(GuestRouteConfig.decide(machine: .host, takesForeground: true,
                                        configured: "") == .host)
        #expect(GuestRouteConfig.decide(machine: .host, takesForeground: false,
                                        configured: "sequoia-seed") == .host)
    }

    @Test("a takeover batch with a guest configured refuses the host and names it")
    func takeoverWithAGuestIsRefused() throws {
        let route = GuestRouteConfig.decide(machine: .host, takesForeground: true,
                                            configured: "sequoia-seed")
        guard case .refuseHost(let name, let demand) = route else {
            Issue.record("expected a refusal"); return
        }
        #expect(name == "sequoia-seed")
        #expect(demand.contains("PROCTOR_GUEST"))
        #expect(demand.contains("sequoia-seed"))
        #expect(demand.contains("wrong machine"))
        let refusal = try #require(GuestRouteConfig.refusal(for: route))
        #expect(refusal.remedy.contains("Unset PROCTOR_GUEST"))
        #expect(refusal.remedy.contains("reach"))
    }

    @Test("a session already on a guest is not refused here")
    func alreadyOnAGuest() {
        let route = GuestRouteConfig.decide(machine: guest, takesForeground: true,
                                            configured: "other")
        guard case .alreadyOnGuest(let machine) = route else {
            Issue.record("expected already-on-guest"); return
        }
        #expect(machine.name == "sequoia-seed")
        #expect(GuestRouteConfig.refusal(for: route) == nil)
    }

    @Test("the configured name is the trimmed environment value")
    func configuredName() {
        #expect(GuestRouteConfig.configured([:]) == nil)
        #expect(GuestRouteConfig.configured(["PROCTOR_GUEST": "  "]) == nil)
        #expect(GuestRouteConfig.configured(["PROCTOR_GUEST": " sequoia-seed "])
                == "sequoia-seed")
    }
}
