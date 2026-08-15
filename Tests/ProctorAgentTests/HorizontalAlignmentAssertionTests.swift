import Foundation
import Testing
import ProctorCore
@testable import ProctorAgent

// PRO-0042 — the wiring half of the horizontalAlignment assertion.
//
// The classification itself is pure and tested in ProctorCoreTests. What is
// tested here is everything the classifier cannot see: which rectangle the
// assertion measured against, whether a container that was asked for and did not
// resolve is answered anyway, and whether a caller who reads only the `reason`
// string — which is what a model relays — is told enough to act.
//
// What is NOT testable here: that a real AX container reports the frame a real
// layout gave it. That needs a window server and a running application.

@Suite("Horizontal alignment assertion")
struct HorizontalAlignmentAssertionTests {

    private static let bundleId = "com.example.alignment"
    /// The window every assertion falls back to when no container is given.
    private static let windowFrame = Rect(x: 0, y: 0, w: 1000, h: 600)

    private func harness(subject: Rect?,
                         container: Rect? = nil,
                         containerHasFrame: Bool = true) async throws -> Session {
        let ax = FakeAX(bundleId: Self.bundleId)
        ax.nodesByID = [
            "win-1": AXNode(id: "win-1", role: "AXWindow", frame: Self.windowFrame),
            "subject-1": AXNode(id: "subject-1", role: "AXButton", title: "OK", frame: subject),
            "container-1": AXNode(id: "container-1", role: "AXGroup",
                                  frame: containerHasFrame ? container : nil)
        ]
        let session = Session(ax: ax, capture: FakeCapture(),
                              tools: ToolProbes(
                                obscura: ToolProbe(probe: {
                                    ToolPresence(tool: ObscuraTool.binary, available: false)
                                }),
                                browserUse: ToolProbe(probe: {
                                    ToolPresence(tool: BrowserUseTool.binary, available: false)
                                }),
                                environment: [:]))
        await session.setAuditSink(AuditCollector().sink)
        _ = try await session.attachResolved(bundleId: Self.bundleId, pid: nil, name: nil)
        return session
    }

    /// Run one assertion and hand back its rendered entry. Evidence is off: a
    /// failing assertion would otherwise try to capture a window that is not there.
    private func assertOne(_ session: Session,
                           _ spec: [String: JSONValue]) async throws -> [String: JSONValue] {
        var body = spec
        body["kind"] = .string("horizontalAlignment")
        let result = try await session.assertAll(window: "win-1", assertions: [.object(body)],
                                                 captureEvidence: false)
        let entries = result["assertions"]?.arrayValue ?? []
        #expect(entries.count == 1)
        return entries.first?.objectValue ?? [:]
    }

    private func status(_ entry: [String: JSONValue]) -> String? { entry["status"]?.stringValue }
    private func reason(_ entry: [String: JSONValue]) -> String { entry["reason"]?.stringValue ?? "" }
    private func detail(_ entry: [String: JSONValue]) -> [String: JSONValue] {
        entry["detail"]?.objectValue ?? [:]
    }

    // MARK: - The container that was measured against

    @Test("with no container the window frame is used, and the outcome says so")
    func theWindowIsTheContainerWhenNoneIsGiven() async throws {
        let session = try await harness(subject: Rect(x: 0, y: 0, w: 100, h: 20))
        let entry = try await assertOne(session, ["node": .string("subject-1"),
                                                  "expected": .string("left")])
        #expect(status(entry) == "pass")
        #expect(detail(entry)["containerDefaultedToWindow"]?.boolValue == true)
        // The window is 1000 wide, so an element at its left edge is left-aligned
        // in it and nothing else.
        #expect(entry["observed"]?.stringValue == "left")
    }

    @Test("a container that was asked for and has no frame is skipped, not answered")
    func aContainerThatDoesNotResolveIsSkipped() async throws {
        // The subject is left-aligned in the window, so the shipped code's silent
        // fallback would have returned a confident `pass` here — a verdict about a
        // rectangle the caller never asked about.
        let session = try await harness(subject: Rect(x: 0, y: 0, w: 100, h: 20),
                                        containerHasFrame: false)
        let entry = try await assertOne(session, ["node": .string("subject-1"),
                                                  "container": .string("container-1"),
                                                  "expected": .string("left")])
        #expect(status(entry) == "skipped")
        #expect(reason(entry).contains("no readable frame"))
        #expect(detail(entry)["containerDefaultedToWindow"] == nil)
    }

