import Foundation

// Whether a command-line tool Proctor recommends is actually on this machine.
//
// Proctor routes browser pages to Obscura (PRO-0020). Recommending a tool that
// is not installed is worse than recommending nothing, because the handoff reads
// as an instruction from something that knows what it is talking about.
//
// Two rules hold this file together, and they are the same rule at two levels.
//
// **Proctor never installs anything**, and the shell commands that would install
// it never appear in a tool result. A model holding a shell that is handed
// `curl … | tar …` will run it, which defers a fetch-and-execute rather than
// avoiding it. `ToolAbsence` therefore carries no command text at all; the
// commands live in the status window, where a person is present.
//
// **Detection reads the filesystem and never runs the binary.** The directories
// that make a launchd agent's lookup work — ~/.local/bin, ~/.cargo/bin,
// /opt/homebrew/bin — are user-writable, so executing whatever answers to that
// filename inside a process holding Accessibility would be a code-execution path
// opened on Proctor's own initiative. Reading a mode bit runs nothing. The cost
// is that Proctor learns no version, and that a file planted at one of those
// paths is reported as present: what this reports is the presence of a name at a
// path, not a verified tool, and it says so in those terms.
//
// Everything here is pure. The caller supplies the environment and one
// predicate; this file decides.

/// Whether a tool can actually be used, as far as Proctor established.
///
/// The three states, and the spelling, PRO-0041 gave the grants. `unconfirmed` is
/// a fact about Proctor's knowledge rather than about the tool: the lane may be
/// perfectly healthy, and what is known is that nothing established it.
public enum ToolUsability: String, Codable, Sendable, CaseIterable {
    case usable, unusable, unconfirmed
}

/// What was consulted to reach that verdict, weakest first.
///
/// The floor for a tool that was *found* is `presence` — a row saying nothing at
/// all is known about a file we just located reads as a bug rather than as
/// caution, which is why there is no `none` case.
///
/// `laneReport` is deliberately not called `selfReport`: **nothing here asks a
/// tool about itself.** `proctor_doctor` creates no process. That rung is
/// populated only from a preflight that already ran because the lane was *used*,
/// so it is Proctor's record of a completed act rather than a question a health
/// check asked.
public enum ToolEvidence: String, Codable, Sendable, CaseIterable {
    case absent, presence, signature, installPath, laneReport
}

/// Where a tool was looked for, and what was found.
public struct ToolPresence: Codable, Sendable, Equatable {
    public var tool: String
    /// Whether an executable regular file of that name exists at one of the
    /// searched paths. **This is unchanged and is not a usability claim** —
    /// `usability` is the axis beside it, added by PRO-0050, never a
    /// redefinition of this one.
    public var available: Bool
    /// Where it was found, or nil. On the wire because a reader whose own shell
    /// disagrees with Proctor can only settle it by comparing paths.
    public var path: String?
    /// Every candidate, in the order they were checked. "Installed but Proctor
    /// cannot see it" is the failure a launchd agent actually produces, and it is
    /// only diagnosable if Proctor says where it looked.
    public var searched: [String]
    /// Siblings the tool needs that are not beside it. A half install fails one
    /// subcommand and no others, which is worth naming rather than discovering.
    public var missingCompanions: [String]
    /// Whether this tool can be used, as far as anything established it.
    public var usability: ToolUsability?
    /// What backs that verdict.
    public var evidence: ToolEvidence?
    /// The version, when a route that runs nothing produced one. `evidence` says
    /// which route: a version read out of an install layout is what the layout
    /// claims, not what the binary answers.
    public var version: String?
    /// One line, in Proctor's own words, saying what was established and what was
    /// not. Never a string a located tool supplied.
    public var detail: String?
    /// When the usability verdict was established.
    public var checkedAt: Double?

    public init(tool: String, available: Bool, path: String? = nil,
                searched: [String] = [], missingCompanions: [String] = [],
                usability: ToolUsability? = nil, evidence: ToolEvidence? = nil,
                version: String? = nil, detail: String? = nil,
                checkedAt: Double? = nil) {
        self.tool = tool; self.available = available; self.path = path
        self.searched = searched; self.missingCompanions = missingCompanions
        self.usability = usability; self.evidence = evidence
        self.version = version; self.detail = detail; self.checkedAt = checkedAt
    }
}

/// What a model is told when a recommended tool is missing.
///
/// No command text, deliberately. `askThePerson` states a capability rather than
/// a promise: "Proctor will never install anything" written into the protocol
/// would become a lie the day a button ships, and a protocol field is the wrong
/// place to freeze a policy.
public struct ToolAbsence: Codable, Sendable, Equatable {
    public var tool: String
    public var missing: String
    public var docs: String
    public var askThePerson: String

