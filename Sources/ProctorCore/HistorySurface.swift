import Foundation

// PRO-0071. What the history window draws, and what it must never count as a
// pass.
//
// The window's job is to say what a run did. The failure it must not have is the
// one the product exists to prevent, committed by the product's own UI: showing
// three passes and silently omitting a fourth check because nothing could
// measure it. `docs/architecture.md` and every assertion path already hold that
// a check which could not run is not a check that passed, and this is where a
// person reads the result.

public enum HistorySurface {

    /// How an assertion's verdict is drawn.
    ///
    /// `skipped` is not a shade of `passed` and not a shade of `failed`. It
    /// carries a reason, and it has its own treatment so a reader cannot mistake
    /// it for either.
    public enum Verdict: String, Sendable, CaseIterable {
        case passed, failed, skipped

        public var pill: String {
            switch self {
            case .passed: return "pill.ok"
            case .failed: return "pill.bad"
            case .skipped: return "pill.quiet"
            }
        }

        /// Whether this counts toward a pass total. Only one does.
        public var countsAsPass: Bool { self == .passed }
    }

    /// One assertion in a run's detail.
    public struct Check: Sendable, Equatable {
        public let name: String
        public let detail: String
        public let verdict: Verdict
        /// Present exactly when the verdict is `skipped`. A skipped check with
        /// no reason is indistinguishable from one nobody wrote.
        public let reason: String?

        public init(name: String, detail: String, verdict: Verdict, reason: String? = nil) {
            self.name = name; self.detail = detail; self.verdict = verdict; self.reason = reason
        }
    }

    /// A run's assertion tally.
    ///
    /// Three counts, never two. Folding `skipped` into either of the others is
    /// the defect; reporting a rate over `passed + failed + skipped` is the same
    /// defect wearing a denominator.
    public struct Tally: Sendable, Equatable {
        public var passed = 0
        public var failed = 0
        public var skipped = 0

        /// What was actually settled. Excludes what could not be measured,
        /// because a denominator including it reports coverage the run never had.
        public var measured: Int { passed + failed }
        public var isClean: Bool { failed == 0 }
    }

    public static func tally(_ checks: [Check]) -> Tally {
        var t = Tally()
        for check in checks {
            switch check.verdict {
            case .passed: t.passed += 1
            case .failed: t.failed += 1
            case .skipped: t.skipped += 1
            }
        }
        return t
    }

    /// Whether a check is well formed for display.
    ///
    /// A skipped verdict without a reason is refused rather than drawn: it would
    /// read as "this did not run" with no way to tell whether that was a missing
    /// instrument or a missing test.
    public static func isWellFormed(_ check: Check) -> Bool {
        check.verdict == .skipped ? (check.reason?.isEmpty == false) : true
    }

    // MARK: - Copy

    public enum Copy {
        public static let title = "History"
        public static let emptyTitle = "No runs recorded yet"
        /// Names the action that fills it, rather than reporting an absence.
        public static let emptyBody =
            "The trail starts at the first tool call. Connect a model, or drive one step from "
            + "the command line, and it appears here."
        public static let emptyAction = "Copy the connect snippet"

        /// Retention, stated on the surface. The trail **rotates whole** rather
        /// than pruning from the front: it is hash-chained from a genesis over
        /// its own prefix, so removing entries would leave the first survivor
        /// linked to a record that is gone.
        public static let retention = "14 days or 10,000 entries, whichever comes first"
        public static let rotationWord = "rotates"

        public static let skippedNote = "A check that could not run is skipped and says why. "
            + "It is never counted as a pass."
    }

    // MARK: - What the window may never show
    //
    // `RunHistory` deliberately excludes the redacted value and script
    // fingerprints, the post-state hash, the sealing and signing key ids, and
    // the session handle ids. The guarantee is that a field not on the face of
    // the window is not in the type — so this list exists to be asserted
    // against, and a later widening of the projection fails here rather than
    // leaking.

    public static let forbiddenFields = [
        "value", "script", "postStateHash", "keyId", "signingKeyId", "app", "window",
    ]

    public enum ID {
        public static let window = "proctor.history.window"
        public static func state(_ empty: Bool) -> String {
            empty ? "proctor.history.empty" : "proctor.history.ideal"
        }
        public static func run(_ id: String) -> String { "proctor.history.run.\(id)" }
        public static func check(_ name: String) -> String {
            "proctor.history.check." + name.lowercased().replacingOccurrences(of: " ", with: "-")
        }
        public static let copyConnect = "proctor.history.action.copy-connect"
    }
}
