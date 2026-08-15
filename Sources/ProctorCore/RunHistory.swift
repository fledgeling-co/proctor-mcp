import Foundation

// The run history's projection, pure half.
//
// Two facts shape this file. The first is that a person does not think in
// events. The unit is "that thing it just did" — one tool call, with its steps
// inside it — so a stream of audit lines has to be folded back into runs before
// anything draws it. The second is that everything here is derived from text an
// application under test may have authored, so what leaves this file is exactly
// what a surface draws and nothing else. There is no "and the rest of the
// record" — a field that is not on the face of the window is not in these types.
//
// What deliberately does not appear anywhere below: the redacted `value` and
// `script` fingerprints, the post-state hash, the sealing and signing key ids,
// and the session handle ids the record stores in `app` and `window`. The last
// of those is worth a line: `app` holds `app-3`, not "Mail", and a handle id is
// meaningless once the agent restarts. An application is identified here by its
// bundle id, which is the durable identity the policy gate already judges on and
// is not display text somebody chose.
//
// This file reads no clock it is not given, opens no file, and holds no state.
public enum RunHistory {

    // MARK: - What one row is made of

    /// A piece of text that came from outside Proctor: an application's own
    /// accessibility title, or a name the calling model supplied. It is
    /// sanitised before it is stored, and it is a type of its own so that a view
    /// cannot render it without going through the fence — the compiler is a
    /// better rule than a convention here, because the failure is invisible.
    public struct Object: Codable, Sendable, Equatable {
        public let text: String
        public let supplied: Bool

        public init(text: String, supplied: Bool) {
            self.text = text; self.supplied = supplied
        }
    }

    /// How something ended, in the vocabulary a person reads rather than the
    /// one the record stores.
    public enum Outcome: String, Codable, Sendable, Equatable {
        case ok
        case failed
        /// The policy gate turned it down.
        case refused
        /// A person stopped it. Not a fault, and drawn as its own thing: the run
        /// HUD already refuses to paint a person's own stop in the error colour
        /// and this agrees with it.
        case halted
        /// Proctor named another lane for a page it does not drive. An act of
        /// advice, never a claim that the lane ran.
        case recommended
        /// Some steps worked and some did not.
        case mixed
        /// Proctor asked and cannot say whether it happened — a delegated step
        /// whose backend stopped answering mid-call.
        ///
        /// Not a shade of `failed`. `failed` says the action did not happen, and
        /// on this path Proctor has no basis for saying so: the request may have
        /// been delivered and performed before the driver went.
        case indeterminate
    }

    /// One step inside a run.
    public struct Step: Codable, Sendable, Equatable, Identifiable {
        public var id: String { "\(seq)-\(at)" }
        public let seq: Int
        public let at: Double
        public let kind: String?
        /// Proctor's own past-tense wording. Never foreign text.
        public let act: String?
        /// What it acted on. Foreign text; fenced wherever it is drawn.
        public let object: Object?
        /// Which plane it travelled, as the record stored it. An unrecognised
        /// value is carried through as-is rather than dropped, so a later
        /// actuation lane shows up as a label instead of as a blank.
        public let plane: String?
        public let ms: Int?
        public let outcome: Outcome
        /// Why, for a refusal or a failure. A refusal's reason is Proctor's own
        /// sentence; a failure's is an error message and is treated as foreign.
        public let reason: String?

        public init(seq: Int, at: Double, kind: String?, act: String?, object: Object?,
                    plane: String?, ms: Int?, outcome: Outcome, reason: String?) {
            self.seq = seq; self.at = at; self.kind = kind; self.act = act
            self.object = object; self.plane = plane; self.ms = ms
            self.outcome = outcome; self.reason = reason
        }
    }

