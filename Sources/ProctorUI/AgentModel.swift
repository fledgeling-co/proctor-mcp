import Foundation
import AppKit
import ApplicationServices
import CoreGraphics
import ProctorCore

/// The window's view of the agent.
///
/// Every call opens a short-lived connection on a background queue rather than
/// holding one open. The agent is the grant holder and the long-lived party;
/// the UI is a bystander that should never be the reason it is busy, and a
/// dropped connection should not need reconnect logic in a status panel.
@MainActor
@Observable
final class AgentModel {
    enum Reachability: Equatable {
        case unknown
        case reachable
        case unreachable(String)
    }

    private(set) var report: DoctorReport?
    private(set) var reachability: Reachability = .unknown
    private(set) var lastChecked: Date?
    private(set) var isChecking = false

    /// The tool Proctor is running right now (nil when idle) and a newest-first
    /// ring of the ones it just ran, polled alongside the doctor report so the
    /// menu bar and status window can show what a model is driving.
    private(set) var currentActivity: String?
    private(set) var recentActivity: [ActivityItem] = []
    /// How many other sessions are waiting for their turn. Mirrored here so the
    /// queue is answerable from the menu bar without the run panel being on
    /// screen — the scheduler runs whether or not anything is drawn.
    private(set) var queueWaiting = 0
    /// Whether a run is going to take the machine, and whether it is taking it
    /// right now. Mirrored into the menu bar because the run panel lands on one
    /// display and the person whose machine it is may be looking at another.
    private(set) var foreground = ForegroundStatus()

    struct ForegroundStatus: Sendable, Equatable {
        var running = false
        /// A synthetic step travelled on the last poll. Sampled at the polling
        /// interval, so a step shorter than one poll can pass unseen here — the
        /// panel is the instantaneous surface, this is the one on every display.
        var active = false
        var takesForeground = false
        var mayTakeForeground = false
        var notice: String?
        /// The run got out of somebody's way and is holding. Read ahead of
        /// `active` wherever both are shown: a held run is not taking the
        /// machine, and saying both at once would be two claims about one
        /// instant.
        var yielded = false
        var yieldLine: String?
    }

    /// What the run HUD is doing, mirrored from the agent so the menu bar can
    /// draw the same character in the same state. `hudPhase` is the phase the one
    /// `RunHUDState` reduced — nothing here derives a second one.
    private(set) var hudPhase: RunHUDPhase = .idle
    private(set) var hudRunning = false
    private(set) var hudDrawing = true
    /// Whether the panel could be brought back at all. False on an agent started
    /// with `PROCTOR_HUD` off: that launch runs a bare run loop, so a panel drawn
    /// now would have a Pause and a Stop nobody could click.
    private(set) var hudCanShow = false
    /// Why Show is unavailable, in the agent's own words. Nil when it is.
    private(set) var hudShowRefusal: String?

    /// The menu bar's own sprite clock. Owned here because the phase arrives
    /// here; the label only reads it.
    let character = MenuBarCharacter()

    struct ActivityItem: Identifiable, Sendable {
        let id = UUID()
        let tool: String
        let at: Date
        let ok: Bool
    }

    /// True while the agent is being restarted to pick up a permission it had
    /// already cached as denied. The socket is briefly down during this, so the
    /// UI reads this rather than flashing "agent not answering".
    private(set) var isApplying = false

    /// Ad-hoc signed builds lose their grants on every rebuild, which presents
    /// as elements not being found rather than as a permission error. Worth
    /// saying on the face of the window rather than in a log.
    let signature = SignatureInfo.current()

    /// Two cadences, because the two answers age differently. The activity feed
    /// is a projection of state the agent already holds, over a local socket, and
    /// it carries the run phase the menu bar draws — so it runs fast enough that
    /// the character and the Pause and Stop items are not visibly behind the run
    /// they belong to. The doctor report probes permissions and enumerates apps,
    /// changes only when somebody touches System Settings, and stays slow.
    private var activityTimer: Timer?
    private var doctorTimer: Timer?

