import Foundation

// PRO-0074. `proctor tui` — the supervision surface, as a value.
//
// Supervision was a floating panel and a SwiftUI window, and both need a GUI
// session on the machine being driven. The remote HTTP transport and the SSH
// `StreamLocal` guest reach created the case neither covers: an operator over
// SSH sees no run line, no queue, no history, and **has no Stop button**. The
// kill switch existed and was unreachable — the same failure PRO-0015 fixed
// locally when it moved the agent to `NSApplication.run()` so a click could
// reach a button.
//
// It watches and it halts. It issues no tool calls, authors no flows and edits
// no policy, so the surface that reaches furthest is also the one that can do
// least.

public enum TUISurface {

    // MARK: - Panes

    public enum Pane: String, Sendable, CaseIterable {
        case run, queue, readiness, history, switches

        /// The number key that selects it. Derived from the ordering rather than
        /// listed, so a pane added without a key is impossible.
        public var key: String { String(Pane.allCases.firstIndex(of: self)! + 1) }

        /// Upper case for the pane you are on, lower for the rest. A terminal has
        /// one font at one size, so case is one of the few weight channels there
        /// is, and it survives losing colour.
        public func tabLabel(current: Pane) -> String {
            self == current ? rawValue.uppercased() : rawValue
        }
    }

    /// The tab bar. Every pane is always reachable, so a person who cannot find
    /// Stop is one keystroke from the pane that has it.
    public static func tabs(current: Pane) -> TUIKeybar {
        TUIKeybar(Pane.allCases.map { ($0.key, $0.tabLabel(current: current)) })
    }

    // MARK: - What the surface is looking at

    public enum Connection: Sendable, Equatable {
        case connecting
        /// Nothing on the screen is live, and the pane says so rather than
        /// showing the last good frame as current.
        case unreachable(reason: String, staleSeconds: Int)
        /// The agent answered and does not know how to be watched — it is an
        /// older build than this surface.
        ///
        /// A separate state because the remedy is different and a person acts on
        /// the remedy: an agent that is not running is started, and an agent
        /// that is running an older build is upgraded. Folding this into
        /// `unreachable` would tell somebody to start a process that is already
        /// running, which is the kind of wrong advice that costs an hour.
        case tooOld(reason: String)
        case connected
    }

    public enum Phase: String, Sendable, CaseIterable {
        case idle, acting, paused, finished
    }

    public struct Run: Sendable, Equatable {
        public var phase: Phase
        public var headline: [String]
        public var facts: [Pair]
        public var step: Int
        public var steps: Int
        public var machine: String
        public var tier: String

        public init(phase: Phase, headline: [String], facts: [Pair],
                    step: Int, steps: Int, machine: String = "host", tier: String = "native") {
            self.phase = phase; self.headline = headline; self.facts = facts
            self.step = step; self.steps = steps; self.machine = machine; self.tier = tier
        }
    }

    /// A label and its value. A tuple would do, but a named pair survives being
    /// passed through a `Sendable` boundary without the labels going missing.
    public struct Pair: Sendable, Equatable {
        public var label: String, value: String
        public init(_ label: String, _ value: String) { self.label = label; self.value = value }
    }

    public struct Lane: Sendable, Equatable {
        public var name: String, holder: String, state: String, wait: String
        public init(name: String, holder: String, state: String, wait: String) {
            self.name = name; self.holder = holder; self.state = state; self.wait = wait
        }
        public var isWaiting: Bool { state == "waiting" }
    }

    public struct Row4: Sendable, Equatable {
        public var cells: [String]
        public init(_ cells: [String]) { self.cells = cells }
    }

    public struct Model: Sendable, Equatable {
        public var pane: Pane = .run
        public var connection: Connection = .connected
        public var run: Run?
        public var lanes: [Lane] = []
        public var laneCap: String?
        public var grants: [Row4] = []
        public var readiness: [Row4] = []
        public var history: [Row4] = []
        /// Trail entries the agent could open the file for and could not open.
        ///
        /// Carried rather than dropped, because an entry that could not be read
        /// is not an entry that did not happen: a history quietly one row short
        /// reads as a complete history of a quieter machine.
        public var historyUnreadable: Int = 0
        public var historyPage: (Int, Int) = (1, 1)
        public var historySelection: Int?
        public var switches: [Row4] = []
        /// Where the handshake has got to, for the one state that has nothing
        /// else to show.
        public var handshake: Double = 60

