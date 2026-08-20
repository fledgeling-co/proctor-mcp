import Testing
import Foundation
@testable import ProctorCore

// PRO-0029. The switches' catalogue, the precedence rule, and the store.
//
// Everything the feature decides is here, because everything it decides is pure.
// The window renders what these functions return; `Package.swift` declares no
// `ProctorUI` test target and there is no window server under `swift test`, so a
// rule written in a view body would be a rule this repo cannot prove.

// MARK: - The catalogue

@Suite("PRO-0029 switch catalogue")
struct SwitchCatalogueTests {

    @Test("The catalogue names exactly the nine runtime switches")
    func namesTheNine() {
        #expect(SwitchCatalogue.all.count == 9)
        #expect(Set(SwitchCatalogue.all.map(\.variable)) == [
            "PROCTOR_HUD", "PROCTOR_CURSOR", "PROCTOR_TAKEOVER", "PROCTOR_YIELD",
            "PROCTOR_YIELD_INPUT", "PROCTOR_TAKEOVER_INPUT", "PROCTOR_OVERLAY_CAPTURE",
            "PROCTOR_SECOND_LANE", "PROCTOR_ACTUATION"
        ])
    }

    @Test("Defaults: the four drawing switches are on, the other five are off")
    func defaults() {
        for aSwitch in SwitchCatalogue.all {
            #expect(aSwitch.defaultOn == (aSwitch.kind == .drawing),
                    "\(aSwitch.variable) default")
        }
        #expect(SwitchCatalogue.all.filter(\.defaultOn).count == 4)
    }

    /// Clause 11. The arithmetic the out-of-family gate caught: the first draft
    /// said six of eight applied at next start while also saying HUD alone was
    /// live, and eight minus one is seven.
    @Test("Exactly one switch applies live; the other eight need a fresh agent")
    func timingCount() {
        let live = SwitchCatalogue.all.filter { $0.timing == .live }
        #expect(live.map(\.variable) == ["PROCTOR_HUD"])
        #expect(SwitchCatalogue.all.filter { $0.timing == .nextStart }.count == 8)
    }

    /// Clause 20's testable half. `PROCTOR_YIELD_INPUT` is deliberately not a
    /// consent gate: it observes input and intercepts nothing, and a confirmation
    /// there would train people to click through the two that matter.
    @Test("Three switches require consent: the input block, the second lane, and overlay capture")
    func consentGates() {
        let gates = SwitchCatalogue.all.filter(\.requiresConsent).map(\.variable)
        #expect(gates.sorted() == ["PROCTOR_OVERLAY_CAPTURE", "PROCTOR_SECOND_LANE",
                                   "PROCTOR_TAKEOVER_INPUT"])
        #expect(!SwitchCatalogue.yieldInput.requiresConsent)
        // Every consent gate is off by default: a gate on a default-on switch
        // would be a confirmation nobody ever sees.
        for gate in SwitchCatalogue.all where gate.requiresConsent {
            #expect(!gate.defaultOn, "\(gate.variable) must be off by default")
        }
    }

    @Test("Only the two lane switches carry an on-value")
    func laneValues() {
        #expect(SwitchCatalogue.secondLane.onValue == "browser-use")
        #expect(SwitchCatalogue.actuation.onValue == "cua")
        for aSwitch in SwitchCatalogue.all where aSwitch.kind != .lane {
            #expect(aSwitch.onValue == nil, "\(aSwitch.variable) should have no on-value")
        }
    }
}

// MARK: - Drift

/// Clause 2. The guard against the failure that created this item.
///
/// Comparing two hand-typed strings catches nothing — both would be edited
/// together by whoever was already wrong. What catches drift is resolving through
/// the catalogue and comparing the ANSWER against the original function at the
/// call site, over the same dictionary. A switch that changes shape then reddens
/// the build instead of quietly disagreeing with a window.
@Suite("PRO-0029 catalogue cannot drift from the code")
struct SwitchCatalogueDriftTests {

