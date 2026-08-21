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
        //
        // MATCHED ON A TOKEN, NEVER ON A SUBSTRING, and that is not a tidying.
        // `hay.contains("win")` was true of **darwin**, which is the word tart
        // prints for a macOS guest — so every macOS guest whose provider named
        // its platform honestly came back `.windows`, took the delegated tier,
        // lost the accessibility tree and the frame-status channel, and was
        // refused by `GuestReach` as a machine with no Proctor inside. Found by
        // PRO-0076 against tart 2.32.1; latent since PRO-0058 for any provider
        // that says `darwin` rather than `macOS`.
        //
        // A token that STARTS with "win" is Windows (`win`, `win11`, `windows`);
        // one that merely contains it is not (`darwin`).
        let tokens = hay.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        if tokens.contains(where: { $0.hasPrefix("win") }) { return .windows }
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

// MARK: - tart

/// Decode `tart list --format json` and `tart get <name> --format json`.
///
/// Measured on this machine 2026-08-20 against tart 2.32.1, not read from docs:
///
///     list --format json  -> [{Size, State, Source, Name, Running, Accessed, Disk}]
///     get <n> --format json -> {OS, CPU, Size, State, Display, Memory,
///                               DiskFormat, Disk, Running}
///
/// **The listing carries no `OS`, and that is the whole reason this type has two
/// halves.** PRO-0076 requires the platform to be read from what the provider
/// says rather than inferred from a guest's name, because the cap the pool
/// enforces is Apple's rule about macOS guests. `parse` therefore leaves
/// `platform` nil and `platform(fromGet:)` reads it from a `get`; the adapter
/// puts the two together.
///
/// Inferring from the name would work on exactly this machine and is refused
/// anyway: `anvil-mac-node` and `anvil-linux-node` would both come out right,
/// which is what makes it a trap. A guest called `build-box` would be counted
/// against Apple's two, or excused from it, by its name.
public enum TartInventory {

    public static let provider = TartTool.binary