        public init() {}

        public static func == (a: Model, b: Model) -> Bool {
            a.pane == b.pane && a.connection == b.connection && a.run == b.run
                && a.lanes == b.lanes && a.laneCap == b.laneCap && a.grants == b.grants
                && a.readiness == b.readiness && a.history == b.history
                && a.historyUnreadable == b.historyUnreadable
                && a.historyPage == b.historyPage && a.historySelection == b.historySelection
                && a.switches == b.switches && a.handshake == b.handshake
        }
    }

    // MARK: - Copy
    //
    // The states that have no data to show still have something to say. A good
    // empty state names the action that fills it rather than reporting an
    // absence, and a good error names the remedy rather than the condition.

    public enum Copy {
        public static let runEmpty = [
            "", "Nothing running.", "",
            "Proctor is listening on the agent socket. A run",
            "appears here the moment a model calls a tool.", "",
            "Press <3> for readiness, <?> for keys.",
        ]
        public static let connecting = [
            "Reaching the agent.",
            "~/Library/Application Support/",
            "  app.fledgeling.procter/agent.sock",
        ]
        /// Says the data is stale rather than showing the last good frame as
        /// current. A supervision surface drawing a four-second-old queue as live
        /// is worse than one drawing nothing.
        public static func unreachable(reason: String, staleSeconds: Int) -> ([String], [String]) {
            (["The background agent is not answering.",
              reason,
              "Until it runs, nothing on this screen is live."],
             ["",
              "The last good frame was \(staleSeconds)s ago and is not shown,",
              "because a stale frame reads as a running one."])
        }

        /// The agent answered. It is the build that is wrong, not the process.
        public static func tooOld(reason: String) -> ([String], [String]) {
            (["The agent is answering but cannot be watched.",
              reason,
              "It is an older build than this supervision surface."],
             ["",
              "Nothing on this screen is live, and no run is affected —",
              "the agent is still serving the tools it knows."])
        }
        public static let queueEmpty = ["", "Every lane is free."]
        public static let historyEmpty = [
            "", "No runs recorded on this machine.", "",
            "The trail starts at the first tool call and keeps",
            "14 days or 10,000 entries, whichever comes first.", "",
            "Press <3> to check the agent is ready to record.",
        ]
        /// The trail is there and this process could not open it.
        ///
        /// A different sentence from `historyEmpty` on purpose. "No runs
        /// recorded" and "the entries are sealed and this Mac would not open
        /// them" are opposite facts, and one empty pane drawn for both says the
        /// machine was quiet when the truth is that nobody can tell.
        public static let historySealed = [
            "", "The trail could not be opened.", "",
            "Entries are sealed to a key in this Mac's login keychain,",
            "and reading them back needs that keychain unlocked.", "",
            "Unlock the Mac and press <r>.",
        ]
        public static let laneModel = [
            "Reads never join the line.",
            "Process-directed actuation contends per app.",
            "Synthetic events contend globally, one at a time,",
            "and raising an app holds that app's lane too.",
        ]
        /// Named on the surface, because a person reading a value they cannot
        /// change here needs to know where it is changed.
        public static let switchesFooter = "set in the app or the launchd environment"
        public static let retention = "14 days, 10,000 entries"
    }

    // MARK: - Keys
    //
    // The footer is a live surface rather than a static legend: it carries the
    // keys the pane in front of you actually has.

    public static func keys(for pane: Pane) -> TUIKeybar {
        switch pane {
        case .run, .queue:
            return TUIKeybar([("p", "pause"), ("s", "stop"), ("d", "drop waiting"),
                              ("?", "help"), ("q", "quit")])
        case .readiness, .history, .switches:
            return TUIKeybar([("r", "re-check"), ("tab", "pane"), ("?", "help"), ("q", "quit")])
        }
    }

