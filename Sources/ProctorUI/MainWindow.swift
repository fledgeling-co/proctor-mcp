import SwiftUI
import AppKit
import ProctorCore

struct MainWindow: View {
    let model: AgentModel

    /// PRO-0066. The window draws the sections its state says it may, and no
    /// others.
    ///
    /// It used to draw all eight unconditionally, so an unreachable agent still
    /// rendered Tools, Switches, Activity, Connect and Agent over data nothing
    /// had read. A stale "Ready" pill above a dead agent is a false statement
    /// about a security-relevant grant, and it is the one failure this surface
    /// must not have. `StatusSurface.sections(for:)` decides, and it is tested.
    private var state: StatusSurface.State {
        let lanesAllUsable = (model.report?.lanes ?? []).allSatisfy { $0.state == "ready" }
        switch model.reachability {
        case .unknown:
            return StatusSurface.state(reachable: false, answered: false, lanesAllUsable: true)
        case .unreachable:
            return StatusSurface.state(reachable: false, answered: true, lanesAllUsable: true)
        case .reachable:
            return StatusSurface.state(reachable: true, answered: true,
                                       lanesAllUsable: lanesAllUsable)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: StatusSurface.Geometry.sectionSpacing) {
                Header()
                ForEach(StatusSurface.sections(for: state), id: \.self) { section in
                    sectionView(section)
                        .accessibilityIdentifier(StatusSurface.ID.section(section))
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .accessibilityIdentifier(StatusSurface.ID.state(state))
    }

    @ViewBuilder
    private func sectionView(_ section: StatusSurface.Section) -> some View {
        switch section {
        case .agentDown: AgentDownSection(model: model)
        case .permissions: ReadinessSection(model: model)
        case .tools: ToolsSection(model: model)
        case .lanes: LanesSection(model: model)
        case .switches: SwitchesSection(model: model)
        case .activity: ActivitySection(model: model)
        case .connect: ConnectSection(model: model)
        case .agent: AgentSection(model: model)
        case .footer: FooterSection(model: model)
        }
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
                Text(StatusSurface.Copy.windowTitle)
                    .font(.system(size: 26, weight: .semibold))
                Spacer()
            }
            Text(StatusSurface.Copy.headerLede)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(StatusSurface.Copy.headerProcessNote)
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
                SectionTitle(StatusSurface.Copy.permissionsHeading)
                Spacer()
                StatusPill(model: model)
            }
            // What a permission *is*, said once, so this section and the Tools
            // section below it read as two kinds of claim rather than one list
            // with a mixed subtitle. That mixture is what put a command-line tool
            // under "Optional — asked for per app".
            Text(StatusSurface.Copy.permissionsNote)
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Two states here, not three. DEF-037: this section had a third
            // branch for an unreachable agent, and nothing could reach it.
            // `MainWindow.state` turns `.unreachable` into `StatusSurface.State`
            // `.down`, and `sections(for: .down)` returns `[.agentDown]` alone —
            // deliberately, because a permission row drawn over data nothing has
            // read is the one failure this surface must not have. So the branch
            // drew a second copy of `AgentDownSection`'s two buttons, calling the
            // same two actions and without its accessibility identifiers, for a
            // state that never arrives.
            //
            // The one thing in it that was not redundant went with it rather than
            // being deleted: the progress spinner for `isApplying`. That state is
            // reachable — `reprobeAfterGrant()` restarts the agent after a grant
            // lands, and a 2-second poll meeting a restarting agent gets a refused
            // connection and reports unreachable — so it now draws in
            // `AgentDownSection`, which is the block that is actually on screen
            // then. Without the move, a restart Proctor itself asked for shows a
            // red warning saying the agent is not answering.
            if case .unknown = model.reachability {
                Text(StatusSurface.Copy.checking)
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
            if case .reachable = model.reachability {
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
                    Label(StatusSurface.Copy.ready,
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
                            title: StatusSurface.Copy.recoveryTitle,
                            message: offer.reason)
                    Button(offer.action) { model.take(offer) }
                        .buttonStyle(.borderedProminent)
                }
                if model.signature.isAdHoc {
                    Callout(
                        icon: "exclamationmark.triangle.fill",
                        tint: .orange,
                        title: StatusSurface.Copy.adHocTitle,
                        message: StatusSurface.Copy.adHocMessage)
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
                            title: StatusSurface.Copy.updatedTitle,
                            message: StatusSurface.Copy.updatedMessage(
                                agentReplaced: model.agentBuildReplaced))
                        Button(StatusSurface.Copy.relaunch) {
                            Actions.relaunch(alsoAgent: model.agentBuildReplaced)
                        }
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
                    Button(StatusSurface.Copy.openSettings) { Actions.openPane(pane) }
                        .controlSize(.small)
                        .accessibilityLabel(AccessibilityNames.grantAction(.openSettings,
                                                                           grant: grant.name))
                }
                if !grant.granted {
                    Button(showHow ? StatusSurface.Copy.hide : StatusSurface.Copy.how) {
                        showHow.toggle()
                    }
                        .controlSize(.small).buttonStyle(.borderless)
                        .accessibilityLabel(AccessibilityNames.grantAction(
                            showHow ? .hideHow : .how, grant: grant.name))
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
                SectionTitle(StatusSurface.Copy.toolsHeading)
                Text(StatusSurface.Copy.toolsNote)
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
                    Text(StatusSurface.Copy.secondLaneDisclosure)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: row.tone.symbol).foregroundStyle(tint)
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
                    Button(showDetail ? StatusSurface.Copy.hide : StatusSurface.Copy.details) {
                        showDetail.toggle()
                    }
                        .controlSize(.small).buttonStyle(.borderless)
                        // Seven rows carry this button and the word on it is the
                        // same on every one, so the tool it belongs to is what
                        // makes it answerable.
                        .accessibilityLabel(AccessibilityNames.toolDisclosure(
                            tool: row.tool, expanded: showDetail))
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
                        Text(StatusSurface.Copy.foundAt(path))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .textSelection(.enabled)
                    }
                    if !row.searched.isEmpty {
                        Text(StatusSurface.Copy.lookedIn(row.searched))
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
                SectionTitle(StatusSurface.Copy.switchesHeading)
                Spacer()
                if model.switchesNeedRestart {
                    Button(StatusSurface.Copy.restartToApply) {
                        model.restartAgentForSwitches()
                    }
                        .controlSize(.small)
                        .buttonStyle(.borderedProminent)
                }
            }
            Text(StatusSurface.Copy.switchesNote)
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
                        title: StatusSurface.Copy.switchWriteErrorTitle,
                        message: error)
            }

            // Said once, at the bottom, rather than on eight rows. It is a fact
            // about the file rather than about any one switch, and a caveat
            // repeated eight times is one nobody reads.
            Text(StatusSurface.Copy.switchesStorageNote)
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
        StatusSurface.Copy.switchSource(on: row.running?.on,
                                        source: row.source,
                                        variable: row.aSwitch.variable)
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
                    // The visible label is the row's own heading, which the
                    // toggle does not carry: without this the control reaches
                    // the accessibility tree as an unnamed checkbox, and nine
                    // of them in a column are indistinguishable.
                    .accessibilityLabel(AccessibilityNames.switchToggle(title: row.aSwitch.title))
                    .help(row.locked
                          ? StatusSurface.Copy.lockedHelp(variable: row.aSwitch.variable)
                          : "")
            }

            if row.pending {
                Text(StatusSurface.Copy.switchPending)
                    .font(.system(size: 11)).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // The disclosure sits ABOVE the confirmation, so the thing being
            // consented to is on screen before the second press is offered.
            if confirming {
                VStack(alignment: .leading, spacing: 8) {
                    Callout(icon: "exclamationmark.shield.fill", tint: .orange,
                            title: StatusSurface.Copy.consentTitle,
                            message: consentText)
                    HStack {
                        Button(StatusSurface.Copy.consentConfirm) {
                            confirming = false
                            model.setSwitch(row.aSwitch, on: true)
                        }
                        .buttonStyle(.borderedProminent)
                        Button(StatusSurface.Copy.cancel) { confirming = false }
                    }
                }
            }

            if let warning = row.running?.pairingWarning {
                Callout(icon: "eye.slash.fill", tint: .orange,
                        title: StatusSurface.Copy.pairingWarningTitle,
                        message: warning)
            }
        }
        .padding(.vertical, 8)
    }

    private var consentText: String { StatusSurface.Copy.consentText(for: row.aSwitch) }
}

