import Testing
@testable import ProctorCore

// Promises the suite made and did not guard.
//
// Found by arming, not by reading: each behaviour below was broken on purpose in
// the source and the whole existing suite stayed green, which means the campaign
// was carrying a pass for something no assertion could see. The mutation that
// went unnoticed is named on each test, so a later reader can re-run the same
// experiment rather than trust this comment.

@Suite("Capture sizing holds its ceiling")
struct CaptureFitCeilingTests {

    // Unnoticed mutation: `edgeScale` forced to 1.0 in VisionCapture.fit, which
    // stops a frame ever being brought down to its tier's long edge. Every zoom
    // and capture test stayed green, so nothing checked the promise the three
    // tiers exist to keep.

    @Test("a frame past the long edge is brought down to it")
    func longEdgeBinds() {
        let fit = VisionCapture.fit(width: 3456, height: 2234,
                                    maxLongEdge: 768, maxPixels: 10_000_000)
        #expect(fit.applied)
        #expect(max(fit.width, fit.height) == 768)
        #expect(fit.scale < 1.0)
    }

    @Test("the aspect ratio survives the reduction")
    func aspectHolds() {
        let fit = VisionCapture.fit(width: 2000, height: 1000,
                                    maxLongEdge: 500, maxPixels: 10_000_000)
        #expect(fit.width == 500)
        #expect(fit.height == 250)
    }

    @Test("a frame already inside both ceilings is returned untouched")
    func alreadySmallEnough() {
        let fit = VisionCapture.fit(width: 400, height: 300,
                                    maxLongEdge: 768, maxPixels: 10_000_000)
        #expect(!fit.applied)
        #expect(fit.scale == 1)
        #expect(fit.width == 400 && fit.height == 300)
    }

    @Test("each tier's own ceiling is the one that binds")
    func tiersDiffer() {
        let targeting = VisionCapture.fit(width: 4000, height: 3000,
                                          maxLongEdge: VisionCapture.Purpose.targeting.maxLongEdge,
                                          maxPixels: 10_000_000)
        let detail = VisionCapture.fit(width: 4000, height: 3000,
                                       maxLongEdge: VisionCapture.Purpose.detail.maxLongEdge,
                                       maxPixels: 10_000_000)
        #expect(max(targeting.width, targeting.height) == 768)
        #expect(max(detail.width, detail.height) == 1568)
        #expect(targeting.width < detail.width)
    }
}

@Suite("A disagreement between observers is a disagreement")
struct ObserverAgreementTests {

    // Unnoticed mutation: `agrees` returning true whenever the roles differ.
    // The tri-observer check is the thing that catches a ghost node, so an
    // agreement function that cannot disagree is the whole guarantee gone.

    private func identity(role: String, label: String?, frame: Rect? = nil) -> ElementIdentity {
        ElementIdentity(chain: [ElementStep(role: role, label: label)], frame: frame)
    }

    @Test("a different role does not agree")
    func roleMismatch() {
        let mine = identity(role: "AXButton", label: "Stop")
        let theirs = ElementCandidate(index: 1, role: "AXStaticText", label: "Stop",
                                      parentIndex: 0, depth: 1)
        #expect(!ElementMatch.agrees(identity: mine, candidate: theirs))
    }

    @Test("a different label does not agree")
    func labelMismatch() {
        let mine = identity(role: "AXButton", label: "Stop")
        let theirs = ElementCandidate(index: 1, role: "AXButton", label: "Pause",
                                      parentIndex: 0, depth: 1)
        #expect(!ElementMatch.agrees(identity: mine, candidate: theirs))
    }

    @Test("the same role and label agree")
    func matching() {
        let mine = identity(role: "AXButton", label: "Stop")
        let theirs = ElementCandidate(index: 1, role: "AXButton", label: "Stop",
                                      parentIndex: 0, depth: 1)
        #expect(ElementMatch.agrees(identity: mine, candidate: theirs))
    }
}

@Suite("A guest's state word decides whether it is running")
struct GuestRunningStateTests {

    // Unnoticed mutation: `isRunning` answering true for every non-empty state,
    // which reports a stopped or invalid machine as one a run can be sent to.

    @Test("only the words that mean running mean running")
    func runningWords() {
        for word in ["running", "started", "running_up", "up", "RUNNING", "Started"] {
            #expect(GuestPower.isRunning(word), "\(word) means running")
        }
    }

    @Test("everything else does not, including the states a real listing returns")
    func notRunning() {
        // `invalid` is what prlctl returned for the Windows 11 machine on this
        // Mac during the campaign, and `stopped` is the ordinary case.
        for word in ["stopped", "invalid", "suspended", "paused", "", "unknown", "down"] {
            #expect(!GuestPower.isRunning(word), "\(word) does not mean running")
        }
    }
}

@Suite("A delegated machine refuses what it cannot see")
struct DelegatedWitnessTierTests {

