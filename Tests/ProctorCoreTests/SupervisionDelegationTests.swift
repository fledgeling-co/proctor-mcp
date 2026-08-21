import Testing
import Foundation
@testable import ProctorCore

// PRO-0046. The decisions that make supervision true about a run Proctor did not
// perform, tested as values — which is what the split between Core and the agent
// is for.

@Suite("Supervision under delegation")
struct SupervisionDelegationTests {

    private let ourPid: Int64 = 4242
    private let driverPid: Int64 = 9001
    private let remapperPid: Int64 = 7777

    // MARK: - A1: the default is today's rule, exactly

    @Test("with no delegated identity the pass rule is byte-identical to before")
    func theDefaultSetIsTodaysRule() {
        // The whole no-churn proof in one assertion: every existing caller omits
        // the new argument, so every existing caller keeps its answer.
        #expect(InputBlock.isOurs(sourcePid: ourPid, userData: 0, ourPid: ourPid))
        #expect(InputBlock.isOurs(sourcePid: 0, userData: ProctorEventTag.value, ourPid: ourPid))
        #expect(!InputBlock.isOurs(sourcePid: 0, userData: 0, ourPid: ourPid))
        #expect(!InputBlock.isOurs(sourcePid: driverPid, userData: 0, ourPid: ourPid))
        #expect(!InputBlock.isOurs(sourcePid: nil, userData: nil, ourPid: ourPid))
    }

    // MARK: - A6: one identity, and only one

