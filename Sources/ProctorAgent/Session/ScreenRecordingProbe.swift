import Foundation
import ScreenCaptureKit
import ProctorCore

// The Screen Recording probe, bounded.
//
// MEASURED, 2026-08-15, and the measurement is why this is shaped the way it is
// rather than the way anyone would write it first.
//
// The obvious bound is a structured race: put the probe and a timer in a
// `withTaskGroup`, take whichever finishes first, `cancelAll()`. **That does not
// work here.** Instrumented with unbuffered file markers, the timer fired at
// +2.07s and the race resolved — and `withTaskGroup` never returned. A task group
// awaits its children before it returns, and `cancelAll()` cannot cancel a task
// parked inside `SCShareableContent`'s non-cancellable continuation. The
// structured version reproduces the hang with extra steps.
//
// So the bound is unstructured: a continuation resumed by whichever of two
// detached tasks gets there first, with a resume-once guard. Measured working —
// returned at 2.030s and the whole test process exited 2s later with the probe
// still parked, so an abandoned continuation does not hold the process open.
//
// One consequence worth naming, because it looks like a defect and is not. On a
// machine that has never granted Screen Recording, this call raises the system
// consent dialog and does not return until somebody answers it — which is longer
// than the bound. So a person sitting on that dialog makes `proctor_doctor`
// report `unconfirmed`, which is exactly what is true at that moment. When they
// answer, the parked probe returns, its answer is cached, and the next call —
// 2 seconds later on the window's own poll — reports it. That is strictly better
// than the behaviour it replaces, which was a health check that blocked until the
// dialog was dismissed.

/// Resume-once. `withCheckedContinuation` traps on a second resume, and two
/// detached tasks racing to resume it is the entire design.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false
    func claim() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}

/// Asks the platform whether Screen Recording is granted, and stops asking after
/// a bound.
///
/// The platform call is a closure so the bound itself is testable: a call that
/// answers, a call that throws, and — the case this exists for — a call that does
/// neither.
struct ScreenRecordingProbe: Sendable {

    let platform: @Sendable () async -> GrantState
    let keeper: GrantProbeKeeper
    let bound: Double
    let now: @Sendable () -> Double

    init(bound: Double = GrantProbe.bound,
         keeper: GrantProbeKeeper? = nil,
         now: @escaping @Sendable () -> Double = { Date().timeIntervalSince1970 },
         platform: @escaping @Sendable () async -> GrantState) {
        self.bound = bound
        self.keeper = keeper ?? GrantProbeKeeper(bound: bound)
        self.now = now
        self.platform = platform
    }

    /// The real one. Screen Recording has no query API: asking ScreenCaptureKit
    /// for shareable content answers, throws, or — measured — does neither, which
    /// is what the bound above is for.
    static let live = ScreenRecordingProbe {
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true)
            return .granted
        } catch {
            return .denied
        }
    }

    /// Answers `granted`, `denied`, or `unconfirmed`, always within the bound.
    func state() async -> GrantState {
        switch keeper.claim(now: now()) {
        case .cached(let known):
            return known
        case .unconfirmed:
            return .unconfirmed
        case .join(let remaining):
            // Somebody else's probe is running inside its bound. Wait out what is
            // left of it rather than starting a second probe against a platform
            // that is already busy not answering — but wait in slices and stop the
            // moment an answer lands. Sleeping the whole remainder would make a
            // 20ms grant cost every concurrent caller the full bound.
            return await waitForRunningProbe(upTo: remaining)
        case .start(let token):
            return await bounded(token: token)
        }
    }

    /// Poll the cache while somebody else's probe runs. Slices rather than one
    /// sleep, so a fast answer is returned fast.
    private func waitForRunningProbe(upTo remaining: Double) async -> GrantState {
        let slice = 0.02
        var waited = 0.0
        while waited < remaining {
            if let known = keeper.cachedDefinite() { return known }
            try? await Task.sleep(nanoseconds: UInt64(min(slice, remaining - waited) * 1_000_000_000))
            waited += slice
        }
        return keeper.cachedDefinite() ?? .unconfirmed
    }

    private func bounded(token: Int) async -> GrantState {
        let answer: GrantState = await withCheckedContinuation { continuation in
            let once = ResumeOnce()
            let finish: @Sendable (GrantState) -> Void = { value in
                if once.claim() { continuation.resume(returning: value) }
            }
            Task.detached {
                let result = await platform()
                // Recorded before the waiter is resumed, so a waiter that wakes to
                // a definite answer can always see it. Token-stamped: this call may
                // land long after its own attempt was given up on, and it must not
                // rearrange a later attempt's bookkeeping — though its *answer* is
                // kept either way, because a definite answer is a per-process
                // constant on this platform.
                keeper.record(result, token: token, now: now())
                finish(result)
            }
            Task.detached {
                try? await Task.sleep(nanoseconds: UInt64(bound * 1_000_000_000))
                finish(.unconfirmed)
            }
        }

        guard answer == .unconfirmed else { return answer }
        // Free the slot and push the next attempt out — but read the cache first,
        // because the platform may have answered in the instant between the timer
        // firing and this line. Reporting `unconfirmed` beside a populated cache
        // would be wrong in the one direction that matters.
        keeper.abandon(token: token, now: now())
        return keeper.cachedDefinite() ?? .unconfirmed
    }
}