    // Unnoticed mutation: `cannotEvaluate` gated on `.native` rather than
    // `.delegated`, which lets a Linux or Windows target answer a tree
    // assertion instead of skipping it with a reason. That inversion is exactly
    // the weak pass the two tiers exist to prevent.

    @Test("a delegated machine cannot evaluate a tree assertion, and says why")
    func delegatedRefusesTreeKinds() {
        for kind in ["exists", "valueEquals", "agree", "enabled"] {
            let reason = WitnessTier.delegated.cannotEvaluate(kind)
            #expect(reason != nil, "\(kind) must be refused on a delegated machine")
            #expect(reason?.contains(kind) == true)
            #expect(reason?.contains("skipped") == true)
        }
    }

    @Test("a delegated machine can still assert on pixels")
    func delegatedKeepsPixels() {
        for kind in WitnessTier.pixelKinds {
            #expect(WitnessTier.delegated.cannotEvaluate(kind) == nil)
        }
    }

    @Test("a native machine evaluates everything")
    func nativeRefusesNothing() {
        for kind in ["exists", "valueEquals", "agree", "regionMatches"] {
            #expect(WitnessTier.native.cannotEvaluate(kind) == nil, "\(kind) on native")
        }
    }
}

@Suite("The simulator lane names simctl")
struct SimctlPathTests {

    // Unnoticed mutation: the located path pointing at a different binary in the
    // same directory. Every iOS wiring test stayed green, so nothing checked
    // that the lane runs the tool it says it runs.

    @Test("the path is simctl under the developer directory")
    func pathShape() {
        let path = SimctlLocator.simctlPath(inDeveloperDirectory: "/Applications/Xcode.app/Contents/Developer")
        #expect(path == "/Applications/Xcode.app/Contents/Developer/usr/bin/simctl")
        #expect(path.hasSuffix("/usr/bin/simctl"))
    }

    @Test("a different developer directory keeps the same tail")
    func differentRoot() {
        #expect(SimctlLocator.simctlPath(inDeveloperDirectory: "/opt/Xcode-beta/Contents/Developer")
                == "/opt/Xcode-beta/Contents/Developer/usr/bin/simctl")
    }
}

@Suite("A frame is evidence only if it is both complete and real")
struct CaptureTrustTests {

    // Unnoticed mutation: `trustworthy` forced to true in the capture engine.
    // The whole acceptance suite stayed green, so the guardrail that stops a
    // stale or empty frame being presented as what an application drew was
    // carried by nothing.

    @Test("a complete frame with area is trustworthy")
    func completeAndReal() {
        #expect(CaptureTrust.trustworthy(frameComplete: true, contentWidth: 640, contentHeight: 592))
    }

    @Test("an incomplete frame is not, whatever its rect says")
    func incomplete() {
        #expect(!CaptureTrust.trustworthy(frameComplete: false, contentWidth: 640, contentHeight: 592))
    }

    @Test("a complete frame with no area is not trustworthy either")
    func completeButEmpty() {
        // The case this pairing exists for, and the one measured on this Mac:
        // ScreenCaptureKit returned SCFrameStatus complete for overlay windows
        // whose frames were entirely empty. Completeness alone would have called
        // those evidence.
        #expect(!CaptureTrust.trustworthy(frameComplete: true, contentWidth: 0, contentHeight: 592))
        #expect(!CaptureTrust.trustworthy(frameComplete: true, contentWidth: 640, contentHeight: 0))
        #expect(!CaptureTrust.trustworthy(frameComplete: true, contentWidth: 0, contentHeight: 0))
    }
}

@Suite("A settle names the signals it actually had")
struct SettleSignalsTests {

    // Unnoticed mutation: the capture signal forced to unavailable. Nothing went
    // red, so "allSignalsQuiet" could be reported over a settle that had stopped
    // watching pixels entirely.

    @Test("each signal appears only when it was available")
    func availability() {
        #expect(SettleSignals.available(capture: true, ax: true, reflector: true)
                == ["capture", "ax", "reflector"])
        #expect(SettleSignals.available(capture: false, ax: true, reflector: false) == ["ax"])
        #expect(SettleSignals.available(capture: true, ax: false, reflector: false) == ["capture"])
        #expect(SettleSignals.available(capture: false, ax: false, reflector: false).isEmpty)
    }

    @Test("quiet cannot be claimed over no signals at all")
    func quietNeedsSomething() {
        #expect(!SettleSignals.canReportQuiet(signals: []))
        #expect(SettleSignals.canReportQuiet(signals: ["ax"]))
    }

    @Test("dropping the pixel signal changes what the verdict is over")
    func pixelSignalMatters() {
        let withPixels = SettleSignals.available(capture: true, ax: true, reflector: false)
        let withoutPixels = SettleSignals.available(capture: false, ax: true, reflector: false)
        #expect(withPixels.contains("capture"))
        #expect(!withoutPixels.contains("capture"))
        #expect(withPixels != withoutPixels)
    }
}

