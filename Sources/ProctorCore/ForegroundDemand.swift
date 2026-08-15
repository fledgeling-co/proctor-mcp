import Foundation

// Will this batch take the foreground?
//
// One value answers it, computed before anything runs, and everything that
// needs the answer reads this rather than re-deriving it. `LaneDemand` asks it
// to decide whether a run takes the exclusive global lane; the run HUD asks it
// to say so on the panel before the machine is taken; the menu bar asks it to
// say so while it is happening. Three answers to one question is how they drift
// apart.
//
// The distinction that makes it non-trivial is that a step's plane is not
// always knowable up front:
//
//   CERTAIN      `click`, `hover`, `dragPath`, `key`. There is no accessibility
//                expression for them at all, so they enter the WindowServer
//                event stream and need the target frontmost. Known from the
//                kind alone.
//   CONDITIONAL  `type` into a field the accessibility plane cannot write, and
//                `scroll` with no scroll action to perform. Both prefer the
//                accessibility plane and fall to a synthetic event only when the
//                element refuses — which is a property of the element, not of
//                the request, so it is not knowable until the step is reached.
//
// So an up-front count is a FLOOR. It is stated as one (the wording below never
// says a bare "N of M" when a conditional step could add to N), it revises
// upward when a fallback actually happens, and what a finished run reports is
// measured from the planes the steps actually travelled rather than predicted a
// second time.
//
// Which kinds are which is the agent's business — it owns the actuator — so
// both sets are passed in rather than named here, exactly as `LaneDemand`
// already takes `synthetic`.
//
// And asking for the foreground is not the same as needing it. Nothing
// activates an application except a synthetic post, so `foreground: true` on a
// batch with no step that could ever post is a request with nothing to spend
// itself on: it used to take the exclusive global lane, arm a contention watch
// and announce a takeover, all for a run that then travelled the accessibility
// plane and left the machine alone. The predicate below is "might post, or
// raises" rather than "was asked", and the dead request is disclosed on the
// report instead of being honoured.

/// What a batch will do to the foreground, decided from its steps before it runs.
public struct ForegroundDemand: Hashable, Sendable {
    /// Steps that can only travel the event stream.
    public var certainSteps: Int
    /// Steps that may fall to it, depending on the element they reach.
    public var conditionalSteps: Int
    /// Which kinds those were, so a reader of this value can tell when one of
    /// them has settled and the uncertainty it carried is spent. Without it the
    /// hedge on the wording would never come off: a `type` that stayed on the
    /// accessibility plane resolves the doubt without changing any count.
    public var conditionalKinds: Set<ActionStep.Kind> = []
    /// A `raise` brings a window forward, which moves the ground under every
    /// synthetic event anybody else is posting.
    public var raises: Bool
    /// The batch asked for the app in front outright.
    public var requestedForeground: Bool
    public var totalSteps: Int

    public init(certainSteps: Int = 0, conditionalSteps: Int = 0,
                conditionalKinds: Set<ActionStep.Kind> = [], raises: Bool = false,
                requestedForeground: Bool = false, totalSteps: Int = 0) {
        self.certainSteps = certainSteps
        self.conditionalSteps = conditionalSteps
        self.conditionalKinds = conditionalKinds
        self.raises = raises
        self.requestedForeground = requestedForeground
        self.totalSteps = totalSteps
    }

    /// It will take the foreground. This is the predicate the scheduler applies
    /// and the one a decision to hold a run should be made on: everything it
    /// counts is knowable now and cannot turn out otherwise.
    public var takesForeground: Bool {
        mightPost || raises
    }

    /// Could any step in this batch reach the event stream?
    ///
    /// A certain step always can. A conditional one can only when the batch
    /// asked for the front, because the actuator *refuses* the synthetic
    /// fallback outright when `foreground` is false rather than activating
    /// behind the caller's back — so `requestedForeground` is a precondition of
    /// posting rather than a second reason for it.
    ///
    /// Which is why `requestedForeground` alone is not enough. A batch of
    /// `press` and `setValue` steps that asked for the front never calls
    /// `activate`, because nothing in it has anywhere to use the front: the
    /// request is a habit, not a plan, and honouring it costs the exclusive
    /// global lane, a contention watch and a line on the panel announcing a
    /// takeover that never happens.
    public var mightPost: Bool {
        certainSteps > 0 || (requestedForeground && conditionalSteps > 0)
    }

    /// The batch asked for the front and no step in it could ever have used
    /// one. Disclosed rather than silently corrected, so a caller passing
    /// `foreground: true` out of habit finds out.
    public var requestWasInert: Bool {
        requestedForeground && !mightPost && !raises
    }

