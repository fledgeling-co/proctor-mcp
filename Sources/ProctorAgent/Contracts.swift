import Foundation
import IOKit.hid
import CoreGraphics
import ApplicationServices
import Carbon.HIToolbox
import ProctorCore

// Internal seams inside the agent. Written before the implementations so the
// AX side, the capture side and the session side can be built against a fixed
// interface rather than against each other.

// MARK: - Accessibility

protocol AXEngine: AnyObject, Sendable {
    /// Enumerate running applications. Cheap; touches nothing.
    func listApps(includeWindowless: Bool) throws -> [AppHandle]

    /// Begin a stateful session on an app: warm the tree, apply
    /// AXManualAccessibility where needed, start observers, retain refs.
    func attach(bundleId: String?, pid: Int32?, name: String?) throws -> (AppHandle, TreeProvenance)

    func detach(app: String) throws

    func windows(app: String) throws -> [WindowHandle]

    /// Walk a window's tree. Refs come from the cache where one exists, because
    /// a retained ref resolves across Spaces and a fresh enumeration does not.
    func snapshot(window: String, root: String?, maxDepth: Int, maxNodes: Int,
                  includeInvisible: Bool) throws -> (AXNode, TreeProvenance)

    func find(window: String, predicate: FindPredicate, limit: Int) throws -> [AXNode]

    func node(id: String) throws -> AXNode

    /// Perform one step through the process-directed plane. Returns the plane
    /// actually used, since a step may fall back from a declared contract.
    func perform(step: ActionStep, window: String, foreground: Bool) throws -> Actuation

    /// Read the app's menu bar as a raw tree for key-equivalent reconstruction.
    /// Returns nil when the app exposes no menu bar (agent-style apps have none).
    func menuBar(app: String) throws -> [RawMenuItem]?

    /// Notifications seen on this app since a mark. Backs the AX half of settle.
    func notificationCount(app: String, since: UInt64) -> Int
    func notificationMark(app: String) -> UInt64

    func health() -> [DoctorReport.AttachedAppHealth]
    var observersLive: Int { get }

    /// Which window a node belongs to; used to route capture and settle.
    func windowOf(node: String) -> String?

    /// The web areas in a window: what each says its URL is, and where it sits.
    /// Nil when the window holds none.
    ///
    /// One downward walk answers every question this feature asks — is the window
    /// showing a page, is a named element inside it, is a coordinate inside it —
    /// because containment is geometric. Walking up from each element instead
    /// would be an accessibility round trip per level of a DOM, per target.
    /// Only ever called for an application the browser catalogue already matched,
    /// so a native app pays nothing for it.
    func webContent(window: String) throws -> WebContentProbe?
}

struct FindPredicate: Sendable {
    var role: String?
    var subrole: String?
    var title: String?
    var label: String?
    var identifier: String?
    var valueContains: String?
    var enabled: Bool?
    var focused: Bool?
    var hasAction: String?
    var match: MatchMode = .substring
    enum MatchMode: String, Sendable { case substring, exact, regex }
}

// MARK: - Capture

/// Opt-in vision normalisation for a capture. The ceilings default to the
/// vision-API limits; a caller overrides them per call. The decision and the
/// coordinate round-trip both live in ProctorCore.VisionCapture — this only
/// carries the request from the tool boundary to the engine.
struct CaptureNormalizeOptions: Sendable {
    var maxLongEdge: Int = VisionCapture.Purpose.default.maxLongEdge
    var maxPixels: Int = VisionCapture.Purpose.default.maxPixels
    /// Which tier the ceilings came from, for the result to report. Nil when the
    /// caller set an explicit pixel ceiling, because then no tier describes it
    /// and naming one would be a label rather than a fact.
    var purpose: VisionCapture.Purpose? = VisionCapture.Purpose.default
}

/// How the frame is written to disk. Defaults to lossless PNG; a caller trades
/// text fidelity for bytes explicitly, never by omission. See
/// ProctorCore.ImageFormat for the measurements behind that default.
struct ImageEncodingOptions: Sendable {
    var format: ImageFormat = ImageFormat.defaultFormat
    var quality: Int?

    static let `default` = ImageEncodingOptions()
}

protocol CaptureEngine: AnyObject, Sendable {
    func capture(window: WindowHandle, to path: String?, waitForComplete: Bool,
                 timeoutMs: Int, scale: Double?, tileHashes: Bool,
                 includeCursor: Bool, normalize: CaptureNormalizeOptions?,
                 encoding: ImageEncodingOptions) async throws -> CaptureResult

    /// A running stream used by settle: report dirty area per frame without
    /// writing anything to disk.
    func beginQuietWatch(window: WindowHandle) async throws -> QuietWatch
}

extension CaptureEngine {
    /// Convenience for the callers that never normalise — the settle probe, the
    /// act/assert/flow evidence captures, the tri-observer frame, and the
    /// full-window capture proctor_zoom crops from. They keep the original
    /// argument list and stay native, lossless PNG; only proctor_capture reaches
    /// the normalising form.
    func capture(window: WindowHandle, to path: String?, waitForComplete: Bool,
                 timeoutMs: Int, scale: Double?, tileHashes: Bool,
                 includeCursor: Bool) async throws -> CaptureResult {
        try await capture(window: window, to: path, waitForComplete: waitForComplete,
                          timeoutMs: timeoutMs, scale: scale, tileHashes: tileHashes,
                          includeCursor: includeCursor, normalize: nil,
                          encoding: .default)
    }

