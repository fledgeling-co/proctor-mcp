import Foundation

/// A handle for one unit of app-declared work. An app that knows it is busy —
/// a network fetch, a document open, a long render — can say so, and the idle
/// signal becomes the app's own answer rather than an outside guess.
public struct ActivityToken: Sendable, Hashable {
    public let name: String
    let serial: UInt64
    init(name: String, serial: UInt64) {
        self.name = name
        self.serial = serial
    }
}

/// In-process view and layer reflection for an app you own.
///
/// Adopt it in one line from `applicationDidFinishLaunching`. It binds a Unix
/// domain socket and answers `hierarchy`, `node`, `idle`, `revision` and `ping`
/// over 4-byte big-endian length-prefixed JSON.
///
/// The whole implementation is compiled only under `DEBUG` or the
/// `PROCTOR_REFLECTOR` flag. A release build with neither carries no socket, no
/// observers and no display link — `start()` returns immediately.
///
/// SwiftUI: `NSHostingView` subtrees are walked as ordinary `NSView`s, so you
/// see the hosting view and whatever AppKit backing views SwiftUI happens to
/// create. That is not SwiftUI introspection — there is no supported way to read
/// resolved SwiftUI modifier values from outside the framework, and this package
/// does not pretend otherwise.
public enum ProctorReflector {

    /// Where a reflector for this process binds by default. The agent discovers
    /// reflectors by scanning this directory for `reflector-*.sock` and matching
    /// the pid, so the file name is part of the contract.
    public static var defaultSocketPath: String {
        "\(supportDirectory)/reflector-\(ProcessInfo.processInfo.processIdentifier).sock"
    }

    static var supportDirectory: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/Application Support/app.fledgeling.procter"
    }

    /// Protocol version carried in every `ping` reply.
    public static let protocolVersion = 1

    #if DEBUG || PROCTOR_REFLECTOR

    public static func start(socketPath: String? = nil) {
        Runtime.shared.start(socketPath: socketPath ?? defaultSocketPath)
    }

    public static func stop() {
        Runtime.shared.stop()
    }

    public static var isRunning: Bool {
        Runtime.shared.isRunning
    }

    public static func beginActivity(_ name: String) -> ActivityToken {
        Runtime.shared.beginActivity(name)
    }

    public static func endActivity(_ token: ActivityToken) {
        Runtime.shared.endActivity(token)
    }

    public static var isIdle: Bool {
        Runtime.shared.isIdle()
    }

    #else

    /// No-op. This build was compiled without `DEBUG` or `PROCTOR_REFLECTOR`,
    /// so no socket is created and no observers are registered.
    public static func start(socketPath: String? = nil) {}

    public static func stop() {}

    public static var isRunning: Bool { false }

    public static func beginActivity(_ name: String) -> ActivityToken {
        ActivityToken(name: name, serial: 0)
    }

    public static func endActivity(_ token: ActivityToken) {}

    /// Always true in an inert build. Nothing is tracked, so nothing is in
    /// flight; check `isRunning` before reading this as a measurement.
    public static var isIdle: Bool { true }

    #endif
}
