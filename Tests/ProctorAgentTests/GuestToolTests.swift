import Foundation
import Testing
import ProctorCore
@testable import ProctorAgent

// PRO-0059 — proctor_guest, the lifecycle tool.
//
// The parsers and the lane derivation are already proved in Core. What is
// proved here is the surface: the catalogue states the ceiling; a guest
// handle is refused by name from every window-taking path; list / status /
// start / stop / clone go through an injected adapter and never provision;
// a missing CLI is a named refusal rather than an empty listing; mutating
// actions land on the trail.

final class FakeGuestProvider: GuestProvider, @unchecked Sendable {
    let id: String
    var records: [GuestRecord]
    var calls: [(String, String)] = []
    var failNext: GuestProviderError?

    init(id: String, records: [GuestRecord]) {
        self.id = id
        self.records = records
    }

    func list() async throws -> [GuestRecord] {
        try throwIfPlanted()
        calls.append(("list", ""))
        return records
    }

    func status(name: String) async throws -> GuestRecord {
        try throwIfPlanted()
        calls.append(("status", name))
        guard let match = records.first(where: { $0.name == name }) else {
            throw GuestProviderError.notFound(name: name, provider: id)
        }
        return match
    }

    func start(name: String) async throws -> GuestRecord {
        try throwIfPlanted()
        return try mutate(name, action: "start", state: "running", running: true)
    }

    func stop(name: String) async throws -> GuestRecord {
        try throwIfPlanted()
        return try mutate(name, action: "stop", state: "stopped", running: false)
    }

    func clone(name: String, as newName: String) async throws -> GuestRecord {
        try throwIfPlanted()
        calls.append(("clone", "\(name)->\(newName)"))
        guard let source = records.first(where: { $0.name == name }) else {
            throw GuestProviderError.notFound(name: name, provider: id)
        }
        let copy = GuestRecord(name: newName, provider: id, state: source.state,
                               running: source.running, platform: source.platform)
        records.append(copy)
        return copy
    }

    private func mutate(_ name: String, action: String, state: String,
                        running: Bool) throws -> GuestRecord {
        calls.append((action, name))
        guard let index = records.firstIndex(where: { $0.name == name }) else {
            throw GuestProviderError.notFound(name: name, provider: id)
        }
        records[index].state = state
        records[index].running = running
        return records[index]
    }

    private func throwIfPlanted() throws {
        if let failNext {
            self.failNext = nil
            throw failNext
        }
    }
}

@Suite("PRO-0059 · the guest tool surface")
struct GuestToolSurfaceTests {

    @Test("proctor_guest is in the catalogue and states its ceiling")
    func toolSurfaceIsCoherent() throws {
        #expect(ToolCatalogue.all.count == 21)
        let spec = try #require(ToolCatalogue.spec(named: "proctor_guest"))
        #expect(!spec.readOnly)
        #expect(spec.destructive)
        #expect(spec.description.contains("guest lane, not a window lane"))
        #expect(spec.description.contains("Nothing here provisions"))
        #expect(spec.description.contains("grant-once"))
        #expect(spec.description.contains("Sequoia"))
        let actions = spec.inputSchema["properties"]?["action"]?["enum"]?
            .arrayValue?.compactMap(\.stringValue) ?? []
        #expect(Set(actions) == ["list", "status", "start", "stop", "clone"])
    }

    @Test("a guest handle is refused by name wherever a window handle is expected")
    func guestHandleIsRefusedAtTheWindowSeam() async throws {
        let session = Session(ax: FakeAX(bundleId: "com.example.fake"),
                              capture: FakeCapture(), secureInputProbe: { false })
        let handle = GuestHandle.id(provider: "lume", name: "sequoia-seed")
        #expect(GuestHandle.isGuestHandle(handle))
        do {
            _ = try await session.snapshot(window: handle,
                                           options: Session.SnapshotOptions(),
                                           sinceRevision: Int?.none)
            Issue.record("a guest handle must not resolve as a window")
        } catch let error as AgentError {
            #expect(error.message.contains("guest handle"))
            #expect(!error.message.contains("no window with handle"))
            let remedy = try #require(error.remedy)
            #expect(remedy.contains("proctor_guest"))
            #expect(remedy.contains("different machine"))
        }
    }

    @Test("an ordinary unknown window still reports as an unknown window")
    func ordinaryHandlesAreUnaffected() async throws {
        let session = Session(ax: FakeAX(bundleId: "com.example.fake"),
                              capture: FakeCapture(), secureInputProbe: { false })
        do {
            _ = try await session.snapshot(window: "w-nope",
                                           options: Session.SnapshotOptions(),
                                           sinceRevision: Int?.none)
            Issue.record("an unknown window must still fail")
        } catch let error as AgentError {
            #expect(error.code == .windowNotFound)
            #expect(!error.message.contains("guest handle"))
            #expect(!error.message.contains("iOS device handle"))
        }
    }
}

@Suite("PRO-0059 · lifecycle against an injected adapter")
struct GuestLifecycleWiringTests {

    private func session(providers: [any GuestProvider]) async -> (Session, AuditCollector) {
        let session = Session(ax: FakeAX(bundleId: "com.example.fake"),
                              capture: FakeCapture(), secureInputProbe: { false })
        await session.setGuestProviders(providers)
        let audit = AuditCollector()
        await session.setAuditSink(audit.sink)
        await session.setDrawsHUD(false)
        return (session, audit)
    }

    private var sequoia: GuestRecord {
        GuestRecord(name: "sequoia-seed", provider: "lume",
                    state: "stopped", running: false, platform: .macos)
    }

