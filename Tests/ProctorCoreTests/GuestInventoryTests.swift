import Foundation
import Testing
@testable import ProctorCore

// PRO-0058 — guest providers, the deciding half.
//
// Everything here is bytes in, records out. Neither lume nor prlctl is run.
// The prlctl fixtures are the shapes measured on this machine against
// Parallels Desktop 26.4.0; the lume fixtures follow the same field names
// the project's own docs use, because there is no lume binary here to
// measure against.

@Suite("PRO-0058 · platform and power")
struct GuestInferenceTests {

    @Test("a listing that names Windows is windows, even when the name is noisy")
    func windowsWins() {
        #expect(GuestPlatform.infer(os: "win-11", name: nil) == .windows)
        #expect(GuestPlatform.infer(os: nil, name: "Windows 11") == .windows)
        #expect(GuestPlatform.infer(os: "-", name: "Win11 ARM") == .windows)
    }

    @Test("linux words are recognised, and a dash is not a guess")
    func linuxAndAbsence() {
        #expect(GuestPlatform.infer(os: "ubuntu-24.04", name: nil) == .linux)
        #expect(GuestPlatform.infer(os: nil, name: "debian-seed") == .linux)
        #expect(GuestPlatform.infer(os: "-", name: nil) == nil)
        #expect(GuestPlatform.infer(os: nil, name: nil) == nil)
        #expect(GuestPlatform.infer(os: "something-custom", name: "box-1") == nil)
    }

    @Test("darwin is macOS, not Windows — the substring trap, pinned")
    func darwinIsNotWindows() {
        // PRO-0076. The Windows branch used to test `hay.contains("win")`, and
        // **dar-win** contains "win". Every macOS guest whose provider named
        // its platform `darwin` — which is the word tart prints — came back
        // `.windows`, took the delegated tier, and lost the accessibility tree
        // and the frame-status channel it actually has.
        #expect(GuestPlatform.infer(os: "darwin", name: nil) == .macos)
        #expect(GuestPlatform.infer(os: "Darwin", name: nil) == .macos)
        #expect(GuestPlatform.infer(os: "darwin", name: "anvil-mac-node") == .macos)
        // And the word that genuinely is Windows still is, in every spelling
        // the original cases covered.
        #expect(GuestPlatform.infer(os: "win-11", name: nil) == .windows)
        #expect(GuestPlatform.infer(os: "windows", name: nil) == .windows)
        #expect(GuestPlatform.infer(os: nil, name: "Win11 ARM") == .windows)
    }

    @Test("macOS guests are recognised by family and by release name")
    func macosWords() {
        #expect(GuestPlatform.infer(os: "macOS", name: nil) == .macos)
        #expect(GuestPlatform.infer(os: nil, name: "sequoia-seed") == .macos)
        #expect(GuestPlatform.infer(os: "sonoma", name: nil) == .macos)
        #expect(GuestPlatform.infer(os: nil, name: "tahoe-dev") == .macos)
    }

    @Test("only known running words count as running")
    func powerIsFailClosed() {
        #expect(GuestPower.isRunning("running"))
        #expect(GuestPower.isRunning("started"))
        #expect(!GuestPower.isRunning("stopped"))
        #expect(!GuestPower.isRunning("paused"))
        #expect(!GuestPower.isRunning("suspended"))
        #expect(!GuestPower.isRunning("invalid"))
        #expect(!GuestPower.isRunning("something-new"))
    }

    @Test("a macOS guest is native; anything else is delegated")
    func machineTierIsFailClosed() {
        let mac = GuestRecord(name: "sequoia-seed", provider: "lume",
                              state: "stopped", running: false, platform: .macos)
        #expect(mac.machine.tier == .native)
        #expect(mac.machine.kind == .guest)
        #expect(mac.machine.provider == "lume")

        let linux = GuestRecord(name: "ubuntu-1", provider: "lume",
                                state: "running", running: true, platform: .linux)
        #expect(linux.machine.tier == .delegated)

        let unknown = GuestRecord(name: "box", provider: "prlctl",
                                  state: "stopped", running: false, platform: nil)
        #expect(unknown.machine.tier == .delegated)
    }
}

@Suite("PRO-0058 · lume listings")
struct LumeInventoryTests {

    @Test("an array of objects is the happy path")
    func jsonArray() throws {
        let data = Data("""
        [{"name":"sequoia-seed","os":"macOS","status":"stopped"},
         {"name":"ubuntu-1","os":"linux","status":"running","ip":"192.168.64.2"}]
        """.utf8)
        let records = try LumeInventory.parse(data)
        #expect(records.map(\.name) == ["sequoia-seed", "ubuntu-1"])
        #expect(records[0].platform == .macos)
        #expect(records[0].running == false)
        #expect(records[1].platform == .linux)
        #expect(records[1].running == true)
        #expect(records[1].ip == "192.168.64.2")
        #expect(records.allSatisfy { $0.provider == "lume" })
    }

