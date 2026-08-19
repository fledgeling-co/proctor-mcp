import Foundation
import Testing
@testable import ProctorCore

// PRO-0065. The harness's own contract, judged without a window.
//
// The load-bearing clause is A6: a property no channel can settle must be
// unreachable from `.matches`, by construction rather than by a caller
// remembering. A property the instrument never saw and a property that matched
// look identical in a passing report, and that is the failure this item exists
// to prevent.

@Suite("Surface fidelity")
struct SurfaceFidelityTests {

    @Test("A3 · every mock surface has an anchor, and every anchor is unique")
    func anchorsComplete() {
        let anchors = SurfaceFidelity.anchors
        #expect(anchors.count == 28)
        #expect(Set(anchors.map(\.identifier)).count == anchors.count, "identifiers collide")
        #expect(Set(anchors.map(\.anchor)).count == anchors.count, "mock anchors collide")
        for a in anchors {
            #expect(a.identifier.hasPrefix("proctor."), "\(a.identifier) is not namespaced")
            #expect(!a.item.isEmpty)
        }
    }

    @Test("A3 · each surface item owns the anchors it converts")
    func anchorsPerItem() {
        // A conversion that forgot a state cannot pass by omission, because the
        // table is the enumeration rather than the build being asked what it has.
        #expect(SurfaceFidelity.anchors(forItem: "PRO-0069").count == 7,
                "the HUD has seven character states")
        #expect(SurfaceFidelity.anchors(forItem: "PRO-0066").count == 4)
        #expect(SurfaceFidelity.anchors(forItem: "PRO-0072").count == 4)
        #expect(SurfaceFidelity.anchors(forItem: "PRO-9999").isEmpty)
    }

    @Test("A6 · a property no channel settles can never report a match")
    func unsettleableIsUnreachable() {
        // The clause the item turns on. A SwiftUI modifier value is not readable
        // from outside the framework — the Reflector's own README says so — and
        // no measurement a caller supplies may turn that into agreement.
        for measured in ["16", "anything at all", ""] {
            let v = SurfaceFidelity.compare(.swiftUIModifier, expected: "16", measured: measured)
            #expect(!v.isMatch, "a swiftUIModifier verdict must never be a match")
            #expect(v == .inconclusive(.swiftUIModifier, .noChannel))
        }
    }

    @Test("A5 · an unread layer property is inconclusive with its reason, not a match")
    func notMaterialised() {
        let v = SurfaceFidelity.compare(.cornerRadius, expected: "8", measured: nil)
        #expect(v == .inconclusive(.cornerRadius, .notMaterialisedInLayer))
        #expect(!v.isMatch)
    }

    @Test("A5 · a release build reports reflectorUnavailable rather than agreement")
    func reflectorAbsent() {
        let v = SurfaceFidelity.compare(.textColour, expected: "#8A6224",
                                        measured: "#8A6224", reflectorRunning: false)
        #expect(v == .inconclusive(.textColour, .reflectorUnavailable))
        #expect(!v.isMatch, "a matching value read through an absent instrument is not a match")
    }

    @Test("A5 · an untrustworthy frame cannot settle rendered appearance")
    func frameNotComplete() {
        let v = SurfaceFidelity.compare(.renderedAppearance, expected: "ref.png",
                                        measured: "ref.png", frameComplete: false)
        #expect(v == .inconclusive(.renderedAppearance, .frameNotComplete))
    }

    @Test("A6 · the channel table answers for every property class")
    func channelTable() {
        for property in FidelityProperty.allCases {
            let channel = FidelityChannel.settling(property)
            #expect(FidelityChannel.allCases.contains(channel))
        }
        #expect(FidelityChannel.settling(.identifier) == .tree)
        #expect(FidelityChannel.settling(.frame) == .tree)
        #expect(FidelityChannel.settling(.cornerRadius) == .layer)
        #expect(FidelityChannel.settling(.renderedAppearance) == .pixels)
        #expect(FidelityChannel.settling(.swiftUIModifier) == .none)
    }

    @Test("tree properties settle on a real comparison, both ways")
    func treeComparison() {
        #expect(SurfaceFidelity.compare(.identifier, expected: "proctor.status.ready",
                                        measured: "proctor.status.ready").isMatch)
        let differs = SurfaceFidelity.compare(.frame, expected: "0,0,640,592",
                                              measured: "0,0,640,600")
        #expect(differs == .differs(.frame, expected: "0,0,640,592", measured: "0,0,640,600"))
    }

    @Test("a report never folds inconclusive results into its pass count")
    func reportKeepsThemApart() {
        let report = SurfaceFidelity.summarise([
            .matches(.identifier),
            .matches(.frame),
            .differs(.label, expected: "Send", measured: "send"),
            .inconclusive(.swiftUIModifier, .noChannel),
            .inconclusive(.cornerRadius, .notMaterialisedInLayer),
        ])
        #expect(report.matched == 2)
        #expect(report.differed == 1)
        #expect(report.inconclusive == 2)
        #expect(!report.isClean)
        // The denominator excludes what could not be measured: a rate over the
        // total would report coverage the run never had.
        #expect(report.measured == 3)
    }
}
