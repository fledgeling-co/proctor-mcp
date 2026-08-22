import Foundation

// PRO-0036. What each check in the status window can actually establish, and
// what would move its answer.
//
// **Everything here is pure**, and that is forced rather than preferred:
// `Package.swift` declares two test targets, `ProctorCoreTests` and
// `ProctorAgentTests`, and none for `ProctorUI`. There is no window server under
// `swift test`. So a rule written inside a SwiftUI view body is a rule this repo
// cannot prove, and every rule this feature depends on lives here instead. The
// window renders what these functions return. `AgentRecovery` (PRO-0041),
// `BrowserUseTool.statusSummary` (PRO-0035) and `Toolchain.row` (PRO-0050) are
// the same shape.
//
// The item this file exists for: three controls labelled `Re-check` and one line
// reading `Checked 14:32:01`, over a report whose answers do not all age the same
// way. Accessibility is re-read every poll. Every tool is re-stat'd every poll.
// Screen Recording is answered from a cache macOS holds **per process for the
// life of that process**, so a denial the agent has already been given is frozen
// until the agent restarts — see `GrantProbe`. One timestamp over all three is a
// claim that is true of two of them.
//
// MEASURED, 2026-08-15, and it is what deleted the footer's button rather than
// relabelling it: `AgentModel.stopPolling()` is called by nothing, so the 2-second
// poll runs for the application's whole life; and `lastChecked` is re-stamped on
// every landing report, so the clock beside that button already advances without
// it. It refreshed rows that refresh themselves, next to a clock that ticks
// itself, while the one row anybody presses it for cannot move at all.

/// What kind of thing a row in the status window is about, and — the part that
/// matters — what would change its answer.
///
/// The three permission cases are not decoration on one enum case: a person
/// looking at a denied permission needs to know whether waiting is enough,
/// whether they must go to System Settings, or whether nothing on screen will
/// move until the agent is restarted. Those are three different next actions.
public enum StatusCheckKind: String, Sendable, Equatable, CaseIterable {
    /// macOS re-reads this every time Proctor asks, so the poll picks up a grant
    /// made in System Settings on its own.
    case permissionReadLive
    /// macOS answers this once per agent process and then repeats itself. Only a
    /// fresh process asks again.
    case permissionSettledAtLaunch
    /// Only the target application's own prompt settles this, at first use. It
    /// cannot be established in advance, by any means, for any application.
    case permissionPerApplication
    /// Not a permission at all: a program on this machine. A decision macOS holds
    /// about Proctor and a file on a disk are different kinds of claim, and the
    /// window said them in one voice until this item.
    case tool
}

public enum StatusChecks {

    // MARK: - The names, and what kind each one is

    public static let accessibility = "Accessibility"
    public static let screenRecording = "Screen Recording"
    public static let automation = "Automation"
    public static let shortcutsCLI = "Shortcuts CLI"

    /// Every name the health report can put in its grants list.
    ///
    /// `Shortcuts CLI` is in here because the report calls it a grant — it is
    /// appended to `grants`, and only when it is *missing*. That is the defect
    /// this item corrects at the window; correcting it on the wire is somebody
    /// else's change, so this map is where the two views are reconciled.
    public static let inputMonitoring = "Input Monitoring"

    public static let known: [String: StatusCheckKind] = [
        accessibility: .permissionReadLive,
        screenRecording: .permissionSettledAtLaunch,
        automation: .permissionPerApplication,
        // `IOHIDCheckAccess` reports the recorded answer and shows no dialog, so
        // this is read live like Accessibility rather than settled at launch.
        inputMonitoring: .permissionReadLive,
        shortcutsCLI: .tool
    ]

    public static func kind(ofCheckNamed name: String) -> StatusCheckKind? {
        known[name]
    }

    /// Where an unrecognised name goes.
    ///
    /// **Not `Permissions`,** which was the first draft and was wrong. The
    /// permission names are a closed set macOS fixes; tools are the half that
    /// grows. So an unknown name is far likelier to be a new tool, and defaulting
    /// it into the permissions list would re-create the exact defect this item
    /// exists to remove. It is close to unreachable in any case: the drift test
    /// compares this map against the agent's own literals and reddens the build
    /// the moment they part company, so this is a net under a closed door.
    static let unknownFallsTo = StatusCheckKind.tool

    static func resolvedKind(ofCheckNamed name: String) -> StatusCheckKind {
        known[name] ?? unknownFallsTo
    }

    // MARK: - The partition

    /// The entries that belong in the permissions section: decisions macOS holds
    /// about Proctor, and nothing else.
    public static func permissions(in grants: [DoctorReport.Grant]) -> [DoctorReport.Grant] {
        grants.filter { resolvedKind(ofCheckNamed: $0.name) != .tool }
    }

