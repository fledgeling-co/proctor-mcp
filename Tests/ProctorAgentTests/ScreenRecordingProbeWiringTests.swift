import Foundation
import Testing
import ProctorCore
@testable import ProctorAgent

// PRO-0041 — the wiring half: the bound around a platform call that may never
// answer, and what `proctor_doctor` says about it.
//
// The platform call is a closure here, so the case this whole item exists for —
// a call that neither answers nor throws — is a test rather than a story. Before
// this change the same case hung `swift test` until its deadline; the suites that
// call `doctor` were skipped at every merge for two waves because of it.
@Suite("Screen Recording probe")
struct ScreenRecordingProbeWiringTests {

    /// A platform call that never returns. Parked on a continuation nobody
    /// resumes, which is exactly what was measured happening to
    /// `SCShareableContent` inside a test host.
    private static let neverAnswers: @Sendable () async -> GrantState = {
        await withCheckedContinuation { (_: CheckedContinuation<GrantState, Never>) in }
    }

    private func probe(bound: Double = 0.2,
                       platform: @escaping @Sendable () async -> GrantState)
    -> ScreenRecordingProbe {
        ScreenRecordingProbe(bound: bound, platform: platform)
    }

    // MARK: A1 — the probe is bounded

    @Test("a platform call that never answers returns unconfirmed within the bound")
    func aParkedCallDoesNotHang() async {
        let started = Date()
        let probe = probe(bound: 0.2, platform: Self.neverAnswers)
        let state = await probe.state()
        let elapsed = Date().timeIntervalSince(started)

        #expect(state == .unconfirmed)
        // The bound is a bound, not a hope. Generous headroom so this does not
        // flake on a loaded machine, and still nowhere near the "forever" it
        // replaced.
        #expect(elapsed < 5.0)
    }

    @Test("an answering platform call is reported as it answered")
    func definiteAnswersPassThrough() async {
        for answer in [GrantState.granted, .denied] {
            let state = await probe(platform: { answer }).state()
            #expect(state == answer)
        }
    }

    @Test("a throwing probe reads as denied, which is what a denial looks like")
    func aThrowIsADenial() async {
        // The real closure turns the ScreenCaptureKit throw into `.denied`; this
        // pins that a definite negative is still definite and is not swept into
        // the new third state.
        let state = await probe(platform: { .denied }).state()
        #expect(state == .denied)
    }

    // MARK: A6 / A7 — caching, coalescing and recovery through the real probe

    @Test("a definite answer costs one platform call however often it is asked")
    func definiteAnswersAreProbedOnce() async {
        let calls = Counter()
        let probe = probe(platform: { calls.bump(); return .granted })
        for _ in 0..<5 { _ = await probe.state() }
        #expect(calls.value == 1)
    }

    @Test("an unconfirmed answer is re-probed rather than remembered")
    func unconfirmedIsNotRemembered() async {
        // A clock the test drives, so the backoff can be waited out in a
        // microsecond instead of two seconds. The schedule itself is pinned in
        // GrantProbeTests; what is pinned here is that the platform really does
        // get asked a second time.
        let clock = TestClock()
        let calls = Counter()
        let probe = ScreenRecordingProbe(
            bound: 0.1,
            keeper: GrantProbeKeeper(bound: 0.1),
            now: { clock.now },
            platform: { calls.bump(); return await Self.neverAnswers() })

        #expect(await probe.state() == .unconfirmed)
        // Immediately after, the backoff is holding — no second probe.
        #expect(await probe.state() == .unconfirmed)
        #expect(calls.value == 1)

        clock.advance(GrantProbe.backoff[0] + 1)
        #expect(await probe.state() == .unconfirmed)
        // Asked again rather than answered from a remembered timeout. A cached
        // non-answer would leave the agent saying this for the rest of its life.
        #expect(calls.value == 2)
    }

    @Test("a late answer is picked up by the next call")
    func aLateAnswerIsPickedUp() async {
        let gate = Gate()
        let calls = Counter()
        let probe = ScreenRecordingProbe(
            bound: 0.15,
            keeper: GrantProbeKeeper(bound: 0.15),
            now: { 0 },
            platform: { calls.bump(); await gate.wait(); return .granted })

        // First call gives up before the platform answers.
        #expect(await probe.state() == .unconfirmed)
        // The abandoned probe finally comes back.
        gate.open()
        try? await Task.sleep(nanoseconds: 300_000_000)
        // And the answer is there, without another platform call — a definite
        // answer is a per-process constant, so one arriving late is exactly as
        // valid as one arriving on time.
        #expect(await probe.state() == .granted)
        #expect(calls.value == 1)
    }

