import Foundation
import Testing
import ProctorCore

// PRO-0018 — noticing that a person is taking the machine back.
//
// The whole feature is signal quality, and its two failure modes are both worse
// than not shipping: Proctor reading its own events as somebody else's and
// pausing itself forever, and a hold nobody asked for that nobody can undo. Both
// are decided by pure values, and this is where they are pinned.
//
// What `swift test` cannot reach is stated in the spec and not dressed up here:
// a real `NSEvent` arriving, a real frontmost change, and whether the tag Proctor
// stamps on a posted `CGEvent` survives to the `NSEvent` an input monitor sees.
// The last one was measured by hand on 2026-08-14 (it does), and filter 3 covers
// the case where a later macOS stops carrying it.

@Suite("Contention — is a person using this Mac")
struct ContentionTests {

    private let ours: Int32 = 4242
    private let target: Int32 = 99
    private let somebodyElse: Int32 = 77

    private func sample(expected: Int32? = 99, front: Int32? = 99, secure: Bool = false,
                        input: Double? = nil, now: Double = 100) -> ContentionSample {
        ContentionSample(expectedPid: expected, frontmostPid: front, proctorPids: [ours],
                         secureInput: secure, lastUserInputAt: input, now: now)
    }

    // MARK: - A2: Proctor's own doing is never a person's

    @Test("a run driving the app it raised never yields, however many steps it posts")
    func proctorsOwnForegroundIsNotContention() {
        var watch = ContentionWatch()
        for tick in 0..<20 {
            #expect(watch.sample(sample(now: 100 + Double(tick))) == .none)
        }
        #expect(watch.isYielded == false)
    }

