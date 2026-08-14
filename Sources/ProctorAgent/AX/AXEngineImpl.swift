import Foundation
import AppKit
import ApplicationServices
import ProctorCore

/// The accessibility engine. Stateful on purpose: attachment warms the tree,
/// negotiates AXManualAccessibility where an app needs it, starts observers and
/// retains element refs. The retained refs are the reason the state exists — a
/// retained AXUIElementRef keeps resolving after its window moves to another
/// Space, and a fresh enumeration from the application element does not find it
/// there. Every lookup therefore goes to the cache first.
final class AXEngineImpl: AXEngine, @unchecked Sendable {

    private let lock = NSLock()
    private var sessions: [String: AppSession] = [:]
    private var epochCounter = 0

    init() {}

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    // MARK: - Apps

    func listApps(includeWindowless: Bool) throws -> [AppHandle] {
        let attached = withLock { sessions.values.reduce(into: [pid_t: AppHandle]()) {
            $0[$1.pid] = $1.handle
        } }
        return NSWorkspace.shared.runningApplications.compactMap { app in
            guard includeWindowless || app.activationPolicy == .regular else { return nil }
            let pid = app.processIdentifier
            if let known = attached[pid] { return known }
            return AppHandle(id: "app:\(pid):0", pid: pid,
                             bundleId: app.bundleIdentifier,
                             name: app.localizedName ?? app.bundleIdentifier ?? "pid \(pid)")
        }
    }

    func attach(bundleId: String?, pid: Int32?, name: String?) throws -> (AppHandle, TreeProvenance) {
        guard Grants.accessibility() else {
            throw AgentError(code: .permissionAccessibility,
                             message: "Proctor is not trusted for Accessibility",
                             remedy: Grants.accessibilityFixText(osMajor: osMajor()))
        }
        let app = try resolve(bundleId: bundleId, pid: pid, name: name)
        let appPid = app.processIdentifier

        if let existing = withLock({ sessions.values.first { $0.pid == appPid } }),
           existing.appElementResponds {
            return (existing.handle, existing.attachProvenance)
        }

        let started = Date()
        let element = AXUIElementCreateApplication(appPid)
        AXUIElementSetMessagingTimeout(element, AXTimeout.walk)

        let epoch = withLock { () -> Int in
            epochCounter += 1
            return epochCounter
        }
        let handle = AppHandle(id: "app:\(appPid):\(epoch)", pid: appPid,
                               bundleId: app.bundleIdentifier,
                               name: app.localizedName ?? app.bundleIdentifier ?? "pid \(appPid)")
        let session = AppSession(handle: handle, epoch: epoch, pid: appPid, appElement: element)

        let log = UnsupportedLog()
        var walks = 1
        var windows = AXRead.elements(element, kAXWindowsAttribute, log: log)

        // Chromium and Electron expose nothing until a client sets
        // AXManualAccessibility on the application element, and the first walk
        // after setting it usually still comes back empty.
        let chromium = isChromiumBased(app)
        let needsFlag = chromium
            || treeLooksEmpty(windows, log: log)
            || treeLooksLikeAnUnexposedShell(windows, log: log)
        if needsFlag, CGWindowIndex.hasVisibleWindows(pid: appPid) {
            session.manualAccessibilityApplied =
                AXWrite.set(element, AXAttr.manualAccessibility, kCFBooleanTrue).isSuccess
            session.enhancedUserInterfaceApplied =
                AXWrite.set(element, AXAttr.enhancedUserInterface, kCFBooleanTrue).isSuccess

            for attempt in 2...3 {
                usleep(250_000)
                walks = attempt
                windows = AXRead.elements(element, kAXWindowsAttribute, log: log)
                if !treeLooksEmpty(windows, log: log),
                   !treeLooksLikeAnUnexposedShell(windows, log: log) { break }
            }
        }
        session.warmupWalks = walks

        let observerStarted = AXObservers.start(session: session)
        for window in windows { AXObservers.observe(window: window, in: session) }

        let provenance = TreeProvenance(
            manualAccessibilityApplied: session.manualAccessibilityApplied,
            enhancedUserInterfaceApplied: session.enhancedUserInterfaceApplied,
            warmupWalks: walks,
            unsupportedAttributes: log.sorted,
            elapsedMs: Int(Date().timeIntervalSince(started) * 1000))
        session.attachProvenance = provenance

        withLock { sessions[handle.id] = session }

        if !observerStarted {
            // Not fatal: the coarse diffing poll in the settle layer is the
            // backstop, and health() reports the observer as dead.
            NSLog("proctor: AXObserverCreate failed for pid \(appPid)")
        }
        return (handle, provenance)
    }