    /// Stop is offered wherever a run can be running.
    ///
    /// Not negotiable, and the reason this surface exists: an operator over SSH
    /// with no Stop is an operator watching a Mac they cannot halt.
    public static func offersStop(_ pane: Pane) -> Bool {
        keys(for: pane).items.contains { $0.0 == "s" }
    }

    // MARK: - Building a pane

    public static func node(_ model: Model) -> TUINode {
        .column([
            TUIChild(.keybar(tabs(current: model.pane)), size: 1),
            TUIChild(body(model)),
            TUIChild(.keybar(keys(for: model.pane)), size: 1),
        ])
    }

    static func body(_ model: Model) -> TUINode {
        switch model.pane {
        case .run: return runPane(model)
        case .queue: return queuePane(model)
        case .readiness: return readinessPane(model)
        case .history: return historyPane(model)
        case .switches: return switchesPane(model)
        }
    }

    static func runPane(_ model: Model) -> TUINode {
        switch model.connection {
        case .connecting:
            return .column([TUIChild(.panel(TUIPanel(
                title: "RUN", shelfCentre: "connecting", shelfRight: "-",
                child: .column([
                    TUIChild(.text(TUIText(Copy.connecting, role: "text-dim")), size: 3),
                    TUIChild(.gauge(TUIGauge(label: "handshake", value: model.handshake,
                                             readout: "waiting")), size: 1),
                    TUIChild(.blank),
                ]))))])
        case .unreachable, .tooOld:
            let why: [String], staleness: [String], shelf: String, keys: [(String, String)]
            if case .tooOld(let reason) = model.connection {
                (why, staleness) = Copy.tooOld(reason: reason)
                shelf = "agent too old"
                keys = [("r", "retry now"), ("a", "upgrade the agent")]
            } else if case .unreachable(let reason, let stale) = model.connection {
                (why, staleness) = Copy.unreachable(reason: reason, staleSeconds: stale)
                shelf = "agent unreachable"
                keys = [("r", "retry now"), ("a", "start the agent")]
            } else {
                return .blank
            }
            return .column([TUIChild(.panel(TUIPanel(
                title: "RUN", shelfCentre: shelf, borderRole: "danger",
                child: .column([
                    TUIChild(.text(TUIText(why, role: "danger")), size: 3),
                    TUIChild(.text(TUIText(staleness, role: "text-dim")), size: 3),
                    TUIChild(.blank),
                    // The remedy is a key, not a sentence. `proctor status` prints
                    // the same two answers, and this offers them.
                    TUIChild(.keybar(TUIKeybar(keys)), size: 1),
                ]))))])
        case .connected:
            guard let run = model.run else {
                return .column([TUIChild(.panel(TUIPanel(
                    title: "RUN", shelfRight: "host · native",
                    child: .text(TUIText(Copy.runEmpty, role: "text-dim", align: .centre)))))])
            }
            return .column([
                TUIChild(.panel(runPanel(run)), size: 10),
                TUIChild(queuePanel(model, pad: run.phase == .finished ? 1 : 2)),
            ])
        }
    }

    static func runPanel(_ run: Run) -> TUIPanel {
        let role: String
        switch run.phase {
        case .paused: role = "warn"
        case .finished: role = "ok"
        default: role = "text"
        }
        return TUIPanel(
            title: "RUN",
            focus: run.phase == .acting || run.phase == .paused,
            shelfCentre: run.phase == .acting ? "acting"
                : run.phase == .paused ? "paused"
                : run.phase == .finished ? "finished" : nil,
            shelfRight: "\(run.machine) · \(run.tier)",
            shelfBottomRight: run.phase == .finished
                ? "\(run.step) of \(run.steps)" : "step \(run.step) of \(run.steps)",
            child: .column([
                TUIChild(.text(TUIText(run.headline, role: role)), size: 2),
                TUIChild(.pairs(TUIPairs(run.facts.map { ($0.label, $0.value) }))),
            ]))
    }

