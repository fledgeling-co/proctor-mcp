import Foundation
import Testing
import ProctorCore
@testable import ProctorAgent

// PRO-0057 — the witness tier, and what it refuses.
//
// The one concept that stops a Linux target passing itself off as a macOS one.
// Proctor's instruments are macOS APIs: `SCFrameStatus` on a capture, an
// `AXUIElement` tree, and the tri-observer check that reports where the tree,
// the geometry and the pixels disagree. In a guest running a full Proctor those
// all exist. On a delegated lane none of them do, and what arrives instead is a
// screenshot with no completeness signal and whatever the driver says it did.
//
// The rule under test is the skill's own, applied to a whole substrate rather
// than to one call: an assertion that could not be evaluated is not an assertion
// that passed. So a tier does not scale a score and does not soften a verdict.
// It decides what can be asked at all, and what cannot is reported **skipped
// with a reason**.
@Suite("PRO-0057 · what a delegated machine cannot be asked")
struct WitnessTierTests {

    private static let target = "com.example.target"

    private func session(tier: WitnessTier) async throws -> (Session, FakeAX) {
        let ax = FakeAX(bundleId: Self.target)
        let session = Session(ax: ax, capture: FakeCapture(), secureInputProbe: { false })
        await session.setAuditSink(AuditCollector().sink)
        await session.setDrawsHUD(false)
        await session.setMachine(Machine(kind: .guest, name: "ubuntu-1",
                                         provider: "cua", platform: .linux, tier: tier))
        _ = try await session.attachResolved(bundleId: Self.target, pid: nil, name: nil)
        return (session, ax)
    }

    // MARK: - The gate is a list of what survives, not a list of what is refused

    @Test("a native machine refuses nothing")
    func nativeRefusesNothing() {
        for kind in ["exists", "absent", "valueEquals", "enabled", "focused", "hasLabel",
                     "frameEquals", "containedIn", "alignedWith", "horizontalAlignment",
                     "minHitSize", "contrast", "focusOrder", "regionMatches", "agree"] {
            #expect(WitnessTier.native.cannotEvaluate(kind) == nil,
                    "native should evaluate \(kind)")
        }
    }

    @Test("a delegated machine refuses every kind that reads the tree")
    func delegatedRefusesTreeKinds() {
        for kind in ["exists", "absent", "valueEquals", "enabled", "focused", "hasLabel",
                     "frameEquals", "containedIn", "alignedWith", "horizontalAlignment",
                     "minHitSize", "contrast", "focusOrder", "agree"] {
            #expect(WitnessTier.delegated.cannotEvaluate(kind) != nil,
                    "delegated should refuse \(kind)")
        }
    }

    @Test("a kind nobody has classified is refused rather than quietly permitted")
    func anUnknownKindIsRefused() {
        // The gate is written as a list of what SURVIVES, and this is the reason.
        // A kind added later and forgotten is refused by that shape and permitted
        // by the opposite one. A refusal on a kind that would have worked is
        // visible and complained about; a permission on one that cannot be
        // evaluated is a pass nobody measured.
        #expect(WitnessTier.delegated.cannotEvaluate("somethingAddedNextYear") != nil)
    }

    @Test("the one pixel kind survives, because pixels are what a delegated lane has")
    func pixelKindSurvives() {
        #expect(WitnessTier.delegated.cannotEvaluate("regionMatches") == nil)
        #expect(WitnessTier.pixelKinds == ["regionMatches"])
    }

    @Test("the refusal says why, and points somewhere")
    func theRefusalIsActionable() {
        let why = WitnessTier.delegated.cannotEvaluate("agree")
        #expect(why?.contains("agree") == true)
        #expect(why?.contains("accessibility tree") == true)
        // A refusal with no way forward is a dead end rather than a finding.
        #expect(why?.contains("regionMatches") == true)
    }

    // MARK: - Through a real session

    @Test("a delegated run reports skipped with a reason, never passed")
    func aDelegatedAssertionIsSkipped() async throws {
        let (session, ax) = try await self.session(tier: .delegated)
        let result = try await session.assertAll(
            window: ax.window.id,
            assertions: [.object(["kind": .string("exists"),
                                  "find": .object(["role": .string("AXButton")])])],
            captureEvidence: false)
        let first = result["assertions"]?.arrayValue?.first?.objectValue
        #expect(first?["status"]?.stringValue == "skipped")
        #expect(first?["reason"]?.stringValue?.isEmpty == false)
        // The distinction the whole item exists for.
        #expect(first?["status"]?.stringValue != "pass")
    }

    @Test("the same assertion on a native machine is actually evaluated")
    func aNativeAssertionRuns() async throws {
        let (session, ax) = try await self.session(tier: .native)
        let result = try await session.assertAll(
            window: ax.window.id,
            assertions: [.object(["kind": .string("exists"),
                                  "find": .object(["role": .string("AXButton")])])],
            captureEvidence: false)
        let status = result["assertions"]?.arrayValue?.first?.objectValue?["status"]?.stringValue
        #expect(status == "pass" || status == "fail", "got \(status ?? "nil")")
        #expect(status != "skipped")
    }

    @Test("a skipped assertion does not count as an overall pass")
    func skippedDoesNotMakeTheRunGreen() async throws {
        let (session, ax) = try await self.session(tier: .delegated)
        let result = try await session.assertAll(
            window: ax.window.id,
            assertions: [.object(["kind": .string("exists"),
                                  "find": .object(["role": .string("AXButton")])])],
            captureEvidence: false)
        // `ok` is the field a caller branches on, and a run whose only assertion
        // could not be evaluated has established nothing.
        #expect(result["ok"]?.boolValue != true)
    }

    // MARK: - The pixel caveat

    @Test("a delegated pixel comparison carries what it is worth")
    func thePixelCaveatIsStated() {
        let caveat = WitnessTier.delegated.pixelCaveat
        #expect(caveat != nil)
        #expect(caveat?.contains("SCFrameStatus") == true)
        #expect(caveat?.contains("completeness") == true)
    }

    @Test("a native pixel comparison has nothing to qualify")
    func nativeHasNoPixelCaveat() {
        #expect(WitnessTier.native.pixelCaveat == nil)
    }

    // MARK: - The type

    @Test("tier has no default, so a machine cannot claim observation it does not have")
    func tierIsAlwaysNamed() {
        // Not a behaviour test: this is a compile-time contract, and the reason
        // every construction site in the suite names its tier. Recorded here so
        // that adding a default later fails a test rather than passing silently
        // into a Linux guest describing itself as native.
        #expect(Machine.host.tier == .native)
        let linux = Machine(kind: .guest, name: "u", platform: .linux, tier: .delegated)
        #expect(linux.tier == .delegated)
    }

    @Test("tier survives a round trip, since it goes out on the wire")
    func tierRoundTrips() throws {
        let m = Machine(kind: .guest, name: "u", provider: "cua",
                        platform: .linux, tier: .delegated)
        let decoded = try JSONDecoder().decode(Machine.self,
                                               from: try JSONEncoder().encode(m))
        #expect(decoded == m)
        #expect(decoded.tier == .delegated)
    }
}