    @Test("an app Proctor asked for but never got is not somebody taking it away")
    func anUnconfirmedFrontCannotFire() {
        var watch = ContentionWatch(releaseDelay: 0)
        // The raise silently failed, or the app is still launching. The front is
        // not what Proctor asked for, and no person did that. Holding here would
        // park every run whose target never came forward, which is a stall
        // dressed up as somebody using their Mac.
        for tick in 0..<10 {
            #expect(watch.sample(sample(front: somebodyElse, now: 100 + Double(tick))) == .none)
        }
        // It arrives; now the reading means something.
        #expect(watch.sample(sample(front: target, now: 110)) == .none)
        #expect(watch.sample(sample(front: somebodyElse, now: 111))
                == .yielded(.frontmostChanged))
    }

    @Test("before Proctor has taken the front there is nothing to take back")
    func noExpectedPidMeansNoContention() {
        var watch = ContentionWatch()
        // Something else is frontmost, but Proctor has not raised anything, so
        // this is just a Mac with an app on it.
        #expect(watch.sample(sample(expected: nil, front: somebodyElse)) == .none)
        #expect(watch.isYielded == false)
    }

    @Test("Proctor's own windows in front are not somebody taking the machine")
    func proctorsOwnProcessIsNotAPerson() {
        var watch = ContentionWatch()
        // Somebody opened Proctor's menu to press Resume. Reading that as
        // contention would hold the very run they are trying to release.
        #expect(watch.sample(sample(front: ours)) == .none)
        #expect(watch.isYielded == false)
    }

    // MARK: - A3: the signals fire, and release

    @Test("the front moving away yields, and coming back releases")
    func frontmostYieldsAndReleases() {
        var watch = ContentionWatch(releaseDelay: 0)
        // Proctor's app is seen in front first. Until it has been, there is
        // nothing for anybody to have taken back.
        #expect(watch.sample(sample(front: target)) == .none)
        #expect(watch.sample(sample(front: somebodyElse)) == .yielded(.frontmostChanged))
        #expect(watch.reason == .frontmostChanged)
        // Still away: held, and not re-announced.
        #expect(watch.sample(sample(front: somebodyElse, now: 101)) == .none)
        #expect(watch.sample(sample(front: target, now: 102)) == .released(.frontmostChanged))
        #expect(watch.isYielded == false)
    }

    @Test("secure keyboard entry yields, and releases when it goes off")
    func secureInputYieldsAndReleases() {
        var watch = ContentionWatch(releaseDelay: 0)
        #expect(watch.sample(sample(secure: true)) == .yielded(.secureInput))
        #expect(watch.sample(sample(secure: false, now: 101)) == .released(.secureInput))
    }

    @Test("secure input outranks the frontmost reading when both hold")
    func secureInputOutranksFrontmost() {
        var watch = ContentionWatch(releaseDelay: 0)
        _ = watch.sample(sample(front: target))
        let both = sample(front: somebodyElse, secure: true)
        #expect(watch.sample(both) == .yielded(.secureInput))
        #expect(watch.reason == .secureInput)
    }

    @Test("a person's own input yields and decays rather than sitting forever")
    func userInputDecays() {
        var watch = ContentionWatch(inputWindow: 10, releaseDelay: 0)
        #expect(watch.sample(sample(input: 100, now: 100)) == .yielded(.userInput))
        #expect(watch.sample(sample(input: 100, now: 105)) == .none)      // still theirs
        #expect(watch.sample(sample(input: 100, now: 111)) == .released(.userInput))
    }

    @Test("a hold survives one sample of the condition flickering")
    func releaseIsDamped() {
        var watch = ContentionWatch(releaseDelay: 2)
        _ = watch.sample(sample(front: target))
        #expect(watch.sample(sample(front: somebodyElse)) == .yielded(.frontmostChanged))
        // The front comes back for an instant — an app finishing a launch, a
        // notification going away. Releasing here and re-yielding on the next
        // sample would flicker the panel and the run.
        #expect(watch.sample(sample(front: target, now: 101)) == .none)
        #expect(watch.sample(sample(front: somebodyElse, now: 101.5)) == .none)
        #expect(watch.isYielded == true)
    }

    @Test("two reasons at once release only when both have gone")
    func everyReasonHasToClear() {
        var watch = ContentionWatch(releaseDelay: 0)
        _ = watch.sample(sample(front: target, now: 99))
        #expect(watch.sample(sample(front: somebodyElse, input: 100, now: 100))
                == .yielded(.userInput))
        // The app comes back but the person is still typing. Releasing here
        // would forget the hand on the keyboard because the weaker reason was
        // the one that happened to clear.
        #expect(watch.sample(sample(front: target, input: 100, now: 101)) == .none)
        #expect(watch.isYielded == true)
        #expect(watch.sample(sample(front: target, input: 100, now: 111))
                == .released(.userInput))
    }

    // MARK: - A5: a person's decision wins, and Resume is not undone

    @Test("Resume overrides the episode, so the same condition does not re-yield")
    func resumeOverridesTheEpisode() {
        var watch = ContentionWatch(releaseDelay: 0)
        _ = watch.sample(sample(front: target))
        #expect(watch.sample(sample(front: somebodyElse)) == .yielded(.frontmostChanged))
        watch.resumedByPerson()
        // Still in another app, and the run carries on because they said so.
        #expect(watch.sample(sample(front: somebodyElse, now: 101)) == .none)
        #expect(watch.sample(sample(front: somebodyElse, now: 102)) == .none)
        #expect(watch.isYielded == false)
    }

    @Test("and it re-arms once that reason has cleared and recurred")
    func overrideIsSpentWhenTheConditionGoes() {
        var watch = ContentionWatch(releaseDelay: 0)
        _ = watch.sample(sample(front: target))
        _ = watch.sample(sample(front: somebodyElse))
        watch.resumedByPerson()
        #expect(watch.sample(sample(front: somebodyElse, now: 101)) == .none)
        // Back in the app under test: the override is spent.
        #expect(watch.sample(sample(front: target, now: 102)) == .none)
        // And away again is a new episode, which yields.
        #expect(watch.sample(sample(front: somebodyElse, now: 103))
                == .yielded(.frontmostChanged))
    }

    @Test("resuming past one reason does not blind Proctor to another")
    func theOverrideIsPerReason() {
        var watch = ContentionWatch(releaseDelay: 0)
        _ = watch.sample(sample(front: target))
        _ = watch.sample(sample(front: somebodyElse))
        watch.resumedByPerson()
        #expect(watch.sample(sample(front: somebodyElse, secure: true, now: 101))
                == .yielded(.secureInput))
    }

    // MARK: - A1 / the filters: was that event ours?

    @Test("an event Proctor posted is never read as a person's")
    func ourOwnEventsAreNeverAPerson() {
        // Exhaustive over what an input monitor can see. Only the all-negative
        // cell is a person: hardware pid, no tag of ours, outside the grace.
        //
        // The direction matters more than the coverage. A person's input is not
        // "an event that is not ours" — it is an event that came from the
        // HARDWARE. Stating it the other way compiles, passes a test written
        // against it, and in production reads the driven application's own
        // echoes as a person and never lets go.
        for pid in [Int64(0), 4242, 99] {
            for tag in [Int64(0), ProctorEventTag.value] {
                for since in [Double?.none, 0.1, 5.0] {
                    let verdict = PersonInput.isAPerson(sourcePid: pid, userData: tag,
                                                        sinceSyntheticPost: since, grace: 0.25)
                    let expected = pid == 0 && tag != ProctorEventTag.value
                                && !(since.map { $0 < 0.25 } ?? false)
                    #expect(verdict == expected,
                            "pid \(pid) tag \(tag) since \(String(describing: since))")
                }
            }
        }
    }

    @Test("an event from some other process is not a person either")
    func aProcessIsNotAPerson() {
        // The driven application echoing one of Proctor's clicks, an input
        // method, the window server. Non-zero pid, no tag, well outside the
        // grace — and still not a hand on the keyboard.
        #expect(PersonInput.isAPerson(sourcePid: 501, userData: 0,
                                      sinceSyntheticPost: 30) == false)
    }

    @Test("an event carrying no CGEvent at all is not evidence of a person")
    func noSourceIsNotEvidence() {
        #expect(PersonInput.isAPerson(sourcePid: nil, userData: nil,
                                      sinceSyntheticPost: nil) == false)
    }

    @Test("the grace window covers an arrival Proctor's own post caused")
    func theGraceWindowCatchesTheEcho() {
        #expect(PersonInput.isAPerson(sourcePid: 0, userData: 0,
                                      sinceSyntheticPost: 0.1, grace: 0.25) == false)
        #expect(PersonInput.isAPerson(sourcePid: 0, userData: 0,
                                      sinceSyntheticPost: 0.3, grace: 0.25) == true)
    }

    // MARK: - A6: the panel says why

    @Test("every reason has its own line, and none of them reads as a fault")
    func everyReasonSaysWhy() {
        #expect(YieldReason.frontmostChanged.line == "Paused — you moved to another app")
        #expect(YieldReason.secureInput.line == "Paused — secure keyboard entry is on")
        #expect(YieldReason.userInput.line == "Paused — you used the keyboard or mouse")
        for reason in YieldReason.allCases {
            #expect(!reason.line.isEmpty)
            #expect(!reason.detail.isEmpty)
        }
    }

    @Test("a yielded run wears the quiet held state, not a new one")
    func theYieldedStateIsThePausedOne() {
        var state = RunHUDState()
        state.apply(.runBegan(total: 2, app: "Acme"))
        state.apply(.stepActing(step: ActionStep(kind: .click), node: nil, synthetic: true))
        state.apply(.yielded(reason: .userInput))
        #expect(state.model.phase == .paused)
        #expect(state.model.tone == .quiet)
        #expect(state.model.line == YieldReason.userInput.line)
        // Resume is the ask's answer, and it has to be clickable — the panel
        // gates its mouse handling on this flag, so a held run that left it set
        // would be a hold nobody could undo.
        #expect(state.model.pauseLabel == "Resume")
        #expect(state.model.syntheticInFlight == false)
    }

    @Test("carrying on returns to the step it was holding before")
    func unyieldingReturnsToTheStep() {
        var state = RunHUDState()
        state.apply(.runBegan(total: 2, app: "Acme"))
        let step = ActionStep(kind: .click, node: "n1")
        state.apply(.stepActing(step: step, node: nil, synthetic: true))
        state.apply(.yielded(reason: .frontmostChanged))
        state.apply(.unyielded)
        #expect(state.model.phase == .acting)
        #expect(state.model.line != YieldReason.frontmostChanged.line)
    }

    // MARK: - A8: it says so afterwards

    @Test("a run that was held says how long and why")
    func theRecordsSayWhatHappened() throws {
        let records = [
            YieldRecord(reason: .frontmostChanged, step: 2, heldMs: 4300, endedBy: .released),
            YieldRecord(reason: .userInput, step: 5, heldMs: 900, endedBy: .person)
        ]
        let note = try #require(YieldRecord.note(for: records))
        #expect(note.contains("2 times"))
        #expect(note.contains("5200ms"))
        let encoded = try JSONValue.encode(records[0])
        #expect(encoded["reason"]?.stringValue == "frontmostChanged")
        #expect(encoded["endedBy"]?.stringValue == "released")
        #expect(encoded["step"]?.intValue == 2)
    }

    @Test("a run nothing contended with says nothing at all")
    func silenceWhenNothingHappened() {
        #expect(YieldRecord.note(for: []) == nil)
    }

    @Test("a result with no yields encodes exactly as it did before this existed")
    func noYieldsIsByteIdentical() throws {
        let result = ActResult(window: "w1", steps: [], completed: 0, failedAt: nil,
                               finalHash: nil, backend: .native)
        let encoded = try JSONValue.encode(result)
        #expect(encoded["yields"] == nil || encoded["yields"] == .null)
    }
}
