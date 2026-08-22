import Foundation
import Testing
import ProctorCore
@testable import ProctorAgent

// PRO-0082 — two of the six child-work items PRO-0036 recorded, tested where the
// claim is actually made.
//
// Both are about the health report rather than about a window: PRO-0036 corrected
// the Shortcuts CLI at the status window by partitioning the grants list on
// arrival, which left every other reader of the same report drawing a program on
// a disk as a decision macOS holds about Proctor. A correction applied by one
// reader is not a corrected report.

@Suite("The health report's permissions list, and the grant it freezes")
struct StatusWindowDebtWiringTests {

    /// A session whose two machine-dependent inputs are declared rather than
    /// inherited. `shortcutsPresent` is the interesting one: the old defect fired
    /// **only** when the CLI was missing, and every Mac in this fleet has it.
    private func session(shortcutsPresent: Bool) -> Session {
        Session(ax: FakeAX(bundleId: "com.example.app"), capture: FakeCapture(),
                screenRecordingProbe: .fake(.granted),
                accessibilityProbe: { true },
                shortcutsProbe: { shortcutsPresent })
    }

    // MARK: - A1. The permissions list contains only permissions

    @Test("no report files the Shortcuts CLI under grants, on a Mac that lacks it")
    func theMissingShortcutsCLIIsNotAGrant() async {
        // The case the old code reached and this one does not: `if
        // !shortcutsAvailable { grants.append(…) }`. Asserted on the absent Mac
        // because the present one never exercised the branch at all.
        let report = await session(shortcutsPresent: false).doctor(verbose: false)

        #expect(!report.shortcutsCLIAvailable,
                "the fixture must actually be the missing-CLI case, or this proves nothing")
        let names = report.grants.map(\.name)
        #expect(!names.contains(StatusChecks.shortcutsCLI),
                Comment(rawValue: "grants: \(names.joined(separator: ", "))"))
        #expect(StatusChecks.misfiledTools(in: report.grants).isEmpty)
        #expect(StatusChecks.permissions(in: report.grants).count == report.grants.count)
    }

    @Test("every grant the report carries is a permission, on either kind of Mac")
    func everyGrantIsAPermission() async {
        for present in [true, false] {
            let report = await session(shortcutsPresent: present).doctor(verbose: false)
            for grant in report.grants {
                #expect(StatusChecks.kindIsPermission(grant.name),
                        Comment(rawValue: "\(grant.name) is filed under grants and is not a permission"))
            }
        }
    }

    @Test("the fact itself survives — the boolean still carries it")
    func theBooleanStillCarriesTheFact() async {
        // Removing the row must not remove the knowledge. This is what the status
        // window's tools card composes its Shortcuts row from.
        let absent = await session(shortcutsPresent: false).doctor(verbose: false)
        let present = await session(shortcutsPresent: true).doctor(verbose: false)
        #expect(!absent.shortcutsCLIAvailable)
        #expect(present.shortcutsCLIAvailable)

        let rows = StatusChecks.toolRows(tools: absent.tools,
                                         shortcutsCLIAvailable: absent.shortcutsCLIAvailable)
        let shortcuts = rows.first { $0.tool == StatusChecks.shortcutsCLI }
        #expect(shortcuts != nil, "a missing CLI must still be visible somewhere")
        #expect(shortcuts?.tone == .bad)
    }

    // MARK: - A6. The frozen grant, armed before it is believed
    //
    // Child item 6, and the reason it is proved here rather than by revoking the
    // permission on this machine: the revocation could only ever CONFIRM the
    // freeze, never falsify it. `GrantProbeKeeper.definite` is assigned in one
    // place and cleared in none, and `claim(now:)` returns `.cached` as its first
    // branch — so after a definite answer no probe is ever started again for the
    // life of the process, whatever macOS does underneath.

    /// A platform closure whose answer can be changed between calls, standing in
    /// for a person toggling the switch in System Settings.
    private final class MutablePlatform: @unchecked Sendable {
        private let lock = NSLock()
        private var value: GrantState
        private(set) var calls = 0
        init(_ initial: GrantState) { value = initial }
        func set(_ new: GrantState) { lock.lock(); value = new; lock.unlock() }
        func read() -> GrantState {
            lock.lock(); defer { lock.unlock() }
            calls += 1
            return value
        }
    }

    @Test("a granted answer is frozen: the platform says denied and the probe still says granted")
    func aGrantedAnswerIsFrozenAgainstARevocation() async {
        let platform = MutablePlatform(.granted)
        let probe = ScreenRecordingProbe(platform: { platform.read() })

        #expect(await probe.state() == .granted)
        // The revocation. Nothing restarts; the process is the same one.
        platform.set(.denied)

        #expect(await probe.state() == .granted,
                "DEF-180: the grant is reported after it has been taken away")
        #expect(platform.calls == 1,
                "and the platform is never asked again, which is why no OS behaviour can fix it")
    }

    @Test("the control: an unconfirmed answer is not frozen, so the instrument can report the other outcome")
    func anUnconfirmedAnswerIsReProbed() async {
        // Without this the test above proves only that a stub returned a stub.
        // `unconfirmed` is never cached, so the same probe DOES ask again — the
        // freeze is a property of caching a definite answer and not of the
        // harness.
        let platform = MutablePlatform(.unconfirmed)
        let probe = ScreenRecordingProbe(bound: 0.05, platform: { platform.read() })

        #expect(await probe.state() == .unconfirmed)
        platform.set(.granted)
        // Past the backoff for one attempt, so the retry is due.
        var state = await probe.state()
        var waited = 0
        while state != .granted && waited < 40 {
            try? await Task.sleep(nanoseconds: 100_000_000)
            state = await probe.state()
            waited += 1
        }
        #expect(state == .granted, "an unconfirmed probe must be able to change its answer")
        #expect(platform.calls > 1, "and it must have asked the platform again to do so")
    }

    @Test("doctor reports the frozen value, so the freeze reaches a person")
    func doctorReportsTheFrozenValue() async {
        let platform = MutablePlatform(.granted)
        let session = Session(ax: FakeAX(bundleId: "com.example.app"), capture: FakeCapture(),
                              screenRecordingProbe: ScreenRecordingProbe(platform: { platform.read() }),
                              accessibilityProbe: { true },
                              shortcutsProbe: { true })

        let before = await session.doctor(verbose: false)
        #expect(before.grants.first { $0.name == StatusChecks.screenRecording }?.resolvedState
                == .granted)

        platform.set(.denied)

        let after = await session.doctor(verbose: false)
        let row = after.grants.first { $0.name == StatusChecks.screenRecording }
        #expect(row?.resolvedState == .granted,
                "DEF-180: doctor reports granted after the permission was revoked")
        #expect(row?.granted == true)
    }
}
