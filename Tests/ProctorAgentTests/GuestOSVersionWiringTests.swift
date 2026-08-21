import Foundation
import Testing
import ProctorCore
@testable import ProctorAgent

// PRO-0094. `proctor_guest action "status"` says which macOS a guest is running,
// or says why it cannot.
//
// The whole point of the field is that it is never a guess. A guest's provider
// does not record its OS version — `lume get` and tart's `config.json` report
// only `macOS` / `darwin` — so the only thing that knows is the machine itself,
// reached through the link an attach already opened. Every other case is
// `unknown` carrying a reason that names what would change it.
//
// **What the fakes do and do not supply.** `FakeGuestLink.reply` is the guest's
// answer, so a version this suite reads back is one the fixture wrote — that is
// the routing claim, and it is stated as such. The REASONS are not written here:
// they come out of `GuestOSVersionResolution`, and the cases below assert that
// four different situations produce four different production strings, counted
// with a `Set` rather than read.
@Suite("PRO-0094 · which macOS a guest is running")
struct GuestOSVersionWiringTests {

    // MARK: - Harness

    private static func record(_ name: String, running: Bool = true,
                               platform: MachinePlatform? = .macos,
                               provider: String = "tart") -> GuestRecord {
        GuestRecord(name: name, provider: provider,
                    state: running ? "running" : "stopped", running: running,
                    platform: platform, identifier: name)
    }

    private func harness(_ records: [GuestRecord])
        async throws -> (session: Session, link: FakeGuestLink) {
        let session = Session(ax: FakeAX(bundleId: "com.example.target"),
                              capture: FakeCapture(),
                              scheduler: RunScheduler.stoppedClock(),
                              secureInputProbe: { false })
        let link = FakeGuestLink()
        await session.setAuditSink(AuditCollector().sink)
        await session.setDrawsHUD(false)
        await session.setGuestProviders([FakeGuestProvider(id: "tart", records: records)])
        await session.setGuestLinkFactory { _ in link }
        return (session, link)
    }

    /// What the guest's own Proctor answers a `proctor_doctor` with.
    private func doctorReply(osVersion: String?) -> JSONValue {
        var fields: [String: JSONValue] = [
            "agentRunning": .bool(true),
            "machine": .object(["kind": .string("host")])
        ]
        if let osVersion { fields["osVersion"] = .string(osVersion) }
        return .object(fields)
    }

    private func osVersion(_ result: JSONValue) -> JSONValue? {
        result.objectValue?["osVersion"]
    }

    /// How many macOS guest slots the scheduler currently reports as held.
    private func macPoolHeld(_ session: Session) async -> Int? {
        let pools = await session.poolStatus().objectValue?["pools"]?.arrayValue
        let mac = pools?.first { $0.objectValue?["platform"]?.stringValue == "macos" }
        return mac?.objectValue?["held"]?.intValue
    }

    // MARK: - CASE-0184

    @Test("an attached guest reports the version its own Proctor answered with")
    func anAttachedGuestReportsItsVersion() async throws {
        let h = try await harness([Self.record("proctor-guest")])
        h.link.reply = doctorReply(osVersion: "26.6.2")
        _ = try await h.session.guest(action: "attach", guest: "proctor-guest",
                                      provider: nil, newName: nil)

        let status = try await h.session.guest(action: "status", guest: "proctor-guest",
                                               provider: nil, newName: nil)
        // Required, not optional-chained: `os` being absent altogether would
        // satisfy every `?.` check below by vacuum.
        let os = try #require(osVersion(status)?.objectValue,
                              "status must carry an osVersion object")
        #expect(os["version"]?.stringValue == "26.6.2")
        #expect(os["source"]?.stringValue == "guest-agent")
        #expect(os["reason"]?.stringValue == nil, "a known version carries no reason")