    /// One tool call, with whatever it did inside it.
    public struct Run: Codable, Sendable, Equatable, Identifiable {
        public let id: String
        public let tool: String
        /// The application's bundle id, or nil for a run that touched none.
        public let bundleId: String?
        public let startedAt: Double
        public let endedAt: Double
        public let outcome: Outcome
        public let steps: [Step]
        /// Set on a run that recommended a browser lane: the lane, the rule that
        /// chose it and the address's scheme. Never an address — PRO-0024 routes
        /// on the scheme alone and recording more would store browsing history.
        public let lane: Lane?
        /// Entries inside this run's span that could not be opened at all.
        public let unreadable: Int
        /// The reason attached to the run itself, where it has one that is not a
        /// step's — a gate refusal, a person's stop.
        public let reason: String?

        public var spanMs: Int? {
            let ms = Int(((endedAt - startedAt) * 1000).rounded())
            return ms > 0 ? ms : nil
        }

        public init(id: String, tool: String, bundleId: String?, startedAt: Double,
                    endedAt: Double, outcome: Outcome, steps: [Step], lane: Lane?,
                    unreadable: Int, reason: String?) {
            self.id = id; self.tool = tool; self.bundleId = bundleId
            self.startedAt = startedAt; self.endedAt = endedAt; self.outcome = outcome
            self.steps = steps; self.lane = lane; self.unreadable = unreadable
            self.reason = reason
        }
    }

    public struct Lane: Codable, Sendable, Equatable {
        public let lane: String
        public let rule: String
        public let scheme: String?

        public init(lane: String, rule: String, scheme: String?) {
            self.lane = lane; self.rule = rule; self.scheme = scheme
        }
    }

    // MARK: - What goes in

    /// One line of the trail as the agent handed it over: opened, or marked
    /// unreadable. An entry that could not be opened is counted in place rather
    /// than dropped, because a list with silent holes in it is worse than one
    /// that says how many it could not read.
    public enum Entry: Sendable {
        case opened(AuditRecord)
        case unreadable
    }

    // MARK: - Folding a stream back into runs

    /// Group a trail tail into runs, newest run first, steps oldest first.
    ///
    /// `records` arrive oldest first, as the trail stores them.
    public static func runs(from entries: [Entry], limit: Int = 20) -> [Run] {
        var groups: [(key: String, records: [AuditRecord], unreadable: Int)] = []
        var indexByRun: [String: Int] = [:]
        var standalone = 0

        for entry in entries {
            switch entry {
            case .unreadable:
                // Attributed to whatever run is currently open, so it is counted
                // near where it happened rather than in a bucket of its own.
                if !groups.isEmpty { groups[groups.count - 1].unreadable += 1 }
            case .opened(let record):
                if let run = record.run, !run.isEmpty {
                    if let at = indexByRun[run] {
                        groups[at].records.append(record)
                    } else {
                        indexByRun[run] = groups.count
                        groups.append((key: run, records: [record], unreadable: 0))
                    }
                } else {
                    // No run identifier: a record written outside a tool call —
                    // a person's Stop, a hold, or anything written before runs
                    // were recorded at all. Each is its own event and reads as a
                    // run of one, in its right place in time.
                    standalone += 1
                    groups.append((key: "single-\(standalone)", records: [record], unreadable: 0))
                }
            }
        }

        let runs = groups.compactMap { make(id: $0.key, from: $0.records, unreadable: $0.unreadable) }
        return Array(runs.sorted { $0.startedAt > $1.startedAt }.prefix(max(0, limit)))
    }