    static func queuePanel(_ model: Model, pad: Int = 2) -> TUINode {
        let waiting = model.lanes.filter(\.isWaiting).count
        var shelf = "\(waiting) waiting"
        if let cap = model.laneCap { shelf += ", cap \(cap)" }
        guard !model.lanes.isEmpty else {
            return .panel(TUIPanel(title: "QUEUE", shelfRight: shelf, pad: 1,
                                   child: .text(TUIText(Copy.queueEmpty, role: "text-dim",
                                                        align: .centre))))
        }
        return .panel(TUIPanel(title: "QUEUE", shelfRight: shelf, pad: pad,
                               child: .table(laneTable(model.lanes))))
    }

    static func laneTable(_ lanes: [Lane]) -> TUITable {
        TUITable(columns: [
            TUIColumn("LANE", width: 13, role: "accent"),
            TUIColumn("HOLDER"),
            TUIColumn("STATE", width: 8),
            TUIColumn("WAIT", width: 5, align: .right),
        ], rows: lanes.map { [$0.name, $0.holder, $0.state, $0.wait] })
    }

    static func queuePane(_ model: Model) -> TUINode {
        .column([
            TUIChild(.panel(TUIPanel(title: "LANE MODEL",
                                     shelfRight: "\(laneModelSize) lanes",
                                     child: .text(TUIText(Copy.laneModel, role: "text-dim")))),
                     size: 8),
            TUIChild(queuePanel(model)),
        ])
    }

    /// The lane model has three lanes, and the count is about the model rather
    /// than about what is in the queue right now: reads never join the line,
    /// process-directed actuation contends per app, and synthetic events contend
    /// globally. A count derived from the live queue would say "2 lanes" on a
    /// quiet machine and describe the queue instead of the rule the panel beside
    /// it is explaining.
    public static let laneModelSize = 3

    static func readinessPane(_ model: Model) -> TUINode {
        .column([
            // Sized to the rows it is given rather than to the three the design
            // was drawn with: the campaign found a fourth grant silently dropped
            // off the bottom, which is the one failure a permissions list must
            // not have. The floor keeps the panel's shape when the report is
            // empty or unreachable.
            TUIChild(.panel(TUIPanel(title: "PERMISSIONS", shelfRight: "read-only",
                child: .table(TUITable(columns: [
                    TUIColumn("GRANT", width: 17),
                    TUIColumn("STATE", width: 9, role: "accent"),
                    TUIColumn("WHAT IT GATES"),
                ], rows: model.grants.map(\.cells))))),
                     size: max(9, model.grants.count + 6)),
            TUIChild(.panel(TUIPanel(title: "LANES", shelfRight: "derived",
                child: .table(TUITable(columns: [
                    TUIColumn("LANE", width: 8, role: "accent"),
                    TUIColumn("STATE", width: 12),
                    TUIColumn("NEEDS"),
                ], rows: model.readiness.map(\.cells)))))),
        ])
    }

    static func historyPane(_ model: Model) -> TUINode {
        guard !model.history.isEmpty else {
            let sealed = model.historyUnreadable > 0
            return .column([TUIChild(.panel(TUIPanel(
                title: "HISTORY",
                shelfCentre: sealed ? "sealed" : "nothing recorded yet",
                child: .text(TUIText(sealed ? Copy.historySealed : Copy.historyEmpty,
                                     role: "text-dim", align: .centre)))))])
        }
        return .column([TUIChild(.panel(TUIPanel(
            title: "HISTORY", shelfCentre: Copy.retention,
            shelfBottomLeft: Self.unreadableNote(model.historyUnreadable),
            shelfBottomRight: "page \(model.historyPage.0) of \(model.historyPage.1)",
            child: .table(TUITable(columns: [
                TUIColumn("WHEN", width: 8),
                TUIColumn("TOOL", width: 15, role: "accent"),
                TUIColumn("APP"),
                TUIColumn("OUTCOME", width: 8),
                TUIColumn("STEPS", width: 5, align: .right),
            ], rows: model.history.map(\.cells),
               selected: model.historySelection, selectedMarker: "▸")))))])
    }

    static func switchesPane(_ model: Model) -> TUINode {
        .column([TUIChild(.panel(TUIPanel(
            title: "SWITCHES", shelfCentre: "read-only here",
            shelfBottomLeft: Copy.switchesFooter,
            child: .table(TUITable(columns: [
                TUIColumn("SWITCH", width: 22, role: "accent"),
                TUIColumn("VALUE", width: 5),
                TUIColumn("FROM", width: 11),
                TUIColumn("EFFECT"),
            ], rows: model.switches.map(\.cells))))))])
    }