    @Test("list returns handles, capabilities, and does not start anything")
    func listTouchesNothing() async throws {
        let lume = FakeGuestProvider(id: "lume", records: [sequoia])
        let (session, _) = await session(providers: [lume])
        let result = try await session.guest(action: "list", guest: nil,
                                             provider: nil, newName: nil)
        let guests = result["guests"]?.arrayValue ?? []
        #expect(guests.count == 1)
        #expect(guests[0].objectValue?["name"]?.stringValue == "sequoia-seed")
        #expect(guests[0].objectValue?["handle"]?.stringValue?.hasPrefix("gst-") == true)
        #expect(result["capabilities"] != nil)
        #expect(result["note"]?.stringValue?.contains("does not already exist") == true)
        #expect(lume.calls.map(\.0) == ["list"])
    }

    @Test("start changes the power state, re-reads, and lands on the trail")
    func startIsAudited() async throws {
        let lume = FakeGuestProvider(id: "lume", records: [sequoia])
        let (session, audit) = await session(providers: [lume])
        let result = try await session.guest(action: "start", guest: "sequoia-seed",
                                             provider: nil, newName: nil)
        #expect(result["guest"]?.objectValue?["running"]?.boolValue == true)
        #expect(result["machine"]?.objectValue?["tier"]?.stringValue == "native")
        #expect(result["changed"]?.boolValue == true)
        #expect(lume.calls.map(\.0).contains("start"))
        #expect(audit.records.contains { $0.tool == AuditTool.guestStart && $0.outcome == "ok" })
    }

    @Test("clone copies and does not invent a guest that was not there")
    func cloneRequiresASource() async throws {
        let lume = FakeGuestProvider(id: "lume", records: [sequoia])
        let (session, audit) = await session(providers: [lume])
        let result = try await session.guest(action: "clone", guest: "sequoia-seed",
                                             provider: nil, newName: "sequoia-copy")
        #expect(result["guest"]?.objectValue?["name"]?.stringValue == "sequoia-copy")
        #expect(result["source"]?.objectValue?["name"]?.stringValue == "sequoia-seed")
        #expect(result["note"]?.stringValue?.contains("granted") == true)
        #expect(audit.records.contains { $0.tool == AuditTool.guestClone && $0.outcome == "ok" })

        await #expect(throws: AgentError.self) {
            _ = try await session.guest(action: "clone", guest: "no-such",
                                        provider: nil, newName: "x")
        }
    }

    @Test("a name held by two providers is refused rather than guessed")
    func ambiguityIsRefused() async throws {
        let a = GuestRecord(name: "box", provider: "lume",
                            state: "stopped", running: false, platform: .linux)
        let b = GuestRecord(name: "box", provider: "prlctl",
                            state: "stopped", running: false, platform: .windows)
        let (session, _) = await session(providers: [
            FakeGuestProvider(id: "lume", records: [a]),
            FakeGuestProvider(id: "prlctl", records: [b])
        ])
        do {
            _ = try await session.guest(action: "status", guest: "box",
                                        provider: nil, newName: nil)
            Issue.record("an ambiguous name must not resolve")
        } catch let error as AgentError {
            #expect(error.message.contains("2 guests match"))
            #expect(error.remedy?.contains("provider") == true)
        }
        let picked = try await session.guest(action: "status", guest: "box",
                                             provider: "prlctl", newName: nil)
        #expect(picked["guest"]?.objectValue?["provider"]?.stringValue == "prlctl")
    }

    @Test("neither CLI is a named refusal, not an empty listing")
    func missingProvidersAreRefused() async throws {
        let session = Session(ax: FakeAX(bundleId: "com.example.fake"),
                              capture: FakeCapture(),
                              tools: ToolProbes(
                                lume: ToolProbe(probe: {
                                    ToolPresence(tool: "lume", available: false)
                                }, presentTTL: 300, absentTTL: 300),
                                prlctl: ToolProbe(probe: {
                                    ToolPresence(tool: "prlctl", available: false)
                                }, presentTTL: 300, absentTTL: 300)),
                              secureInputProbe: { false })
        await session.setAuditSink({ _ in })
        do {
            _ = try await session.guest(action: "list", guest: nil,
                                        provider: nil, newName: nil)
            Issue.record("a machine with neither CLI must not look like an empty fleet")
        } catch let error as AgentError {
            #expect(error.code == .notImplemented)
            #expect(error.message.contains("lume"))
            #expect(error.message.contains("prlctl"))
            #expect(error.remedy?.contains("never install") == true)
        }
    }

    @Test("list without a guest argument is the default and does not provision")
    func listDoesNotNeedAName() async throws {
        let lume = FakeGuestProvider(id: "lume", records: [])
        let (session, audit) = await session(providers: [lume])
        let result = try await session.guest(action: "list", guest: nil,
                                             provider: nil, newName: nil)
        #expect(result["count"]?.doubleValue == 0)
        #expect(audit.records.isEmpty)
    }
}

@Suite("PRO-0059 · guest handles")
struct GuestHandleTests {

    @Test("the same (provider, name) always produces the same handle")
    func handleIsStable() {
        let a = GuestHandle.id(provider: "lume", name: "sequoia-seed")
        let b = GuestHandle.id(provider: "lume", name: "sequoia-seed")
        #expect(a == b)
        #expect(a.hasPrefix("gst-"))
        #expect(a != GuestHandle.id(provider: "prlctl", name: "sequoia-seed"))
        #expect(a != GuestHandle.id(provider: "lume", name: "sequoia-copy"))
    }

    @Test("a record's handle matches the namespace")
    func recordCarriesItsHandle() throws {
        let record = GuestRecord(name: "Windows 11", provider: "prlctl",
                                 state: "invalid", running: false, platform: .windows)
        #expect(record.handle.hasPrefix("gst-"))
        let encoded = try JSONValue.encode(record)
        #expect(encoded.objectValue?["handle"]?.stringValue == record.handle)
    }
}
