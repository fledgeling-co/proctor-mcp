import Testing
import Foundation
@testable import ProctorAgent
@testable import ProctorCore

// PRO-0029. The half of the drift guard that has to live in the agent target.
//
// `ContentionMonitor` is in `ProctorAgent`, so `ProctorCoreTests` cannot see it and
// the yield pair's drift assertions live here instead. Same rule as the Core half:
// resolve through the catalogue, then ask the function the agent actually calls,
// over the same dictionary. Two answers that must agree, rather than two strings
// that were both typed by the same hand.

@Suite("PRO-0029 yield switches cannot drift")
struct SwitchYieldDriftTests {

    @Test("PROCTOR_YIELD resolves exactly as ContentionMonitor reads it")
    func yieldAgrees() {
        for raw in Self.probes {
            let env = raw.map { ["PROCTOR_YIELD": $0] } ?? [:]
            #expect(SwitchResolver.isOn(raw, for: SwitchCatalogue.yield)
                    == ContentionMonitor.enabled(in: env),
                    "PROCTOR_YIELD on \(raw ?? "<unset>")")
        }
    }

    @Test("PROCTOR_YIELD_INPUT resolves exactly as ContentionMonitor reads it")
    func yieldInputAgrees() {
        for raw in Self.probes {
            let env = raw.map { ["PROCTOR_YIELD_INPUT": $0] } ?? [:]
            #expect(SwitchResolver.isOn(raw, for: SwitchCatalogue.yieldInput)
                    == ContentionMonitor.inputObserved(in: env),
                    "PROCTOR_YIELD_INPUT on \(raw ?? "<unset>")")
        }
    }

    /// A declined capability must be invisible to the reader, not merely false —
    /// `inputObserved` treats "unset" and "0" alike, and the effective environment
    /// removes the key rather than writing an off-value for exactly that reason.
    @Test("A saved off removes PROCTOR_YIELD_INPUT from what the monitor reads")
    func declinedYieldInputIsAbsent() {
        let env = SwitchResolver.effectiveEnvironment(
            processEnvironment: ["PROCTOR_YIELD_INPUT": "1"],
            saved: ["PROCTOR_YIELD_INPUT": "0"])
        #expect(env["PROCTOR_YIELD_INPUT"] == nil)
        #expect(!ContentionMonitor.inputObserved(in: env))
    }

    /// The other direction: a drawing switch reads unset as ON, so saving it off
    /// has to write an off-value. Asserted against the real reader.
    @Test("A saved off leaves PROCTOR_YIELD present and off for the monitor")
    func declinedYieldIsWritten() {
        let env = SwitchResolver.effectiveEnvironment(processEnvironment: [:],
                                                      saved: ["PROCTOR_YIELD": "0"])
        #expect(env["PROCTOR_YIELD"] != nil)
        #expect(!ContentionMonitor.enabled(in: env))
    }

    static let probes: [String?] = [nil, "", " ", "0", "off", "false", "no",
                                    "1", "true", "on", "yes", "nonsense"]
}

// MARK: - The environment holder

// **Nothing here mutates `ProctorEnvironment`, and that is a deliberate
// constraint rather than an oversight.**
//
// The first draft of this suite called `install` and `reset`. It went green
// twice and red once in a full run: the holder is a process-wide global, 1286
// tests run concurrently, and `ToolProbe`'s default argument, `CursorOverlay`
// and `SessionHUD` all read `ProctorEnvironment.current` while these were
// rewriting it. That is the leak the repo already knows about — a harness that
// does not inject a singleton drives production state and carries it into other
// suites — and PRO-0053 is the standing lesson that a test which reddens at
// random costs more than the coverage it buys.
//
// Nor is there a test asserting the holder EQUALS the process environment when
// nothing has been installed. That looks read-only and is not: the holder is a
// snapshot taken when the static initialises, `ProcessInfo.processInfo.environment`
// is read live, and `NativePlaneLaneTests` calls `setenv` mid-run — so the two
// legitimately differ for the length of that test. The snapshot semantics are
// wanted in production (the agent installs once, at start, and nothing calls
// `setenv` in it); they simply cannot be asserted from inside a concurrent suite.
//
// So the holder's own wiring is proven where it can be proven without a shared
// mutable: `SwitchResolver.effectiveEnvironment` is tested directly above and in
// `ProctorCoreTests`, and the one line in `main.swift` that installs it was
// verified end to end against a running agent — `proctor_doctor` reported
// `PROCTOR_TAKEOVER_INPUT` as off/saved with `PROCTOR_TAKEOVER_INPUT=1` in the
// agent's own environment, which no unit test can establish anyway.

@Suite("PRO-0029 effective environment holder")
struct ProctorEnvironmentTests {

    /// The distinction conflating the two dictionaries would destroy, asserted on
    /// the pure function rather than on the holder.
    ///
    /// Resolving against the EFFECTIVE environment reports a saved preference as
    /// having come from the environment, and therefore as locked — the exact
    /// misreport this feature exists to prevent. That was a real bug in the first
    /// draft, and this is what would have caught it.
    @Test("Resolving against the effective environment would misreport source and lock")
    func inheritedAndEffectiveAreNotInterchangeable() {
        let saved = ["PROCTOR_CURSOR": "0"]
        let inherited: [String: String] = ["PATH": "/bin"]
        let effective = SwitchResolver.effectiveEnvironment(processEnvironment: inherited,
                                                            saved: saved)

        let right = SwitchResolver.resolve(SwitchCatalogue.cursor,
                                           environment: inherited, saved: saved)
        #expect(right.source == .saved)
        #expect(!right.locked)

        // The mistake, spelled out so it cannot be reintroduced quietly.
        let wrong = SwitchResolver.resolve(SwitchCatalogue.cursor,
                                           environment: effective, saved: saved)
        #expect(wrong.source == .environment)
        #expect(wrong.locked)
    }
}
