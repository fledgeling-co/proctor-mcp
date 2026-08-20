import Foundation
import Testing
@testable import ProctorCore

// PRO-0076 — what an attachment is, and which handles may resolve while it is.
//
// Pure: no socket, no provider, no VM. The tier derivation and the three
// refusals are decisions, and this is where they are provable.

@Suite("PRO-0076 · the attachment")
struct GuestAttachmentTests {

    private func record(_ name: String, platform: MachinePlatform?,
                        provider: String = "tart") -> GuestRecord {
        GuestRecord(name: name, provider: provider, state: "running", running: true,
                    platform: platform, identifier: name)
    }

    // MARK: - A3

    @Test("the tier is derived from the platform, in both directions")
    func tierIsDerived() {
        // Both directions, because a test that only catches "a delegated guest
        // claimed native" would pass on a build that called every guest
        // delegated — including the macOS one this feature exists to drive.
        #expect(GuestAttachment.machine(for: record("m", platform: .macos)).tier == .native)
        #expect(GuestAttachment.machine(for: record("l", platform: .linux)).tier == .delegated)
        #expect(GuestAttachment.machine(for: record("w", platform: .windows)).tier == .delegated)
    }

    @Test("a platform the provider did not name is delegated, never native")
    func absentPlatformIsFailClosed() {
        let machine = GuestAttachment.machine(for: record("unknown", platform: nil))
        #expect(machine.tier == .delegated)
        #expect(machine.platform == nil)
    }

    @Test("the derivation is a function, so no attach site can supply a tier")
    func tierCannotBeSupplied() {
        // `Machine.tier` has no default precisely so a site that forgot to say
        // cannot describe a Linux guest as carrying instruments it does not
        // have. `machine(for:)` takes a GuestRecord and nothing else — there is
        // no parameter through which a caller could assert a tier.
        let m = GuestAttachment.machine(for: record("anvil-mac-node", platform: .macos))
        #expect(m.kind == .guest)
        #expect(m.name == "anvil-mac-node")
        #expect(m.provider == "tart")
        #expect(m.platform == .macos)
    }

    @Test("darwin from tart ends up native, end to end")
    func darwinIsNative() {
        // The classification that decides the only live target's tier, its pool
        // and whether `reach` will speak to it at all.
        let platform = GuestPlatform.infer(os: "darwin", name: nil)
        #expect(platform == .macos)
        #expect(GuestAttachment.machine(for: record("anvil-mac-node", platform: platform)).tier
                    == .native)
    }

    // MARK: - A4

    private let guestMachine = Machine(kind: .guest, name: "anvil-mac-node",
                                       provider: "tart", platform: .macos, tier: .native)
    private let otherGuest = Machine(kind: .guest, name: "second-node",
                                     provider: "tart", platform: .macos, tier: .native)

    @Test("a host window id under a guest session is refused, naming both machines")
    func hostHandleInGuestSession() {
        let refusal = GuestHandleScope.refusal(handle: "win:12:0",
                                               callerMachine: guestMachine,
                                               callerSession: "s1",
                                               origin: .host)
        let message = try! #require(refusal).message
        #expect(message.contains("win:12:0"))
        #expect(message.contains("this Mac"), "the host must be named")
        #expect(message.contains("anvil-mac-node"), "the guest must be named")
    }

    @Test("a guest window id under a host session is refused, naming both machines")
    func guestHandleInHostSession() {
        let refusal = GuestHandleScope.refusal(
            handle: "win:99:0", callerMachine: .host, callerSession: "s1",
            origin: .guest(session: "s1", machine: "anvil-mac-node · macos · tart"))
        let message = try! #require(refusal).message
        #expect(message.contains("anvil-mac-node"))
        #expect(message.contains("this Mac"))
    }

    @Test("one guest session cannot resolve another guest session's handle")
    func crossSessionGuestHandle() {
        // THE CASE A4 IS ACTUALLY ABOUT. Both sides are guests, so a check that
        // compared only machines would let this straight through and the lookup
        // would come back `windowNotFound` -- a miss that reads as "the window
        // closed" and sends a caller round a retry loop for a window that was
        // never theirs.
        let refusal = GuestHandleScope.refusal(
            handle: "win:99:0", callerMachine: guestMachine, callerSession: "s2",
            origin: .guest(session: "s1", machine: "anvil-mac-node · macos · tart"))
        let message = try! #require(refusal).message
        #expect(message.contains("a different session"))
        #expect(message.contains("resolves only within the session that attached it"))
    }

    @Test("two guest sessions on DIFFERENT guests are also refused across")
    func crossSessionDifferentGuests() {
        let refusal = GuestHandleScope.refusal(
            handle: "win:5:0", callerMachine: otherGuest, callerSession: "s2",
            origin: .guest(session: "s1", machine: "anvil-mac-node · macos · tart"))
        #expect(refusal != nil)
    }

    @Test("a session's own handles resolve, on both machines")
    func ownHandlesResolve() {
        // The scoping must not refuse the ordinary case, or it would break every
        // existing host session on this Mac.
        #expect(GuestHandleScope.refusal(handle: "win:1:0", callerMachine: .host,
                                         callerSession: "s1", origin: .host) == nil)
        #expect(GuestHandleScope.refusal(
            handle: "win:9:0", callerMachine: guestMachine, callerSession: "s1",
            origin: .guest(session: "s1", machine: "anvil-mac-node")) == nil)
    }

    @Test("every refusal names both machines and offers a route that works")
    func refusalsCarryARemedy() {
        let cases: [(Machine, String, GuestHandleScope.Origin)] = [
            (guestMachine, "s1", .host),
            (.host, "s1", .guest(session: "s1", machine: "anvil-mac-node")),
            (guestMachine, "s2", .guest(session: "s1", machine: "anvil-mac-node"))
        ]
        for (machine, session, origin) in cases {
            let refusal = try! #require(GuestHandleScope.refusal(
                handle: "win:1:0", callerMachine: machine,
                callerSession: session, origin: origin))
            #expect(!refusal.remedy.isEmpty)
            #expect(refusal.remedy.contains("proctor_"),
                    "a refusal must name the call that does work")
        }
    }

    // MARK: - The attachment value

    @Test("an attachment holds its slot until something releases it once")
    func slotHeldIsTheIdempotenceBit() {
        var attachment = GuestAttachment(
            machine: guestMachine, handle: "gst-abc", provider: "tart",
            name: "anvil-mac-node", localSocket: "/tmp/g.sock",
            startedByThisAgent: true, attachedAt: 100)
        #expect(attachment.slotHeld)
        #expect(attachment.poolGuestKey == "tart:anvil-mac-node")
        #expect(attachment.lastUsedAt == 100, "last use defaults to the attach time")

        attachment.slotHeld = false
        #expect(!attachment.slotHeld,
                "a second release must be able to see the first one happened")
    }

    @Test("who started the guest is recorded, because it is what licenses stopping it")
    func startedByThisAgentIsRecorded() {
        let found = GuestAttachment(machine: guestMachine, handle: "gst-a", provider: "tart",
                                    name: "n", localSocket: "/tmp/a.sock",
                                    startedByThisAgent: false, attachedAt: 0)
        #expect(!found.startedByThisAgent,
                "a guest found already running is never stopped to free a slot")
    }
}