    @Test("Variable names equal the constants the agent reads")
    func namesMatchConstants() {
        #expect(SwitchCatalogue.secondLane.variable == BrowserUseTool.laneVariable)
        #expect(SwitchCatalogue.actuation.variable == CuaDriverTool.laneEnv)
        #expect(SwitchCatalogue.secondLane.onValue == BrowserUseTool.binary)
        #expect(SwitchCatalogue.actuation.onValue == CuaDriverTool.laneValue)
    }

    /// Every value either side of each switch's boundary, answered twice: once
    /// through the catalogue and once by the function the agent actually calls.
    @Test("Resolving through the catalogue agrees with each original reader")
    func agreesWithOriginalReaders() {
        let probes: [String?] = [nil, "", " ", "0", "off", "false", "no", "1", "true",
                                 "on", "yes", "browser-use", "cua", "BROWSER-USE", "CUA",
                                 "nonsense"]
        for raw in probes {
            var env: [String: String] = [:]

            // The four OverlaySwitch-shaped ones.
            env = raw.map { ["PROCTOR_CURSOR": $0] } ?? [:]
            #expect(SwitchResolver.isOn(raw, for: SwitchCatalogue.cursor)
                    == OverlaySwitch.isOn("PROCTOR_CURSOR", in: env),
                    "PROCTOR_CURSOR on \(raw ?? "<unset>")")

            env = raw.map { ["PROCTOR_TAKEOVER": $0] } ?? [:]
            #expect(SwitchResolver.isOn(raw, for: SwitchCatalogue.takeover)
                    == Takeover.overlayEnabled(in: env),
                    "PROCTOR_TAKEOVER on \(raw ?? "<unset>")")

            // PROCTOR_YIELD and PROCTOR_YIELD_INPUT are compared against
            // ContentionMonitor in ProctorAgentTests, because that type lives in
            // the agent target and this one cannot see it.

            // The two opt-ins.
            env = raw.map { ["PROCTOR_TAKEOVER_INPUT": $0] } ?? [:]
            #expect(SwitchResolver.isOn(raw, for: SwitchCatalogue.takeoverInput)
                    == Takeover.blockEnabled(in: env),
                    "PROCTOR_TAKEOVER_INPUT on \(raw ?? "<unset>")")

            // The two lanes.
            env = raw.map { [BrowserUseTool.laneVariable: $0] } ?? [:]
            #expect(SwitchResolver.isOn(raw, for: SwitchCatalogue.secondLane)
                    == BrowserUseTool.enabled(environment: env),
                    "PROCTOR_SECOND_LANE on \(raw ?? "<unset>")")

            env = raw.map { [CuaDriverTool.laneEnv: $0] } ?? [:]
            #expect(SwitchResolver.isOn(raw, for: SwitchCatalogue.actuation)
                    == CuaDriverTool.laneSelected(env),
                    "PROCTOR_ACTUATION on \(raw ?? "<unset>")")
        }
    }
}

// MARK: - The parse table

@Suite("PRO-0029 parse table")
struct SwitchParseTests {

