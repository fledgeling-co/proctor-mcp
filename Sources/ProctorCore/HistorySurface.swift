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

    // MARK: - Wire
    //
    // PRO-0090, closing the half of DEF-039 that is not copy.
    //
    // `HistoryModel.swift` held 44 of its 46 flagged literals as JSON subscript
    // keys — `value["capDays"]`, `value["startedAt"]`. A dictionary subscript is
    // not one of the identifier constructs `status_literals.py` recognises, and
    // teaching it one would be editing the gate. So the keys move here, which is
    // where the classifier's default-deny answer says a string that addresses
    // the machine belongs.
    //
    // The reason this is worth more than satisfying a gate is DEF-035's shape
    // one layer down: `SessionHistory.swift` wrote `"capDays"` and
    // `HistoryModel.swift` read `"capDays"` and nothing bound them, so a rename
    // at either end would have shipped as a field that silently reads zero. Both
    // ends now reach these constants, and `HistoryWireTests` pins each spelling
    // so a rename is a failing test rather than an empty column in a window.

    public enum Wire {
        /// The two verbs. Deliberately absent from `ToolCatalogue` — a model
        /// cannot route to either — and named here because the window, the TUI
        /// and the agent's dispatch table all have to agree on the spelling.
        public static let historyTool = "proctor_history"
        public static let clearTool = "proctor_history_clear"
        public static let limitArgument = "limit"

        // The reply's three parts.
        public static let runs = "runs"
        public static let unreadable = "unreadable"
        public static let header = "header"
        public static let cleared = "cleared"

        // A run.
        public static let id = "id"
        public static let tool = "tool"
        public static let startedAt = "startedAt"
        public static let endedAt = "endedAt"
        public static let outcome = "outcome"
        public static let steps = "steps"
        public static let bundleId = "bundleId"
        public static let reason = "reason"
        public static let lane = "lane"
        public static let laneRule = "rule"
        public static let laneScheme = "scheme"

        // A step.
        public static let seq = "seq"
        public static let at = "at"
        public static let kind = "kind"
        public static let act = "act"
        public static let object = "object"
        public static let text = "text"
        public static let supplied = "supplied"
        public static let plane = "plane"
        public static let ms = "ms"

        // The header.
        public static let entries = "entries"
        public static let capDays = "capDays"
        public static let capEntries = "capEntries"
        public static let remainingByAge = "remainingByAge"
        public static let remainingByEntries = "remainingByEntries"
        public static let writable = "writable"
        public static let verdictClean = "verdictClean"
        public static let verdictEntries = "verdictEntries"
        public static let keyConfirmed = "keyConfirmed"
        public static let dropped = "dropped"
        public static let keyMismatch = "keyMismatch"
        public static let error = "error"
        public static let fault = "fault"
        public static let faultKind = "kind"
        public static let faultEntry = "entry"
        public static let faultDetail = "detail"
        public static let rotated = "rotated"
        public static let rotatedDiscarded = "discarded"
        public static let rotatedReason = "reason"

        /// Every key above, for a test that walks them rather than naming a
        /// subset and calling the walk complete.
        public static let all: [(String, String)] = [
            ("historyTool", historyTool), ("clearTool", clearTool),
            ("limitArgument", limitArgument),
            ("runs", runs), ("unreadable", unreadable), ("header", header),
            ("cleared", cleared),
            ("id", id), ("tool", tool), ("startedAt", startedAt), ("endedAt", endedAt),
            ("outcome", outcome), ("steps", steps), ("bundleId", bundleId),
            ("reason", reason), ("lane", lane), ("laneRule", laneRule),
            ("laneScheme", laneScheme),
            ("seq", seq), ("at", at), ("kind", kind), ("act", act),
            ("object", object), ("text", text), ("supplied", supplied),
            ("plane", plane), ("ms", ms),
            ("entries", entries), ("capDays", capDays), ("capEntries", capEntries),
            ("remainingByAge", remainingByAge),
            ("remainingByEntries", remainingByEntries),
            ("writable", writable), ("verdictClean", verdictClean),
            ("verdictEntries", verdictEntries), ("keyConfirmed", keyConfirmed),
            ("dropped", dropped), ("keyMismatch", keyMismatch), ("error", error),
            ("fault", fault), ("faultKind", faultKind), ("faultEntry", faultEntry),
            ("faultDetail", faultDetail),
            ("rotated", rotated), ("rotatedDiscarded", rotatedDiscarded),
            ("rotatedReason", rotatedReason),
        ]
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

        /// What the window says when the agent answered with a refusal and no
        /// message of its own.
        ///
        /// PRO-0090. One sentence, and it was a literal in two views —
        /// `HistoryModel.swift:235` and `AgentModel.swift:630` — which is the
        /// DEF-035 shape in miniature: two copies of one sentence, and an edit to
        /// either would have left the app saying two things.
        public static let agentRefused = "the agent refused the request"

        // MARK: - PRO-0090. What the history window draws.
        //
        // Every string below moved character for character from
        // `Sources/ProctorUI/HistoryWindow.swift`, which held 71 user-facing
        // literals of 91 examined. No wording changed.
        //
        // The pluralised sentences are functions rather than constants because
        // that is what they were in the view: a sentence assembled from a count
        // is still one sentence, and splitting it into fragments to keep it a
        // `let` would have made it less legible here than it was there.

        public static let clearDialogTitle = "Clear Proctor's history?"
        public static let clearConfirm = "Clear history"
        public static let clearCancel = "Keep it"
        public static let clearWarning =
            "Everything recorded here is removed from this Mac and cannot be brought "
            + "back. Proctor keeps a note that the history was cleared, how much went, "
            + "and when — but not what was in it."

        /// The window's own empty state. `emptyTitle` and `emptyBody` above are
        /// PRO-0066's wording for the same two lines and the window has never
        /// rendered either; both pairs are kept and named, as with
        /// `StatusSurface.Copy.toolsNote`. DEF-035.
        public static let nothingRecordedTitle = "Nothing recorded yet."
        public static let nothingRecordedBody =
            "Proctor writes to its history whenever a model drives this Mac. "
            + "When that has happened, the runs appear here."

        public static let unreadableTitle = "The history cannot be opened on this Mac"
        public static let unreadableSymbol = "lock.trianglebadge.exclamationmark"
        public static let unreadableNote =
            "Proctor's history is encrypted, and the key lives in this Mac's login "
            + "keychain and nowhere else. There is no copy and no recovery key: that "
            + "was chosen deliberately, so a stolen backup is unreadable."

        public static let unreachableTitle = "Proctor's background agent is not answering"
        public static let unreachableSymbol = "bolt.horizontal.circle"
        public static let unreachableNote =
            "The agent holds the key, so nothing can be read until it is running."

        public static let runsHeading = "Runs"
        public static let historyHeading = "History"
        public static let refresh = "Refresh"
        public static let clearAction = "Clear…"
        public static let headerNote =
            "What Proctor did on this Mac, one row per run. It is kept on this Mac only, "
            + "encrypted, and it clears itself as it ages."

        public static let suppliedNameHelp = "A name the model driving Proctor supplied"
        public static let readNameHelp = "A name Proctor read from the application"

        public static let verdictFailedTitle = "This history does not check out"
        public static let verdictUncheckedTitle = "This history could not be checked"
        public static let verdictSymbol = "exclamationmark.triangle.fill"
        public static let verdictUncheckedMessage =
            "The signing key could not be reached, so what is below is "
            + "internally consistent but unconfirmed: nothing proves it was "
            + "written by Proctor on this Mac."

        public static let droppedSymbol = "square.stack.3d.up.slash"
        public static func droppedTitle(_ dropped: Int) -> String {
            "\(dropped) \(dropped == 1 ? "action was" : "actions were") not recorded"
        }
        public static func droppedMessage(_ dropped: Int) -> String {
            "Proctor could not write \(dropped == 1 ? "it" : "them") "
            + "to the history this run, so \(dropped == 1 ? "it is" : "they are") "
            + "missing from the list below. A history with nothing wrong in it is "
            + "not the same as a complete one."
        }

        public static let unopenedSymbol = "questionmark.square.dashed"
        public static func unopenedTitle(_ unreadable: Int) -> String {
            "\(unreadable) \(unreadable == 1 ? "entry" : "entries") could not be opened"
        }
        public static func unopenedMessage(_ unreadable: Int) -> String {
            "\(unreadable == 1 ? "It was" : "They were") sealed with a "
            + "key this Mac no longer holds. Something happened; this window "
            + "cannot say what."
        }

        public static let rotatedSymbol = "clock.arrow.circlepath"
        public static let rotatedByPersonTitle = "History was cleared"
        public static let rotatedByLimitTitle = "History reached its limit and started again"
        public static func rotatedMessage(_ discarded: Int) -> String {
            "\(discarded) earlier "
            + "\(discarded == 1 ? "entry was" : "entries were") removed. Proctor "
            + "keeps a note that it happened and how much went, and nothing else "
            + "about them."
        }

        public static func entriesHeld(_ entries: Int) -> String {
            entries == 1 ? "entry held" : "entries held"
        }
        public static func retentionNote(capDays: Int, capEntries: Int) -> String {
            "keeps \(capDays) days or \(capEntries) entries, then starts again"
        }

        public static let noStepsRecorded = "No steps were recorded for this run."
        public static func runUnreadable(_ unreadable: Int) -> String {
            "\(unreadable) \(unreadable == 1 ? "entry" : "entries") "
            + "in this run could not be opened."
        }
        public static let actedHeading = "Acted"
        public static let expandedSymbol = "chevron.down"
        public static let collapsedSymbol = "chevron.right"
        public static let stepDetailSymbol = "text.alignleft"

        /// A run's one-line summary: how many steps, and how it ended.
        ///
        /// PRO-0090. A copy table keyed by an outcome, moved out of the view
        /// beside the value it describes — the same handling PRO-0081 gave
        /// `StatusChecks.ToolRow.Tone.symbol`, and for the same reason: a string
        /// returned from a computed property never reaches an identifier
        /// construct, so no classifier can see it as one.
        ///
        /// `indeterminate` is deliberately never the word "failed". The whole
        /// reason that outcome exists is that Proctor has no basis for saying
        /// the step did not happen.
        public static func runSummary(steps: Int, outcome: RunHistory.Outcome) -> String {
            let count = steps == 0 ? "no steps" : (steps == 1 ? "1 step" : "\(steps) steps")
            switch outcome {
            case .ok:            return count
            case .failed:        return "\(count), failed"
            case .refused:       return "\(count), refused"
            case .halted:        return "\(count), stopped by a person"
            case .recommended:   return "named another lane"
            case .mixed:         return "\(count), some failed"
            case .indeterminate: return "\(count), outcome unknown"
            }
        }

        /// A step's cost, in the unit that reads.
        public static func duration(ms: Int) -> String {
            ms < 1000 ? "\(ms) ms" : String(format: "%.1f s", Double(ms) / 1000)
        }

        /// The mark drawn beside an outcome.
        ///
        /// A person's own stop is not a fault and is not drawn as one — the run
        /// panel already refuses to paint it red and this agrees with it.
        public static func outcomeSymbol(_ outcome: RunHistory.Outcome) -> String {
            switch outcome {
            case .ok:            return "checkmark.circle.fill"
            case .failed:        return "xmark.circle.fill"
            case .refused:       return "hand.raised.fill"
            case .halted:        return "stop.circle.fill"
            case .recommended:   return "arrow.turn.down.right"
            case .mixed:         return "exclamationmark.circle.fill"
            case .indeterminate: return "questionmark.circle.fill"
            }
        }

        /// How an actuation plane is said to a person. An unknown plane is
        /// echoed rather than hidden: the window would otherwise draw a blank
        /// where the agent named something this build does not know.
        ///
        /// PRO-0090, DEF-130. The view matched `case "appleEvent"` — singular —
        /// and `ActuationPlane`'s raw value is `appleEvents`. Nothing in this
        /// repo produces the singular spelling: `Actuator.swift:809` returns
        /// `.appleEvents`, and `RunHUDSurface.swift:107` matches the plural.
        /// So the branch was dead and an Apple Events step drew the wire word
        /// `appleEvents` through the default arm, where the code plainly meant
        /// to draw "Apple event". Matching on the enum rather than on a literal
        /// is what makes the mismatch impossible rather than invisible, and it
        /// is the reason this label is worth having in Core at all.
        ///
        /// The wording is unchanged. What changed is that it can now appear.
        public static func planeLabel(_ plane: String) -> String {
            switch plane {
            case ActuationPlane.accessibility.rawValue:  return "accessibility"
            case ActuationPlane.appleEvents.rawValue:    return "Apple event"
            case ActuationPlane.syntheticEvent.rawValue: return "synthetic"
            default:                                     return plane
            }
        }
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

    /// The SwiftUI scene id and title for the history window.
    ///
    /// PRO-0090. Three places named this window by hand: the `Window(_:id:)`
    /// that declares it, the two menu items that open it, and the capture
    /// exclusion in `HistoryWindow.excludeFromCapture()`, which matches on the
    /// id and falls back to the title. That last one is why they belong
    /// together: it is what keeps a window holding opened history out of every
    /// screenshot, including one `proctor_capture` takes, and it fails silently
    /// if either name drifts.
    public static let sceneID = "history"
    public static let sceneTitle = "History"

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
