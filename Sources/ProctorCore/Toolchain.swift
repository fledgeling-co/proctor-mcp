import Foundation

// PRO-0050. One definition of the toolchain Proctor depends on but does not
// ship, and every decision made from it.
//
// **Everything here is pure.** The caller supplies what it observed on the
// filesystem — a located path, an install-layout version, a signature verdict,
// whatever a completed preflight recorded — and this file decides what that
// means. The split is deliberate and was forced by the plan review: usability
// and evidence were originally stamped where the probing happened, which puts
// the decisions in the half that cannot be tested without a machine that has
// these tools installed. A machine with none of them can prove all of this.
//
// The other reason this file exists is drift. `scripts/doctor.sh` has to look in
// the same places the agent does, and a second hand-written copy of the search
// order in shell is a copy that will disagree. `shellFragment()` renders the
// list, the rendered file is committed, and a test fails the build when they
// part company.

// MARK: - What a tool's file says about itself

/// What a code signature says, one layer removed from `CuaPreflight`'s own
/// verdict so that the deciding half of this feature does not depend on the
/// agent. The agent maps its verdict onto this.
public enum ToolSignature: Sendable, Equatable {
    /// Signed by the identity the tool's own documentation names.
    case valid
    case unsigned
    /// Ad-hoc, which a local `swift build` or a source install produces.
    case adhoc
    case wrongIdentity(String?)
    case unreadable(String)
    /// Not looked at — either the tool is one whose signature Proctor has no
    /// pinned identity for, or it was not found at all.
    case notChecked
}

// MARK: - The toolchain

/// How a tool is looked for.
public enum ToolSearchRoute: String, Sendable, Equatable {
    /// The inherited `PATH` plus `ToolLocator.commonToolDirectories`.
    case commonDirectories
    /// Inside the active developer directory. `SimctlLocator` owns this one; it
    /// is a different shape of search rather than a list of bin directories.
    case developerDirectory
}

/// One tool Proctor looks for, and what its presence is worth.
public struct ToolchainEntry: Sendable, Equatable {
    public var tool: String
    public var companions: [String]
    public var route: ToolSearchRoute
    /// The lane that stops working without it.
    public var lane: String
    /// Whether finding the file settles whether the tool can be used.
    ///
    /// True for every tool Proctor invokes as a one-shot whose failure is
    /// reported at the moment it is called. False for `cua-driver`, whose daemon,
    /// version and own permissions are all invisible to a stat, and which is the
    /// reason this whole axis exists.
    public var presenceIsSufficient: Bool
    /// Whether this tool's row is only ever shown when an operator named it.
    public var operatorGated: Bool

    public init(tool: String, companions: [String] = [],
                route: ToolSearchRoute = .commonDirectories,
                lane: String, presenceIsSufficient: Bool = true,
                operatorGated: Bool = false) {
        self.tool = tool; self.companions = companions; self.route = route
        self.lane = lane; self.presenceIsSufficient = presenceIsSufficient
        self.operatorGated = operatorGated
    }
}

/// What the impure half observed about one tool. Facts only — no verdict.
public struct ToolFacts: Sendable, Equatable {
    /// What the locator found: path, searched paths, missing companions. Only
    /// the fields a filesystem answer can fill.
    public var located: ToolPresence
    /// A version the install layout carries, already parsed. Homebrew writes one
    /// into its symlink target and Xcode writes one into a plist; neither is the
    /// binary's own answer, and the evidence rung says so.
    public var installVersion: String?
    public var signature: ToolSignature
    /// What a preflight that already ran established. Never triggered by asking.
    public var laneReport: ToolLaneFacts?
    public var checkedAt: Double

    public init(located: ToolPresence, installVersion: String? = nil,
                signature: ToolSignature = .notChecked,
                laneReport: ToolLaneFacts? = nil, checkedAt: Double = 0) {
        self.located = located; self.installVersion = installVersion
        self.signature = signature; self.laneReport = laneReport
        self.checkedAt = checkedAt
    }
}

