import Foundation
import Testing
@testable import ProctorCore

// PRO-0069. The run panel's per-phase contract, judged without a panel.

@Suite("Run HUD surface")
struct RunHUDSurfaceTests {

    @Test("A1 · all seven phases resolve to a symbol, and each is distinct")
    func symbolsPerPhase() {
        var seen = Set<String>()
        for phase in RunHUDPhase.allCases {
            let symbol = RunHUDSurface.symbol(for: phase)
            #expect(!symbol.isEmpty, "\(phase.rawValue) has no symbol")
            #expect(seen.insert(symbol).inserted,
                    "\(phase.rawValue) reuses the symbol \(symbol) — the phase would read as another")
        }
        #expect(RunHUDPhase.allCases.count == 7)
    }

    @Test("A2 · idle offers no controls, and every phase with a run offers Stop")
    func controlsPerPhase() {
        #expect(RunHUDSurface.controls(for: .idle).isEmpty,
                "a control that does nothing is worse than an absent one here")
        for phase in [RunHUDPhase.travelling, .acting, .blocked, .paused] {
            #expect(RunHUDSurface.controls(for: phase).contains(.stop),
                    "\(phase.rawValue) has a run and no Stop")
        }
        // Paused offers Resume rather than Pause: the two never both appear,
        // because a panel showing both is a panel asking which one is live.
        #expect(RunHUDSurface.controls(for: .paused).contains(.resume))
        #expect(!RunHUDSurface.controls(for: .paused).contains(.pause))
    }

    @Test("A3 · the chip reports what the step said, and infers nothing")
    func chipIsReported() {
        let chip = RunHUDSurface.chip(plane: "accessibility", route: "selectedText", machine: "host")
        #expect(chip?.fields.count == 3)
        #expect(chip?.fields.first?.1 == "accessibility")
        // Nothing to report is no chip, rather than a chip asserting provenance
        // for a step that never happened.
        #expect(RunHUDSurface.chip(plane: nil, route: nil, machine: nil) == nil)
        // A plane with no route still reports the plane.
        #expect(RunHUDSurface.chip(plane: "syntheticEvent", route: nil, machine: nil)?.fields.count == 1)
    }

    @Test("A3 · a run on an unrecognised delivery mode is never called background-safe")
    func unknownIsNotSafe() {
        #expect(RunHUDSurface.isBackgroundSafe(plane: "accessibility"))
        #expect(RunHUDSurface.isBackgroundSafe(plane: "routedEvent"),
                "a routed event is delivered to one process, not the shared stream")
        #expect(!RunHUDSurface.isBackgroundSafe(plane: "syntheticEvent"))
        // The two that matter: `unknown` means this build cannot say how the
        // machine was driven, and a plane from a newer build is not assumed.
        #expect(!RunHUDSurface.isBackgroundSafe(plane: "unknown"))
        #expect(!RunHUDSurface.isBackgroundSafe(plane: "somethingNewerThanThisBuild"))
        #expect(!RunHUDSurface.isBackgroundSafe(plane: nil))
    }

    @Test("identifiers are unique across every phase and control")
    func identifiers() {
        var all = RunHUDPhase.allCases.map(RunHUDSurface.ID.panel)
        all += RunHUDControl.allCases.map(RunHUDSurface.ID.control)
        all += [RunHUDSurface.ID.chip, RunHUDSurface.ID.step]
        #expect(Set(all).count == all.count)
        for id in all { #expect(id.hasPrefix("proctor.hud.")) }
    }

    @Test("a phase that offers Stop is exactly a phase with a stoppable run")
    func stoppableAgrees() {
        for phase in RunHUDPhase.allCases {
            #expect(RunHUDSurface.hasStoppableRun(phase)
                    == RunHUDSurface.controls(for: phase).contains(.stop))
        }
        #expect(!RunHUDSurface.hasStoppableRun(.idle))
        #expect(!RunHUDSurface.hasStoppableRun(.finished))
    }
}

// PRO-0075. `RunHUDSurface.Chip`'s equality, pinned field by field.
//
// Found by the mutation assay over ProctorCore: `a.fields.count == b.fields.count`
// mutated to `!=` and survived, which means nothing had ever compared two chips
// with different field counts. It is a hand-written `==` over an array of tuples
// — Swift cannot synthesise one, because a tuple is not Equatable — so it is
// exactly the shape that goes wrong quietly, and the second one this wave found
// after `TUISurface.Model`.
//
// A chip carries the provenance the run panel shows: which plane performed the
// step and on what. Two chips that say different things comparing equal is a
// panel that keeps drawing the previous step's provenance for the current one.

@Suite("Run HUD chip equality")
struct RunHUDChipEqualityTests {

    @Test("two chips built the same way are equal")
    func sameFieldsAreEqual() {
        let a = RunHUDSurface.Chip([("plane", "synthetic"), ("on", "host")])
        let b = RunHUDSurface.Chip([("plane", "synthetic"), ("on", "host")])
        #expect(a == b)
    }

    @Test("a different number of fields makes two chips unequal")
    func fieldCountParticipates() {
        // The mutant that survived: with `count !=` the two below compare equal
        // and a chip that lost a field reads as the chip that has it.
        let full = RunHUDSurface.Chip([("plane", "synthetic"), ("on", "host")])
        let short = RunHUDSurface.Chip([("plane", "synthetic")])
        #expect(full != short)
        #expect(short != full, "and the comparison is symmetric")
    }

    @Test("a different field name, and a different field value, each make two chips unequal")
    func namesAndValuesBothParticipate() {
        let base = RunHUDSurface.Chip([("plane", "synthetic"), ("on", "host")])
        #expect(base != RunHUDSurface.Chip([("plane", "synthetic"), ("via", "host")]),
                "the field's name is compared")
        #expect(base != RunHUDSurface.Chip([("plane", "delegated"), ("on", "host")]),
                "the field's value is compared")
        #expect(base != RunHUDSurface.Chip([("on", "host"), ("plane", "synthetic")]),
                "and order is part of what a chip says, because it is what a person reads")
    }

    @Test("an empty chip equals an empty chip and nothing else")
    func emptyIsItsOwnValue() {
        let empty = RunHUDSurface.Chip([])
        let alsoEmpty = RunHUDSurface.Chip([])
        #expect(empty == alsoEmpty)
        #expect(empty != RunHUDSurface.Chip([("plane", "synthetic")]))
    }
}
