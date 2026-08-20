import Foundation
import Testing
import ProctorCore
@testable import ProctorAgent

// PRO-0076 — the attach and the pool, against injected seams.
//
// No VM, no socket, no tunnel. The link is a protocol with a fake, the provider
// is the existing `FakeGuestProvider`, and the scheduler takes an injected clock
// and sleeper — never a wall-clock wait in a queue test, which is the flake
// PRO-0053 and PRO-0054 both closed.

/// A link that records what it was asked to forward, and can be told to fail.
final class FakeGuestLink: GuestLink, @unchecked Sendable {
    let localSocket: String
    private let lock = NSLock()
    private var _forwarded: [String] = []
    var probeError: Error?
    var sendError: Error?
    /// What the guest answers with.
    var reply: JSONValue = .object(["from": .string("the guest")])

    init(localSocket: String = "/tmp/fake-guest.sock") { self.localSocket = localSocket }

    var forwarded: [String] { lock.lock(); defer { lock.unlock() }; return _forwarded }

    func probe() async throws {
        if let probeError { throw probeError }
    }

    func send(_ request: AgentRequest) async throws -> AgentResponse {
        record(request.tool)
        if let sendError { throw sendError }
        return AgentResponse(id: request.id, ok: true, result: reply)
    }

    /// Synchronous: NSLock is unavailable from an async context.
    private func record(_ tool: String) {
        lock.lock(); _forwarded.append(tool); lock.unlock()
    }

    /// **Yields, deliberately.** Closing a real socket is a suspension point, and
    /// a fake that never suspends makes the interleaving in
    /// `releaseGuestAttachment` unreachable — so a test for the idempotence latch
    /// would pass just as happily with the latch removed. Modelling the
    /// suspension is what lets the release race actually race.
    func close() async { await Task.yield() }
}

@Suite("PRO-0076 · attaching to a guest")
struct GuestAttachWiringTests {

    private static func macRecord(_ name: String, running: Bool = true) -> GuestRecord {
        GuestRecord(name: name, provider: "tart", state: running ? "running" : "stopped",
                    running: running, platform: .macos, identifier: name)
    }

    private func harness(records: [GuestRecord] = [macRecord("anvil-mac-node")])
        async throws -> (session: Session, provider: FakeGuestProvider,
                         link: FakeGuestLink, audit: AuditCollector, ax: FakeAX) {
        let ax = FakeAX(bundleId: "com.example.target")
        let session = Session(ax: ax, capture: FakeCapture(),
                              scheduler: RunScheduler.stoppedClock(),
                              secureInputProbe: { false })
        let provider = FakeGuestProvider(id: "tart", records: records)
        let link = FakeGuestLink()
        let audit = AuditCollector()
        await session.setAuditSink(audit.sink)
        await session.setDrawsHUD(false)
        await session.setGuestProviders([provider])
        await session.setGuestLinkFactory { _ in link }
        return (session, provider, link, audit, ax)
    }

    // MARK: - A1