/// The part of a completed preflight that belongs in a health report.
///
/// **Every field is a value Proctor produced or parsed.** There is deliberately
/// no free-text field carrying whatever the driver printed: `proctor_doctor` is
/// the first call the Proctor skill tells a model to make, and a tool result that
/// pipes another process's prose into that position is an injection surface. The
/// stage is Proctor's own enum, the version is what Proctor's parser accepted,
/// and the overrides are Proctor's own words for switches an operator set.
public struct ToolLaneFacts: Sendable, Equatable {
    public var version: String?
    public var healthy: Bool
    /// Which ordered check refused, when one did: presence, signature, version,
    /// capabilities, grants.
    public var failedStage: String?
    public var overrides: [String]
    /// What the driver said about its own permissions, **keyed by Proctor's
    /// vocabulary rather than the driver's**. See `recognisedGrants`.
    public var driverReportedGrants: [String: Bool]
    /// How many keys the driver reported that Proctor does not recognise. On the
    /// wire as a count so that dropping them is visible rather than silent.
    public var unrecognisedGrantKeys: Int

    public init(version: String? = nil, healthy: Bool,
                failedStage: String? = nil, overrides: [String] = [],
                driverReportedGrants: [String: Bool] = [:],
                unrecognisedGrantKeys: Int = 0) {
        self.version = version; self.healthy = healthy
        self.failedStage = failedStage; self.overrides = overrides
        self.driverReportedGrants = driverReportedGrants
        self.unrecognisedGrantKeys = unrecognisedGrantKeys
    }

    /// The permission names Proctor will repeat from a driver's own report.
    ///
    /// A map that came from another process has attacker-controlled **keys**, not
    /// just values, and this map is rendered into the first tool result a model
    /// reads. So the keys are matched against Proctor's own vocabulary and
    /// anything else is dropped and counted. A driver that reports a permission
    /// Proctor has no name for is a reason to add a name here, not a reason to
    /// let it write into a health report.
    public static let recognisedGrants: [String: String] = [
        "accessibility": "Accessibility",
        "screenrecording": "Screen Recording",
        "screen_recording": "Screen Recording",
        "screen-recording": "Screen Recording",
        "automation": "Automation"
    ]

    /// Keep the permissions Proctor has a name for; count the rest.
    public static func filterGrants(_ raw: [String: Bool]) -> (kept: [String: Bool],
                                                               dropped: Int) {
        var kept: [String: Bool] = [:]
        var dropped = 0
        for (key, value) in raw {
            if let name = recognisedGrants[key.lowercased()] {
                kept[name] = value
            } else {
                dropped += 1
            }
        }
        return (kept, dropped)
    }
}

public enum Toolchain {

    public static let macLane = "mac"
    public static let browserLane = "browser"
    public static let iosLane = "ios"
    public static let cuaLane = "cua"
    public static let guestLane = "guest"

    /// Every tool Proctor looks for, in the order the report lists them.
    ///
    /// `simctl` sits here beside the rest even though its search route is
    /// different, because "is there an iOS lane on this machine" is the same
    /// question as "is there a browser lane" and answering it from a second list
    /// is how the two drift.
    public static let entries: [ToolchainEntry] = [
        ToolchainEntry(tool: ObscuraTool.binary, companions: ObscuraTool.companions,
                       lane: browserLane),
        ToolchainEntry(tool: BrowserUseTool.binary, lane: browserLane, operatorGated: true),
        ToolchainEntry(tool: "simctl", route: .developerDirectory, lane: iosLane),
        ToolchainEntry(tool: CuaDriverTool.binary, lane: cuaLane, presenceIsSufficient: false),
        ToolchainEntry(tool: MaestroTool.binary, lane: iosLane),
        ToolchainEntry(tool: LumeTool.binary, lane: guestLane),
        ToolchainEntry(tool: PrlctlTool.binary, lane: guestLane)
    ]

    public static func entry(for tool: String) -> ToolchainEntry? {
        entries.first { $0.tool == tool }
    }

    // MARK: - The row, which is where a verdict is decided

