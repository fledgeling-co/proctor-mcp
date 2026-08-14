import Foundation

// PRO-0011: the checkable half of per-step artifacts on proctor_stability.
//
// The determinism instrument replays a flow N times. With capture switched on it
// now writes a frame for every step of every replay, and — with the marker
// switched on too — a marked sibling showing the point that step acted on. Every
// decision worth proving lives here, away from any window, capture stream or TCC
// grant: how the two opt-in switches reconcile, what one ledger entry says about
// what a step produced, how a whole run's ledger is assembled, and the exact JSON
// a per-step capture has always encoded to. The capture and the drawing themselves
// stay in the agent, as PRO-0010 left them. This mirrors PointerMarker, where the
// placement maths sits in Core and only the compositing is in the agent.
//
// Honesty note carried from PRO-0010: Proctor drives through AX / Apple Events
// and does not move the system pointer, so a marker annotates *where the step
// acted*, never a live cursor.

/// What one step's capture produced. The typed artifact is shared by proctor_act,
/// proctor_flow replay and proctor_stability, so the determinism ledger can read
/// the file locations without re-parsing its own output. Only act and flow replay
/// emit `json`; stability encodes a `StabilityCapture` instead, because its report
/// has to name the replay a frame came from.
public struct StepArtifact: Sendable {
    public var step: Int
    public var capture: CaptureResult?
    public var error: AgentError?
    public var errorText: String?

    public init(step: Int, capture: CaptureResult? = nil,
                error: AgentError? = nil, errorText: String? = nil) {
        self.step = step; self.capture = capture
        self.error = error; self.errorText = errorText
    }

    /// The per-step entry act and flow replay put in their `captures` array. The
    /// three shapes are fixed here, with golden coverage, because the surfaces
    /// that emit them have no test target of their own and a silent change to
    /// this JSON would be a breaking change to two tools nobody would notice.
    public var json: JSONValue {
        if let capture {
            return .object(["step": .number(Double(step)),
                            "capture": (try? JSONValue.encode(capture)) ?? .null])
        }
        if let error {
            return .object(["step": .number(Double(step)),
                            "error": (try? JSONValue.encode(error)) ?? .string(error.message)])
        }
        return .object(["step": .number(Double(step)),
                        "error": .string(errorText ?? "the capture failed")])
    }

    /// Why no frame exists, for a report that has to say so. Nil when one does.
    public var failure: String? {
        capture == nil ? (error?.message ?? errorText ?? "the capture failed") : nil
    }
}

/// One saved artifact in a stability run, identified by which replay and which
/// step produced it. Replay and step together are the identity that makes the
/// ledger useful: comparing the same step across replays is the whole point, and
/// a flat per-step list could not say which replay a frame came from.
public struct StabilityCapture: Codable, Sendable, Equatable {
    public var run: Int             // replay index, 0-based
    public var step: Int            // step index within the flow, 0-based
    public var path: String?        // the plain PNG on disk; nil when none was produced
    public var markedPath: String?  // the marked sibling, when a marker was drawn
    /// Why this step produced no frame, or no marker. A step that failed to
    /// produce either is reported here rather than failing the run or changing
    /// its score — the same way a failed capture is already carried alongside a
    /// step elsewhere.
    public var note: String?

    public init(run: Int, step: Int, path: String? = nil,
                markedPath: String? = nil, note: String? = nil) {
        self.run = run; self.step = step; self.path = path
        self.markedPath = markedPath; self.note = note
    }
}

public enum StabilityCaptureOptions {

    /// The argument names, shared by the advertised schema and the dispatcher, so
    /// a rename cannot leave a tool advertising a switch its handler never reads.
    public static let captureEachArg = "captureEach"
    public static let pointerMarksArg = "pointerMarks"

    /// What the two switches resolve to, plus what the run must say about it.
    public struct Resolved: Sendable, Equatable {
        public var captureEach: Bool
        public var pointerMarks: Bool
        public var notes: [String]
        public init(captureEach: Bool, pointerMarks: Bool, notes: [String]) {
            self.captureEach = captureEach; self.pointerMarks = pointerMarks; self.notes = notes
        }
    }

    /// Reconcile the two opt-in switches.
    ///
    /// Both off is the default and resolves to exactly today's behaviour: no
    /// frames, no notes, no added cost. Asking for the marker with capture off
    /// switches capture on and says so, rather than accepting a switch that
    /// silently does nothing — a marker is composited onto a frame, so there is
    /// nothing to mark without one. And any run that captures says that it did,
    /// because capturing after every step moves the timings, and a determinism
    /// score from a capturing run must not be quietly compared against one taken
    /// without.
    public static func resolve(captureEach: Bool, pointerMarks: Bool) -> Resolved {
        var notes: [String] = []
        let capturing = captureEach || pointerMarks

        if pointerMarks && !captureEach {
            notes.append("pointerMarks was requested with captureEach off, so per-step capture was "
                       + "switched on for this run: a marker is composited onto a frame, so there "
                       + "is nothing to mark without one.")
        }
        if capturing {
            notes.append("Per-step capture was on for this run. Capturing after every step adds "
                       + "time to that step, so these timings and any settle that depends on them "
                       + "are not comparable with a run captured off, and this determinism score "
                       + "should only be compared against another run captured the same way.")
        }
        return Resolved(captureEach: capturing, pointerMarks: pointerMarks, notes: notes)
    }

