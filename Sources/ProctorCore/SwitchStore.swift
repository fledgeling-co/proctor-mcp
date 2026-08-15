import Foundation

// PRO-0029. Where a saved switch lives, and why it is not the launchd plist.
//
// **The plist was the obvious home and it is the wrong one.** Measured at
// `c9e42c9`: `scripts/install.sh` writes
// `~/Library/LaunchAgents/app.fledgeling.procter.agent.plist` with a `cat >`
// heredoc that has NO `EnvironmentVariables` key and overwrites the file
// unconditionally on every run. A preference written there would be destroyed by
// the next `install.sh` — silently, on an upgrade, taking a person's settings with
// it. That is precisely the disappearance this item exists to fix, so writing to
// the plist would reproduce the defect rather than close it. Applying a plist
// change also needs `bootout` + `bootstrap`, which is strictly heavier than the
// `kickstart` the window already uses.
//
// So: a file beside the agent's other state, which `install.sh` creates with
// `mkdir -p` and never removes.
//
// **`procter` is not a typo.** `Wire.bundleIdentifier` is `app.fledgeling.procter`
// and every store, socket and log path in this tree derives from it. The
// out-of-family gate flagged it as a misspelling; correcting it would point the
// window at a directory the agent does not use. The path is derived here rather
// than written out, so the question cannot arise twice.
//
// **This file is not a trust boundary and nothing here claims otherwise.** It
// lives in the user's home directory, so any process running as this user can
// write it, and `0600` keeps out other users rather than other programs. The agent
// reads it at start and honours it. What makes that proportionate rather than
// alarming is in the spec: off wins for the two capability switches so the file can
// never be the sole reason a tap exists that a person cannot cancel; the effective
// value and its source travel in the report and the run record; and the one
// shell-holding party this could hand something to — the second lane's agent —
// exists only once that lane is already on, so it cannot write the file to turn
// itself on.

/// The saved half of the two sources of truth.
///
/// Stored as a name-to-string map rather than eight named booleans, because the
/// values are not all booleans: two of them are tool names, and a `Bool` field
/// would have to be translated back into `browser-use` by whoever wrote it. One
/// spelling, written once, read by `SwitchResolver`.
public struct SavedSwitches: Codable, Sendable, Equatable {

    /// Variable name to raw value. Only the eight are ever written.
    public private(set) var values: [String: String]

    public init(values: [String: String] = [:]) {
        self.values = values.filter { SwitchCatalogue.named($0.key) != nil }
    }

    public subscript(variable: String) -> String? { values[variable] }

    /// Record a switch's state in its own on/off spelling.
    public mutating func set(_ aSwitch: ProctorSwitch, on: Bool) {
        values[aSwitch.variable] = on ? SwitchResolver.onValue(for: aSwitch)
                                      : SwitchResolver.offValue(for: aSwitch)
    }

    /// Forget a switch, so it falls back to the environment or the default.
    public mutating func clear(_ aSwitch: ProctorSwitch) {
        values.removeValue(forKey: aSwitch.variable)
    }

    // MARK: - Codable

    // Hand-rolled so an unknown key is IGNORED rather than throwing. A newer
    // window writing a ninth switch must not stop an older agent from starting;
    // the `init(values:)` filter is what drops it.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = (try? container.decode([String: String].self)) ?? [:]
        self.init(values: raw)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(values)
    }
}

public enum SwitchStore {

    /// `~/Library/Application Support/app.fledgeling.procter/settings`, derived
    /// from the bundle identifier exactly as `PolicyStore` and `FlowStore` derive
    /// theirs. Never a literal, and never a directory called `Proctor`.
    public static func directory(home: URL) -> URL {
        home.appendingPathComponent(
            "Library/Application Support/\(Wire.bundleIdentifier)/settings",
            isDirectory: true)
    }

    public static func url(home: URL) -> URL {
        directory(home: home).appendingPathComponent("settings.json", isDirectory: false)
    }

    public static var defaultURL: URL {
        url(home: FileManager.default.homeDirectoryForCurrentUser)
    }

    /// Read, tolerating everything.
    ///
    /// A missing, unreadable, corrupt or half-written file returns the empty set,
    /// which resolves every switch to its built-in default — so the two capability
    /// switches and the two lanes read OFF. Failing towards "on" here would mean a
    /// damaged file could arm an event tap, which is the one direction this must
    /// never fail in.
    public static func load(from url: URL) -> SavedSwitches {
        guard let data = try? Data(contentsOf: url),
              let saved = try? JSONDecoder().decode(SavedSwitches.self, from: data) else {
            return SavedSwitches()
        }
        return saved
    }

    /// Write atomically, so a reader never sees a torn file.
    ///
    /// `.atomic` is write-temp-then-rename. It does not exclude a second writer —
    /// nothing here does, and the header says so — it guarantees that whichever
    /// write lands, lands whole.
    public static func save(_ saved: SavedSwitches, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(saved).write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600],
                                               ofItemAtPath: url.path)
    }
}
