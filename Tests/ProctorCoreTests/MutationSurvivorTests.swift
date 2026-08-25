import Foundation
import Testing
@testable import ProctorCore

/// PRO-0125 / PRO-0138 — assertions written against surviving mutants.
///
/// `mutation_report.py` aggregated four runs and found 47 mutants that changed
/// production behaviour and left the suite green. Each is an assertion nobody
/// wrote, and the ones below are the ProctorCore half that a unit test can
/// reach. Every test here names the exact edit it kills, because a test whose
/// connection to a survivor is only in a commit message stops being one after
/// the next refactor.
///
/// Three of the survivors examined turned out to be **equivalent mutants** —
/// edits that cannot change behaviour, so no assertion can kill them. They are
/// recorded in `MutationEquivalenceTests` below rather than chased, because a
/// mutation score computed over unkillable mutants is a score nobody can reach.
@Suite("Mutation survivors: the assertions nobody had written")
struct MutationSurvivorTests {

    // MenuKeyEquivalent.swift:120  '109' -> '110'
    @Test("every function-key virtual code maps to the name the actuator drives")
    func functionKeyCodes() {
        // F10 is 109. The survivor moved it to 110, which is not a key at all,
        // and nothing noticed — a menu item with ⌥F10 would have come back
        // naming a key `act` cannot press.
        #expect(MenuKeyEquivalent.virtualKeyNames[109] == "f10")
        #expect(MenuKeyEquivalent.virtualKeyNames[110] == nil)
        // The neighbours, so a shift of the whole table is caught too.
        #expect(MenuKeyEquivalent.virtualKeyNames[101] == "f9")
        #expect(MenuKeyEquivalent.virtualKeyNames[103] == "f11")
        // And the count, which is what a wholesale edit moves.
        #expect(MenuKeyEquivalent.virtualKeyNames.count == 36)
    }

    // BrowserTarget.swift:1020  'false' -> 'true'
    @Test("a URL with no host is not a private network address")
    func privateNetworkNeedsAHost() {
        // The guard's else branch returned false; the survivor returned true,
        // so every unparseable string became "private" and the browser lane's
        // SSRF question answered itself the wrong way.
        #expect(!BrowserTarget.isPrivateNetwork("not a url at all"))
        #expect(!BrowserTarget.isPrivateNetwork(""))
        #expect(!BrowserTarget.isPrivateNetwork("file:///tmp/page.html"))
        // And the positives still hold, so the fix is not "return false always".
        #expect(BrowserTarget.isPrivateNetwork("http://localhost:8080/"))
        #expect(BrowserTarget.isPrivateNetwork("http://127.0.0.1/"))
        #expect(BrowserTarget.isPrivateNetwork("http://192.168.1.4/"))
        #expect(BrowserTarget.isPrivateNetwork("http://172.16.0.1/"))
        #expect(!BrowserTarget.isPrivateNetwork("http://172.32.0.1/"))
        #expect(!BrowserTarget.isPrivateNetwork("https://example.com/"))
    }