    /// The inventory. `Running` is a real boolean here rather than a word to
    /// interpret, so it is read directly and `state` keeps the provider's own
    /// spelling for the report.
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
        let name = string(object, "Name") ?? string(object, "name")
        guard let name, !name.isEmpty else { return nil }
        let state = string(object, "State") ?? string(object, "state") ?? "unknown"
        let running: Bool
        if let flag = object["Running"] as? Bool {
            running = flag
        } else {
            running = GuestPower.isRunning(state)
        }
        // Platform deliberately nil: a tart listing does not say. The adapter
        // fills it from `get`, and a guest whose platform could not be read is
        // refused at attach rather than admitted uncounted.
        return GuestRecord(name: name, provider: provider, state: state,
                           running: running, platform: nil, identifier: name)
    }

    /// The platform, read from a `tart get` payload and from nothing else.
    ///
    /// `name` is passed as nil into the inference on purpose, so the only thing
    /// consulted is the word the provider printed. tart says `darwin` for a
    /// macOS guest, which `GuestPlatform.infer` already recognises.
    public static func platform(fromGet data: Data) -> MachinePlatform? {
        guard !data.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        let os = string(object, "OS") ?? string(object, "os")
        return GuestPlatform.infer(os: os, name: nil)
    }

    /// Whether a `get` payload says the guest is up. Used by `start`, which
    /// launches tart detached and then polls this rather than waiting on a
    /// process that lives as long as the VM does.
    public static func isRunning(fromGet data: Data) -> Bool {
        guard !data.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        if let flag = object["Running"] as? Bool { return flag }
        return GuestPower.isRunning(string(object, "State") ?? "")
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

/// `tart`, Cirrus Labs' Virtualization.framework CLI. macOS and Linux guests.
///
/// The third adapter, and the one with a working macOS guest on this machine,
/// which is what makes PRO-0076's attach measurable rather than carried.
/// Detection is a filesystem read like every other tool; running it is the
/// adapter's job.
public enum TartTool {
    public static let binary = "tart"
    public static let docs = "https://tart.run"
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

// MARK: - PRO-0094: what is known about Tahoe guests, held as the measurement

/// Notes the guest lane carries on every surface a reader sees.
///
/// **One constant, because three copies is three sources.** The Tahoe
/// window-rendering sentence was hand-written into the doctor's guest lane, the
/// `proctor_guest` tool description and every `proctor_guest` result, and a
/// correction landing in one of them would leave the other two saying the old
/// thing. This repo has shipped that defect twice already.
public enum GuestNotes {

    /// The upstream reports, and this project's own measurement against them.
    ///
    /// **The prose is composed from the fields rather than written beside
    /// them.** A note that states a version, a date and three application names
    /// is a claim somebody can check, and a claim somebody can check drifts the
    /// moment it is only prose: the fields are the measurement, `sentence` is a
    /// rendering of it, and `GuestNoteSourceTests` binds the fields back to the
    /// spec section that recorded them.
    ///
    /// What is deliberately NOT said: that the bug is fixed, that it never
    /// bites, or that the reader should go and find a Sequoia image. One guest
    /// on one host at one version refutes nothing — it is one measurement, and
    /// the reader is given it with its provenance so they can weigh it against
    /// two reports that are still open.
    public enum TahoeRendering {
        /// The reports this note is about. **Both still open**, which is why the
        /// note qualifies the measurement rather than replacing them with it.
        public static let upstream = "trycua/cua #870 and Apple FB21748086"
        /// The guest's own macOS version, as its Proctor reported it over the
        /// attach link — not read off an image name.
        public static let guestOS = "26.6.2"
        public static let measuredOn = "2026-08-21"
        /// What drew a window. Three applications, named, because "it worked"
        /// is not a measurement.
        public static let applications = ["Calculator", "System Settings", "Setup Assistant"]
        /// Where the measurement is written down, so the sentence carries its
        /// own citation to a reader who has the repo.
        public static let citation = "docs/specs/spec-PRO-0076.md"
        /// The sentence that opens the recorded measurement inside `citation`.
        ///
        /// Not decoration: `GuestNoteSourceTests` locates this, takes the section
        /// around it and looks for the claims THERE. Checking the whole file
        /// instead was the first draft, and it was green against a spec whose
        /// measurement paragraph had been deleted, because every claim in it also
        /// appears elsewhere in that document. Found by the PRO-0094 D-prime
        /// validator, which counted the duplicates.
        public static let measurementAnchor =
            "The Tahoe window-rendering warning did not reproduce."

        /// The applications in prose: "A, B and C".
        static var applicationList: String {
            guard let last = applications.last else { return "" }
            guard applications.count > 1 else { return last }
            return applications.dropLast().joined(separator: ", ") + " and " + last
        }

        /// One sentence, composed from the fields above.
        public static let sentence =
            "Tahoe guests were reported to render no application windows — \(upstream), both "
          + "still open — but on \(measuredOn) Proctor drove a macOS \(guestOS) guest in which "
          + "\(applicationList) all rendered normally (\(citation)), so treat it as an open "
          + "report upstream rather than a settled property of every Tahoe guest."
    }

    /// The sentence every guest surface carries. Interpolated, never copied.
    public static var tahoeRendering: String { TahoeRendering.sentence }
}

// MARK: - PRO-0094: which macOS a guest is running

/// A guest's macOS version, or the reason Proctor cannot establish it.
///
/// **`unknown` with a reason is the honest answer, and it is the common one.**
/// No provider records a guest's OS version: `lume get` and tart's `config.json`
/// both report only `macOS`/`darwin`, and `prlctl` does not carry one either. The
/// only thing that knows is the machine itself, so the version is what the
/// Proctor inside the guest said when it was asked — and where nothing can be
/// asked, this says so and names what would change the answer.
///
/// **Never inferred.** Not from the image name, not from the provider, not from
/// `platform`. `platform` answers *which OS*; it has never answered *which
/// version*, and a guest called `macos-sequoia-cua` is evidence of what somebody
/// typed. That negative is checkable rather than asserted: `obstacle` below takes
/// a record and a bool and reads neither the name nor the image.
public struct GuestOSVersion: Codable, Sendable, Equatable {
    /// The version string, exactly as the guest's own Proctor reported it. Nil
    /// exactly when it could not be established.
    public var version: String?
    /// Where the answer came from. `guest-agent` when a Proctor inside the guest
    /// answered; `unknown` otherwise.
    ///
    /// A string rather than an enum, for the reason `GuestRecord.state` is one: a
    /// channel a later build adds survives into an older reader's report instead
    /// of being flattened into whichever case looked closest.
    public var source: String
    /// Why there is no version, and what would change that. Present exactly when
    /// `version` is nil.
    public var reason: String?

    public init(version: String?, source: String, reason: String?) {
        self.version = version; self.source = source; self.reason = reason
    }

    public static func known(_ version: String) -> GuestOSVersion {
        GuestOSVersion(version: version, source: "guest-agent", reason: nil)
    }

    public static func unknown(reason: String) -> GuestOSVersion {
        GuestOSVersion(version: nil, source: "unknown", reason: reason)
    }
}

/// Whether a guest can be asked which macOS it is running, decided purely.
///
/// Pure so every branch is provable on a machine with none of `lume`, `prlctl` or
/// `tart` installed — the rule this file sets for the whole lane — and so the
/// "never inferred from the image name" guarantee is a property of the signature
/// rather than a promise in a comment.
public enum GuestOSVersionResolution {

    /// Why this guest cannot be asked, or nil when it can be.
    ///
    /// **The order of these three checks is load-bearing.** Platform comes first
    /// because a delegated guest has no answer at any power state, so telling its
    /// reader to start it would send them to do something that cannot work.
    /// Power comes before attachment for the same reason in miniature: attaching
    /// to a stopped guest is not the next step, starting it is.
    public static func obstacle(record: GuestRecord,
                                attachedByThisSession: Bool) -> String? {
        guard record.platform == .macos else {
            return "\(record.name) is not a macOS guest, so there is no Proctor inside it to "
                 + "ask. A delegated guest is driven through Cua, which reports no OS version "
                 + "either."
        }
        guard record.running else {
            // A guest stopped from under a session that is still attached to it
            // cannot be told to attach: that call is refused while an attachment
            // stands. Found by the PRO-0094 completeness critic, which read the
            // remedy against `guestAttach`'s own guard.
            let lead = "\(record.name) is \(record.state), so nothing inside it can be asked, "
                     + "and no provider records a guest's macOS version in its listing. "
            guard attachedByThisSession else {
                return lead + "Start it with proctor_guest action \"start\", attach, and read "
                            + "status again."
            }
            return lead + "This session is still attached to it, so detach with proctor_guest "
                        + "action \"detach\" first, then start it, attach again and read status."
        }
        guard attachedByThisSession else {
            return "this session is not attached to \(record.name), so there is no link to ask "
                 + "over. Attach with proctor_guest action \"attach\" and read status again; the "
                 + "version comes from the Proctor inside the guest, never from the image name."
        }
        return nil
    }

    /// A guest that should have been answerable and was not.
    ///
    /// Carries what the link said verbatim, because the two reasons a reader
    /// might be here — a tunnel that dropped and a Proctor that is not running
    /// inside the guest — are fixed in different places.
    public static func silentAgent(name: String, said: String?) -> String {
        let tail = said?.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = (tail?.isEmpty == false) ? " The link said: \(tail!)" : ""
        return "the Proctor inside \(name) did not report an OS version.\(detail) The attachment "
             + "is untouched — this is a read, and a read does not release a slot."
    }
}
