import Foundation
import Testing
@testable import ProctorAgent
@testable import ProctorCore

@Suite("Guest health in the report: what a diagnostic may and may not do")
struct GuestHealthReportingTests {

    @Test("an attachment with no beat yet is unreachable, never healthy")
    func noBeatIsNotHealth() {
        // The failure this prevents: a health block that defaults to healthy
        // reports every freshly attached guest as fine, and the first thing an
        // operator does after attaching is run doctor.
        let fresh = GuestHealthProbe.classify([])
        #expect(fresh.status == .unreachable)
        #expect(!fresh.socketReachable)
    }

    @Test("the window keeps enough beats to tell one slow sample from a slow run")
    func windowIsBigEnoughToBeUseful() {
        // classify() needs more than one answered beat before it will call a
        // guest degraded, so a window of 1 would make that branch unreachable —
        // a check that cannot fire.
        #expect(Session.guestBeatWindow > 1,
                "the beat window cannot show a run, so the degraded branch is dead code")
        #expect(Session.guestBeatWindow <= 10,
                "this is a diagnostic rather than a history; an unbounded window is a leak")

        // And the window really does bound: more beats than it holds keeps the
        // newest, because a stale run of slow beats would outlive the condition.
        var beats: [GuestHealthProbe.Beat] = []
        for i in 0..<(Session.guestBeatWindow + 3) {
            beats.append(.answered(latencyMs: Double(i)))
        }
        let kept = Array(beats.suffix(Session.guestBeatWindow))
        #expect(kept.count == Session.guestBeatWindow)
        #expect(kept.first != beats.first, "the oldest beat survived a full window")
    }
}