    /// It might. Disclosure only, and deliberately not the scheduler's predicate
    /// — a `type` batch that took the exclusive global lane on the chance it
    /// falls back would serialise runs that never touch the foreground.
    public var mayTakeForeground: Bool {
        takesForeground || conditionalSteps > 0
    }

    public static func forBatch(kinds: [ActionStep.Kind],
                                synthetic: Set<ActionStep.Kind>,
                                conditional: Set<ActionStep.Kind>,
                                foreground: Bool) -> ForegroundDemand {
        ForegroundDemand(
            certainSteps: kinds.count(where: { synthetic.contains($0) }),
            conditionalSteps: kinds.count(where: { conditional.contains($0) }),
            conditionalKinds: conditional,
            raises: kinds.contains(.raise),
            requestedForeground: foreground,
            totalSteps: kinds.count)
    }

    /// The panel's up-front row, or nil when the batch leaves the machine alone.
    ///
    /// The one sentence Proctor says about a plane before a run, and it is only
    /// ever said about the exception — accessibility is the rule and is never
    /// announced. `known` is the count as it stands, which starts at
    /// `certainSteps` and rises if a conditional step turns out to need the
    /// front, so the number a person is reading is never behind what has
    /// actually happened.
    /// `delegated` says another program is performing the steps. It changes the
    /// wording rather than adding a row: PRO-0019 settled that the exception is
    /// said once, in words, on one row with one wording function, and a second
    /// row for a second fact would be two things competing for the same glance.
    ///
    /// It matters on this row in particular because a delegated batch predicts
    /// nothing — every kind on that lane decides at the element — so the count is
    /// always a "may", and the reason it is always a "may" is worth a reader
    /// knowing. It is also the only place the up-front surface can say what IS
    /// knowable before such a run starts, since the full-screen statement cannot
    /// go up until an escalation has actually happened.
    public func notice(app: String?, known: Int? = nil,
                       resolvedConditional: Int = 0,
                       delegated: Bool = false) -> String? {
        // Sanitised, and unfenced — deliberately the same treatment
        // `RunHUDState.exceptionLine` already gives the app name on this very
        // row. Two quoting conventions on one line would be worse than either.
        let who = StepDescription.sanitised(app) ?? "the app under test"
        let count = max(known ?? certainSteps, certainSteps)
        // A conditional step that has not run yet could still add to the count.
        // One that has run cannot, whichever plane it took, so the hedge comes
        // off as the doubt is spent rather than staying up for the whole run.
        let pending = max(0, conditionalSteps - resolvedConditional)
        let of = "\(count) of \(totalSteps) step\(totalSteps == 1 ? "" : "s")"

        if count > 0 {
            return pending > 0
                ? "At least \(of) need \(who) in front"
                : "\(of) need \(who) in front"
        }
        if pending > 0 {
            let upTo = "\(pending) of \(totalSteps) step\(totalSteps == 1 ? "" : "s")"
            return delegated
                ? "Driven by cua-driver — up to \(upTo) may take \(who) to the front"
                : "Up to \(upTo) may need \(who) in front"
        }
        // `raise` and a bare `foreground: true` change what is in front without
        // any step needing the event stream. Worth saying, and there is no count
        // to put on it.
        if takesForeground { return "This run brings \(who) to the front" }
        // A `foreground: true` no step can use is not an exception to announce.
        // Accessibility is the rule and is never announced, and this batch is
        // going to travel it whatever the flag says.
        //
        // Except on the delegated lane, where there IS something to announce and
        // it is not a count: the steps are being performed by another program,
        // which decides at each element whether to take the front and can do so
        // without warning Proctor first. Said up front because it is the part
        // that IS knowable before such a run starts.
        if delegated { return "Driven by cua-driver — a step may take \(who) to the front" }
        return nil
    }
}

/// How much of a finished run actually needed the foreground.
///
/// Measured, not predicted a second time: `measured` counts the steps whose
/// reported plane was `syntheticEvent`, so it accounts for a `type` that fell
/// back as well as for the kinds that were never going to travel any other way.
/// That is what makes "this suite cannot run unattended" a fact about the suite
/// rather than something you find out by watching it.
public struct ForegroundReport: Codable, Sendable, Equatable {
    /// What was knowable before the run: steps that could only be synthetic.
    public var declaredCertain: Int
    /// And the ones that might have been, before anything was tried.
    public var declaredConditional: Int
    /// What actually travelled the event stream.
    public var measured: Int
    public var totalSteps: Int
    /// Whether the batch took the foreground at all, on the same predicate the
    /// scheduler used.
    public var ranInForeground: Bool
    /// The batch asked for the foreground and nothing in it could use one, so
    /// the request was not honoured. Said rather than silently corrected: a
    /// caller passing `foreground: true` by habit is paying nothing for it now,
    /// and would otherwise never learn that it was doing nothing before.
    public var requestIgnored: Bool
    /// Steps that were performed by a backend which did not say how.
    ///
    /// `measured` answers "how much of this took the machine" and can only count
    /// what it can identify. A delegated step whose delivery mode this build does
    /// not recognise is not evidence of a background-safe run and is not evidence
    /// of a foreground one either, so it is counted separately and `note` stops
    /// being nil. That last part is the load-bearing half: `note == nil` is the
    /// signal every existing reader already uses for "nothing to disclose", so a
    /// new field alone would leave those readers believing an unproven run was
    /// clean.
    public var unproven: Int
    /// A step the backend escalated to the foreground without being asked. The
    /// machine was taken with none of the guards armed for it, because a post
    /// made by another process cannot be declared in advance by this one.
    public var unrequestedForeground: Int

