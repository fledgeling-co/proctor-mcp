import Foundation
import Testing
@testable import ProctorCore

// A pointer over a window nobody can see.
//
// Reported from real use: "sometimes I'll see the fake cursor moving during
// testing, but the app it's working on is in the background and not visible,
// which makes the fake cursor's operation confusing."
//
// The window list called that target on screen — covered is not minimised — so
// the plane was attempted, and when the restack did not hold the pointer fell
// back to floating above everything. That is the picture `PointerPlane`'s own
// header says must never be painted: a pointer over the app the person is
// looking at, while Proctor drives a different one. The dimming was standing in
// for not painting it, and dimming marks uncertainty about a position rather
// than a pointer in the wrong plane entirely.

@Suite("Pointer plane over a covered target")
struct PointerPlaneCoveredTests {

    @Test("a covered target with no resolvable window id draws nothing rather than floating")
    func coveredWithoutAnIDIsHidden() {
        #expect(PointerPlanePolicy.decide(targetWindowID: nil, targetIsOnScreen: true,
                                          targetIsCovered: true) == .hidden)
        // Uncovered is unchanged: the pointer is where it would be anyway and
        // only the exact ordering is unconfirmed.
        #expect(PointerPlanePolicy.decide(targetWindowID: nil, targetIsOnScreen: true,
                                          targetIsCovered: false) == .floatingDimmed)
    }

    @Test("off screen still wins over everything, covered or not")
    func offScreenIsAlwaysHidden() {
        // Minimised, hidden, or on another Space. All three mean the same thing.
        #expect(PointerPlanePolicy.decide(targetWindowID: 42, targetIsOnScreen: false,
                                          targetIsCovered: false) == .hidden)
        #expect(PointerPlanePolicy.decide(targetWindowID: 42, targetIsOnScreen: false,
                                          targetIsCovered: true) == .hidden)
    }

    @Test("a restack that did not hold falls back by whether anything covers the target")
    func fallbackSplitsOnCover() {
        // Front to back. The target at the front is covered by nothing.
        #expect(PointerPlanePolicy.fallback(target: 7, order: [7, 8, 9]) == .floatingDimmed)
        // Something is drawn over it: there is no honest place for the pointer.
        #expect(PointerPlanePolicy.fallback(target: 7, order: [9, 7, 8]) == .hidden)
    }

    @Test("a target that is not in the window list at all is treated as covered")
    func absentFromTheListIsCovered() {
        // It went away between the ordering call and the read-back. Refusing to
        // draw is the safe direction: the alternative is a pointer annotating a
        // window that is no longer there.
        #expect(PointerPlanePolicy.isCovered(target: 7, order: [1, 2, 3]))
        #expect(PointerPlanePolicy.fallback(target: 7, order: [1, 2, 3]) == .hidden)
    }

    @Test("Proctor's own panels do not count as covering the target")
    func ourOwnPanelsAreNotCover() {
        // The pointer's surfaces sit above their target by construction, and the
        // run panel sits above everything. Counting either would hide the
        // pointer from every target it ever annotates — the fix turning into a
        // regression that looks like the feature never worked.
        #expect(!PointerPlanePolicy.isCovered(target: 7, order: [100, 101, 7, 8],
                                              ignoring: [100, 101]))
        #expect(PointerPlanePolicy.fallback(target: 7, order: [100, 101, 7, 8],
                                            ours: [100, 101]) == .floatingDimmed)
        // And a real window above them still counts.
        #expect(PointerPlanePolicy.isCovered(target: 7, order: [100, 55, 7],
                                             ignoring: [100]))
    }

    @Test("the happy path is untouched")
    func inPlaneStillWins() {
        #expect(PointerPlanePolicy.decide(targetWindowID: 42, targetIsOnScreen: true,
                                          targetIsCovered: false) == .inPlane(above: 42))
        // Covered does not change the attempt: in plane, a covering window
        // covers the pointer too, which is the truthful picture. The split only
        // decides what happens when that attempt fails.
        #expect(PointerPlanePolicy.decide(targetWindowID: 42, targetIsOnScreen: true,
                                          targetIsCovered: true) == .inPlane(above: 42))
    }
}
