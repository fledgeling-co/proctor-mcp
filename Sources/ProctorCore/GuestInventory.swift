import Foundation

// PRO-0058. What a guest is, and how to read one off a provider's own output.
//
// **Everything here is pure.** The caller supplies bytes a CLI already produced;
// this file decides what they mean. The subprocesses live in
// `ProctorAgent/Guest`, which is what makes the parsers, the platform inference
// and the machine construction provable on a machine with neither `lume` nor
// `prlctl` — and, more importantly, what keeps a health check from ever running
// either binary. Detection is a filesystem read (`LumeTool` / `PrlctlTool` go
// through `ToolLocator`); listing a guest is a separate act, gated behind
// `proctor_guest`.
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
    /// The handle a caller holds. Stored so it travels on the wire. Deliberately
    /// not the shape of a window or device handle: the prefix is what every
    /// window-taking tool matches on to refuse it by name.
    public var handle: String

    public init(name: String, provider: String, state: String, running: Bool,
                platform: MachinePlatform? = nil, identifier: String? = nil,
                ip: String? = nil) {
        self.name = name; self.provider = provider; self.state = state
        self.running = running; self.platform = platform
        self.identifier = identifier; self.ip = ip
        self.handle = GuestHandle.id(provider: provider, name: name)
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

/// The guest-handle namespace, and the refusal that goes with it.
///
/// Proctor's whole model is windows, and a guest is a different machine.
/// Rather than dress one up as the other, a guest gets its own handle shape
/// and every window-taking tool refuses it *by name*. The refusal is the
/// load-bearing part: a model that believes it can snapshot a guest because
/// it holds a handle would otherwise waste a campaign discovering otherwise
/// one call at a time.
public enum GuestHandle {

    public static let prefix = "gst-"

    /// Stable across listings of the same (provider, name). A hash rather
    /// than the name itself, because Parallels names carry spaces and two
    /// providers can hold guests of the same name.
    public static func id(provider: String, name: String) -> String {
        prefix + fnv1a(provider + "\u{0}" + name)
    }

    public static func isGuestHandle(_ id: String) -> Bool {
        id.hasPrefix(prefix)
    }

    public static func rejection(handle: String, tool: String) -> (message: String, remedy: String) {
        (message: "\(handle) is a guest handle and \(tool) needs a macOS window handle",
         remedy: "A guest is a different machine. Observation and actuation against it "
               + "go through the Proctor (or Cua) running inside it, not through a window "
               + "handle on this Mac. What is available: proctor_guest action \"list\" / "
               + "\"status\" / \"start\" / \"stop\" / \"clone\". Window handles come from "
               + "proctor_apps, on the machine the session is attached to.")
    }

    /// FNV-1a 64-bit, lowercase hex. Deterministic, no Foundation crypto, and
    /// short enough to read in a result.
    static func fnv1a(_ seed: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }
}

public enum GuestParseError: Error, Equatable {
    case unreadable
    case unexpectedShape
}

// MARK: - Reaching a guest's Proctor

/// How a host-side session talks to a Proctor that is already running on
/// another Mac. No new network transport: StreamLocal forwarding onto that
/// agent's unix socket, then `PROCTOR_SOCKET` pointed at the local end.
///
/// **The recipe is structured, never a shell line.** A tool result that
/// carried `ssh -L …` would be an instruction a model with a shell would
/// run, which is the same defect `ToolAbsence` already refuses for install
/// commands. The person at the keyboard types the tunnel; this only says
/// what it has to bind.
///
/// Delegated guests do not use this path. They have no Proctor inside, so
/// there is no socket to forward onto; they go through Cua.
public struct GuestReach: Codable, Sendable, Equatable {

    public enum Kind: String, Codable, Sendable {
        case streamLocal
    }

    public var kind: Kind
    /// Where the host-side shim should connect. Set `PROCTOR_SOCKET` to this.
    public var localSocket: String
    /// The guest agent's own socket, as it appears on that machine.
    public var remoteSocket: String
    /// SSH target. A hostname, a Tailscale MagicDNS name, or a guest IP.
    public var host: String
    public var user: String?
    /// The one environment override the host-side process needs.
    public var socketOverride: String
    public var note: String

    public init(kind: Kind = .streamLocal, localSocket: String, remoteSocket: String,
                host: String, user: String?, socketOverride: String, note: String) {
        self.kind = kind
        self.localSocket = localSocket
        self.remoteSocket = remoteSocket
        self.host = host
        self.user = user
        self.socketOverride = socketOverride
        self.note = note
    }

    /// The guest agent's default socket, written the same way `Wire.socketPath`
    /// writes the host one, so a standard install is reachable without being
    /// told a path. A non-standard guest install passes `remoteSocket`.
    public static let defaultRemoteSocket =
        "~/Library/Application Support/app.fledgeling.procter/agent.sock"

    public static let socketEnv = "PROCTOR_SOCKET"

    /// Why this machine cannot be reached this way, or nil when it can.
    ///
    /// A list of what survives rather than a list of what is refused, for the
    /// same reason `WitnessTier.cannotEvaluate` is: a forgotten platform is
    /// refused, not silently tunnelled toward a socket that is not there.
    public static func cannotReach(_ machine: Machine) -> String? {
        if machine.kind == .host {
            return "This session is already on this Mac. There is no guest socket to forward onto."
        }
        if machine.platform != .macos {
            let named = machine.platform?.rawValue ?? "an unnamed platform"
            return "A \(named) guest has no Proctor inside, so there is no unix socket to "
                 + "forward onto. Delegated guests go through Cua, not through SSH. "
                 + "Install Proctor in a macOS guest, or drive this one on the Cua lane."
        }
        if machine.tier == .delegated {
            return "This guest is marked delegated, so it has no Proctor socket. "
                 + "Delegated guests go through Cua. A macOS guest running a full "
                 + "Proctor is native and is the one this path reaches."
        }
        return nil
    }

    /// The local socket for one guest, under the same support directory the
    /// host agent already uses. One file per handle, so two guests do not
    /// share an end.
    public static func defaultLocalSocket(handle: String, home: String) -> String {
        home + "/Library/Application Support/app.fledgeling.procter/guests/" + handle + ".sock"
    }

    public static func decide(machine: Machine, host: String, user: String?,
                              remoteSocket: String?, localSocket: String?,
                              handle: String, home: String) -> GuestReachDecision {
        if let why = cannotReach(machine) { return .refused(why) }
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else {
            return .refused("reach needs a host: a hostname, a Tailscale name, or the guest's IP.")
        }
        let remote = (remoteSocket?.isEmpty == false)
            ? remoteSocket!
            : defaultRemoteSocket
        let local = (localSocket?.isEmpty == false)
            ? localSocket!
            : defaultLocalSocket(handle: handle, home: home)
        let trimmedUser = user?.trimmingCharacters(in: .whitespacesAndNewlines)
        let userPart = (trimmedUser?.isEmpty == false) ? trimmedUser : nil
        return .recipe(GuestReach(
            localSocket: local,
            remoteSocket: remote,
            host: trimmedHost,
            user: userPart,
            socketOverride: local,
            note: "A person opens an SSH StreamLocal tunnel from localSocket onto "
                + "remoteSocket, then starts the host-side shim with \(socketEnv) set "
                + "to localSocket. Proctor does not open the tunnel and does not "
                + "install ssh. The same recipe reaches a remote Mac over Tailscale: "
                + "the host is that Mac's name, and there is no guest in between."))
    }
}

public enum GuestReachDecision: Sendable, Equatable {
    case recipe(GuestReach)
    case refused(String)
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