    /// Turn what was observed into what it means.
    public static func row(entry: ToolchainEntry, facts: ToolFacts) -> ToolPresence {
        var row = facts.located
        row.checkedAt = facts.checkedAt

        guard row.available else {
            row.usability = .unusable
            row.evidence = .absent
            row.detail = "Not found in any of the \(row.searched.count) "
                       + "\(row.searched.count == 1 ? "location" : "locations") Proctor checks. "
                       + "A launchd agent inherits no login shell's PATH, so a tool your terminal "
                       + "finds can still be invisible here — the searched paths say where to look."
            return row
        }

        // A completed preflight is the strongest thing available, and it is the
        // only rung that can report a tool as confirmed working.
        if let lane = facts.laneReport {
            row.evidence = .laneReport
            row.version = lane.version ?? facts.installVersion
            row.usability = lane.healthy ? .usable : .unusable
            if lane.healthy {
                var detail = "Established when the lane was last used"
                if let version = lane.version { detail += ", running \(version)" }
                detail += "."
                if !lane.overrides.isEmpty {
                    detail += " Overrides in force: \(lane.overrides.sorted().joined(separator: ", "))."
                }
                row.detail = detail
            } else {
                let stage = lane.failedStage.map { " at the \($0) check" } ?? ""
                row.detail = "The last preflight refused this lane\(stage). "
                           + "Proctor does not repeat it from a health check."
            }
            return row
        }

        if !row.missingCompanions.isEmpty {
            row.usability = .unusable
            row.evidence = .presence
            row.detail = "Found, but \(row.missingCompanions.joined(separator: " and ")) "
                       + "\(row.missingCompanions.count == 1 ? "is" : "are") not beside it, so the "
                       + "subcommands that need it fail and no others do."
            return row
        }

        if entry.presenceIsSufficient {
            row.usability = .usable
            row.version = facts.installVersion
            if facts.installVersion != nil {
                row.evidence = .installPath
                row.detail = "Found, and the install layout names this version. Proctor did not run "
                           + "it: reading is free and running one of these costs seconds."
            } else {
                row.evidence = .presence
                row.detail = "Found. Proctor does not run a located binary to learn more about it, "
                           + "so this is the presence of a name at a path rather than a verified tool."
            }
            return row
        }

        // Presence is not enough for this one. The signature is the strongest
        // thing a read can establish, and it is the check that decides whether
        // the binary may ever be executed.
        switch facts.signature {
        case .valid:
            row.usability = .unconfirmed
            row.evidence = .signature
            row.version = facts.installVersion
            row.detail = "Found, and signed by the identity its own documentation names. Its "
                       + "version, its daemon and its own permissions are not established — a "
                       + "health check does not run it, so those are settled the first time the "
                       + "lane is used."
        case .unsigned, .adhoc, .wrongIdentity, .unreadable:
            row.usability = .unusable
            row.evidence = .signature
            row.detail = "Found, but \(describe(facts.signature)), so Proctor will not run it. "
                       + "Proctor holds the Accessibility grant, and this directory is one anybody "
                       + "logged in can write to."
        case .notChecked:
            row.usability = .unconfirmed
            row.evidence = .presence
            row.detail = "Found. Nothing has established its version, its daemon or its own "
                       + "permissions, and a stat cannot answer any of the three."
        }
        return row
    }

    static func describe(_ signature: ToolSignature) -> String {
        switch signature {
        case .valid:                   return "is correctly signed"
        case .unsigned:                return "it carries no code signature"
        case .adhoc:                   return "it is ad-hoc signed, which a local or source build is"
        case .wrongIdentity(let who):  return "it is signed by \(who ?? "another identity")"
        case .unreadable(let why):     return "its signature could not be read (\(why))"
        case .notChecked:              return "its signature was not checked"
        }
    }

    // MARK: - Versions that cost nothing

    /// The version a Homebrew-style install layout carries.
    ///
    /// `/opt/homebrew/bin/maestro` is a symlink to `../Cellar/maestro/2.4.0/bin/maestro`,
    /// so the version is readable with `readlink` — measured against `maestro
    /// --version`, which agrees and costs 3.9 to 5.3 seconds because it starts a
    /// JVM. This is what the install layout claims, not what the binary answers,
    /// and the evidence rung says which.
    ///
    /// Conservative on purpose: a component has to look like a version, or this
    /// returns nil rather than a guess, following `CuaVersion.parse`.
    public static func versionFromInstallPath(symlinkTarget: String?) -> String? {
        guard let target = symlinkTarget else { return nil }
        for component in target.split(separator: "/").map(String.init).reversed()
        where looksLikeVersion(component) {
            return component
        }
        return nil
    }