    @Test("a wrapper object and a single object both decode")
    func wrappedAndSingle() throws {
        let wrapped = Data("""
        {"vms":[{"name":"box","status":"stopped"}]}
        """.utf8)
        #expect(try LumeInventory.parse(wrapped).map(\.name) == ["box"])

        let single = Data("""
        {"name":"only","os":"macOS","state":"running"}
        """.utf8)
        let one = try LumeInventory.parse(single)
        #expect(one.count == 1)
        #expect(one[0].running == true)
        #expect(one[0].platform == .macos)
    }

    @Test("a table listing still works when the build printed text")
    func tableFallback() throws {
        let text = """
        NAME           OS      STATUS
        sequoia-seed   macOS   stopped
        ubuntu-1       linux   running
        """
        let records = try LumeInventory.parse(Data(text.utf8))
        #expect(records.map(\.name) == ["sequoia-seed", "ubuntu-1"])
        #expect(records[0].platform == .macos)
        #expect(records[1].running == true)
    }

    @Test("empty output is an empty list, not an error")
    func emptyIsEmpty() throws {
        #expect(try LumeInventory.parse(Data()).isEmpty)
        #expect(try LumeInventory.parse(Data("   \n".utf8)).isEmpty)
    }

    @Test("a row without a name is dropped rather than invented")
    func namelessIsDropped() throws {
        let data = Data("""
        [{"os":"macOS","status":"running"},{"name":"kept","status":"stopped"}]
        """.utf8)
        #expect(try LumeInventory.parse(data).map(\.name) == ["kept"])
    }
}

@Suite("PRO-0058 · prlctl listings")
struct PrlctlInventoryTests {

    @Test("the short listing measured on Parallels 26.4.0")
    func shortListing() throws {
        // Captured from `prlctl list -a -j` on this machine, 2026-08-17.
        let data = Data("""
        [{"uuid":"01732d18-5897-4550-b905-6fb947678c68","status":"invalid",
          "ip_configured":"-","name":"Windows 11"}]
        """.utf8)
        let records = try PrlctlInventory.parse(data)
        #expect(records.count == 1)
        #expect(records[0].name == "Windows 11")
        #expect(records[0].provider == "prlctl")
        #expect(records[0].state == "invalid")
        #expect(records[0].running == false)
        #expect(records[0].platform == .windows)
        #expect(records[0].identifier == "01732d18-5897-4550-b905-6fb947678c68")
        #expect(records[0].ip == nil)
    }

    @Test("the info listing uses ID / Name / State / OS")
    func infoListing() throws {
        let data = Data("""
        [{"ID":"01732d18-5897-4550-b905-6fb947678c68","Name":"Windows 11",
          "State":"running","OS":"win-11","ip_configured":"10.211.55.4"}]
        """.utf8)
        let records = try PrlctlInventory.parse(data)
        #expect(records[0].running == true)
        #expect(records[0].platform == .windows)
        #expect(records[0].ip == "10.211.55.4")
        #expect(records[0].identifier == "01732d18-5897-4550-b905-6fb947678c68")
    }

    @Test("a Linux Parallels guest is delegated")
    func linuxGuestIsDelegated() throws {
        let data = Data("""
        [{"uuid":"aaaa","name":"Ubuntu 24.04","status":"stopped","dist":"ubuntu"}]
        """.utf8)
        let records = try PrlctlInventory.parse(data)
        #expect(records[0].platform == .linux)
        #expect(records[0].machine.tier == .delegated)
    }
}

@Suite("PRO-0058 · guest lane")
struct GuestLaneTests {

    private func row(_ tool: String, _ usability: ToolUsability) -> ToolPresence {
        ToolPresence(tool: tool, available: usability != .unusable, path: "/x/\(tool)",
                     usability: usability, evidence: .presence)
    }

    private var grants: [DoctorReport.Grant] {
        [DoctorReport.Grant(name: "Accessibility", state: .granted, required: true, howToFix: ""),
         DoctorReport.Grant(name: "Screen Recording", state: .granted, required: true, howToFix: "")]
    }

    @Test("either provider is enough")
    func eitherProviderIsEnough() {
        let lumeOnly = Toolchain.lanes(tools: [row("lume", .usable)],
                                       grants: grants, secondLane: .off, cuaLaneSelected: false)
        #expect(lumeOnly.first { $0.lane == "guest" }?.state == "ready")

        let prlOnly = Toolchain.lanes(tools: [row("prlctl", .usable)],
                                      grants: grants, secondLane: .off, cuaLaneSelected: false)
        #expect(prlOnly.first { $0.lane == "guest" }?.state == "ready")
    }

