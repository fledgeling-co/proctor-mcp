import Foundation
import Testing
@testable import ProctorCore

// PRO-0025 — where the drawn pointer belongs.
//
// The drawing itself is not testable here and is not pretended to be: a panel
// presenting, a window covering it, a dimmed glyph and the restack that puts it
// in the plane all need a window server. What is testable is the decision made
// before any of that, and the read-back that judges whether the restack held —
// which is precisely the part that must not quietly become an assumption.

@Suite("Pointer plane")
struct PointerPlaneTests {

    @Test("a correlated window that is on screen gets the pointer in its own plane")
    func inPlane() {
        #expect(PointerPlanePolicy.decide(targetWindowID: 4321, targetIsOnScreen: true)
                == .inPlane(above: 4321))
    }

    @Test("a target nobody can see gets no pointer at all")
    func offScreenDrawsNothing() {
        // Minimised, hidden, or on another Space: the on-screen window list says
        // the same thing for all three, and it is the right thing. Drawing a
        // dimmed pointer on the Space somebody is actually looking at would put
        // it over windows it has nothing to do with, which is the very
        // misstatement this feature removes.
        #expect(PointerPlanePolicy.decide(targetWindowID: 4321, targetIsOnScreen: false)
                == .hidden)
        #expect(PointerPlanePolicy.decide(targetWindowID: nil, targetIsOnScreen: false)
                == .hidden)
    }

    @Test("a window with no correlated id is marked rather than trusted")
    func uncorrelatedIsDimmed() {
        // Nothing to order against, so the plane cannot be established. The
        // pointer still draws — the run is worth following — but dimmed, so it
        // never claims a position it cannot hold.
        #expect(PointerPlanePolicy.decide(targetWindowID: nil, targetIsOnScreen: true)
                == .floatingDimmed)
        // A zero window number is the absence of one wearing a value.
        #expect(PointerPlanePolicy.decide(targetWindowID: 0, targetIsOnScreen: true)
                == .floatingDimmed)
    }

    @Test("the restack held only when the panel is immediately above its target")
    func heldIsStrict() {
        // Front to back.
        #expect(PointerPlanePolicy.held(panel: 20, above: 30, order: [10, 20, 30, 40]))
        // Anywhere-above is not good enough: the window at 25 would be drawn
        // under the pointer while being over the target, which is a smaller
        // version of the same lie.
        #expect(!PointerPlanePolicy.held(panel: 20, above: 30, order: [10, 20, 25, 30]))
        // Behind the target.
        #expect(!PointerPlanePolicy.held(panel: 40, above: 30, order: [10, 20, 30, 40]))
    }

    @Test("a placement that cannot be read back is not a placement")
    func heldFailsClosed() {
        // The panel missing from the list, the target gone, an empty list: none
        // of them is evidence the ordering took, so all of them demote to the
        // marked pointer rather than being read as success.
        #expect(!PointerPlanePolicy.held(panel: 20, above: 30, order: [30, 40]))
        #expect(!PointerPlanePolicy.held(panel: 20, above: 30, order: [10, 20]))
        #expect(!PointerPlanePolicy.held(panel: 20, above: 30, order: []))
        // And a panel cannot be above itself.
        #expect(!PointerPlanePolicy.held(panel: 20, above: 20, order: [10, 20, 30]))
    }

    @Test("the dimmed pointer is still legible")
    func dimmedIsMarkingNotHiding() {
        #expect(PointerPlanePolicy.dimmedOpacity > 0.15)
        #expect(PointerPlanePolicy.dimmedOpacity < 0.6)
    }
}
