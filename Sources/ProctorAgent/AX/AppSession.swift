import Foundation
import ApplicationServices
import ProctorCore

/// Bumped from the AXObserver callback, which runs on whichever run loop the
/// observer source was added to, so the counter carries its own lock.
final class NotificationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value: UInt64 = 0

    func bump() {
        lock.lock()
        value &+= 1
        lock.unlock()
    }

    var current: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

/// A retained element plus where it sits. The retain is the point: an
/// AXUIElementRef keeps resolving after its window moves to another Space,
/// whereas re-enumerating from the application element will not find it there.
struct NodeRef {
    var element: AXUIElement
    var window: String
    var path: String
}

struct WindowEntry {
    var id: String
    var element: AXUIElement
    var ordinal: Int
}

/// Everything the engine holds for one attached application. Guarded by the
/// engine's lock; nothing in here is safe to touch concurrently.
final class AppSession {
    let handle: AppHandle
    let epoch: Int
    let pid: pid_t
    let appElement: AXUIElement
    let counter = NotificationCounter()

    var manualAccessibilityApplied = false
    var enhancedUserInterfaceApplied = false
    var warmupWalks = 1
    var attachProvenance = TreeProvenance()

    var observer: AXObserver?
    var observedElements: [AXUIElement] = []
    var refconToken: Unmanaged<NotificationCounter>?

    var windows: [String: WindowEntry] = [:]
    var nextOrdinal = 0
    var nodes: [String: NodeRef] = [:]

    init(handle: AppHandle, epoch: Int, pid: pid_t, appElement: AXUIElement) {
        self.handle = handle
        self.epoch = epoch
        self.pid = pid
        self.appElement = appElement
    }

    /// Ordinals are allocated once per window and kept for the life of the
    /// session, so a handle stays valid while other windows open and close.
    func windowId(for element: AXUIElement) -> String {
        for (_, entry) in windows where CFEqual(entry.element, element) {
            return entry.id
        }
        let ordinal = nextOrdinal
        nextOrdinal += 1
        let id = "win:\(epoch):\(ordinal)"
        windows[id] = WindowEntry(id: id, element: element, ordinal: ordinal)
        return id
    }

    func window(_ id: String) -> WindowEntry? { windows[id] }

    func forgetWindows(keeping live: [AXUIElement]) {
        windows = windows.filter { _, entry in
            live.contains { CFEqual($0, entry.element) }
        }
    }

    /// The application element still answering is the only honest liveness test:
    /// observers die silently when their element is invalidated.
    var appElementResponds: Bool {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(appElement, kAXRoleAttribute as CFString, &value)
        return err == .success || err == .noValue
    }

    var observerAlive: Bool {
        guard let observer else { return false }
        let source = AXObserverGetRunLoopSource(observer)
        return CFRunLoopSourceIsValid(source) && appElementResponds
    }
}
