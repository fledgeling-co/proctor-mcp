import Foundation
import Testing
import ProctorCore
@testable import ProctorAgent

// PRO-0056 — a run says which machine it is on.
//
// This is the disclosure spine, and it lands before any routing does. PRO-0051
// rejected automatic fallback because it "hands back a verdict that looks fine
// and measures the plumbing"; routing a batch into a guest is the same move, and
// it is honest only once every surface a reader consults already says which
// machine answered. So what is proved here is coverage, not behaviour: the act
// result, the determinism report, the audit trail and the doctor each carry it,
// and the default is still the host so nothing that existed before this changes.
@Suite("PRO-0056 · a run names its machine")
struct MachineDisclosureWiringTests {

    private static let target = "com.example.target"

    private func harness(machine: Machine? = nil) async throws
        -> (session: Session, ax: FakeAX, audit: AuditCollector) {
        let ax = FakeAX(bundleId: Self.target)
        let session = Session(ax: ax, capture: FakeCapture(), secureInputProbe: { false })
        let audit = AuditCollector()
        await session.setAuditSink(audit.sink)
        await session.setDrawsHUD(false)
        if let machine { await session.setMachine(machine) }
        _ = try await session.attachResolved(bundleId: Self.target, pid: nil, name: nil)
        return (session, ax, audit)
    }

    // A macOS guest running a full Proctor, so it observes natively. The tier is
    // named rather than defaulted because `Machine` gives it no default: see
    // PRO-0057 for why a forgotten tier would be worse than an absent one.
    private static let guestMachine = Machine(kind: .guest, name: "sequoia-seed",
                                              provider: "lume", platform: .macos,
                                              tier: .native)

    // MARK: - The default does not move

    @Test("a session nobody told is on this Mac")
    func theDefaultIsTheHost() async throws {
        let h = try await harness()
        let machine = await h.session.machine
        #expect(machine == .host)
        #expect(machine.isGuest == false)
    }

    @Test("the host says which platform it is, rather than leaving it to be assumed")
    func theHostNamesItsPlatform() {
        // A reader comparing a host result with a guest one should not have to
        // know that the host is always macOS in order to compare them.
        #expect(Machine.host.platform == .macos)
    }

    // MARK: - Every surface carries it

    @Test("an act result names the machine it ran on")
    func actResultCarriesTheMachine() async throws {
        let h = try await harness(machine: Self.guestMachine)
        let result = try await h.session.act(window: h.ax.window.id,
                                             steps: [ActionStep(kind: .press, node: "node-1")],
                                             settle: .default, foreground: false,
                                             captureEach: false, diffEach: false, record: nil)
        let machine = result["machine"]?.objectValue
        #expect(machine?["kind"]?.stringValue == "guest")
        #expect(machine?["name"]?.stringValue == "sequoia-seed")
        #expect(machine?["provider"]?.stringValue == "lume")
    }

    @Test("a run in which every step refused still names its machine")
    func arefusedRunStillNamesItsMachine() async throws {
        // The case the field exists for, and the same argument `backend` makes:
        // a run whose steps all refused carries no per-step evidence at all, so
        // the run-level field is the only thing that can place it.
        let h = try await harness(machine: Self.guestMachine)
        let result = try await h.session.act(window: h.ax.window.id,
                                             steps: [ActionStep(kind: .click, node: "node-1")],
                                             settle: .default, foreground: false,
                                             captureEach: false, diffEach: false, record: nil)
        #expect(result["completed"]?.intValue == 0)
        #expect(result["machine"]?.objectValue?["kind"]?.stringValue == "guest")
    }

    @Test("the audit trail writes the machine on every step, always")
    func theTrailCarriesTheMachine() async throws {
        let h = try await harness(machine: Self.guestMachine)
        _ = try await h.session.act(window: h.ax.window.id,
                                    steps: [ActionStep(kind: .press, node: "node-1")],
                                    settle: .default, foreground: false,
                                    captureEach: false, diffEach: false, record: nil)
        let rows = h.audit.records.filter { $0.kind != nil }
        #expect(rows.isEmpty == false)
        for row in rows { #expect(row.mach == "guest:sequoia-seed") }
    }

    @Test("a host run writes host rather than writing nothing")
    func theTrailIsExplicitAboutTheHost() async throws {
        // Absence would be unambiguous today, since every row written before
        // guests existed was a host row. It is written anyway, so that a later
        // build which forgot to set it for a guest is distinguishable from an
        // older honest one rather than reading as the host.
        let h = try await harness()
        _ = try await h.session.act(window: h.ax.window.id,
                                    steps: [ActionStep(kind: .press, node: "node-1")],
                                    settle: .default, foreground: false,
                                    captureEach: false, diffEach: false, record: nil)
        let rows = h.audit.records.filter { $0.kind != nil }
        #expect(rows.isEmpty == false)
        for row in rows { #expect(row.mach == "host") }
    }

    @Test("the doctor says which machine every other answer in it is about")
    func theDoctorNamesTheMachine() async throws {
        let h = try await harness(machine: Self.guestMachine)
        let report = await h.session.doctor(verbose: false)
        #expect(report.machine?.kind == .guest)
        #expect(report.machine?.name == "sequoia-seed")
    }

    // MARK: - The words

    @Test("the audit token is one stable token, not a sentence")
    func theAuditTokenIsStable() {
        // The trail is grepped and diffed, so this must not gain or lose clauses
        // with whatever happened to be known when the row was written.
        #expect(Machine.host.auditToken == "host")
        #expect(Self.guestMachine.auditToken == "guest:sequoia-seed")
        #expect(Machine(kind: .guest, tier: .native).auditToken == "guest:unnamed")
    }

    @Test("the panel's phrase degrades by dropping clauses, never by printing an absence")
    func theLineDegradesGracefully() {
        #expect(Machine.host.line == "this Mac")
        #expect(Self.guestMachine.line == "sequoia-seed · macos · lume")
        // A guest whose provider was never established says less, and says
        // nothing about nil.
        let bare = Machine(kind: .guest, name: "win11", tier: .delegated)
        #expect(bare.line == "win11")
        #expect(bare.line.contains("nil") == false)
    }

    // MARK: - Records written before this existed

    @Test("a result with no machine still decodes, so an older record is not lost")
    func absentMachineDecodes() throws {
        let json = """
        {"window":"w-1","steps":[],"completed":0,"backend":"native"}
        """
        let decoded = try JSONDecoder().decode(ActResult.self, from: Data(json.utf8))
        #expect(decoded.machine == nil)
        #expect(decoded.backend == .native)
    }

    @Test("machine survives a round trip, since it goes out on the wire")
    func machineRoundTrips() throws {
        let encoded = try JSONEncoder().encode(Self.guestMachine)
        let decoded = try JSONDecoder().decode(Machine.self, from: encoded)
        #expect(decoded == Self.guestMachine)
    }
}
