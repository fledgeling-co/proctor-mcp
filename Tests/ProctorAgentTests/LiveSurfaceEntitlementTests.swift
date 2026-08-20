import Testing
@testable import ProctorAgent

// PRO-0075. The suite does not draw on the machine it runs on.
//
// Reported from real use: the full-screen statement read
// `Proctor is driving "Fake"`. That is `FakeAX`'s app handle. It reached the
// screen because `Session.takeover` defaults to `LiveTakeover` and most of the
// wiring suites build a session without replacing it, so a step this package
// considers synthetic called through to the real overlay. Measured while one
// suite ran: two windows at level 1000 covering the whole of both displays,
// owned by `swiftpm-testing-helper`.
//
// These are process-level facts rather than values, which is unusual here and is
// the point: the defect was a true statement about a value (`PROCTOR_TAKEOVER`
// is on) combined with a false assumption about the process reading it. Only a
// check that asks the running process can tell the two apart.
//
// Nothing here calls `AgentProcess.claimIsAgent()`. The claim has no counterpart
// that gives it up, so making it inside a test would arm every live surface for
// the remainder of the run and reintroduce exactly the defect being guarded.
// `OverlaySwitch.mayRaise` carries the entitled case, in Core, as arithmetic.
@Suite("Live surfaces stay off outside the agent")
struct LiveSurfaceEntitlementTests {

    @Test("this process has not claimed to be the agent")
    func theSuiteIsNotTheAgent() {
        #expect(!AgentProcess.isAgent)
    }

    @Test("the full-screen statement cannot be raised from here")
    func theStatementStaysDown() {
        #expect(!TakeoverOverlay.isEnabled)
    }

    @Test("the drawn pointer cannot be raised from here")
    func thePointerStaysDown() {
        #expect(!CursorOverlay.isEnabled)
    }

    @Test("the input block cannot be armed from here")
    func theBlockStaysOff() {
        // Opt-in already, so this passed before the entitlement term existed.
        // It is here so all three surfaces are asserted together rather than
        // two being guarded and the third being safe by luck.
        #expect(!InputBlocker.isEnabled)
    }
}
