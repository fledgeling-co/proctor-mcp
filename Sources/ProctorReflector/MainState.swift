#if DEBUG || PROCTOR_REFLECTOR

import AppKit
import QuartzCore

/// Main-thread state: which layers the last walk saw, the render-revision
/// counter, and the idle computation. Everything here touches AppKit, so
/// everything here is main-actor isolated.
@MainActor
final class MainState: NSObject {
    static let shared = MainState()

    private var layers = NSHashTable<CALayer>.weakObjects()
    private var displayLink: CADisplayLink?
    private var observer: NSObjectProtocol?
    private var quietTicks = 0

    /// The display link stops itself after this many consecutive frames with
    /// nothing in flight. A reflector that woke the app every frame forever
    /// would be a battery cost the host app did not ask for.
    private static let quietTicksBeforePausing = 120

    private override init() { super.init() }

    // MARK: - Lifecycle

    func startObserving() {
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didUpdateNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                MainState.shared.bump()
            }
        }
        if displayLink == nil, let screen = NSScreen.main {
            let link = screen.displayLink(target: self, selector: #selector(tick))
            link.add(to: .main, forMode: .common)
            link.isPaused = true
            displayLink = link
        }
    }

    func stopObserving() {
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
        displayLink?.invalidate()
        displayLink = nil
        layers.removeAllObjects()
        quietTicks = 0
    }

    // MARK: - Tracking

    func track(layers newLayers: [CALayer]) {
        layers.removeAllObjects()
        for layer in newLayers.prefix(4096) { layers.add(layer) }
        wake()
    }

    private func wake() {
        quietTicks = 0
        displayLink?.isPaused = false
    }

    private func bump() {
        Runtime.shared.incrementRevision()
        wake()
    }

    @objc private func tick(_ link: CADisplayLink) {
        if anyLayerInFlight() {
            Runtime.shared.incrementRevision()
            quietTicks = 0
        } else {
            quietTicks += 1
            if quietTicks >= Self.quietTicksBeforePausing {
                link.isPaused = true
            }
        }
    }

    // MARK: - Idle

    /// A layer counts as in flight when CoreAnimation still holds animations for
    /// it, or when its presentation copy has not caught up with its model value.
    func anyLayerInFlight() -> Bool {
        for layer in layers.allObjects {
            if !(layer.animationKeys() ?? []).isEmpty { return true }
            guard let presented = layer.presentation() else { continue }
            if !presentationMatchesModel(presented, layer) { return true }
        }
        return false
    }

    private func presentationMatchesModel(_ presented: CALayer, _ model: CALayer) -> Bool {
        let eps = Walker.epsilon
        func close(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(Double(a - b)) <= eps }
        return abs(Double(presented.opacity - model.opacity)) <= eps
            && close(presented.bounds.width, model.bounds.width)
            && close(presented.bounds.height, model.bounds.height)
            && close(presented.position.x, model.position.x)
            && close(presented.position.y, model.position.y)
            && close(presented.cornerRadius, model.cornerRadius)
            && close(presented.borderWidth, model.borderWidth)
            && CATransform3DEqualToTransform(presented.transform, model.transform)
    }

    func pendingLayout() -> Bool {
        for window in NSApplication.shared.windows {
            if window.viewsNeedDisplay { return true }
            if let content = window.contentView, content.needsLayout { return true }
        }
        return false
    }

    /// Idle is a conjunction of three independent claims, and each one can be
    /// wrong on its own: the app says it is not busy, CoreAnimation says nothing
    /// is moving, and AppKit says nothing is waiting to lay out.
    func idleNow() -> Bool {
        Runtime.shared.activityCount == 0 && !anyLayerInFlight() && !pendingLayout()
    }

    func idleReport() -> JSONValue {
        let activities = Runtime.shared.activityNames
        let animating = anyLayerInFlight()
        let layout = pendingLayout()
        return .object([
            "idle": .bool(activities.isEmpty && !animating && !layout),
            "activities": .array(activities.map { JSONValue.string($0) }),
            "activityCount": JSONValue.num(activities.count),
            "layersInFlight": .bool(animating),
            "trackedLayers": JSONValue.num(layers.count),
            "pendingLayout": .bool(layout),
            "revision": JSONValue.num(Runtime.shared.revision)
        ])
    }
}

#endif