    private static func make(id: String, from records: [AuditRecord], unreadable: Int) -> Run? {
        guard let first = records.first else { return nil }
        // Ordered by the position the run recorded, and by time where a record
        // carries no position — a gate refusal has no step number but happened
        // before the steps it refused.
        let ordered = records.enumerated().sorted { a, b in
            switch (a.element.seq, b.element.seq) {
            case let (x?, y?) where x != y: return x < y
            case (nil, _?): return true
            case (_?, nil): return false
            default:
                if a.element.timestamp != b.element.timestamp {
                    return a.element.timestamp < b.element.timestamp
                }
                return a.offset < b.offset
            }
        }.map(\.element)

        let steps = ordered.enumerated().compactMap { index, record -> Step? in
            // A record with no step kind is the run's own — a gate refusal, a
            // recommendation, a person's stop — and belongs on the run rather
            // than in its step list.
            guard record.kind != nil else { return nil }
            return Step(seq: record.seq ?? index, at: record.timestamp, kind: record.kind,
                        act: record.act, object: record.obj.map {
                            Object(text: $0.text, supplied: $0.supplied)
                        },
                        plane: record.plane, ms: record.ms,
                        outcome: outcome(of: record), reason: record.reason)
        }

        let lane = ordered.compactMap(\.recommendation).first.map {
            Lane(lane: $0.lane, rule: $0.rule, scheme: $0.scheme)
        }
        // The run's own reason is the one on a record that carries no step, so a
        // gate refusal's sentence lands on the run rather than being lost among
        // steps that never ran.
        let runReason = ordered.first { $0.kind == nil && $0.reason != nil }?.reason
            ?? ordered.compactMap(\.reason).first

        return Run(id: id,
                   tool: first.tool,
                   bundleId: ordered.compactMap(\.bundleId).first,
                   startedAt: ordered.map(\.timestamp).min() ?? first.timestamp,
                   endedAt: ordered.map(\.timestamp).max() ?? first.timestamp,
                   outcome: reduce(ordered.map { outcome(of: $0) }),
                   steps: steps,
                   lane: lane,
                   unreadable: unreadable,
                   reason: runReason)
    }

    /// One record's outcome, in the reading vocabulary. A refusal that names a
    /// person's halt is drawn as a halt: the run HUD already refuses to paint
    /// somebody's own Stop as a fault, and a history that did would disagree with
    /// the surface the person pressed.
    static func outcome(of record: AuditRecord) -> Outcome {
        switch record.outcome {
        case AuditRecord.Outcome.ok: return .ok
        case AuditRecord.Outcome.failed: return .failed
        case AuditRecord.Outcome.recommended: return .recommended
        case AuditRecord.Outcome.indeterminate: return .indeterminate
        case AuditRecord.Outcome.refused:
            return isHalt(record) ? .halted : .refused
        // An outcome this build has never heard of degrades to a fault rather
        // than to a success. It is also how an older build reads a newer trail's
        // `indeterminate`, which is a safe direction: it over-reports a problem
        // instead of hiding one, and needs no migration.
        default: return .failed
        }
    }

    /// Whether a refusal was a person's rather than the gate's. Matched on the
    /// tool that recorded it and on the halt code, both of which Proctor writes;
    /// nothing a caller or an application supplies reaches this decision.
    static func isHalt(_ record: AuditRecord) -> Bool {
        if record.tool.hasPrefix("proctor_hud") || record.tool.hasPrefix("proctor_queue")
            || record.tool.hasPrefix("run.") {
            return true
        }
        guard let reason = record.reason?.lowercased() else { return false }
        return reason.contains("haltedbyperson") || reason.contains("a person stopped")
            || reason.contains("a person paused")
    }

    /// A run's outcome from its records'. Order matters: a person's stop outranks
    /// a failure, because "somebody stopped it" is the true account of a run that
    /// then had steps it never ran; a refusal outranks the rest for the same
    /// reason; and `mixed` exists so a run that half worked is not reported as
    /// though it wholly did or wholly did not.
    static func reduce(_ outcomes: [Outcome]) -> Outcome {
        guard !outcomes.isEmpty else { return .ok }
        if outcomes.contains(.halted) { return .halted }
        // Ranked directly below a person's Stop, and above every other mixture.
        // A run holding one of these is a run whose end state Proctor cannot
        // describe, and folding it into `mixed` — or worse, letting three good
        // steps and one unknown one reduce to `ok` — would lose exactly the fact
        // the outcome was added to carry.
        if outcomes.contains(.indeterminate) { return .indeterminate }
        if outcomes.allSatisfy({ $0 == .refused }) { return .refused }
        if outcomes.allSatisfy({ $0 == .recommended }) { return .recommended }
        if outcomes.allSatisfy({ $0 == .ok }) { return .ok }
        if outcomes.allSatisfy({ $0 == .failed }) { return .failed }
        if outcomes.contains(.refused) { return .refused }
        return .mixed
    }
}
