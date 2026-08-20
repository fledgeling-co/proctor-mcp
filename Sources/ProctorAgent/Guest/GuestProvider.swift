import Foundation
import ProctorCore

// PRO-0058. The seam a guest is reached through.
//
// Modelled on `ActuationBackend`: one protocol, two adapters, and the
// production types are the only ones that create a process. Everything a
// test needs to prove — parsing, platform inference, argument shape, the
// refusal when a binary is missing — is injectable. The adapters own no
// lifecycle policy. They translate `list` / `status` / `start` / `stop` /
// `clone` into the argv the provider already documents, then hand the
// bytes to the pure parsers in `GuestInventory`.
//
// **Nothing here is called from `proctor_doctor`.** Detection is a
// filesystem read in `ToolProbe`. A health check that listed guests would
// be a side-effect channel on the first call the Proctor skill tells a
// model to make, and it would start two CLIs on every status-window poll.

/// One provider's answer for the guests it knows about.
protocol GuestProvider: AnyObject, Sendable {
    /// `lume` or `prlctl`. Matches `GuestRecord.provider` and `Machine.provider`.
    var id: String { get }

    func list() async throws -> [GuestRecord]
    func status(name: String) async throws -> GuestRecord
    func start(name: String) async throws -> GuestRecord
    func stop(name: String) async throws -> GuestRecord
    func clone(name: String, as newName: String) async throws -> GuestRecord
}

/// What a bounded child returned, stripped of the iOS-lane type name.
struct GuestProcessResult: Sendable {
    var exitCode: Int32
    var stdout: Data
    var stderr: String
    var timedOut: Bool
    var truncated: Bool
}

enum GuestProviderError: Error, Equatable {
    case binaryMissing(tool: String)
    case commandFailed(tool: String, action: String, exit: Int32, stderr: String)
    case unparseable(tool: String, reason: String)
    case notFound(name: String, provider: String)
    case timedOut(tool: String, action: String)
    case truncated(tool: String, action: String)
}

// MARK: - lume

/// Cua's Virtualization.framework CLI.
///
/// Argument shape, measured against lume's published surface rather than
/// against a binary on this machine (there is not one): `ls --json` for the
/// inventory, `get <name> --json` for one guest, `run` / `stop` / `clone`.
/// A build that uses `list` instead of `ls` is tried once, on the first
/// listing, and only after `ls` itself refused.
final class LumeProvider: GuestProvider {

    let id = LumeTool.binary
    private let executable: String
    private let run: @Sendable (String, [String], Int) -> GuestProcessResult
    private let timeoutMs: Int

    init(executable: String,
         timeoutMs: Int = 15_000,
         run: @escaping @Sendable (String, [String], Int) -> GuestProcessResult) {
        self.executable = executable
        self.timeoutMs = timeoutMs
        self.run = run
    }

    convenience init(executable: String, timeoutMs: Int = 15_000) {
        self.init(executable: executable, timeoutMs: timeoutMs, run: Self.liveRun)
    }

    func list() async throws -> [GuestRecord] {
        let first = invoke(["ls", "--json"], action: "list")
        if first.exitCode == 0 {
            return try decodeList(first)
        }
        let second = invoke(["list", "--json"], action: "list")
        if second.exitCode == 0 {
            return try decodeList(second)
        }
        throw GuestProviderError.commandFailed(tool: id, action: "list",
                                               exit: first.exitCode, stderr: first.stderr)
    }

    func status(name: String) async throws -> GuestRecord {
        let result = invoke(["get", name, "--json"], action: "status")
        if result.exitCode == 0 {
            let records = try decodeList(result)
            if let match = records.first(where: { $0.name == name }) ?? records.first {
                return match
            }
        }
        // A get that the build does not have: fall back to the inventory.
        let all = try await list()
        guard let match = all.first(where: { $0.name == name }) else {
            throw GuestProviderError.notFound(name: name, provider: id)
        }
        return match
    }

    func start(name: String) async throws -> GuestRecord {
        try await runMutating(["run", name], action: "start", name: name)
    }

    func stop(name: String) async throws -> GuestRecord {
        try await runMutating(["stop", name], action: "stop", name: name)
    }