    /// The normalising form with default encoding, for callers that care about
    /// the vision ceiling but not the container.
    func capture(window: WindowHandle, to path: String?, waitForComplete: Bool,
                 timeoutMs: Int, scale: Double?, tileHashes: Bool,
                 includeCursor: Bool,
                 normalize: CaptureNormalizeOptions?) async throws -> CaptureResult {
        try await capture(window: window, to: path, waitForComplete: waitForComplete,
                          timeoutMs: timeoutMs, scale: scale, tileHashes: tileHashes,
                          includeCursor: includeCursor, normalize: normalize,
                          encoding: .default)
    }
}

protocol QuietWatch: AnyObject, Sendable {
    /// Fraction of the frame that changed in the most recent frame, and its status.
    func poll() -> (dirtyArea: Double, status: FrameStatus, frames: Int)

    /// The same question asked of one rectangle, given in points relative to the
    /// window's top-left corner. The answer is either a measurement or the reason
    /// there is none, because a region that could not be measured is not a region
    /// that was quiet.
    func poll(region: Rect) -> RegionQuietSample

    func stop()
}

struct RegionQuietSample: Sendable {
    /// Dirty area inside the region as a fraction of the region, 0..1. Nil when
    /// the region could not be measured; `error` then says why.
    var dirtyArea: Double?
    var status: FrameStatus
    var frames: Int
    /// The rectangle as it was actually measured, in frame pixels.
    var regionPixels: Rect?
    var error: AgentError?
}

// MARK: - Owned-app reflector

protocol ReflectorBridge: AnyObject, Sendable {
    func isConnected(pid: Int32) -> Bool
    func inspect(pid: Int32, window: WindowHandle, node: String?, maxDepth: Int,
                 includeConstraints: Bool, presentation: Bool) throws -> JSONValue
    func isIdle(pid: Int32) -> Bool?
    func renderRevision(pid: Int32) -> Int?
}

// MARK: - Grants

enum Grants {
    static func accessibility() -> Bool {
        AXIsProcessTrusted()
    }

    /// Input Monitoring, read without asking anybody for anything.
    ///
    /// `IOHIDCheckAccess` reports the recorded answer and shows no dialog, which
    /// is what makes it safe to call from a health report. It matters here
    /// because a keyboard event tap is gated on a grant that is NOT the one
    /// Proctor needs for everything else, so an operator who turned the input
    /// block on can find it silently unavailable. Which service macOS 26 gates a
    /// `.defaultTap` on is not verified in this repo, so this is reported as a
    /// fact about the machine rather than as the cause of a failure.
    static func inputMonitoringState() -> String {
        switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
        case kIOHIDAccessTypeGranted: return "granted"
        case kIOHIDAccessTypeDenied: return "denied"
        default: return "unknown"
        }
    }

    static func promptAccessibility() {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Ask macOS for the Screen Recording consent dialog.
    ///
    /// `CGRequestScreenCaptureAccess` is the only way to get the system's own
    /// dialog rather than dumping the user in System Settings to find a switch.
    /// Like every TCC prompt it is shown once per app identity; after that it
    /// returns the recorded answer without showing anything, which is why the
    /// UI still offers the Settings route beside it.
    @discardableResult
    static func promptScreenRecording() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    /// Screen Recording cannot be probed without side effects on every version,
    /// so this asks ScreenCaptureKit for shareable content and reads the failure.
    static func screenRecordingFixText(osMajor: Int) -> String {
        "System Settings ▸ Privacy & Security ▸ Screen & System Audio Recording, enable Proctor. "
        + "This grant can never be applied silently or by profile on any macOS version — a person has to click it."
    }

    /// What to say when the probe did not answer at all.
    ///
    /// Deliberately **not** the Settings text. The permission may well be granted;
    /// what happened is that macOS did not answer inside the bound, and sending
    /// somebody to System Settings to grant something they already granted is the
    /// defect PRO-0041 exists to fix. The remedies that actually apply are asking
    /// again and restarting the agent, so those are the ones named.
    static func screenRecordingUnconfirmedText(bound: Double) -> String {
        "Not established. macOS did not answer the Screen Recording probe within "
        + "\(String(format: "%.1f", bound))s, so this is not a denial and System Settings is "
        + "probably not where the answer is. Call proctor_doctor again — the answer is cached "
        + "as soon as it arrives. If it stays unconfirmed, restart the agent to probe from a "
        + "fresh process. Capture may still work; what is missing is the confirmation, not "
        + "necessarily the permission."
    }

    static func accessibilityFixText(osMajor: Int) -> String {
        if osMajor >= 27 {
            return "System Settings ▸ Privacy & Security ▸ Accessibility, enable Proctor. "
                 + "On macOS 27 the legacy PPPC profile path is removed; managed fleets use declarative App Settings."
        }
        return "System Settings ▸ Privacy & Security ▸ Accessibility, enable Proctor. "
             + "On macOS 26 a managed fleet can also grant this by PPPC profile."
    }

    static func secureEventInputActive() -> Bool {
        IsSecureEventInputEnabled()
    }
}
