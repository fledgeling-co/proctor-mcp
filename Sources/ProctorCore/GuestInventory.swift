import Foundation

// PRO-0058. What a guest is, and how to read one off a provider's own output.
//
// **Everything here is pure.** The caller supplies bytes a CLI already produced;
// this file decides what they mean. The subprocesses live in
// `ProctorAgent/Guest`, which is what makes the parsers, the platform inference
// and the machine construction provable on a machine with neither `lume` nor
// `prlctl` — and, more importantly, what keeps a health check from ever running
// either binary. Detection is a filesystem read (`LumeTool` / `PrlctlTool` go
// through `ToolLocator`); listing a guest is a separate act, gated behind the
// lifecycle tool that has not landed yet.
//
// Proctor owns no VM lifecycle. These types describe what an adapter already
// found. Creating a guest, granting TCC inside one, and cloning the result are
// all things a person does with the provider's own CLI; the grant-once-then-clone
// recipe is documented on the guest lane rather than automated here.

// MARK: - One guest, as a provider describes it

/// One virtual machine, as its provider listed it.
///
/// The provider's own words for the power state travel through `state` rather
/// than being remapped onto an enum of ours: a value this build has not seen
/// survives into the report instead of being flattened into whichever case
/// looked closest. `running` is the one derived boolean a caller can branch on
/// without learning each CLI's vocabulary.
public struct GuestRecord: Codable, Sendable, Equatable {
    /// The name you can type at the provider. For `prlctl` this is the VM name,
    /// not the UUID; the UUID sits in `identifier` when the provider has one.
    public var name: String
    /// Which adapter produced this row — `lume` or `prlctl`. Recorded because
    /// two providers can hold guests of the same name.
    public var provider: String
    /// The provider's own word for the power state: `running`, `stopped`,
    /// `paused`, `suspended`, `invalid`, or whatever else it printed.
    public var state: String
    public var running: Bool
    /// Nil when the listing did not say. A missing platform is not inferred
    /// from the provider: `prlctl` runs Windows and Linux, `lume` runs macOS
    /// and Linux.
    public var platform: MachinePlatform?
    /// The provider's durable id (a Parallels UUID, a lume name when that is
    /// all it has). Optional because lume's listing is name-keyed.
    public var identifier: String?
    public var ip: String?

    public init(name: String, provider: String, state: String, running: Bool,
                platform: MachinePlatform? = nil, identifier: String? = nil,
                ip: String? = nil) {
        self.name = name; self.provider = provider; self.state = state
        self.running = running; self.platform = platform
        self.identifier = identifier; self.ip = ip
    }

    /// The `Machine` this guest is, for every surface PRO-0056 already carries.
    ///
    /// A macOS guest is `native` because a full Proctor can run inside it. Any
    /// other platform — and a listing that did not name one — is `delegated`.
    /// That is the fail-closed direction: a forgotten platform refuses the
    /// tree-reading assertions rather than claiming a frame-status channel it
    /// does not have. Attach (PRO-0060) is what will negotiate the real tier
    /// for a macOS guest that has no agent inside.
    public var machine: Machine {
        Machine(kind: .guest, name: name, provider: provider, platform: platform,
                tier: platform == .macos ? .native : .delegated)
    }
}

/// Whether a provider's own power-state word means the guest is up.
///
/// Known running words only. An unrecognised value is not running: "invalid",
/// "paused", "suspended" and a string this build has never seen are all
/// reasons not to send work there, and the opposite guess would route into a
/// machine that cannot accept it.
public enum GuestPower {
    public static func isRunning(_ state: String) -> Bool {
        switch state.lowercased() {
        case "running", "started", "running_up", "up":
            return true
        default:
            return false
        }
    }
}