    func clone(name: String, as newName: String) async throws -> GuestRecord {
        let result = invoke(["clone", name, newName], action: "clone")
        try throwIfFailed(result, action: "clone")
        return try await status(name: newName)
    }

    private func runMutating(_ arguments: [String], action: String,
                             name: String) async throws -> GuestRecord {
        let result = invoke(arguments, action: action)
        try throwIfFailed(result, action: action)
        return try await status(name: name)
    }

    private func invoke(_ arguments: [String], action: String) -> GuestProcessResult {
        run(executable, arguments, timeoutMs)
    }

    private func decodeList(_ result: GuestProcessResult) throws -> [GuestRecord] {
        if result.truncated {
            throw GuestProviderError.truncated(tool: id, action: "list")
        }
        do {
            return try LumeInventory.parse(result.stdout)
        } catch {
            throw GuestProviderError.unparseable(tool: id, reason: "lume output was not a listing")
        }
    }

    private func throwIfFailed(_ result: GuestProcessResult, action: String) throws {
        if result.timedOut { throw GuestProviderError.timedOut(tool: id, action: action) }
        if result.truncated { throw GuestProviderError.truncated(tool: id, action: action) }
        if result.exitCode != 0 {
            throw GuestProviderError.commandFailed(tool: id, action: action,
                                                   exit: result.exitCode, stderr: result.stderr)
        }
    }

    private static func liveRun(_ path: String, _ arguments: [String],
                                _ timeoutMs: Int) -> GuestProcessResult {
        let run = Session.runBounded(path, arguments, timeoutMs: timeoutMs)
        return GuestProcessResult(exitCode: run.exitCode, stdout: run.stdout,
                                  stderr: run.stderr, timedOut: run.timedOut,
                                  truncated: run.truncated)
    }
}

// MARK: - prlctl

/// Parallels Desktop's CLI. Windows on ARM is the reason this adapter exists
/// beside lume rather than as a fallback for it.
///
/// Listing uses `list -a -j` (measured on 26.4.0: an array of
/// `{uuid, name, status, ip_configured}` objects). Info listings (`-i -j`)
/// parse through the same decoder because the field names differ and the
/// parser already accepts both.
final class PrlctlProvider: GuestProvider {

    let id = PrlctlTool.binary
    private let executable: String
    private let run: @Sendable (String, [String], Int) -> GuestProcessResult
    private let timeoutMs: Int

    init(executable: String,
         timeoutMs: Int = 15_000,
         run: @escaping @Sendable (String, [String], Int) -> GuestProcessResult) {
        self.executable = executable
        self.timeoutMs = timeoutMs
        self.run = run
    }

    convenience init(executable: String, timeoutMs: Int = 15_000) {
        self.init(executable: executable, timeoutMs: timeoutMs, run: Self.liveRun)
    }

    func list() async throws -> [GuestRecord] {
        let result = invoke(["list", "-a", "-j"], action: "list")
        try throwIfFailed(result, action: "list")
        return try decodeList(result)
    }

    func status(name: String) async throws -> GuestRecord {
        // `-n` restricts the listing to that name. A name with spaces is one
        // argument; Process already preserves that.
        let result = invoke(["list", "-n", name, "-j"], action: "status")
        if result.exitCode == 0, let match = try? decodeList(result).first(where: { $0.name == name }) {
            return match
        }
        let all = try await list()
        guard let match = all.first(where: { $0.name == name }) else {
            throw GuestProviderError.notFound(name: name, provider: id)
        }
        return match
    }

    func start(name: String) async throws -> GuestRecord {
        try await runMutating(["start", name], action: "start", name: name)
    }

    func stop(name: String) async throws -> GuestRecord {
        try await runMutating(["stop", name], action: "stop", name: name)
    }

    func clone(name: String, as newName: String) async throws -> GuestRecord {
        let result = invoke(["clone", name, "--name", newName], action: "clone")
        try throwIfFailed(result, action: "clone")
        return try await status(name: newName)
    }