    func detach(app: String) throws {
        try withLock {
            guard let session = sessions[app] else {
                throw AgentError(code: .appNotFound, message: "no attached app \(app)")
            }
            AXObservers.stop(session: session)
            session.nodes.removeAll()
            sessions[app] = nil
        }
    }

    // MARK: - Windows

    func windows(app: String) throws -> [WindowHandle] {
        let session = try withLock { try requireSession(app) }
        let elements = AXRead.elements(session.appElement, kAXWindowsAttribute)
        let all = CGWindowIndex.records(option: .optionAll, pid: session.pid)
        let onScreen = Set(CGWindowIndex.records(option: .optionOnScreenOnly, pid: session.pid)
            .map(\.number))

        return withLock {
            session.forgetWindows(keeping: elements)
            return elements.map { element in
                AXUIElementSetMessagingTimeout(element, AXTimeout.walk)
                let id = session.windowId(for: element)
                AXObservers.observe(window: element, in: session)
                let title = AXRead.string(element, kAXTitleAttribute)
                let frame = AXRead.frame(element) ?? Rect(x: 0, y: 0, w: 0, h: 0)
                let cgID = CGWindowIndex.correlate(frame: frame, title: title, in: all)
                return WindowHandle(
                    id: id,
                    app: session.handle.id,
                    title: title,
                    frame: frame,
                    isMain: AXRead.bool(element, kAXMainAttribute) ?? false,
                    isMinimized: AXRead.bool(element, kAXMinimizedAttribute) ?? false,
                    isOnActiveSpace: cgID.map { onScreen.contains($0) } ?? false,
                    cgWindowID: cgID)
            }
        }
    }

    // MARK: - Tree

    func snapshot(window: String, root: String?, maxDepth: Int, maxNodes: Int,
                  includeInvisible: Bool) throws -> (AXNode, TreeProvenance) {
        let (session, element, path) = try withLock { try resolveWalkRoot(window: window, root: root) }
        let started = Date()

        let walker = TreeWalker(windowId: window,
                                budget: .init(maxDepth: max(0, maxDepth),
                                              maxNodes: max(1, maxNodes),
                                              includeInvisible: includeInvisible))
        let node = walker.walk(root: element, rootPath: path)

        withLock { session.nodes.merge(walker.refs) { _, new in new } }

        let provenance = TreeProvenance(
            manualAccessibilityApplied: session.manualAccessibilityApplied,
            enhancedUserInterfaceApplied: session.enhancedUserInterfaceApplied,
            warmupWalks: session.warmupWalks,
            truncatedAtDepth: walker.truncatedAtDepth,
            truncatedAtCount: walker.truncatedAtCount,
            unsupportedAttributes: walker.log.sorted,
            elapsedMs: Int(Date().timeIntervalSince(started) * 1000))
        return (node, provenance)
    }

    /// The canonical hash of a window's current tree, masked and quantised so
    /// two runs of the same flow produce the same string.
    func stateHash(window: String) throws -> String {
        let (root, _) = try snapshot(window: window, root: nil, maxDepth: 64,
                                     maxNodes: 20_000, includeInvisible: false)
        return Canonical.hash(root)
    }

    func find(window: String, predicate: FindPredicate, limit: Int) throws -> [AXNode] {
        let (session, element, path) = try withLock {
            try resolveWalkRoot(window: window, root: nil)
        }
        let walker = TreeWalker(windowId: window,
                                budget: .init(maxDepth: 64, maxNodes: 20_000, includeInvisible: true))
        let root = walker.walk(root: element, rootPath: path)
        withLock { session.nodes.merge(walker.refs) { _, new in new } }

        var out: [AXNode] = []
        for node in root.flattened() where predicate.matches(node) {
            out.append(node.withoutChildren)
            if out.count >= max(1, limit) { break }
        }
        return out
    }

    func node(id: String) throws -> AXNode {
        let ref = try withLock { () -> NodeRef in
            for session in sessions.values {
                if let ref = session.nodes[id] { return ref }
            }
            throw AgentError(code: .nodeNotFound,
                             message: "no cached element for node \(id)",
                             remedy: "Re-snapshot the window; node ids are stable per window per session.")
        }
        var probe: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(ref.element, kAXRoleAttribute as CFString, &probe)
        if err == .invalidUIElement {
            throw AgentError(code: .nodeStale,
                             message: "node \(id) resolved but the element has been invalidated",
                             remedy: "Re-snapshot the window.")
        }
        let walker = TreeWalker(windowId: ref.window,
                                budget: .init(maxDepth: 0, maxNodes: 1, includeInvisible: true))
        return walker.walk(root: ref.element, rootPath: ref.path)
    }

