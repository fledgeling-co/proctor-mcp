import CoreGraphics
import Foundation
import ProctorCore
@testable import ProctorAgent

/// A CoreGraphics window number this Mac is not using.
///
/// DEF-337. Every fake window here carried `cgWindowID: 7`, and 7 is a real
/// window on a running Mac — Notification Centre, measured 2026-08-25, at layer
/// 21. `Session.cursorPlane(for:)` resolves a plane by asking whether the id is
/// in the on-screen window list, so a suite asserting `.hidden` for a fabricated
/// window passed or failed according to whether Notification Centre happened to
/// be up. It failed once in this repository's history for exactly that reason,
/// and re-running it made it pass, which is the worst shape a failure can take.
///
/// Picking a large constant would only move the collision further away. This
/// reads the live list and takes one above the highest number on it, then the
/// caller asserts the absence it was given — so a helper that ever stops working
/// makes the test say so rather than pass vacuously.
enum TestWindowIDs {

    /// A number no window on this machine holds, at the moment it is asked.
    static func absent() -> UInt32 {
        let ws = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements],
                                            kCGNullWindowID) as? [[String: Any]] ?? []
        let highest = ws.compactMap { $0[kCGWindowNumber as String] as? UInt32 }.max() ?? 0
        return highest &+ 1_000
    }

    /// Is this number genuinely absent from the on-screen list right now?
    /// The assertion a test makes about its own fixture before trusting it.
    static func isAbsentOnScreen(_ id: UInt32) -> Bool {
        let ws = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                            kCGNullWindowID) as? [[String: Any]] ?? []
        return !ws.contains { ($0[kCGWindowNumber as String] as? UInt32) == id }
    }
}

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
    /// Fail the nth perform call with a specific error, for a test that needs a
    /// particular *kind* of failure rather than any failure — an indeterminate
    /// one, whose `indeterminate` flag is set by the backend and is what the
    /// score reads. Takes precedence over `failPerformAt` at the same index.
    var failPerformWith: [Int: AgentError] = [:]
    /// Called with the 0-based index of each perform, before it returns. A test
    /// that needs something to happen *during* a run — a person pressing Stop
    /// between two steps — hangs it here.
    var onPerform: (@Sendable (Int) -> Void)?
    /// The plane a given step index reports having travelled. Absent means the
    /// accessibility plane, which is what a fake app answers unless a test is
    /// specifically about a step that could not travel that way.
    var planeAt: [Int: ActuationPlane] = [:]
    /// The route a given step index reports having taken. Absent means the
    /// plain value write a fake element would accept.
    var routeAt: [Int: ActuationRoute] = [:]

    /// What the window reports as web content. Nil is a window with no page in it,
    /// which is what every non-browser test wants and what a browser's About panel
    /// would report. Implemented on the class rather than left to a protocol
    /// default, so a test that forgets to set it fails a positive assertion rather
    /// than passing vacuously.
    var webContentProbe: WebContentProbe?

    /// The role and frame the fake's single node reports, so a test can place a
    /// match inside or outside a web area.
    var nodeRole = "AXButton"
    var nodeFrame = Rect(x: 0, y: 0, w: 40, h: 20)

    /// Nodes `node(id:)` should answer with by id, for a test that needs more
    /// than one — a subject, its container and the window are three different
    /// rectangles, and a geometry assertion cannot be exercised against a fake
    /// that answers the same node to every id. Empty is the single-node
    /// behaviour every other suite is written against.
    var nodesByID: [String: AXNode] = [:]

    init(bundleId: String, appID: String = "app-1", windowID: String = "win-1") {
        app = AppHandle(id: appID, pid: 4242, bundleId: bundleId, name: "Fake")
        window = WindowHandle(id: windowID, app: appID, title: "Fake Window",
                              frame: Rect(x: 0, y: 0, w: 800, h: 600), isMain: true,
                              isMinimized: false, isOnActiveSpace: true,
                              cgWindowID: TestWindowIDs.absent())
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

    func node(id: String) throws -> AXNode { nodesByID[id] ?? node }

    func perform(step: ActionStep, window: String, foreground: Bool) throws -> Actuation {
        let index = performed.count
        performed.append(step)
        onPerform?(index)
        if let error = failPerformWith[index] { throw error }
        if failPerformAt == index {
            throw AgentError(code: .actionFailed, message: "fake failure at step \(index)")
        }
        let plane = planeAt[index] ?? .accessibility
        return Actuation(plane, routeAt[index] ?? (plane == .syntheticEvent ? .eventStream
                                                                           : .valueWrite))
    }

    var menuBarItems: [RawMenuItem]?

    func menuBar(app: String) throws -> [RawMenuItem]? { menuBarItems }
    func notificationCount(app: String, since: UInt64) -> Int { 0 }
    func notificationMark(app: String) -> UInt64 { 0 }
    func health() -> [DoctorReport.AttachedAppHealth] { [] }
    var observersLive: Int { 0 }
    func windowOf(node: String) -> String? { window.id }

    func webContent(window: String) throws -> WebContentProbe? { webContentProbe }

    private var node: AXNode {
        AXNode(id: "node-1", role: nodeRole, title: "OK", frame: nodeFrame)
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

/// A hold to hand the latch in a test that cares about the parking rule rather
/// than about the attribution. Production never builds one this way — it derives
/// every part from the peer process and the driven window — so the session name
/// here is deliberately one nothing could mistake for a real one.
func aHold(_ reason: YieldReason, session: String = "test-session 0000",
           app: String? = nil) -> HoldAttribution {
    HoldAttribution(reason: reason, session: session, app: app)
}

// MARK: - Screen Recording

extension ScreenRecordingProbe {
    /// A probe that answers instantly, for any suite that calls `doctor`.
    ///
    /// PRO-0041: the real probe asks ScreenCaptureKit for shareable content, and
    /// measured on 2026-08-15 that call parks forever inside a swiftpm test host
    /// — it neither answers nor throws, while the same call from a plain script
    /// answered in 0.037s. Six tests across two suites hung on it, which is why
    /// the merge gate ran `--skip ObscuraPresenceWiringTests
    /// --skip BrowserLaneWiringTests` for two waves.
    ///
    /// The bound in `ScreenRecordingProbe` means those suites would now finish
    /// either way; injecting is what keeps them instant, and keeps a suite's
    /// answer from depending on whether the machine running it granted Screen
    /// Recording. The bound has its own tests in
    /// `ScreenRecordingProbeWiringTests`, so injecting here does not hide it.
    static func fake(_ state: GrantState = .granted) -> ScreenRecordingProbe {
        ScreenRecordingProbe(platform: { state })
    }
}