    private func runMutating(_ arguments: [String], action: String,
                             name: String) async throws -> GuestRecord {
        let result = invoke(arguments, action: action)
        try throwIfFailed(result, action: action)
        return try await status(name: name)
    }

    private func invoke(_ arguments: [String], action: String) -> GuestProcessResult {
        run(executable, arguments, timeoutMs)
    }

    private func decodeList(_ result: GuestProcessResult) throws -> [GuestRecord] {
        if result.truncated {
            throw GuestProviderError.truncated(tool: id, action: "list")
        }
        do {
            return try PrlctlInventory.parse(result.stdout)
        } catch {
            throw GuestProviderError.unparseable(tool: id, reason: "prlctl output was not a listing")
        }
    }

    private func throwIfFailed(_ result: GuestProcessResult, action: String) throws {
        if result.timedOut { throw GuestProviderError.timedOut(tool: id, action: action) }
        if result.truncated { throw GuestProviderError.truncated(tool: id, action: action) }
        if result.exitCode != 0 {
            throw GuestProviderError.commandFailed(tool: id, action: action,
                                                   exit: result.exitCode, stderr: result.stderr)
        }
    }

    private static func liveRun(_ path: String, _ arguments: [String],
                                _ timeoutMs: Int) -> GuestProcessResult {
        let run = Session.runBounded(path, arguments, timeoutMs: timeoutMs)
        return GuestProcessResult(exitCode: run.exitCode, stdout: run.stdout,
                                  stderr: run.stderr, timedOut: run.timedOut,
                                  truncated: run.truncated)
    }
}

// MARK: - tart

/// Cirrus Labs' Virtualization.framework CLI, and the only provider on this
/// machine with a working macOS guest — which is what makes PRO-0076's attach
/// measurable rather than carried.
///
/// Argument shape measured against tart 2.32.1 on 2026-08-20 rather than read
/// from its docs: `list --format json`, `get <name> --format json`, `run`,
/// `stop`, `clone <src> <dst>`.
///
/// **Two things differ from the other two adapters, and each is forced by tart
/// rather than chosen.**
///
/// `list` does not print `OS`, so every row is enriched with a `get` to learn
/// its platform. That costs one extra process per guest and it buys the one
/// fact PRO-0076's cap is derived from. A `get` that fails leaves the platform
/// nil, and a guest whose platform could not be read is refused at attach
/// rather than admitted uncounted — nil is fail-closed for actuation and
/// fail-OPEN for the cap, so it cannot be allowed to reach the pool.
///
/// `tart run` is a foreground process that lives as long as the VM does, where
/// `lume run` returns. So `start` launches it detached and polls `get` for
/// `Running: true`. **A poll that times out stops what it launched** before
/// reporting the timeout: leaving it up would orphan a macOS guest that is
/// running, uncounted and unowned, which would make the cap, the start record
/// and the never-evict rule all false at once. Stopping is permitted there for
/// the same reason it is at detach — this agent started it.
final class TartProvider: GuestProvider {

    let id = TartTool.binary
    private let executable: String
    private let run: @Sendable (String, [String], Int) -> GuestProcessResult
    /// Launch and leave. Separate from `run` because a bounded run cannot
    /// express a process that is meant to outlive the call.
    private let spawn: @Sendable (String, [String]) -> Void
    private let sleep: @Sendable (Int) async -> Void
    private let timeoutMs: Int
    /// How long `start` waits for the guest to report itself up. A cold macOS
    /// guest takes tens of seconds; this is generous rather than tight because
    /// the failure it guards is a boot that never happens, not a slow one.
    private let startTimeoutMs: Int
    private let pollIntervalMs: Int

    init(executable: String,
         timeoutMs: Int = 15_000,
         startTimeoutMs: Int = 180_000,
         pollIntervalMs: Int = 2_000,
         run: @escaping @Sendable (String, [String], Int) -> GuestProcessResult,
         spawn: @escaping @Sendable (String, [String]) -> Void,
         sleep: @escaping @Sendable (Int) async -> Void) {
        self.executable = executable
        self.timeoutMs = timeoutMs
        self.startTimeoutMs = startTimeoutMs
        self.pollIntervalMs = pollIntervalMs
        self.run = run
        self.spawn = spawn
        self.sleep = sleep
    }