    /// What a supervision client should draw, from what it has been told.
    ///
    /// Pure, and in Core rather than in the terminal driver, for the same reason
    /// the CLI's verdict decision is: a decision only reachable by running the
    /// program against a live agent is a decision nothing checks. Every rule
    /// this surface has about staleness and about which absence is which lives
    /// here, and the driver only supplies the facts.
    public static func model(pane: Pane,
                             frame: SupervisionFrame?,
                             receivedAt: Date?,
                             now: Date,
                             failure: String? = nil,
                             outdated: String? = nil) -> Model {
        var model = Model()
        model.pane = pane
        // An agent that answered and does not know the request is a different
        // situation from one that is not running, and it is checked first
        // because it is the more specific of the two.
        if let outdated {
            model.connection = .tooOld(reason: outdated)
            return model
        }
        if let failure {
            model.connection = .unreachable(
                reason: failure,
                staleSeconds: Int(now.timeIntervalSince(receivedAt ?? now)))
            return model
        }
        guard let frame else {
            model.connection = .connecting
            return model
        }
        // A frame that has stopped arriving says so rather than being drawn as
        // current. A stale queue drawn as live is worse than none at all,
        // because it is the screen somebody decides against.
        let age = now.timeIntervalSince(receivedAt ?? now)
        if age > SupervisionFrame.staleAfter {
            model.connection = .unreachable(reason: "No frame from the agent for \(Int(age))s.",
                                            staleSeconds: Int(age))
            return model
        }
        model.connection = .connected
        model.lanes = frame.lanesForSurface()
        model.run = frame.runForSurface()
        return model
    }

    /// Fill the readiness and switches panes from a health report.
    ///
    /// PRO-0075. Found by the campaign: three of the five panes had no data
    /// source at all, so they drew their empty state whatever the machine was
    /// doing. Readiness and switches are answerable from `proctor_doctor`;
    /// history is answerable from `proctor_history`, and `history(from:)` below
    /// reads it.
    public static func readiness(from report: JSONValue) -> (grants: [Row4], lanes: [Row4]) {
        var grants: [Row4] = []
        for grant in report["grants"]?.arrayValue ?? [] {
            guard let name = grant["name"]?.stringValue else { continue }
            // PRO-0082, DEF-181. An agent from before that item files the
            // Shortcuts CLI under `grants`, so this pane drew a program on a disk
            // as a decision macOS holds about Proctor. The agent no longer sends
            // it; this partition is what stops an OLDER agent's report putting it
            // back, and it is the same rule the status window has used since
            // PRO-0036 rather than a second opinion about which is which.
            guard StatusChecks.kindIsPermission(name) else { continue }
            grants.append(Row4([name,
                                grant["state"]?.stringValue ?? "unknown",
                                gates(name)]))
        }
        var lanes: [Row4] = []
        for lane in report["lanes"]?.arrayValue ?? [] {
            guard let name = lane["lane"]?.stringValue ?? lane["name"]?.stringValue
            else { continue }
            lanes.append(Row4([name,
                               lane["state"]?.stringValue ?? "unknown",
                               needs(of: lane)]))
        }
        return (grants, lanes)
    }

    /// A note for the history shelf when some entries could not be opened.
    ///
    /// `nil` when the count is zero, so the shelf carries the fact only when
    /// there is one to carry.
    static func unreadableNote(_ count: Int) -> String? {
        guard count > 0 else { return nil }
        return count == 1 ? "1 entry could not be opened"
                          : "\(count) entries could not be opened"
    }

