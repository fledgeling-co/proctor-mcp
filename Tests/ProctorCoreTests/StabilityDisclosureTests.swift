import Foundation
import Testing
@testable import ProctorCore

// PRO-0038 — the shapes half.
//
// What is pinned here is the arithmetic and the wire: that the fold publishes the
// sample count it computed its own numbers from, that a score computed on too few
// samples is not published as a number, that the new fields are absent on a record
// written before they existed, and that a native sweep's encoding is unchanged.
//
// The wiring half — that a real `Session` classifies a step at the moment it ran
// and that an unvouchable hash never reaches the fold — is in
// `StabilityPageContentTests`, because those need a session, a flow and a fake
// application.

@Suite("Stability disclosure shapes")
struct StabilityDisclosureTests {

    private func report(stepBasis: [StabilityStepBasis]? = nil,
                        pageContent: PageContentDisclosure? = nil) -> StabilityReport {
        StabilityReport(flow: "f", runs: 2, stepCount: 1, firstDivergence: nil,
                        stepInstability: [0], deterministic: true, divergenceDetail: nil,
                        notes: [], backend: .native,
                        stepBasis: stepBasis, pageContent: pageContent)
    }

    private func wire(_ value: some Encodable) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - A8 — the fold publishes what it counted, and it counts once

    @Test("the fold reports the sample count its own instability was computed from")
    func theFoldReportsItsOwnSampleCount() {
        // Step 0 in every run, step 1 in two of three, step 2 in one.
        let fold = StabilityScore.fold(perRun: [["a", "b", "c"], ["a", "b"], ["a"]],
                                       stepCount: 3, runs: 3)
        #expect(fold.samples == [3, 2, 1])
        // The same numbers `undersampled` already reported, from the same columns —
        // which is the point: one computation, so the two cannot disagree.
        #expect(fold.undersampled == [1: 2, 2: 1])
        #expect(fold.samples.count == fold.stepInstability.count)
    }

    @Test("a column of one hash scores zero, which is why the count has to travel with it")
    func aSingleSampleScoresZero() {
        let fold = StabilityScore.fold(perRun: [["a", "x"], ["a"]], stepCount: 2, runs: 2)
        // This is the measured trap the disclosure exists for: step 1 was seen once
        // and is indistinguishable, by its number alone, from a step five repeats
        // agreed on.
        #expect(fold.stepInstability[1] == 0)
        #expect(fold.samples[1] == 1)
    }

    @Test("a step measured on fewer than two repeats publishes no instability number")
    func aThinColumnPublishesNoNumber() throws {
        let basis = StabilityStepBasis(step: 1, samples: 1, instability: nil)
        let json = try wire(basis)
        #expect(json["samples"] as? Int == 1)
        #expect(json["instability"] == nil)
    }

    @Test("a step measured on enough repeats publishes the number the fold computed")
    func aFullColumnPublishesTheFoldsNumber() throws {
        let fold = StabilityScore.fold(perRun: [["a"], ["b"]], stepCount: 1, runs: 2)
        let basis = StabilityStepBasis(step: 0, samples: fold.samples[0],
                                       instability: fold.stepInstability[0])
        #expect(basis.samples == 2)
        #expect(basis.instability == fold.stepInstability[0])
        #expect(try wire(basis)["instability"] as? Double == 1.0)
    }

    // MARK: - A5 — one sentence, and it is the one that already existed

    @Test("the disclosure carries proctor_act's own evidence sentence, not a second wording")
    func theDisclosureReusesTheExistingSentence() throws {
        let disclosure = PageContentDisclosure(browser: "Google Chrome",
                                               bundleId: "com.google.Chrome",
                                               steps: [1, 2],
                                               evidence: BrowserTarget.evidence)
        #expect(disclosure.evidence == BrowserTarget.evidence)
        let json = try wire(report(pageContent: disclosure))
        let page = try #require(json["pageContent"] as? [String: Any])
        #expect(page["browser"] as? String == "Google Chrome")
        #expect(page["steps"] as? [Int] == [1, 2])
        #expect(page["evidence"] as? String == BrowserTarget.evidence)
    }

