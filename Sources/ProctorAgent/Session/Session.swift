import Foundation
import ProctorCore

enum AgentBuild {
    static let version = "0.1.0"
}

/// Everything stateful in the agent lives here, behind one actor.
///
/// The state is the point rather than an optimisation. A retained
/// AXUIElementRef keeps resolving when its window moves to another Space; a
/// fresh enumeration does not find it. Electron trees stay empty until
/// AXManualAccessibility is set on the application element and the tree has
/// warmed. AXObservers have to be long-lived. A server that re-enumerated on
/// every call would pass against one frontmost window and then fail on
/// background windows, other Spaces and Electron apps — reported as "element
/// not found", which a model papers over by retrying.
///
/// An actor rather than a lock because the operations are async (capture and
/// settle both await) and because serialising them is correct anyway: two
/// concurrent actions against the same window would each settle on the other's
/// changes.
actor Session {

    let ax: any AXEngine
    let capture: any CaptureEngine
    let reflector: any ReflectorBridge
    let tri: (any TriObserving)?
    let settler: Settler

    /// How many past trees are retained per window to serve a sinceRevision
    /// diff. A caller more than this far behind is diffed from the oldest tree
    /// still held, and the diff says which revision that was.
    static let historyDepth = 5

    struct TreeRevision: Sendable {
        let revision: Int
        let node: AXNode
        let hash: String
    }

    struct WalkOutcome: Sendable {
        let root: AXNode
        let provenance: TreeProvenance
        let revision: Int
        let hash: String
        let previous: TreeRevision?
        let history: [TreeRevision]
    }

    struct SnapshotOptions: Sendable {
        var root: String?
        var maxDepth: Int = 24
        // 2000 returns promptly on an ordinary window and takes tens of seconds
        // on a large icon-view list, where the target's own accessibility
        // implementation is the cost. 600 covers the windows a test actually
        // drives; raise it deliberately when a wide tree is the subject.
        var maxNodes: Int = 600
        var includeInvisible: Bool = false
    }

    private var apps: [String: AppHandle] = [:]
    private var provenanceByApp: [String: TreeProvenance] = [:]
    private var windowsByID: [String: WindowHandle] = [:]
    private var revisions: [String: Int] = [:]
    private var history: [String: [TreeRevision]] = [:]

    private(set) var flows: [String: RecordedFlow] = [:]
    private(set) var recording: String?
    private var flowsLoaded = false

    init(ax: any AXEngine,
         capture: any CaptureEngine,
         reflector: any ReflectorBridge = NullReflectorBridge(),
         tri: (any TriObserving)? = nil) {
        self.ax = ax
        self.capture = capture
        self.reflector = reflector
        self.tri = tri
        self.settler = Settler(capture: capture)
    }

    // MARK: - Handles

    func windowHandle(_ id: String) throws -> WindowHandle {
        if let cached = windowsByID[id] { return cached }
        refreshWindows()
        if let cached = windowsByID[id] { return cached }
        throw AgentError(
            code: .windowNotFound,
            message: "no window with handle \(id)",
            remedy: apps.isEmpty
                ? "Nothing is attached. Call proctor_apps with action \"attach\" first — window handles only exist for attached apps."
                : "Call proctor_apps with action \"list\" to re-read the windows of the attached apps; the window may have closed.")
    }

    func appHandle(forWindow window: WindowHandle) -> AppHandle? { apps[window.app] }

    private func refreshWindows() {
        for appID in apps.keys {
            guard let windows = try? ax.windows(app: appID) else { continue }
            for window in windows { windowsByID[window.id] = window }
        }
    }

    // MARK: - proctor_apps

    func listApps(includeWindowless: Bool) throws -> JSONValue {
        let running = try ax.listApps(includeWindowless: includeWindowless)
        refreshWindows()

        var entries: [JSONValue] = []
        for app in running {
            var obj: [String: JSONValue] = [
                "id": .string(app.id),
                "pid": .number(Double(app.pid)),
                "name": .string(app.name),
                "attached": .bool(apps[app.id] != nil)
            ]
            if let bundleId = app.bundleId { obj["bundleId"] = .string(bundleId) }
            if apps[app.id] != nil {
                let windows = windowsByID.values.filter { $0.app == app.id }
                obj["windows"] = .array(try windows.sorted { $0.id < $1.id }
                                                   .map { try JSONValue.encode($0) })
                if let provenance = provenanceByApp[app.id] {
                    obj["provenance"] = try JSONValue.encode(provenance)
                }
            }
            entries.append(.object(obj))
        }

        return .object([
            "apps": .array(entries),
            "attached": .array(apps.keys.sorted().map { .string($0) }),
            // Enumerating the windows of every running application costs an AX
            // round trip per app and warms trees nobody asked about, so window
            // lists are only returned for what is attached.
            "note": .string("Window handles are listed for attached applications only. Attach an app to see its windows.")
        ])
    }

    func attach(bundleId: String?, pid: Int32?, name: String?) throws -> JSONValue {
        guard bundleId != nil || pid != nil || name != nil else {
            throw AgentError(code: .invalidArguments,
                             message: "attach needs one of bundleId, pid or name",
                             remedy: "Call proctor_apps with action \"list\" to find one.")
        }
        let (app, provenance) = try ax.attach(bundleId: bundleId, pid: pid, name: name)
        apps[app.id] = app
        provenanceByApp[app.id] = provenance

        let windows = (try? ax.windows(app: app.id)) ?? []
        for window in windows { windowsByID[window.id] = window }

        return .object([
            "app": try JSONValue.encode(app),
            "windows": .array(try windows.map { try JSONValue.encode($0) }),
            "provenance": try JSONValue.encode(provenance)
        ])
    }

    func detach(app id: String) throws -> JSONValue {
        guard apps[id] != nil else {
            throw AgentError(code: .appNotFound,
                             message: "\(id) is not attached",
                             remedy: "Call proctor_apps with action \"list\" to see what is attached.")
        }
        try ax.detach(app: id)
        apps.removeValue(forKey: id)
        provenanceByApp.removeValue(forKey: id)
        let dropped = windowsByID.filter { $0.value.app == id }.map(\.key)
        for window in dropped {
            windowsByID.removeValue(forKey: window)
            revisions.removeValue(forKey: window)
            history.removeValue(forKey: window)
        }
        return .object(["detached": .string(id), "windowsReleased": .number(Double(dropped.count))])
    }

    // MARK: - Trees

    /// Walk a window and fold the result into the revision history. The
    /// revision only advances when the tree actually differs, so a caller that
    /// polls does not see motion that did not happen.
    @discardableResult
    func walk(window id: String, options: SnapshotOptions = SnapshotOptions()) throws -> WalkOutcome {
        let (root, provenance) = try ax.snapshot(window: id,
                                                 root: options.root,
                                                 maxDepth: options.maxDepth,
                                                 maxNodes: options.maxNodes,
                                                 includeInvisible: options.includeInvisible)
        let hash = Canonical.hash(root)

        // A walk rooted at a subtree is not the window's state, so it is
        // reported without disturbing the window's revision line.
        guard options.root == nil else {
            return WalkOutcome(root: root, provenance: provenance,
                               revision: revisions[id] ?? 0, hash: hash,
                               previous: nil, history: history[id] ?? [])
        }

        var entries = history[id] ?? []
        let previous = entries.last
        var revision = revisions[id] ?? 0
        if previous?.hash != hash {
            revision += 1
            revisions[id] = revision
            entries.append(TreeRevision(revision: revision, node: root, hash: hash))
            if entries.count > Session.historyDepth {
                entries.removeFirst(entries.count - Session.historyDepth)
            }
            history[id] = entries
        }
        return WalkOutcome(root: root, provenance: provenance, revision: revision,
                           hash: hash, previous: previous, history: entries)
    }

    func snapshot(window id: String, options: SnapshotOptions, sinceRevision: Int?) throws -> Snapshot {
        _ = try windowHandle(id)
        let outcome = try walk(window: id, options: options)

        guard let since = sinceRevision else {
            return Snapshot(window: id, revision: outcome.revision, root: outcome.root,
                            diff: nil, provenance: outcome.provenance, stateHash: outcome.hash)
        }

        // The diff is taken from the retained tree closest to what was asked
        // for, and fromRevision names the one actually used, because a diff
        // against a tree the caller did not ask for is only safe if it says so.
        let base = outcome.history.last { $0.revision <= since } ?? outcome.history.first
        let diff = SnapshotDiffer.diff(from: base?.node, to: outcome.root,
                                       fromRevision: base?.revision ?? 0)
        return Snapshot(window: id, revision: outcome.revision, root: nil, diff: diff,
                        provenance: outcome.provenance, stateHash: outcome.hash)
    }

    func find(window id: String, predicate: FindPredicate, limit: Int) throws -> JSONValue {
        _ = try windowHandle(id)
        let nodes = try ax.find(window: id, predicate: predicate, limit: limit)
        return .object([
            "window": .string(id),
            "predicate": predicate.described,
            "count": .number(Double(nodes.count)),
            "truncated": .bool(nodes.count >= limit),
            "nodes": .array(try nodes.map { try JSONValue.encode($0) })
        ])
    }

    // MARK: - proctor_capture

    func captureWindow(_ id: String, path: String?, waitForComplete: Bool, timeoutMs: Int,
                       scale: Double?, tileHashes: Bool, includeCursor: Bool) async throws -> JSONValue {
        let window = try windowHandle(id)
        let result = try await capture.capture(window: window, to: path,
                                               waitForComplete: waitForComplete,
                                               timeoutMs: timeoutMs, scale: scale,
                                               tileHashes: tileHashes,
                                               includeCursor: includeCursor)
        // Freshness metadata passes through untouched. Rewriting or defaulting
        // any of it would erase the only thing separating a stale frame from a
        // correct one.
        return try JSONValue.encode(result)
    }

    // MARK: - proctor_inspect

    func inspect(window id: String, node: String?, maxDepth: Int,
                 includeConstraints: Bool, presentation: Bool) throws -> JSONValue {
        let window = try windowHandle(id)
        guard let app = apps[window.app] else {
            throw AgentError(code: .appNotFound,
                             message: "the app owning \(id) is no longer attached",
                             remedy: "Re-attach with proctor_apps.")
        }
        guard reflector.isConnected(pid: app.pid) else {
            throw AgentError(
                code: .reflectorUnavailable,
                message: "\(app.name) does not have a ProctorReflector connection",
                remedy: "Embed the ProctorReflector package in the app under test behind #if DEBUG. "
                      + "There is no cross-process equivalent of computed styles on macOS, so for an app "
                      + "you do not own the ceiling is proctor_snapshot plus proctor_capture.")
        }
        let payload = try reflector.inspect(pid: app.pid, window: window, node: node,
                                            maxDepth: maxDepth,
                                            includeConstraints: includeConstraints,
                                            presentation: presentation)
        var out: [String: JSONValue] = ["window": .string(id), "hierarchy": payload]
        if let revision = reflector.renderRevision(pid: app.pid) {
            out["renderRevision"] = .number(Double(revision))
        }
        return .object(out)
    }

    // MARK: - Flow state

    func loadFlowsIfNeeded() {
        guard !flowsLoaded else { return }
        flows = FlowStore.loadAll()
        flowsLoaded = true
    }

    func setRecording(_ name: String?) { recording = name }
    func putFlow(_ flow: RecordedFlow) { flows[flow.name] = flow }
    func removeFlow(_ name: String) { flows.removeValue(forKey: name) }

    // MARK: - Health inputs

    func healthSnapshot() -> (apps: [DoctorReport.AttachedAppHealth], observers: Int) {
        (ax.health(), ax.observersLive)
    }
}
