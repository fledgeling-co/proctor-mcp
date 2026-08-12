import Foundation
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
    func perform(step: ActionStep, window: String, foreground: Bool) throws -> ActuationPlane

    /// Notifications seen on this app since a mark. Backs the AX half of settle.
    func notificationCount(app: String, since: UInt64) -> Int
    func notificationMark(app: String) -> UInt64

    func health() -> [DoctorReport.AttachedAppHealth]
    var observersLive: Int { get }

    /// Which window a node belongs to; used to route capture and settle.
    func windowOf(node: String) -> String?
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

protocol CaptureEngine: AnyObject, Sendable {
    func capture(window: WindowHandle, to path: String?, waitForComplete: Bool,
                 timeoutMs: Int, scale: Double?, tileHashes: Bool,
                 includeCursor: Bool) async throws -> CaptureResult

    /// A running stream used by settle: report dirty area per frame without
    /// writing anything to disk.
    func beginQuietWatch(window: WindowHandle) async throws -> QuietWatch
}

protocol QuietWatch: AnyObject, Sendable {
    /// Fraction of the frame that changed in the most recent frame, and its status.
    func poll() -> (dirtyArea: Double, status: FrameStatus, frames: Int)
    func stop()
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

    static func promptAccessibility() {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Screen Recording cannot be probed without side effects on every version,
    /// so this asks ScreenCaptureKit for shareable content and reads the failure.
    static func screenRecordingFixText(osMajor: Int) -> String {
        "System Settings ▸ Privacy & Security ▸ Screen & System Audio Recording, enable Proctor. "
        + "This grant can never be applied silently or by profile on any macOS version — a person has to click it."
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