    @Test("An unset drawing switch is on; an unset anything-else is off")
    func unset() {
        for aSwitch in SwitchCatalogue.all {
            #expect(SwitchResolver.isOn(nil, for: aSwitch) == (aSwitch.kind == .drawing),
                    "\(aSwitch.variable) unset")
        }
    }

    @Test("An unrecognised value reads on for a drawing switch and off for the rest")
    func unrecognised() {
        for aSwitch in SwitchCatalogue.all {
            let expected: Bool
            switch aSwitch.kind {
            case .drawing:    expected = true      // OverlaySwitch: anything but an off-value
            case .capability: expected = true      // set, non-empty, not an off-value
            case .lane:       expected = false     // must equal the tool's own name
            }
            #expect(SwitchResolver.isOn("nonsense", for: aSwitch) == expected,
                    "\(aSwitch.variable) on \"nonsense\"")
        }
    }

    @Test("Every off-value turns every switch off")
    func offValues() {
        for aSwitch in SwitchCatalogue.all {
            for off in OverlaySwitch.offValues {
                #expect(!SwitchResolver.isOn(off, for: aSwitch), "\(aSwitch.variable)=\(off)")
                #expect(!SwitchResolver.isOn(" \(off.uppercased()) ", for: aSwitch),
                        "\(aSwitch.variable)=\(off) padded and upper")
            }
        }
    }

    /// Clause 6/7. The failure the brief warned a toggle can have: a control that
    /// writes `1` reads as enabled in a window and is off in the agent.
    @Test("A lane rejects every spelling but its own name")
    func lanesRejectBooleans() {
        for lane in [SwitchCatalogue.secondLane, SwitchCatalogue.actuation] {
            for wrong in ["1", "true", "on", "yes", "enabled"] {
                #expect(!SwitchResolver.isOn(wrong, for: lane), "\(lane.variable)=\(wrong)")
            }
            #expect(SwitchResolver.isOn(lane.onValue!, for: lane))
            #expect(SwitchResolver.isOn(lane.onValue!.uppercased(), for: lane))
        }
    }

    @Test("A control writes the value its own switch accepts")
    func onValueRoundTrips() {
        for aSwitch in SwitchCatalogue.all {
            #expect(SwitchResolver.isOn(SwitchResolver.onValue(for: aSwitch), for: aSwitch),
                    "\(aSwitch.variable) on-value")
            #expect(!SwitchResolver.isOn(SwitchResolver.offValue(for: aSwitch), for: aSwitch),
                    "\(aSwitch.variable) off-value")
        }
    }
}

// MARK: - Precedence

@Suite("PRO-0029 precedence")
struct SwitchPrecedenceTests {

    /// Clause 3.
    @Test("An ordinary switch takes the environment over a saved preference, and locks")
    func environmentWinsForOrdinary() {
        for aSwitch in SwitchCatalogue.all where aSwitch.kind != .capability {
            let on = SwitchResolver.onValue(for: aSwitch)
            let r = SwitchResolver.resolve(aSwitch,
                                           environment: [aSwitch.variable: on],
                                           saved: [aSwitch.variable: "0"])
            #expect(r.on, "\(aSwitch.variable) should follow the environment")
            #expect(r.source == .environment)
            #expect(r.locked, "\(aSwitch.variable) should lock when the environment set it")
        }
    }

    /// Clause 6.
    @Test("An environment off-value beats an on preference")
    func environmentOffBeatsSavedOn() {
        let r = SwitchResolver.resolve(SwitchCatalogue.cursor,
                                       environment: ["PROCTOR_CURSOR": "0"],
                                       saved: ["PROCTOR_CURSOR": "1"])
        #expect(!r.on)
        #expect(r.source == .environment)
        #expect(r.locked)
    }

    @Test("A saved preference is used when the environment is silent, and does not lock")
    func savedUsedWhenEnvironmentSilent() {
        let r = SwitchResolver.resolve(SwitchCatalogue.cursor,
                                       environment: [:], saved: ["PROCTOR_CURSOR": "0"])
        #expect(!r.on)
        #expect(r.source == .saved)
        #expect(!r.locked)
    }

    @Test("With neither source, every switch falls to its built-in default")
    func builtInDefault() {
        for aSwitch in SwitchCatalogue.all {
            let r = SwitchResolver.resolve(aSwitch, environment: [:], saved: [:])
            #expect(r.on == aSwitch.defaultOn, "\(aSwitch.variable)")
            #expect(r.source == .builtInDefault)
            #expect(!r.locked)
        }
    }

