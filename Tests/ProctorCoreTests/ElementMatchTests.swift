import Testing
import Foundation
@testable import ProctorCore

// PRO-0044, slice 3. Whether the element a delegated backend is about to strike
// is the element Proctor resolved.
//
// The cases that matter are the refusals. A matcher that returns a hit whenever
// it can find one is worse than useless here: the failure it produces is a click
// on the wrong control that replays green forever, which is exactly the defect
// this repo exists to detect in other people's tools.

private func button(_ index: Int, _ label: String?, parent: Int?, depth: Int,
                    frame: Rect? = nil, role: String = "AXButton") -> ElementCandidate {
    ElementCandidate(index: index, role: role, label: label, frame: frame,
                     parentIndex: parent, depth: depth)
}

private func group(_ index: Int, _ label: String?, parent: Int?, depth: Int) -> ElementCandidate {
    ElementCandidate(index: index, role: "AXGroup", label: label,
                     parentIndex: parent, depth: depth)
}

private let window = ElementCandidate(index: 0, role: "AXWindow", label: "Main",
                                      parentIndex: nil, depth: 0)

private func identity(_ rungs: [(String, String?)], frame: Rect? = nil) -> ElementIdentity {
    ElementIdentity(chain: rungs.map { ElementStep(role: $0.0, label: $0.1) }, frame: frame)
}

@Suite("Element matching across the backend boundary")
struct ElementMatchTests {

    @Test("a unique chain matches")
    func uniqueChain() {
        let candidates = [window, group(1, "Toolbar", parent: 0, depth: 1),
                          button(2, "Save", parent: 1, depth: 2)]
        let want = identity([("AXWindow", "Main"), ("AXGroup", "Toolbar"), ("AXButton", "Save")])
        #expect(ElementMatch.match(identity: want, candidates: candidates) == .matched(2))
    }

    @Test("two OK buttons under different parents are told apart by their ancestry")
    func chainDisambiguates() {
        // The case an identifier would have solved, solved instead by the one
        // disambiguator a driver publishing a parent index actually gives us.
        let candidates = [window,
                          group(1, "Save sheet", parent: 0, depth: 1),
                          button(2, "OK", parent: 1, depth: 2),
                          group(3, "Quit sheet", parent: 0, depth: 1),
                          button(4, "OK", parent: 3, depth: 2)]
        let want = identity([("AXWindow", "Main"), ("AXGroup", "Quit sheet"), ("AXButton", "OK")])
        #expect(ElementMatch.match(identity: want, candidates: candidates) == .matched(4))
    }

    @Test("two identical buttons under the same parent refuse rather than guess")
    func sameChainIsAmbiguous() {
        let candidates = [window,
                          group(1, "Row", parent: 0, depth: 1),
                          button(2, "Delete", parent: 1, depth: 2),
                          button(3, "Delete", parent: 1, depth: 2)]
        let want = identity([("AXWindow", "Main"), ("AXGroup", "Row"), ("AXButton", "Delete")])
        guard case .ambiguous(_, let hits) = ElementMatch.match(identity: want,
                                                                candidates: candidates) else {
            Issue.record("two identical elements must not resolve to one")
            return
        }
        #expect(hits == [2, 3])
    }

    @Test("a pair separable only by position is refused, not resolved by the position")
    func frameOnlySeparationRefuses() {
        // The trap this whole file exists to avoid. The frame CAN pick one out.
        // Letting it would make the match a coordinate strike, which replays by
        // hitting an absolute position and breaks the moment the layout moves.
        let candidates = [window,
                          group(1, "Row", parent: 0, depth: 1),
                          button(2, "Delete", parent: 1, depth: 2,
                                 frame: Rect(x: 0, y: 0, w: 40, h: 20)),
                          button(3, "Delete", parent: 1, depth: 2,
                                 frame: Rect(x: 200, y: 0, w: 40, h: 20))]
        let want = identity([("AXWindow", "Main"), ("AXGroup", "Row"), ("AXButton", "Delete")],
                            frame: Rect(x: 0, y: 0, w: 40, h: 20))
        guard case .ambiguous(let why, _) = ElementMatch.match(identity: want,
                                                               candidates: candidates) else {
            Issue.record("a frame must never be the only thing deciding a match")
            return
        }
        #expect(why.contains("coordinate"))
    }

    @Test("a complete view with no match says the element is absent")
    func absentWhenComplete() {
        let candidates = [window, button(1, "Save", parent: 0, depth: 1)]
        let want = identity([("AXWindow", "Main"), ("AXButton", "Cancel")])
        #expect(ElementMatch.match(identity: want, candidates: candidates) == .absent)
    }

    @Test("a truncated view can never say absent")
    func truncationIsNeverAbsent() {
        // "I could not finish looking" and "it is not there" lead a caller to
        // opposite conclusions, and only one of them is honest here.
        let candidates = [window, button(1, "Save", parent: 0, depth: 1)]
        let want = identity([("AXWindow", "Main"), ("AXButton", "Cancel")])
        let outcome = ElementMatch.match(identity: want, candidates: candidates, truncated: true)
        guard case .ambiguous(let why, _) = outcome else {
            Issue.record("a truncated view must not report absence")
            return
        }
        #expect(why.contains("truncated"))
    }

    @Test("a chain deeper than the candidate's ancestry is a different element")
    func deeperChainDoesNotMatchASuffix() {
        let candidates = [window, button(1, "Save", parent: 0, depth: 1)]
        let want = identity([("AXWindow", "Main"), ("AXGroup", "Toolbar"), ("AXButton", "Save")])
        #expect(ElementMatch.match(identity: want, candidates: candidates) == .absent)
    }

    // MARK: - Agreement, which is what covers the first attempt

    @Test("two observers describing the same element agree")
    func agreementHolds() {
        let want = identity([("AXButton", "Save")], frame: Rect(x: 10, y: 10, w: 40, h: 20))
        let theirs = button(2, "Save", parent: 1, depth: 2,
                            frame: Rect(x: 11, y: 10, w: 40, h: 20))
        #expect(ElementMatch.agrees(identity: want, candidate: theirs))
    }

    @Test("a candidate somewhere else on screen is a disagreement")
    func frameDisagreementRefuses() {
        let want = identity([("AXButton", "Save")], frame: Rect(x: 10, y: 10, w: 40, h: 20))
        let theirs = button(2, "Save", parent: 1, depth: 2,
                            frame: Rect(x: 600, y: 400, w: 40, h: 20))
        #expect(!ElementMatch.agrees(identity: want, candidate: theirs))
    }

    @Test("a different label at the same place is a disagreement")
    func labelDisagreementRefuses() {
        // The mutation case: the slot is where it was, and something else is in
        // it. No handle went stale, so nothing would have raised an error.
        let want = identity([("AXButton", "Save")], frame: Rect(x: 10, y: 10, w: 40, h: 20))
        let theirs = button(2, "Discard", parent: 1, depth: 2,
                            frame: Rect(x: 10, y: 10, w: 40, h: 20))
        #expect(!ElementMatch.agrees(identity: want, candidate: theirs))
    }

    @Test("an element with no geometry on either side is not a disagreement")
    func missingFramesAreNotADisagreement() {
        let want = identity([("AXMenuItem", "Open")])
        let theirs = ElementCandidate(index: 3, role: "AXMenuItem", label: "Open",
                                      parentIndex: 1, depth: 2)
        #expect(ElementMatch.agrees(identity: want, candidate: theirs))
    }
}
