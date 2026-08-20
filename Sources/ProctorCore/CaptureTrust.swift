import Foundation

// Whether a captured frame may be presented as evidence, and which signals a
// settle was actually able to consult.
//
// Both decisions used to sit inline in the agent, where `Package.swift` has no
// way to reach them: there is no window server under `swift test`, so a rule
// written beside a ScreenCaptureKit call is a rule this repo cannot prove. Both
// were found unguarded by arming — `trustworthy` was forced to `true` and the
// capture signal was forced to unavailable, and the whole suite stayed green in
// each case. They are values here for the same reason `StatusChecks` and
// `SwitchCatalogue` are.
public enum CaptureTrust {

    /// Whether a frame can be shown as evidence of what an application drew.
    ///
    /// Two conditions, and the second is the one that is easy to forget: a frame
    /// the platform called complete but whose content rect has no area is a
    /// window that was not really captured, and it arrives looking exactly like a
    /// good frame. Both must hold, so neither can carry a pass alone.
    public static func trustworthy(frameComplete: Bool, contentWidth: Double,
                                   contentHeight: Double) -> Bool {
        frameComplete && contentWidth > 0 && contentHeight > 0
    }
}

/// Which signals a settle could consult, named the way the report names them.
///
/// A settle that reports `allSignalsQuiet` over an empty signal list has said
/// nothing at all, so the list is what makes the verdict readable: it is the
/// denominator behind the word "all".
public enum SettleSignals {
    public static let capture = "capture"
    public static let ax = "ax"
    public static let reflector = "reflector"

    /// In report order, and only what was genuinely available.
    public static func available(capture: Bool, ax: Bool, reflector: Bool) -> [String] {
        var signals: [String] = []
        if capture { signals.append(Self.capture) }
        if ax { signals.append(Self.ax) }
        if reflector { signals.append(Self.reflector) }
        return signals
    }

    /// Whether a settle is entitled to claim quiet at all. With nothing to
    /// consult there is no quiet to report, only an absence of instruments.
    public static func canReportQuiet(signals: [String]) -> Bool { !signals.isEmpty }
}
