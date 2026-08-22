import Foundation
import AppKit
import CoreGraphics
import Testing
@testable import ProctorAgent
@testable import ProctorCore

// PRO-0092 — the thirteen survivors of the first `ProctorAgent` mutation sample
// that PRO-0080 could not reach.
//
// PRO-0080 ran 24 mutants over a pool of 3,189 sites under seed 20260821 and 19
// survived. Five were killed there, one was argued equivalent, and thirteen were
// recorded as `no seam` or `uncovered-by-lane` — headless-testable in principle,
// with no fake to test them through. Ten of those thirteen are killed here; the
// other three are recorded in the spec with the argument for each, because the
// only oracle available to them is the literal the mutation changed, and a test
// that writes a constant a second time raises the score while lowering what the
// suite knows.
//
// Every oracle below is independent of the source under test: the catalogue's
// own published schema, an invariant over a palette rather than one of its
// values, a round trip through the filesystem, or a population the test states.
// Each test is armed — the mutant re-applied, the mutation confirmed to have
// landed, the named test watched going red, the mutant reverted.
@Suite("Mutation seams, ProctorAgent")
struct MutationSeamTests {

    // MARK: - Survivor 1 — AXEngineImpl.swift, `||` became `&&`

    // `guard includeWindowless || app.activationPolicy == .regular` decides which
    // running applications `proctor_apps` reports. With `&&` the flag inverts
    // meaning: asking for windowless apps returns only the ones with a Dock icon,
    // and asking for the ordinary list returns nothing at all. Nothing watched
    // it, because `listApps` read `NSWorkspace` directly and a test cannot state
    // what that will say.
    @Test("Asking for windowless apps returns the accessory ones too")
    func listAppsHonoursIncludeWindowless() throws {
        let population = [
            AXEngineImpl.RunningApp(pid: 101, isRegular: true,
                                    bundleId: "test.regular", localizedName: "Regular"),
            AXEngineImpl.RunningApp(pid: 202, isRegular: false,
                                    bundleId: "test.accessory", localizedName: "Accessory"),
            AXEngineImpl.RunningApp(pid: 303, isRegular: true,
                                    bundleId: "test.regular.two", localizedName: "Regular Two"),
        ]
        let engine = AXEngineImpl(runningApps: { population })

        let everything = try engine.listApps(includeWindowless: true).map(\.pid).sorted()
        #expect(everything == [101, 202, 303],
                "includeWindowless: true reported \(everything)")