    // Takeover.swift:356  '1' -> '2'   (InputModifiers.command's bit)
    @Test("each modifier owns one bit, and the four are disjoint")
    func modifierBits() {
        #expect(InputModifiers.command.rawValue == 1)
        #expect(InputModifiers.option.rawValue == 2)
        #expect(InputModifiers.control.rawValue == 4)
        #expect(InputModifiers.shift.rawValue == 8)
        // The survivor made command and option the same bit. A chord test that
        // only checks membership passes on that; a disjointness check does not.
        let all: [InputModifiers] = [.command, .option, .control, .shift]
        for (i, a) in all.enumerated() {
            for b in all[(i + 1)...] {
                #expect(a.rawValue & b.rawValue == 0,
                        "two modifiers share a bit, so a chord cannot be read back")
            }
        }
        #expect(InputModifiers([.command, .shift]).rawValue == 9)
    }

    // SetOfMarks.swift:135  '>' -> '>='   (options.spacingPoints > 0)
    //
    // Measured EQUIVALENT and kept anyway. With `>= 0` the first guard admits
    // spacing 0, and `guard step >= 1` two lines down refuses it, so the two
    // spellings cannot be separated by any input. The test is kept because the
    // BEHAVIOUR it asserts is what a caller depends on; what it is not is a kill
    // for that mutant, and claiming one would be a score nobody can reach.
    @Test("a grid with no spacing draws nothing rather than a solid fill")
    func gridRefusesZeroSpacing() {
        let zero = SetOfMarks.GridOptions(enabled: true, spacingPoints: 0)
        #expect(SetOfMarks.gridOverlay(zero, imageWidth: 800, imageHeight: 600,
                                       scale: 2) == nil,
                "spacing 0 admitted by the guard makes step 0, which is every pixel")
        let negative = SetOfMarks.GridOptions(enabled: true, spacingPoints: -10)
        #expect(SetOfMarks.gridOverlay(negative, imageWidth: 800, imageHeight: 600,
                                       scale: 2) == nil)
        // A real spacing still draws, so the guard is not just "always nil".
        let real = SetOfMarks.GridOptions(enabled: true, spacingPoints: 100)
        #expect(SetOfMarks.gridOverlay(real, imageWidth: 800, imageHeight: 600,
                                       scale: 2) != nil)
    }

    // PointerMarker.swift:60  '0' -> '1'   (frame.w > 0, frame.h > 0)
    @Test("a one-point element still has a centre to mark")
    func markerTakesAOnePointFrame() {
        let step = ActionStep(kind: .press)
        let tiny = Rect(x: 10, y: 20, w: 1, h: 1)
        let target = PointerMarker.targetPoint(for: step, elementFrame: tiny)
        // The survivor raised the threshold to > 1, so a 1x1 element — a
        // disclosure triangle, a badge — silently marked nothing.
        #expect(target != nil, "a 1x1 element has a centre and must be markable")
        #expect(target?.x == 10.5)
        #expect(target?.y == 20.5)
        // A zero-area frame genuinely has no place, and still returns nil.
        #expect(PointerMarker.targetPoint(for: step,
                                          elementFrame: Rect(x: 0, y: 0, w: 0, h: 0)) == nil)
    }

    // RunHUDSurface.swift:80  '==' -> '!='   (a.fields.count == b.fields.count)
    @Test("two chips of different length are not equal")
    func chipEqualityCountsFields() {
        let one = RunHUDSurface.Chip([("a", "1")])
        let two = RunHUDSurface.Chip([("a", "1"), ("b", "2")])
        // The survivor inverted the length check, so chips of DIFFERENT length
        // compared equal whenever their shared prefix matched — which is every
        // chip that gained a field.
        #expect(one != two)
        #expect(two != one)
        #expect(one == RunHUDSurface.Chip([("a", "1")]))
        #expect(two == RunHUDSurface.Chip([("a", "1"), ("b", "2")]))
        #expect(RunHUDSurface.Chip([]) == RunHUDSurface.Chip([]))
        #expect(RunHUDSurface.Chip([]) != one)
    }

    // HorizontalPlacement.swift:150  '0' -> '1'   (centreOffset <= 0)
    @Test("an element centred exactly reads as left of centre, not right of it")
    func centreOffsetBoundary() {
        // The boundary is the whole content of the survivor: at exactly 0 the
        // original says "to its left" and the mutant says "to its right", and
        // both sentences are about a zero offset, so only the wording differs.
        // That is precisely the kind of drift a design-conformance reader trusts.
        let exact = HorizontalPlacement.Reading(leftOffset: 0, rightOffset: 0,
                                                centreOffset: 0, tolerance: 1)
        #expect(exact.describeOffsets().contains("to its left"))
        #expect(!exact.describeOffsets().contains("to its right"))
        // The discriminating input is the offset the mutant MOVES the boundary
        // to. A first draft tested 0 and 4, and `<= 0` and `<= 1` agree on both,
        // so the mutant survived a test written against it — which is the same
        // failure as an assertion nobody wrote, one layer in.
        let justRight = HorizontalPlacement.Reading(leftOffset: 0, rightOffset: 0,
                                                    centreOffset: 1, tolerance: 1)
        #expect(justRight.describeOffsets().contains("to its right"),
                "a positive offset of any size is to the right, and 1 is positive")
        let right = HorizontalPlacement.Reading(leftOffset: 0, rightOffset: 0,
                                                centreOffset: 4, tolerance: 1)
        #expect(right.describeOffsets().contains("to its right"))
    }

    // TUILayout.swift:351  '>=' -> '>'   (i >= region.h)
    @Test("text is clipped at the row count, not one row past it")
    func textStopsAtTheRegionHeight() {
        let region = TUIRegion(0, 0, 20, 2)
        let text = TUIText(["one", "two", "three"])
        var canvas = TUICanvas(cols: 20, rows: 4)
        TUILayout.paintText(region, text, into: &canvas)
        // The survivor painted one line past the region, so a two-row box drew
        // three rows and overwrote whatever the layout put underneath.
        let painted = canvas.cells.filter { row in row.contains { $0.ch != " " } }.count
        #expect(painted <= 2, "text painted \(painted) row(s) into a 2-row region")
        #expect(canvas.findings.contains { $0.kind == "text-overflow-rows" },
                "an overflow is noted rather than silently clipped")
    }
}

