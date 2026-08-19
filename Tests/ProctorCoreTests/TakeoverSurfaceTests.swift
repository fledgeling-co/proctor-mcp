import Foundation
import Testing
@testable import ProctorCore

// PRO-0070. What the takeover notice claims, and what it must not.

@Suite("Takeover surface")
struct TakeoverSurfaceTests {

    @Test("A1 · the refusal names the guest and the switch that clears it")
    func refusalNamesTheGuest() {
        let route = GuestRouteConfig.decide(machine: .host, takesForeground: true,
                                      configured: "gst-sequoia-01")
        let refusal = TakeoverSurface.refusal(for: route)
        #expect(refusal != nil)
        #expect(refusal?.guest == "gst-sequoia-01")
        // Both halves are needed: which guest caused it, and what clears it.
        // A refusal a person cannot act on is a bare denial.
        #expect(refusal?.message.contains("gst-sequoia-01") == true)
        #expect(refusal?.remedy.contains("PROCTOR_GUEST") == true)
    }

    @Test("A1 · no guest configured and no foreground demand is not a refusal")
    func noRefusalWithoutBoth() {
        #expect(TakeoverSurface.refusal(for: .host) == nil)
        // A batch that never takes the machine is not refused, whatever is set.
        let background = GuestRouteConfig.decide(machine: .host, takesForeground: false,
                                           configured: "gst-sequoia-01")
        #expect(TakeoverSurface.refusal(for: background) == nil)
        // A session already on a guest is already elsewhere.
        let onGuest = Machine(kind: .guest, name: "gst-sequoia-01", provider: "lume",
                              platform: .macos, tier: .native)
        let already = GuestRouteConfig.decide(machine: onGuest, takesForeground: true,
                                        configured: "gst-sequoia-01")
        #expect(TakeoverSurface.refusal(for: already) == nil)
    }

    @Test("A3 · Stop is reachable whenever the veil is up")
    func stopUnderTheVeil() {
        // The veil covers the screen. A person whose Stop is underneath it has
        // no way to halt a run that is holding their keyboard.
        #expect(TakeoverSurface.offersStop(in: .armed))
        #expect(!TakeoverSurface.offersStop(in: .absent))
    }

    @Test("the copy states the mechanism and claims nothing about consequence")
    func claimsOnlyMechanism() {
        // PRO-0026 finding 10: an all-accessibility run can delete a file
        // through AXPress with this overlay never appearing. So the overlay
        // means "Proctor holds the event stream" and must not imply more.
        let copy = (TakeoverSurface.Copy.title + " " + TakeoverSurface.Copy.body).lowercased()
        for claim in TakeoverSurface.Copy.forbiddenClaims {
            #expect(!copy.contains(claim),
                    "the overlay implies consequence it cannot know: “\(claim)”")
        }
        // And it says what the person can still do, which is the part that
        // makes it a notice rather than a warning.
        #expect(TakeoverSurface.Copy.body.contains("pauses"))
    }

    @Test("identifiers are unique and namespaced")
    func identifiers() {
        var all = TakeoverSurface.State.allCases.map(TakeoverSurface.ID.overlay)
        all += [TakeoverSurface.ID.stop, TakeoverSurface.ID.pause, TakeoverSurface.ID.refusal]
        #expect(Set(all).count == all.count)
        for id in all { #expect(id.hasPrefix("proctor.takeover.")) }
    }
}
