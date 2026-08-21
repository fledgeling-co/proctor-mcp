import Foundation

// What Proctor knows about a permission, and how it stops waiting to find out.
//
// MEASURED, 2026-08-15. The Screen Recording grant has no query API. The way to
// probe it is to ask ScreenCaptureKit for shareable content and read the failure,
// and the comment that used to sit over that call said it "either answers or
// throws, and the throw is the denial". Inside a swiftpm test host it did
// neither: the call parked in a continuation that never resumed, for 120s, while
// the same call from a plain script on the same machine at the same moment
// answered in 0.037s. So there is a third outcome — the platform will not answer
// — and a health check that models the world as two states hangs on it.
//
// This file is the third state and the rule for when to ask again. The rule is
// pure and clock-injected on purpose: it is the part worth testing, and it tests
// without a window server, a permission, or a platform call.

/// What a permission probe established.
///
/// `unconfirmed` is a fact about Proctor's knowledge, not about the permission —
/// which is why it is not spelled `unknown`. The grant may be perfectly in place;
/// what is known is that this process asked and was not answered.
public enum GrantState: String, Codable, Sendable, CaseIterable {
    case granted, denied, unconfirmed

    /// Whether this counts as *confirmed* granted. `unconfirmed` is deliberately
    /// false: every boolean consumer stays fail-closed, and the ones that put a
    /// remedy in front of a person read the state instead.
    public var isConfirmedGranted: Bool { self == .granted }
}

/// The bound, and the schedule for asking again after the platform ignores us.
public enum GrantProbe {

    /// The `AXIsProcessTrustedWithOptions` key that turns a silent read of the
    /// recorded answer into a consent dialog.
    ///
    /// PRO-0090. Two processes spell it — `AgentModel.requestAccessibilityPrompt`
    /// and the agent's `Contracts.swift` — and a misspelt key is not rejected: the
    /// dictionary is simply ignored and the call returns the recorded answer with
    /// no dialog drawn, which is indistinguishable from the person dismissing one.
    public static let trustedCheckOptionPrompt = "AXTrustedCheckOptionPrompt"


    /// How long to wait for the platform before answering `unconfirmed`.
    ///
    /// The healthy answer measured 0.037s, so this is ~40x the observed latency
    /// and will not fire on a merely slow machine. It is deliberately **shorter
    /// than the status window's 2.0s doctor poll**: a bound equal to the poll
    /// leaves no idle gap between one probe's deadline and the next poll landing.
    public static let bound: Double = 1.5

    /// How long to leave a wedged platform alone before probing again, by attempt.
    ///
    /// A permanently parked probe must not hold the slot forever. Strict
    /// single-flight — at most one probe for the life of the process — was the
    /// first design and the out-of-family gate killed it: it would leave the agent
    /// answering `unconfirmed` for the rest of its life after one slow probe,
    /// which is the same permanent-wrong-answer failure this whole item exists to
    /// avoid, wearing a different word.
    ///
    /// Backing off rather than retrying every call is what keeps that affordable.
    /// An abandoned probe is a suspended continuation rather than a thread, and
    /// this schedule leaves about twenty of them behind in an hour of a wedged
    /// machine instead of eighteen hundred.
    public static let backoff: [Double] = [2, 10, 60, 300]

    static func retryDelay(afterAttempts attempts: Int) -> Double {
        guard attempts > 0 else { return 0 }
        return backoff[min(attempts - 1, backoff.count - 1)]
    }
}

/// What a caller should do about the probe, right now.
public enum GrantProbeDecision: Equatable, Sendable {
    /// This process already has a definite answer. Use it; do not probe.
    case cached(GrantState)
    /// The slot is claimed by this caller. Run the probe, bounded, and report back
    /// with this token — it identifies *which* attempt answered, so a straggler
    /// from an earlier attempt cannot rearrange the bookkeeping of a later one.
    case start(token: Int)
    /// A probe is already running inside its bound. Wait up to this long for it,
    /// reading the cache as you go — do not start a second one.
    case join(remaining: Double)
    /// Nothing to wait for and nothing worth starting yet. Answer now.
    case unconfirmed

    /// The token, when this is a `.start`. Convenience for call sites and tests.
    public var startToken: Int? {
        if case .start(let token) = self { return token }
        return nil
    }
}