    static func looksLikeVersion(_ component: String) -> Bool {
        var candidate = component
        if candidate.hasPrefix("v") { candidate.removeFirst() }
        // A pre-release tail is everything after the first hyphen, and it is not
        // numeric — `0.14.0-nightly.1` is a version, and the tail travels with it.
        let core = candidate.split(separator: "-", maxSplits: 1,
                                   omittingEmptySubsequences: false)[0]
        let parts = core.split(separator: ".", omittingEmptySubsequences: false)
        // Two numeric parts at least, so `bin`, `Cellar` and `1.x` are not
        // mistaken for versions. Conservative on purpose, following
        // `CuaVersion.parse`: a guess here becomes a version in a health report.
        guard parts.count >= 2 else { return false }
        return parts.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isNumber) }
    }

    /// Xcode's own version, beside the developer directory rather than inside it.
    /// Root-owned and readable; nothing is executed to learn the iOS lane's Xcode.
    public static func xcodeVersionPlistPath(developerDirectory: String) -> String {
        var directory = developerDirectory
        while directory.count > 1 && directory.hasSuffix("/") { directory.removeLast() }
        return directory + "/../version.plist"
    }

    // MARK: - The shell fragment

    public static let generatedShellPath = "scripts/generated/toolchain-search.sh"
    public static let regenerateCommand =
        "PROCTOR_REGENERATE_TOOLCHAIN=1 swift test --filter shellFragmentMatchesTheCommittedFile"

    /// The search order, rendered for `scripts/doctor.sh` to source.
    ///
    /// Parallel arrays rather than an associative array, because macOS ships bash
    /// 3.2 and the shell doctor has to run on a machine with nothing installed —
    /// which is the situation it exists for.
    ///
    /// The developer-directory route is not rendered: it is a different shape of
    /// search rather than a directory list, and it is stated once in each
    /// language with a comment naming the other.
    public static func shellFragment() -> String {
        var out = """
        # Generated by ProctorCore.Toolchain.shellFragment(). Do not edit by hand.
        #
        # Regenerate with:
        #   \(regenerateCommand)
        #
        # This is the search order the AGENT uses. A launchd agent inherits no login
        # shell's PATH, which is why the list is explicit — and why this script and
        # the agent can honestly disagree about whether a tool is installed.
        #
        # simctl is not here: it lives inside the active developer directory rather
        # than in a bin directory. See SimctlLocator.swift for that route.

        PROCTOR_TOOL_DIRECTORIES=(

        """
        for directory in ToolLocator.commonToolDirectories {
            out += "  \"\(directory)\"\n"
        }
        out += ")\n\nPROCTOR_TOOL_NAMES=(\n"
        for entry in shellEntries {
            out += "  \"\(entry.tool)\"\n"
        }
        out += ")\n\n# Companions, index-matched to PROCTOR_TOOL_NAMES; empty when a tool has none.\n"
        out += "PROCTOR_TOOL_COMPANIONS=(\n"
        for entry in shellEntries {
            out += "  \"\(entry.companions.joined(separator: " "))\"\n"
        }
        out += ")\n"
        return out
    }

    /// The tools the shell doctor can look for the same way the agent does.
    static var shellEntries: [ToolchainEntry] {
        entries.filter { $0.route == .commonDirectories }
    }
}

/// Maestro: the iOS flow runner. A row here rather than a probe of its own, so
/// PRO-0049 consumes this one instead of looking a second time.
///
/// Not required for the iOS lane. Deep links work without it — `proctor_ios`
/// drives `simctl` directly — so its absence is a note on that lane rather than
/// a blocker on it.
public enum MaestroTool {
    public static let binary = "maestro"
    public static let docs = "https://maestro.dev"
    public static let extraDirectories = ToolLocator.commonToolDirectories
}
