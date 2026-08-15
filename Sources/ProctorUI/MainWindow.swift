import SwiftUI
import AppKit
import ProctorCore

struct MainWindow: View {
    let model: AgentModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                Header()
                ReadinessSection(model: model)
                ToolsSection(model: model)
                SwitchesSection(model: model)
                ActivitySection(model: model)
                ConnectSection(model: model)
                AgentSection(model: model)
                FooterSection(model: model)
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

// MARK: - Header

private struct Header: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "rectangle.on.rectangle.angled")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.tint)
                Text("Proctor").font(.system(size: 26, weight: .semibold))
                Spacer()
            }
            Text("Proctor lets a model test a Mac app: read what is actually on screen, "
                 + "drive the controls, and check what the app rendered.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("It runs in the background as its own process. That is deliberate — macOS "
                 + "attributes a permission to the process responsible for asking, so the "
                 + "grants below belong to Proctor and keep working when you change or "
                 + "upgrade the tool driving it.")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Readiness

private struct ReadinessSection: View {
    let model: AgentModel

    var body: some View {
        Card {
            HStack(alignment: .firstTextBaseline) {
                SectionTitle("Permissions")
                Spacer()
                StatusPill(model: model)
            }
            // What a permission *is*, said once, so this section and the Tools
            // section below it read as two kinds of claim rather than one list
            // with a mixed subtitle. That mixture is what put a command-line tool
            // under "Optional — asked for per app".
            Text("Decisions macOS holds about Proctor. You change these in System Settings, "
                 + "and Proctor can only read them.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            switch model.reachability {
            case .unknown:
                Text("Checking…").font(.system(size: 12)).foregroundStyle(.secondary)

            case .unreachable(let why):
                if model.isApplying {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Applying the new permission…")
                            .font(.system(size: 13, weight: .medium))
                    }
                } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("The background agent is not answering.")
                        .font(.system(size: 13, weight: .medium))
                    Text(why).font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Until it is running, permissions cannot be read and no test can run.")
                        .font(.system(size: 12)).foregroundStyle(.tertiary)
                    HStack {
                        Button("Start the agent") { Actions.ensureAgent(); model.refresh() }
                            .buttonStyle(.borderedProminent)
                        Button("Re-check") { model.refresh() }
                    }
                }
                }

            case .reachable:
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(model.requiredGrants, id: \.name) { grant in
                        GrantRow(grant: grant)
                        Divider().padding(.vertical, 2)
                    }
                    ForEach(model.optionalGrants, id: \.name) { grant in
                        GrantRow(grant: grant)
                    }
                }
                if model.ready {
                    Label("Ready. Every permission Proctor needs is granted.",
                          systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.green)
                        .padding(.top, 4)
                }
                // The remedy for the one answer no re-read can move, beside the
                // permission it is about.
                //
                // `AgentRecovery.decide` already ran — the model recomputes it on
                // every doctor tick and every HUD tick — and this renders what it
                // returned rather than deciding again. Its gate is load-bearing and
                // stays where it is: the restart is offered only when THIS process
                // can see the grant for itself, so a Mac that has never granted
                // Screen Recording gets no permanent row with a button that could
                // not create a permission. Reason and button together, because a
                // person who has to finish a paragraph before finding the action
                // has been given a reading assignment instead of a remedy.
                //
                // Only `.restartAgent` can appear here: `.startAgent` belongs to the
                // unreachable branch above, which has its own button.
                if let offer = model.recovery, offer.kind == .restartAgent {
                    Callout(icon: "arrow.clockwise.circle.fill", tint: .orange,
                            title: "The agent is holding an out-of-date answer",
                            message: offer.reason)
                    Button(offer.action) { model.take(offer) }
                        .buttonStyle(.borderedProminent)
                }
                if model.signature.isAdHoc {
                    Callout(
                        icon: "exclamationmark.triangle.fill",
                        tint: .orange,
                        title: "This build is ad-hoc signed",
                        message: "macOS ties these grants to the exact bytes of this build, so "
                            + "rebuilding Proctor silently revokes them — and a revoked grant "
                            + "shows up as \"element not found\", not as a permission error. "
                            + "A Developer ID signed and notarised build keeps its grants "
                            + "across upgrades.")
                }
                if model.buildReplaced {
                    // Said here as well as in the menu, because this window is
                    // where somebody comes to find out why Proctor is behaving
                    // oddly — and "the window you are reading was built before the
                    // thing you are asking about" is the first useful answer.
                    VStack(alignment: .leading, spacing: 6) {
                        Callout(
                            icon: "arrow.triangle.2.circlepath",
                            tint: .orange,
                            title: "Proctor was updated",
                            message: "The app on disk is a newer build than the one running, so "
                                + "anything this window reports comes from the old one. "
                                + (model.agentBuildReplaced
                                   ? "The agent's binary changed too, so relaunching restarts it "
                                     + "as well — which ends any run in flight."
                                   : "The installer already restarted the agent on the new build; "
                                     + "relaunching leaves it, and any run in flight, alone."))
                        Button("Relaunch Proctor") { Actions.relaunch(alsoAgent: model.agentBuildReplaced) }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
    }
}