    /// Whether the app on disk is a different build from the one running.
    ///
    /// An upgrade replaces the bundle underneath this process. `scripts/install.sh`
    /// kickstarts the agent, so *it* comes back on the new binary; nothing brings
    /// this window back, and until this existed nothing said so — which is how a
    /// menu bar running an eight-hour-old build got reported as a bug in a rule
    /// that was working correctly. Measured on 2026-08-15: the agent restarted ten
    /// seconds after the install, the window did not restart at all.
    private(set) var buildReplaced = false

    /// Whether the *agent's* binary moved too. Tracked apart from the window's
    /// because the fix differs: this one is a launchd kickstart, and doing it
    /// unasked would drop a run in flight. The installer normally does it, so
    /// this is usually false while `buildReplaced` is true.
    private(set) var agentBuildReplaced = false

    /// This app's own build: the executable, and the idle picture from Core's
    /// resource bundle. Two, not one, because the thing that goes missing is an
    /// asset — a reinstall that replaced only the resource bundle would leave a
    /// Mach-O stamp untouched and the character wrong anyway.
    private static var appPaths: [String] {
        [Bundle.main.executablePath,
         RunHUDCharacter.menuBarAssetURL(asset: "idle-0", scale: 1)?.path].compactMap { $0 }
    }

    /// The agent's binary, beside this one in the same bundle.
    private static var agentPaths: [String] {
        [Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/proctor-agent").path]
    }

    private let appStamps: [BuildStamp?] = appPaths.map(BuildStamp.of(path:))
    private let agentStamps: [BuildStamp?] = agentPaths.map(BuildStamp.of(path:))

    /// The menu's one action when something is wrong with the agent, or nil.
    ///
    /// This replaced a menu row labelled "Re-check now", which called `refresh()`
    /// — the same call a 2-second timer has been making all along. The row was
    /// defended for the case of a grant made in System Settings, and that is the
    /// one case it could not serve: the agent reads Screen Recording through
    /// ScreenCaptureKit, whose answer macOS caches for the life of the process, so
    /// re-asking the same agent returns the same denial however often it is asked.
    /// A restart is the only thing that clears it. `AgentRecovery` carries the
    /// reasoning, and the reason a restart is offered only where this window can
    /// see the grant for itself.
    private(set) var recovery: AgentRecovery.Offer?

    /// This process's own live read of Screen Recording, refreshed on the doctor
    /// tick. `CGPreflightScreenCaptureAccess` reads the recorded grant without
    /// prompting, and `build-app.sh` signs every nested binary with `-i` the
    /// bundle identifier, so it is the same TCC record the agent answers from.
    private var windowSeesScreenRecording: Bool?

    /// Polling starts with the model and runs for the app's whole life, not just
    /// while the window is open — the menu-bar glyph and status line have to stay
    /// live after the window is closed.
    init() { startPolling() }

    var ready: Bool { report?.ready == true }

    /// Whether every grant Proctor cannot work without is in place.
    ///
    /// Narrower than `ready`, on purpose, and the menu bar reads this one. `ready`
    /// is `blockers.isEmpty` and the doctor's blockers include Secure Event Input,
    /// which is not a grant and does not want the same picture — see `MenuBarBlock`.
    /// Every other consumer of `ready` still asks the wider question, which is the
    /// right one for a status line.
    ///
    /// A report carrying no required grants at all answers false. An empty list is
    /// absence of evidence, not evidence of a grant, and `allSatisfy` over nothing
    /// is true — which would have quietly put a calm character over a report that
    /// said nothing about permissions.
    var requiredGrantsGranted: Bool {
        guard let report else { return false }
        let required = report.grants.filter(\.required)
        return !required.isEmpty && required.allSatisfy(\.granted)
    }

    /// A required grant macOS did not answer for. Its own question, because the
    /// remedy differs: a denial is fixed in System Settings and an unconfirmed
    /// grant is not.
    var requiredGrantsUnconfirmed: Bool {
        report?.grants.contains { $0.required && $0.resolvedState == .unconfirmed } ?? false
    }

    /// A required grant macOS said no to. Separate from the above so the menu bar
    /// can rank a denial above a non-answer; `requiredGrantsGranted` is false for
    /// both and cannot tell them apart.
    var requiredGrantsDenied: Bool {
        report?.grants.contains { $0.required && $0.resolvedState == .denied } ?? false
    }

    /// The permissions, and only the permissions.
    ///
    /// The report files the Shortcuts CLI under `grants` — and only when it is
    /// missing — so a filter is what keeps a program on a disk out of a list of
    /// decisions macOS holds about Proctor. `StatusChecks` owns which is which,
    /// because that rule has to be testable and there is no test target here.
    private var permissionGrants: [DoctorReport.Grant] {
        StatusChecks.permissions(in: report?.grants ?? [])
    }

    var requiredGrants: [DoctorReport.Grant] {
        permissionGrants.filter(\.required)
    }

    var optionalGrants: [DoctorReport.Grant] {
        permissionGrants.filter { !$0.required }
    }

    func startPolling() {
        refresh()
        doctorTimer?.invalidate()
        // Two seconds is fast enough that toggling a grant in System Settings
        // reflects here while the user is still looking at both windows.
        doctorTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshDoctor() }
        }
        activityTimer?.invalidate()
        // Half a second, always — not only while a run is going. Gating the fast
        // cadence on "a run is live" would mean learning that a run had *started*
        // on the slow one, which puts the character and the menu's Pause and Stop
        // up to two seconds behind exactly when they matter most.
        activityTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshActivity() }
        }
    }

    func stopPolling() {
        activityTimer?.invalidate(); activityTimer = nil
        doctorTimer?.invalidate(); doctorTimer = nil
    }

    func refresh() {
        refreshDoctor()
        refreshActivity()
    }

    private func refreshDoctor() {
        guard !isChecking else { return }
        isChecking = true
        // The stale-build check rides this tick rather than bringing a timer of
        // its own: two stats against a socket round trip already running at this
        // cadence is not worth a second clock. Once true it stays true — the
        // build on disk does not go back.
        if !buildReplaced {
            buildReplaced = BuildStamp.replaced(
                running: appStamps, onDisk: Self.appPaths.map(BuildStamp.of(path:)))
        }
        if !agentBuildReplaced {
            agentBuildReplaced = BuildStamp.replaced(
                running: agentStamps, onDisk: Self.agentPaths.map(BuildStamp.of(path:)))
        }
        // This window's own answer about Screen Recording, taken fresh beside the
        // stamps. `CGPreflightScreenCaptureAccess` reads the recorded grant without
        // prompting, and both binaries live in Proctor.app under one bundle
        // identifier, so it is the same record the agent is answering from — which
        // is what makes a disagreement between them mean "the agent is holding a
        // stale answer" rather than "one of these is about a different app".
        windowSeesScreenRecording = CGPreflightScreenCaptureAccess()
        Task.detached(priority: .utility) {
            let outcome = Self.callDoctor(requestAccessibility: false, requestScreenRecording: false)
            await MainActor.run { self.apply(outcome) }
        }
    }

    private func refreshActivity() {
        guard !isPollingActivity else { return }
        isPollingActivity = true
        Task.detached(priority: .utility) {
            let activity = Self.callActivity()
            await MainActor.run { self.isPollingActivity = false; self.applyActivity(activity) }
        }
    }

    private var isPollingActivity = false

    // MARK: - The run panel, from the menu bar

    /// Show or hide the run panel now, for the current run.
    ///
    /// The same switch `PROCTOR_HUD` sets, moved from the menu bar instead of
    /// from the environment. Nothing is written to disk, so the environment is
    /// still the default at the next launch.
    func setPanel(visible: Bool) { control(visible ? .show : .hide) }

    /// The run's own controls, so hiding the panel never hides the kill switch.
    /// Pause and Stop, never the queue's Hold and Clear — those live on the panel
    /// and the two pairs are deliberately never together.
    func togglePause() { control(hudPhase == .paused ? .resume : .pause) }
    func stopRun() { control(.stop) }

    // MARK: - The switches (PRO-0029)

    /// What is saved on disk. The window's half of the two sources of truth; the
    /// other half is the agent's own environment, which only the agent can report.
    private(set) var savedSwitches = SwitchStore.load(from: SwitchStore.defaultURL)

    /// The last write's failure, if it failed. Shown rather than swallowed: a
    /// preference that silently did not save is the class of defect this whole
    /// item exists to remove.
    private(set) var switchWriteError: String?

    /// One row, ready to draw.
    ///
    /// `running` comes from the agent and is nil until its first report lands.
    /// It is never guessed from this process's environment: the window is started
    /// by LaunchServices and the agent by launchd, so this process's `ProcessInfo`
    /// describes a different environment and would describe it plausibly.
    struct SwitchRow: Identifiable, Equatable {
        var id: String { aSwitch.variable }
        let aSwitch: ProctorSwitch
        /// What the agent is running with, or nil when nothing has said yet.
        let running: SwitchState?
        /// What is saved here, or nil when nothing is saved.
        let saved: Bool?

        /// What the control should show. The saved value when there is one,
        /// otherwise what the agent reports, otherwise the built-in default.
        var controlOn: Bool { saved ?? running?.on ?? aSwitch.defaultOn }
        var locked: Bool { running?.locked ?? false }
        var source: SwitchSource? {
            running.flatMap { SwitchSource(rawValue: $0.source) }
        }
        /// A saved change that the running agent has not picked up yet.
        var pending: Bool {
            guard let running, aSwitch.timing == .nextStart else { return false }
            guard let saved else { return false }
            // A locked switch is not pending: the environment is winning and a
            // restart would not change that.
            return !running.locked && saved != running.on
        }
    }

    var switchRows: [SwitchRow] {
        let states = report?.switches ?? []
        let byName = Dictionary(uniqueKeysWithValues: states.map { ($0.variable, $0) })
        return SwitchCatalogue.all.map { aSwitch in
            let raw = savedSwitches[aSwitch.variable]
            return SwitchRow(aSwitch: aSwitch,
                             running: byName[aSwitch.variable],
                             saved: raw.map { SwitchResolver.isOn($0, for: aSwitch) })
        }
    }

    /// Whether any saved change is waiting on a restart.
    var switchesNeedRestart: Bool { switchRows.contains { $0.pending } }

    /// Save a switch. Never claims the agent picked it up — that is `pending`'s
    /// job, and it clears when the agent's next report says the new value is what
    /// it is running with.
    /// The saved value of a drawing switch, or its default where nothing is
    /// saved. Read by the Run menu's toggles, which show what a person chose
    /// rather than what the agent is currently running with.
    func isSavedOn(_ aSwitch: ProctorSwitch) -> Bool {
        if let raw = savedSwitches[aSwitch.variable] {
            return SwitchResolver.isOn(raw, for: aSwitch)
        }
        return aSwitch.defaultOn
    }

    /// Clear every waiting run. The run in flight is untouched, which is why
    /// this is a different word from Stop on a different row of the menu.
    func dropWaiting() {
        Task.detached { _ = Self.callQueue(.clear) }
    }

    func setSwitch(_ aSwitch: ProctorSwitch, on: Bool) {
        var saved = savedSwitches
        saved.set(aSwitch, on: on)
        persist(saved)

        // The run panel is the one switch with a live channel, so honour it now
        // as well as at the next start. The saved value is the start-up default;
        // this is the current run.
        if aSwitch == SwitchCatalogue.hud { setPanel(visible: on) }
    }

    /// Forget a saved preference, so the switch falls back to the environment or
    /// its built-in default.
    func clearSwitch(_ aSwitch: ProctorSwitch) {
        var saved = savedSwitches
        saved.clear(aSwitch)
        persist(saved)
    }

    private func persist(_ saved: SavedSwitches) {
        do {
            try SwitchStore.save(saved, to: SwitchStore.defaultURL)
            savedSwitches = saved
            switchWriteError = nil
        } catch {
            switchWriteError = error.localizedDescription
        }
    }

    /// Restart the agent so the relaunch-scoped switches take effect, then
    /// re-read. The window learns it worked from the agent's next report.
    func restartAgentForSwitches() {
        Actions.restartAgent()
        refresh()
    }

    private func control(_ action: RunHUDControl) {
        Task.detached(priority: .userInitiated) {
            let result = Self.callHUD(action)
            await MainActor.run { self.applyHUD(result) }
        }
    }

    /// Ask macOS for the real Accessibility consent dialog.
    ///
    /// The request has to come from the agent, because TCC attributes consent
    /// to the process responsible for asking — prompting from this window would
    /// put the grant on the wrong identity. macOS shows the dialog only once
    /// per app identity, so a second call is silently a no-op and System
    /// Settings becomes the only route.
    /// Prompts run here, in the window's own process, not through the agent.
    ///
    /// Both binaries live in Proctor.app and are signed with the bundle's
    /// identifier, so the grant TCC records covers the agent too — but macOS
    /// only reliably *shows* a consent dialog for a foreground app. Asking from
    /// the launchd agent returns the recorded answer without ever drawing
    /// anything, which is indistinguishable from the user being ignored.
    func requestAccessibilityPrompt() {
        NSApp.activate(ignoringOtherApps: true)
        _ = AXIsProcessTrustedWithOptions(
            ["AXTrustedCheckOptionPrompt" as CFString: true] as CFDictionary)
        refresh()
    }

    /// Same reasoning as Accessibility. `CGRequestScreenCaptureAccess` blocks
    /// until the dialog is answered, so it runs off the main actor.
    ///
    /// The agent probes Screen Recording through `SCShareableContent`, which
    /// macOS caches per process for the life of that process. So a grant made
    /// here is invisible to the already-running agent until it restarts and
    /// re-probes — restart it on a fresh grant rather than leaving the window
    /// stuck reporting "not granted yet" against a permission the user just gave.
    func requestScreenRecordingPrompt() {
        NSApp.activate(ignoringOtherApps: true)
        isChecking = true
        Task.detached(priority: .userInitiated) {
            let granted = CGRequestScreenCaptureAccess()
            await MainActor.run {
                self.isChecking = false
                if granted { self.reprobeAfterGrant() } else { self.refresh() }
            }
        }
    }

    /// Restart the agent so it re-probes a permission it had cached as denied,
    /// holding an "applying" state across the restart so the momentary socket
    /// drop doesn't read as the agent falling over.
    ///
    /// Two callers, deliberately one path: the grant made through Proctor's own
    /// dialog, and the grant made in System Settings and then noticed here. The
    /// remedy is identical because the problem is — a running agent that cannot be
    /// told — and having the hand-driven route be the same code is what stops the
    /// two surfaces drifting into two answers.
    private func reprobeAfterGrant() {
        isApplying = true
        recomputeRecovery()
        Actions.restartAgent()
        // launchd needs a beat to bring the agent back; polling immediately
        // races the restart and reports it as down.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.isApplying = false
            self?.recomputeRecovery()
            self?.refresh()
        }
    }

    private func apply(_ outcome: Outcome) {
        switch outcome {
        case .success(let r):
            report = r
            reachability = .reachable
        case .failure(let message):
            report = nil
            reachability = .unreachable(message)
        }
        lastChecked = Date()
        isChecking = false
        recomputeRecovery()
    }

    /// Recomputed wherever any input lands: the doctor report carries the agent's
    /// cached grant and its reachability, the HUD state carries whether a run is
    /// in flight, and `isApplying` is set around a restart. They arrive on
    /// different cadences and from different calls.
    private func recomputeRecovery() {
        let reachable: Bool
        if case .reachable = reachability { reachable = true } else { reachable = false }
        let agentSees = report?.grants
            .first { $0.name == "Screen Recording" }?.resolvedState ?? .denied
        recovery = AgentRecovery.decide(
            applying: isApplying,
            reachable: reachable,
            agentSeesScreenRecording: agentSees,
            windowSeesScreenRecording: windowSeesScreenRecording,
            runInFlight: hudRunning)
    }

    /// The menu's offers, taken.
    ///
    /// The restart is the same call the in-app grant already makes, deliberately
    /// one path: the problem is identical — a running agent that cannot be told —
    /// and having the hand-driven route share the code is what stops the two
    /// surfaces drifting into two answers.
    func take(_ offer: AgentRecovery.Offer) {
        switch offer.kind {
        case .startAgent:
            // Off the main thread: bootstrapping takes a moment and the fallback
            // shells out to the installer, exactly as the app delegate does at
            // launch. The poll picks the change up.
            DispatchQueue.global(qos: .userInitiated).async {
                Actions.ensureAgent()
                Task { @MainActor in self.refresh() }
            }
        case .restartAgent:
            reprobeAfterGrant()
        }
    }

    private func applyActivity(_ snapshot: ActivitySnapshot?) {
        // A failed activity poll (agent restarting) leaves the last feed in
        // place rather than blanking it, which would flicker on every restart.
        guard let snapshot else { return }
        currentActivity = snapshot.current
        recentActivity = snapshot.items
        queueWaiting = snapshot.queueWaiting
        applyHUD(snapshot.hud)
        foreground = snapshot.foreground
    }

    /// Apply a hud state, from a poll or from the reply to a control. Both carry
    /// the same shape, so a control's effect shows the moment it is answered
    /// rather than at the next poll.
    private func applyHUD(_ state: HUDState?) {
        guard let state else { return }
        hudPhase = state.phase
        hudRunning = state.running
        hudDrawing = state.drawing
        hudCanShow = state.canShow
        if let refusal = state.refusal { hudShowRefusal = refusal }
        else if state.canShow { hudShowRefusal = nil }
        character.show(state.phase)
        // A run starting or ending changes what the restart offer costs, and that
        // arrives here on the fast cadence rather than with the doctor report.
        recomputeRecovery()
    }

    /// What the menu bar item draws. Readiness outranks the character: a calm
    /// idle picture over an agent that is not answering would be a falsehood
    /// about the machine.
    var menuBarIcon: MenuBarIcon {
        switch reachability {
        case .unknown: return .checking
        case .unreachable:
            return MenuBarIcon.decide(reachable: false, block: .missingGrant, phase: hudPhase)
        case .reachable:
            let block = MenuBarIcon.block(
                requiredGrantsGranted: requiredGrantsGranted,
                secureEventInputActive: report?.secureEventInputActive == true,
                ready: ready,
                requiredGrantsDenied: requiredGrantsDenied,
                requiredGrantsUnconfirmed: requiredGrantsUnconfirmed)
            return MenuBarIcon.decide(reachable: true, block: block, phase: hudPhase,
                                      takingForeground: foreground.active)
        }
    }

    struct HUDState: Sendable {
        let phase: RunHUDPhase
        let running: Bool
        let drawing: Bool
        let canShow: Bool
        let refusal: String?

        init?(_ value: JSONValue?, refusal: String? = nil) {
            guard let value,
                  let phase = value["phase"]?.stringValue.flatMap(RunHUDPhase.init(rawValue:))
            else { return nil }
            self.phase = phase
            self.running = value["running"]?.boolValue ?? false
            self.drawing = value["drawing"]?.boolValue ?? true
            self.canShow = value["canShow"]?.boolValue ?? false
            self.refusal = refusal
        }
    }

    struct ActivitySnapshot: Sendable {
        let current: String?
        let items: [ActivityItem]
        let queueWaiting: Int
        let hud: HUDState?
        let foreground: ForegroundStatus
    }

    private enum Outcome {
        case success(DoctorReport)
        case failure(String)
    }

    /// Runs off the main actor. `SocketClient` is blocking by design.
    private nonisolated static func callDoctor(requestAccessibility: Bool,
                                               requestScreenRecording: Bool) -> Outcome {
        var flags: [String: JSONValue] = [:]
        if requestAccessibility { flags["requestAccessibility"] = .bool(true) }
        if requestScreenRecording { flags["requestScreenRecording"] = .bool(true) }
        let client = SocketClient()
        defer { client.disconnect() }
        do {
            let response = try client.send(
                AgentRequest(id: UUID().uuidString, tool: "proctor_doctor",
                              arguments: .object(flags)))
            guard response.ok, let result = response.result else {
                return .failure(response.error?.message ?? "the agent refused the request")
            }
            let data = try JSONEncoder().encode(result)
            return .success(try JSONDecoder().decode(DoctorReport.self, from: data))
        } catch let error as AgentError {
            return .failure(error.message)
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    /// The recent-activity feed over the same socket. Best-effort: any failure
    /// returns nil and the last feed is kept, since the menu bar showing a
    /// slightly stale "last tool" beats it blanking whenever a poll misses.
    private nonisolated static func callActivity() -> ActivitySnapshot? {
        let client = SocketClient()
        defer { client.disconnect() }
        guard let response = try? client.send(
                AgentRequest(id: UUID().uuidString, tool: "proctor_recent_activity",
                             arguments: .object([:]))),
              response.ok, let result = response.result else { return nil }
        let iso = ISO8601DateFormatter()
        let items = result["recent"]?.arrayValue?.compactMap { entry -> ActivityItem? in
            guard let tool = entry["tool"]?.stringValue else { return nil }
            let at = entry["at"]?.stringValue.flatMap(iso.date(from:)) ?? Date()
            return ActivityItem(tool: tool, at: at, ok: entry["ok"]?.boolValue ?? true)
        } ?? []
        let f = result["foreground"]
        let foreground = ForegroundStatus(
            running: f?["running"]?.boolValue ?? false,
            active: f?["active"]?.boolValue ?? false,
            takesForeground: f?["takesForeground"]?.boolValue ?? false,
            mayTakeForeground: f?["mayTakeForeground"]?.boolValue ?? false,
            notice: f?["notice"]?.stringValue,
            yielded: f?["yield"]?["active"]?.boolValue ?? false,
            yieldLine: f?["yield"]?["line"]?.stringValue)
        return ActivitySnapshot(current: result["current"]?.stringValue, items: items,
                                queueWaiting: result["queueWaiting"]?.intValue ?? 0,
                                hud: HUDState(result["hud"]),
                                foreground: foreground)
    }

    /// The run panel's switch and the run's controls, over the same socket. An
    /// internal verb: it is not in the tool catalogue, so no MCP host can reach
    /// it and put a person's stop button away.
    /// The queue's own internal verb. Kept apart from `callHUD` because the two
    /// vocabularies are kept apart everywhere else, and a shared call site is
    /// where they would quietly merge again.
    private nonisolated static func callQueue(_ action: RunQueueControl) -> Bool {
        let client = SocketClient()
        defer { client.disconnect() }
        guard let response = try? client.send(
                AgentRequest(id: UUID().uuidString, tool: "proctor_queue",
                             arguments: .object(["action": .string(action.rawValue)])))
        else { return false }
        return response.ok
    }

    private nonisolated static func callHUD(_ action: RunHUDControl) -> HUDState? {
        let client = SocketClient()
        defer { client.disconnect() }
        guard let response = try? client.send(
                AgentRequest(id: UUID().uuidString, tool: "proctor_hud",
                             arguments: .object(["action": .string(action.rawValue)]))),
              response.ok, let result = response.result else { return nil }
        return HUDState(result["hud"], refusal: result["refused"]?.stringValue)
    }
}

/// What the running bundle is signed with, read from its own code signature.
struct SignatureInfo: Sendable {
    var isAdHoc: Bool
    var teamID: String?
    var authority: String?

    var summary: String {
        if let authority, let teamID { return "\(authority) (\(teamID))" }
        return isAdHoc ? "Ad-hoc — grants are tied to these exact bytes" : "Unsigned"
    }

    static func current() -> SignatureInfo {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        task.arguments = ["-dv", Bundle.main.bundlePath]
        let pipe = Pipe()
        task.standardError = pipe
        task.standardOutput = Pipe()
        do { try task.run() } catch { return SignatureInfo(isAdHoc: true, teamID: nil, authority: nil) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)

        func field(_ key: String) -> String? {
            for line in text.split(separator: "\n") where line.hasPrefix(key + "=") {
                return String(line.dropFirst(key.count + 1))
            }
            return nil
        }
        let team = field("TeamIdentifier")
        return SignatureInfo(
            isAdHoc: text.contains("Signature=adhoc"),
            teamID: (team == "not set") ? nil : team,
            authority: field("Authority"))
    }
}