    public init(tool: String, missing: String, docs: String, askThePerson: String) {
        self.tool = tool; self.missing = missing; self.docs = docs
        self.askThePerson = askThePerson
    }
}

public enum ToolLocator {

    /// The directories a launchd agent has to be told about, shared by every tool
    /// Proctor looks for. One list rather than one per tool: a launchd agent's
    /// lookup problem is the same problem whatever the binary is, and two lists
    /// would drift.
    public static let commonToolDirectories = [
        "/opt/homebrew/bin",    // Apple Silicon Homebrew
        "/usr/local/bin",       // Intel Homebrew, and most manual installs
        "~/.local/bin",         // pipx and `uv tool`; the verified Obscura install here too
        "~/.cargo/bin",         // Obscura is Rust; cargo install is a real path to it
        "/opt/local/bin"        // MacPorts
    ]

    /// The directories to check, in order: the inherited `PATH` first, then the
    /// explicit list. The explicit list is not a convenience — a launchd agent
    /// inherits no login shell's `PATH`, so `/opt/homebrew/bin` and the rest have
    /// to be named or a Homebrew install is invisible.
    ///
    /// Entries are made absolute (a leading `~` is expanded from `home`), stripped
    /// of a trailing slash, dropped when still not absolute, and deduplicated with
    /// their order preserved — so a `PATH` entry repeating an explicit directory
    /// is checked and reported once.
    public static func candidateDirectories(pathEnvironment: String?, home: String,
                                            extraDirectories: [String]) -> [String] {
        let fromPath = (pathEnvironment ?? "").split(separator: ":", omittingEmptySubsequences: true)
            .map(String.init)
        var seen: Set<String> = []
        var out: [String] = []
        for raw in fromPath + extraDirectories {
            guard let dir = normalise(raw, home: home), seen.insert(dir).inserted else { continue }
            out.append(dir)
        }
        return out
    }

    /// The candidate paths for one binary, in the order they are checked.
    public static func candidatePaths(binary: String, pathEnvironment: String?, home: String,
                                      extraDirectories: [String]) -> [String] {
        candidateDirectories(pathEnvironment: pathEnvironment, home: home,
                             extraDirectories: extraDirectories).map { $0 + "/" + binary }
    }

    /// Find `binary`, and check that its `companions` sit beside it.
    ///
    /// `isExecutable` must mean **an executable regular file**. `FileManager`'s
    /// own `isExecutableFile` answers true for a directory carrying the execute
    /// bit, so a directory named `obscura` on the path would otherwise be
    /// reported as the tool. The predicate is the only I/O this function does,
    /// and it runs nothing.
    ///
    /// A **complete** install wins over an earlier incomplete one. First-hit-wins
    /// alone would let a stray copy of the binary on an early `PATH` entry mask a
    /// real install further down and report a permanent half-install; preferring
    /// the first complete hit costs one extra pass and describes the machine
    /// correctly. When no candidate is complete, the first hit is reported with
    /// what it is missing.
    public static func locate(binary: String, companions: [String] = [],
                              pathEnvironment: String?, home: String,
                              extraDirectories: [String],
                              isExecutable: (String) -> Bool) -> ToolPresence {
        let directories = candidateDirectories(pathEnvironment: pathEnvironment, home: home,
                                               extraDirectories: extraDirectories)
        let searched = directories.map { $0 + "/" + binary }

        var firstHit: (path: String, missing: [String])?
        for directory in directories {
            let path = directory + "/" + binary
            guard isExecutable(path) else { continue }
            let missing = companions.filter { !isExecutable(directory + "/" + $0) }
            if missing.isEmpty {
                return ToolPresence(tool: binary, available: true, path: path,
                                    searched: searched, missingCompanions: [])
            }
            if firstHit == nil { firstHit = (path, missing) }
        }

        if let hit = firstHit {
            return ToolPresence(tool: binary, available: true, path: hit.path,
                                searched: searched, missingCompanions: hit.missing)
        }
        return ToolPresence(tool: binary, available: false, path: nil,
                            searched: searched, missingCompanions: [])
    }

    static func normalise(_ raw: String, home: String) -> String? {
        var dir = raw
        if dir == "~" {
            dir = home
        } else if dir.hasPrefix("~/") {
            dir = home + String(dir.dropFirst(1))
        }
        while dir.count > 1 && dir.hasSuffix("/") { dir.removeLast() }
        guard dir.hasPrefix("/") else { return nil }
        return dir
    }
}