private struct GrantRow: View {
    let grant: DoctorReport.Grant
    @State private var showHow = false

    // An unconfirmed grant is not a denial and must not be dressed as one. The
    // Open Settings button is the specific thing that has to go: macOS did not
    // answer the probe, the permission may well be granted, and sending somebody
    // to a switch they already flipped is the defect PRO-0041 fixed. The How
    // button stays, because its text now says what actually happened.
    private var unconfirmed: Bool { grant.resolvedState == .unconfirmed }

    // Both decided in Core, where they can be tested. `statusText` moved there
    // unchanged so that "Optional — asked for per app" became a rule about
    // Automation rather than an accident of who was left in the list; `mobility`
    // is the sentence saying what would move this answer, and it is keyed on the
    // kind AND the state, because a denied Screen Recording grant needs a restart
    // and an unconfirmed one needs nothing at all.
    private var statusText: String { StatusChecks.statusText(for: grant) }
    private var mobility: String? { StatusChecks.mobility(of: grant) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: grant.granted ? "checkmark.circle.fill"
                      : (unconfirmed ? "questionmark.circle" : "circle"))
                    .foregroundStyle(grant.granted ? Color.green
                                     : (unconfirmed ? Color.secondary
                                        : (grant.required ? Color.orange : Color.secondary)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(grant.name).font(.system(size: 13, weight: .medium))
                    Text(statusText)
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                if !grant.granted, !unconfirmed, let pane = Actions.pane(for: grant.name) {
                    Button("Open Settings") { Actions.openPane(pane) }
                        .controlSize(.small)
                }
                if !grant.granted {
                    Button(showHow ? "Hide" : "How") { showHow.toggle() }
                        .controlSize(.small).buttonStyle(.borderless)
                }
            }
            if let mobility {
                Text(mobility)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 26)
            }
            if showHow {
                Text(grant.howToFix)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 26)
            }
        }
        .padding(.vertical, 7)
    }
}

// MARK: - Tools

/// Programs on this Mac, which are not permissions and no longer pretend to be.
///
/// A grant is a decision macOS holds about Proctor; a tool is a file on a disk.
/// They shared a card and a subtitle until this item, which is how the Shortcuts
/// CLI came to be described as "asked for per app" — Automation's sentence.
///
/// Every row here is a verdict the report already reached. `Toolchain.row`
/// (PRO-0050) decides usability and evidence; this draws them. The window used to
/// write its own summary of Obscura beside that verdict, and two opinions about
/// one fact eventually disagree.
private struct ToolsSection: View {
    let model: AgentModel

    private var rows: [StatusChecks.ToolRow] {
        guard let r = model.report else { return [] }
        return StatusChecks.toolRows(tools: r.tools,
                                     shortcutsCLIAvailable: r.shortcutsCLIAvailable)
    }

    /// Whether the second browser lane's row is on screen at all. It is present
    /// only when an operator named the lane — the agent omits it from the report
    /// otherwise — so this reads the rows rather than re-deriving the switch.
    private var showsSecondLane: Bool {
        rows.contains { $0.tool == BrowserUseTool.binary }
    }