    // MARK: - A9 / A10 — the vocabulary says what it means

    @Test("a step the repeats disagreed about carries both subjects")
    func disagreementCarriesBothSubjects() throws {
        let basis = StabilityStepBasis(step: 0, subjects: [.pageContent, .browserChrome],
                                       samples: 2, instability: 1.0)
        #expect(try wire(basis)["subjects"] as? [String]
                    == ["pageContent", "browserChrome"])
    }

    @Test("unclassified is a value on the wire, never an absence")
    func unclassifiedIsAValue() throws {
        // The distinction A10 exists for: a browser window whose step named no
        // resolvable target says so, rather than looking like a native window.
        let json = try wire(StabilityStepBasis(step: 0, subjects: [.unclassified], samples: 2))
        #expect(json["subjects"] as? [String] == ["unclassified"])
        let native = try wire(StabilityStepBasis(step: 0, subjects: nil, samples: 2))
        #expect(native["subjects"] == nil)
    }

    @Test("a withheld sample is counted on the step, and omitted when there were none")
    func withheldIsCountedAndOtherwiseOmitted() throws {
        #expect(try wire(StabilityStepBasis(step: 0, samples: 1, withheld: 2))["withheld"]
                    as? Int == 2)
        #expect(try wire(StabilityStepBasis(step: 0, samples: 2))["withheld"] == nil)
    }

    // MARK: - A11 — older records decode, and a native sweep is unchanged

    @Test("a report written before these fields existed still decodes")
    func aReportWithoutTheNewFieldsStillDecodes() throws {
        let legacy = """
        {"flow":"f","runs":3,"stepCount":1,"stepInstability":[0.0],"deterministic":true,
         "notes":[],"backend":"native"}
        """
        let decoded = try JSONDecoder().decode(StabilityReport.self,
                                               from: Data(legacy.utf8))
        #expect(decoded.stepBasis == nil)
        #expect(decoded.pageContent == nil)
        #expect(decoded.deterministic)
    }

    @Test("a step written before hashSubject existed still decodes")
    func aStepWithoutASubjectStillDecodes() throws {
        let legacy = """
        {"index":0,"step":{"kind":"press"},"ok":true,"elapsedMs":4}
        """
        #expect(try JSONDecoder().decode(StepResult.self, from: Data(legacy.utf8))
                    .hashSubject == nil)
    }

    @Test("a native sweep encodes none of the new keys")
    func aNativeSweepEncodesNoNewKeys() throws {
        let json = try wire(report())
        #expect(json["stepBasis"] == nil)
        #expect(json["pageContent"] == nil)
        // And the fields it always had are untouched.
        #expect(json["stepInstability"] as? [Double] == [0])
        #expect(json["backend"] as? String == "native")
    }

    @Test("a native step encodes no hashSubject")
    func aNativeStepEncodesNoSubject() throws {
        let step = StepResult(index: 0, step: ActionStep(kind: .press, node: "n1"), ok: true,
                              plane: .accessibility, error: nil, settle: nil,
                              stateHash: "h", diff: nil, elapsedMs: 1)
        #expect(try wire(step)["hashSubject"] == nil)
    }

    @Test("records with the new fields round-trip")
    func recordsRoundTrip() throws {
        let original = report(
            stepBasis: [StabilityStepBasis(step: 0, subjects: [.pageContent], samples: 2,
                                           withheld: 1, instability: 0.5)],
            pageContent: PageContentDisclosure(browser: "Safari", bundleId: "com.apple.Safari",
                                               steps: [0], evidence: BrowserTarget.evidence))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(StabilityReport.self, from: data)
        #expect(decoded.stepBasis == original.stepBasis)
        #expect(decoded.pageContent == original.pageContent)
    }

    // MARK: - A12 — the published description describes what comes back

    @Test("the catalogue says a score can be taken over page content")
    func theCatalogueDescribesPageContent() {
        let description = ToolCatalogue.stability.description
        #expect(description.contains("render tree"))
        #expect(description.contains("stepBasis"))
        #expect(description.contains("pageContent"))
    }
}