    @Test("a container that resolves is what the placement is measured in")
    func anExplicitContainerIsUsed() async throws {
        // Left-aligned in the window; right-aligned in the container. Only one of
        // those can be the answer, and it is the one that was asked for.
        let session = try await harness(subject: Rect(x: 0, y: 0, w: 100, h: 20),
                                        container: Rect(x: -100, y: 0, w: 200, h: 40))
        let entry = try await assertOne(session, ["node": .string("subject-1"),
                                                  "container": .string("container-1"),
                                                  "expected": .string("right")])
        #expect(status(entry) == "pass")
        #expect(detail(entry)["containerDefaultedToWindow"]?.boolValue == false)
        #expect(detail(entry)["containerNode"]?.stringValue == "container-1")
    }

    // MARK: - The vocabulary at the wire

    @Test("an alias passes and is reported as the physical word")
    func aliasesPassAndReportThePhysicalWord() async throws {
        let session = try await harness(subject: Rect(x: 0, y: 0, w: 100, h: 20))
        for word in ["leading", "LEFT", " left "] {
            let entry = try await assertOne(session, ["node": .string("subject-1"),
                                                      "expected": .string(word)])
            #expect(status(entry) == "pass", "\(word) should pass")
            // Both sides report the physical term, so a pass written as `leading`
            // does not read like a mismatch in the result.
            #expect(entry["observed"]?.stringValue == "left")
            #expect(entry["expected"]?.stringValue == "left")
        }
    }

    @Test("trailing is accepted for the right edge, closing the shipped asymmetry")
    func trailingIsAccepted() async throws {
        let session = try await harness(subject: Rect(x: 900, y: 0, w: 100, h: 20))
        let entry = try await assertOne(session, ["node": .string("subject-1"),
                                                  "expected": .string("trailing")])
        #expect(status(entry) == "pass")
        #expect(entry["observed"]?.stringValue == "right")
    }

    @Test("a word outside the vocabulary is skipped with the list, not failed")
    func anUnknownWordIsSkippedWithTheList() async throws {
        // Failing here would report a caller's typo as a layout defect.
        let session = try await harness(subject: Rect(x: 0, y: 0, w: 100, h: 20))
        let entry = try await assertOne(session, ["node": .string("subject-1"),
                                                  "expected": .string("middle")])
        #expect(status(entry) == "skipped")
        #expect(reason(entry).contains("unknown alignment"))
        #expect(reason(entry).contains("leading"))
        #expect(reason(entry).contains("trailing"))
    }

    @Test("no expectation is skipped, and still reports what it observed")
    func noExpectationIsSkippedButStillObserves() async throws {
        // The shipped code defaulted to leading, so an assertion that claimed
        // nothing could fail a layout nobody had made a claim about.
        let session = try await harness(subject: Rect(x: 900, y: 0, w: 100, h: 20))
        let result = try await session.assertAll(
            window: "win-1",
            assertions: [.object(["kind": .string("horizontalAlignment"),
                                  "node": .string("subject-1")])],
            captureEvidence: false)
        let entry = result["assertions"]?.arrayValue.flatMap(\.first)?.objectValue ?? [:]
        #expect(status(entry) == "skipped")
        #expect(reason(entry).contains("needs `expected`"))
        // It still answers "what is this?", which is the use a probe has for it.
        #expect(entry["observed"]?.stringValue == "right")
        // And a skipped assertion is never a pass.
        #expect(result["ok"]?.boolValue == false)
        #expect(result["skipped"]?.doubleValue == 1)
    }

    // MARK: - What a failure tells a person

