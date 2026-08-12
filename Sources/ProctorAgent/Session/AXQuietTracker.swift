import Foundation
import ProctorCore

/// The AX half of a settle, held across the polls of one wait.
///
/// `Settler` asks for notifications seen and how long the window has been
/// quiet; AXEngine reports a running count against a mark. Turning one into the
/// other needs somewhere to remember when the count last moved, and that is all
/// this is.
final class AXQuietTracker: @unchecked Sendable {

    private let ax: any AXEngine
    private let app: String
    private let mark: UInt64
    private let available: Bool

    private let lock = NSLock()
    private var lastCount = 0
    private var lastChange = DispatchTime.now().uptimeNanoseconds

    init(ax: any AXEngine, app: String) {
        self.ax = ax
        self.app = app
        self.mark = ax.notificationMark(app: app)
        self.available = ax.health().first { $0.app == app }?.observerAlive ?? false
    }

    /// A negative quietMs is how the AX signal declares itself unavailable.
    /// Counting an app with no live observer as quiet would let a settle claim
    /// agreement between signals when only one of them existed.
    func sample() -> (count: Int, quietMs: Int) {
        guard available else { return (0, -1) }
        let now = DispatchTime.now().uptimeNanoseconds
        lock.lock()
        defer { lock.unlock() }
        let count = ax.notificationCount(app: app, since: mark)
        if count != lastCount {
            lastCount = count
            lastChange = now
        }
        return (count, Int((now &- lastChange) / 1_000_000))
    }
}