    @Test("both missing is unavailable, and the note names the grant-once recipe")
    func bothMissing() {
        let lanes = Toolchain.lanes(tools: [], grants: grants,
                                    secondLane: .off, cuaLaneSelected: false)
        let guest = lanes.first { $0.lane == "guest" }!
        #expect(guest.state == "unavailable")
        #expect(guest.blockers.isEmpty == false)
        #expect(guest.note?.contains("clone") == true)
        // PRO-0094. Bound to the constant, not to the word "Sequoia" that the
        // old over-claim ended on. See GuestNoteSourceTests for why there is
        // exactly one source for this sentence.
        #expect(guest.note?.contains(GuestNotes.tahoeRendering) == true)
        #expect(guest.note?.contains("verify against Sequoia") != true)
    }

    @Test("presence is enough for both CLIs — a health check does not run them")
    func presenceSettlesTheCLIs() throws {
        for tool in ["lume", "prlctl"] {
            let row = try Toolchain.row(entry: #require(Toolchain.entry(for: tool)),
                                        facts: ToolFacts(located: ToolPresence(
                                        tool: tool, available: true, path: "/x/\(tool)")))
            #expect(row.usability == .usable)
            #expect(row.evidence == .presence)
        }
    }
}

@Suite("PRO-0060 · reaching a guest")
struct GuestReachTests {

    private let home = "/Users/tester"
    private let handle = "gst-abc"

    private func decide(platform: MachinePlatform?, tier: WitnessTier,
                        host: String = "box.local", user: String? = "luke",
                        remote: String? = nil, local: String? = nil,
                        kind: Machine.Kind = .guest) -> GuestReachDecision {
        let machine = Machine(kind: kind, name: "box", provider: "lume",
                              platform: platform, tier: tier)
        return GuestReach.decide(machine: machine, host: host, user: user,
                                 remoteSocket: remote, localSocket: local,
                                 handle: handle, home: home)
    }

    @Test("a native macOS guest produces a StreamLocal recipe")
    func nativeMacProducesARecipe() throws {
        guard case .recipe(let reach) = decide(platform: .macos, tier: .native) else {
            Issue.record("expected a recipe"); return
        }
        #expect(reach.kind == .streamLocal)
        #expect(reach.host == "box.local")
        #expect(reach.user == "luke")
        #expect(reach.remoteSocket == GuestReach.defaultRemoteSocket)
        #expect(reach.localSocket.hasSuffix("/guests/\(handle).sock"))
        #expect(reach.socketOverride == reach.localSocket)
        #expect(reach.note.contains("does not open the tunnel"))
        #expect(reach.note.contains("Tailscale"))
        #expect(!reach.note.contains("ssh -L"))
    }

    @Test("a Linux guest is refused, and so is a delegated macOS one")
    func delegatedIsRefused() {
        guard case .refused(let why) = decide(platform: .linux, tier: .delegated) else {
            Issue.record("a Linux guest must not produce a socket recipe"); return
        }
        #expect(why.contains("Cua"))
        #expect(!why.contains("ssh -L"))
        guard case .refused(let windows) = decide(platform: .windows, tier: .delegated) else {
            Issue.record("a Windows guest must not produce a socket recipe"); return
        }
        #expect(windows.contains("Cua"))
        guard case .refused(let delegated) = decide(platform: .macos, tier: .delegated) else {
            Issue.record("a delegated macOS guest has no socket"); return
        }
        #expect(delegated.contains("delegated"))
    }

    @Test("the host itself is refused — there is nothing to forward onto")
    func theHostIsRefused() {
        guard case .refused(let why) = decide(platform: .macos, tier: .native, kind: .host) else {
            Issue.record("the host is already this Mac"); return
        }
        #expect(why.contains("already on this Mac"))
    }

    @Test("an empty host is refused; a supplied socket is honoured")
    func hostAndOverride() throws {
        guard case .refused(let why) = decide(platform: .macos, tier: .native, host: "  ") else {
            Issue.record("an empty host is not a target"); return
        }
        #expect(why.contains("host"))
        guard case .recipe(let reach) = decide(platform: .macos, tier: .native,
                                               remote: "/tmp/guest.sock",
                                               local: "/tmp/local.sock") else {
            Issue.record("expected a recipe"); return
        }
        #expect(reach.remoteSocket == "/tmp/guest.sock")
        #expect(reach.localSocket == "/tmp/local.sock")
    }

    @Test("the encoded recipe never carries a shell command")
    func noShellOnTheWire() throws {
        guard case .recipe(let reach) = decide(platform: .macos, tier: .native) else {
            Issue.record("expected a recipe"); return
        }
        let text = String(decoding: try JSONEncoder().encode(reach), as: UTF8.self)
        #expect(!text.contains("ssh -L"))
        #expect(!text.contains("ssh "))
        #expect(text.contains("PROCTOR_SOCKET") || text.contains("does not open"))
    }
}
