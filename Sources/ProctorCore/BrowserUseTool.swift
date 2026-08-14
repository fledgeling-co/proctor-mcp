import Foundation

// browser-use: the second browser lane, and the two gates in front of it.
//
// Obscura is a bounded reader — fetch, eval, screenshot. `browser-use` is an
// **autonomous LLM agent**, and its default local mode attaches to the running
// Chrome over CDP with that person's cookies, extensions and logins. Naming it is
// not choosing a better instrument for a page; it is starting a second agent that
// can act as that person on every origin they are signed in to, and whose actions
// appear nowhere in Proctor's audit trail.
//
// That is why presence on disk is not enough. Installing a CLI is consent to have
// a file; it is not consent for a process holding Accessibility to name that file
// to a model that has a shell. So there are two gates and they do different jobs:
//
//   * `PROCTOR_SECOND_LANE` decides whether the name may appear **at all**. Unset
//     is Obscura-only, which is this machine's standing instruction as written.
//   * the binary on disk decides whether the lane is **usable**.
//
// Set-but-missing is its own state (`SecondLaneState.unavailable`) rather than a
// collapse to off, because an operator who enabled a lane and never sees it has to
// be told why by the thing that would have used it.
//
// There are deliberately **no install commands here**, and no path that produces
// any. Proctor asks nobody to install this. `absence` exists only for the
// set-but-missing state, and `ToolAbsence` cannot carry command text by
// construction — see `ToolPresence.swift`.

public enum BrowserUseTool {

    /// The official package's console script.
    public static let binary = "browser-use"

    /// None. browser-use is one console script; what it needs — a Chromium, a
    /// model credential — is not a sibling file and is not checkable by stat.
    public static let companions: [String] = []

    public static let docs = "https://docs.browser-use.com"

    /// The operator's switch. Named after the tool rather than being a boolean, so
    /// a third lane is a value rather than a second variable, and so the act says
    /// which tool is being consented to.
    public static let laneVariable = "PROCTOR_SECOND_LANE"

    /// The same directories PRO-0023 searches for Obscura, which already cover
    /// where a Python console script lands: `~/.local/bin` for pipx and
    /// `uv tool`, plus the two Homebrew prefixes.
    public static let extraDirectories = ToolLocator.commonToolDirectories

    /// Whether the operator has named this lane. Reads a supplied dictionary
    /// rather than `ProcessInfo`, because a process's environment is cached at
    /// launch and a test that reaches for the real one wins the whole process.
    public static func enabled(environment: [String: String]) -> Bool {
        guard let raw = environment[laneVariable] else { return false }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == binary
    }

    public static let missing =
        "The second browser lane is enabled but browser-use is not installed, or not anywhere "
        + "Proctor can see it. Proctor runs as a launchd agent, so it checks a fixed list of "
        + "locations rather than a login shell's PATH, and a project-local virtualenv is "
        + "invisible to it; proctor_doctor reports every path it checked."

    public static let askThePerson =
        "Proctor does not install this and has no opinion about whether it should be here. "
        + "The person driving you enabled the lane, so tell them it is not on the machine."

    /// Only ever emitted in the set-but-missing state. Carries no command text.
    public static var absence: ToolAbsence {
        ToolAbsence(tool: binary, missing: missing, docs: docs, askThePerson: askThePerson)
    }

    /// What the status window's row says, or `nil` for no row at all.
    ///
    /// A row appears exactly when the operator has named the lane. Presence alone
    /// buys no row: a machine whose own rule removed browser-use, and where
    /// somebody happens to have it installed for unrelated reasons, sees nothing
    /// anywhere — which is the same rule the handoff and `proctor_doctor` follow,
    /// so the gate is one invariant rather than three. Pure, and here rather than
    /// in the view, so it is testable without a window server.
    public static func statusSummary(secondLane: SecondLaneState, found: Bool) -> String? {
        switch secondLane {
        case .enabled:      return "second lane on"
        case .unavailable:  return "lane set, not installed"
        case .off:          return nil
        }
    }
}
