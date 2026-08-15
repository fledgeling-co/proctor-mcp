import Foundation
import Testing
@testable import ProctorCore

// PRO-0042 — the classifier behind proctor_assert's horizontalAlignment kind.
//
// This is the whole of the decision the assertion makes: two rectangles and a
// tolerance in, a placement or a stated inability to name one out. It needs no
// window, so it is checked here exhaustively and the agent-side tests only have
// to prove the Outcome is shaped from it correctly.
//
// The two behaviours that shipped wrong are the two most heavily covered: the
// tolerance used to be tripled on the edges and left alone on the centre, and a
// container barely wider than its element used to be answered `center` by
// precedence rather than by measurement.

@Suite("Horizontal placement")
struct HorizontalPlacementTests {

    /// A 1000-wide container at the origin, wide enough that the three
    /// placements are nowhere near each other.
    private static let container = Rect(x: 0, y: 0, w: 1000, h: 100)

    private func element(x: Double, w: Double = 100) -> Rect {
        Rect(x: x, y: 0, w: w, h: 20)
    }

    // MARK: - Clause 1: one tolerance, applied identically

    @Test("the tolerance is one distance on both edges and on the centre")
    func toleranceAppliesEquallyToEdgesAndCentre() {
        // Exactly at the tolerance is inside it on all three, and just past it is
        // outside on all three. The shipped code tripled the tolerance for the two
        // edges, so an element 3x out on its leading edge still read `left` while
        // the same drift on the centre read `custom`.
        let tolerance = 4.0

        let atLeft = HorizontalPlacement.read(element: element(x: 4), container: Self.container,
                                              tolerance: tolerance)
        #expect(atLeft.placement == .left)

        let pastLeft = HorizontalPlacement.read(element: element(x: 4.1), container: Self.container,
                                                tolerance: tolerance)
        #expect(pastLeft.placement == nil)
        #expect(pastLeft.isCustom)

        // The right edge, symmetrically. An element ending 4pt short of the
        // container's right edge is right-aligned; 4.1pt short is not.
        let atRight = HorizontalPlacement.read(element: element(x: 896), container: Self.container,
                                               tolerance: tolerance)
        #expect(atRight.placement == .right)
        let pastRight = HorizontalPlacement.read(element: element(x: 895.9),
                                                 container: Self.container, tolerance: tolerance)
        #expect(pastRight.isCustom)

        // And the centre, at the same distance.
        let atCentre = HorizontalPlacement.read(element: element(x: 454), container: Self.container,
                                                tolerance: tolerance)
        #expect(atCentre.placement == .center)
        let pastCentre = HorizontalPlacement.read(element: element(x: 454.1),
                                                  container: Self.container, tolerance: tolerance)
        #expect(pastCentre.isCustom)
    }

    @Test("three times the tolerance on an edge is custom, not left")
    func theTripledToleranceIsGone() {
        // The specific regression. Under the shipped classifier this element read
        // `leading`, because the leading test was `<= tolerance * 3`.
        let reading = HorizontalPlacement.read(element: element(x: 24), container: Self.container,
                                               tolerance: 8)
        #expect(reading.isCustom)
        #expect(reading.placement == nil)
    }

    @Test("a negative tolerance is clamped rather than matching nothing")
    func negativeToleranceClamps() {
        let reading = HorizontalPlacement.read(element: element(x: 0), container: Self.container,
                                               tolerance: -50)
        #expect(reading.tolerance == 0)
        #expect(reading.placement == .left)
    }

    // MARK: - Clause 2: the vocabulary

    @Test("the semantic words parse to the physical ones")
    func aliasesParseToPhysicalWords() {
        #expect(HorizontalPlacement.parse("left") == .left)
        #expect(HorizontalPlacement.parse("leading") == .left)
        #expect(HorizontalPlacement.parse("right") == .right)
        // The asymmetry that shipped: `left` was accepted for leading and `right`
        // was accepted for nothing at all.
        #expect(HorizontalPlacement.parse("trailing") == .right)
        #expect(HorizontalPlacement.parse("center") == .center)
        #expect(HorizontalPlacement.parse("centre") == .center)
        // Case and surrounding space are the caller's, not the vocabulary's.
        #expect(HorizontalPlacement.parse("  LEADING ") == .left)
        #expect(HorizontalPlacement.parse("Centre") == .center)
    }

