import Foundation
import ProctorCore

/// The reflector fallback, used whenever the app under test does not embed
/// ProctorReflector. It reports absence rather than approximating: there is no
/// cross-process equivalent of computed styles on macOS, and a guessed value
/// returned in the shape of a measurement is worse than no value at all.
final class NullReflectorBridge: ReflectorBridge {
    init() {}

    func isConnected(pid: Int32) -> Bool { false }

    func inspect(pid: Int32, window: WindowHandle, node: String?, maxDepth: Int,
                 includeConstraints: Bool, presentation: Bool) throws -> JSONValue {
        throw AgentError(
            code: .reflectorUnavailable,
            message: "no ProctorReflector is embedded in pid \(pid), so resolved styles and layer geometry cannot be read",
            remedy: "Add the ProctorReflector package to the app under test behind #if DEBUG. "
                  + "For an app you do not own, the ceiling is proctor_snapshot plus proctor_capture.")
    }

    func isIdle(pid: Int32) -> Bool? { nil }

    func renderRevision(pid: Int32) -> Int? { nil }
}