    convenience init(executable: String, timeoutMs: Int = 15_000) {
        self.init(executable: executable, timeoutMs: timeoutMs,
                  run: Self.liveRun, spawn: Self.liveSpawn,
                  sleep: { ms in try? await Task.sleep(nanoseconds: UInt64(max(ms, 0)) * 1_000_000) })
    }

    func list() async throws -> [GuestRecord] {
        let result = invoke(["list", "--format", "json"], action: "list")
        try throwIfFailed(result, action: "list")
        let rows = try decodeList(result)
        // The listing does not say which OS, and the cap is derived from that,
        // so each row is enriched. A get that fails leaves the platform absent
        // rather than guessing from the name.
        var out: [GuestRecord] = []
        out.reserveCapacity(rows.count)
        for row in rows {
            var record = row
            record.platform = platform(of: row.name)
            out.append(record)
        }
        return out
    }

    func status(name: String) async throws -> GuestRecord {
        let all = try await list()
        guard let match = all.first(where: { $0.name == name }) else {
            throw GuestProviderError.notFound(name: name, provider: id)
        }
        return match
    }

    func start(name: String) async throws -> GuestRecord {
        let existing = try await status(name: name)
        if existing.running { return existing }

        spawn(executable, ["run", name])

        var waited = 0
        while waited < startTimeoutMs {
            await sleep(pollIntervalMs)
            waited += pollIntervalMs
            let probe = invoke(["get", name, "--format", "json"], action: "start")
            if probe.exitCode == 0, TartInventory.isRunning(fromGet: probe.stdout) {
                return try await status(name: name)
            }
        }

        // It never came up. Stop what was launched rather than leaving a macOS
        // guest running that nothing is counting and nothing owns.
        _ = invoke(["stop", name], action: "start")
        throw GuestProviderError.timedOut(tool: id, action: "start")
    }

    func stop(name: String) async throws -> GuestRecord {
        let result = invoke(["stop", name], action: "stop")
        try throwIfFailed(result, action: "stop")
        return try await status(name: name)
    }

    func clone(name: String, as newName: String) async throws -> GuestRecord {
        let result = invoke(["clone", name, newName], action: "clone")
        try throwIfFailed(result, action: "clone")
        return try await status(name: newName)
    }

    /// One guest's platform, from `get` and from nothing else.
    private func platform(of name: String) -> MachinePlatform? {
        let result = invoke(["get", name, "--format", "json"], action: "status")
        guard result.exitCode == 0, !result.truncated else { return nil }
        return TartInventory.platform(fromGet: result.stdout)
    }

    private func invoke(_ arguments: [String], action: String) -> GuestProcessResult {
        run(executable, arguments, timeoutMs)
    }

    private func decodeList(_ result: GuestProcessResult) throws -> [GuestRecord] {
        if result.truncated {
            throw GuestProviderError.truncated(tool: id, action: "list")
        }
        do {
            return try TartInventory.parse(result.stdout)
        } catch {
            throw GuestProviderError.unparseable(tool: id, reason: "tart output was not a listing")
        }
    }

    private func throwIfFailed(_ result: GuestProcessResult, action: String) throws {
        if result.timedOut { throw GuestProviderError.timedOut(tool: id, action: action) }
        if result.truncated { throw GuestProviderError.truncated(tool: id, action: action) }
        if result.exitCode != 0 {
            throw GuestProviderError.commandFailed(tool: id, action: action,
                                                   exit: result.exitCode, stderr: result.stderr)
        }
    }

    private static func liveRun(_ path: String, _ arguments: [String],
                                _ timeoutMs: Int) -> GuestProcessResult {
        let run = Session.runBounded(path, arguments, timeoutMs: timeoutMs)
        return GuestProcessResult(exitCode: run.exitCode, stdout: run.stdout,
                                  stderr: run.stderr, timedOut: run.timedOut,
                                  truncated: run.truncated)
    }

    /// Launch and return. The child outlives this call by design — it is the VM.
    private static func liveSpawn(_ path: String, _ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        try? process.run()
    }
}
