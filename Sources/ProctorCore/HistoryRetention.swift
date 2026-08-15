import Foundation

// How much history is kept, and what happens when that is passed.
//
// The decision half only: no file, no clock it is not handed, no key store. The
// agent supplies the count, the trail's start time and the wall clock, and this
// answers keep or rotate. `AuditLog` does the moving.
//
// Why there is a cap at all. The trail records everything an agent did on
// somebody's Mac, and until now it grew forever. A permanent, complete record of
// that sitting in a home directory is a surveillance artifact whether or not
// anyone meant it to be, so retention is a decision this feature has to make
// rather than a default it can inherit.
//
// Why rotation rather than pruning. The trail is hash-chained from a genesis
// taken over its own prefix and anchored by a count and a head hash held out of
// reach of file access. Removing entries from the front is therefore not
// representable: the first survivor still stores a link to a record that is gone,
// and the verifier is right to call that a broken chain. Two alternatives were
// live — a retired segment carrying its own anchor, and a signed truncation
// record that makes front-removal legal. The first grows the verifier or quietly
// narrows what it covers; the second converts "removing history is
// unrepresentable" into "removing history is permitted when signed", which is
// the property worth keeping. So the trail rotates in whole, and the first
// record of the new trail commits to what the old one held.
public enum HistoryRetention {

    /// The two dials, already clamped.
    public struct Caps: Sendable, Equatable {
        public let days: Int
        public let entries: Int

        public init(days: Int, entries: Int) {
            self.days = Caps.clampDays(days)
            self.entries = Caps.clampEntries(entries)
        }

        public static let `default` = Caps(days: defaultDays, entries: defaultEntries)

        public static let defaultDays = 14
        public static let defaultEntries = 10_000
        public static let minimumDays = 1
        public static let maximumDays = 90
        public static let minimumEntries = 100
        public static let maximumEntries = 100_000

        static func clampDays(_ value: Int) -> Int {
            min(maximumDays, max(minimumDays, value))
        }

        static func clampEntries(_ value: Int) -> Int {
            min(maximumEntries, max(minimumEntries, value))
        }

        /// Read from the agent's environment, in the shape the other switches
        /// use.
        ///
        /// There is deliberately no value meaning "keep everything" and none
        /// meaning "keep almost nothing". An unbounded setting would reinstate
        /// exactly the artifact the cap exists to remove, and a floor of zero
        /// would let anything that can write the agent's environment shred the
        /// trail on the next append. Anyone who can rewrite that environment can
        /// already replace the agent, so the floor is a guard against a typo
        /// rather than a claim against that attacker — but a typo that silently
        /// destroys history is worth guarding against on its own.
        ///
        /// An unset, empty, unparseable or out-of-range value takes the default
        /// or the nearer bound. It never disables the cap.
        public static func read(from env: [String: String]) -> Caps {
            Caps(days: number(env["PROCTOR_HISTORY_DAYS"]) ?? defaultDays,
                 entries: number(env["PROCTOR_HISTORY_ENTRIES"]) ?? defaultEntries)
        }

        private static func number(_ raw: String?) -> Int? {
            guard let raw else { return nil }
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, let value = Int(trimmed) else { return nil }
            return value
        }
    }

    /// Why a rotation happened. Carried into the record the new trail opens with,
    /// so a person's clear and a cap being reached are told apart afterwards.
    public enum Reason: String, Sendable, Equatable, Codable {
        case age
        case size
        case person
    }

    public enum Decision: Sendable, Equatable {
        case keep
        case rotate(Reason)
    }

    /// Whether the trail has outgrown what is kept.
    ///
    /// `oldest` is the trail's own start time, which lives with the end-mark in
    /// the key store rather than in the file — the timestamps inside the file are
    /// sealed, and reading them to decide whether to write would make an append
    /// depend on the read key. Nil where an end-mark predates this feature, which
    /// leaves the age cap dormant until the next rotation writes one and the
    /// entry cap carrying the whole decision in the meantime.
    ///
    /// The age test is a wall-clock one, because that is the clock the records
    /// are stamped with and there is no better one available. A clock moved
    /// backwards delays a rotation — the entry cap is the backstop for that — and
    /// a clock moved forwards brings one on, which the rotation record attests
    /// rather than hides.
    public static func decide(entries: Int, oldest: Double?, now: Double,
                              caps: Caps = .default) -> Decision {
        if entries >= caps.entries { return .rotate(.size) }
        if let oldest, oldest > 0 {
            let age = now - oldest
            if age >= Double(caps.days) * 86_400 { return .rotate(.age) }
        }
        return .keep
    }

    /// How much of the window is left, as a fraction from 0 to 1, for a surface
    /// that would rather show a person where they are than surprise them. Nil
    /// where the age is unknowable, in which case the count is the only honest
    /// thing to show.
    public static func remaining(entries: Int, oldest: Double?, now: Double,
                                 caps: Caps = .default) -> (byAge: Double?, byEntries: Double) {
        let byEntries = 1 - min(1, max(0, Double(entries) / Double(caps.entries)))
        guard let oldest, oldest > 0 else { return (nil, byEntries) }
        let span = Double(caps.days) * 86_400
        let used = min(1, max(0, (now - oldest) / span))
        return (1 - used, byEntries)
    }

    /// What the record opening a new trail says. It is the only surviving
    /// statement about the history that has gone, so it carries the count, the
    /// span and — the part that matters — the discarded trail's final link, which
    /// is what stops "the history is gone" and "the history was never there"
    /// being the same claim.
    ///
    /// `discarded` is nil when the summary could not be observed: a rotation that
    /// was interrupted after the trail was replaced has nothing left to count, and
    /// the marker recording the intent is an ordinary file anyone who can write
    /// the directory could have planted. Saying so is the honest answer; repeating
    /// an unverifiable number under Proctor's signature is not.
    public static func rotationNote(reason: Reason, discarded: Int?, from: Double?, to: Double?,
                                    trailId: String?, head: String?) -> String {
        var out: String
        switch reason {
        case .person:
            out = "A person cleared Proctor's history."
        case .age:
            out = "Proctor's history reached its age limit and started again."
        case .size:
            out = "Proctor's history reached its size limit and started again."
        }
        guard let discarded else {
            out += " How much was discarded could not be established, because the change was "
                 + "interrupted after the record had already been replaced."
            out += " There is no copy: the discarded entries cannot be recovered from this Mac."
            return out
        }
        out += " \(discarded) \(discarded == 1 ? "entry was" : "entries were") discarded"
        if let from, let to, discarded > 0 {
            out += ", covering \(stamp(from)) to \(stamp(to))"
        }
        out += "."
        if let trailId { out += " The discarded trail was \(trailId)." }
        if let head { out += " Its final entry hashed to \(head)." }
        out += " There is no copy: the discarded entries cannot be recovered from this Mac."
        return out
    }

    private static func stamp(_ seconds: Double) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: Date(timeIntervalSince1970: seconds))
    }
}