    var body: some View {
        // No report means nothing to say. A heading over an empty card would be
        // its own small falsehood.
        if model.report != nil {
            Card {
                SectionTitle("Tools")
                Text("Programs on this Mac that Proctor uses but does not ship. None of them is "
                     + "a permission, and Proctor drives Mac apps without any of them.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.tool) { index, row in
                        if index > 0 { Divider().padding(.vertical, 2) }
                        ToolRowView(row: row)
                    }
                }

                if showsSecondLane {
                    // Moved here with its row rather than left behind in the agent
                    // card. It is a safety disclosure about what that tool is, and
                    // it belongs beside the tool it is about.
                    Text("Proctor names browser-use for pages Obscura cannot open. It is an "
                         + "autonomous agent driving a real browser with real credentials, and "
                         + "nothing it does reaches Proctor's audit trail. Set by "
                         + "PROCTOR_SECOND_LANE in the agent's launchd environment.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let absence = model.report?.obscuraUnavailable {
                    ObscuraOffer(absence: absence, model: model)
                }
            }
        }
    }
}

private struct ToolRowView: View {
    let row: StatusChecks.ToolRow
    @State private var showDetail = false

    private var tint: Color {
        switch row.tone {
        case .good:    return .green
        case .bad:     return .orange
        case .unknown: return .secondary
        }
    }