/// The state a bounded probe needs to keep, held **outside** any actor.
///
/// `Session` is a reentrant actor: its isolation drops at every `await`, so a
/// check-then-set living in its fields would be torn by the 2-second doctor poll
/// re-entering during the wait. Every transition here happens inside one
/// synchronous critical section with no `await` in it, and the late answer from an
/// abandoned probe is written through the same lock rather than touching actor
/// state from detached work.
///
/// What is cached, and for how long, is the load-bearing part:
///
/// - A **definite** answer — granted or denied — is cached for the life of the
///   process. That is not an optimisation laid over the platform, it is the
///   platform: macOS answers this from a TCC state it caches per process for the
///   process's life, which is why PRO-0028 deleted the "Re-check now" row and
///   replaced it with a restart.
/// - An **unconfirmed** answer is never cached. A timeout is a property of the
///   moment, not of the process. Caching one would freeze a transient into a
///   verdict for the life of the agent.
public final class GrantProbeKeeper: @unchecked Sendable {

    private let lock = NSLock()
    private let bound: Double
    private var definite: GrantState?
    private var startedAt: Double?
    private var attempts = 0
    private var nextRetryAt: Double = 0
    /// Which probe attempt the current slot belongs to. A probe abandoned at its
    /// bound is not cancelled — nothing can cancel it — so its answer may arrive
    /// while a *later* attempt is in flight. The token is what stops that
    /// straggler clearing the newer attempt's slot and letting a third probe
    /// start beside it.
    private var generation = 0

    public init(bound: Double = GrantProbe.bound) { self.bound = bound }

    /// Decide what to do, and **claim the slot** in the same breath when the answer
    /// is `.start`. Deciding and claiming cannot be two steps: two callers arriving
    /// together would both be told to start.
    public func claim(now: Double) -> GrantProbeDecision {
        lock.lock(); defer { lock.unlock() }
        if let definite { return .cached(definite) }
        if let startedAt {
            let elapsed = now - startedAt
            if elapsed < bound { return .join(remaining: bound - elapsed) }
            // Past its bound. Reap it here rather than waiting for whoever started
            // it to come back and do so: if that caller never does, the slot would
            // stay claimed and every later call would answer `unconfirmed` for the
            // life of the process — the permanent-wrong-answer failure again,
            // reached by a different road. Reaping here makes that unreachable and
            // the state self-healing.
            reapLocked(now: now)
            return .unconfirmed
        }
        guard now >= nextRetryAt else { return .unconfirmed }
        generation += 1
        self.startedAt = now
        return .start(token: generation)
    }

    /// The platform answered. Cache it for the life of the process and let the
    /// backoff go; this is true whether the answer arrived inside its bound or
    /// long after it was given up on.
    ///
    /// A definite answer is recorded whichever attempt produced it — on this
    /// platform it is a per-process constant, so a straggler's answer is exactly
    /// as valid as a fresh one. Only the in-flight bookkeeping is token-gated.
    public func record(_ state: GrantState, token: Int? = nil, now: Double) {
        guard state != .unconfirmed else { return }
        lock.lock(); defer { lock.unlock() }
        definite = state
        guard token == nil || token == generation else { return }
        startedAt = nil
        attempts = 0
        nextRetryAt = 0
    }

    /// The bound expired. Free the slot and push the next attempt out.
    ///
    /// Guarded on the slot still being claimed *by this attempt*, so that several
    /// waiters giving up on one probe count as one attempt, and a straggler giving
    /// up long after its slot was reaped does not touch a later attempt's.
    public func abandon(token: Int? = nil, now: Double) {
        lock.lock(); defer { lock.unlock() }
        guard startedAt != nil else { return }
        guard token == nil || token == generation else { return }
        reapLocked(now: now)
    }

    /// Free the slot and schedule the next attempt. Caller holds the lock.
    private func reapLocked(now: Double) {
        startedAt = nil
        attempts += 1
        nextRetryAt = now + GrantProbe.retryDelay(afterAttempts: attempts)
    }

    /// Whatever definite answer this process holds, if any.
    ///
    /// Read by a waiter at the instant its bound expires: an answer that landed
    /// while it was waiting is the answer, and returning `unconfirmed` beside a
    /// populated cache would be wrong in the one direction that matters.
    public func cachedDefinite() -> GrantState? {
        lock.lock(); defer { lock.unlock() }
        return definite
    }
}