    public init(declaredCertain: Int, declaredConditional: Int, measured: Int,
                totalSteps: Int, ranInForeground: Bool, requestIgnored: Bool = false,
                unproven: Int = 0, unrequestedForeground: Int = 0) {
        self.declaredCertain = declaredCertain
        self.declaredConditional = declaredConditional
        self.measured = measured
        self.totalSteps = totalSteps
        self.ranInForeground = ranInForeground
        self.requestIgnored = requestIgnored
        self.unproven = unproven
        self.unrequestedForeground = unrequestedForeground
    }

    public static func from(_ demand: ForegroundDemand, planes: [ActuationPlane?]) -> ForegroundReport {
        ForegroundReport(declaredCertain: demand.certainSteps,
                         declaredConditional: demand.conditionalSteps,
                         measured: planes.count(where: { $0 == .syntheticEvent }),
                         totalSteps: demand.totalSteps,
                         ranInForeground: demand.takesForeground,
                         requestIgnored: demand.requestWasInert,
                         unproven: planes.count(where: { $0 == .unknown }))
    }

    /// The same, from the finished step results, so the delegated facts that only
    /// exist per step — an unrequested escalation — reach the report.
    ///
    /// `ranInForeground` is taken from what actually travelled as well as from
    /// the up-front demand: a delegated batch predicts nothing, so a run that
    /// escalated must report the front even though its demand said otherwise.
    public static func from(_ demand: ForegroundDemand,
                            results: [StepResult]) -> ForegroundReport {
        let planes = results.map(\.plane)
        let escalations = results.count(where: { $0.unrequestedForeground == true })
        var report = from(demand, planes: planes)
        report.unrequestedForeground = escalations
        if report.measured > 0 { report.ranInForeground = true }
        return report
    }

    /// One sentence for a caller that reads prose rather than fields. Nil when
    /// nothing needed the front, because there is nothing to disclose.
    public var note: String? {
        // Said first, and it is why this property can no longer return nil on
        // the strength of the foreground counts alone. An escalation nobody
        // asked for is the strongest thing this report can say: the machine was
        // taken, and the guards that exist to make that visible were not armed,
        // because the post came from another process.
        if unrequestedForeground > 0 {
            return "\(unrequestedForeground) of \(totalSteps) step"
                 + "\(totalSteps == 1 ? "" : "s") was escalated to the foreground by the "
                 + "actuation backend without being asked, so the application was brought to "
                 + "the front with no warning shown. This run is not a background-safe one."
        }
        // A step nobody can account for is not a clean run. This is checked
        // before the counts below because a run can be unproven while measuring
        // zero synthetic steps, which is exactly the case that would otherwise
        // return nil and read as "nothing to disclose".
        if unproven > 0 {
            return "\(unproven) of \(totalSteps) step\(totalSteps == 1 ? "" : "s") "
                 + "travelled by a route this build could not identify, so whether this run "
                 + "needed the application in front could not be established. It should not "
                 + "be treated as background-safe."
        }
        guard measured > 0 || ranInForeground else {
            // One exception to "nothing to disclose": the caller asked for the
            // front and no step could have used it. Nothing was taken, which is
            // the good outcome, but the request is dead weight in whatever
            // produced it and will go on being so until somebody is told.
            return requestIgnored
                ? "This run asked for the foreground and no step in it could use one, so "
                + "the request was ignored and the run stayed in the background."
                : nil
        }
        guard measured > 0 else {
            return "This run brought the application to the front, so the result is not a "
                 + "background-safe one."
        }
        return "\(measured) of \(totalSteps) step\(totalSteps == 1 ? "" : "s") travelled as "
             + "synthetic events, which required the application to be frontmost. The result is "
             + "not a background-safe one, and this run cannot be repeated unattended."
    }
}
