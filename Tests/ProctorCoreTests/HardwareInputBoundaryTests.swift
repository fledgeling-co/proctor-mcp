import Foundation
import Testing
@testable import ProctorCore

// PRO-0111 / DEF-151 / REQ-161: Hardware Input Event Source Boundary Characterization.
//
// Formally verifies the boundary between kernel IOHIDEvent (hardware input, sourcePid == 0)
// and synthetic user-space CGEvent posts (sourcePid > 0), tagged automation events,
// and the post-synthetic grace window.
@Suite("PRO-0111 · Hardware Input Event Source Boundary")
struct HardwareInputBoundaryTests {

    private static let ourPid: Int64 = 4200
    private static let otherPid: Int64 = 9911
    private static let delegatedPid: Int64 = 5500

    // MARK: - PersonInput Truth Table Matrix (CASE-0633)

    @Test("PersonInput accepts kernel/hardware events (sourcePid == 0) and rejects userspace synthetic posts")
    func personInputSourcePidDiscrimination() {
        // Hardware event (PID 0, untagged, outside grace) -> Person
        #expect(PersonInput.isAPerson(sourcePid: 0, userData: 0, sinceSyntheticPost: nil))

        // Proctor tagged event (PID 0, tagged) -> NOT Person
        #expect(!PersonInput.isAPerson(sourcePid: 0, userData: ProctorEventTag.value, sinceSyntheticPost: nil))

        // Synthetic userspace event from our process -> NOT Person
        #expect(!PersonInput.isAPerson(sourcePid: Self.ourPid, userData: 0, sinceSyntheticPost: nil))

        // Synthetic userspace event from other process -> NOT Person
        #expect(!PersonInput.isAPerson(sourcePid: Self.otherPid, userData: 0, sinceSyntheticPost: nil))

        // Nil PID (no event source) -> NOT Person
        #expect(!PersonInput.isAPerson(sourcePid: nil, userData: nil, sinceSyntheticPost: nil))
    }

    // MARK: - Grace Period Suppression (CASE-0634)

    @Test("PersonInput suppresses events within the post-synthetic grace window and admits events after")
    func personInputGracePeriodBoundary() {
        let grace = PersonInput.graceSeconds // 0.25s

        // Event arriving immediately after synthetic post (e.g. 0.05s) -> Suppressed
        #expect(!PersonInput.isAPerson(sourcePid: 0, userData: 0, sinceSyntheticPost: 0.05, grace: grace))

        // Event arriving just before grace deadline (e.g. 0.24s) -> Suppressed
        #expect(!PersonInput.isAPerson(sourcePid: 0, userData: 0, sinceSyntheticPost: 0.24, grace: grace))

        // Event arriving exactly at or after grace deadline (e.g. 0.25s / 0.30s) -> Admitted
        #expect(PersonInput.isAPerson(sourcePid: 0, userData: 0, sinceSyntheticPost: 0.25, grace: grace))
        #expect(PersonInput.isAPerson(sourcePid: 0, userData: 0, sinceSyntheticPost: 0.30, grace: grace))
    }

    // MARK: - InputBlock.isOurs Combinatorial Characterization (CASE-0635)

    @Test("InputBlock.isOurs correctly classifies automation, delegated, and human events")
    func inputBlockClassificationMatrix() {
        let delegated: Set<Int64> = [Self.delegatedPid]

        // Our own process PID is ours
        #expect(InputBlock.isOurs(sourcePid: Self.ourPid, userData: 0, ourPid: Self.ourPid, delegated: delegated))

        // Tagged event from pid 0 is ours
        #expect(InputBlock.isOurs(sourcePid: 0, userData: ProctorEventTag.value, ourPid: Self.ourPid, delegated: delegated))

        // Delegated process PID is ours
        #expect(InputBlock.isOurs(sourcePid: Self.delegatedPid, userData: 0, ourPid: Self.ourPid, delegated: delegated))

        // Hardware untagged event (PID 0) is NEVER ours
        #expect(!InputBlock.isOurs(sourcePid: 0, userData: 0, ourPid: Self.ourPid, delegated: delegated))

        // Non-delegated external process is NOT ours
        #expect(!InputBlock.isOurs(sourcePid: Self.otherPid, userData: 0, ourPid: Self.ourPid, delegated: delegated))
    }
}
