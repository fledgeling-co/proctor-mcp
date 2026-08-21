import Foundation
import ProctorCore

// The history a person reads, agent half.
//
// This is the second reader of a trail PRO-0013 deliberately made unreadable at
// rest, and it is the only place plaintext from that trail leaves this process.
// So the shape of what leaves is the whole design: the window is handed a
// **projection** — the fields a row draws and nothing else — rather than records.
//
// What deliberately does not leave, and is asserted by a test rather than left
// to review: the redacted `value` and `script` fingerprints, the post-state
// hash, the sealing and signing key ids, and the session handle ids stored in
// `app` and `window`. The last is worth its own line, because it also fixes a
// bug the first draft of this had: `app` holds `app-3`, not "Mail". It is a
// handle, meaningless after a restart, and drawing it as though it named an
// application would have been wrong as well as leaky. An application is named
// here by its bundle id.
//
// Two rules about when this runs. It opens the trail only when a person asks —
// never on the half-second activity poll, never on the two-second doctor poll —
// because a timer that decrypts continuously would make sealing a property of
// the file rather than of the history. And it is reachable only from Proctor's
// own window: neither verb is in `ToolCatalogue`, so the shim cannot route a
// `tools/call` to either.
//
// One honest limit on that last claim. Keeping these verbs out of the catalogue
// keeps a model out of *this surface*; it does not make the trail unreadable to
// a model, because `proctor_policy` action `audit` is a catalogue tool that
// already opens the trail and hands back whole records. This projection is
// strictly narrower than that one, and capping that tool belongs to PRO-0005.
extension Session {

    /// How many trail entries to open for one history read.
    ///
    /// A run is several entries, so the tail read is a multiple of the runs
    /// asked for, and both ends are capped: the opened trail is the plaintext
    /// the seal exists to prevent existing, and a window holding thousands of
    /// records of it alive is a copy in all but name.
    private static let entriesPerRun = 24
    private static let maximumRuns = 100
    private static let maximumEntries = 1200

    func history(limit: Int = 20) -> JSONValue {
        let runs = max(1, min(Self.maximumRuns, limit))
        let window = min(Self.maximumEntries, runs * Self.entriesPerRun)

        var unreadable = 0
        let decoder = JSONDecoder()
        let entries: [RunHistory.Entry] = AuditLog.openedTail(window).map { entry in
            switch entry {
            case .opened(let line):
                guard let data = line.data(using: .utf8),
                      let record = try? decoder.decode(AuditRecord.self, from: data) else {
                    // A line that opens but does not decode as a record is not a
                    // secret and is not a row either. Counted with the ones that
                    // could not be opened, because from a reader's point of view
                    // it is the same fact: something happened here and this
                    // surface cannot tell you what.
                    unreadable += 1
                    return .unreadable
                }
                return .opened(record)
            case .unreadable:
                unreadable += 1
                return .unreadable
            }
        }

        let grouped = RunHistory.runs(from: entries, limit: runs)
        return .object([
            HistorySurface.Wire.runs: .array(grouped.map(Self.encode(run:))),
            HistorySurface.Wire.unreadable: .number(Double(unreadable)),
            HistorySurface.Wire.header: historyHeader()
        ])
    }

    /// Clear the history: rotate the trail now.
    ///
    /// The confirmation is in the window, and this verb has none of its own —
    /// which is the boundary PRO-0013 already named, since any process running
    /// as this user can reach the socket. The difference worth stating is that
    /// deleting the trail file by hand is *detected* by the end-mark, where this
    /// is legitimate. What closes that gap is that the rotation is not silent:
    /// the new trail opens with a record naming what went and the hash of its
    /// final entry, so a shred leaves a mark rather than an empty file.
    func clearHistory() -> JSONValue {
        let ok = AuditLog.clear()
        return .object([
            HistorySurface.Wire.cleared: .bool(ok),
            HistorySurface.Wire.runs: .array([]),
            HistorySurface.Wire.unreadable: .number(0),
            HistorySurface.Wire.header: historyHeader()
        ])
    }

