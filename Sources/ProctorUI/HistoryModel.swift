import Foundation
import ProctorCore

/// The History window's view of the trail.
///
/// It reads once when the window opens and once more whenever a person asks. It
/// does **not** poll, and that is a decision rather than an omission: every read
/// opens a trail that is sealed at rest, and a timer doing that continuously
/// would make the sealing a property of the file rather than of the history. The
/// live surfaces for what is happening now already exist twice over — the run
/// panel and the menu bar — and neither needs the key.
///
/// Everything it holds is dropped when the window closes, for the same reason:
/// what it holds is the opened plaintext, and a second process keeping thousands
/// of records of it alive is a copy in all but name.
@MainActor
@Observable
final class HistoryModel {

    enum State: Equatable {
        case idle
        case loading
        /// The agent answered and there is nothing recorded.
        case empty
        case loaded
        /// The agent answered and said it cannot open the trail on this Mac.
        case unreadable(String)
        /// The agent did not answer.
        case unreachable(String)
    }

    private(set) var state: State = .idle
    private(set) var runs: [Run] = []
    private(set) var header: Header?
    private(set) var unreadable = 0
    /// Which run rows are open. Held here rather than in the view so a refresh
    /// does not fold everything the reader had opened.
    var expanded: Set<String> = []

    // MARK: - What a row is

    /// Text that came from outside Proctor. It is a type of its own so that a
    /// view cannot render it without going through the fence: the compiler is a
    /// better rule than a convention here, because a missing fence is invisible
    /// until somebody exploits it.
    struct Foreign: Equatable {
        let text: String
        let supplied: Bool
    }

    struct Step: Identifiable, Equatable {
        var id: String { "\(seq)-\(at.timeIntervalSince1970)" }
        let seq: Int
        let at: Date
        let kind: String?
        /// Proctor's own wording. Safe to draw plainly.
        let act: String?
        /// What it acted on. Fenced.
        let object: Foreign?
        let plane: String?
        let ms: Int?
        let outcome: RunHistory.Outcome
        /// Fenced: a failure's reason is an error message, not Proctor's prose.
        let reason: Foreign?
    }

    struct Run: Identifiable, Equatable {
        let id: String
        let tool: String
        let bundleId: String?
        let startedAt: Date
        let endedAt: Date
        let outcome: RunHistory.Outcome
        let steps: [Step]
        let lane: String?
        let unreadable: Int
        let reason: Foreign?

        var spanMs: Int? {
            let ms = Int(((endedAt.timeIntervalSince1970 - startedAt.timeIntervalSince1970) * 1000)
                         .rounded())
            return ms > 0 ? ms : nil
        }
    }

    struct Header: Equatable {
        var entries = 0
        var capDays = 0
        var capEntries = 0
        var remainingByAge: Double?
        var remainingByEntries: Double = 1
        var writable = true
        var verdictClean = true
        var keyConfirmed = true
        var dropped = 0
        var keyMismatch = false
        var faultDetail: String?
        var error: String?
        var rotatedDiscarded: Int?
        var rotatedReason: String?

        /// How much of the window is left, as the smaller of the two dials —
        /// whichever fills first is the one that will end this history.
        var remaining: Double {
            min(remainingByEntries, remainingByAge ?? 1)
        }
    }

    // MARK: - Reading

    func load() {
        state = runs.isEmpty ? .loading : state
        Task.detached(priority: .userInitiated) {
            let answer = Self.call(HistorySurface.Wire.historyTool,
                                   arguments: [HistorySurface.Wire.limitArgument: JSONValue.number(30)])
            await MainActor.run { self.apply(answer) }
        }
    }

    /// Clear, which rotates the trail. Destructive and not undoable; the view
    /// asks before calling this.
    func clear() {
        state = .loading
        Task.detached(priority: .userInitiated) {
            let answer = Self.call(HistorySurface.Wire.clearTool, arguments: [:])
            await MainActor.run { self.apply(answer) }
        }
    }

    /// Drop everything when the window goes. The opened trail does not outlive
    /// the window that asked for it.
    func forget() {
        runs = []
        header = nil
        expanded = []
        unreadable = 0
        state = .idle
    }

    /// The agent answered, or did not. A plain two-case answer rather than
    /// `Result`, because the failure here is a sentence to show a person and not
    /// an error anybody catches.
    enum Answer {
        case reply(JSONValue)
        case noAnswer(String)
    }

    private func apply(_ answer: Answer) {
        switch answer {
        case .noAnswer(let message):
            state = .unreachable(message)
        case .reply(let value):
            header = Self.header(from: value[HistorySurface.Wire.header])
            unreadable = value[HistorySurface.Wire.unreadable]?.intValue ?? 0
            runs = value[HistorySurface.Wire.runs]?.arrayValue?.compactMap(Self.run(from:)) ?? []
            expanded = expanded.intersection(Set(runs.map(\.id)))
            if let error = header?.error, !(header?.writable ?? true) {
                state = .unreadable(error)
            } else if runs.isEmpty {
                state = .empty
            } else {
                state = .loaded
            }
        }
    }