    // MARK: - Web content

    /// The web areas in a window, read in one downward walk.
    ///
    /// Only reached for an application the browser catalogue matched, so the cost
    /// is paid by browsers and by nothing else. The walk stops at each web area
    /// rather than descending into it: a page's interior holds no second web area
    /// worth reading, and descending would pull a whole DOM through the
    /// accessibility API one round trip at a time.
    func webContent(window: String) throws -> WebContentProbe? {
        let (_, element, _) = try withLock { try resolveWalkRoot(window: window, root: nil) }
        var areas: [WebArea] = []
        collectWebAreas(from: element, into: &areas, depth: 0, budget: WebAreaScan())
        return areas.isEmpty ? nil : WebContentProbe(areas: areas)
    }

    private final class WebAreaScan {
        var visited = 0
        let maxNodes = 4_000
        let maxDepth = 40
    }

    private func collectWebAreas(from element: AXUIElement, into areas: inout [WebArea],
                                 depth: Int, budget: WebAreaScan) {
        guard depth <= budget.maxDepth, budget.visited < budget.maxNodes else { return }
        budget.visited += 1

        if AXRead.string(element, kAXRoleAttribute as String) == BrowserTarget.webAreaRole {
            // Safari answers AXURL; some Chromium builds carry it on AXDocument
            // instead, so both are tried before the URL is reported as absent.
            let url = AXRead.url(element, kAXURLAttribute as String)
                ?? AXRead.url(element, kAXDocumentAttribute as String)
            areas.append(WebArea(url: url, frame: AXRead.frame(element)))
            return
        }

        for child in AXRead.elements(element, kAXChildrenAttribute as String) {
            collectWebAreas(from: child, into: &areas, depth: depth + 1, budget: budget)
        }
    }

    // MARK: - Actuation

    func perform(step: ActionStep, window: String, foreground: Bool) throws -> Actuation {
        let target = try withLock { () -> ActuationTarget in
            let session = try sessionOwning(window: window)
            var node: AXUIElement?
            if let requested = step.node {
                guard let ref = session.nodes[requested]
                        ?? sessions.values.compactMap({ $0.nodes[requested] }).first else {
                    throw AgentError(code: .nodeNotFound,
                                     message: "no cached element for node \(requested)",
                                     remedy: "Snapshot or find the window first; ids come from those.")
                }
                node = ref.element
            }
            return ActuationTarget(pid: session.pid,
                                   appElement: session.appElement,
                                   windowElement: session.window(window)?.element,
                                   node: node,
                                   nodeId: step.node)
        }
        return try Actuator.perform(step, target: target, foreground: foreground)
    }

    // MARK: - Menu bar

    func menuBar(app: String) throws -> [RawMenuItem]? {
        // The app element is grabbed under the lock, then read outside it — the
        // menu walk is many AX round trips and must not hold the session lock,
        // mirroring how windows(app:) reads elements after releasing it.
        let element = try withLock { try requireSession(app).appElement }
        return MenuBarReader.read(appElement: element)
    }

    // MARK: - Notifications

    func notificationMark(app: String) -> UInt64 {
        withLock { sessions[app]?.counter.current ?? 0 }
    }

    func notificationCount(app: String, since: UInt64) -> Int {
        let now = withLock { sessions[app]?.counter.current ?? 0 }
        return now >= since ? Int(now - since) : 0
    }

    // MARK: - Health

    func health() -> [DoctorReport.AttachedAppHealth] {
        let snapshot = withLock { Array(sessions.values) }
        return snapshot.map { session in
            let windows = AXRead.elements(session.appElement, kAXWindowsAttribute).count
            return DoctorReport.AttachedAppHealth(
                app: session.handle.id,
                name: session.handle.name,
                windows: windows,
                manualAccessibility: session.manualAccessibilityApplied,
                observerAlive: session.observerAlive,
                cachedRefs: withLock { session.nodes.count },
                reflectorConnected: false)
        }
    }

    var observersLive: Int {
        let snapshot = withLock { Array(sessions.values) }
        return snapshot.filter(\.observerAlive).count
    }

    func windowOf(node: String) -> String? {
        withLock {
            for session in sessions.values {
                if let ref = session.nodes[node] { return ref.window }
            }
            return nil
        }
    }

    // MARK: - Internals

    private func requireSession(_ app: String) throws -> AppSession {
        guard let session = sessions[app] else {
            throw AgentError(code: .appNotFound,
                             message: "no attached app \(app)",
                             remedy: "Call attach first; handles do not survive a relaunch.")
        }
        return session
    }

