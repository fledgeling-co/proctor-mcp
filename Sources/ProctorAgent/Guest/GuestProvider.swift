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