    /// One ledger entry, derived from what a step actually produced.
    ///
    /// A capture carrying a pointer overlay yields both paths. A capture with no
    /// overlay while the marker was requested yields the plain frame and says the
    /// marker was not drawn — the marker is best-effort by design, so it is
    /// missing either because the step resolved to no target point or because the
    /// drawing failed, and the entry does not claim to know which. No capture at
    /// all yields no paths and the reason. None of these fail the run.
    public static func entry(run: Int, step: Int, capture: CaptureResult?,
                             failure: String?, pointerMarksRequested: Bool) -> StabilityCapture {
        guard let capture else {
            return StabilityCapture(
                run: run, step: step,
                note: "no frame was captured for this step: "
                    + (failure ?? "the capture failed and no reason was recorded")
                    + ". The step's own result and this run's score are unaffected.")
        }
        // An overlay with no path on disk is not a marked frame, so it is reported
        // as a missing marker rather than as a location a reader would go looking
        // for and not find.
        if let pointer = capture.pointer, !pointer.annotatedPath.isEmpty {
            return StabilityCapture(run: run, step: step, path: capture.path,
                                    markedPath: pointer.annotatedPath)
        }
        if pointerMarksRequested {
            return StabilityCapture(
                run: run, step: step, path: capture.path,
                note: "the frame was captured but no marker was drawn on it: the step resolved to "
                    + "no target point, or the marker could not be drawn.")
        }
        return StabilityCapture(run: run, step: step, path: capture.path)
    }

    /// One replay's worth of ledger. Every step the replay attempted gets an
    /// entry, whether or not it produced a frame — the point of the ledger is
    /// comparing the same step across replays, which a ledger that skipped the
    /// steps that agreed, or the steps that failed, could not support.
    ///
    /// `failedStep` is the index a replay broke at. That step ran and produced no
    /// frame — capture only happens after a step succeeds — so it gets an entry
    /// saying so. Steps after it were never attempted and get none: reporting
    /// those as having failed to produce a frame would be a different and false
    /// claim.
    public static func ledger(run: Int, artifacts: [StepArtifact], failedStep: Int?,
                              pointerMarksRequested: Bool) -> [StabilityCapture] {
        var out = artifacts.map {
            entry(run: run, step: $0.step, capture: $0.capture, failure: $0.failure,
                  pointerMarksRequested: pointerMarksRequested)
        }
        if let failedStep, !out.contains(where: { $0.step == failedStep }) {
            out.append(StabilityCapture(
                run: run, step: failedStep,
                note: "no frame was captured for this step: the step itself failed, so the replay "
                    + "ended here before a frame could be taken. Steps after it were not attempted "
                    + "in this replay."))
        }
        return out.sorted { $0.step < $1.step }
    }
}

/// The determinism fold: per-run hash columns in, scores out. Extracted so the
/// claim that per-step artifacts cannot move a score is checkable rather than
/// asserted — this function takes hashes and nothing else, so there is no
/// parameter through which a capture, a marker or a failed frame could reach it.
/// The maths is unchanged from where it lived inline.
public enum StabilityScore {

    public struct Fold: Sendable, Equatable {
        public var firstDivergence: Int?
        public var stepInstability: [Double]
        public var deterministic: Bool
        public var divergenceDetail: [String: [String]]
        /// Steps measured on fewer runs than were performed, as index -> samples.
        /// The caller turns these into the notes it already emits.
        public var undersampled: [Int: Int]
        public init(firstDivergence: Int?, stepInstability: [Double], deterministic: Bool,
                    divergenceDetail: [String: [String]], undersampled: [Int: Int]) {
            self.firstDivergence = firstDivergence; self.stepInstability = stepInstability
            self.deterministic = deterministic; self.divergenceDetail = divergenceDetail
            self.undersampled = undersampled
        }
    }

    public static func fold(perRun: [[String]], stepCount: Int, runs: Int) -> Fold {
        var stepInstability: [Double] = []
        var divergenceDetail: [String: [String]] = [:]
        var undersampled: [Int: Int] = [:]

        for index in 0..<stepCount {
            let column = perRun.compactMap { index < $0.count ? $0[index] : nil }
            stepInstability.append(Canonical.instability(hashes: column))
            let distinct = Set(column)
            if distinct.count > 1 {
                divergenceDetail[String(index)] = distinct.sorted()
            }
            if column.count < perRun.count {
                undersampled[index] = column.count
            }
        }

        let firstDivergence = Canonical.firstDivergence(perRun: perRun)
        let complete = perRun.allSatisfy { $0.count == stepCount }
        return Fold(firstDivergence: firstDivergence,
                    stepInstability: stepInstability,
                    deterministic: firstDivergence == nil && complete
                        && stepInstability.allSatisfy { $0 == 0 } && runs > 1,
                    divergenceDetail: divergenceDetail,
                    undersampled: undersampled)
    }
}