    /// Clause 4 — the out-of-family gate's finding, and the single most important
    /// test in this file.
    ///
    /// Under one blanket rule, `PROCTOR_TAKEOVER_INPUT=1` in the agent's launch
    /// environment creates the event tap that swallows a person's keyboard, and the
    /// lock rule then disables the only control that could turn it off.
    @Test("Off wins from either source for a capability switch, and it never locks")
    func capabilityOffAlwaysWins() {
        for aSwitch in SwitchCatalogue.capabilities {
            // Environment on, preference off -> OFF, and the person can still press it.
            let declined = SwitchResolver.resolve(aSwitch,
                                                  environment: [aSwitch.variable: "1"],
                                                  saved: [aSwitch.variable: "0"])
            #expect(!declined.on, "\(aSwitch.variable): a saved off must win")
            #expect(!declined.locked, "\(aSwitch.variable): a capability must never lock")
            #expect(declined.source == .saved,
                    "\(aSwitch.variable): the saved preference is what turned it off")

            // Environment on, nothing saved -> ON.
            let asked = SwitchResolver.resolve(aSwitch,
                                               environment: [aSwitch.variable: "1"], saved: [:])
            #expect(asked.on)
            #expect(!asked.locked)

            // Environment silent, preference on -> OFF. A preference cannot grant a
            // capability the launching context never asked for.
            let unasked = SwitchResolver.resolve(aSwitch,
                                                 environment: [:], saved: [aSwitch.variable: "1"])
            #expect(!unasked.on, "\(aSwitch.variable): a preference alone must not arm it")
            #expect(!unasked.locked)

            // Neither -> OFF.
            let neither = SwitchResolver.resolve(aSwitch, environment: [:], saved: [:])
            #expect(!neither.on)
        }
    }

    /// Clause 10.
    @Test("No capability switch ever reports itself locked, under any combination")
    func capabilitiesNeverLock() {
        let values: [String?] = [nil, "0", "1"]
        for aSwitch in SwitchCatalogue.capabilities {
            for env in values {
                for saved in values {
                    let r = SwitchResolver.resolve(
                        aSwitch,
                        environment: env.map { [aSwitch.variable: $0] } ?? [:],
                        saved: saved.map { [aSwitch.variable: $0] } ?? [:])
                    #expect(!r.locked,
                            "\(aSwitch.variable) env=\(env ?? "-") saved=\(saved ?? "-")")
                }
            }
        }
    }

    @Test("resolveAll returns every switch in catalogue order")
    func resolveAllOrder() {
        let all = SwitchResolver.resolveAll(environment: [:], saved: [:])
        #expect(all.map(\.variable) == SwitchCatalogue.all.map(\.variable))
    }
}

// MARK: - The effective environment

@Suite("PRO-0029 effective environment")
struct EffectiveEnvironmentTests {

    /// The mechanism by which a preference reaches the agent at all: the existing
    /// call sites keep reading a dictionary, and the dictionary changes.
    @Test("A saved preference reaches each original reader unchanged")
    func savedReachesTheReaders() {
        let saved = ["PROCTOR_CURSOR": "0",
                     BrowserUseTool.laneVariable: BrowserUseTool.binary,
                     CuaDriverTool.laneEnv: CuaDriverTool.laneValue]
        let env = SwitchResolver.effectiveEnvironment(processEnvironment: [:], saved: saved)

        #expect(!OverlaySwitch.isOn("PROCTOR_CURSOR", in: env))
        #expect(BrowserUseTool.enabled(environment: env))
        #expect(CuaDriverTool.laneSelected(env))
    }