    @Test("the reported word is always the physical one")
    func observationsArePhysical() {
        // Nothing here reads layout direction, so `leading` would be a claim the
        // measurement cannot support.
        #expect(HorizontalPlacement.left.rawValue == "left")
        #expect(HorizontalPlacement.right.rawValue == "right")
        #expect(HorizontalPlacement.allCases.map(\.rawValue) == ["left", "center", "right"])
    }

    // MARK: - Clause 3: an unusable word decides nothing

    @Test("a word outside the vocabulary parses to nothing")
    func anUnknownWordParsesToNothing() {
        #expect(HorizontalPlacement.parse("middle") == nil)
        #expect(HorizontalPlacement.parse("start") == nil)
        #expect(HorizontalPlacement.parse("") == nil)
        // The caller has to be told what was acceptable, so the list is part of
        // the type rather than a string at one call site.
        #expect(HorizontalPlacement.acceptedWords.contains("left"))
        #expect(HorizontalPlacement.acceptedWords.contains("trailing"))
    }

    // MARK: - Clause 4: the nearest fit wins

    @Test("the nearest placement wins in a container barely wider than the element")
    func theNearestPlacementWinsInACompactContainer() {
        // A 28pt control in a 36pt cell: offsets 0, 4 and 8. At a tolerance of 8
        // all three are candidates, and the element is plainly left-aligned.
        // Refusing to rank this would make an ordinary compact layout
        // unassertable, since a run's `ok` requires nothing was skipped.
        let cell = Rect(x: 100, y: 0, w: 36, h: 20)
        let reading = HorizontalPlacement.read(element: Rect(x: 100, y: 0, w: 28, h: 20),
                                               container: cell, tolerance: 8)
        #expect(reading.candidates == [.left, .center, .right])
        #expect(reading.placement == .left)
        #expect(!reading.isTied)
        #expect(!reading.isCustom)

        // The same cell with the control at its trailing edge ranks the other way.
        let trailing = HorizontalPlacement.read(element: Rect(x: 108, y: 0, w: 28, h: 20),
                                                container: cell, tolerance: 8)
        #expect(trailing.placement == .right)

        // And centred in it.
        let centred = HorizontalPlacement.read(element: Rect(x: 104, y: 0, w: 28, h: 20),
                                               container: cell, tolerance: 8)
        #expect(centred.placement == .center)
    }

    // MARK: - Clause 5: only a genuine tie is undecidable

    @Test("an element that fills its container ties on all three")
    func anElementFillingItsContainerIsATie() {
        let reading = HorizontalPlacement.read(element: Self.container,
                                               container: Self.container, tolerance: 1)
        #expect(reading.leftOffset == 0)
        #expect(reading.rightOffset == 0)
        #expect(reading.centreOffset == 0)
        #expect(reading.isTied)
        #expect(reading.placement == nil)
        #expect(!reading.isCustom)
        #expect(reading.nearest == [.left, .center, .right])
    }

    @Test("two offsets within the tie window tie; a clear winner does not")
    func theTieWindowIsTheRoundingAllowance() {
        // A 999.6-wide element in a 1000-wide container at x+0.2: left 0.2,
        // centre -0.2, right -0.2. Every pair is within half a point, which is
        // less than one device pixel at 2x — a real tie.
        let reading = HorizontalPlacement.read(element: Rect(x: 0.2, y: 0, w: 999.6, h: 20),
                                               container: Self.container, tolerance: 2)
        #expect(reading.isTied)
        #expect(reading.nearest == [.left, .center, .right])

        // Widen the gap past the tie window and it decides.
        let decided = HorizontalPlacement.read(element: Rect(x: 0, y: 0, w: 996, h: 20),
                                               container: Self.container, tolerance: 4)
        #expect(decided.placement == .left)
        #expect(!decided.isTied)
    }

    @Test("the tie window is not the default tolerance, so ranking still works at the default")
    func rankingSurvivesAtTheDefaultTolerance() {
        // The defect the completeness gate found. When the tie window equals the
        // tolerance, every multi-candidate reading at the default is a tie — the
        // candidate band is only one tolerance wide, so no two candidates can be
        // further apart than that — and the nearest-fit rule never runs where
        // most callers are.
        #expect(HorizontalPlacement.tieWindow < HorizontalPlacement.defaultTolerance)

        // A 16pt element flush against an 18pt cell: offsets 0, -1, -2. At the
        // default tolerance left and centre are both candidates, and the element
        // is plainly left-aligned. `ok` requires nothing was skipped, so calling
        // this undecidable would make an ordinary row unassertable.
        let cell = Rect(x: 0, y: 0, w: 18, h: 20)
        let reading = HorizontalPlacement.read(element: Rect(x: 0, y: 0, w: 16, h: 20),
                                               container: cell)
        #expect(reading.candidates == [.left, .center])
        #expect(!reading.isTied)
        #expect(reading.placement == .left)
    }

