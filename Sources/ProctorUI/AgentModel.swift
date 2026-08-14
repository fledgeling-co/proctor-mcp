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

    /// Polling starts with the model and runs for the app's whole life, not just
    /// while the window is open — the menu-bar glyph and status line have to stay
    /// live after the window is closed.
    init() { startPolling() }

    var ready: Bool { report?.ready == true }

    var requiredGrants: [DoctorReport.Grant] {
        report?.grants.filter(\.required) ?? []
    }

    var optionalGrants: [DoctorReport.Grant] {
        report?.grants.filter { !$0.required } ?? []
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
    private func reprobeAfterGrant() {
        isApplying = true
        Actions.restartAgent()
        // launchd needs a beat to bring the agent back; polling immediately
        // races the restart and reports it as down.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.isApplying = false
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
    }

    /// What the menu bar item draws. Readiness outranks the character: a calm
    /// idle picture over an agent that is not answering would be a falsehood
    /// about the machine.
    var menuBarIcon: MenuBarIcon {
        switch reachability {
        case .unknown: return .checking
        case .unreachable: return MenuBarIcon.decide(reachable: false, ready: false, phase: hudPhase)
        case .reachable: return MenuBarIcon.decide(reachable: true, ready: ready,
                                                   phase: hudPhase,
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
            notice: f?["notice"]?.stringValue)
        return ActivitySnapshot(current: result["current"]?.stringValue, items: items,
                                queueWaiting: result["queueWaiting"]?.intValue ?? 0,
                                hud: HUDState(result["hud"]),
                                foreground: foreground)
    }

    /// The run panel's switch and the run's controls, over the same socket. An
    /// internal verb: it is not in the tool catalogue, so no MCP host can reach
    /// it and put a person's stop button away.
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