    /// What the window shows above the list: how much is held, how much of the
    /// window is left, and — the part that stops a broken trail reading as an
    /// empty one — whether the trail verifies.
    private func historyHeader() -> JSONValue {
        let caps = HistoryRetention.Caps.read(from: ProcessInfo.processInfo.environment)
        let status = AuditLog.status()
        let entries = AuditLog.lineCount()
        let now = clock()
        let remaining = HistoryRetention.remaining(entries: entries, oldest: status.startedAt,
                                                   now: now, caps: caps)
        let verdict = AuditLog.verify()

        var out: [String: JSONValue] = [
            HistorySurface.Wire.entries: .number(Double(entries)),
            HistorySurface.Wire.capDays: .number(Double(caps.days)),
            HistorySurface.Wire.capEntries: .number(Double(caps.entries)),
            HistorySurface.Wire.remainingByEntries: .number(remaining.byEntries),
            HistorySurface.Wire.writable: .bool(status.writable),
            // A trail that verifies clean and a trail nobody could check are
            // different answers, and a history surface that showed neither would
            // present a rolled-back trail as an ordinary short one.
            HistorySurface.Wire.verdictClean: .bool(verdict.isClean),
            HistorySurface.Wire.verdictEntries: .number(Double(verdict.total)),
            HistorySurface.Wire.keyConfirmed: .bool(verdict.keyConfirmed)
        ]
        if let byAge = remaining.byAge { out[HistorySurface.Wire.remainingByAge] = .number(byAge) }
        if let startedAt = status.startedAt { out[HistorySurface.Wire.startedAt] = .number(startedAt) }
        if let error = status.error { out[HistorySurface.Wire.error] = .string(error) }
        if status.dropped > 0 { out[HistorySurface.Wire.dropped] = .number(Double(status.dropped)) }
        if status.keyMismatch { out[HistorySurface.Wire.keyMismatch] = .bool(true) }
        if let fault = verdict.faults.first {
            out[HistorySurface.Wire.fault] = .object([
                HistorySurface.Wire.faultKind: .string(fault.kind.rawValue),
                HistorySurface.Wire.faultEntry: .number(Double(fault.position)),
                HistorySurface.Wire.faultDetail: .string(fault.detail)
            ])
        }
        if let rotated = status.rotated {
            out[HistorySurface.Wire.rotated] = .object([
                HistorySurface.Wire.rotatedDiscarded: .number(Double(rotated.count)),
                HistorySurface.Wire.rotatedReason: .string(rotated.reason.rawValue)
            ])
        }
        return .object(out)
    }

    // MARK: - Encoding

    /// One run on the wire. Written out by hand rather than by encoding the
    /// struct, so the set of fields that can cross this boundary is a list
    /// somebody has to edit on purpose.
    private static func encode(run: RunHistory.Run) -> JSONValue {
        var out: [String: JSONValue] = [
            HistorySurface.Wire.id: .string(run.id),
            HistorySurface.Wire.tool: .string(run.tool),
            HistorySurface.Wire.startedAt: .number(run.startedAt),
            HistorySurface.Wire.endedAt: .number(run.endedAt),
            HistorySurface.Wire.outcome: .string(run.outcome.rawValue),
            HistorySurface.Wire.steps: .array(run.steps.map(encode(step:)))
        ]
        if let bundleId = run.bundleId { out[HistorySurface.Wire.bundleId] = .string(bundleId) }
        if let reason = run.reason { out[HistorySurface.Wire.reason] = .string(fence(reason)) }
        if run.unreadable > 0 { out[HistorySurface.Wire.unreadable] = .number(Double(run.unreadable)) }
        if let lane = run.lane {
            var laneOut: [String: JSONValue] = [
                HistorySurface.Wire.lane: .string(lane.lane), HistorySurface.Wire.laneRule: .string(lane.rule)
            ]
            // The scheme and never any other part of an address: PRO-0024 routes
            // on the scheme alone, and a history that carried the address would
            // be a browsing log.
            if let scheme = lane.scheme { laneOut[HistorySurface.Wire.laneScheme] = .string(scheme) }
            out[HistorySurface.Wire.lane] = .object(laneOut)
        }
        return .object(out)
    }

    private static func encode(step: RunHistory.Step) -> JSONValue {
        var out: [String: JSONValue] = [
            HistorySurface.Wire.seq: .number(Double(step.seq)),
            HistorySurface.Wire.at: .number(step.at),
            HistorySurface.Wire.outcome: .string(step.outcome.rawValue)
        ]
        if let kind = step.kind { out[HistorySurface.Wire.kind] = .string(kind) }
        // Proctor's own wording. Not fenced, because nothing outside Proctor can
        // reach it — that is the reason it is stored apart from the object.
        if let act = step.act { out[HistorySurface.Wire.act] = .string(act) }
        if let object = step.object {
            out[HistorySurface.Wire.object] = .object([
                HistorySurface.Wire.text: .string(object.text),
                HistorySurface.Wire.supplied: .bool(object.supplied)
            ])
        }
        if let plane = step.plane { out[HistorySurface.Wire.plane] = .string(plane) }
        if let ms = step.ms { out[HistorySurface.Wire.ms] = .number(Double(ms)) }
        if let reason = step.reason { out[HistorySurface.Wire.reason] = .string(fence(reason)) }
        return .object(out)
    }

    /// A reason, cleaned before it crosses.
    ///
    /// A refusal's reason is Proctor's own sentence; a failure's is an error
    /// message, which can in principle quote text a step carried. It is kept
    /// because a history that cannot say why something failed has lost most of
    /// its value, and it goes through the same cleaning every other foreign
    /// string does — one routine, never a second one that would drift from it.
    private static func fence(_ reason: String) -> String {
        StepDescription.sanitised(reason, limit: 240) ?? ""
    }
}