    // MARK: - Frames that cannot be measured

    @Test("a non-finite or negative frame is not measurable")
    func nonFiniteFramesAreRejected() {
        // Every comparison against a NaN is false, so an unguarded NaN width
        // reads as `custom` — a confident verdict from an unreadable frame — and
        // a finite origin beside a NaN width reads as a confident `left`.
        #expect(!HorizontalPlacement.isMeasurable(Rect(x: .nan, y: 0, w: 100, h: 20)))
        #expect(!HorizontalPlacement.isMeasurable(Rect(x: 0, y: 0, w: .nan, h: 20)))
        #expect(!HorizontalPlacement.isMeasurable(Rect(x: 0, y: 0, w: .infinity, h: 20)))
        // A negative width is not the rectangle that was drawn, so classifying
        // from its origin would answer about a box that is not on screen.
        #expect(!HorizontalPlacement.isMeasurable(Rect(x: 0, y: 0, w: -10, h: 20)))

        // A zero-width element is a real thing (a separator, a collapsed view)
        // and measures fine, as does a bad `y` the classification never reads.
        #expect(HorizontalPlacement.isMeasurable(Rect(x: 0, y: 0, w: 0, h: 20)))
        #expect(HorizontalPlacement.isMeasurable(Rect(x: 0, y: .nan, w: 100, h: .nan)))
    }

    @Test("a roomy container separates the placements outright")
    func aRoomyContainerDistinguishesExactlyOne() {
        let reading = HorizontalPlacement.read(element: element(x: 0), container: Self.container,
                                               tolerance: 1)
        #expect(reading.candidates == [.left])
        #expect(reading.placement == .left)
        #expect(!reading.isTied)
    }

    // MARK: - Clause 6: one default across the tool

    @Test("the default tolerance is the same one the other geometry kinds use")
    func theDefaultIsOnePoint() {
        // The trap this closes: the kind shipped defaulting to 8.0 beside
        // alignedWith's 1.0 on the same tool, so a `tolerance` copied from one
        // assertion to the next changed strictness eightfold without saying so.
        #expect(HorizontalPlacement.defaultTolerance == 1.0)
        #expect(HorizontalPlacement.tieWindow == 0.5)
        let defaulted = HorizontalPlacement.read(element: element(x: 0.5),
                                                 container: Self.container)
        #expect(defaulted.tolerance == 1.0)
        #expect(defaulted.placement == .left)
    }

    // MARK: - Clause 7: what a person is told when nothing fits

    @Test("a custom reading names every offset it measured")
    func customNamesEveryOffset() {
        // An element inset 32pt inside a 1000-wide container, 128 wide: left 32,
        // right -840, centre -404. `custom` is honest, and on its own useless —
        // the numbers are what tell a caller which container to name instead.
        let reading = HorizontalPlacement.read(element: Rect(x: 32, y: 0, w: 128, h: 20),
                                               container: Self.container, tolerance: 1)
        #expect(reading.isCustom)
        let described = reading.describeOffsets()
        #expect(described.contains("32.0pt"))
        #expect(described.contains("840.0pt"))
        #expect(described.contains("404.0pt"))
        // The edges do not share a sign convention, so the wording is checked
        // rather than assumed: a positive left offset is inside the container and
        // a negative right offset is also inside it.
        #expect(described.contains("left edge is 32.0pt inside"))
        #expect(described.contains("right edge 840.0pt inside"))
        #expect(described.contains("to its left"))
    }

    @Test("an element hanging outside the container reads as outside, not inside")
    func offsetsOutsideTheContainerAreWordedAsSuch() {
        let reading = HorizontalPlacement.read(element: Rect(x: -20, y: 0, w: 1040, h: 20),
                                               container: Self.container, tolerance: 1)
        let described = reading.describeOffsets()
        #expect(described.contains("left edge is 20.0pt outside"))
        #expect(described.contains("right edge 20.0pt past"))
    }
}
