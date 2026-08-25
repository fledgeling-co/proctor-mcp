import Foundation
import Testing
@testable import ProctorCore

@Suite("Guest health: a heartbeat that tells a wedged agent from a stopped guest")
struct GuestHealthProbeTests {

    @Test("a socket that accepts and never answers is stalled, not healthy")
    func silenceIsNotHealth() {
        // CASE-0029 measured this on the host: SIGSTOP leaves the listener
        // bound, connect() succeeds, and the reply never comes. A probe that
        // only asks "did the socket accept me" calls that guest healthy, and a
        // runner then waits on it until its own deadline fires.
        let h = GuestHealthProbe.classify([.silent])
        #expect(h.status == .stalled)
        #expect(h.socketReachable,
                "the socket DID accept, and saying otherwise sends an operator to restart the wrong thing")
        #expect(h.pingLatencyMs == nil)
        #expect(h.diagnosticNote?.contains("restart the agent inside it") == true,
                "the note does not say which of the two things to restart")
    }

    @Test("nothing listening is unreachable, and says so with the reason")
    func refusedIsUnreachable() {
        let h = GuestHealthProbe.classify([.refused("no socket at /tmp/guest.sock")])
        #expect(h.status == .unreachable)
        #expect(!h.socketReachable)
        #expect(h.diagnosticNote?.contains("no socket at /tmp/guest.sock") == true)
        // The two failures must not collapse: unreachable and stalled have
        // different remedies, and a probe that reports one for the other has an
        // operator restarting a guest whose agent needed restarting, or the
        // reverse.
        #expect(h.status != GuestHealthProbe.classify([.silent]).status)
    }

    @Test("an attempt that could not be made is never read as the guest being dead")
    func indeterminateIsNotDeath() {
        let h = GuestHealthProbe.classify([.indeterminate("socket path too long for sun_path")])
        #expect(h.status == .degraded, "a host-side failure was reported as the guest's")
        #expect(h.diagnosticNote?.contains("about this host") == true)
        #expect(h.status != .unreachable)
    }

    @Test("one slow beat is a busy machine; a run of them is the guest")
    func latencyNeedsARun() {
        // A single sample over the threshold is noise on a machine running five
        // simulators. The verdict reads the whole run, so a probe cannot be
        // talked into `degraded` by one unlucky beat — and cannot miss a guest
        // that is slow every time.
        let oneSlow = GuestHealthProbe.classify([.answered(latencyMs: 4000),
                                                 .answered(latencyMs: 12)])
        #expect(oneSlow.status == .healthy)
        #expect(oneSlow.pingLatencyMs == 12)

        let allSlow = GuestHealthProbe.classify([.answered(latencyMs: 900),
                                                 .answered(latencyMs: 1100),
                                                 .answered(latencyMs: 1000)])
        #expect(allSlow.status == .degraded)
        #expect(allSlow.pingLatencyMs == 1000, "the mean of the run is what is reported")
        #expect(allSlow.diagnosticNote?.contains("mean 1000ms") == true)

        // And a single fast beat is healthy without needing a run, because
        // requiring one would report every first heartbeat as unknown.
        #expect(GuestHealthProbe.classify([.answered(latencyMs: 5)]).status == .healthy)
    }

    @Test("no heartbeat at all is unreachable, and says it measured nothing")
    func noAttemptIsNotAPass() {
        let h = GuestHealthProbe.classify([])
        #expect(h.status == .unreachable)
        #expect(h.diagnosticNote?.contains("nothing here is a fact about the guest") == true,
                "an unrun probe reported a verdict about the guest")
    }

    @Test("retrying is bounded, and only where waiting can change the answer")
    func retryIsBoundedAndReasoned() {
        // A wedged agent sometimes comes back, so silence is retried with a
        // widening gap. Nothing listening is not retried: waiting does not start
        // a guest, and a probe that retries forever turns a dead guest into a
        // hung runner — the fault it was added to prevent.
        #expect(GuestHealthProbe.retryDelayMs(after: .silent, attempt: 0) == 250)
        #expect(GuestHealthProbe.retryDelayMs(after: .silent, attempt: 1) == 500)
        #expect(GuestHealthProbe.retryDelayMs(after: .silent, attempt: 2) == 1000)
        #expect(GuestHealthProbe.retryDelayMs(after: .silent, attempt: 3) == nil,
                "the retry is unbounded, so a wedged guest holds the runner")
        #expect(GuestHealthProbe.retryDelayMs(after: .refused("gone"), attempt: 0) == nil)
        #expect(GuestHealthProbe.retryDelayMs(after: .answered(latencyMs: 3), attempt: 0) == nil)
    }

    @Test("a real socket answers, and a real one that goes quiet reads as stalled")
    func againstARealSocket() throws {
        // The classifier is exercised against beats a REAL socket produced,
        // rather than against beats a test invented. Two listeners: one that
        // answers, one that accepts and holds — which is what a stopped agent
        // looks like from outside.
        let answering = try ChaosListener(behaviour: .answer)
        defer { answering.stop() }
        let start = Date()
        let client = SocketClient(path: answering.path)
        client.ioTimeoutSeconds = 3
        try client.connect()
        let reply = try client.send(AgentRequest(id: "1", tool: "proctor_doctor",
                                                 arguments: .object([:])))
        client.disconnect()
        #expect(reply.ok)
        let healthy = GuestHealthProbe.classify(
            [.answered(latencyMs: Date().timeIntervalSince(start) * 1000)])
        #expect(healthy.status == .healthy)
        #expect(healthy.socketReachable)

        let quiet = try ChaosListener(behaviour: .silence)
        defer { quiet.stop() }
        let c2 = SocketClient(path: quiet.path)
        c2.ioTimeoutSeconds = 1
        try c2.connect()
        var beat: GuestHealthProbe.Beat = .indeterminate("not attempted")
        do {
            _ = try c2.send(AgentRequest(id: "2", tool: "proctor_doctor", arguments: .object([:])))
            beat = .answered(latencyMs: 0)
        } catch {
            // The connection succeeded and the reply did not come — which is the
            // whole distinction, and it is read off a real socket here rather
            // than asserted.
            beat = .silent
        }
        c2.disconnect()
        #expect(beat == .silent, "a listener that accepted and held did not read as silent")
        let stalled = GuestHealthProbe.classify([beat])
        #expect(stalled.status == .stalled)
        #expect(stalled.socketReachable)
    }

    @Test("the real lume listing parses, and a stopped guest is not reported running")
    func liveLumeListingParses() throws {
        // Read from the machine, not from a fixture: `lume ls --format json` as
        // it stood when this was written, with the one guest this Mac holds.
        // Nothing here starts, stops or removes anything.
        let json = Data("""
        [{"provisioningOperation":null,"cpuCount":4,
          "diskSize":{"allocated":27044630528,"total":107374182400},
          "display":"1024x768","downloadProgress":null,"networkMode":"nat","vncUrl":null,
          "ipAddress":null,"name":"proctor-guest","memorySize":8589934592,
          "status":"stopped","os":"macOS","sharedDirectories":null,
          "locationName":"home","sshAvailable":null}]
        """.utf8)
        let records = try LumeInventory.parse(json)
        #expect(records.count == 1)
        let guest = try #require(records.first)
        #expect(guest.name == "proctor-guest")
        #expect(guest.state == "stopped")
        #expect(!guest.running, "a stopped guest reported itself running")
        #expect(guest.platform == .macos)
        #expect(guest.handle.hasPrefix("gst-"))
        // A macOS guest is native tier because a full Proctor runs inside it;
        // anything else is delegated, which is the fail-closed direction.
        #expect(GuestAttachment.machine(for: guest).tier == .native)
        // And a guest with no IP has no reach yet — reporting one would send a
        // caller at an address that does not exist.
        #expect(guest.ip == nil)
    }
}