    @Test("an attached session's calls go to the guest, and nothing runs on this Mac")
    func callsAreForwarded() async throws {
        let h = try await harness()
        _ = try await h.session.guest(action: "attach", guest: "anvil-mac-node",
                                      provider: nil, newName: nil)

        let request = AgentRequest(id: "1", tool: "proctor_act", arguments: .object([:]))
        let result = try await h.session.forwardToGuestIfAttached(request)

        #expect(result != nil, "an attached session must not fall through to host work")
        #expect(h.link.forwarded == ["proctor_act"])
        // The host's own accessibility engine was never asked to do anything.
        #expect(h.ax.performed.isEmpty,
                "the host agent actuates nothing on behalf of a guest session")
    }

    @Test("attaching points the session's machine at the guest, for this caller only")
    func machineFollowsTheAttachment() async throws {
        let h = try await harness()
        #expect(await h.session.machine == .host)
        _ = try await h.session.guest(action: "attach", guest: "anvil-mac-node",
                                      provider: nil, newName: nil)
        let machine = await h.session.machine
        #expect(machine.isGuest)
        #expect(machine.name == "anvil-mac-node")
        #expect(machine.tier == .native, "a macOS guest runs a full Proctor")

        // A different caller is untouched: one Session serves every client, so
        // an attach that moved a shared field would move everybody.
        let other = RunSessionIdentity(project: "other", connection: "bbbb", key: "999:1")
        let seen = await SessionIdentity.$current.withValue(other) {
            await h.session.machine
        }
        #expect(seen == .host, "another session must still be on this Mac")
    }

    @Test("the host keeps the tools that answer about this Mac")
    func hostOnlyToolsAreNotForwarded() async throws {
        let h = try await harness()
        _ = try await h.session.guest(action: "attach", guest: "anvil-mac-node",
                                      provider: nil, newName: nil)
        for tool in ["proctor_doctor", "proctor_guest", "proctor_policy", "proctor_queue"] {
            let request = AgentRequest(id: "x", tool: tool, arguments: .object([:]))
            let forwarded = try await h.session.forwardToGuestIfAttached(request)
            #expect(forwarded == nil, "\(tool) answers about this Mac and stays here")
        }
        #expect(h.link.forwarded.isEmpty)
    }

    @Test("a tool nobody listed forwards, rather than quietly running here")
    func forwardingIsADenylist() async throws {
        // The direction that matters. An allowlist of machine-facing tools fails
        // OPEN: add an actuation tool later, forget to list it, and it runs on
        // the host under a guest session — a verdict about the wrong machine.
        #expect(GuestForwarding.shouldForward("proctor_a_tool_added_next_year"))
        #expect(GuestForwarding.shouldForward("proctor_act"))
        #expect(GuestForwarding.shouldForward("proctor_snapshot"))
        #expect(!GuestForwarding.shouldForward("proctor_doctor"))

        // And every tool in the catalogue is either forwarded or deliberately
        // named, so the set cannot drift without this failing.
        for spec in ToolCatalogue.all where !GuestForwarding.shouldForward(spec.name) {
            #expect(GuestForwarding.hostOnly.contains(spec.name))
        }
    }

    // MARK: - A2

    @Test("a link that will not answer refuses the attach rather than attaching anyway")
    func aDeadLinkRefusesTheAttach() async throws {
        let h = try await harness()
        h.link.probeError = AgentError(code: .agentUnavailable, message: "connection refused")

        await #expect(throws: AgentError.self) {
            _ = try await h.session.guest(action: "attach", guest: "anvil-mac-node",
                                          provider: nil, newName: nil)
        }
        let attached = await h.session.currentAttachment
        #expect(attached == nil, "a failed probe must leave no attachment behind")
        // And the slot it took is back, so a guest that would not answer does
        // not leave a slot held by nothing.
        let snapshot = await h.session.runScheduler.snapshot()
        #expect(snapshot.active.isEmpty)
    }

    @Test("a link that fails mid-run refuses, names the guest, and runs nothing here")
    func aFailingLinkRefusesAndNamesTheGuest() async throws {
        let h = try await harness()
        _ = try await h.session.guest(action: "attach", guest: "anvil-mac-node",
                                      provider: nil, newName: nil)
        h.link.sendError = AgentError(code: .agentUnavailable, message: "broken pipe")

        let request = AgentRequest(id: "1", tool: "proctor_act", arguments: .object([:]))
        do {
            _ = try await h.session.forwardToGuestIfAttached(request)
            Issue.record("a failing link must refuse rather than fall back to this Mac")
        } catch let error as AgentError {
            #expect(error.message.contains("anvil-mac-node"), "the guest must be named")
            #expect(error.message.contains("Nothing ran on this Mac"))
            #expect(error.remedy?.contains("verdict about the wrong machine") == true)
        }
        #expect(h.ax.performed.isEmpty, "no step may reach the host actuator")
    }

    @Test("there is no code path that runs a guest session's batch on the host")
    func noFallbackBranchExists() throws {
        // A2 is an absence, and an absence needs a guard that fails when somebody
        // adds the branch back. The forward either returns the guest's answer or
        // throws; it never returns nil for a forwarding tool while attached.
        let source = try String(contentsOfFile:
            #filePath.replacingOccurrences(
                of: "Tests/ProctorAgentTests/GuestAttachWiringTests.swift",
                with: "Sources/ProctorAgent/Session/SessionGuest.swift"),
            encoding: .utf8)
        let forward = source.components(separatedBy: "func forwardToGuestIfAttached").last ?? ""
        let body = forward.components(separatedBy: "\n    func ").first ?? ""
        #expect(!body.isEmpty)
        #expect(!body.lowercased().contains("fallback"))
        #expect(body.contains("throw GuestLinkRefusal.unreachable"),
                "the failure path must refuse, and it must be visible here")
    }

    // MARK: - A4, over the wire

    @Test("a window id that came back from the guest is refused for another session")
    func guestHandlesAreScopedToTheirSession() async throws {
        let h = try await harness()
        _ = try await h.session.guest(action: "attach", guest: "anvil-mac-node",
                                      provider: nil, newName: nil)
        h.link.reply = .object(["windows": .array([
            .object(["id": .string("win:99:0"), "title": .string("Inside the guest")])
        ])])
        let request = AgentRequest(id: "1", tool: "proctor_apps", arguments: .object([:]))
        _ = try await h.session.forwardToGuestIfAttached(request)

        // The same id, used by a session that never attached to that guest.
        let other = RunSessionIdentity(project: "other", connection: "bbbb", key: "999:1")
        await SessionIdentity.$current.withValue(other) {
            do {
                _ = try await h.session.windowHandle("win:99:0")
                Issue.record("a guest's window id must not resolve for another session")
            } catch let error as AgentError {
                #expect(error.message.contains("anvil-mac-node"))
                #expect(error.message.contains("this Mac"))
            } catch {
                Issue.record("unexpected error: \(error)")
            }
        }
    }

    // MARK: - A9

    @Test("attaching a stopped guest starts it, through the audited path")
    func attachStartsAStoppedGuest() async throws {
        let h = try await harness(records: [Self.macRecord("anvil-mac-node", running: false)])
        let result = try await h.session.guest(action: "attach", guest: "anvil-mac-node",
                                               provider: nil, newName: nil)
        #expect(result["startedByProctor"]?.boolValue == true)
        #expect(h.provider.calls.contains { $0.0 == "start" && $0.1 == "anvil-mac-node" })
        // Recorded, not merely done: A9 says both stay gated and recorded.
        let records = h.audit.records
        #expect(records.contains { $0.tool == AuditTool.guestStart })
        #expect(records.contains { $0.tool == AuditTool.guestAttach })
    }

    @Test("attaching a running guest starts nothing")
    func attachDoesNotRestartARunningGuest() async throws {
        let h = try await harness()
        let result = try await h.session.guest(action: "attach", guest: "anvil-mac-node",
                                               provider: nil, newName: nil)
        #expect(result["startedByProctor"]?.boolValue == false)
        #expect(!h.provider.calls.contains { $0.0 == "start" })
    }

    @Test("detach stops only a guest this agent started")
    func detachStopsOnlyWhatItStarted() async throws {
        // Started here: stopped on the way out.
        let started = try await harness(records: [Self.macRecord("anvil-mac-node", running: false)])
        _ = try await started.session.guest(action: "attach", guest: "anvil-mac-node",
                                            provider: nil, newName: nil)
        let out = try await started.session.guest(action: "detach", guest: nil,
                                                  provider: nil, newName: nil)
        #expect(out["guestStopped"]?.boolValue == true)
        #expect(started.provider.calls.contains { $0.0 == "stop" })

        // Found running: left alone. Stopping a running VM discards its state.
        let found = try await harness()
        _ = try await found.session.guest(action: "attach", guest: "anvil-mac-node",
                                          provider: nil, newName: nil)
        let leftAlone = try await found.session.guest(action: "detach", guest: nil,
                                                      provider: nil, newName: nil)
        #expect(leftAlone["guestStopped"]?.boolValue == false)
        #expect(!found.provider.calls.contains { $0.0 == "stop" },
                "a guest a person started is never stopped to free a slot")
    }

    // MARK: - The platform refusal

    @Test("a guest whose platform the provider did not name is refused, not admitted")
    func unknownPlatformIsRefused() async throws {
        // nil platform is fail-CLOSED for actuation (it reads as delegated) and
        // fail-OPEN for the cap, because a delegated guest is not counted
        // against the macOS pool. A macOS VM admitted that way would boot
        // outside Apple's two with nothing noticing.
        let unknown = GuestRecord(name: "mystery", provider: "tart", state: "running",
                                  running: true, platform: nil, identifier: "mystery")
        let h = try await harness(records: [unknown])
        do {
            _ = try await h.session.guest(action: "attach", guest: "mystery",
                                          provider: nil, newName: nil)
            Issue.record("a guest of unknown platform must not take a pool slot")
        } catch let error as AgentError {
            // It is refused before the platform question, as a machine with no
            // Proctor inside — either refusal is correct, and neither admits it.
            #expect(error.code == .notImplemented || error.code == .invalidArguments)
        }
        let snapshot = await h.session.runScheduler.snapshot()
        #expect(snapshot.active.isEmpty, "nothing may hold a slot after that refusal")
    }

    @Test("a linux guest is refused: it has no Proctor inside to forward to")
    func delegatedGuestsAreNotAttachable() async throws {
        let linux = GuestRecord(name: "anvil-linux-node", provider: "tart", state: "running",
                                running: true, platform: .linux, identifier: "anvil-linux-node")
        let h = try await harness(records: [linux])
        await #expect(throws: AgentError.self) {
            _ = try await h.session.guest(action: "attach", guest: "anvil-linux-node",
                                          provider: nil, newName: nil)
        }
    }

    @Test("a session cannot attach twice")
    func oneMachineAtATime() async throws {
        let h = try await harness()
        _ = try await h.session.guest(action: "attach", guest: "anvil-mac-node",
                                      provider: nil, newName: nil)
        await #expect(throws: AgentError.self) {
            _ = try await h.session.guest(action: "attach", guest: "anvil-mac-node",
                                          provider: nil, newName: nil)
        }
    }

    @Test("detaching when nothing is attached is a refusal, not a silent success")
    func detachWithoutAttach() async throws {
        let h = try await harness()
        await #expect(throws: AgentError.self) {
            _ = try await h.session.guest(action: "detach", guest: nil,
                                          provider: nil, newName: nil)
        }
    }
}