    private var symbol: String {
        switch row.tone {
        case .good:    return "checkmark.circle.fill"
        case .bad:     return "circle"
        case .unknown: return "questionmark.circle"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: symbol).foregroundStyle(tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.tool).font(.system(size: 13, weight: .medium, design: .monospaced))
                    Text(row.status).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                if let version = row.version {
                    Text(version)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                if row.detail != nil || !row.searched.isEmpty {
                    Button(showDetail ? "Hide" : "Details") { showDetail.toggle() }
                        .controlSize(.small).buttonStyle(.borderless)
                }
            }
            if showDetail {
                VStack(alignment: .leading, spacing: 4) {
                    if let detail = row.detail {
                        Text(detail)
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let path = row.path {
                        Text("Found at \(path)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .textSelection(.enabled)
                    }
                    // The paths earn their place: the agent is started by the
                    // system and inherits none of a terminal's lookup settings, so
                    // "but it IS installed" is only ever settled by comparing where
                    // each side looked.
                    if !row.searched.isEmpty {
                        Text("Looked in:\n" + row.searched.joined(separator: "\n"))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.leading, 26)
            }
        }
        .padding(.vertical, 7)
    }
}

// MARK: - Switches

/// PRO-0029. The eight runtime switches, with where each value came from.
///
/// **A toggle that silently loses to an environment variable is worse than no
/// toggle**, which is the whole reason this card shows a source beside every
/// value rather than a switch on its own. Every rule it renders — precedence, the
/// lock, the pending state, the pairing warnings — is decided in `SwitchResolver`
/// and `SwitchCatalogue`, because `Package.swift` declares no `ProctorUI` test
/// target and there is no window server under `swift test`. This view draws
/// answers; it reaches none.
///
/// The running value comes from the agent's report and from nowhere else. This
/// process is started by LaunchServices and the agent by launchd, so reading
/// `ProcessInfo` here would describe a different process's environment — and would
/// describe it plausibly, which is worse than reading "not yet known".
private struct SwitchesSection: View {
    let model: AgentModel

    private var rows: [AgentModel.SwitchRow] { model.switchRows }

    var body: some View {
        Card {
            HStack(alignment: .firstTextBaseline) {
                SectionTitle("Switches")
                Spacer()
                if model.switchesNeedRestart {
                    Button("Restart agent to apply") { model.restartAgentForSwitches() }
                        .controlSize(.small)
                        .buttonStyle(.borderedProminent)
                }
            }
            Text("How Proctor behaves while it runs. These are read by the background agent, "
                 + "so all but the run panel take effect when it next starts.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 { Divider().padding(.vertical, 2) }
                    SwitchRowView(row: row, model: model)
                }
            }

            if let error = model.switchWriteError {
                Callout(icon: "exclamationmark.triangle.fill", tint: .orange,
                        title: "That setting was not saved",
                        message: error)
            }

            // Said once, at the bottom, rather than on eight rows. It is a fact
            // about the file rather than about any one switch, and a caveat
            // repeated eight times is one nobody reads.
            Text("Saved in Proctor's own support folder, not in the launchd job, so "
                 + "reinstalling does not lose them. Any program running as you can change "
                 + "that file — it is a convenience, not a lock.")
                .font(.system(size: 10)).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct SwitchRowView: View {
    let row: AgentModel.SwitchRow
    let model: AgentModel
    @State private var confirming = false

    /// The two switches that hand something away — a person's own keyboard, or a
    /// browser with their real logins to an autonomous agent. Decided in the
    /// catalogue, where it is testable, rather than re-derived from a shape here.
    private var isConsentGate: Bool { row.aSwitch.requiresConsent }

    private var sourceLine: String {
        guard let running = row.running else {
            return "Not yet known — waiting for the agent"
        }
        switch SwitchSource(rawValue: running.source) {
        case .environment:
            return "\(running.on ? "On" : "Off") — set by \(row.aSwitch.variable), which the "
                 + "agent inherited when it started"
        case .saved:
            return "\(running.on ? "On" : "Off") — your saved setting"
        case .builtInDefault, .none:
            return "\(running.on ? "On" : "Off") — Proctor's default"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(row.aSwitch.title).font(.system(size: 13, weight: .medium))
                        Text(row.aSwitch.variable)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                    Text(row.aSwitch.summary)
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(sourceLine)
                        .font(.system(size: 11))
                        .foregroundStyle(row.locked ? AnyShapeStyle(Color.orange)
                                                   : AnyShapeStyle(.tertiary))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 12)
                Toggle("", isOn: Binding(
                    get: { row.controlOn },
                    set: { wanted in
                        // Turning a consent gate ON asks twice. Turning anything
                        // off never does: a person withdrawing a capability must
                        // not be argued with.
                        if wanted, isConsentGate, !confirming { confirming = true; return }
                        confirming = false
                        model.setSwitch(row.aSwitch, on: wanted)
                    }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .disabled(row.locked)
                    .help(row.locked
                          ? "\(row.aSwitch.variable) is set in the agent's environment, so it "
                          + "wins over anything saved here."
                          : "")
            }

            if row.pending {
                Text("Saved. The running agent still has the old value — restart it to apply.")
                    .font(.system(size: 11)).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // The disclosure sits ABOVE the confirmation, so the thing being
            // consented to is on screen before the second press is offered.
            if confirming {
                VStack(alignment: .leading, spacing: 8) {
                    Callout(icon: "exclamationmark.shield.fill", tint: .orange,
                            title: "Before you turn this on",
                            message: consentText)
                    HStack {
                        Button("Turn it on") {
                            confirming = false
                            model.setSwitch(row.aSwitch, on: true)
                        }
                        .buttonStyle(.borderedProminent)
                        Button("Cancel") { confirming = false }
                    }
                }
            }

            if let warning = row.running?.pairingWarning {
                Callout(icon: "eye.slash.fill", tint: .orange,
                        title: "Nothing on screen will say this is happening",
                        message: warning)
            }
        }
        .padding(.vertical, 8)
    }

    /// Proctor's own words, and deliberately concrete about what is handed over.
    /// `BrowserUseTool`'s existing disclosure is the model.
    private var consentText: String {
        if row.aSwitch == SwitchCatalogue.secondLane {
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
}

// MARK: - Activity

private struct ActivitySection: View {
    let model: AgentModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Card {
            HStack(alignment: .firstTextBaseline) {
                SectionTitle("Activity")
                Spacer()
                // This card answers "what is it doing"; the History window
                // answers "what did it do". Reaching one from the other is the
                // shortest path between the two questions a person actually asks.
                Button("Show history") {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "history")
                }
                .controlSize(.small)
            }
            if let current = model.currentActivity {
                HStack(spacing: 8) {
                    LiveDot(reduceMotion: reduceMotion)
                    Text("Running").font(.system(size: 13, weight: .medium))
                    Text(current).font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.tint)
                    Spacer()
                }
            } else if model.recentActivity.isEmpty {
                Text(model.reachability == .reachable
                     ? "Idle — no model is driving Proctor right now."
                     : "No activity to report.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            } else {
                Text("Idle — last actions below.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }

            if !model.recentActivity.isEmpty {
                Divider().padding(.vertical, 2)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(model.recentActivity.prefix(6)) { item in
                        ActivityRow(item: item)
                    }
                }
            }
        }
    }
}

private struct ActivityRow: View {
    let item: AgentModel.ActivityItem
    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: item.ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(item.ok ? Color.green : Color.orange)
            Text(item.tool)
                .font(.system(size: 12, design: .monospaced))
            Spacer()
            Text(item.at, format: .relative(presentation: .numeric))
                .font(.system(size: 10)).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

/// A green dot that softly pulses while a tool is in flight; static under
/// reduced motion so the "running" state is still legible without animation.
private struct LiveDot: View {
    let reduceMotion: Bool
    @State private var on = false
    var body: some View {
        Circle().fill(Color.green)
            .frame(width: 8, height: 8)
            .opacity(reduceMotion ? 1 : (on ? 1 : 0.35))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    on = true
                }
            }
    }
}

// MARK: - Connect

private struct ConnectSection: View {
    let model: AgentModel

    private var shimPath: String {
        Bundle.main.bundlePath + "/Contents/MacOS/proctor-shim"
    }

    private var snippet: String {
        """
        {
          "mcpServers": {
            "proctor": { "command": "\(shimPath)" }
          }
        }
        """
    }

    var body: some View {
        Card {
            SectionTitle("Connect a model to it")
            Text("Add this to your MCP host's config. The command below holds no "
                 + "permissions of its own — it forwards to Proctor, which does.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(snippet)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .quaternarySystemFill), in: RoundedRectangle(cornerRadius: 6))
            HStack {
                Button("Copy config") { Actions.copy(snippet) }
                Button("Copy command path only") { Actions.copy(shimPath) }
                    .buttonStyle(.borderless).controlSize(.small)
            }
        }
    }
}

// MARK: - Agent

private struct AgentSection: View {
    let model: AgentModel

    var body: some View {
        Card {
            SectionTitle("Background agent")
            // Facts about the running process. Tools moved to their own section:
            // "which programs are on this Mac" and "what is this process" are
            // different questions, and answering both in one grid is what let a
            // CLI be reported twice, in two registers, in two places.
            if let r = model.report {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                    Row("Version", "\(r.agentVersion)  ·  protocol \(r.protocolVersion)")
                    // The window is its own process from its own copy of the bundle,
                    // and an upgrade can leave the two halves on different builds for
                    // hours. Normally these two strings match; when they do not, the
                    // difference is the diagnosis, in words rather than in timestamps
                    // somebody has to go and read.
                    Row("This window", BuildInfo.current.descriptor)
                    Row("macOS", r.osVersion)
                    Row("Socket", r.socketPath)
                    Row("Attached apps", r.attachedApps.isEmpty
                        ? "none" : r.attachedApps.map(\.name).joined(separator: ", "))
                    Row("Live observers", "\(r.observersLive)")
                    Row("Signature", model.signature.summary)
                }
                if r.secureEventInputActive {
                    Callout(
                        icon: "keyboard.badge.ellipsis",
                        tint: .orange,
                        title: "Secure Event Input is active",
                        message: "Something on this Mac — usually a password field — is holding "
                            + "secure input. Reading the accessibility tree and driving "
                            + "controls still work; synthesised keystrokes do not.")
                }
            } else {
                Text("No agent to report on.").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }

    private struct Row: View {
        let k: String, v: String
        init(_ k: String, _ v: String) { self.k = k; self.v = v }
        var body: some View {
            GridRow {
                Text(k).font(.system(size: 11)).foregroundStyle(.secondary)
                Text(v).font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(2).truncationMode(.middle)
            }
        }
    }
}

/// What "offer to install" means here: the exact command for this Mac, one click
/// away, and a re-check that confirms it worked.
///
/// Proctor does not run it. The install is a download of an unsigned binary from
/// the internet, and this process holds Accessibility and Screen Recording; the
/// window's answer to a missing permission is *Open Settings* rather than granting
/// it, and a missing tool gets the same shape of answer.
private struct ObscuraOffer: View {
    let absence: ToolAbsence
    let model: AgentModel

    private var commands: [String] {
        ObscuraTool.installCommands(architecture: Actions.hardwareArchitecture())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Callout(
                icon: "arrow.down.circle",
                tint: .orange,
                title: "Obscura is not installed",
                message: "Proctor hands browser pages to Obscura rather than driving them "
                    + "through the accessibility tree, so without it that advice names a "
                    + "command this Mac does not have. Proctor does not install it: these "
                    + "commands download a binary from the internet, and this process holds "
                    + "Accessibility and Screen Recording.")
            Text(commands.joined(separator: "\n"))
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .quaternarySystemFill),
                            in: RoundedRectangle(cornerRadius: 6))
            HStack {
                Button("Copy install commands") { Actions.copy(commands.joined(separator: "\n")) }
                Button("Open the project page") { Actions.open(absence.docs) }
                    .buttonStyle(.borderless).controlSize(.small)
                Button("Re-check") { model.refresh() }
                    .buttonStyle(.borderless).controlSize(.small)
            }
        }
    }
}

// MARK: - Footer

private struct FooterSection: View {
    let model: AgentModel

    // The footer's `Re-check` is deliberately gone. PRO-0028 deleted a menu row on
    // two grounds and both applied here unchanged: the 2-second poll already did
    // everything it did, and the press a person is motivated to make — the frozen
    // Screen Recording row — is the one it could not serve. Measured before
    // deciding: `stopPolling()` is called by nothing, so the poll runs for the
    // app's whole life; and `lastChecked` is re-stamped by every landing report,
    // so the clock below already advances without a button. It refreshed rows that
    // refresh themselves, beside a clock that ticks itself.
    //
    // The two surviving `Re-check` buttons are not this one. Each sits inside a
    // remediation block — "the agent is not answering", "Obscura is not installed"
    // — reads something uncached, and changes its answer when pressed after the
    // instruction above it has been followed. `Restart agent` stays here as the
    // one action that can move what the poll cannot.
    var body: some View {
        HStack(spacing: 10) {
            Button("Open log") { Actions.openLog() }
            Button("Restart agent") { Actions.restartAgent(); model.refresh() }
            Spacer()
            if let t = model.lastChecked {
                // "Checked …" was one freshness claim over every answer above it,
                // and false for the one that is settled at the agent's launch.
                // What happened at this time is that Proctor asked.
                Text(StatusChecks.reportFreshness(
                        at: t.formatted(date: .omitted, time: .standard)))
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Pieces

private struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .tracking(0.8)
            .foregroundStyle(.secondary)
    }
}

private struct StatusPill: View {
    let model: AgentModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let (label, tint): (String, Color) = {
            if model.isApplying { return ("Applying", .secondary) }
            switch model.reachability {
            case .unknown: return ("Checking", .secondary)
            case .unreachable: return ("Agent down", .red)
            case .reachable: return model.ready ? ("Ready", .green) : ("Needs permission", .orange)
            }
        }()
        Text(label)
            .font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(tint.opacity(0.14), in: Capsule())
            .foregroundStyle(tint)
            .id(label)
            .transition(reduceMotion ? .opacity
                        : .scale(scale: 0.88).combined(with: .opacity))
            .animation(reduceMotion ? nil : Motion.med, value: label)
    }
}

private struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1))
    }
}

private struct Callout: View {
    let icon: String, tint: Color, title: String, message: String
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: icon).foregroundStyle(tint).font(.system(size: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(message).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
    }
}

// MARK: - Side effects

enum Actions {
    static func pane(for grant: String) -> String? {
        switch grant {
        case "Accessibility":   return "Privacy_Accessibility"
        case "Screen Recording": return "Privacy_ScreenCapture"
        case "Automation":      return "Privacy_Automation"
        default:                return nil
        }
    }