    /// The entries the report files under grants that are really tools. Today
    /// that is the Shortcuts CLI, and only from an agent older than PRO-0082 on a
    /// Mac that is missing it — this agent no longer sends one.
    public static func misfiledTools(in grants: [DoctorReport.Grant]) -> [DoctorReport.Grant] {
        grants.filter { resolvedKind(ofCheckNamed: $0.name) == .tool }
    }

    /// Whether a name from a report's grants list belongs in a permissions
    /// surface, by name alone.
    ///
    /// PRO-0082. The two partitions above take `DoctorReport.Grant` values, which
    /// the TUI does not have: it reads the report as `JSONValue` and never
    /// decodes it. So the rule needs a spelling that takes the name, and it is
    /// this one rather than a second table — both go through `resolvedKind`, so a
    /// surface cannot hold an opinion the drift test does not check.
    public static func kindIsPermission(_ name: String) -> Bool {
        resolvedKind(ofCheckNamed: name) != .tool
    }

    // MARK: - What a permission row says

    /// The subtitle under a permission's name.
    ///
    /// **"Optional — asked for per app" is keyed on the check being the per-
    /// application kind, not on it being non-required.** That distinction is the
    /// whole of clause 3. The shipped view keyed it on `required == false`, so any
    /// optional entry produced Automation's sentence — which is how a command-line
    /// tool came to be described as something asked for per application. Removing
    /// the tool from the list would have hidden that, because Automation is
    /// currently the only optional permission left; keying on the kind makes it a
    /// rule instead of an accident that survives only while the list stays as it
    /// is. Behaviour on today's report is identical.
    /// The System Settings privacy pane a grant is granted in, or nil where
    /// macOS offers no pane for it.
    ///
    /// PRO-0081. An anchor is an identifier macOS matches, not words a person
    /// reads, and it moved here from the view for the same reason the rest of
    /// this file exists: the window has no test target, and a mapping nothing
    /// checks is one that goes wrong silently — an anchor macOS does not
    /// recognise opens the top of Settings and looks like the button did
    /// nothing.
    ///
    /// `Shortcuts CLI` and `Input Monitoring` are absent deliberately. The first
    /// is a program on a disk rather than a decision macOS holds; the second has
    /// no anchor of its own in this pane family.
    public static func settingsPane(for grant: String) -> String? {
        switch grant {
        case accessibility:   return "Privacy_Accessibility"
        case screenRecording: return "Privacy_ScreenCapture"
        case automation:      return "Privacy_Automation"
        default:              return nil
        }
    }

    public static func statusText(for grant: DoctorReport.Grant) -> String {
        if grant.granted { return "Granted" }
        if grant.resolvedState == .unconfirmed { return "Not established — macOS did not answer" }
        if resolvedKind(ofCheckNamed: grant.name) == .permissionPerApplication {
            return "Optional — asked for per app"
        }
        return grant.required ? "Required — not granted yet" : "Optional — not granted yet"
    }

    /// What would change this answer, or nil when there is nothing worth saying.
    ///
    /// **Keyed on the kind and the state together, never on the permission
    /// alone.** Screen Recording moves by two entirely different means depending
    /// on which state it is in: a definite denial needs a fresh agent process, and
    /// an unconfirmed probe needs nothing at all because it is retried on its own.
    /// One sentence for the permission would be false in one of those states, and
    /// the out-of-family review caught exactly that in the first draft.
    ///
    /// A *granted* row says nothing, deliberately. The same cache freezes a
    /// revocation, so a green row can outlive the permission it describes — but a
    /// caveat under every healthy permission on every working Mac is the permanent
    /// nag PRO-0028's critic forced out of the menu, and the two errors do not cost
    /// the same: a stale denial is silent and traps somebody into thinking their
    /// grant failed, where a stale grant fails loudly at the first capture.
    public static func mobility(of grant: DoctorReport.Grant) -> String? {
        guard !grant.granted else { return nil }
        switch resolvedKind(ofCheckNamed: grant.name) {
        case .permissionReadLive:
            return "Proctor notices this on its own, within a couple of seconds of you granting it."
        case .permissionSettledAtLaunch:
            if grant.resolvedState == .unconfirmed {
                // Must name neither a restart nor System Settings. Nothing is
                // wrong yet and nothing needs doing: the probe did not come back
                // inside its bound and is retried on a backoff.
                return "macOS did not answer in time. Proctor asks again on its own, "
                     + "so this is not a refusal."
            }
            return "macOS settled this answer when the agent started and will not revisit it. "
                 + "Granting it in Settings will not change this row until the agent restarts."
        case .permissionPerApplication, .tool:
            // Automation's own subtitle and its How text already say it, and a
            // tool has no business in this list at all.
            return nil
        }
    }

    // MARK: - The report's own freshness

    /// The footer's line.
    ///
    /// `Checked …` was one freshness claim laid over every answer in the window.
    /// True of the report, of every tool row and of Accessibility; false of a
    /// Screen Recording answer established when the agent launched, which may be
    /// hours old. What actually happened at this time is that Proctor asked.
    public static func reportFreshness(at time: String) -> String {
        "Asked the agent \(time)"
    }

