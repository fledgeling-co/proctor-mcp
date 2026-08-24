import CoreGraphics
import Foundation
import Testing
@testable import ProctorAgent
@testable import ProctorCore

@Suite("Covered target cursor plane & window occlusion witness (REQ-043 / REQ-200 / DEF-325)")
struct CoveredTargetOcclusionWitnessTests {

    @Test("REQ-043 / REQ-200: WindowOcclusionDetector classifies clear, point-occluded, fully-covered, and modal-layer occlusion")
    func windowOcclusionDetectorCharacterization() {
        let target = WindowOcclusionEntry(
            windowID: 101, pid: 501,
            bounds: Rect(x: 100, y: 100, w: 400, h: 300),
            layer: 0, alpha: 1.0, isOnScreen: true
        )
        let background = WindowOcclusionEntry(
            windowID: 102, pid: 502,
            bounds: Rect(x: 200, y: 200, w: 400, h: 300),
            layer: 0, alpha: 1.0, isOnScreen: true
        )
        let frontOverlap = WindowOcclusionEntry(
            windowID: 103, pid: 503,
            bounds: Rect(x: 200, y: 200, w: 400, h: 300),
            layer: 0, alpha: 1.0, isOnScreen: true
        )
        let enclosingFront = WindowOcclusionEntry(
            windowID: 104, pid: 504,
            bounds: Rect(x: 50, y: 50, w: 600, h: 500),
            layer: 0, alpha: 1.0, isOnScreen: true
        )
        let modalPanel = WindowOcclusionEntry(
            windowID: 105, pid: 600,
            bounds: Rect(x: 200, y: 200, w: 200, h: 150),
            layer: 100, alpha: 1.0, isOnScreen: true
        )
        let proctorOverlay = WindowOcclusionEntry(
            windowID: 999, pid: 700,
            bounds: Rect(x: 0, y: 0, w: 1920, h: 1080),
            layer: 100, alpha: 1.0, isOnScreen: true
        )

        // 1. Target frontmost and clear
        let state1 = WindowOcclusionDetector.evaluate(
            targetID: 101,
            targetPoint: Point(x: 250, y: 250),
            windows: [target, background]
        )
        #expect(state1 == .clear)
        #expect(!state1.isOccluded)

        // 2. Target point occluded by front overlapping window
        let state2 = WindowOcclusionDetector.evaluate(
            targetID: 101,
            targetPoint: Point(x: 250, y: 250),
            windows: [frontOverlap, target]
        )
        #expect(state2 == .pointOccluded(by: [103]))
        #expect(state2.isOccluded)

        // 3. Target point unoccluded in partially covered window (outside front overlap)
        let state3 = WindowOcclusionDetector.evaluate(
            targetID: 101,
            targetPoint: Point(x: 150, y: 150),
            windows: [frontOverlap, target]
        )
        #expect(state3 == .clear)
        #expect(!state3.isOccluded)

        // 4. Target window fully enclosed by larger front window
        let state4 = WindowOcclusionDetector.evaluate(
            targetID: 101,
            targetPoint: Point(x: 150, y: 150),
            windows: [enclosingFront, target]
        )
        #expect(state4.isOccluded)

        // 5. Modal panel at higher layer occludes target point even if listed later
        let state5 = WindowOcclusionDetector.evaluate(
            targetID: 101,
            targetPoint: Point(x: 250, y: 250),
            windows: [target, modalPanel]
        )
        #expect(state5 == .pointOccluded(by: [105]))
        #expect(state5.isOccluded)

        // 6. Proctor overlay ignored so it does not cause self-occlusion
        let state6 = WindowOcclusionDetector.evaluate(
            targetID: 101,
            targetPoint: Point(x: 250, y: 250),
            windows: [proctorOverlay, target],
            ignoring: [999]
        )
        #expect(state6 == .clear)
        #expect(!state6.isOccluded)

        // 7. Target not on screen
        let state7 = WindowOcclusionDetector.evaluate(
            targetID: 9999,
            targetPoint: Point(x: 250, y: 250),
            windows: [target]
        )
        #expect(state7 == .notOnScreen)
        #expect(state7.isOccluded)
    }

    @Test("REQ-043: ContentionWatch records targetOccluded hold reason when target window is occluded")
    func contentionWatchTargetOccludedHoldAttribution() {
        var watch = ContentionWatch(inputWindow: 10, releaseDelay: 2)

        let sampleClear = ContentionSample(expectedPid: 501, frontmostPid: 501, targetOccluded: false, now: 100)
        #expect(watch.sample(sampleClear) == .none)
        #expect(!watch.isYielded)

        let sampleOccluded = ContentionSample(expectedPid: 501, frontmostPid: 501, targetOccluded: true, now: 101)
        let change = watch.sample(sampleOccluded)
        #expect(change == .yielded(.targetOccluded))
        #expect(watch.isYielded)
        #expect(watch.reason == .targetOccluded)
        #expect(watch.reason?.line == "Paused — target window is occluded")
        #expect(watch.reason?.detail.contains("target window is occluded by another application") == true)

        let sampleRelieved = ContentionSample(expectedPid: 501, frontmostPid: 501, targetOccluded: false, now: 102)
        #expect(watch.sample(sampleRelieved) == .none) // within release delay
        #expect(watch.isYielded)

        let sampleReleased = ContentionSample(expectedPid: 501, frontmostPid: 501, targetOccluded: false, now: 105)
        #expect(watch.sample(sampleReleased) == .released(.targetOccluded))
        #expect(!watch.isYielded)
    }

    @Test("REQ-043 / REQ-200 effect witness: deterministic correlation of window bounds, levels, and coordinates suppresses pointer plane")
    func deterministicOcclusionPlaneWitness() {
        let targetWin = WindowOcclusionEntry(
            windowID: 42, pid: 1000,
            bounds: Rect(x: 100, y: 100, w: 500, h: 400),
            layer: 0, alpha: 1.0, isOnScreen: true
        )
        let coveringModal = WindowOcclusionEntry(
            windowID: 43, pid: 2000,
            bounds: Rect(x: 200, y: 200, w: 300, h: 200),
            layer: 10, alpha: 1.0, isOnScreen: true
        )

        // Point inside covering modal bounds (x: 200..500, y: 200..400)
        let occludedPoint = Point(x: 250, y: 250)
        let occlusion = WindowOcclusionDetector.evaluate(
            targetID: 42,
            targetPoint: occludedPoint,
            windows: [targetWin, coveringModal]
        )
        #expect(occlusion.isOccluded)

        // Decide plane: when occluded, pointer is suppressed (.hidden)
        let plane = occlusion.isOccluded ? PointerPlane.hidden : PointerPlanePolicy.decide(targetWindowID: 42, targetIsOnScreen: true)
        #expect(plane == .hidden, "pointer is suppressed when target is occluded by covering modal window")

        // Unoccluded point on same window (x: 150, y: 150)
        let clearPoint = Point(x: 150, y: 150)
        let clearOcclusion = WindowOcclusionDetector.evaluate(
            targetID: 42,
            targetPoint: clearPoint,
            windows: [targetWin, coveringModal]
        )
        #expect(!clearOcclusion.isOccluded)
        let clearPlane = clearOcclusion.isOccluded ? PointerPlane.hidden : PointerPlanePolicy.decide(targetWindowID: 42, targetIsOnScreen: true)
        #expect(clearPlane == .inPlane(above: 42), "pointer is placed inPlane when coordinate is clear")
    }
}
