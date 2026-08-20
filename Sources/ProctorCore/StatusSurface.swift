import Foundation

// PRO-0066. What the status window says, as a value.
//
// The window is a `View` and this repo cannot test one: `Package.swift` declares
// no `ProctorUI` test target and `swift test` has no window server. So the four
// states, the section list each resolves to, every user-facing string and every
// accessibility identifier live here, where a test can reach them, and the view
// is a projection.
//
// The clause that matters most is the agent-down one. When the agent is not
// answering, this window withholds the rest of itself rather than dimming it —
// a stale "Ready" pill over a dead agent is a false statement about a
// security-relevant grant, and it is the one failure this surface must not have.

public enum StatusSurface {

    /// What the window is showing. Not a superset of the agent's health: it is
    /// what a person is looking at.
    public enum State: String, Sendable, CaseIterable {
        /// Everything readable, every grant answered.
        case ready
        /// The first read has not come back yet.
        case checking
        /// The agent answers and something optional is not usable.
        case partial
        /// The agent is not answering. Nothing below the notice is live.
        case down
    }

    public enum Section: String, Sendable, CaseIterable {
        case permissions, tools, lanes, switches, activity, connect, agent, footer
        /// The block that replaces everything when the agent is unreachable.
        case agentDown
    }

    /// Which sections a state draws, in order.
    ///
    /// `down` returns exactly one section, and the test asserts nothing else is
    /// reachable from it. The alternative — drawing the sections greyed — leaves
    /// a permission row on screen that nothing has read, which is the defect.
    public static func sections(for state: State) -> [Section] {
        switch state {
        case .down:
            return [.agentDown]
        case .checking:
            return [.permissions, .footer]
        case .ready, .partial:
            return [.permissions, .tools, .lanes, .switches, .activity, .connect, .agent, .footer]
        }
    }

    /// Which state the window is in, from what the agent said.
    ///
    /// Pure, because this is the decision the whole surface turns on and a
    /// decision made inside a view body is one this repo cannot prove. `partial`
    /// is not a degraded `ready`: every permission is granted in both, and the
    /// difference is only whether some optional lane is unusable — which never
    /// changes what `ready` means.
    public static func state(reachable: Bool,
                             answered: Bool,
                             lanesAllUsable: Bool) -> State {
        guard answered else { return .checking }
        guard reachable else { return .down }
        return lanesAllUsable ? .ready : .partial
    }

    // MARK: - Copy
    //
    // Every user-facing string in the window. A literal in the view is a string
    // no test can see and no translator can find.

    public enum Copy {
        public static let windowTitle = "Proctor"

        public static let permissionsHeading = "Permissions"
        public static let permissionsNote =
            "Decisions macOS holds about Proctor. You change these in System Settings, "
            + "and Proctor can only read them."

        public static let toolsHeading = "Tools"
        public static let toolsNote =
            "What is on this Mac. Proctor finds these by reading the filesystem and never "
            + "runs them to check. It installs nothing — the commands are here for you to run."

        public static let lanesHeading = "Lanes"
        public static let lanesNote =
            "Derived from the grants and the tools found, never reported separately, so a "
            + "lane cannot claim to be ready while the thing it needs is missing."

        public static let switchesHeading = "Switches"
        public static let switchesNote =
            "What you see, then what Proctor may take, then which path a run takes. Drawing "
            + "switches start on; a capability starts off and stays off if either source says so."

        public static let activityHeading = "Activity"
        public static let connectHeading = "Connect a model"
        public static let agentHeading = "Agent"

        public static let checking = "Checking…"
        public static let ready = "Ready. Every permission Proctor needs is granted."

        // The agent-down block. The wording is load-bearing: it says what is
        // wrong, what it stops, and what to do, and it does not apologise.
        public static let downTitle = "The background agent is not answering."
        public static let downConsequence =
            "Until it is running, permissions cannot be read and no test can run. "
            + "Nothing below is live, so nothing below is shown."
        public static let downStart = "Start the agent"
        public static let downRecheck = "Re-check"

        public static let quit = "Quit Proctor"
        public static let quitNote = "Quit stops the background agent too. Both come back at the next login."
        public static let restart = "Restart the agent"
        public static let copySnippet = "Copy"
        public static let showHistory = "Show history"
    }

    // MARK: - Lane states
    //
    // Three, and the difference between the last two is the point. PRO-0041
    // closed a defect where a person was sent to fix a lane that was merely
    // unestablished; drawing them alike reintroduces it at the surface.

    public enum LaneState: String, Sendable, CaseIterable {
        case ready, unconfirmed, unavailable

        /// The pill token each renders with. `unconfirmed` and `unavailable`
        /// must not share one: one is a fact about what Proctor established,
        /// the other is something to go and fix.
        public var pill: String {
            switch self {
            case .ready: return "pill.ok"
            case .unconfirmed: return "pill.warn"
            case .unavailable: return "pill.bad"
            }
        }

        /// Whether this counts as usable. Fail-closed: `unconfirmed` reads false
        /// exactly as `unavailable` does, because a lane nothing established is
        /// not a lane known to work.
        public var isUsable: Bool { self == .ready }
    }

    // MARK: - Geometry
    //
    // The skeleton stands in for a permission row, so it is the same height. A
    // skeleton of the wrong height guarantees a jump when the real answer lands,
    // and this window polls every two seconds.

    public enum Geometry {
        public static let rowHeight: Double = 44
        public static let skeletonHeight: Double = rowHeight
        public static let sectionSpacing: Double = 26
        public static let windowWidth: Double = 640
    }

    // MARK: - Identifiers
    //
    // Durable selectors, so Proctor can drive its own UI and a replay survives a
    // layout change. The Cua research found an opaque per-snapshot handle
    // survives replay only by re-clicking absolute coordinates, which is what a
    // layout change breaks; this is the counter-claim made true of our own app.

    public enum ID {
        public static let window = "proctor.status.window"
        public static func state(_ s: State) -> String { "proctor.status.\(s.rawValue)" }
        public static func section(_ s: Section) -> String { "proctor.status.section.\(s.rawValue)" }
        public static func grantRow(_ name: String) -> String {
            "proctor.status.grant." + name.lowercased().replacingOccurrences(of: " ", with: "-")
        }
        public static func laneRow(_ lane: String) -> String { "proctor.status.lane.\(lane)" }
        public static func switchRow(_ variable: String) -> String {
            "proctor.status.switch." + variable.lowercased().replacingOccurrences(of: "_", with: "-")
        }
        public static let startAgent = "proctor.status.action.start-agent"
        public static let recheck = "proctor.status.action.recheck"
        public static let restartAgent = "proctor.status.action.restart-agent"
        public static let quit = "proctor.status.action.quit"
        public static let copyConnect = "proctor.status.action.copy-connect"
        public static let showHistory = "proctor.status.action.show-history"

        /// Every identifier this surface can emit, for the uniqueness test.
        public static var all: [String] {
            var out = [window, startAgent, recheck, restartAgent, quit, copyConnect, showHistory]
            out += State.allCases.map(state)
            out += Section.allCases.map(section)
            // Every grant the health report can carry. `Automation` was missing
            // and `Input Monitoring` was named but never emitted, so the
            // uniqueness test was checking a set that did not describe the
            // surface — found by the campaign photographing the window and
            // comparing it against this list.
            out += ["Accessibility", "Screen Recording", "Automation",
                    "Input Monitoring", "Shortcuts CLI"].map(grantRow)
            out += ["mac", "browser", "ios", "cua", "guest"].map(laneRow)
            out += SwitchCatalogue.all.map { switchRow($0.variable) }
            return out
        }
    }
}
