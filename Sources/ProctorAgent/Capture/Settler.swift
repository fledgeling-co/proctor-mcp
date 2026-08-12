import Foundation
import ProctorCore

// Settling is a conjunction, never a sleep. A fixed wait is either too short,
// in which case the assertion races the app, or too long, in which case every
// test pays for the worst case. Every signal that is genuinely available has to
// agree before the wait ends, and the report names which ones there were, because
// a settle backed by one signal is weaker evidence than one backed by three.

actor Settler {

    /// Signal names as they appear in SettleReport.signals.
    enum Signal {
        static let capture = "capture"
        static let ax = "ax"
        static let reflector = "reflector"
        static let timeout = "timeout"
    }

    private let capture: CaptureEngine?
    private let pollIntervalMs: Int

    init(capture: CaptureEngine?, pollIntervalMs: Int = 50) {
        self.capture = capture
        self.pollIntervalMs = max(5, pollIntervalMs)
    }

    /// `axQuiet` reports notifications seen and how long the window has been
    /// quiet. A negative quietMs means no observer is attached, which is how the
    /// AX signal declares itself unavailable rather than silently counting as quiet.
    /// `reflectorIdle` returns nil when no reflector is embedded.
    func settle(window: WindowHandle,
                policy: SettlePolicy,
                axQuiet: @Sendable () -> (count: Int, quietMs: Int),
                reflectorIdle: @Sendable () -> Bool?) async -> SettleReport {

        let started = Date()
        let deadline = started.addingTimeInterval(Double(max(policy.timeoutMs, 1)) / 1000)

        var watch: QuietWatch?
        if let capture {
            watch = try? await capture.beginQuietWatch(window: window)
        }
        defer { watch?.stop() }

        var captureAvailable = watch != nil
        let firstAX = axQuiet()
        let axAvailable = firstAX.quietMs >= 0
        let firstReflector = reflectorIdle()
        var reflectorAvailable = firstReflector != nil

        var signals: [String] = []
        if captureAvailable { signals.append(Signal.capture) }
        if axAvailable { signals.append(Signal.ax) }
        if reflectorAvailable { signals.append(Signal.reflector) }

        var quietFrames = 0
        var lastDirtyArea = 0.0
        var lastFrameCount = -1
        var axCount = firstAX.count
        var axMs = max(0, firstAX.quietMs)
        var reflectorState = firstReflector

        while true {
            if let watch {
                let frame = watch.poll()
                lastDirtyArea = frame.dirtyArea
                let delivered = frame.frames != lastFrameCount
                lastFrameCount = frame.frames

                if frame.status == .stopped {
                    // The stream died. Carrying on as if it were quiet would turn a
                    // dead signal into a passing one, so it stops counting instead.
                    captureAvailable = false
                    quietFrames = 0
                } else if !delivered {
                    // ScreenCaptureKit delivers a frame when the window changes and
                    // then goes silent. A poll with no new frame is therefore the
                    // strongest quiet evidence the capture side has — reading the
                    // previous frame's dirty area again would hold the settle open
                    // forever on a window that finished moving before it started.
                    quietFrames += 1
                } else if frame.status == .complete && frame.dirtyArea < policy.dirtyThreshold {
                    quietFrames += 1
                } else if frame.status == .idle {
                    // An idle frame means the window server had nothing new to send,
                    // which is the same evidence of quiet as a clean complete frame.
                    quietFrames += 1
                } else {
                    quietFrames = 0
                }
            }

            let ax = axQuiet()
            axCount = ax.count
            if ax.quietMs >= 0 { axMs = ax.quietMs }
            reflectorState = reflectorIdle()
            reflectorAvailable = reflectorState != nil

            let captureQuiet = captureAvailable && quietFrames >= policy.quietFrames
            let axQuietNow = axAvailable && axMs >= policy.axQuietMs
            let reflectorQuiet = reflectorState == true

            // requireReflectorIdle with no reflector connected can never be
            // satisfied, and reporting it as settled would be a lie about which
            // evidence was actually obtained.
            let reflectorSatisfied = policy.requireReflectorIdle
                ? reflectorQuiet
                : (!reflectorAvailable || reflectorQuiet)

            let captureSatisfied = !captureAvailable || captureQuiet
            let axSatisfied = !axAvailable || axQuietNow
            let anyAvailable = captureAvailable || axAvailable || reflectorAvailable

            if anyAvailable && captureSatisfied && axSatisfied && reflectorSatisfied {
                let reason: SettleReport.Reason
                if captureAvailable && axAvailable {
                    reason = .allSignalsQuiet
                } else if reflectorAvailable && reflectorQuiet {
                    reason = .reflectorIdle
                } else if axAvailable {
                    reason = .axQuietOnly
                } else {
                    reason = .captureQuietOnly
                }
                return SettleReport(
                    settled: true,
                    elapsedMs: Int(Date().timeIntervalSince(started) * 1000),
                    reason: reason,
                    quietFrames: quietFrames,
                    lastDirtyArea: lastDirtyArea,
                    axNotificationsSeen: axCount,
                    axQuietMs: axMs,
                    reflectorIdle: reflectorState,
                    signals: signals)
            }

            // An app with a caret, a spinner or any looping animation delivers a
            // dirty frame forever, so pixel-quiet is unreachable there. Holding the
            // whole conjunction open for a signal that can never arrive turns every
            // step into a timeout. Once the other signals have held for well past
            // their own threshold, the settle concludes on those and reports the
            // weaker reason rather than claiming agreement it did not get.
            if captureAvailable, axAvailable, axQuietNow,
               axMs >= max(policy.axQuietMs * 3, policy.axQuietMs + 500), reflectorSatisfied {
                return SettleReport(
                    settled: true,
                    elapsedMs: Int(Date().timeIntervalSince(started) * 1000),
                    reason: .axQuietOnly,
                    quietFrames: quietFrames,
                    lastDirtyArea: lastDirtyArea,
                    axNotificationsSeen: axCount,
                    axQuietMs: axMs,
                    reflectorIdle: reflectorState,
                    signals: signals + ["captureNeverQuiet"])
            }

            if Date() >= deadline { break }
            try? await Task.sleep(nanoseconds: UInt64(pollIntervalMs) * 1_000_000)
        }

        var timeoutSignals = signals
        if timeoutSignals.isEmpty { timeoutSignals = [Signal.timeout] }
        return SettleReport(
            settled: false,
            elapsedMs: Int(Date().timeIntervalSince(started) * 1000),
            reason: .timeout,
            quietFrames: quietFrames,
            lastDirtyArea: lastDirtyArea,
            axNotificationsSeen: axCount,
            axQuietMs: axMs,
            reflectorIdle: reflectorState,
            signals: timeoutSignals)
    }
}