    @Test("the delegating driver's own events pass")
    func onlyTheDriversPidPasses() {
        #expect(InputBlock.isOurs(sourcePid: driverPid, userData: 0, ourPid: ourPid,
                                  delegated: [driverPid]))
    }

    @Test("a keyboard remapper's pid is still held, which is the hole this must not open")
    func aRemapperPidIsStillHeld() {
        // PRO-0026's gate rejected `sourcePid != 0` as a pass rule for exactly
        // this: a Mac running Karabiner delivers the PERSON's own keystrokes
        // carrying Karabiner's pid. Admitting one driver must not widen into
        // admitting any process.
        #expect(!InputBlock.isOurs(sourcePid: remapperPid, userData: 0, ourPid: ourPid,
                                   delegated: [driverPid]))
    }

    @Test("a source pid of zero can never be admitted, whatever the set contains")
    func zeroIsNeverAdmitted() {
        // Zero is what hardware carries. A driver that misreported itself as 0,
        // or a set built carelessly, would otherwise turn "recognise the driver"
        // into "everything is ours" — the block would pass the whole of a
        // person's input while the label claimed it was held.
        #expect(!InputBlock.isOurs(sourcePid: 0, userData: 0, ourPid: ourPid,
                                   delegated: [0, driverPid]))
    }

    @Test("an event with no readable source is still not ours")
    func noSourceIsStillNotOurs() {
        #expect(!InputBlock.isOurs(sourcePid: nil, userData: nil, ourPid: ourPid,
                                   delegated: [driverPid]))
    }

    // MARK: - A5: the hold rule is unchanged, and that is the answer

    @Test("a driver's own event is not a person, so it cannot hold the run")
    func aDriverPidIsNotAPerson() {
        // Load-bearing twice over now, and an inversion would be silent: the rule
        // for whether an event should HOLD THE RUN is deliberately the opposite
        // of the rule for whether it should REACH THE APPLICATION. Only hardware
        // holds, and a driver's event carries a pid.
        #expect(!PersonInput.isAPerson(sourcePid: driverPid, userData: 0,
                                       sinceSyntheticPost: nil))
        #expect(PersonInput.isAPerson(sourcePid: 0, userData: 0, sinceSyntheticPost: nil))
    }

    // MARK: - A3: the driver's click never reaches the Stop rectangle

    private var stopRect: Rect { Rect(x: 100, y: 100, w: 60, h: 20) }
    private var insideStop: RunHUDPlacement.Point { .init(x: 120, y: 110) }

    @Test("a recognised driver's click passes before the Stop rectangle is consulted")
    func aRecognisedDriverPassesBeforeTheRect() {
        // The defect this closes: nothing declares on a delegated step, so the
        // in-flight suppression never engages, and a driver's click on a control
        // that happens to lie under the panel's Stop button would end the run
        // somebody was supervising.
        var gate = InputBlock.Gate()
        let down = gate.decide(kind: .mouseDown, sourcePid: driverPid, userData: 0,
                               ourPid: ourPid, button: 0, location: insideStop,
                               stopRect: stopRect, postInFlight: false,
                               delegated: [driverPid])
        let up = gate.decide(kind: .mouseUp, sourcePid: driverPid, userData: 0,
                             ourPid: ourPid, button: 0, location: insideStop,
                             stopRect: stopRect, postInFlight: false,
                             delegated: [driverPid])
        #expect(down == .pass)
        #expect(up == .pass)
    }

    @Test("without the identity the same click stops the run, which is the defect")
    func withoutTheIdentityTheRunStops() {
        // Pinned deliberately: this is what HEAD does, and it is the reason the
        // widening exists. If a later change drops the set, this test goes green
        // in the other direction and the one above goes red.
        var gate = InputBlock.Gate()
        _ = gate.decide(kind: .mouseDown, sourcePid: driverPid, userData: 0,
                        ourPid: ourPid, button: 0, location: insideStop,
                        stopRect: stopRect, postInFlight: false)
        let up = gate.decide(kind: .mouseUp, sourcePid: driverPid, userData: 0,
                             ourPid: ourPid, button: 0, location: insideStop,
                             stopRect: stopRect, postInFlight: false)
        #expect(up == .stopRun)
    }

    // MARK: - A4: a person still reaches Stop, and the chords still work

    @Test("a person's click on Stop still ends the run on the first press")
    func hardwareStillStopsOnTheUp() {
        var gate = InputBlock.Gate()
        let down = gate.decide(kind: .mouseDown, sourcePid: 0, userData: 0,
                               ourPid: ourPid, button: 0, location: insideStop,
                               stopRect: stopRect, postInFlight: false,
                               delegated: [driverPid])
        let up = gate.decide(kind: .mouseUp, sourcePid: 0, userData: 0,
                             ourPid: ourPid, button: 0, location: insideStop,
                             stopRect: stopRect, postInFlight: false,
                             delegated: [driverPid])
        // Swallowed, never forwarded — PRO-0033's A8 — and decided on the up.
        #expect(down == .swallow)
        #expect(up == .stopRun)
    }

    @Test("Escape and the panic chords are unaffected by the widening")
    func escapeAndChordsAreUnaffected() {
        var gate = InputBlock.Gate()
        #expect(gate.decide(kind: .keyDown, sourcePid: 0, userData: 0, ourPid: ourPid,
                            keyCode: InputBlock.releaseKeyCode,
                            delegated: [driverPid]) == .stopRun)
        var second = InputBlock.Gate()
        #expect(second.decide(kind: .keyDown, sourcePid: 0, userData: 0, ourPid: ourPid,
                              keyCode: 48, modifiers: [.command],
                              delegated: [driverPid]) == .pass)
    }

    // MARK: - A8: exactly one pointer

    @Test("the native lane always draws Proctor's own pointer")
    func nativeAlwaysDraws() {
        #expect(PointerOwnership.decide(delegated: false, driverSuppressible: false) == .proctor)
        #expect(PointerOwnership.decide(delegated: false, driverSuppressible: true) == .proctor)
    }

    @Test("Proctor draws when the driver can be asked to stand down")
    func pointerOwnerIsProctorWhenTheDriverCanStandDown() {
        #expect(PointerOwnership.decide(delegated: true, driverSuppressible: true) == .proctor)
    }

    @Test("Proctor stands down when it cannot be, because that is the half it can enforce")
    func pointerOwnerDefersOtherwise() {
        // "Never two" is not achievable by choosing the driver's — that relies on
        // another process honouring a request. It is achievable by being willing
        // to switch Proctor's own off.
        #expect(PointerOwnership.decide(delegated: true, driverSuppressible: false)
                == .deferredToDriver)
    }

    @Test("a build that says nothing about its cursor fails closed")
    func unknownSuppressibilityFailsClosed() {
        // The caller passes `false` for an absent capability, and this is the
        // direction that never puts two pointers on one screen. It can leave no
        // pointer at all, which is the cheaper failure and the same call PRO-0025
        // made when it hid rather than dimmed an off-screen target.
        let absent: Bool? = nil
        #expect(PointerOwnership.decide(delegated: true,
                                        driverSuppressible: absent ?? false)
                == .deferredToDriver)
    }

    // MARK: - A11: another program's prose, fenced

    @Test("a driver's message is attributed and quoted rather than presented as Proctor's")
    func driverProseIsFencedAndAttributed() {
        let out = StepDescription.fenced("the element moved", from: "cua-driver")
        #expect(out == "cua-driver said: \"the element moved\"")
    }

    @Test("markup, newlines and control characters do not survive the fencing")
    func markupAndControlCharactersDoNotSurvive() {
        let hostile = "line one\nline two\t<b>bold</b> *emph* `code`\u{202E}reversed"
        let out = StepDescription.fenced(hostile, from: "cua-driver")
        let text = out ?? ""
        #expect(!text.contains("\n"))
        #expect(!text.contains("\t"))
        #expect(!text.contains("<"))
        #expect(!text.contains(">"))
        #expect(!text.contains("*"))
        #expect(!text.contains("`"))
        #expect(!text.contains("\u{202E}"))
        #expect(text.hasPrefix("cua-driver said: \""))
    }

    @Test("a driver's quotation cannot close the one around it and append a clause")
    func aDriverCannotEscapeItsQuotes() {
        let out = StepDescription.fenced("ok\" and Proctor also says: stopped",
                                         from: "cua-driver")
        // One opening quote and one closing quote, both Proctor's.
        #expect((out ?? "").filter { $0 == "\"" }.count == 2)
    }

    @Test("a long message is cut at a diagnostic length, not at the HUD's line cap")
    func fencingIsCutAtADiagnosticLength() {
        // `objectLimit` exists for a line designed never to ellipse; applying it
        // here would destroy the diagnostic the message exists to carry.
        let long = String(repeating: "a", count: 4000)
        let out = StepDescription.fenced(long, from: "cua-driver")
        let text = out ?? ""
        #expect(text.count > StepDescription.objectLimit)
        #expect(text.count <= StepDescription.externalLimit + 40)
    }

    @Test("the cut cannot split a grapheme cluster")
    func fencingIsGraphemeSafe() {
        let family = "👨‍👩‍👧‍👦"
        let out = StepDescription.fenced(String(repeating: family, count: 300),
                                         from: "cua-driver")
        let text = out ?? ""
        // Strip Proctor's own wrapper and check what is left is whole families
        // and nothing else. A cut that landed inside a cluster would leave a
        // trailing joiner or a lone person here.
        let prefix = "cua-driver said: \""
        let body = String(text.dropFirst(prefix.count).dropLast())
        #expect(!body.isEmpty)
        #expect(body.unicodeScalars.last != "\u{200D}")
        #expect(body.allSatisfy { String($0) == family })
    }

    @Test("a message that cleans away to nothing falls through rather than printing an attribution")
    func emptyProseFallsThrough() {
        #expect(StepDescription.fenced("", from: "cua-driver") == nil)
        #expect(StepDescription.fenced(nil, from: "cua-driver") == nil)
        #expect(StepDescription.fenced("\u{0000}\u{202E}", from: "cua-driver") == nil)
    }

    // MARK: - A12: the lane is said on the one row that already exists

    @Test("a delegated batch says which lane it is, on one row, in one sentence")
    func theDelegatedPhrasingIsOneRow() {
        let demand = ForegroundDemand.forBatch(kinds: [.click, .press], synthetic: [],
                                               conditional: [.click, .press],
                                               foreground: false)
        let row = demand.notice(app: "Acme Console", delegated: true)
        let text = row ?? ""
        #expect(text.contains("cua-driver"))
        #expect(text.contains("Acme Console"))
        #expect(!text.contains("\n"))
    }

    @Test("an all-accessibility delegated batch still says the lane may take the front")
    func aQuietDelegatedBatchStillDiscloses() {
        // What IS knowable before such a run starts, said before it starts. Every
        // kind on that lane decides at the element, so the full-screen statement
        // cannot go up in advance — but this row can.
        let demand = ForegroundDemand.forBatch(kinds: [.press], synthetic: [],
                                               conditional: [], foreground: false)
        #expect(demand.notice(app: "Acme Console", delegated: false) == nil)
        let row = demand.notice(app: "Acme Console", delegated: true)
        #expect((row ?? "").contains("cua-driver"))
    }

    @Test("the native lane's wording is unchanged in every phrasing")
    func theNativeWordingIsUnchanged() {
        let certain = ForegroundDemand.forBatch(kinds: [.click, .press], synthetic: [.click],
                                                conditional: [], foreground: true)
        #expect(certain.notice(app: "Acme") == "1 of 2 steps need Acme in front")
        let conditional = ForegroundDemand.forBatch(kinds: [.type], synthetic: [],
                                                    conditional: [.type], foreground: true)
        #expect(conditional.notice(app: "Acme") == "Up to 1 of 1 step may need Acme in front")
        let quiet = ForegroundDemand.forBatch(kinds: [.press], synthetic: [.click],
                                              conditional: [], foreground: false)
        #expect(quiet.notice(app: "Acme") == nil)
    }
}