    @Test("a custom failure carries every offset and, against the window, the fix")
    func theCustomReasonCarriesTheOffsetsAndTheHint() async throws {
        // Inset 32pt inside the window: not left, not centred, not right.
        let session = try await harness(subject: Rect(x: 32, y: 0, w: 128, h: 20))
        let entry = try await assertOne(session, ["node": .string("subject-1"),
                                                  "expected": .string("left")])
        #expect(status(entry) == "fail")
        #expect(entry["observed"]?.stringValue == "custom")
        let why = reason(entry)
        #expect(why.contains("32.0pt"))
        #expect(why.contains("840.0pt"))
        #expect(why.contains("404.0pt"))
        // The container defaulted, which is the commonest cause of exactly this
        // failure, so the fix is named.
        #expect(why.contains("pass `container`"))
        #expect(detail(entry)["leftOffset"]?.doubleValue == 32)
        #expect(detail(entry)["tolerance"]?.doubleValue == 1)
    }

    @Test("the container hint is absent when a container was supplied")
    func theHintIsConditional() async throws {
        let session = try await harness(subject: Rect(x: 32, y: 0, w: 128, h: 20),
                                        container: Rect(x: 0, y: 0, w: 1000, h: 40))
        let entry = try await assertOne(session, ["node": .string("subject-1"),
                                                  "container": .string("container-1"),
                                                  "expected": .string("left")])
        #expect(status(entry) == "fail")
        // Naming the fix to someone who has already applied it is noise.
        #expect(!reason(entry).contains("pass `container`"))
        #expect(reason(entry).contains("32.0pt"))
    }

    @Test("a wrong-but-known placement says what it is instead, without the container advice")
    func aFailureNamesWhatItIsInstead() async throws {
        let session = try await harness(subject: Rect(x: 0, y: 0, w: 100, h: 20))
        let entry = try await assertOne(session, ["node": .string("subject-1"),
                                                  "expected": .string("right")])
        #expect(status(entry) == "fail")
        #expect(entry["observed"]?.stringValue == "left")
        #expect(reason(entry).contains("aligned left in the container, not right"))
        // The container advice answers "nothing matched, and an inset is why".
        // This placement was measured cleanly and is simply not the one asked
        // for, so the same advice would be about a different problem.
        #expect(!reason(entry).contains("pass `container`"))
    }

    // MARK: - Frames that cannot be measured

    @Test("a frame that cannot be measured horizontally is skipped, not classified")
    func anUnmeasurableSubjectIsSkipped() async throws {
        // Every comparison against a NaN is false, so without a guard this comes
        // back as a confident `custom` fail against a frame nothing could read.
        let session = try await harness(subject: Rect(x: 0, y: 0, w: .nan, h: 20))
        let entry = try await assertOne(session, ["node": .string("subject-1"),
                                                  "expected": .string("left")])
        #expect(status(entry) == "skipped")
        #expect(reason(entry).contains("cannot be measured horizontally"))
    }

    @Test("an unmeasurable container is skipped rather than classified against")
    func anUnmeasurableContainerIsSkipped() async throws {
        let session = try await harness(subject: Rect(x: 0, y: 0, w: 100, h: 20),
                                        container: Rect(x: 0, y: 0, w: -500, h: 40))
        let entry = try await assertOne(session, ["node": .string("subject-1"),
                                                  "container": .string("container-1"),
                                                  "expected": .string("left")])
        #expect(status(entry) == "skipped")
        #expect(reason(entry).contains("container reports a frame"))
    }

    // MARK: - The two container forms, and the window that has none

    @Test("a container given as a rectangle is measured against directly")
    func aContainerCanBeARectangle() async throws {
        // The other half of `referenceRect`'s contract, and the form a caller
        // reaches for when the container is not an AX node at all.
        let session = try await harness(subject: Rect(x: 0, y: 0, w: 100, h: 20))
        let entry = try await assertOne(session, [
            "node": .string("subject-1"),
            "container": .array([.number(-100), .number(0), .number(200), .number(40)]),
            "expected": .string("right")
        ])
        #expect(status(entry) == "pass")
        #expect(detail(entry)["containerDefaultedToWindow"]?.boolValue == false)
        #expect(detail(entry)["containerNode"] == nil)
    }