    // MARK: - Decoding

    private static func run(from value: JSONValue) -> Run? {
        guard let id = value[HistorySurface.Wire.id]?.stringValue, let tool = value[HistorySurface.Wire.tool]?.stringValue,
              let started = value[HistorySurface.Wire.startedAt]?.doubleValue else { return nil }
        let ended = value[HistorySurface.Wire.endedAt]?.doubleValue ?? started
        return Run(
            id: id,
            tool: tool,
            bundleId: value[HistorySurface.Wire.bundleId]?.stringValue,
            startedAt: Date(timeIntervalSince1970: started),
            endedAt: Date(timeIntervalSince1970: ended),
            outcome: value[HistorySurface.Wire.outcome]?.stringValue.flatMap(RunHistory.Outcome.init(rawValue:)) ?? .ok,
            steps: value[HistorySurface.Wire.steps]?.arrayValue?.compactMap(step(from:)) ?? [],
            lane: value[HistorySurface.Wire.lane]?[HistorySurface.Wire.lane]?.stringValue,
            unreadable: value[HistorySurface.Wire.unreadable]?.intValue ?? 0,
            reason: value[HistorySurface.Wire.reason]?.stringValue.map { Foreign(text: $0, supplied: false) })
    }

    private static func step(from value: JSONValue) -> Step? {
        guard let at = value[HistorySurface.Wire.at]?.doubleValue else { return nil }
        let object = value[HistorySurface.Wire.object].flatMap { o -> Foreign? in
            guard let text = o[HistorySurface.Wire.text]?.stringValue else { return nil }
            return Foreign(text: text, supplied: o[HistorySurface.Wire.supplied]?.boolValue ?? false)
        }
        return Step(
            seq: value[HistorySurface.Wire.seq]?.intValue ?? 0,
            at: Date(timeIntervalSince1970: at),
            kind: value[HistorySurface.Wire.kind]?.stringValue,
            act: value[HistorySurface.Wire.act]?.stringValue,
            object: object,
            plane: value[HistorySurface.Wire.plane]?.stringValue,
            ms: value[HistorySurface.Wire.ms]?.intValue,
            outcome: value[HistorySurface.Wire.outcome]?.stringValue.flatMap(RunHistory.Outcome.init(rawValue:)) ?? .ok,
            reason: value[HistorySurface.Wire.reason]?.stringValue.map { Foreign(text: $0, supplied: false) })
    }

    private static func header(from value: JSONValue?) -> Header? {
        guard let value else { return nil }
        var out = Header()
        out.entries = value[HistorySurface.Wire.entries]?.intValue ?? 0
        out.capDays = value[HistorySurface.Wire.capDays]?.intValue ?? 0
        out.capEntries = value[HistorySurface.Wire.capEntries]?.intValue ?? 0
        out.remainingByAge = value[HistorySurface.Wire.remainingByAge]?.doubleValue
        out.remainingByEntries = value[HistorySurface.Wire.remainingByEntries]?.doubleValue ?? 1
        out.writable = value[HistorySurface.Wire.writable]?.boolValue ?? true
        out.verdictClean = value[HistorySurface.Wire.verdictClean]?.boolValue ?? true
        out.keyConfirmed = value[HistorySurface.Wire.keyConfirmed]?.boolValue ?? true
        out.dropped = value[HistorySurface.Wire.dropped]?.intValue ?? 0
        out.keyMismatch = value[HistorySurface.Wire.keyMismatch]?.boolValue ?? false
        out.faultDetail = value[HistorySurface.Wire.fault]?[HistorySurface.Wire.faultDetail]?.stringValue
        out.error = value[HistorySurface.Wire.error]?.stringValue
        out.rotatedDiscarded = value[HistorySurface.Wire.rotated]?[HistorySurface.Wire.rotatedDiscarded]?.intValue
        out.rotatedReason = value[HistorySurface.Wire.rotated]?[HistorySurface.Wire.rotatedReason]?.stringValue
        return out
    }

    /// Off the main actor. `SocketClient` is blocking by design, and this is the
    /// same short-lived-connection shape the status window already uses: the
    /// agent is the long-lived party and a reader should never be why it is busy.
    private nonisolated static func call(_ tool: String,
                                         arguments: [String: JSONValue]) -> Answer {
        let client = SocketClient()
        defer { client.disconnect() }
        do {
            let response = try client.send(
                AgentRequest(id: UUID().uuidString, tool: tool, arguments: .object(arguments)))
            guard response.ok, let result = response.result else {
                return .noAnswer(response.error?.message ?? HistorySurface.Copy.agentRefused)
            }
            return .reply(result)
        } catch let error as AgentError {
            return .noAnswer(error.message)
        } catch {
            return .noAnswer(error.localizedDescription)
        }
    }
}
