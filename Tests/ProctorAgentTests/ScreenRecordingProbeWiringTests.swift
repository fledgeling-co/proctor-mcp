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

    @Test("a platform call that never answers is ended by the bound, on the bound the product ships")
    func aParkedCallIsEndedByTheBound() async {
        // This case used to end `#expect(elapsed < 5.0)` against a stopwatch, and
        // the stopwatch was measuring the machine: six recorded failures in one wave
        // — 5.6s, 6.1s, 6.58s, 8.13s, 10.25s and 14.73s — against a product that
        // answered correctly every time, and 1.8s when the same case ran alone.
        //
        // The claim worth making is the mechanism, not the duration: a call that
        // never answers is ended by the bound arm rather than by luck. So the bound
        // arm is told to the probe, and the test watches it fire. `GrantProbe.bound`
        // is the product's own constant and nothing here writes it, so this also
        // catches a probe that bounds itself by something other than its bound.
        let asked = BoundRequest()
        let probe = ScreenRecordingProbe(timer: { seconds in asked.record(seconds) },
                                         platform: Self.neverAnswers)

        let state = await probe.state()

        #expect(state == .unconfirmed)
        #expect(asked.seconds == GrantProbe.bound)
    }

    @Test("an answer inside the bound wins even when the bound never fires")
    func anAnswerBeatsABoundThatNeverFires() async {
        // The other half of the race, pinned the same way round. A timer that never
        // returns is what a healthy call looks like from the bound's side, and the
        // answer must still come back — a probe that waited for its timer would make
        // every doctor poll cost the full 1.5s on a Mac where the grant is fine.
        let probe = ScreenRecordingProbe(timer: { _ in await Self.never() },
                                         platform: { .granted })
        #expect(await probe.state() == .granted)
    }

    @Test("the probe the agent actually runs is bounded by the constant the report quotes")
    func theLiveProbeCarriesTheRealBound() {
        // The seams above are only worth anything if production takes the real one.
        #expect(ScreenRecordingProbe.live.bound == GrantProbe.bound)
        #expect(GrantProbe.bound == 1.5)
    }

    @Test("the real timer still ends a parked call, however long the machine takes about it")
    func theDefaultTimerStillEndsAParkedCall() async {
        // The default timer, unsubstituted, against the call this whole item exists
        // for. No clock is read: what is asserted is that it comes back at all,
        // which is the difference from the hang it replaced. On a loaded machine
        // this takes longer and still passes, which is the point.
        #expect(await probe(bound: 0.2, platform: Self.neverAnswers).state() == .unconfirmed)
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
        let keeper = GrantProbeKeeper(bound: 0.15)
        let probe = ScreenRecordingProbe(
            bound: 0.15,
            keeper: keeper,
            now: { 0 },
            platform: { calls.bump(); await gate.wait(); return .granted })

        // First call gives up before the platform answers.
        #expect(await probe.state() == .unconfirmed)
        // The abandoned probe finally comes back.
        gate.open()
        for _ in 0..<100 {
            if keeper.cachedDefinite() != nil { break }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
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

    /// What the bound arm was asked to wait for. One `Double`, recorded once, so a
    /// test can ask whether the bound fired and on what number instead of timing it.
    private final class BoundRequest: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Double?
        func record(_ seconds: Double) { lock.lock(); value = value ?? seconds; lock.unlock() }
        var seconds: Double? { lock.lock(); defer { lock.unlock() }; return value }
    }

    /// A wait that never ends, for standing in as the arm that loses the race.
    private static func never() async {
        await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in }
    }

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