    private func sessionOwning(window: String) throws -> AppSession {
        for session in sessions.values where session.window(window) != nil { return session }
        // The window may not have been enumerated yet in this session, but its
        // id still names the epoch that minted it.
        let epoch = window.split(separator: ":").dropFirst().first.flatMap { Int($0) }
        if let epoch, let session = sessions.values.first(where: { $0.epoch == epoch }) {
            return session
        }
        throw AgentError(code: .windowNotFound,
                         message: "no attached window \(window)",
                         remedy: "Call windows(app:) to mint window handles.")
    }

    private func resolveWalkRoot(window: String, root: String?)
        throws -> (AppSession, AXUIElement, String?) {
        let session = try sessionOwning(window: window)
        if let root {
            guard let ref = session.nodes[root] else {
                throw AgentError(code: .nodeNotFound,
                                 message: "no cached element for node \(root)")
            }
            return (session, ref.element, ref.path)
        }
        guard let entry = session.window(window) else {
            throw AgentError(code: .windowNotFound,
                             message: "window \(window) has not been enumerated",
                             remedy: "Call windows(app:) first.")
        }
        return (session, entry.element, nil)
    }

    private func treeLooksEmpty(_ windows: [AXUIElement], log: UnsupportedLog) -> Bool {
        guard let first = windows.first else { return true }
        return AXRead.elements(first, kAXChildrenAttribute, log: log).isEmpty
    }

    /// A Chromium window with accessibility off is not empty — it is a native
    /// shell. Slack presents a window with a title bar, three traffic-light
    /// buttons and a handful of groups, and none of the actual interface. An
    /// emptiness test passes it and the flag never gets set, so the shallowness
    /// is measured against the window's size instead: a 1710-point-wide window
    /// with a dozen nodes in it is not a window that has been exposed.
    private func treeLooksLikeAnUnexposedShell(_ windows: [AXUIElement],
                                               log: UnsupportedLog) -> Bool {
        guard let first = windows.first else { return false }
        guard let frame = AXRead.frame(first, log: log), frame.w > 400, frame.h > 300
        else { return false }
        return countDescendants(first, limit: 40, log: log) < 40
    }

    private func countDescendants(_ element: AXUIElement, limit: Int,
                                  log: UnsupportedLog) -> Int {
        var seen = 0
        var stack = [element]
        while let next = stack.popLast(), seen < limit {
            seen += 1
            stack.append(contentsOf: AXRead.elements(next, kAXChildrenAttribute, log: log))
        }
        return seen
    }

    /// Chromium-based apps are identified from the bundle rather than inferred
    /// from the tree, because the tree is exactly what is missing before the
    /// flag is set.
    private func isChromiumBased(_ app: NSRunningApplication) -> Bool {
        guard let url = app.bundleURL else { return false }
        let frameworks = url.appendingPathComponent("Contents/Frameworks")
        let fm = FileManager.default
        for name in ["Electron Framework.framework", "Chromium Framework.framework"] {
            if fm.fileExists(atPath: frameworks.appendingPathComponent(name).path) { return true }
        }
        // Chrome and Edge name their framework after the product.
        if let entries = try? fm.contentsOfDirectory(atPath: frameworks.path) {
            return entries.contains { $0.hasSuffix("Framework.framework")
                && ($0.contains("Chrom") || $0.contains("Edge") || $0.contains("Brave")) }
        }
        return false
    }

    private func resolve(bundleId: String?, pid: Int32?, name: String?) throws -> NSRunningApplication {
        let running = NSWorkspace.shared.runningApplications
        if let bundleId, !bundleId.isEmpty,
           let match = running.first(where: { $0.bundleIdentifier == bundleId }) {
            return match
        }
        if let pid, let match = running.first(where: { $0.processIdentifier == pid }) {
            return match
        }
        if let pid, let match = NSRunningApplication(processIdentifier: pid) { return match }
        if let name, !name.isEmpty {
            if let exact = running.first(where: {
                $0.localizedName?.caseInsensitiveCompare(name) == .orderedSame
            }) { return exact }
            if let partial = running.first(where: {
                $0.localizedName?.range(of: name, options: .caseInsensitive) != nil
            }) { return partial }
        }
        let asked = [bundleId, pid.map(String.init), name].compactMap { $0 }.joined(separator: ", ")
        throw AgentError(code: .appNotFound,
                         message: "no running application matched \(asked.isEmpty ? "an empty query" : asked)",
                         remedy: "Call list_apps to see what is running.")
    }

    private func osMajor() -> Int {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion
    }
}
