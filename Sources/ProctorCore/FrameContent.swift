import Foundation

// PRO-0088. Whether a frame that arrived has anything in it.
//
// `SCFrameStatus complete` means ScreenCaptureKit delivered a frame, not that
// the frame depicts something. Measured 2026-08-20: `proctor_capture` on a
// window Proctor's own UI owns returned `status: complete, trustworthy: true`
// over a PNG in which all 2,942,720 pixels were RGBA(0,0,0,0). The exclusion
// worked exactly as designed — Proctor keeps its own windows out of its own
// captures — and nothing between the status bit and the verdict asked whether
// the exclusion was all that came back.
//
// The decision lives here, in Core, with no I/O and no ScreenCaptureKit, so it
// can be driven by a test on a machine with no display: what runs in production
// and what a test drives are then the same function rather than twins.
//
// The honest edge this file is built around: a legitimately blank window
// exists, and calling that a defect would be its own false positive. So an
// empty frame is never reported as a fault in the target. It is reported as
// *not established*, and where the path holds a fact that explains it — the
// target is a window Proctor excludes by design — it states the mechanism
// rather than inferring from pixels.

/// What was actually seen in a captured frame's bytes. Everything here is
/// measured over the same pixels the PNG on disk was encoded from, so the
/// verdict and the file a person opens are about the same frame.
public struct FrameContentSummary: Codable, Sendable, Equatable {
    /// How many pixels the summary looked at, which is every pixel in the
    /// frame.
    ///
    /// Alpha is read exhaustively rather than on a stride. A square stride over
    /// a 3456x2234 frame steps 7-8 pixels, so a one-pixel hairline falls between
    /// every sample and a window with something in it reports empty — a false
    /// positive on the exact edge this file exists for. `allTransparent` is
    /// therefore a claim about the whole frame, and this is its denominator.
    ///
    /// `distinctColours` is the one field here that is still strided, and it is
    /// reported rather than judged, so nothing keys off its population.
    ///
    /// Zero means no measurement was taken at all — a layout this cannot read,
    /// or a buffer shorter than its own geometry. It never means an empty frame.
    public var pixelsSampled: Int
    /// The highest alpha byte seen, 0...255.
    public var maxAlpha: Int
    /// Distinct RGBA values seen, counted up to a cap. Reported rather than
    /// judged: an opaque single-colour frame is a real thing an application can
    /// draw, and a caller that wants to make something of `1` can.
    public var distinctColours: Int
    /// True when a non-empty sample found no alpha at all.
    public var allTransparent: Bool

    public init(pixelsSampled: Int, maxAlpha: Int, distinctColours: Int, allTransparent: Bool) {
        self.pixelsSampled = pixelsSampled
        self.maxAlpha = maxAlpha
        self.distinctColours = distinctColours
        self.allTransparent = allTransparent
    }
}

/// What the content check concluded. Deliberately not a boolean: "empty because
/// we exclude this window" and "empty and we cannot say why" are different
/// things to tell a caller, and collapsing them loses the only fact that
/// distinguishes a designed emptiness from an unexplained one.
public enum CaptureContentVerdict: String, Codable, Sendable {
    /// Something is in the frame.
    case content
    /// Nothing is in the frame, and the target is a window Proctor excludes
    /// from its own captures. Nothing was going to be in it.
    case excludedTarget
    /// Nothing is in the frame, and the target is not one Proctor excludes.
    case emptyFrame
    /// No sample was taken, so nothing is claimed either way.
    case notMeasured
}

public enum CaptureContentGate {

    /// The cap on `distinctColours`. High enough that any real window blows
    /// past it, low enough that counting costs nothing.
    public static let colourCap = 256

    /// Total, and free of I/O. A `nil` summary is `notMeasured` rather than
    /// `emptyFrame`: not looking and looking and finding nothing are not the
    /// same claim.
    public static func verdict(summary: FrameContentSummary?,
                               targetIsProctorOwned: Bool) -> CaptureContentVerdict {
        guard let summary, summary.pixelsSampled > 0 else { return .notMeasured }
        guard summary.allTransparent else { return .content }
        return targetIsProctorOwned ? .excludedTarget : .emptyFrame
    }

    /// Why the frame cannot be vouched for, in the words a caller reading the
    /// reply needs. `nil` only for `.content`, which is the only verdict that
    /// leaves the frame trustworthy and so the only one with nothing to say.
    ///
    /// `.notMeasured` used to return `nil` too, on the reading that a check
    /// which claims nothing owes no explanation. That was wrong once the verdict
    /// started gating `trustworthy`: the caller gets `trustworthy: false` over a
    /// frame whose bytes were never read, and an untrustworthy verdict with no
    /// reason beside it is the shape of report this whole item exists to stop.
    /// The sentence says what could not be done, and takes care not to imply the
    /// window was empty — that is the claim not being made.
    public static func caveat(for verdict: CaptureContentVerdict,
                              summary: FrameContentSummary?,
                              window: String) -> String? {
        switch verdict {
        case .content:
            return nil
        case .notMeasured:
            return "The content of window \(window) was not measured, so nothing here says "
                 + "whether the frame depicts anything. The bytes did not arrive in the 32BGRA "
                 + "layout the capture stream asks for, or the buffer was shorter than its own "
                 + "geometry, and reading them either way would have reported a colour channel "
                 + "as alpha. This is not a report that the window was empty. The PNG was "
                 + "written from these same bytes, so it is the thing to look at; retry the "
                 + "capture if the picture disagrees."
        case .excludedTarget:
            return "Window \(window) belongs to Proctor, and Proctor excludes its own windows from "
                 + "its own captures so the run HUD and the takeover statement never appear in a "
                 + "shot. The frame arrived, and it is empty because nothing was going to be in "
                 + "it. The status says a frame was delivered; it does not say the frame depicts "
                 + "anything."
        case .emptyFrame:
            let sampled = summary?.pixelsSampled ?? 0
            return "The frame arrived with no content: \(sampled) pixel(s) sampled and every one "
                 + "fully transparent. That is not a judgement about whether the picture is "
                 + "right, only that there is no picture to judge. Raise the window, or confirm "
                 + "it is not excluded from capture by its owner, then retry."
        }
    }

    /// The bundle identifiers Proctor's own windows are drawn by. Two, not one:
    /// the UI app is `Wire.bundleIdentifier` and the agent carries its own
    /// embedded `Info.plist` identifying it as `Wire.agentLabel`
    /// (`Apps/Proctor/AgentInfo.plist`). Measured 2026-08-21 against a running
    /// build: `proctor_apps list` reports the agent as
    /// `app.fledgeling.procter.agent`, so a check written against the UI's
    /// identifier alone would miss every window the agent draws — which is all
    /// three overlays.
    ///
    /// Matched exactly rather than by prefix. A prefix test would also claim
    /// any future identifier that happens to start the same way, and the point
    /// of this fact is that it is a fact.
    public static let proctorBundleIdentifiers: Set<String> = [
        Wire.bundleIdentifier, Wire.agentLabel,
    ]

    /// True when a window's owning bundle identifier is one of Proctor's own.
    public static func isProctorOwned(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        return proctorBundleIdentifiers.contains(bundleIdentifier)
    }
}