    /// The bug this test exists for: a drawing switch reads UNSET as ON, so
    /// expressing "off" by removing the key would turn the thing on.
    @Test("Saving a drawing switch off writes an off-value rather than removing the key")
    func drawingOffIsWrittenNotRemoved() {
        for aSwitch in SwitchCatalogue.all where aSwitch.kind == .drawing {
            let env = SwitchResolver.effectiveEnvironment(
                processEnvironment: [:], saved: [aSwitch.variable: "0"])
            #expect(env[aSwitch.variable] != nil,
                    "\(aSwitch.variable) must be present and off, not absent")
            #expect(!OverlaySwitch.isOn(aSwitch.variable, in: env), "\(aSwitch.variable)")
        }
    }

    @Test("Declining a capability removes it, so no reader can see it set")
    func declinedCapabilityIsAbsent() {
        for aSwitch in SwitchCatalogue.capabilities {
            let env = SwitchResolver.effectiveEnvironment(
                processEnvironment: [aSwitch.variable: "1"], saved: [aSwitch.variable: "0"])
            #expect(env[aSwitch.variable] == nil, "\(aSwitch.variable) should be absent")
        }
        // And the readers agree.
        let env = SwitchResolver.effectiveEnvironment(
            processEnvironment: ["PROCTOR_TAKEOVER_INPUT": "1", "PROCTOR_YIELD_INPUT": "1"],
            saved: ["PROCTOR_TAKEOVER_INPUT": "0", "PROCTOR_YIELD_INPUT": "0"])
        #expect(!Takeover.blockEnabled(in: env))
    }

    @Test("Every other variable passes through untouched")
    func passesThroughEverythingElse() {
        let process = ["PATH": "/usr/bin:/bin", "HOME": "/Users/x", "PROCTOR_SOCKET": "/tmp/s"]
        let env = SwitchResolver.effectiveEnvironment(processEnvironment: process,
                                                      saved: ["PROCTOR_CURSOR": "0"])
        #expect(env["PATH"] == "/usr/bin:/bin")
        #expect(env["HOME"] == "/Users/x")
        #expect(env["PROCTOR_SOCKET"] == "/tmp/s")
    }

    @Test("An environment value survives the fold, so precedence holds downstream")
    func environmentSurvives() {
        let env = SwitchResolver.effectiveEnvironment(
            processEnvironment: [CuaDriverTool.laneEnv: CuaDriverTool.laneValue],
            saved: [CuaDriverTool.laneEnv: "0"])
        #expect(CuaDriverTool.laneSelected(env), "the environment must win for a lane")
    }
}

// MARK: - Pairings

@Suite("PRO-0029 pairing warnings")
struct SwitchPairingTests {

    /// Clause 12. Holding a keyboard with the notice that would say so turned off
    /// is a Mac that stops responding for no stated reason.
    @Test("A warning appears only when the capability is on and its notice is off")
    func fourCombinations() {
        for pairing in SwitchCatalogue.pairings {
            #expect(SwitchCatalogue.pairingWarning(capabilityOn: true, announcesOn: false,
                                                   capability: pairing.capability) != nil)
            #expect(SwitchCatalogue.pairingWarning(capabilityOn: true, announcesOn: true,
                                                   capability: pairing.capability) == nil)
            #expect(SwitchCatalogue.pairingWarning(capabilityOn: false, announcesOn: false,
                                                   capability: pairing.capability) == nil)
            #expect(SwitchCatalogue.pairingWarning(capabilityOn: false, announcesOn: true,
                                                   capability: pairing.capability) == nil)
        }
    }

    /// A pairing exists where a capability would otherwise act on somebody with
    /// the notice that says so switched off. `PROCTOR_OVERLAY_CAPTURE` is the one
    /// capability that conceals nothing: it makes Proctor's own panels visible to
    /// a capture rather than taking anything from the person at the keyboard, so
    /// there is no drawing switch that would announce it and pairing it with one
    /// would be inventing a warning nobody needs.
    @Test("Every capability that acts on the person is paired; overlay capture is not one")
    func everyCapabilityIsPaired() {
        let paired = SwitchCatalogue.capabilities.filter { $0 != SwitchCatalogue.overlayCapture }
        #expect(SwitchCatalogue.pairings.count == paired.count)
        for capability in paired {
            #expect(SwitchCatalogue.pairings.contains { $0.capability == capability },
                    "\(capability.variable) needs a pairing")
        }
        #expect(!SwitchCatalogue.pairings.contains { $0.capability == SwitchCatalogue.overlayCapture })
    }
}

// MARK: - The report's states