        // The channel, named: the question that produced it went to the guest
        // and it was the one that actuates nothing.
        #expect(h.link.forwarded.contains("proctor_doctor"),
                "the version must come from asking the guest, not from anything here")
    }

    // MARK: - CASE-0185

    @Test("four unanswerable situations give four different reasons")
    func everyUnknownNamesWhatWouldChangeIt() async throws {
        var reasons: [String: String] = [:]

        // 1. Stopped. Starting it is the next step, not attaching.
        do {
            let h = try await harness([Self.record("stopped-mac", running: false)])
            let status = try await h.session.guest(action: "status", guest: "stopped-mac",
                                                   provider: nil, newName: nil)
            let os = osVersion(status)?.objectValue
            #expect(os?["version"]?.stringValue == nil)
            #expect(os?["source"]?.stringValue == "unknown")
            reasons["stopped"] = os?["reason"]?.stringValue ?? ""
        }
        // 2. Delegated. No power state makes this one answerable.
        do {
            let h = try await harness([Self.record("linux-box", platform: .linux)])
            let status = try await h.session.guest(action: "status", guest: "linux-box",
                                                   provider: nil, newName: nil)
            let os = osVersion(status)?.objectValue
            #expect(os?["version"]?.stringValue == nil)
            reasons["delegated"] = os?["reason"]?.stringValue ?? ""
        }
        // 3. Running, macOS, nobody attached. There is no link to ask over.
        do {
            let h = try await harness([Self.record("idle-mac")])
            let status = try await h.session.guest(action: "status", guest: "idle-mac",
                                                   provider: nil, newName: nil)
            let os = osVersion(status)?.objectValue
            #expect(os?["version"]?.stringValue == nil)
            reasons["unattached"] = os?["reason"]?.stringValue ?? ""
        }
        // 4. Attached, and the guest's Proctor did not answer.
        do {
            let h = try await harness([Self.record("mute-mac")])
            _ = try await h.session.guest(action: "attach", guest: "mute-mac",
                                          provider: nil, newName: nil)
            h.link.sendError = AgentError(code: .agentUnavailable,
                                          message: "connection reset")
            let status = try await h.session.guest(action: "status", guest: "mute-mac",
                                                   provider: nil, newName: nil)
            let os = osVersion(status)?.objectValue
            #expect(os?["version"]?.stringValue == nil)
            reasons["silent"] = os?["reason"]?.stringValue ?? ""
            #expect(reasons["silent"]?.contains("connection reset") == true,
                    "what the link said travels verbatim: the tunnel and a Proctor that is not running inside the guest are fixed in different places")
        }

        #expect(reasons.count == 4, "four situations were exercised")
        for (situation, reason) in reasons {
            #expect(!reason.isEmpty, "\(situation) produced an empty reason")
        }
        // Distinct, counted rather than compared by eye. Two branches sharing one
        // sentence would tell a reader to do the wrong thing about one of them.
        #expect(Set(reasons.values).count == 4,
                "four situations produced \(Set(reasons.values).count) distinct reasons")
    }

    // MARK: - CASE-0186

    @Test("a session attached to one guest reads unknown for another")
    func oneGuestsVersionIsNeverAnothersAnswer() async throws {
        let h = try await harness([Self.record("guest-a"), Self.record("guest-b")])
        h.link.reply = doctorReply(osVersion: "26.6.2")
        _ = try await h.session.guest(action: "attach", guest: "guest-a",
                                      provider: nil, newName: nil)

        let a = try await h.session.guest(action: "status", guest: "guest-a",
                                          provider: nil, newName: nil)
        #expect(osVersion(a)?.objectValue?["version"]?.stringValue == "26.6.2")

        let b = try await h.session.guest(action: "status", guest: "guest-b",
                                          provider: nil, newName: nil)
        let os = osVersion(b)?.objectValue
        #expect(os?["version"]?.stringValue == nil,
                "guest-b was never asked; reporting guest-a's version here would be a true statement about the wrong machine")
        #expect(os?["reason"]?.stringValue?.contains("guest-b") == true)
    }

    // MARK: - CASE-0187

    @Test("the image name is never the answer")
    func theNameIsNotEvidence() async throws {
        // A guest whose name asserts a whole different macOS. The answer comes
        // from the machine or it does not come.
        let named = "macos-sequoia-cua"

        let unattached = try await harness([Self.record(named)])
        let cold = try await unattached.session.guest(action: "status", guest: named,
                                                     provider: nil, newName: nil)
        #expect(osVersion(cold)?.objectValue?["version"]?.stringValue == nil,
                "nothing may read a version out of \(named)")
        #expect(osVersion(cold)?.objectValue?["source"]?.stringValue == "unknown")

        let attached = try await harness([Self.record(named)])
        attached.link.reply = doctorReply(osVersion: "26.6.2")
        _ = try await attached.session.guest(action: "attach", guest: named,
                                             provider: nil, newName: nil)
        let warm = try await attached.session.guest(action: "status", guest: named,
                                                    provider: nil, newName: nil)
        #expect(osVersion(warm)?.objectValue?["version"]?.stringValue == "26.6.2",
                "the same guest, asked, answers what it is running rather than what it is called")

        // The pure resolver takes a record and a bool. Two guests differing only
        // in name reach the same verdict, so there is no name-shaped branch.
        let sequoiaShaped = GuestOSVersionResolution.obstacle(
            record: Self.record(named), attachedByThisSession: false)
        let plain = GuestOSVersionResolution.obstacle(
            record: Self.record("x"), attachedByThisSession: false)
        // Both must be REAL obstacles, not merely equal ones: `(nil == nil)` is
        // true, so an obstacle() gutted to return nil unconditionally passed the
        // first draft of this check. Found by the PRO-0094 completeness critic.
        #expect(sequoiaShaped != nil, "an unattached guest has an obstacle whatever it is called")
        #expect(plain != nil, "an unattached guest has an obstacle whatever it is called")
        #expect(sequoiaShaped?.replacingOccurrences(of: named, with: "NAME")
                == plain?.replacingOccurrences(of: "x", with: "NAME"),
                "the obstacle must differ only where the guest's name is quoted back")
    }

    // MARK: - CASE-0188

    @Test("a status read whose link fails does not release the attachment")
    func aReadNeverEvictsASlot() async throws {
        let h = try await harness([Self.record("held-mac")])
        _ = try await h.session.guest(action: "attach", guest: "held-mac",
                                      provider: nil, newName: nil)

        let heldBefore = try #require(await macPoolHeld(h.session))
        #expect(heldBefore == 1, "attaching took the slot this case is about")

        h.link.sendError = AgentError(code: .agentUnavailable, message: "connection reset")
        let status = try await h.session.guest(action: "status", guest: "held-mac",
                                               provider: nil, newName: nil)
        #expect(osVersion(status)?.objectValue?["version"]?.stringValue == nil)

        // The slot itself, counted off the scheduler rather than inferred from
        // the attachment surviving. The spec clause names both, and a release
        // that dropped the ticket while leaving the record would pass the check
        // below and fail this one.
        #expect(await macPoolHeld(h.session) == heldBefore,
                "a failed status read must not give back the macOS slot its session is holding")

        // Still attached, proved by an observable rather than by reading a field:
        // a released session answers a forwardable call here on this Mac instead.
        h.link.sendError = nil
        let forwarded = try await h.session.forwardToGuestIfAttached(
            AgentRequest(id: "after", tool: "proctor_act", arguments: .object([:])))
        #expect(forwarded != nil,
                "the attachment survived the failed read; a status poll must never evict the slot a live run is holding")
        #expect(h.link.forwarded.contains("proctor_act"))
    }

    // MARK: - CASE-0181c

    @Test("every guest listing carries the one Tahoe note")
    func theCapabilitiesNoteIsTheConstant() async {
        let note = await Session.guestCapabilities.objectValue?["note"]?.stringValue
        #expect(note != nil, "the guest capabilities must carry a note")
        #expect(note?.contains(GuestNotes.tahoeRendering) == true,
                "guestCapabilities must interpolate GuestNotes.tahoeRendering")
        #expect(note?.contains("verify against Sequoia") != true)
    }

    // MARK: - CASE-0189 (the refusal a caller reads)

    @Test("the missing-guest refusal names all three providers")
    func theRefusalNamesTart() async throws {
        let h = try await harness([Self.record("anything")])
        do {
            _ = try await h.session.guest(action: "status", guest: nil,
                                          provider: nil, newName: nil)
            Issue.record("a status with no guest must be refused")
        } catch let error as AgentError {
            let remedy = error.remedy ?? ""
            #expect(remedy.contains("tart"),
                    "the refusal says \(remedy.debugDescription); a reader who is told two providers concludes the third is unsupported")
            for stale in ["lume or prlctl", "lume and prlctl"] {
                #expect(!remedy.contains(stale))
            }
        }
    }
}
