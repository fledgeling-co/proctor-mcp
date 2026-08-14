import Foundation

// Obscura: the tool Proctor recommends for a browser page, and what to say when
// it is not here.
//
// The install is not a package-manager line. Checked rather than assumed:
// `brew info obscura` reports no such formula, and the project's own macOS
// instructions are a curl of an architecture-specific tarball from GitHub
// Releases, extracted to two executables that have to stay in the same
// directory. That is why `companions` exists, why the third install command
// exists, and why no button in Proctor runs any of it: a fetch-and-execute from
// a launchd agent already holding Accessibility and Screen Recording is not a
// convenience.
//
// `installCommands` is reached only from the status window. It is here, in a
// pure target, so both architecture branches are testable without a second
// machine — but it never reaches a tool result.

public enum ObscuraTool {

    public static let binary = "obscura"

    /// The release archive ships `obscura` and `obscura-worker`, and the project
    /// says they must stay in the same directory; the parallel `scrape` command
    /// needs the second one.
    public static let companions = ["obscura-worker"]

    public static let docs = "https://github.com/h4ckf0r0day/obscura"

    /// Checked in addition to whatever `PATH` the agent inherited, because a
    /// launchd agent's `PATH` is usually /usr/bin:/bin:/usr/sbin:/sbin. Shared
    /// with every other tool Proctor looks for; see `ToolLocator`.
    public static let extraDirectories = ToolLocator.commonToolDirectories

    /// Where the install commands put it. On the candidate list above, and it
    /// needs no administrator rights.
    public static let installDestination = "~/.local/bin"

    /// What the absence is a claim about, said out loud: a launchd agent's
    /// environment is not the login shell the reader will type into, so Proctor
    /// can report missing where a terminal finds it, and the reverse.
    public static let missing =
        "Obscura is not installed, or not anywhere Proctor can see it. Proctor runs as a "
        + "launchd agent, so it checks a fixed list of locations rather than a login shell's "
        + "PATH; proctor_doctor reports every path it checked."

    public static let askThePerson =
        "Proctor has no way to install it. Tell the person driving you rather than trying to "
        + "install it yourself: the Proctor status window has the install command ready to "
        + "copy for this Mac, and a Re-check that confirms it worked."

    public static var absence: ToolAbsence {
        ToolAbsence(tool: binary, missing: missing, docs: docs, askThePerson: askThePerson)
    }

    // MARK: - Install, for the status window only

    /// Which release archive this Mac needs. Read from the **hardware** rather
    /// than the running process, so a Proctor under Rosetta still names the Apple
    /// Silicon build; the reading itself is the caller's, which keeps this target
    /// pure and both branches testable.
    public enum Architecture: String, Sendable, Equatable {
        case appleSilicon, intel
        var archiveSlug: String {
            switch self {
            case .appleSilicon: return "aarch64"
            case .intel:        return "x86_64"
            }
        }
    }

    /// The commands a person runs. Never encoded onto the wire.
    ///
    /// The third line is here because a tarball extracted into a download folder
    /// is not an install, and because both executables have to land in the same
    /// directory. The download URL is deliberately unpinned and carries no
    /// checksum: a version and a hash Proctor cannot refresh would go stale and
    /// start instructing people to install an old build, which fails worse than
    /// an unpinned link to the project's own current release. The project page is
    /// named beside it as the authority.
    public static func installCommands(architecture: Architecture) -> [String] {
        let archive = "obscura-\(architecture.archiveSlug)-macos.tar.gz"
        return [
            "curl -LO \(docs)/releases/latest/download/\(archive)",
            "tar xzf \(archive)",
            "mkdir -p \(installDestination) && mv \(binary) \(companions.joined(separator: " ")) "
            + "\(installDestination)/"
        ]
    }
}
