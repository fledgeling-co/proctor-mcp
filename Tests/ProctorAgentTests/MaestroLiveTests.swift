import Foundation
import Testing
import ProctorCore
@testable import ProctorAgent

// PRO-0049 — the live lane, run against a real Maestro and a real simulator.
//
// Skipped unless `PROCTOR_LIVE_MAESTRO=1`, because it needs three things a fleet
// machine may not have: Xcode, `maestro` on PATH, and a booted iOS Simulator.
// A gate that goes red for the absence of Xcode tells you about the machine
// rather than about the code, so this is opt-in and the unguarded suites carry
// every acceptance clause.
//
// It is committed rather than run once and described because it is the only
// thing here that exercises the real seam: a JVM subprocess, Maestro's own
// debug-directory layout, and the fold over records this build did not write.
// Reproduce it with:
//
//   PROCTOR_LIVE_MAESTRO=1 scripts/test.sh --filter liveFlow
//
// Measured on 2026-08-15 (maestro 2.4.0, iPhone 16 Pro, iOS 18.2): two repeats
// of a five-command Settings flow scored deterministic, with the per-command
// status vector identical and `backPressCommand` durations 634 ms apart.

@Suite("PRO-0049 · Maestro live lane")
struct MaestroLiveTests {

    static var enabled: Bool {
        ProcessInfo.processInfo.environment["PROCTOR_LIVE_MAESTRO"] == "1"
    }

    @Test("a real flow runs twice against a real simulator and scores the repeats",
          .enabled(if: MaestroLiveTests.enabled))
    func liveFlowScoresRepeats() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pro0049-live-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let flow = directory.appendingPathComponent("settings.yaml")
        try """
        appId: com.apple.Preferences
        ---
        - launchApp
        - assertVisible: "General"
        - tapOn: "General"
        - back
        """.write(to: flow, atomically: true, encoding: .utf8)

        let session = Session(ax: FakeAX(bundleId: "com.example.fake"), capture: FakeCapture())
        let result = try await session.maestroFlow(path: flow.path, device: nil, runs: 2,
                                                   pixelEvidence: true, timeoutMs: 300_000)
        let object = try #require(result.objectValue)

        // The lane names itself, and the flow is identified by its bytes.
        #expect(object["lane"]?.stringValue == MaestroInvocation.lane)
        #expect(object["flowHash"]?.stringValue?.isEmpty == false)
        #expect(object["verdict"]?.stringValue == MaestroVerdict.flowPassed.rawValue)

        // Maestro's own record, parsed: the two injected commands plus the four
        // from the file.
        let commands = try #require(object["commands"]?.arrayValue)
        #expect(commands.count >= 6)
        let injected = commands.filter { $0["injected"]?.boolValue == true }
        #expect(injected.count == 2)
        let sequences = commands.compactMap { $0["sequenceNumber"]?.doubleValue }
        #expect(sequences == sequences.sorted())

        // The score, and what it is a score of.
        let score = try #require(object["score"]?.objectValue)
        #expect(score["divergenceBasis"]?.stringValue == "repeats")
        #expect(score["divergenceIndexIs"]?.stringValue == "maestro sequenceNumber")
        #expect(score["deterministic"]?.boolValue == true)
        #expect(score["firstDivergence"] == .null)
        #expect(object["runs"]?.doubleValue == 2)
        #expect(object["truncated"]?.boolValue == false)

        // Durations are reported and are not in the score. The live measurement
        // that motivates the split: one unchanged command spread 634 to 88 ms.
        let durations = try #require(object["durations"]?.objectValue)
        #expect(durations.isEmpty == false)

        // Proctor's own channel, beside the score rather than inside it.
        let agreement = try #require(object["endStateAgreement"]?.objectValue)
        #expect(agreement["threshold"]?.doubleValue == IOSPixel.changeThreshold)
        #expect(object["frameCaveat"]?.stringValue?.contains("SCFrameStatus") == true)

        // The gate saw the app the flow declares, and the result says `declared`.
        let declared = try #require(object["declaredApps"]?.arrayValue)
        #expect(declared.contains(.string("com.apple.Preferences")))
        #expect(object["declaredNote"]?.stringValue?.contains("DECLARES") == true)
    }

    @Test("a flow that fails an assertion is a flow failure, not a driver one",
          .enabled(if: MaestroLiveTests.enabled))
    func liveFailingFlowIsAttributedToTheFlow() async throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pro0049-live-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let flow = directory.appendingPathComponent("fail.yaml")
        try """
        appId: com.apple.Preferences
        ---
        - launchApp
        - assertVisible: "ThisTextDoesNotExistAnywhere"
        """.write(to: flow, atomically: true, encoding: .utf8)

        let session = Session(ax: FakeAX(bundleId: "com.example.fake"), capture: FakeCapture())
        let result = try await session.maestroFlow(path: flow.path, device: nil, runs: 1,
                                                   pixelEvidence: false, timeoutMs: 300_000)
        let object = try #require(result.objectValue)

        // Exit 1, exactly as a missing device and an unparseable flow exit 1 —
        // and this one is separated from them by the record it wrote.
        #expect(object["verdict"]?.stringValue == MaestroVerdict.flowFailed.rawValue)
        #expect(object["attributed"]?.boolValue == false)
        let commands = try #require(object["commands"]?.arrayValue)
        let failed = commands.filter { $0["status"]?.stringValue == "FAILED" }
        #expect(failed.count == 1)
        #expect(failed[0]["error"]?.stringValue?.contains("Assertion is false") == true)
        // Maestro attaches its own view tree to a failure: the fourth iOS
        // channel PRO-0048 reserved. Presence travels; the tree never scores.
        #expect(failed[0]["hierarchyAttached"]?.boolValue == true)
        // One run is never a determinism claim.
        #expect(object["score"]?.objectValue?["deterministic"]?.boolValue == false)
    }
}
