import Foundation
import ProctorCore
@testable import ProctorAgent

// Fake engines for the agent's own wiring tests. Session takes its accessibility
// and capture sides as injected protocols, so the order the policy gate runs in,
// and what the trail ends up holding, are checkable here without a Mac, a TCC
// grant, or a real application on screen.

/// An accessibility engine that answers from a script rather than from AX. It
/// records every step it was asked to perform, so a test can tell "the gate
/// refused before anything ran" from "the gate refused after the fact".
final class FakeAX: AXEngine, @unchecked Sendable {

    let app: AppHandle
    let window: WindowHandle
    /// Steps actually actuated, in order. A gate that runs late leaves entries here.
    private(set) var performed: [ActionStep] = []
    /// Fail the nth perform call (0-based), to exercise the failure paths.
    var failPerformAt: Int?

    init(bundleId: String, appID: String = "app-1", windowID: String = "win-1") {
        app = AppHandle(id: appID, pid: 4242, bundleId: bundleId, name: "Fake")
        window = WindowHandle(id: windowID, app: appID, title: "Fake Window",
                              frame: Rect(x: 0, y: 0, w: 800, h: 600), isMain: true,
                              isMinimized: false, isOnActiveSpace: true, cgWindowID: 7)
    }

    func listApps(includeWindowless: Bool) throws -> [AppHandle] { [app] }

    func attach(bundleId: String?, pid: Int32?, name: String?) throws -> (AppHandle, TreeProvenance) {
        (app, TreeProvenance())
    }

    func detach(app: String) throws {}

    func windows(app: String) throws -> [WindowHandle] { [window] }

    func snapshot(window: String, root: String?, maxDepth: Int, maxNodes: Int,
                  includeInvisible: Bool) throws -> (AXNode, TreeProvenance) {
        (node, TreeProvenance())
    }

    func find(window: String, predicate: FindPredicate, limit: Int) throws -> [AXNode] { [node] }

    func node(id: String) throws -> AXNode { node }

    func perform(step: ActionStep, window: String, foreground: Bool) throws -> ActuationPlane {
        let index = performed.count
        performed.append(step)
        if failPerformAt == index {
            throw AgentError(code: .actionFailed, message: "fake failure at step \(index)")
        }
        return .accessibility
    }

    func menuBar(app: String) throws -> [RawMenuItem]? { nil }
    func notificationCount(app: String, since: UInt64) -> Int { 0 }
    func notificationMark(app: String) -> UInt64 { 0 }
    func health() -> [DoctorReport.AttachedAppHealth] { [] }
    var observersLive: Int { 0 }
    func windowOf(node: String) -> String? { window.id }

    private var node: AXNode {
        AXNode(id: "node-1", role: "AXButton", title: "OK",
               frame: Rect(x: 0, y: 0, w: 40, h: 20))
    }
}

/// A capture engine whose stream is immediately idle, so a settle concludes on
/// the capture signal in a couple of polls instead of running to its timeout.
final class FakeCapture: CaptureEngine, @unchecked Sendable {

    func capture(window: WindowHandle, to path: String?, waitForComplete: Bool,
                 timeoutMs: Int, scale: Double?, tileHashes: Bool,
                 includeCursor: Bool, normalize: CaptureNormalizeOptions?,
                 encoding: ImageEncodingOptions) async throws -> CaptureResult {
        throw AgentError(code: .captureFailed, message: "no capture in the fake")
    }

    func beginQuietWatch(window: WindowHandle) async throws -> QuietWatch { IdleWatch() }

    final class IdleWatch: QuietWatch, @unchecked Sendable {
        func poll() -> (dirtyArea: Double, status: FrameStatus, frames: Int) { (0, .idle, 1) }
        func poll(region: Rect) -> RegionQuietSample {
            RegionQuietSample(dirtyArea: 0, status: .idle, frames: 1,
                              regionPixels: nil, error: nil)
        }
        func stop() {}
    }
}

/// A collector standing in for the on-disk trail.
final class AuditCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [AuditRecord] = []

    var records: [AuditRecord] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }

    var sink: @Sendable (AuditRecord) -> Void {
        { [self] record in
            lock.lock(); defer { lock.unlock() }
            storage.append(record)
        }
    }

    func records(tool: String) -> [AuditRecord] { records.filter { $0.tool == tool } }
}