        let regularOnly = try engine.listApps(includeWindowless: false).map(\.pid).sorted()
        #expect(regularOnly == [101, 303],
                "includeWindowless: false reported \(regularOnly)")

        // The accessory app is the whole point of the flag, so name it directly
        // rather than leaving it to a count.
        let windowless = try engine.listApps(includeWindowless: true)
            .contains { $0.pid == 202 }
        #expect(windowless, "the accessory app was dropped from the windowless list")
    }

    // MARK: - Survivors 2 and 8 — Dispatch.swift, two argument defaults

    // `includeTiles: args.bool("includeTiles", false)` became `true`, and
    // `presentation: args.bool("presentation", true)` became `false`. Both are
    // the value a caller gets when the argument is absent, which is most calls.
    //
    // The oracle is the published schema rather than the source: every optional
    // boolean in `ToolCatalogue` states its default in its own description, and
    // `Dispatch.swift`'s header says the catalogue is the source of truth for
    // names and defaults. This checks that the second copy agrees with the
    // first, which kills both survivors and the other decode sites with them.
    @Test("Every decoded boolean default matches the default its schema states")
    func dispatchDefaultsAgreeWithTheCatalogue() throws {
        let decoded = try Self.decodedBooleanDefaults()
        let declared = Self.declaredBooleanDefaults()

        // The two survivors by name, so a parser that silently stopped finding
        // sites cannot pass this test by comparing nothing.
        #expect(decoded[Pair("proctor_stability", "includeTiles")] != nil,
                "no decode site found for stability.includeTiles")
        #expect(decoded[Pair("proctor_inspect", "presentation")] != nil,
                "no decode site found for inspect.presentation")
        #expect(declared[Pair("proctor_stability", "includeTiles")] == false)
        #expect(declared[Pair("proctor_inspect", "presentation")] == true)

        var disagreements: [String] = []
        var compared = 0
        for (pair, stated) in declared.sorted(by: { $0.key.description < $1.key.description }) {
            guard let read = decoded[pair] else { continue }
            compared += 1
            if read != stated {
                disagreements.append("\(pair) decodes \(read), the schema says \(stated)")
            }
        }
        #expect(disagreements.isEmpty, "\(disagreements)")

        // A measured floor. Sixteen pairs are comparable today; the check is that
        // the join did not collapse, not that it is exactly sixteen.
        #expect(compared >= 12, "compared only \(compared) declared defaults")
    }

    // The runtime half of the same two survivors, and it is the one that reads
    // the decoder rather than the file the decoder lives in. Raised by this
    // item's out-of-family review, which was right about it twice: a check that
    // parses `args.bool("includeTiles", false)` out of the source registers a
    // kill without ever asking what an omitted argument resolves to. The seam is
    // a value the decode produces, so the question can be asked directly.
    //
    // The oracle stays the published schema. Two clauses per argument, because a
    // decoder that ignored its input entirely and returned a constant would
    // satisfy the first on its own.
    @Test("An omitted boolean argument resolves at runtime to its published default")
    func decodedArgumentsResolveToThePublishedDefaults() throws {
        let declared = Self.declaredBooleanDefaults()

        let noArguments = Args(tool: "proctor_stability", raw: .object([:]))
        let stability = Dispatcher.StabilityArguments(noArguments)
        #expect(stability.includeTiles == declared[Pair("proctor_stability", "includeTiles")])
        #expect(stability.captureEach
                == declared[Pair("proctor_stability", StabilityCaptureOptions.captureEachArg)])
        #expect(stability.pointerMarks
                == declared[Pair("proctor_stability", StabilityCaptureOptions.pointerMarksArg)])

        let inspectDefaults = Dispatcher.InspectArguments(
            Args(tool: "proctor_inspect", raw: .object([:])))
        #expect(inspectDefaults.includeConstraints
                == declared[Pair("proctor_inspect", "includeConstraints")])
        #expect(inspectDefaults.presentation == declared[Pair("proctor_inspect", "presentation")])

        // Supplied values are read, so none of the above is a constant.
        let supplied = Dispatcher.StabilityArguments(
            Args(tool: "proctor_stability", raw: .object([
                "includeTiles": .bool(true),
                StabilityCaptureOptions.captureEachArg: .bool(true),
                StabilityCaptureOptions.pointerMarksArg: .bool(true)])))
        #expect(supplied == Dispatcher.StabilityArguments.init(
            Args(tool: "proctor_stability", raw: .object([
                "includeTiles": .bool(true),
                StabilityCaptureOptions.captureEachArg: .bool(true),
                StabilityCaptureOptions.pointerMarksArg: .bool(true)]))))
        #expect(supplied.includeTiles && supplied.captureEach && supplied.pointerMarks)
        #expect(supplied != stability, "the decoder returned the same value for both inputs")

        let inspectSupplied = Dispatcher.InspectArguments(
            Args(tool: "proctor_inspect", raw: .object([
                "includeConstraints": .bool(true), "presentation": .bool(false)])))
        #expect(inspectSupplied.includeConstraints)
        #expect(inspectSupplied.presentation == false)
        #expect(inspectSupplied != inspectDefaults)
    }

    // MARK: - Survivor 4 — Session.swift, a snapshot option's default

    // `var includeInvisible: Bool = false` became `true`. The default decides
    // whether an unasked-for snapshot carries zero-area and offscreen nodes,
    // which is the difference between a tree a model can read and one padded with
    // nodes nothing can be done to. The oracle is again the schema's own prose.
    @Test("A default snapshot leaves invisible nodes out, as its schema says")
    func snapshotOptionDefaultsMatchTheSchema() throws {
        let declared = Self.declaredBooleanDefaults()
        let stated = declared[Pair("proctor_snapshot", "includeInvisible")]
        #expect(stated == false, "the schema no longer states this default: \(String(describing: stated))")
        #expect(Session.SnapshotOptions().includeInvisible == stated)
    }

    // MARK: - Survivor 10 — CGWindowCorrelation.swift, the match index

    // `matches[0].number` became `matches[1].number`. The seam was already
    // there — `correlate(frame:title:in:)` takes its records as a parameter —
    // and nothing had ever called it. A wrong window number captures the wrong
    // window and nothing downstream can tell, which is why the function refuses
    // to guess when more than one candidate fits.
    @Test("A single fitting window is correlated to its own number")
    func correlateReturnsTheMatchingWindowsNumber() {
        let target = CGWindowRecord(number: 7001, pid: 42,
                                    bounds: CGRect(x: 10, y: 20, width: 300, height: 200),
                                    title: "Document", layer: 0)
        let elsewhere = CGWindowRecord(number: 7002, pid: 42,
                                       bounds: CGRect(x: 900, y: 900, width: 100, height: 100),
                                       title: "Other", layer: 0)
        let frame = Rect(x: 10, y: 20, w: 300, h: 200)

        #expect(CGWindowIndex.correlate(frame: frame, title: "Document",
                                        in: [target, elsewhere]) == 7001)
        // Order must not decide the answer.
        #expect(CGWindowIndex.correlate(frame: frame, title: "Document",
                                        in: [elsewhere, target]) == 7001)
        // Two fitting candidates are reported as absent rather than guessed.
        let twin = CGWindowRecord(number: 7003, pid: 42, bounds: target.bounds,
                                  title: "Document", layer: 0)
        #expect(CGWindowIndex.correlate(frame: frame, title: "Document",
                                        in: [target, twin]) == nil)
        // A menu-bar or overlay window is not a candidate at all.
        let overlay = CGWindowRecord(number: 7004, pid: 42, bounds: target.bounds,
                                     title: "Document", layer: 25)
        #expect(CGWindowIndex.correlate(frame: frame, title: "Document",
                                        in: [overlay]) == nil)
    }

    // MARK: - Survivor 7 — SessionKill.swift, the bare-pid rule

    // `!candidates.contains(where: { $0.pid == pid })` became `!=`, which
    // appends nothing whenever any other process is running and duplicates the
    // target whenever none is. A bare pid that is not a GUI application would
    // stop being selectable, and `proctor_kill` would report nothing matched.
    @Test("A bare pid that is not a GUI application is still a candidate")
    func barePidIsSynthesisedExactlyOnce() {
        let running = [
            ProcessInfoLite(pid: 501, name: "Finder", bundleId: "com.apple.finder"),
            ProcessInfoLite(pid: 502, name: "Safari", bundleId: "com.apple.Safari"),
        ]

        let synthesised = KillCandidates.includingBarePid(running, query: KillQuery(pid: 999))
        #expect(synthesised.count == 3, "got \(synthesised.map(\.pid))")
        let bare = synthesised.first { $0.pid == 999 }
        #expect(bare != nil, "the bare pid was not added")
        // No bundle id, so an allow list in force refuses it — the fail-closed half.
        #expect(bare?.bundleId == nil)

        // A pid already present is not added a second time.
        let known = KillCandidates.includingBarePid(running, query: KillQuery(pid: 501))
        #expect(known.count == 2, "got \(known.map(\.pid))")
        #expect(known.filter { $0.pid == 501 }.count == 1)

        // A query naming no pid changes nothing.
        #expect(KillCandidates.includingBarePid(running, query: KillQuery(name: "Finder")).count == 2)
    }

    // MARK: - Survivor 9 — RunHUDPanel.swift, the panel's two answers

    // `override var canBecomeMain: Bool { false }` became `true`. The class
    // exists for these two answers and nothing could ask it either, because it
    // was private. A HUD that can become main takes the main window away from
    // the application the run is driving, while still taking key so its Stop
    // control stays clickable.
    @MainActor
    @Test("The HUD panel takes key and refuses to become main")
    func hudPanelTakesKeyAndRefusesMain() {
        _ = NSApplication.shared
        let panel = HUDPanel(contentRect: NSRect(x: 0, y: 0, width: 352, height: 200),
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: true)
        panel.isReleasedWhenClosed = false
        defer { panel.close() }

        let key = panel.canBecomeKey
        let main = panel.canBecomeMain
        #expect(key, "the HUD refused key, so its Stop control cannot be clicked")
        #expect(main == false, "the HUD would take the main window from the app under test")
    }

    // MARK: - Survivor 11 — RunHUDContentView.swift, one channel of one ink

    // `ink3: hex(17, 18, 21, 0.36)` became `hex(18, 18, 21, 0.36)`. The oracle is
    // not the number: the light palette's ink and fill tones are one graphite at
    // several opacities, and a tone that drifts off that base is a different
    // colour wearing the same name. The invariant holds whatever the base is, so
    // this check does not restate the value it is checking.
    @Test("Every light-palette ink and fill tone is one graphite at a different opacity")
    func lightPaletteTonesShareOneBase() throws {
        let palette = RunHUDPalette.light
        let tones: [(String, NSColor)] = [
            ("ink", palette.ink), ("ink2", palette.ink2),
            ("ink3", palette.ink3), ("ink4", palette.ink4),
            ("fill", palette.fill), ("fill2", palette.fill2),
            ("separator", palette.separator),
        ]
        let components = try tones.map { name, colour -> (String, CGFloat, CGFloat, CGFloat, CGFloat) in
            let srgb = try #require(colour.usingColorSpace(.sRGB), "\(name) is not convertible to sRGB")
            return (name, srgb.redComponent, srgb.greenComponent, srgb.blueComponent,
                    srgb.alphaComponent)
        }
        let base = try #require(components.first)
        var drifted: [String] = []
        for tone in components.dropFirst() {
            let same = abs(tone.1 - base.1) < 0.001
                && abs(tone.2 - base.2) < 0.001
                && abs(tone.3 - base.3) < 0.001
            if !same {
                drifted.append("\(tone.0) rgb(\(tone.1), \(tone.2), \(tone.3)) "
                             + "against \(base.0) rgb(\(base.1), \(base.2), \(base.3))")
            }
        }
        #expect(drifted.isEmpty, "\(drifted)")

        // And they are genuinely a ladder rather than one colour repeated, so the
        // check above cannot be satisfied by a palette that lost its opacities.
        // Five rather than seven, measured: `fill2` and `separator` are both
        // 0.09, which is the palette agreeing with itself rather than a fault.
        let alphas = Set(components.map { Int(($0.4 * 1000).rounded()) })
        #expect(alphas.count >= 5,
                "\(components.count) tones carry \(alphas.count) distinct opacities")
    }

    // MARK: - Survivor 12 — TakeoverOverlay.swift, the tap-disabled predicate

    // `type == .tapDisabledByTimeout` became `!=`, which makes every ordinary
    // keystroke read as macOS switching the tap off. The second one lets go of
    // the machine, so a person typing would break their own hold — and a real
    // disable notice would fall through to the handler as if it were input.
    @Test("Only the two disable notices read as macOS switching the tap off")
    func tapDisableNoticesAreTheOnlyDisableNotices() {
        #expect(InputBlocker.isTapDisabledNotice(.tapDisabledByTimeout))
        #expect(InputBlocker.isTapDisabledNotice(.tapDisabledByUserInput))

        let ordinary: [CGEventType] = [.keyDown, .keyUp, .flagsChanged, .leftMouseDown,
                                       .leftMouseUp, .rightMouseDown, .mouseMoved,
                                       .scrollWheel, .otherMouseDown]
        var misread: [String] = []
        for type in ordinary where InputBlocker.isTapDisabledNotice(type) {
            misread.append("\(type.rawValue)")
        }
        #expect(misread.isEmpty, "event types misread as a disable notice: \(misread)")
    }

    // MARK: - Survivor 13 — AuditKeyStore.swift, the cached public key's path

    // `appendingPathComponent("audit.pub", isDirectory: false)` became `true`.
    // The URL then carries a trailing slash and claims to be a directory, and the
    // cached public key is the thing that keeps the audit write path out of the
    // Keychain entirely — no unlock, no prompt while the agent works alone.
    @Test("The cached public key is a file in the audit directory, and reads back")
    func publicKeyURLNamesAFileThatRoundTrips() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("pro0092-auditkey-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = AuditKeyStore.publicKeyURL(in: directory)
        #expect(url.lastPathComponent == "audit.pub")
        #expect(url.hasDirectoryPath == false, "the key URL claims to be a directory: \(url)")
        #expect(url.deletingLastPathComponent().standardizedFileURL
                == directory.standardizedFileURL)

        // The behavioural half: bytes written at that URL come back through it.
        let raw = Data((0..<32).map { UInt8($0) })
        try raw.write(to: url)
        let read = try Data(contentsOf: url)
        #expect(read == raw)

        // And it is a regular file on disk, not a directory.
        var isDirectory: ObjCBool = true
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        #expect(exists)
        #expect(isDirectory.boolValue == false)
    }

    // MARK: - Reading the two statements of a default

    /// One (tool, argument) pair. A `String` key would join `capture.foreground`
    /// onto `act.foreground`, and those two genuinely differ.
    struct Pair: Hashable, CustomStringConvertible {
        let tool: String, argument: String
        init(_ tool: String, _ argument: String) { self.tool = tool; self.argument = argument }
        var description: String { "\(tool).\(argument)" }
    }

    /// What each tool's published schema says its optional booleans default to.
    /// Read from the descriptions rather than from a `default` key, because the
    /// schema does not carry one — the prose is where the contract is stated.
    static func declaredBooleanDefaults() -> [Pair: Bool] {
        var out: [Pair: Bool] = [:]
        for spec in ToolCatalogue.all {
            guard let properties = spec.inputSchema.objectValue?["properties"]?.objectValue
            else { continue }
            for (name, schema) in properties {
                guard let field = schema.objectValue,
                      field["type"]?.stringValue == "boolean",
                      let prose = field["description"]?.stringValue
                else { continue }
                if let stated = statedDefault(in: prose) {
                    out[Pair(spec.name, name)] = stated
                }
            }
        }
        return out
    }

    /// `Defaults to true`, `defaults to false`, `Off by default`, `On by default`.
    /// Anything else is left out, so a description that states no default is not
    /// invented one.
    private static func statedDefault(in prose: String) -> Bool? {
        let lower = prose.lowercased()
        if lower.contains("defaults to true") || lower.contains("on by default") { return true }
        if lower.contains("defaults to false") || lower.contains("off by default") { return false }
        return nil
    }

    /// What `Dispatch.swift` actually writes at each decode site, per tool. The
    /// file is sectioned by `// MARK: - proctor_<name>` and the decode sites sit
    /// inside their tool's section, which is what carries the tool name — an
    /// `args.bool("foreground", …)` on its own does not say whose it is.
    static func decodedBooleanDefaults() throws -> [Pair: Bool] {
        let source = try String(contentsOf: dispatchSource, encoding: .utf8)
        var out: [Pair: Bool] = [:]
        // The two argument names Dispatch spells through a constant rather than a
        // literal, resolved from the constants themselves.
        let named = [
            "StabilityCaptureOptions.captureEachArg": StabilityCaptureOptions.captureEachArg,
            "StabilityCaptureOptions.pointerMarksArg": StabilityCaptureOptions.pointerMarksArg,
        ]
        let call = try NSRegularExpression(
            pattern: #"args\.bool\((?:"([A-Za-z]+)"|(StabilityCaptureOptions\.[A-Za-z]+))\s*,\s*(true|false)\)"#)

        var tool: String?
        for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let text = String(line)
            if let marker = text.range(of: "// MARK: - proctor_") {
                let rest = text[marker.upperBound...]
                let name = rest.prefix { $0.isLetter || $0 == "_" }
                tool = "proctor_" + name
                continue
            }
            guard let tool else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in call.matches(in: text, range: range) {
                let literal = Range(match.range(at: 3), in: text).map { String(text[$0]) }
                var argument: String?
                if let r = Range(match.range(at: 1), in: text) { argument = String(text[r]) }
                else if let r = Range(match.range(at: 2), in: text) { argument = named[String(text[r])] }
                if let argument, let literal {
                    out[Pair(tool, argument)] = literal == "true"
                }
            }
        }
        return out
    }

    static var dispatchSource: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // ProctorAgentTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // package root
            .appendingPathComponent("Sources/ProctorAgent/Dispatch.swift")
    }
}
