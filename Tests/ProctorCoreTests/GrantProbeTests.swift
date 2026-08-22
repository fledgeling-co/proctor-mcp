import Testing
import Foundation
@testable import ProctorCore

// PRO-0041 — what Proctor does when a permission probe will not answer.
//
// The keeper is the whole rule: what is cached, for how long, when a second
// caller is allowed to start a probe, and what a waiter does when its bound
// expires. It is pure and clock-injected, so all of that tests here without a
// permission, a platform call, or a window server.
@Suite("Grant probe keeper")
struct GrantProbeTests {

    // MARK: A6 — only definite answers are cached, for the life of the process

    @Test("a definite answer is cached for the life of the process")
    func definiteAnswersAreCached() {
        for answer in [GrantState.granted, .denied] {
            let keeper = GrantProbeKeeper(bound: 1.5)
            #expect(keeper.claim(now: 0).startToken != nil)
            keeper.record(answer, now: 0.1)

            // Not a re-probe, now or in an hour: macOS answers this from a TCC
            // state it caches per process for the process's life, so a definite
            // answer cannot change without a relaunch.
            #expect(keeper.claim(now: 0.2) == .cached(answer))
            #expect(keeper.claim(now: 3_600) == .cached(answer))
        }
    }

    @Test("an unconfirmed answer is never cached")
    func unconfirmedIsNeverCached() {
        let keeper = GrantProbeKeeper(bound: 1.5)
        #expect(keeper.claim(now: 0).startToken != nil)
        keeper.abandon(now: 1.5)

        // A timeout is a property of the moment, not of the process. Caching one
        // would freeze a transient into a verdict and leave the agent answering
        // the same non-answer for the rest of its life — the failure this whole
        // item exists to avoid, wearing a different word.
        #expect(keeper.cachedDefinite() == nil)
        #expect(keeper.claim(now: 1_000).startToken != nil)
    }

    @Test("recording an unconfirmed answer does nothing")
    func recordingUnconfirmedIsIgnored() {
        let keeper = GrantProbeKeeper(bound: 1.5)
        keeper.record(.unconfirmed, now: 0)
        #expect(keeper.cachedDefinite() == nil)
    }

    // MARK: A7 — callers coalesce, and a wedged probe still recovers

    @Test("a caller arriving inside the bound joins rather than starting a second probe")
    func callersInsideTheBoundJoin() {
        let keeper = GrantProbeKeeper(bound: 1.5)
        #expect(keeper.claim(now: 10).startToken != nil)
        #expect(keeper.claim(now: 10.5) == .join(remaining: 1.0))
        #expect(keeper.claim(now: 11.0) == .join(remaining: 0.5))
    }

    @Test("a caller arriving past the bound answers now and starts nothing")
    func callersPastTheBoundDoNotStartASecondProbe() {
        let keeper = GrantProbeKeeper(bound: 1.5)
        #expect(keeper.claim(now: 10).startToken != nil)
        // The first waiter has not given up yet, but this caller is already past
        // the bound. Starting a second probe against a platform that is visibly
        // not answering buys nothing and leaves a second parked task behind.
        #expect(keeper.claim(now: 11.6) == .unconfirmed)
    }

    // The out-of-family gate's largest finding, and a regression test for the
    // design it killed. Strict single-flight — at most one probe for the life of
    // the process — meant a permanently parked probe held the slot forever, so
    // the agent would answer `unconfirmed` for the rest of its life after one
    // slow probe. That is the same permanent-wrong-answer failure as caching the
    // timeout.
    @Test("a wedged probe does not hold the slot forever")
    func aWedgedProbeIsRetried() {
        let keeper = GrantProbeKeeper(bound: 1.5)
        #expect(keeper.claim(now: 0).startToken != nil)
        keeper.abandon(now: 1.5)

        // Inside the backoff, no new probe.
        #expect(keeper.claim(now: 2.0) == .unconfirmed)
        // Past it, the platform gets asked again.
        #expect(keeper.claim(now: 1.5 + GrantProbe.backoff[0]).startToken != nil)
    }