@Suite("PRO-0029 report states")
struct SwitchReportStateTests {

    @Test("Every switch appears, in catalogue order, with its source and timing")
    func statesCoverEverything() {
        let states = SwitchResolver.reportStates(environment: [:], saved: [:])
        #expect(states.map(\.variable) == SwitchCatalogue.all.map(\.variable))
        #expect(states.allSatisfy { $0.source == SwitchSource.builtInDefault.rawValue })
        #expect(states.filter { $0.timing == ProctorSwitch.Timing.live.rawValue }.count == 1)
    }

    @Test("The pairing warning rides on the capability's own state")
    func warningOnTheState() {
        let states = SwitchResolver.reportStates(
            environment: ["PROCTOR_TAKEOVER_INPUT": "1", "PROCTOR_TAKEOVER": "0"], saved: [:])
        let tap = states.first { $0.variable == "PROCTOR_TAKEOVER_INPUT" }
        #expect(tap?.on == true)
        #expect(tap?.pairingWarning != nil)

        let quiet = SwitchResolver.reportStates(
            environment: ["PROCTOR_TAKEOVER_INPUT": "1"], saved: [:])
        #expect(quiet.first { $0.variable == "PROCTOR_TAKEOVER_INPUT" }?.pairingWarning == nil)
    }
}

// MARK: - The store

@Suite("PRO-0029 settings store")
struct SwitchStoreTests {

    private func temporaryHome() -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pro-0029-\(UUID().uuidString)", isDirectory: true)
        return url
    }

    /// Clause 14, and the finding the out-of-family gate produced before it died:
    /// the first draft named a directory that exists on no Mac.
    @Test("The path derives from the bundle identifier, not a literal")
    func pathDerivesFromBundleIdentifier() {
        let home = URL(fileURLWithPath: "/Users/example")
        let url = SwitchStore.url(home: home)
        #expect(url.path.contains(Wire.bundleIdentifier))
        #expect(url.path
                == "/Users/example/Library/Application Support/app.fledgeling.procter"
                 + "/settings/settings.json")
        // `procter` is the real bundle identifier, not a misspelling. Pinned so
        // nobody "corrects" it into a directory the agent does not use.
        #expect(!url.path.contains("/Proctor/"))
    }

    @Test("A saved set round-trips")
    func roundTrips() throws {
        let home = temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }

        var saved = SavedSwitches()
        saved.set(SwitchCatalogue.cursor, on: false)
        saved.set(SwitchCatalogue.secondLane, on: true)
        try SwitchStore.save(saved, to: SwitchStore.url(home: home))

        let back = SwitchStore.load(from: SwitchStore.url(home: home))
        #expect(back == saved)
        #expect(back[SwitchCatalogue.secondLane.variable] == "browser-use")
        #expect(SwitchResolver.isOn(back[SwitchCatalogue.secondLane.variable],
                                    for: SwitchCatalogue.secondLane))
    }

    /// Clause 13. Failing towards "on" would mean a damaged file could arm an
    /// event tap, which is the one direction this must never fail in.
    @Test("A missing, empty, corrupt or wrongly-typed file resolves to the defaults")
    func malformedFilesFallBackToDefaults() throws {
        let home = temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let url = SwitchStore.url(home: home)

        // Missing.
        #expect(SwitchStore.load(from: url).values.isEmpty)

        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        for bad in ["", "{", "not json at all", "[1,2,3]", "{\"PROCTOR_HUD\": 1}"] {
            try bad.data(using: .utf8)!.write(to: url)
            let loaded = SwitchStore.load(from: url)
            #expect(loaded.values.isEmpty, "\(bad) should yield nothing")
            for aSwitch in SwitchCatalogue.all {
                let r = SwitchResolver.resolve(aSwitch, environment: [:], saved: loaded.values)
                #expect(r.on == aSwitch.defaultOn, "\(aSwitch.variable) after \(bad)")
            }
            // The four that must never come on by accident.
            for aSwitch in SwitchCatalogue.all where aSwitch.kind != .drawing {
                #expect(!SwitchResolver.resolve(aSwitch, environment: [:],
                                                saved: loaded.values).on)
            }
        }
    }

    @Test("An unknown key is ignored rather than rejected")
    func unknownKeysIgnored() throws {
        let home = temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let url = SwitchStore.url(home: home)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try #"{"PROCTOR_CURSOR":"0","PROCTOR_FUTURE_SWITCH":"1","NOT_OURS":"x"}"#
            .data(using: .utf8)!.write(to: url)

        let loaded = SwitchStore.load(from: url)
        #expect(loaded.values == ["PROCTOR_CURSOR": "0"])
    }

    @Test("No key outside the eight is ever written")
    func neverWritesForeignKeys() throws {
        let home = temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let url = SwitchStore.url(home: home)

        let saved = SavedSwitches(values: ["PROCTOR_CURSOR": "0", "PROCTOR_MCP_TOKEN": "secret",
                                           "PATH": "/nope"])
        try SwitchStore.save(saved, to: url)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("PROCTOR_CURSOR"))
        #expect(!text.contains("PROCTOR_MCP_TOKEN"))
        #expect(!text.contains("PATH"))
    }

    @Test("The file is 0600 and its directory 0700")
    func permissions() throws {
        let home = temporaryHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let url = SwitchStore.url(home: home)
        try SwitchStore.save(SavedSwitches(), to: url)

        let file = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect(file[.posixPermissions] as? NSNumber == 0o600)
        let dir = try FileManager.default
            .attributesOfItem(atPath: url.deletingLastPathComponent().path)
        #expect(dir[.posixPermissions] as? NSNumber == 0o700)
    }

    @Test("clear forgets a switch so it falls back")
    func clearFallsBack() {
        var saved = SavedSwitches()
        saved.set(SwitchCatalogue.cursor, on: false)
        #expect(!SwitchResolver.resolve(SwitchCatalogue.cursor,
                                        environment: [:], saved: saved.values).on)
        saved.clear(SwitchCatalogue.cursor)
        let r = SwitchResolver.resolve(SwitchCatalogue.cursor, environment: [:],
                                       saved: saved.values)
        #expect(r.on)
        #expect(r.source == .builtInDefault)
    }
}

