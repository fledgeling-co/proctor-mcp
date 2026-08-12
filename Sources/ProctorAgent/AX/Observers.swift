import Foundation
import ApplicationServices

// AX observers. Two things about them shape this file: the callback is a bare
// C function so state has to travel through the refcon, and the run loop source
// must go on kCFRunLoopCommonModes or the callbacks stop arriving whenever a
// modal loop or a menu tracking loop is running — which is exactly when a UI
// test cares most.

private func proctorAXObserverCallback(_ observer: AXObserver,
                                       _ element: AXUIElement,
                                       _ notification: CFString,
                                       _ refcon: UnsafeMutableRawPointer?) {
    guard let refcon else { return }
    Unmanaged<NotificationCounter>.fromOpaque(refcon).takeUnretainedValue().bump()
}

enum AXObservers {

    static let appNotifications: [String] = [
        kAXWindowCreatedNotification,
        kAXUIElementDestroyedNotification,
        kAXValueChangedNotification,
        kAXFocusedUIElementChangedNotification,
        kAXWindowMovedNotification,
        kAXWindowResizedNotification,
        kAXTitleChangedNotification,
        kAXFocusedWindowChangedNotification,
        kAXMainWindowChangedNotification,
        kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification,
        kAXMenuOpenedNotification,
        kAXMenuClosedNotification,
        kAXSelectedChildrenChangedNotification,
    ]

    static let windowNotifications: [String] = [
        kAXWindowMovedNotification,
        kAXWindowResizedNotification,
        kAXTitleChangedNotification,
        kAXUIElementDestroyedNotification,
        kAXValueChangedNotification,
    ]

    /// Registers on the application element and adds the source to the main run
    /// loop. Returns false when the observer could not be created at all, which
    /// health() then reports rather than hiding.
    @discardableResult
    static func start(session: AppSession) -> Bool {
        guard session.observer == nil else { return true }
        var observer: AXObserver?
        guard AXObserverCreate(session.pid, proctorAXObserverCallback, &observer) == .success,
              let observer else { return false }

        let token = Unmanaged.passUnretained(session.counter)
        session.refconToken = token
        let refcon = token.toOpaque()

        for name in appNotifications {
            _ = AXObserverAddNotification(observer, session.appElement, name as CFString, refcon)
        }

        CFRunLoopAddSource(CFRunLoopGetMain(),
                           AXObserverGetRunLoopSource(observer),
                           CFRunLoopMode.commonModes)

        session.observer = observer
        session.observedElements = [session.appElement]
        return true
    }

    /// Window-scoped notifications, added as windows are discovered. Re-adding an
    /// existing registration returns notificationAlreadyRegistered, which is fine.
    static func observe(window: AXUIElement, in session: AppSession) {
        guard let observer = session.observer, let token = session.refconToken else { return }
        if session.observedElements.contains(where: { CFEqual($0, window) }) { return }
        let refcon = token.toOpaque()
        for name in windowNotifications {
            _ = AXObserverAddNotification(observer, window, name as CFString, refcon)
        }
        session.observedElements.append(window)
    }

    static func stop(session: AppSession) {
        guard let observer = session.observer else { return }
        for element in session.observedElements {
            let names = CFEqual(element, session.appElement) ? appNotifications : windowNotifications
            for name in names {
                _ = AXObserverRemoveNotification(observer, element, name as CFString)
            }
        }
        CFRunLoopRemoveSource(CFRunLoopGetMain(),
                              AXObserverGetRunLoopSource(observer),
                              CFRunLoopMode.commonModes)
        session.observer = nil
        session.observedElements = []
        session.refconToken = nil
    }
}