    // MARK: A2 / A3 — what the report says

    private func doctorReport(_ state: GrantState) async -> DoctorReport {
        let session = Session(ax: FakeAX(bundleId: "com.apple.TextEdit"),
                              capture: FakeCapture(),
                              screenRecordingProbe: ScreenRecordingProbe(platform: { state }))
        return await session.doctor(verbose: false)
    }

    private func screenRecording(_ report: DoctorReport) -> DoctorReport.Grant {
        report.grants.first { $0.name == "Screen Recording" }!
    }

    @Test("an unconfirmed grant is reported as unconfirmed, not as a denial")
    func unconfirmedIsItsOwnState() async {
        let grant = screenRecording(await doctorReport(.unconfirmed))
        #expect(grant.resolvedState == .unconfirmed)
        #expect(grant.state == "unconfirmed")
        // Fail-closed through the boolean, so nothing that reads only the boolean
        // over-claims.
        #expect(grant.granted == false)
    }

    @Test("the two definite states still report as they always did")
    func definiteStatesAreUnchanged() async {
        let granted = screenRecording(await doctorReport(.granted))
        #expect(granted.granted)
        #expect(granted.resolvedState == .granted)

        let denied = screenRecording(await doctorReport(.denied))
        #expect(!denied.granted)
        #expect(denied.resolvedState == .denied)
    }

    @Test("ready is false while a required grant is unconfirmed")
    func unconfirmedIsNotReady() async {
        // `ready` means established-good, and an unanswered probe has established
        // nothing.
        #expect(await doctorReport(.unconfirmed).ready == false)
        #expect(await doctorReport(.denied).ready == false)
    }

    @Test("the remedy for an unconfirmed grant does not send anybody to System Settings")
    func theRemedyIsNotALie() async {
        let unconfirmed = screenRecording(await doctorReport(.unconfirmed))
        let denied = screenRecording(await doctorReport(.denied))

        // The whole defect in one assertion: telling somebody to grant a
        // permission they may already have granted.
        #expect(!unconfirmed.howToFix.contains("System Settings ▸"))
        #expect(denied.howToFix.contains("System Settings ▸"))

        // And it says what actually happened, including the bound — in the
        // report, not only in a comment.
        #expect(unconfirmed.howToFix.contains("did not answer"))
        #expect(unconfirmed.howToFix.contains("1.5s"))
        #expect(unconfirmed.howToFix.contains("proctor_doctor"))
    }

    @Test("the blocker names a non-answer as a non-answer")
    func theBlockerDoesNotClaimADenial() async {
        let unconfirmed = await doctorReport(.unconfirmed)
        let denied = await doctorReport(.denied)

        let unconfirmedBlocker = unconfirmed.blockers.first { $0.contains("Screen Recording") }
        let deniedBlocker = denied.blockers.first { $0.contains("Screen Recording") }

        #expect(unconfirmedBlocker?.contains("could not be confirmed") == true)
        #expect(unconfirmedBlocker?.contains("is not granted") == false)
        #expect(deniedBlocker?.contains("is not granted") == true)
    }

    @Test("the doctor schema tells a reader what the third state means")
    func theSchemaExplainsTheThirdState() {
        let schema = ToolCatalogue.outputSchema(for: "proctor_doctor")
        let description = schema.objectValue?["description"]?.stringValue ?? ""
        #expect(description.contains("unconfirmed"))
        #expect(description.contains("1.5s"))
    }

    // MARK: - Helpers

    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        func bump() { lock.lock(); count += 1; lock.unlock() }
        var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    }

    /// A clock the test drives, so a backoff measured in seconds can be waited
    /// out without the test waiting for it.
    private final class TestClock: @unchecked Sendable {
        private let lock = NSLock()
        private var t = 0.0
        var now: Double { lock.lock(); defer { lock.unlock() }; return t }
        func advance(_ seconds: Double) { lock.lock(); t += seconds; lock.unlock() }
    }

    /// A latch a test can hold a "platform call" behind and then release.
    private final class Gate: @unchecked Sendable {
        private let semaphore = DispatchSemaphore(value: 0)
        func open() { semaphore.signal() }
        func wait() async {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                DispatchQueue.global().async {
                    self.semaphore.wait()
                    continuation.resume()
                }
            }
        }
    }
}