/// Which OS a listing is talking about, read from the words the provider used.
///
/// Returns nil rather than a guess when nothing matches. A wrong platform
/// becomes a wrong witness tier, and a wrong tier is how a Linux guest starts
/// answering `agree`.
public enum GuestPlatform {
    public static func infer(os: String?, name: String?) -> MachinePlatform? {
        let hay = [os, name]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "-" }
            .joined(separator: " ")
            .lowercased()
        guard !hay.isEmpty else { return nil }
        // Windows first: "Windows 11" would otherwise be unrecognised, and a
        // name like "Windows Server on Linux" is still a Windows guest.
        if hay.contains("win") { return .windows }
        if hay.contains("linux") || hay.contains("ubuntu") || hay.contains("debian")
            || hay.contains("fedora") || hay.contains("centos") || hay.contains("rhel")
            || hay.contains("alpine") {
            return .linux
        }
        if hay.contains("mac") || hay.contains("darwin") || hay.contains("osx")
            || hay.contains("os x") || hay.contains("sequoia") || hay.contains("sonoma")
            || hay.contains("ventura") || hay.contains("monterey") || hay.contains("tahoe") {
            return .macos
        }
        return nil
    }
}

// MARK: - lume

/// Decode `lume ls --json` (or `lume get --json`).
///
/// The shape is not pinned by a published schema, so this accepts an array, a
/// single object, or an object wrapping the array under `vms` / `machines` /
/// `images` / `items`. A table (header plus rows) is the fallback for a build
/// that printed text instead. Unknown keys are ignored; a row without a name
/// is dropped rather than invented.
public enum LumeInventory {

    public static let provider = LumeTool.binary

    public static func parse(_ data: Data) throws -> [GuestRecord] {
        if data.isEmpty { return [] }
        if let records = try? parseJSON(data) { return records }
        guard let text = String(data: data, encoding: .utf8) else {
            throw GuestParseError.unreadable
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return [] }
        return parseTable(trimmed)
    }

