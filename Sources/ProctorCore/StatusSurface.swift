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
        /// What the Tools card says on screen.
        ///
        /// PRO-0081, closing PRO-0066's carried A2, moved this out of the view
        /// and found that Core already held a *different* sentence under this
        /// name — one the window has never rendered. Both are kept and both are
        /// named for what they are, because deleting either would hide the
        /// divergence rather than record it. See `toolsNoteInDesign` and DEF-035.
        public static let toolsNote =
            "Programs on this Mac that Proctor uses but does not ship. None of them is "
            + "a permission, and Proctor drives Mac apps without any of them."
        /// The design of record's wording for the same note, carried unrendered
        /// since PRO-0066. `design/surfaces/proctor-surfaces.html`, the
        /// `mac/status` pane. DEF-035.
        public static let toolsNoteInDesign =
            "What is on this Mac. Proctor finds these by reading the filesystem and never "
            + "runs them to check. It installs nothing — the commands are here for you to run."

        public static let lanesHeading = "Lanes"
        public static let lanesNote =
            "Derived from the grants and the tools found, never reported separately, so a "
            + "lane cannot claim to be ready while the thing it needs is missing."

        public static let switchesHeading = "Switches"
        /// What the Switches card says on screen. The same split as `toolsNote`,
        /// and the same defect record: DEF-035.
        public static let switchesNote =
            "How Proctor behaves while it runs. These are read by the background agent, "
            + "so all but the run panel take effect when it next starts."
        /// The design of record's wording, carried unrendered since PRO-0066.
        public static let switchesNoteInDesign =
            "What you see, then what Proctor may take, then which path a run takes. Drawing "
            + "switches start on; a capability starts off and stays off if either source says so."

        public static let activityHeading = "Activity"
        public static let connectHeading = "Connect a model to it"
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
        /// The word on all three of the window's Re-check buttons.
        ///
        /// One constant rather than three, because they say the same word for
        /// the same reason: each sits inside a remediation block, reads
        /// something uncached, and can change its answer once the instruction
        /// above it has been followed. PRO-0028's verdict table is what keeps
        /// the count at three; `StatusChecksTests` asserts which three.
        public static let recheck = "Re-check"

        public static let quit = "Quit Proctor"
        public static let quitNote = "Quit stops the background agent too. Both come back at the next login."
        public static let restart = "Restart the agent"
        public static let copySnippet = "Copy"
        public static let showHistory = "Show history"

        // MARK: The header
        //
        // PRO-0081 closing PRO-0066's carried A2. Everything below moved out of
        // `MainWindow.swift` unchanged: the wording is the reader's, settled in
        // wave 9, and this item moved where it lives rather than what it says.

        public static let headerLede =
            "Proctor lets a model test a Mac app: read what is actually on screen, "
            + "drive the controls, and check what the app rendered."
        public static let headerProcessNote =
            "It runs in the background as its own process. That is deliberate — macOS "
            + "attributes a permission to the process responsible for asking, so the "
            + "grants below belong to Proctor and keep working when you change or "
            + "upgrade the tool driving it."

        // MARK: The tools section

        public static let secondLaneDisclosure =
            "Proctor names browser-use for pages Obscura cannot open. It is an "
            + "autonomous agent driving a real browser with real credentials, and "
            + "nothing it does reaches Proctor's audit trail. Set by "
            + "PROCTOR_SECOND_LANE in the agent's launchd environment."
        public static let details = "Details"
        public static let obscuraTitle = "Obscura is not installed"
        public static let obscuraMessage =
            "Proctor hands browser pages to Obscura rather than driving them "
            + "through the accessibility tree, so without it that advice names a "
            + "command this Mac does not have. Proctor does not install it: these "
            + "commands download a binary from the internet, and this process holds "
            + "Accessibility and Screen Recording."
        public static let copyInstallCommands = "Copy install commands"
        public static let openProjectPage = "Open the project page"

        /// Where a tool was found, said beside the row that found it.
        public static func foundAt(_ path: String) -> String { "Found at \(path)" }

        /// The directories the agent looked in.
        ///
        /// These earn their place: the agent is started by the system and
        /// inherits none of a terminal's lookup settings, so "but it IS
        /// installed" is only ever settled by comparing where each side looked.
        public static func lookedIn(_ paths: [String]) -> String {
            "Looked in:\n" + paths.joined(separator: "\n")
        }

        // MARK: The switches section

        public static let restartToApply = "Restart agent to apply"
        public static let switchWriteErrorTitle = "That setting was not saved"
        public static let switchesStorageNote =
            "Saved in Proctor's own support folder, not in the launchd job, so "
            + "reinstalling does not lose them. Any program running as you can change "
            + "that file — it is a convenience, not a lock."
        public static let switchPending =
            "Saved. The running agent still has the old value — restart it to apply."
        public static let consentTitle = "Before you turn this on"
        public static let consentConfirm = "Turn it on"
        public static let cancel = "Cancel"
        public static let pairingWarningTitle = "Nothing on screen will say this is happening"
        public static let switchSourceUnknown = "Not yet known — waiting for the agent"

        /// Where the value the agent is running with came from.
        ///
        /// **A toggle that silently loses to an environment variable is worse
        /// than no toggle**, which is why this sentence sits beside every row
        /// rather than a bare switch. `nil` means the agent has not answered, and
        /// says so rather than showing a default as though it were a reading.
        public static func switchSource(on: Bool?, source: SwitchSource?, variable: String) -> String {
            guard let on else { return switchSourceUnknown }
            let value = on ? "On" : "Off"
            switch source {
            case .environment:
                return "\(value) — set by \(variable), which the agent inherited when it started"
            case .saved:
                return "\(value) — your saved setting"
            case .builtInDefault, .none:
                return "\(value) — Proctor's default"
            }
        }

        /// The tooltip on a switch the environment has taken away.
        public static func lockedHelp(variable: String) -> String {
            "\(variable) is set in the agent's environment, so it wins over anything saved here."
        }

        /// What turning a consent gate on actually hands over.
        ///
        /// Proctor's own words, and deliberately concrete: a person's keyboard,
        /// or a browser holding their real logins. `BrowserUseTool`'s existing
        /// disclosure is the model.
        public static func consentText(for aSwitch: ProctorSwitch) -> String {
            if aSwitch == SwitchCatalogue.secondLane {
                return "browser-use is an autonomous agent that drives a real browser with your "
                     + "real cookies and logins, and nothing it does reaches Proctor's audit "
                     + "trail. Turning this on names it to the model Proctor is serving. "
                     + "Proctor does not install it and has no opinion about whether it "
                     + "should be here."
            }
            return "Proctor will create an event tap that swallows your keyboard and mouse while "
                 + "it posts a step, so your typing cannot land in the app it is driving. While "
                 + "it is held, Escape stops the run, and Cmd-Tab, Force Quit, lock screen and "
                 + "the screenshot keys still reach the system."
        }

        // MARK: The activity section

        public static let activityRunning = "Running"
        public static let activityIdle = "Idle — no model is driving Proctor right now."
        public static let activityNone = "No activity to report."
        public static let activityIdleWithHistory = "Idle — last actions below."

        // MARK: The connect section

        public static let connectNote =
            "Add this to your MCP host's config. The command below holds no "
            + "permissions of its own — it forwards to Proctor, which does."
        public static let copyConfig = "Copy config"
        public static let copyCommandPath = "Copy command path only"

        /// The MCP host config, with this bundle's own shim path in it.
        ///
        /// Assembled here rather than in the view because it is the one thing on
        /// this card a person copies and pastes into another program, and a
        /// string nobody can test is a string that ships wrong once.
        public static func connectSnippet(shimPath: String) -> String {
            """
            {
              "mcpServers": {
                "proctor": { "command": "\(shimPath)" }
              }
            }
            """
        }

        // MARK: The agent section

        public static let agentSectionHeading = "Background agent"
        public static let agentVersionLabel = "Version"
        public static let agentWindowLabel = "This window"
        public static let agentOSLabel = "macOS"
        public static let agentSocketLabel = "Socket"
        public static let agentAttachedLabel = "Attached apps"
        public static let agentAttachedNone = "none"
        public static let agentObserversLabel = "Live observers"
        public static let agentSignatureLabel = "Signature"
        public static let agentAbsent = "No agent to report on."
        public static let secureInputTitle = "Secure Event Input is active"
        public static let secureInputMessage =
            "Something on this Mac — usually a password field — is holding "
            + "secure input. Reading the accessibility tree and driving "
            + "controls still work; synthesised keystrokes do not."

        /// The agent's version beside the protocol it speaks.
        public static func agentVersion(_ version: String, protocolVersion: Int) -> String {
            "\(version)  ·  protocol \(protocolVersion)"
        }

        // MARK: The footer, and the pill
        //
        // The footer's own `Re-check` is deliberately absent; `recheck` above
        // says which three survive and why.

        public static let openLog = "Open log"
        /// The footer's label for the restart action. `restart` is the longer
        /// form PRO-0066 wrote for the same action and the window has never
        /// rendered; both are kept and named, as with `toolsNote`. DEF-035.
        public static let restartAgent = "Restart agent"

        public static let pillApplying = "Applying"
        public static let pillChecking = "Checking"
        public static let pillDown = "Agent down"
        public static let pillReady = "Ready"
        public static let pillNeedsPermission = "Needs permission"

        // MARK: The permissions section

        public static let applying = "Applying the new permission…"
        /// The one-line form, said beside the permission rows. `downConsequence`
        /// is the longer form the agent-down block uses instead of the window.
        public static let permissionsDownConsequence =
            "Until it is running, permissions cannot be read and no test can run."
        public static let recoveryTitle = "The agent is holding an out-of-date answer"
        public static let adHocTitle = "This build is ad-hoc signed"
        public static let adHocMessage =
            "macOS ties these grants to the exact bytes of this build, so "
            + "rebuilding Proctor silently revokes them — and a revoked grant "
            + "shows up as \"element not found\", not as a permission error. "
            + "A Developer ID signed and notarised build keeps its grants "
            + "across upgrades."
        public static let updatedTitle = "Proctor was updated"
        public static let relaunch = "Relaunch Proctor"
        public static let openSettings = "Open Settings"
        public static let how = "How"
        public static let hide = "Hide"

        /// Why a stale window matters, and what relaunching will and will not do.
        ///
        /// Keyed on whether the agent's own binary moved, because the two answers
        /// end differently: one ends a run in flight and the other deliberately
        /// leaves it alone.
        public static func updatedMessage(agentReplaced: Bool) -> String {
            "The app on disk is a newer build than the one running, so "
            + "anything this window reports comes from the old one. "
            + (agentReplaced
               ? "The agent's binary changed too, so relaunching restarts it "
                 + "as well — which ends any run in flight."
               : "The installer already restarted the agent on the new build; "
                 + "relaunching leaves it, and any run in flight, alone.")
        }
        /// Every constant here, name and value.
        ///
        /// PRO-0081. `ID.all` has existed since PRO-0066 so the uniqueness test
        /// could see the whole identifier set; this is its counterpart for the
        /// words, and it exists for the reason the doc comment above gives —
        /// **no translator can find a literal in a view**. A constant missing
        /// from this list is invisible to the tests below in exactly the way a
        /// literal in the view was, so adding one and forgetting this list
        /// reintroduces the problem one string at a time; `StatusSurfaceTests`
        /// counts the declarations in this file against the length of this list
        /// rather than trusting it to be complete.
        public static var all: [(name: String, text: String)] {
            [
             ("windowTitle", windowTitle),
             ("permissionsHeading", permissionsHeading),
             ("permissionsNote", permissionsNote),
             ("toolsHeading", toolsHeading),
             ("toolsNote", toolsNote),
             ("toolsNoteInDesign", toolsNoteInDesign),
             ("lanesHeading", lanesHeading),
             ("lanesNote", lanesNote),
             ("switchesHeading", switchesHeading),
             ("switchesNote", switchesNote),
             ("switchesNoteInDesign", switchesNoteInDesign),
             ("activityHeading", activityHeading),
             ("connectHeading", connectHeading),
             ("agentHeading", agentHeading),
             ("checking", checking),
             ("ready", ready),
             ("downTitle", downTitle),
             ("downConsequence", downConsequence),
             ("downStart", downStart),
             ("recheck", recheck),
             ("quit", quit),
             ("quitNote", quitNote),
             ("restart", restart),
             ("copySnippet", copySnippet),
             ("showHistory", showHistory),
             ("headerLede", headerLede),
             ("headerProcessNote", headerProcessNote),
             ("secondLaneDisclosure", secondLaneDisclosure),
             ("details", details),
             ("obscuraTitle", obscuraTitle),
             ("obscuraMessage", obscuraMessage),
             ("copyInstallCommands", copyInstallCommands),
             ("openProjectPage", openProjectPage),
             ("restartToApply", restartToApply),
             ("switchWriteErrorTitle", switchWriteErrorTitle),
             ("switchesStorageNote", switchesStorageNote),
             ("switchPending", switchPending),
             ("consentTitle", consentTitle),
             ("consentConfirm", consentConfirm),
             ("cancel", cancel),
             ("pairingWarningTitle", pairingWarningTitle),
             ("switchSourceUnknown", switchSourceUnknown),
             ("activityRunning", activityRunning),
             ("activityIdle", activityIdle),
             ("activityNone", activityNone),
             ("activityIdleWithHistory", activityIdleWithHistory),
             ("connectNote", connectNote),
             ("copyConfig", copyConfig),
             ("copyCommandPath", copyCommandPath),
             ("agentSectionHeading", agentSectionHeading),
             ("agentVersionLabel", agentVersionLabel),
             ("agentWindowLabel", agentWindowLabel),
             ("agentOSLabel", agentOSLabel),
             ("agentSocketLabel", agentSocketLabel),
             ("agentAttachedLabel", agentAttachedLabel),
             ("agentAttachedNone", agentAttachedNone),
             ("agentObserversLabel", agentObserversLabel),
             ("agentSignatureLabel", agentSignatureLabel),
             ("agentAbsent", agentAbsent),
             ("secureInputTitle", secureInputTitle),
             ("secureInputMessage", secureInputMessage),
             ("openLog", openLog),
             ("restartAgent", restartAgent),
             ("pillApplying", pillApplying),
             ("pillChecking", pillChecking),
             ("pillDown", pillDown),
             ("pillReady", pillReady),
             ("pillNeedsPermission", pillNeedsPermission),
             ("applying", applying),
             ("permissionsDownConsequence", permissionsDownConsequence),
             ("recoveryTitle", recoveryTitle),
             ("adHocTitle", adHocTitle),
             ("adHocMessage", adHocMessage),
             ("updatedTitle", updatedTitle),
             ("relaunch", relaunch),
             ("openSettings", openSettings),
             ("how", how),
             ("hide", hide)
            ]
        }

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