    @Test("the retry backs off, and is capped")
    func retriesBackOff() throws {
        let keeper = GrantProbeKeeper(bound: 1.5)
        var now = 0.0
        for expected in GrantProbe.backoff {
            #expect(keeper.claim(now: now).startToken != nil)
            keeper.abandon(now: now)
            // Nothing starts a hair before the delay is up...
            #expect(keeper.claim(now: now + expected - 0.001) == .unconfirmed)
            // ...and the next loop turn proves one starts exactly when it is.
            now += expected
        }
        // Capped rather than growing without bound: the agent keeps checking back
        // on a wedged platform for as long as it lives, just not busily.
        // PRO-0100, DEF-140. `backoff` is production data; an empty one would
        // abort the runner rather than fail the cap assertion below.
        let cap = try #require(GrantProbe.backoff.last, "GrantProbe.backoff is empty")
        #expect(keeper.claim(now: now).startToken != nil)
        keeper.abandon(now: now)
        #expect(keeper.claim(now: now + cap - 0.001) == .unconfirmed)
        #expect(keeper.claim(now: now + cap).startToken != nil)
    }

    @Test("several waiters giving up on one probe count as one attempt")
    func abandonIsIdempotentPerProbe() {
        let keeper = GrantProbeKeeper(bound: 1.5)
        #expect(keeper.claim(now: 0).startToken != nil)
        keeper.abandon(now: 1.5)
        keeper.abandon(now: 1.5)
        keeper.abandon(now: 1.5)
        // One attempt, so the first backoff step — not the third.
        #expect(keeper.claim(now: 1.5 + GrantProbe.backoff[0]).startToken != nil)
    }

    @Test("a definite answer resets the backoff")
    func aDefiniteAnswerResetsTheBackoff() {
        let keeper = GrantProbeKeeper(bound: 1.5)
        #expect(keeper.claim(now: 0).startToken != nil)
        keeper.abandon(now: 1.5)
        #expect(keeper.claim(now: 100).startToken != nil)
        keeper.record(.granted, now: 100.2)
        #expect(keeper.claim(now: 100.3) == .cached(.granted))
    }

    // MARK: The slot cannot get stuck, and a straggler cannot rearrange it

    // The completeness critic's finding. `claim` used to return `.unconfirmed` for
    // a past-bound probe and leave the slot claimed, trusting whoever started it
    // to come back and free it. If that caller never did, the slot stayed claimed
    // and every later call answered `unconfirmed` for the life of the process —
    // the permanent-wrong-answer failure reached by a third road. Reaping in
    // `claim` makes the state self-healing.
    @Test("a slot nobody frees is reaped by the next caller")
    func aStuckSlotIsReaped() {
        let keeper = GrantProbeKeeper(bound: 1.5)
        #expect(keeper.claim(now: 0).startToken != nil)
        // Nobody ever calls abandon. A caller past the bound frees it in passing.
        #expect(keeper.claim(now: 2.0) == .unconfirmed)
        // ...and the backoff started from that moment, so the platform is asked
        // again rather than the process being stuck answering `unconfirmed`.
        #expect(keeper.claim(now: 2.0 + GrantProbe.backoff[0]).startToken != nil)
    }

    // A probe abandoned at its bound is not cancelled — nothing can cancel it —
    // so its answer can arrive while a *later* attempt is in flight. Without the
    // token, that straggler cleared the newer attempt's slot, which let a third
    // probe start beside a second one that was still running.
    @Test("a straggler does not free a later attempt's slot")
    func aStragglerDoesNotDisturbALaterAttempt() {
        let keeper = GrantProbeKeeper(bound: 1.5)
        let first = keeper.claim(now: 0).startToken
        #expect(first != nil)
        keeper.abandon(token: first, now: 1.5)

        let second = keeper.claim(now: 10).startToken
        #expect(second != nil)
        #expect(first != second)

        // The first probe finally answers, long after it was given up on.
        keeper.record(.granted, token: first, now: 10.2)
        // Its answer is kept — a definite answer is a per-process constant, so a
        // straggler's is as valid as anyone's.
        #expect(keeper.cachedDefinite() == .granted)
    }

