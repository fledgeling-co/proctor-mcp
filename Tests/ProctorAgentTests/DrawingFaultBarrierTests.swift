import Foundation
import Testing
@testable import ProctorAgent
import ProctorCatch
import ProctorCore

// The barrier that keeps a drawing fault from killing the agent.
//
// The panel's own draw needs a display and cannot be exercised here. The barrier
// can, and it is the part that carries the guarantee: AppKit raises Objective-C
// exceptions, Swift cannot catch them, and an uncaught one aborts the process —
// taking the agent, the run in flight and the MCP server with it.

@Suite("Drawing fault barrier")
struct DrawingFaultBarrierTests {

    @Test("a body that completes returns nothing, and its work still happened")
    func completingBodyIsTransparent() {
        var ran = false
        let fault = ProctorCatchNSException { ran = true }
        #expect(fault == nil)
        #expect(ran)
    }

    @Test("an exception raised by Foundation itself is caught, not fatal")
    func aRealFrameworkExceptionIsCaught() {
        // Raised by Foundation rather than constructed here, because a barrier
        // tested only against exceptions the test itself threw proves less than
        // it appears to. The abort this exists for came out of CoreText.
        let fault = ProctorCatchNSException {
            _ = NSArray(array: ["only one"]).object(at: 7)
        }
        #expect(fault != nil)
        #expect(fault?.contains("NSRangeException") == true, "\(fault ?? "-")")
    }

    @Test("the fault carries the exception's name and reason, so the next one is diagnosable")
    func faultNamesItself() {
        let fault = ProctorCatchNSException {
            NSException(name: .invalidArgumentException,
                        reason: "attempt to insert nil object from objects[2]",
                        userInfo: nil).raise()
        }
        guard let fault else { Issue.record("no fault reported"); return }
        #expect(fault.contains("NSInvalidArgumentException"))
        #expect(fault.contains("attempt to insert nil object from objects[2]"))
        // The first occurrence left only a stack in a crash report, which is why
        // the nil behind it is still unidentified. A second one says its own name.
        #expect(fault.split(separator: "\n").count > 1, "no call stack in the fault")
    }

    @Test("a caught fault does not poison the next call")
    func barrierRecovers() {
        _ = ProctorCatchNSException {
            NSException(name: .genericException, reason: "first", userInfo: nil).raise()
        }
        var ran = false
        #expect(ProctorCatchNSException { ran = true } == nil)
        #expect(ran)
    }

    @Test("a reported drawing fault leaves doctor able to say the panel is gone and why")
    func availabilityCarriesTheReason() {
        // The record the draw pass writes on a fault. `proctor_doctor` reads this
        // same value, so an absent panel is an explained absence rather than a
        // panel that quietly stopped appearing.
        let before = RunHUDAvailability.shared.status
        RunHUDAvailability.shared.record(
            built: false, reason: "NSInvalidArgumentException: attempt to insert nil object")
        let after = RunHUDAvailability.shared.status
        #expect(after.available == false)
        #expect(after.reason?.contains("NSInvalidArgumentException") == true)
        RunHUDAvailability.shared.record(built: before.available, reason: before.reason)
    }
}
