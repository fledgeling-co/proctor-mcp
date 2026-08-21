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

    /// Per-instance, because the two tools do not want the same policy. Obscura's
    /// absent side is short because Proctor is what provokes somebody to install
    /// it; Proctor asks nobody to install browser-use, so there is nothing to poll
    /// for and both of its sides are long.
    let presentTTL: Double
    let absentTTL: Double

    private let probe: @Sendable () -> ToolPresence
    private let now: @Sendable () -> Double
    private let lock = NSLock()
    private var cached: (presence: ToolPresence, at: Double)?

    init(probe: @escaping @Sendable () -> ToolPresence = ToolProbe.obscuraOnDisk,
         now: @escaping @Sendable () -> Double = { Date().timeIntervalSince1970 },
         presentTTL: Double = ToolProbe.presentTTL,
         absentTTL: Double = ToolProbe.absentTTL) {
        self.probe = probe
        self.now = now
        self.presentTTL = presentTTL
        self.absentTTL = absentTTL
    }

    /// The cached answer when it is still fresh, otherwise a new probe.
    func presence() -> ToolPresence {
        lock.lock()
        if let cached {
            let ttl = cached.presence.available ? presentTTL : absentTTL
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

    /// browser-use, the second lane. Same locator, different arguments — no
    /// companions, because it is one console script and what it needs (a Chromium,
    /// a model credential) is not a sibling file.
    static func browserUseOnDisk() -> ToolPresence {
        ToolLocator.locate(binary: BrowserUseTool.binary,
                           companions: BrowserUseTool.companions,
                           pathEnvironment: ProcessInfo.processInfo.environment["PATH"],
                           home: NSHomeDirectory(),
                           extraDirectories: BrowserUseTool.extraDirectories,
                           isExecutable: executableRegularFile)
    }

    /// simctl, which lives inside Xcode rather than on the PATH. Detection is
    /// still a filesystem read and still runs nothing; what differs is where it
    /// looks — the active developer directory rather than a list of bin
    /// directories. See `SimctlLocator` for why following the root-owned
    /// `xcode_select` symlink is safe where following a user-writable path would
    /// not be.
    static func simctlOnDisk() -> ToolPresence {
        SimctlLocator.onDisk()
    }

    /// Maestro, the iOS flow runner. Located the same way as the browser tools
    /// and, like them, never executed: `maestro --version` costs 3.9 to 5.3
    /// seconds because it starts a JVM, which is roughly twice the interval the
    /// status window polls `proctor_doctor` at. The version comes off the install
    /// layout instead, for free.
    static func maestroOnDisk() -> ToolPresence {
        ToolLocator.locate(binary: MaestroTool.binary,
                           companions: [],
                           pathEnvironment: ProcessInfo.processInfo.environment["PATH"],
                           home: NSHomeDirectory(),
                           extraDirectories: MaestroTool.extraDirectories,
                           isExecutable: executableRegularFile)
    }

    /// `cua-driver`, the delegated actuation lane's binary. Located here and
    /// never run here — what a stat cannot answer about it is answered by a
    /// signature read and by whatever preflight already established.
    static func cuaDriverOnDisk() -> ToolPresence {
        ToolLocator.locate(binary: CuaDriverTool.binary,
                           companions: [],
                           pathEnvironment: ProcessInfo.processInfo.environment["PATH"],
                           home: NSHomeDirectory(),
                           extraDirectories: CuaDriverTool.extraDirectories,
                           isExecutable: executableRegularFile)
    }

    /// `lume`, Cua's Virtualization.framework CLI. A filesystem read, never an
    /// execution — listing guests is a separate act, and a health check does
    /// not do it.
    static func lumeOnDisk() -> ToolPresence {
        ToolLocator.locate(binary: LumeTool.binary,
                           companions: [],
                           pathEnvironment: ProcessInfo.processInfo.environment["PATH"],
                           home: NSHomeDirectory(),
                           extraDirectories: LumeTool.extraDirectories,
                           isExecutable: executableRegularFile)
    }

    /// `tart`, Cirrus Labs' Virtualization.framework CLI. Same rule as lume:
    /// a filesystem read, never an execution.
    static func tartOnDisk() -> ToolPresence {
        ToolLocator.locate(binary: TartTool.binary,
                           companions: [],
                           pathEnvironment: ProcessInfo.processInfo.environment["PATH"],
                           home: NSHomeDirectory(),
                           extraDirectories: TartTool.extraDirectories,
                           isExecutable: executableRegularFile)
    }

    /// `prlctl`, Parallels Desktop's CLI. Same rule as lume: a name at a path,
    /// not a verified tool. The symlink at `/usr/local/bin/prlctl` is what a
    /// launchd agent actually finds.
    static func prlctlOnDisk() -> ToolPresence {
        ToolLocator.locate(binary: PrlctlTool.binary,
                           companions: [],
                           pathEnvironment: ProcessInfo.processInfo.environment["PATH"],
                           home: NSHomeDirectory(),
                           extraDirectories: PrlctlTool.extraDirectories,
                           isExecutable: executableRegularFile)
    }

    // MARK: - Versions that cost nothing to read

    /// The target of a symlink, or nil when the path is not one.
    ///
    /// Homebrew writes the version into it — `/opt/homebrew/bin/maestro` points at
    /// `../Cellar/maestro/2.4.0/bin/maestro` — so a `readlink` answers a question
    /// that otherwise costs a JVM start. `Toolchain.versionFromInstallPath`
    /// decides what the target means; this only reads it.
    static func symlinkTarget(_ path: String?) -> String? {
        guard let path else { return nil }
        return try? FileManager.default.destinationOfSymbolicLink(atPath: path)
    }

    /// Xcode's own version, read from the root-owned `version.plist` beside the
    /// developer directory. Nothing is executed, and the file is not one a user
    /// can rewrite.
    ///
    /// Measured on this machine: `CFBundleShortVersionString` 26.6, build 17F113.
    static func xcodeVersion(simctlPath: String?) -> String? {
        // `<developer dir>/usr/bin/simctl` back to `<developer dir>`.
        guard let simctlPath, simctlPath.hasSuffix("/usr/bin/simctl") else { return nil }
        let developerDirectory = String(simctlPath.dropLast("/usr/bin/simctl".count))
        let plist = Toolchain.xcodeVersionPlistPath(developerDirectory: developerDirectory)
        guard let data = FileManager.default.contents(atPath: plist),
              let parsed = try? PropertyListSerialization.propertyList(
                  from: data, options: [], format: nil) as? [String: Any],
              let short = parsed["CFBundleShortVersionString"] as? String
        else { return nil }
        if let build = parsed["ProductBuildVersion"] as? String { return "\(short) (\(build))" }
        return short
    }
}

/// Both browser tools, and the operator's switch, as one object.
///
/// One container rather than two fields on `Session`, and — more importantly —
/// **one place where the environment and the two presences become a gate**.
/// `BrowserLanes.make` is called from here and from nowhere else, because the
/// handoff, `proctor_doctor` and the status window all need that answer, and three
/// readers each interpreting one environment variable and two stat results is
/// three partial copies of one predicate that will disagree.
///
/// The environment is injected. A process's environment is cached at launch, so
/// `setenv` in a test does nothing, and a suite that reaches for `ProcessInfo`
/// lets whichever test ran first decide for the whole process.
final class ToolProbes: Sendable {

    let obscura: ToolProbe
    let browserUse: ToolProbe
    /// Whether this machine has an iOS lane at all. Both TTLs are long: Xcode
    /// does not appear or vanish mid-session, and unlike Obscura, Proctor asks
    /// nobody to install it in the middle of a run.
    let simctl: ToolProbe
    /// The delegated actuation lane's binary, and the iOS flow runner. Both TTLs
    /// long, for the same reason as simctl's: Proctor recommends neither
    /// mid-run, so there is nothing to poll for.
    let cuaDriver: ToolProbe
    let maestro: ToolProbe
    /// Guest-provider CLIs. Both TTLs long: Proctor does not ask anyone to
    /// install either mid-run, so there is nothing to poll for.
    let lume: ToolProbe
    let prlctl: ToolProbe
    let tart: ToolProbe
    /// What `cua-driver`'s code signature says, cached on the file's identity.
    /// Held here beside the presences because it answers the same question they
    /// do — can this be used — and because it is the one part of that answer a
    /// stat cannot give.
    ///
    /// Defaulted to the shared store rather than to a fresh one. A probe set is
    /// built per `Session`, and a verdict is a fact about a file rather than
    /// about a session, so a cache per session is fifteen sessions verifying one
    /// 82 MB binary at once — which is DEF-044, and which starved the cooperative
    /// pool badly enough to take a security witness with it. A test that wants an
    /// isolated store still passes one.
    let cuaSignature: SignatureVerdictCache
    let environment: [String: String]

    init(obscura: ToolProbe = ToolProbe(),
         browserUse: ToolProbe = ToolProbe(probe: ToolProbe.browserUseOnDisk,
                                           presentTTL: ToolProbe.presentTTL,
                                           absentTTL: ToolProbe.presentTTL),
         simctl: ToolProbe = ToolProbe(probe: ToolProbe.simctlOnDisk,
                                       presentTTL: ToolProbe.presentTTL,
                                       absentTTL: ToolProbe.presentTTL),
         cuaDriver: ToolProbe = ToolProbe(probe: ToolProbe.cuaDriverOnDisk,
                                          presentTTL: ToolProbe.presentTTL,
                                          absentTTL: ToolProbe.presentTTL),
         maestro: ToolProbe = ToolProbe(probe: ToolProbe.maestroOnDisk,
                                        presentTTL: ToolProbe.presentTTL,
                                        absentTTL: ToolProbe.presentTTL),
         lume: ToolProbe = ToolProbe(probe: ToolProbe.lumeOnDisk,
                                     presentTTL: ToolProbe.presentTTL,
                                     absentTTL: ToolProbe.presentTTL),
         prlctl: ToolProbe = ToolProbe(probe: ToolProbe.prlctlOnDisk,
                                       presentTTL: ToolProbe.presentTTL,
                                       absentTTL: ToolProbe.presentTTL),
         tart: ToolProbe = ToolProbe(probe: ToolProbe.tartOnDisk,
                                     presentTTL: ToolProbe.presentTTL,
                                     absentTTL: ToolProbe.presentTTL),
         cuaSignature: SignatureVerdictCache = .shared,
         environment: [String: String] = ProctorEnvironment.current) {
        self.obscura = obscura
        self.browserUse = browserUse
        self.simctl = simctl
        self.cuaDriver = cuaDriver
        self.maestro = maestro
        self.lume = lume
        self.prlctl = prlctl
        self.tart = tart
        self.cuaSignature = cuaSignature
        self.environment = environment
    }

    /// What the machine offers right now, from the caches.
    var lanes: BrowserLanes {
        BrowserLanes.make(obscura: obscura.presence(), browserUse: browserUse.presence(),
                          environment: environment)
    }

    /// Probe both and write both through, so a health check leaves the report and
    /// every later handoff describing the same machine.
    @discardableResult
    func refreshBoth() -> (obscura: ToolPresence, browserUse: ToolPresence) {
        (obscura.refreshed(), browserUse.refreshed())
    }
}