    @Test("a straggler's abandon does not count against a later attempt")
    func aStraggerAbandonDoesNotCount() {
        let keeper = GrantProbeKeeper(bound: 1.5)
        let first = keeper.claim(now: 0).startToken
        keeper.abandon(token: first, now: 1.5)
        let second = keeper.claim(now: 10).startToken
        #expect(second != nil)

        // The first attempt's waiter gives up again, late. It must not reap the
        // second attempt's slot.
        keeper.abandon(token: first, now: 10.1)
        // The second probe is still the one in flight, so a caller inside its
        // bound still joins it rather than starting a third.
        let decision = keeper.claim(now: 10.2)
        #expect(decision.startToken == nil)
        if case .join(let remaining) = decision {
            #expect(abs(remaining - 1.3) < 0.0001)
        } else {
            Issue.record("expected a join, got \(decision)")
        }
    }

    // MARK: A8 — a late answer is not lost

    @Test("an answer arriving after the bound is picked up by the next call")
    func aLateAnswerFillsTheCache() {
        let keeper = GrantProbeKeeper(bound: 1.5)
        #expect(keeper.claim(now: 0).startToken != nil)
        keeper.abandon(now: 1.5)
        #expect(keeper.cachedDefinite() == nil)

        // The abandoned probe finally comes back. It is not stale: on this
        // platform a definite answer is a per-process constant, so one arriving
        // late is exactly as valid as one arriving on time.
        keeper.record(.granted, now: 9.0)
        #expect(keeper.cachedDefinite() == .granted)
        #expect(keeper.claim(now: 9.1) == .cached(.granted))
    }

    @Test("a waiter can read an answer that landed while it was waiting")
    func aWaiterReadsWhatLandedUnderIt() {
        let keeper = GrantProbeKeeper(bound: 1.5)
        #expect(keeper.claim(now: 0).startToken != nil)
        keeper.record(.denied, now: 1.4)
        // The waiter times out a hair later and must return the answer rather
        // than `unconfirmed` beside a populated cache.
        #expect(keeper.cachedDefinite() == .denied)
    }

    // MARK: A9 — the state survives concurrent access

    // `Session` is a reentrant actor whose isolation drops at every await, which
    // is why this state lives outside it behind a lock. Hammering it from many
    // tasks is the cheapest available witness that claiming is one critical
    // section: exactly one caller may be told to start.
    @Test("only one concurrent caller is told to start")
    func claimingIsAtomic() async {
        let keeper = GrantProbeKeeper(bound: 1.5)
        let starts = await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<200 {
                group.addTask { keeper.claim(now: 0).startToken != nil }
            }
            var count = 0
            for await didStart in group where didStart { count += 1 }
            return count
        }
        #expect(starts == 1)
    }

    // MARK: The state itself

    @Test("only a granted state counts as confirmed")
    func onlyGrantedIsConfirmed() {
        #expect(GrantState.granted.isConfirmedGranted)
        #expect(!GrantState.denied.isConfirmedGranted)
        // The fail-closed bit. An unconfirmed grant reads exactly as a denied one
        // does through the boolean, which is what keeps every consumer that only
        // reads the boolean as conservative as it always was.
        #expect(!GrantState.unconfirmed.isConfirmedGranted)
    }

    @Test("the bound is shorter than the window's doctor poll")
    func theBoundFitsInsideThePoll() {
        // The status window polls doctor every 2.0s for the app's whole life. A
        // bound equal to the poll leaves no idle gap between one probe's deadline
        // and the next poll landing on it.
        #expect(GrantProbe.bound < 2.0)
        // And comfortably above the 0.037s a healthy answer measured at, so this
        // does not fire on a merely slow machine.
        #expect(GrantProbe.bound > 1.0)
    }
}