    @Test("a window with no frame and no container given is skipped")
    func aWindowWithoutAFrameIsSkipped() async throws {
        let ax = FakeAX(bundleId: Self.bundleId)
        ax.nodesByID = [
            "win-1": AXNode(id: "win-1", role: "AXWindow", frame: nil),
            "subject-1": AXNode(id: "subject-1", role: "AXButton",
                                frame: Rect(x: 0, y: 0, w: 100, h: 20))
        ]
        let session = Session(ax: ax, capture: FakeCapture(),
                              tools: ToolProbes(
                                obscura: ToolProbe(probe: {
                                    ToolPresence(tool: ObscuraTool.binary, available: false)
                                }),
                                browserUse: ToolProbe(probe: {
                                    ToolPresence(tool: BrowserUseTool.binary, available: false)
                                }),
                                environment: [:]))
        await session.setAuditSink(AuditCollector().sink)
        _ = try await session.attachResolved(bundleId: Self.bundleId, pid: nil, name: nil)
        let entry = try await assertOne(session, ["node": .string("subject-1"),
                                                  "expected": .string("left")])
        #expect(status(entry) == "skipped")
        #expect(reason(entry).contains("nothing to measure the element against"))
    }

    // MARK: - The tolerance, and what it will not decide

    @Test("the default tolerance is one point, the same as every other geometry kind")
    func theDefaultToleranceIsOnePoint() async throws {
        // Half a point off is the same coordinate; two points off is not. Under
        // the shipped default of 8.0 — tripled to 24.0 for an edge — both passed.
        let near = try await harness(subject: Rect(x: 0.5, y: 0, w: 100, h: 20))
        #expect(status(try await assertOne(near, ["node": .string("subject-1"),
                                                  "expected": .string("left")])) == "pass")

        let far = try await harness(subject: Rect(x: 2, y: 0, w: 100, h: 20))
        let entry = try await assertOne(far, ["node": .string("subject-1"),
                                              "expected": .string("left")])
        #expect(status(entry) == "fail")
        #expect(detail(entry)["tolerance"]?.doubleValue == 1)

        // And a caller who wants slack asks for it.
        let allowed = try await assertOne(far, ["node": .string("subject-1"),
                                                "expected": .string("left"),
                                                "tolerance": .number(4)])
        #expect(status(allowed) == "pass")
    }

    @Test("an element that fills its container is skipped rather than resolved by precedence")
    func aTiedReadingIsSkipped() async throws {
        // All three offsets are zero. The shipped code answered `center` here by
        // precedence, so an element filling its row failed a `right` assertion it
        // did not violate.
        let session = try await harness(subject: Self.windowFrame)
        for word in ["left", "center", "right"] {
            let entry = try await assertOne(session, ["node": .string("subject-1"),
                                                      "expected": .string(word)])
            #expect(status(entry) == "skipped", "\(word) should be undecidable, not wrong")
            #expect(reason(entry).contains("too close in width"))
            #expect(reason(entry).contains("unknown rather than wrong"))
        }
    }

    @Test("a compact container still decides, by nearest fit")
    func aCompactContainerStillDecides() async throws {
        // A 28pt control at the left of a 36pt cell is left-aligned, and a check
        // that skipped every near-miss would make this ordinary layout
        // unassertable — `ok` requires that nothing was skipped.
        let session = try await harness(subject: Rect(x: 100, y: 0, w: 28, h: 20),
                                        container: Rect(x: 100, y: 0, w: 36, h: 20))
        let result = try await session.assertAll(
            window: "win-1",
            assertions: [.object(["kind": .string("horizontalAlignment"),
                                  "node": .string("subject-1"),
                                  "container": .string("container-1"),
                                  "expected": .string("left"),
                                  "tolerance": .number(8)])],
            captureEvidence: false)
        let entry = result["assertions"]?.arrayValue.flatMap(\.first)?.objectValue ?? [:]
        #expect(status(entry) == "pass")
        #expect(result["ok"]?.boolValue == true)
    }

    // MARK: - The pre-existing skips, held

    @Test("a subject exposing no frame is skipped")
    func aSubjectWithNoFrameIsSkipped() async throws {
        let session = try await harness(subject: nil)
        let entry = try await assertOne(session, ["node": .string("subject-1"),
                                                  "expected": .string("left")])
        #expect(status(entry) == "skipped")
        #expect(reason(entry).contains("exposes no frame"))
    }
}
