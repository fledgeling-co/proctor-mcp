import Foundation
import Testing
@testable import ProctorCore

// The statement stops strobing.
//
// Reported from real use: "the overlay label flashing every second or two".
// The statement is raised per batch and lowered when the batch ends, and a model
// driving this Mac issues small batches several times a second, so it was doing
// exactly what it was told to. `Takeover.label` already refuses to word its line
// for the instant, on the reasoning that "a message that flickers is one people
// learn to ignore" — the panel carrying that line was flickering underneath it.

@Suite("Takeover dwell")
struct TakeoverDwellTests {

    @Test("a statement raised and immediately ended still stays up for the floor")
    func floorSurvivesAnInstantBatch() {
        var dwell = Takeover.Dwell(minimum: 3)
        #expect(dwell.show(now: 100) == true, "nothing was up, so this raises")
        dwell.end(now: 100.2)
        #expect(dwell.dueAt == 103, "the batch took 200ms and the floor is what decides")
        #expect(dwell.expire(now: 100.2) == false, "a timer firing early does not take it down")
        #expect(dwell.expire(now: 103) == true)
        #expect(!dwell.isVisible)
    }

    @Test("a request while it is up extends it and does not raise it again")
    func aSecondRequestExtendsRatherThanFlashes() {
        var dwell = Takeover.Dwell(minimum: 3)
        #expect(dwell.show(now: 0) == true)
        // The flash: a caller that raised here would drop and re-raise the panel.
        #expect(dwell.show(now: 1) == false, "one is already up, so this only moves the deadline")
        #expect(dwell.dueAt == 4)
        #expect(dwell.show(now: 2) == false)
        #expect(dwell.dueAt == 5)
    }

    @Test("batch after batch converges on one statement rather than a strobe")
    func aBusyRunRaisesOnce() {
        // The reported shape: a batch every 700ms for twenty seconds.
        var dwell = Takeover.Dwell(minimum: 3)
        var raises = 0
        var now = 0.0
        for _ in 0..<28 {
            if dwell.show(now: now) { raises += 1 }
            now += 0.2
            dwell.end(now: now)
            // The timer the agent had pending fires somewhere in the gap.
            _ = dwell.expire(now: now + 0.1)
            now += 0.5
        }
        #expect(raises == 1, "raised \\(raises) times across 28 batches — each one is a flash")
        #expect(dwell.isVisible, "and it is still up at the end, because the work is still going")
    }

    @Test("the deadline never moves backwards")
    func extendingIsMonotonic() {
        var dwell = Takeover.Dwell(minimum: 3)
        _ = dwell.show(now: 10)
        #expect(dwell.dueAt == 13)
        // A late-arriving request from a batch that started earlier must not
        // shorten a deadline a later one already bought.
        #expect(dwell.show(now: 9) == false)
        #expect(dwell.dueAt == 13, "an earlier clock reading cannot pull the deadline in")
        dwell.end(now: 9)
        #expect(dwell.dueAt == 13)
    }

    @Test("once it is down, the next batch raises it again")
    func itRaisesAgainAfterAQuietSpell() {
        var dwell = Takeover.Dwell(minimum: 3)
        _ = dwell.show(now: 0)
        dwell.end(now: 0.1)
        #expect(dwell.expire(now: 3) == true)
        #expect(dwell.show(now: 30) == true, "a run starting half a minute later is a new statement")
        #expect(dwell.dueAt == 33)
    }

    @Test("a stop takes it down rather than holding a claim that stopped being true")
    func cancelIsImmediate() {
        var dwell = Takeover.Dwell(minimum: 3)
        _ = dwell.show(now: 0)
        dwell.cancel()
        #expect(!dwell.isVisible)
        #expect(dwell.expire(now: 0) == false, "and a pending timer finds nothing to lower")
    }

    @Test("the floor matches the run panel's, so the two come down together")
    func theFloorMatchesTheRunPanel() {
        // A shorter floor leaves the panel explaining a statement that has gone;
        // a longer one outlives its own explanation.
        #expect(Takeover.Dwell.minimumSeconds == RunHUDState.quietLinger)
    }

    @Test("a zero floor is honoured rather than clamped to a default")
    func zeroFloorIsAllowed() {
        // An operator who wants the old behaviour back gets it exactly.
        var dwell = Takeover.Dwell(minimum: 0)
        #expect(dwell.show(now: 5) == true)
        dwell.end(now: 5)
        #expect(dwell.expire(now: 5) == true)
    }
}