    private static func parseJSON(_ data: Data) throws -> [GuestRecord] {
        let decoded = try JSONSerialization.jsonObject(with: data)
        let rows: [[String: Any]]
        if let array = decoded as? [[String: Any]] {
            rows = array
        } else if let object = decoded as? [String: Any] {
            if let wrapped = object["vms"] as? [[String: Any]]
                ?? object["machines"] as? [[String: Any]]
                ?? object["images"] as? [[String: Any]]
                ?? object["items"] as? [[String: Any]] {
                rows = wrapped
            } else {
                rows = [object]
            }
        } else {
            throw GuestParseError.unexpectedShape
        }
        return rows.compactMap(record(fromJSON:)).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private static func record(fromJSON object: [String: Any]) -> GuestRecord? {
        let name = string(object, "name") ?? string(object, "Name")
        guard let name, !name.isEmpty else { return nil }
        let os = string(object, "os") ?? string(object, "osName")
            ?? string(object, "operatingSystem") ?? string(object, "OS")
        let state = string(object, "status") ?? string(object, "state")
            ?? string(object, "Status") ?? "unknown"
        let ip = blankToNil(string(object, "ip") ?? string(object, "ipAddress")
                            ?? string(object, "address"))
        return GuestRecord(name: name, provider: provider, state: state,
                           running: GuestPower.isRunning(state),
                           platform: GuestPlatform.infer(os: os, name: name),
                           identifier: name, ip: ip)
    }

    /// `NAME  OS  STATUS` (or any order the header names). A line that does not
    /// fit the header is skipped rather than forced into a record.
    static func parseTable(_ text: String) -> [GuestRecord] {
        let lines = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let first = lines.first else { return [] }
        let header = columns(first).map { $0.lowercased() }
        let body: ArraySlice<String>
        if header.contains("name") {
            body = lines.dropFirst()
        } else {
            body = lines[...]
        }
        let nameIndex = header.firstIndex(of: "name") ?? 0
        let osIndex = header.firstIndex(of: "os")
        let stateIndex = header.firstIndex(of: "status") ?? header.firstIndex(of: "state")
        var out: [GuestRecord] = []
        for line in body {
            let cols = columns(line)
            guard nameIndex < cols.count else { continue }
            let name = cols[nameIndex]
            guard !name.isEmpty, name.lowercased() != "name" else { continue }
            let os = osIndex.flatMap { $0 < cols.count ? cols[$0] : nil }
            let state = stateIndex.flatMap { $0 < cols.count ? cols[$0] : nil } ?? "unknown"
            out.append(GuestRecord(name: name, provider: provider, state: state,
                                   running: GuestPower.isRunning(state),
                                   platform: GuestPlatform.infer(os: os, name: name),
                                   identifier: name))
        }
        return out.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}

// MARK: - prlctl

/// Decode `prlctl list -a -j` and `prlctl list -i -j`.
///
/// Measured against Parallels Desktop 26.4.0: the short listing carries
/// `uuid` / `name` / `status` / `ip_configured` (and `dist` when asked for);
/// the info listing carries `ID` / `Name` / `State` / `OS`. Both shapes land
/// here so a caller that picked either flag does not need a second parser.
public enum PrlctlInventory {

    public static let provider = PrlctlTool.binary

    public static func parse(_ data: Data) throws -> [GuestRecord] {
        if data.isEmpty { return [] }
        let decoded = try JSONSerialization.jsonObject(with: data)
        let rows: [[String: Any]]
        if let array = decoded as? [[String: Any]] {
            rows = array
        } else if let object = decoded as? [String: Any] {
            rows = [object]
        } else {
            throw GuestParseError.unexpectedShape
        }
        return rows.compactMap(record(fromJSON:)).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private static func record(fromJSON object: [String: Any]) -> GuestRecord? {
        let name = string(object, "name") ?? string(object, "Name")
        guard let name, !name.isEmpty else { return nil }
        let state = string(object, "status") ?? string(object, "State")
            ?? string(object, "state") ?? "unknown"
        let os = string(object, "OS") ?? string(object, "os")
            ?? string(object, "dist") ?? string(object, "ostemplate")
        let identifier = string(object, "uuid") ?? string(object, "ID")
            ?? string(object, "id")
        let ip = blankToNil(string(object, "ip_configured") ?? string(object, "ip")
                            ?? string(object, "IP_ADDR"))
        return GuestRecord(name: name, provider: provider, state: state,
                           running: GuestPower.isRunning(state),
                           platform: GuestPlatform.infer(os: os, name: name),
                           identifier: identifier, ip: ip)
    }
}

public enum GuestParseError: Error, Equatable {
    case unreadable
    case unexpectedShape
}

// MARK: - The two binaries, as ToolLocator knows them

/// `lume`, Cua's Virtualization.framework CLI. macOS and Linux guests.
///
/// Detection reads the filesystem and executes nothing, exactly as it does for
/// every other tool Proctor knows about. Running it is a separate act, and it
/// happens in the adapter rather than here.
public enum LumeTool {
    public static let binary = "lume"
    public static let docs = "https://github.com/trycua/lume"
    /// The common directories plus the path the project's own installer uses.
    public static let extraDirectories = ToolLocator.commonToolDirectories + ["~/.lume/bin"]
}

/// `prlctl`, Parallels Desktop's CLI. Windows on ARM is why this adapter
/// exists: Parallels uses its own engine there rather than
/// Virtualization.framework, and that path is further along than Cua's
/// experimental QEMU one.
///
/// The binary a person types is a symlink at `/usr/local/bin/prlctl` onto
/// `parallels_wrapper` inside the app bundle. `ToolLocator` finds the symlink
/// by name; it does not have to know about the bundle.
public enum PrlctlTool {
    public static let binary = "prlctl"
    public static let docs = "https://www.parallels.com/products/desktop/resources/"
    public static let extraDirectories = ToolLocator.commonToolDirectories
}

// MARK: - Small decoders

private func string(_ object: [String: Any], _ key: String) -> String? {
    if let value = object[key] as? String { return value }
    if let value = object[key] as? NSNumber { return value.stringValue }
    return nil
}

private func blankToNil(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty || trimmed == "-" { return nil }
    return trimmed
}

private func columns(_ line: String) -> [String] {
    line.split(whereSeparator: { $0 == "\t" || $0 == " " })
        .map(String.init)
        .filter { !$0.isEmpty }
}