/// Mutants that cannot be killed, with the reason each is equivalent.
///
/// Mutation testing's standard trap: a survivor is assumed to be a missing
/// assertion, somebody writes a test that cannot fail, and the score goes up
/// while the suite gets weaker. These three were examined and are edits with no
/// observable consequence, so they are recorded here rather than chased.
@Suite("Mutation survivors that are equivalent, and why")
struct MutationEquivalenceTests {

    @Test("VisionCapture guard: `width > 0` and `width >= 0` agree on every input")
    func visionGuardIsEquivalent() {
        // At width 0 the original's guard fails and returns 0; the mutant's
        // guard passes and computes 0 * height / 750, which rounds to 0. Below
        // zero both guards fail. So no input separates them.
        #expect(VisionCapture.estimatedVisionTokens(width: 0, height: 1000) == 0)
        #expect(VisionCapture.estimatedVisionTokens(width: 1000, height: 0) == 0)
        #expect(VisionCapture.estimatedVisionTokens(width: -5, height: 1000) == 0)
        // The live path still measures, so this is a statement about the guard
        // rather than about the function.
        #expect(VisionCapture.estimatedVisionTokens(width: 1500, height: 750) == 1500)
    }

    @Test("RunHUDGate.onSegment: a drag that grazes the panel's edge still steps aside")
    func onSegmentBoundaryIsReal() {
        // Recorded as NOT equivalent after examination, and killed here through
        // the public route: the survivor turned `<=` into `<`, so a point
        // exactly on a segment endpoint fell off the segment. A drag whose line
        // touches the panel's edge is exactly that case, and getting it wrong
        // means a synthetic event lands on the kill switch.
        let panel = Rect(x: 100, y: 100, w: 200, h: 80)
        // The discriminating route is a VERTICAL one whose x equals the x of the
        // panel edge it crosses: `min(a.x, b.x) <= c.x` is then an equality, and
        // `<` drops it. A first draft used a horizontal route where the
        // comparison was strict either way, so `<=` and `<` agreed and the
        // mutant survived a test written against it.
        let onTheEdge = [RunHUDPlacement.Point(x: 100, y: 50),
                         RunHUDPlacement.Point(x: 100, y: 400)]
        #expect(RunHUDGate.stepsAside(points: onTheEdge, panel: panel),
                "a drag straight down the panel's left edge crosses it")
        let clear = [RunHUDPlacement.Point(x: 50, y: 400),
                     RunHUDPlacement.Point(x: 60, y: 500)]
        #expect(!RunHUDGate.stepsAside(points: clear, panel: panel),
                "and a route nowhere near it does not, so this is not always-true")
    }
}