    static func openPane(_ anchor: String) {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!
        NSWorkspace.shared.open(url)
    }

    static func copy(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }

    static func open(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Which Obscura release archive this Mac needs.
    ///
    /// `hw.optional.arm64` describes the **hardware**, so a Proctor translated by
    /// Rosetta still names the Apple Silicon build. Reading the process's own
    /// architecture would hand somebody the Intel tarball on an M-series Mac.
    static func hardwareArchitecture() -> ObscuraTool.Architecture {
        var arm64: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("hw.optional.arm64", &arm64, &size, nil, 0) == 0, arm64 == 1 {
            return .appleSilicon
        }
        return .intel
    }

    static func openLog() {
        let log = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/Proctor/agent.log")
        NSWorkspace.shared.open(log)
    }

    static let label = "app.fledgeling.procter.agent"

    private static var domain: String { "gui/\(getuid())" }

    private static var plistPath: String {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist").path
    }

    /// Make sure the agent is loaded into the launchd domain and running.
    ///
    /// `kickstart` starts a job that is already in the domain and fails on one
    /// that is not — and quitting Proctor boots the job out of the domain,
    /// which is what "quit everything" means. So the pair left a hole: after a
    /// quit, opening the app again found no job to kickstart and the agent
    /// stayed down until somebody pressed Start. Bootstrap it back from the
    /// plist when it is missing, and fall back to the bundled shim's installer
    /// when the plist has never been written at all.
    static func ensureAgent() {
        if launchctl(["print", "\(domain)/\(label)"]) == 0 {
            launchctl(["kickstart", "\(domain)/\(label)"])
            return
        }
        if FileManager.default.fileExists(atPath: plistPath),
           launchctl(["bootstrap", domain, plistPath]) == 0 {
            launchctl(["kickstart", "\(domain)/\(label)"])
            return
        }
        installViaShim()
    }

    /// The installer of record lives in the shim, which writes the plist,
    /// bootstraps the job and waits for the socket. Shelling out to it keeps
    /// one definition of the launchd job rather than a second copy here.
    private static func installViaShim() {
        guard let shim = Bundle.main.url(forAuxiliaryExecutable: "proctor-shim") else { return }
        let process = Process()
        process.executableURL = shim
        process.arguments = ["install"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try? process.run()
        process.waitUntilExit()
    }

    static func restartAgent() { launchctl(["kickstart", "-k", "\(domain)/\(label)"]) }

    /// Set while a relaunch is in flight, and read by `applicationWillTerminate`.
    ///
    /// A quit means everything off; a relaunch does not. The agent is the
    /// long-lived party holding the grants, this window is a bystander, and
    /// booting the agent out to swap the bystander's build would be exactly
    /// backwards — as well as dropping any run in flight.
    @MainActor
    static var isRelaunching = false

    /// Quit and come back on the build that is now on disk.
    ///
    /// `open` on a running single-instance menu bar app activates the instance
    /// already there rather than starting the new one, and terminating first then
    /// opening races the launch. So a detached shell waits for this process to go
    /// and opens the bundle afterwards; the command it runs is built and tested in
    /// Core, because a shell string assembled in a view is a shell string nobody
    /// checks.
    ///
    /// `alsoAgent` restarts the agent as well, and only the caller who knows the
    /// agent's own binary moved should pass it. The installer normally kickstarts
    /// the agent itself, so the usual case is a window that is stale beside an
    /// agent that is not — and kickstarting unasked would drop a run in flight to
    /// fix a problem that was not there.
    @MainActor
    static func relaunch(alsoAgent: Bool = false) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = RelaunchCommand.arguments(pid: ProcessInfo.processInfo.processIdentifier,
                                                bundlePath: Bundle.main.bundlePath)
        // Not waited on, on purpose: it has to outlive this process.
        guard (try? p.run()) != nil else { return }
        if alsoAgent { restartAgent() }
        isRelaunching = true
        NSApp.terminate(nil)
    }

    /// Stop the background agent. Used on quit so "Quit Proctor" means everything
    /// off, not just this window. The LaunchAgent plist stays on disk, so the
    /// agent is loaded again at the next login — this is "off now", not uninstall.
    static func stopAgent() { launchctl(["bootout", "\(domain)/\(label)"]) }

    @discardableResult
    private static func launchctl(_ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = args
        p.standardOutput = Pipe(); p.standardError = Pipe()
        do { try p.run() } catch { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }
}