// MARK: - Activity

private struct ActivitySection: View {
    let model: AgentModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Card {
            HStack(alignment: .firstTextBaseline) {
                SectionTitle(StatusSurface.Copy.activityHeading)
                Spacer()
                // This card answers "what is it doing"; the History window
                // answers "what did it do". Reaching one from the other is the
                // shortest path between the two questions a person actually asks.
                Button(StatusSurface.Copy.showHistory) {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "history")
                }
                .controlSize(.small)
            }
            if let current = model.currentActivity {
                HStack(spacing: 8) {
                    LiveDot(reduceMotion: reduceMotion)
                    Text(StatusSurface.Copy.activityRunning)
                        .font(.system(size: 13, weight: .medium))
                    Text(current).font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.tint)
                    Spacer()
                }
            } else if model.recentActivity.isEmpty {
                Text(model.reachability == .reachable
                     ? StatusSurface.Copy.activityIdle
                     : StatusSurface.Copy.activityNone)
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            } else {
                Text(StatusSurface.Copy.activityIdleWithHistory)
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
        Wire.shimPath(inBundle: Bundle.main.bundlePath)
    }

    private var snippet: String { StatusSurface.Copy.connectSnippet(shimPath: shimPath) }

    var body: some View {
        Card {
            SectionTitle(StatusSurface.Copy.connectHeading)
            Text(StatusSurface.Copy.connectNote)
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text(snippet)
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .quaternarySystemFill), in: RoundedRectangle(cornerRadius: 6))
            HStack {
                Button(StatusSurface.Copy.copyConfig) { Actions.copy(snippet) }
                Button(StatusSurface.Copy.copyCommandPath) { Actions.copy(shimPath) }
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
            SectionTitle(StatusSurface.Copy.agentSectionHeading)
            // Facts about the running process. Tools moved to their own section:
            // "which programs are on this Mac" and "what is this process" are
            // different questions, and answering both in one grid is what let a
            // CLI be reported twice, in two registers, in two places.
            if let r = model.report {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                    Row(StatusSurface.Copy.agentVersionLabel,
                        StatusSurface.Copy.agentVersion(r.agentVersion,
                                                        protocolVersion: r.protocolVersion))
                    // The window is its own process from its own copy of the bundle,
                    // and an upgrade can leave the two halves on different builds for
                    // hours. Normally these two strings match; when they do not, the
                    // difference is the diagnosis, in words rather than in timestamps
                    // somebody has to go and read.
                    Row(StatusSurface.Copy.agentWindowLabel, BuildInfo.current.descriptor)
                    Row(StatusSurface.Copy.agentOSLabel, r.osVersion)
                    Row(StatusSurface.Copy.agentSocketLabel, r.socketPath)
                    Row(StatusSurface.Copy.agentAttachedLabel, r.attachedApps.isEmpty
                        ? StatusSurface.Copy.agentAttachedNone
                        : r.attachedApps.map(\.name).joined(separator: ", "))
                    Row(StatusSurface.Copy.agentObserversLabel, "\(r.observersLive)")
                    Row(StatusSurface.Copy.agentSignatureLabel, model.signature.summary)
                }
                if r.secureEventInputActive {
                    Callout(
                        icon: "keyboard.badge.ellipsis",
                        tint: .orange,
                        title: StatusSurface.Copy.secureInputTitle,
                        message: StatusSurface.Copy.secureInputMessage)
                }
            } else {
                Text(StatusSurface.Copy.agentAbsent)
                    .font(.system(size: 12)).foregroundStyle(.secondary)
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
                title: StatusSurface.Copy.obscuraTitle,
                message: StatusSurface.Copy.obscuraMessage)
            Text(commands.joined(separator: "\n"))
                .font(.system(size: 11, design: .monospaced))
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .quaternarySystemFill),
                            in: RoundedRectangle(cornerRadius: 6))
            HStack {
                Button(StatusSurface.Copy.copyInstallCommands) {
                    Actions.copy(commands.joined(separator: "\n"))
                }
                Button(StatusSurface.Copy.openProjectPage) { Actions.open(absence.docs) }
                    .buttonStyle(.borderless).controlSize(.small)
                Button(StatusSurface.Copy.recheck) { model.refresh() }
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
            Button(StatusSurface.Copy.openLog) { Actions.openLog() }
            Button(StatusSurface.Copy.restartAgent) { Actions.restartAgent(); model.refresh() }
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

    /// Sentence case, semibold, secondary.
    ///
    /// PRO-0075. The design of record states the rule and its reason: "the
    /// sections are sentence case, semibold, in the secondary tier — a header
    /// that recedes under what it labels." The shipped treatment was
    /// letter-spaced monospaced capitals, which is the louder of the two and
    /// competes with the row titles beneath it. Measured against the design pane
    /// by be-my-witness, both dark and at the same width.
    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
    }
}