    /// Fill the history pane from a `proctor_history` reply.
    ///
    /// **This opens no path that was not already open.** `proctor_history` is an
    /// internal socket verb the app's own History window already calls; it is
    /// deliberately absent from `ToolCatalogue`, so the shim — which gates
    /// `tools/call` on the catalogue — cannot route a model to it, and reading
    /// it here changes neither that gate nor the sealing. Worth stating because
    /// the campaign first recorded this pane as unfixable on the reasoning that
    /// the trail is unreadable by any client, and that was wrong twice over: the
    /// verb exists, and `proctor_policy` action `audit` is a catalogue tool that
    /// already hands a model whole records. What this pane draws is the same
    /// projection the window draws, which is strictly narrower than that.
    ///
    /// The agent's own projection is trusted for what a row may say. Nothing is
    /// derived here that the reply did not name, so a field withheld there stays
    /// withheld here rather than being reconstructed on this side.
    public static func history(from reply: JSONValue,
                               timeZone: TimeZone = .current) -> (rows: [Row4], unreadable: Int) {
        let rows: [Row4] = (reply["runs"]?.arrayValue ?? []).compactMap { run in
            guard let tool = run["tool"]?.stringValue else { return nil }
            let steps = run["steps"]?.arrayValue ?? []
            return Row4([clock(run["startedAt"]?.doubleValue, in: timeZone),
                         tool,
                         run["bundleId"]?.stringValue ?? "—",
                         run["outcome"]?.stringValue ?? "unknown",
                         "\(steps.count)"])
        }
        return (rows, Int(reply["unreadable"]?.doubleValue ?? 0))
    }

    /// A wall clock in the reader's own zone, from an epoch second.
    ///
    /// Arithmetic rather than a `DateFormatter`, because the column is eight
    /// cells wide and a formatter's output is a locale's decision: a zone or a
    /// calendar that renders a 12-hour clock with a suffix overflows the column
    /// and truncates the seconds, which is a different time.
    static func clock(_ epoch: Double?, in timeZone: TimeZone) -> String {
        guard let epoch else { return "--:--:--" }
        let date = Date(timeIntervalSince1970: epoch)
        let local = Int((epoch + Double(timeZone.secondsFromGMT(for: date))).rounded(.down))
        let second = ((local % 86_400) + 86_400) % 86_400
        return String(format: "%02d:%02d:%02d", second / 3_600, (second % 3_600) / 60, second % 60)
    }

    /// What a lane still wants, from the report's own words.
    ///
    /// `requires` names the tools; `blockers` names what is actually stopping it,
    /// and a blocker outranks a requirement — a reader wants the thing in the way
    /// rather than the full bill of materials.
    static func needs(of lane: JSONValue) -> String {
        let blockers = (lane["blockers"]?.arrayValue ?? []).compactMap { $0.stringValue }
        if !blockers.isEmpty { return blockers.joined(separator: "; ") }
        let requires = (lane["requires"]?.arrayValue ?? []).compactMap { $0.stringValue }
        return requires.isEmpty ? "nothing further" : requires.joined(separator: ", ")
    }

    /// What each grant buys, in one line. Proctor's own words rather than the
    /// operating system's, because the reader wants to know what stops working.
    static func gates(_ grant: String) -> String {
        switch grant {
        case "Accessibility": return "the tree, and writes to it"
        case "Screen Recording": return "pixels, and frame status"
        case "Input Monitoring": return "noticing a person sooner"
        case "Automation": return "declared contracts, per app"
        default: return "asked for when it is needed"
        }
    }

    /// Where a switch's value came from, in the words the status window uses.
    static func source(_ raw: String?) -> String {
        switch raw {
        case "builtInDefault": return "default"
        case "saved": return "saved"
        case "environment": return "environment"
        default: return raw ?? "default"
        }
    }

    /// Fill the switches pane from a health report.
    public static func switches(from report: JSONValue) -> [Row4] {
        (report["switches"]?.arrayValue ?? []).compactMap { row in
            guard let variable = row["variable"]?.stringValue else { return nil }
            return Row4([variable,
                         (row["on"]?.boolValue ?? false) ? "on" : "off",
                         source(row["source"]?.stringValue),
                         row["timing"]?.stringValue == "live" ? "now" : "next start"])
        }
    }

    /// Render a model at a size.
    public static func render(_ model: Model, cols: Int, rows: Int) -> TUICanvas {
        TUILayout.render(node(model), cols: cols, rows: rows)
    }

    /// The floor this surface is designed against. 80×24 is what still exists
    /// everywhere, and a design that only works at 100×30 has an undisclosed
    /// requirement.
    public static let floor = (cols: 80, rows: 24)
}