// MARK: - The wire

@Suite("PRO-0029 report compatibility")
struct SwitchWireTests {

    /// Clause 15. An older agent's report must still decode against a newer window.
    @Test("A report with no switches field still decodes")
    func olderReportDecodes() throws {
        let json = """
        {"agentVersion":"1","protocolVersion":1,"osVersion":"26.0","agentRunning":true,
         "socketPath":"/tmp/s","grants":[],"attachedApps":[],"observersLive":0,
         "secureEventInputActive":false,"shortcutsCLIAvailable":true,
         "obscuraAvailable":false,"tools":[],"secondLane":"off",
         "ready":true,"blockers":[]}
        """
        let report = try JSONDecoder().decode(DoctorReport.self, from: Data(json.utf8))
        #expect(report.switches == nil)
    }

    @Test("A report carrying switches round-trips")
    func switchesRoundTrip() throws {
        let states = SwitchResolver.reportStates(environment: ["PROCTOR_CURSOR": "0"], saved: [:])
        let report = DoctorReport(
            agentVersion: "1", protocolVersion: 1, osVersion: "26.0", agentRunning: true,
            socketPath: "/tmp/s", grants: [], attachedApps: [], observersLive: 0,
            secureEventInputActive: false, shortcutsCLIAvailable: true,
            switches: states, ready: true, blockers: [])
        let data = try JSONEncoder().encode(report)
        let back = try JSONDecoder().decode(DoctorReport.self, from: data)
        #expect(back.switches == states)
        #expect(back.switches?.first { $0.variable == "PROCTOR_CURSOR" }?.locked == true)
    }
}
