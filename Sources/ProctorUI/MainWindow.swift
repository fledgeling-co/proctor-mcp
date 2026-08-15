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

    private var statusText: String {
        if grant.granted { return "Granted" }
        if unconfirmed { return "Not established — macOS did not answer" }
        return grant.required ? "Required — not granted yet" : "Optional — asked for per app"
    }

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
                    Row("Shortcuts CLI", r.shortcutsCLIAvailable ? "available" : "not available")
                    Row("Obscura", obscuraSummary(r))
                    if let second = secondLaneSummary(r) {
                        Row("browser-use", second)
                    }
                    Row("Signature", model.signature.summary)
                }
                if let second = secondLaneSummary(r), second.hasPrefix("second lane on") {
                    Text("Proctor names browser-use for pages Obscura cannot open. It is an "
                         + "autonomous agent driving a real browser with real credentials, and "
                         + "nothing it does reaches Proctor's audit trail. Set by "
                         + "PROCTOR_SECOND_LANE in the agent's launchd environment.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let absence = r.obscuraUnavailable {
                    ObscuraOffer(absence: absence, model: model)
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

    /// A half install is its own state: `obscura` without `obscura-worker` beside
    /// it runs `fetch` and `serve` and fails `scrape`, which is worth naming here
    /// rather than leaving somebody to meet it mid-run.
    private func obscuraSummary(_ r: DoctorReport) -> String {
        guard r.obscuraAvailable else { return "not installed" }
        let missing = r.obscura?.missingCompanions ?? []
        guard !missing.isEmpty else { return "available" }
        return "available, without \(missing.joined(separator: ", "))"
    }

    /// The second lane's row, or nothing. The decision is `BrowserUseTool`'s so it
    /// can be tested without a window server; this only reads the report.
    private func secondLaneSummary(_ r: DoctorReport) -> String? {
        BrowserUseTool.statusSummary(
            secondLane: SecondLaneState(rawValue: r.secondLane) ?? .off,
            found: r.tools.first { $0.tool == BrowserUseTool.binary }?.available ?? false)
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

    var body: some View {
        HStack(spacing: 10) {
            Button("Open log") { Actions.openLog() }
            Button("Restart agent") { Actions.restartAgent(); model.refresh() }
            Spacer()
            if let t = model.lastChecked {
                Text("Checked \(t.formatted(date: .omitted, time: .standard))")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            Button("Re-check") { model.refresh() }.controlSize(.small)
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
