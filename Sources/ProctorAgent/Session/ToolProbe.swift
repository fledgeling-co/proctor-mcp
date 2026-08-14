import Foundation
import ProctorCore

/// Whether Obscura is on this machine, cached, and never executed.
///
/// A reference type rather than a value one, deliberately: a struct's cache forks
/// on every copy, so the actor's copy and any other would answer differently and
/// re-probe independently. One object, one cache, guarded by a lock so it is safe
/// to hand to the `Session` actor at init.
///
/// **The two expiries are different on purpose.** A present answer is held for
/// five minutes; an absent one for fifteen seconds. The state somebody is actively
/// changing is the one worth re-reading, and this feature is what provokes them to
/// change it — so the short absent side is what makes the recommendation come back
/// on its own after the install, without restarting the agent. An uninstall
/// mid-session is not a thing that happens, so the present side can be long. The
/// expiry is measured from the probe, not slid forward on each read.
///
/// `proctor_doctor` calls `refreshed()`, which probes and **writes through**, so
/// after a health check the handoffs and the health report cannot disagree. That
/// is also what the status window's Re-check button drives.
final class ToolProbe: @unchecked Sendable {

    static let presentTTL: Double = 300
    static let absentTTL: Double = 15

    private let probe: @Sendable () -> ToolPresence
    private let now: @Sendable () -> Double
    private let lock = NSLock()
    private var cached: (presence: ToolPresence, at: Double)?

    init(probe: @escaping @Sendable () -> ToolPresence = ToolProbe.obscuraOnDisk,
         now: @escaping @Sendable () -> Double = { Date().timeIntervalSince1970 }) {
        self.probe = probe
        self.now = now
    }

    /// The cached answer when it is still fresh, otherwise a new probe.
    func presence() -> ToolPresence {
        lock.lock()
        if let cached {
            let ttl = cached.presence.available ? Self.presentTTL : Self.absentTTL
            if now() - cached.at < ttl {
                defer { lock.unlock() }
                return cached.presence
            }
        }
        lock.unlock()
        return refreshed()
    }

    /// Probe now, and replace whatever was cached.
    @discardableResult
    func refreshed() -> ToolPresence {
        let fresh = probe()
        let at = now()
        lock.lock()
        cached = (fresh, at)
        lock.unlock()
        return fresh
    }

    // MARK: - The real probe

    /// Reads the filesystem and runs nothing. See `ToolPresence.swift` for why
    /// executing a binary found in a user-writable directory is not on offer.
    static func obscuraOnDisk() -> ToolPresence {
        ToolLocator.locate(binary: ObscuraTool.binary,
                           companions: ObscuraTool.companions,
                           pathEnvironment: ProcessInfo.processInfo.environment["PATH"],
                           home: NSHomeDirectory(),
                           extraDirectories: ObscuraTool.extraDirectories,
                           isExecutable: executableRegularFile)
    }

    /// An executable **regular file**. `FileManager.isExecutableFile` answers true
    /// for a directory carrying the execute bit, so without this a directory named
    /// `obscura` on the path would be reported as the tool.
    static func executableRegularFile(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        let fm = FileManager.default
        guard fm.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue
        else { return false }
        return fm.isExecutableFile(atPath: path)
    }
}