private struct StatusPill: View {
    let model: AgentModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        let (label, tint): (String, Color) = {
            if model.isApplying { return (StatusSurface.Copy.pillApplying, .secondary) }
            switch model.reachability {
            case .unknown: return (StatusSurface.Copy.pillChecking, .secondary)
            case .unreachable: return (StatusSurface.Copy.pillDown, .red)
            case .reachable: return model.ready
                ? (StatusSurface.Copy.pillReady, .green)
                : (StatusSurface.Copy.pillNeedsPermission, .orange)
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
    static func pane(for grant: String) -> String? { StatusChecks.settingsPane(for: grant) }

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

    static let label = Wire.agentLabel

    private static var domain: String { Wire.launchdDomain(uid: getuid()) }

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


// MARK: - Agent down

/// PRO-0066. What replaces the window when the agent is not answering.
///
/// It says what is wrong, what that stops, and the two things to do about it.
/// Every string comes from `StatusSurface.Copy`, so the wording is testable and
/// a translator can find it.
private struct AgentDownSection: View {
    let model: AgentModel

    var body: some View {
        Card {
            // DEF-037. A restart Proctor asked for is not the agent failing.
            // `reprobeAfterGrant()` restarts the agent so macOS will answer the
            // Screen Recording probe again, and the window's own 2-second poll
            // meets the gap: a refused connection reports unreachable, which is
            // this section. Saying "the background agent is not answering" in red
            // about a restart it started itself is a true sentence and the wrong
            // one, so while it is applying, this says what is happening instead.
            //
            // Its limit, stated rather than left to be rediscovered: `isApplying`
            // is cleared by a 1.2-second timer rather than by the restart
            // finishing, so a restart that outlives the timer falls back to the
            // red block. That is unchanged by this and is written up as its own
            // defect rather than fixed here.
            if model.isApplying {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(StatusSurface.Copy.applying)
                        .font(.system(size: 13, weight: .medium))
                }
            } else {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 6) {
                    Text(StatusSurface.Copy.downTitle)
                        .font(.system(size: 13, weight: .medium))
                    if case .unreachable(let why) = model.reachability {
                        Text(why)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(StatusSurface.Copy.downConsequence)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Button(StatusSurface.Copy.downStart) {
                            Actions.ensureAgent(); model.refresh()
                        }
                        .buttonStyle(.borderedProminent)
                        .accessibilityIdentifier(StatusSurface.ID.startAgent)

                        Button(StatusSurface.Copy.recheck) { model.refresh() }
                            .accessibilityIdentifier(StatusSurface.ID.recheck)
                    }
                    .padding(.top, 4)
                }
            }
            }
        }
    }
}