    // MARK: - The tool rows

    /// One tool, ready to draw.
    ///
    /// `detail` is the report's own sentence, carried through unedited. The window
    /// used to write a second summary of Obscura beside the row the report had
    /// already decided, and two verdicts about one fact eventually disagree.
    public struct ToolRow: Sendable, Equatable {
        public var tool: String
        /// Short, derived from `usability` and `evidence` alone.
        public var status: String
        public var tone: Tone
        public var version: String?
        /// Proctor's own full sentence about this tool, from the report.
        public var detail: String?
        public var path: String?
        public var searched: [String]

        public enum Tone: String, Sendable, Equatable {
            case good, bad, unknown

            /// The SF Symbol each tone draws with.
            ///
            /// PRO-0081. It sits here rather than in the view for the same
            /// reason `StatusSurface.LaneState.pill` does: a mapping from a
            /// verdict to a token is a decision, and a decision in a view body
            /// is one this repo cannot prove. Colour is never the only carrier —
            /// the row's status text says the same thing in words.
            public var symbol: String {
                switch self {
                case .good:    return "checkmark.circle.fill"
                case .bad:     return "circle"
                case .unknown: return "questionmark.circle"
                }
            }
        }

        public init(tool: String, status: String, tone: Tone, version: String? = nil,
                    detail: String? = nil, path: String? = nil, searched: [String] = []) {
            self.tool = tool; self.status = status; self.tone = tone
            self.version = version; self.detail = detail
            self.path = path; self.searched = searched
        }
    }

    /// Every tool row the window should draw, in the report's own order.
    ///
    /// The Shortcuts CLI is appended last rather than faked into a `ToolPresence`:
    /// it is an OS component at a fixed absolute path, which is exactly why
    /// PRO-0050 kept it out of the `tools` array — a presence record for it would
    /// be a shape with three empty fields.
    ///
    /// **The second browser lane's invariant holds here for free.** The agent omits
    /// that tool from `tools` unless an operator named the lane, so there is no row
    /// and the window has nothing to render. This function does not need a rule
    /// about it, and a rule here would be a second place for the invariant to live.
    public static func toolRows(tools: [ToolPresence],
                                shortcutsCLIAvailable: Bool) -> [ToolRow] {
        tools.map(row(for:)) + [shortcutsRow(available: shortcutsCLIAvailable)]
    }

    static func row(for presence: ToolPresence) -> ToolRow {
        ToolRow(tool: presence.tool,
                status: status(for: presence),
                tone: tone(for: presence),
                version: presence.version,
                detail: presence.detail,
                path: presence.path,
                searched: presence.searched)
    }

    /// The Shortcuts CLI, which the report carries as a bare boolean.
    ///
    /// Proctor's own words here rather than a report sentence, because there is no
    /// report row to take one from.
    static func shortcutsRow(available: Bool) -> ToolRow {
        available
            ? ToolRow(tool: shortcutsCLI, status: "Usable — part of macOS", tone: .good,
                      detail: "Ships with macOS at a fixed path, so Proctor does not go looking "
                            + "for it. `shortcut` steps need it.",
                      path: "/usr/bin/shortcuts")
            : ToolRow(tool: shortcutsCLI, status: "Not on this Mac", tone: .bad,
                      detail: "/usr/bin/shortcuts is missing, so `shortcut` steps cannot run. "
                            + "Every other way Proctor drives an application is unaffected.")
    }

    /// The short line, from `usability` and `evidence` **only**.
    ///
    /// Deliberately not a function of the path or the version: two rows differing
    /// only in where a tool was found say the same thing about whether it works,
    /// and a status that quietly varied with the path would be a second verdict
    /// wearing a summary's clothes.
    static func status(for presence: ToolPresence) -> String {
        switch presence.usability {
        case .usable:
            switch presence.evidence {
            case .installPath:  return "Usable — version read from where it is installed"
            case .laneReport:   return "Usable — established when the lane was last used"
            default:            return "Usable — found"
            }
        case .unusable:
            switch presence.evidence {
            case .absent:       return "Not found"
            case .signature:    return "Found, but not signed by the identity its documentation names"
            case .laneReport:   return "Found, and the last preflight refused it"
            default:            return "Found, but not usable as it stands"
            }
        case .unconfirmed:
            switch presence.evidence {
            case .signature:    return "Found and correctly signed — nothing has established that it works"
            default:            return "Found — nothing has established that it works"
            }
        case .none:
            // An older agent, before the usability axis existed. `available` is
            // the only thing such a report says, and it is not a usability claim.
            return presence.available ? "Found" : "Not found"
        }
    }

    static func tone(for presence: ToolPresence) -> ToolRow.Tone {
        switch presence.usability {
        case .usable:       return .good
        case .unusable:     return .bad
        case .unconfirmed:  return .unknown
        case .none:         return presence.available ? .unknown : .bad
        }
    }
}