// MARK: - Lanes

/// PRO-0066. What this machine can actually do, lane by lane.
///
/// On the wire as `DoctorReport.lanes` since PRO-0050 and unrendered until now —
/// PRO-0036 deliberately left it. `unconfirmed` and `unavailable` draw
/// differently because they are different answers: one is a fact about what
/// Proctor established, the other is something to go and fix, and sending
/// somebody to fix the first is the defect PRO-0041 closed.
private struct LanesSection: View {
    let model: AgentModel

    var body: some View {
        Card {
            SectionTitle(StatusSurface.Copy.lanesHeading)
            Text(StatusSurface.Copy.lanesNote)
                .font(.system(size: 12)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(model.report?.lanes ?? [], id: \.lane) { lane in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(lane.lane).font(.system(size: 13, weight: .medium))
                        if !lane.requires.isEmpty {
                            Text(lane.requires.joined(separator: ", "))
                                .font(.system(size: 11)).foregroundStyle(.tertiary)
                        }
                        ForEach(lane.blockers, id: \.self) { blocker in
                            Text(blocker)
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer()
                    LanePill(state: lane.state)
                }
                .padding(.vertical, 7)
                .accessibilityIdentifier(StatusSurface.ID.laneRow(lane.lane))
                Divider()
            }
        }
    }
}

/// Three states, three treatments. Colour is never the only carrier — each
/// carries its own word — because 8% of men are colourblind and a greyscale
/// display is not an edge case on a Mac.
private struct LanePill: View {
    let state: String

    var body: some View {
        let resolved = StatusSurface.LaneState(rawValue: state)
        Text(state)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(tint(resolved))
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(tint(resolved).opacity(0.14), in: Capsule())
    }

    private func tint(_ s: StatusSurface.LaneState?) -> Color {
        switch s {
        case .ready: return .green
        case .unconfirmed: return .orange
        case .unavailable: return .red
        case nil: return .secondary
        }
    }
}
