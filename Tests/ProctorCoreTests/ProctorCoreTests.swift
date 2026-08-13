import Testing
import Foundation
@testable import ProctorCore

// These cover the parts of the contract that a wrong answer would make quietly
// useless: the canonical hash deciding two states are different when they are
// the same, and the frame codec losing a message boundary.

private func node(_ role: String, id: String, title: String? = nil,
                  value: JSONValue? = nil, frame: Rect? = nil,
                  children: [AXNode] = []) -> AXNode {
    AXNode(id: id, role: role, title: title, value: value, frame: frame,
           actions: [], children: children.isEmpty ? nil : children,
           childCount: children.count)
}

@Suite("Canonical hashing")
struct CanonicalTests {

    @Test("identical trees hash identically")
    func identical() {
        let a = node("AXWindow", id: "w", children: [node("AXButton", id: "b", title: "Save")])
        let b = node("AXWindow", id: "w", children: [node("AXButton", id: "b", title: "Save")])
        #expect(Canonical.hash(a) == Canonical.hash(b))
    }

    @Test("a changed title changes the hash")
    func titleMatters() {
        let a = node("AXWindow", id: "w", children: [node("AXButton", id: "b", title: "Save")])
        let b = node("AXWindow", id: "w", children: [node("AXButton", id: "b", title: "Send")])
        #expect(Canonical.hash(a) != Canonical.hash(b))
    }

    @Test("sub-pixel drift does not change the hash")
    func geometryQuantised() {
        // Two runs of the same animation land a fraction of a point apart. Treating
        // that as a state change makes every animated view report as unstable.
        let a = node("AXButton", id: "b", frame: Rect(x: 10.0, y: 20.0, w: 80, h: 24))
        let b = node("AXButton", id: "b", frame: Rect(x: 10.4, y: 19.6, w: 80, h: 24))
        #expect(Canonical.hash(a) == Canonical.hash(b))
    }

    @Test("a real move does change the hash")
    func realMove() {
        let a = node("AXButton", id: "b", frame: Rect(x: 10, y: 20, w: 80, h: 24))
        let b = node("AXButton", id: "b", frame: Rect(x: 60, y: 20, w: 80, h: 24))
        #expect(Canonical.hash(a) != Canonical.hash(b))
    }

    @Test("a clock in a label does not change the hash")
    func volatileTextMasked() {
        let a = node("AXStaticText", id: "t", title: "Last synced 14:03")
        let b = node("AXStaticText", id: "t", title: "Last synced 14:04")
        #expect(Canonical.hash(a) == Canonical.hash(b))
    }

    @Test("a UUID in a value does not change the hash")
    func uuidMasked() {
        let a = node("AXStaticText", id: "t",
                     value: .string("id 3F2504E0-4F89-11D3-9A0C-0305E82C3301"))
        let b = node("AXStaticText", id: "t",
                     value: .string("id 7B1F04E0-4F89-11D3-9A0C-0305E82C3301"))
        #expect(Canonical.hash(a) == Canonical.hash(b))
    }

    @Test("masking can be turned off when the text is the thing under test")
    func maskingOptional() {
        let opts = Canonical.Options(maskVolatileText: false)
        let a = node("AXStaticText", id: "t", title: "Last synced 14:03")
        let b = node("AXStaticText", id: "t", title: "Last synced 14:04")
        #expect(Canonical.hash(a, options: opts) != Canonical.hash(b, options: opts))
    }

    @Test("child order is significant, because it is the focus order")
    func orderMatters() {
        let a = node("AXWindow", id: "w", children: [
            node("AXButton", id: "1", title: "Cancel"),
            node("AXButton", id: "2", title: "OK"),
        ])
        let b = node("AXWindow", id: "w", children: [
            node("AXButton", id: "2", title: "OK"),
            node("AXButton", id: "1", title: "Cancel"),
        ])
        #expect(Canonical.hash(a) != Canonical.hash(b))
    }
}

@Suite("Determinism arithmetic")
struct InstabilityTests {

    @Test("identical runs are stable")
    func stable() {
        #expect(Canonical.instability(hashes: ["a", "a", "a", "a", "a"]) == 0)
    }

    @Test("every run different is fully unstable")
    func unstable() {
        #expect(Canonical.instability(hashes: ["a", "b", "c", "d", "e"]) == 1)
    }

    @Test("one odd run out of five scores low but non-zero")
    func partial() {
        let v = Canonical.instability(hashes: ["a", "a", "b", "a", "a"])
        #expect(v > 0 && v < 0.5)
    }

    @Test("a single run cannot be unstable")
    func singleRun() {
        #expect(Canonical.instability(hashes: ["a"]) == 0)
    }

    @Test("divergence is reported at the first disagreeing step")
    func divergence() {
        let runs = [
            ["h0", "h1", "h2", "h3"],
            ["h0", "h1", "hX", "h3"],
            ["h0", "h1", "h2", "h3"],
        ]
        #expect(Canonical.firstDivergence(perRun: runs) == 2)
    }

    @Test("agreeing runs have no divergence")
    func noDivergence() {
        let runs = [["h0", "h1"], ["h0", "h1"]]
        #expect(Canonical.firstDivergence(perRun: runs) == nil)
    }

    @Test("a run that ended early is itself a divergence")
    func shortRun() {
        // Otherwise a flow that crashed at step 2 in one run reports as deterministic,
        // which is the reading that matters most and the one easiest to get wrong.
        let runs = [["h0", "h1", "h2"], ["h0", "h1"]]
        #expect(Canonical.firstDivergence(perRun: runs) == 2)
    }
}

@Suite("Frame codec")
struct FrameCodecTests {

    @Test("a round trip preserves the request")
    func roundTrip() throws {
        let req = AgentRequest(id: "1", tool: "proctor_doctor",
                               arguments: .object(["verbose": .bool(true)]))
        let data = try FrameCodec.encode(req)
        let reader = FrameCodec.Reader()
        reader.feed(data)
        let body = try #require(try reader.next())
        let back = try JSONDecoder().decode(AgentRequest.self, from: body)
        #expect(back.tool == "proctor_doctor")
        #expect(back.arguments["verbose"]?.boolValue == true)
    }

    @Test("a partial frame yields nothing until it completes")
    func partial() throws {
        let req = AgentRequest(id: "1", tool: "proctor_apps", arguments: .object([:]))
        let data = try FrameCodec.encode(req)
        let reader = FrameCodec.Reader()
        reader.feed(data.prefix(data.count - 3))
        #expect(try reader.next() == nil)
        reader.feed(data.suffix(3))
        #expect(try reader.next() != nil)
    }

    @Test("two frames in one read are both recovered")
    func coalesced() throws {
        var data = Data()
        data.append(try FrameCodec.encode(AgentRequest(id: "1", tool: "a", arguments: .null)))
        data.append(try FrameCodec.encode(AgentRequest(id: "2", tool: "b", arguments: .null)))
        let reader = FrameCodec.Reader()
        reader.feed(data)
        let first = try #require(try reader.next())
        let second = try #require(try reader.next())
        #expect(try JSONDecoder().decode(AgentRequest.self, from: first).id == "1")
        #expect(try JSONDecoder().decode(AgentRequest.self, from: second).id == "2")
        #expect(try reader.next() == nil)
    }

    @Test("a payload containing newlines survives, which newline framing would not")
    func embeddedNewlines() throws {
        let text = "line one\nline two\r\nline three"
        let req = AgentRequest(id: "1", tool: "proctor_act",
                               arguments: .object(["text": .string(text)]))
        let reader = FrameCodec.Reader()
        reader.feed(try FrameCodec.encode(req))
        let body = try #require(try reader.next())
        let back = try JSONDecoder().decode(AgentRequest.self, from: body)
        #expect(back.arguments["text"]?.stringValue == text)
    }
}

@Suite("Tool catalogue")
struct CatalogueTests {

    @Test("seventeen tools are advertised")
    func count() {
        #expect(ToolCatalogue.all.count == 17)
    }

    @Test("every tool has a unique name, a description and an object schema")
    func wellFormed() {
        var seen = Set<String>()
        for tool in ToolCatalogue.all {
            #expect(seen.insert(tool.name).inserted, "duplicate tool name \(tool.name)")
            #expect(tool.name.hasPrefix("proctor_"))
            #expect(tool.description.count > 200, "\(tool.name) is under-described")
            #expect(tool.inputSchema["type"]?.stringValue == "object")
            #expect(tool.inputSchema["properties"]?.objectValue != nil)
        }
    }

    @Test("the tools that change state are not marked read-only")
    func readOnlyFlags() {
        let mutating = ["proctor_act", "proctor_apps", "proctor_flow", "proctor_stability",
                        "proctor_computer", "proctor_openai_computer"]
        for name in mutating {
            let tool = try! #require(ToolCatalogue.spec(named: name))
            #expect(tool.readOnly == false, "\(name) should not be read-only")
        }
        for name in ["proctor_snapshot", "proctor_find", "proctor_capture", "proctor_doctor"] {
            let tool = try! #require(ToolCatalogue.spec(named: name))
            #expect(tool.readOnly == true, "\(name) should be read-only")
        }
    }
}

@Suite("Tool annotations")
struct AnnotationTests {

    // The destructive hint is what a host gates behind its own confirmation. Only
    // the tools that actuate or unlock earn it; attach/detach and every read do not.
    @Test("exactly the actuating tools are destructive")
    func destructiveSet() {
        let destructive = Set(ToolCatalogue.all.filter(\.destructive).map(\.name))
        #expect(destructive == ["proctor_act", "proctor_flow",
                                "proctor_stability", "proctor_unlock"])
    }

    @Test("a read-only tool is never destructive and is idempotent")
    func readOnlyNeverDestructive() {
        for tool in ToolCatalogue.all where tool.readOnly {
            #expect(tool.destructive == false, "\(tool.name) is read-only yet destructive")
            #expect(tool.idempotent == true, "\(tool.name) is read-only yet not idempotent")
        }
    }

    @Test("apps mutates session state but is non-destructive and idempotent")
    func appsIsIdempotent() {
        let apps = try! #require(ToolCatalogue.spec(named: "proctor_apps"))
        #expect(apps.readOnly == false)
        #expect(apps.destructive == false)
        #expect(apps.idempotent == true)
    }

    @Test("act is not idempotent, because typing twice types twice")
    func actNotIdempotent() {
        let act = try! #require(ToolCatalogue.spec(named: "proctor_act"))
        #expect(act.destructive == true)
        #expect(act.idempotent == false)
    }
}

@Suite("Output schemas")
struct OutputSchemaTests {

    @Test("every tool advertises an object output schema")
    func everyToolHasObjectSchema() {
        for tool in ToolCatalogue.all {
            let schema = ToolCatalogue.outputSchema(for: tool.name)
            #expect(schema["type"]?.stringValue == "object",
                    "\(tool.name) output schema is not an object")
        }
    }

    @Test("an unknown tool falls back to an open object rather than nothing")
    func unknownFallsBack() {
        #expect(ToolCatalogue.outputSchema(for: "proctor_nonexistent")["type"]?.stringValue == "object")
    }

    @Test("a bespoke schema documents the tool's own fields")
    func captureDocumentsPath() {
        let schema = ToolCatalogue.outputSchema(for: "proctor_capture")
        #expect(schema["properties"]?["path"] != nil)
        #expect(schema["properties"]?["trustworthy"] != nil)
    }
}

@Suite("Tool profiles")
struct ProfileTests {

    private func names(_ p: ToolProfile) -> Set<String> {
        Set(ToolCatalogue.toolNames(for: p))
    }

    @Test("full is the whole catalogue")
    func fullIsEverything() {
        #expect(names(.full) == Set(ToolCatalogue.all.map(\.name)))
    }

    @Test("the profiles nest ax ⊂ core ⊂ scripting ⊂ full")
    func nesting() {
        let ax = names(.ax), core = names(.core)
        let scripting = names(.scripting), full = names(.full)
        #expect(ax.isStrictSubset(of: core))
        #expect(core.isStrictSubset(of: scripting))
        #expect(scripting.isStrictSubset(of: full))
    }

    @Test("every profile is a real subset of the catalogue and keeps apps and doctor")
    func wellFormed() {
        let all = Set(ToolCatalogue.all.map(\.name))
        for profile in ToolProfile.allCases {
            let n = names(profile)
            #expect(n.isSubset(of: all), "\(profile.rawValue) advertises an unknown tool")
            #expect(n.contains("proctor_apps"), "\(profile.rawValue) drops apps")
            #expect(n.contains("proctor_doctor"), "\(profile.rawValue) drops doctor")
        }
    }

    @Test("membership matches the documented clusters")
    func memberships() {
        // ax is accessibility only: no pixels, no reflector, no campaign, no unlock.
        #expect(!names(.ax).contains("proctor_capture"))
        #expect(!names(.ax).contains("proctor_inspect"))
        // core adds the capture loop but not campaign authoring.
        #expect(names(.core).contains("proctor_capture"))
        #expect(!names(.core).contains("proctor_flow"))
        #expect(!names(.core).contains("proctor_unlock"))
        // scripting adds flow and stability, still no inspect or unlock.
        #expect(names(.scripting).contains("proctor_flow"))
        #expect(names(.scripting).contains("proctor_stability"))
        #expect(!names(.scripting).contains("proctor_unlock"))
        // full has the specialist tools.
        #expect(names(.full).contains("proctor_inspect"))
        #expect(names(.full).contains("proctor_unlock"))
    }

    @Test("a profile argument parses case-insensitively; junk and empty do not")
    func parsing() {
        #expect(ToolProfile(argument: "core") == .core)
        #expect(ToolProfile(argument: "FULL") == .full)
        #expect(ToolProfile(argument: "Scripting") == .scripting)
        #expect(ToolProfile(argument: nil) == nil)
        #expect(ToolProfile(argument: "") == nil)
        #expect(ToolProfile(argument: "bogus") == nil)
    }
}

@Suite("Resource catalogue")
struct ResourceCatalogueTests {

    @Test("the four resources are advertised with the expected URIs")
    func fourResources() {
        let uris = Set(ResourceCatalogue.all.map(\.uri))
        #expect(uris == ["proctor://display", "proctor://windows",
                         "proctor://frontmost", "proctor://screenshot/latest"])
    }

    @Test("a URI resolves to its spec and back to the same URI")
    func uriRoundTrips() {
        for spec in ResourceCatalogue.all {
            let resolved = try! #require(ResourceCatalogue.spec(uri: spec.uri))
            #expect(resolved.uri == spec.uri)
            #expect(resolved.key == spec.key)
        }
    }

    @Test("an unknown URI resolves to nothing rather than a wrong resource")
    func unknownURI() {
        #expect(ResourceCatalogue.spec(uri: "proctor://nope") == nil)
        #expect(ResourceCatalogue.spec(uri: "file:///etc/passwd") == nil)
    }

    @Test("every resource is JSON with a non-empty key and description")
    func wellFormed() {
        for spec in ResourceCatalogue.all {
            #expect(spec.mimeType == "application/json")
            #expect(!spec.key.isEmpty)
            #expect(spec.description.count > 20, "\(spec.uri) is under-described")
            #expect(ResourceCatalogue.spec(key: spec.key)?.uri == spec.uri)
        }
    }
}

@Suite("Drag path interpolation")
struct PointerPathTests {

    private func distances(_ points: [CGPoint]) -> [Double] {
        guard points.count > 1 else { return [] }
        return (1..<points.count).map { PointerPath.distance(points[$0 - 1], points[$0]) }
    }

    @Test("the endpoints the caller asked for are the endpoints posted")
    func endpoints() {
        let out = PointerPath.interpolate([CGPoint(x: 10, y: 20), CGPoint(x: 310, y: 220)])
        #expect(out.first == CGPoint(x: 10, y: 20))
        #expect(out.last == CGPoint(x: 310, y: 220))
    }

    @Test("consecutive points are no more than the spacing apart")
    func spacing() {
        // An app tracking a drag needs to see the movement; a hop of 300 points
        // between two events is a jump it can miss entirely.
        let out = PointerPath.interpolate([CGPoint(x: 0, y: 0), CGPoint(x: 300, y: 0)])
        #expect(out.count > 2)
        #expect(distances(out).allSatisfy { $0 <= 10 + 1e-9 })
    }

    @Test("a long path is capped rather than posting thousands of events")
    func capped() {
        let out = PointerPath.interpolate([CGPoint(x: 0, y: 0), CGPoint(x: 100_000, y: 0)])
        #expect(out.count <= PointerPath.defaultMaxPoints)
        #expect(out.first == CGPoint(x: 0, y: 0))
        #expect(out.last == CGPoint(x: 100_000, y: 0))
    }

    @Test("the cap holds even when the supplied path already exceeds it")
    func cappedByDecimation() {
        let dense = (0...500).map { CGPoint(x: Double($0), y: 0) }
        let out = PointerPath.interpolate(dense)
        #expect(out.count <= PointerPath.defaultMaxPoints)
        #expect(out.first == dense.first)
        #expect(out.last == dense.last)
    }

    @Test("every supplied vertex survives, so a path with a corner keeps its corner")
    func verticesKept() {
        let corner = CGPoint(x: 100, y: 0)
        let out = PointerPath.interpolate([CGPoint(x: 0, y: 0), corner, CGPoint(x: 100, y: 100)])
        #expect(out.contains(corner))
        #expect(distances(out).allSatisfy { $0 <= 10 + 1e-9 })
    }

    @Test("a path that does not move still yields a press and a release")
    func zeroLength() {
        let out = PointerPath.interpolate([CGPoint(x: 5, y: 5), CGPoint(x: 5, y: 5)])
        #expect(out.count >= 2)
        #expect(out.first == out.last)
    }

    @Test("a single point cannot be a drag and is returned untouched")
    func single() {
        #expect(PointerPath.interpolate([CGPoint(x: 1, y: 2)]).count == 1)
    }
}

@Suite("Region dirty area")
struct RegionDirtTests {

    private let region = Rect(x: 100, y: 100, w: 200, h: 200)   // 40,000 square units

    @Test("a dirty rect inside the region contributes all of itself")
    func inside() {
        let dirty = Rect(x: 150, y: 150, w: 50, h: 50)
        #expect(RegionDirt.intersectionArea(dirty, region) == 2500)
        #expect(RegionDirt.dirtyFraction([dirty], in: region) == 2500.0 / 40000.0)
    }

    @Test("a dirty rect that only overlaps contributes its intersection")
    func partial() {
        // Half in, half out: counting the whole rect would report twice the
        // change that happened inside the region.
        let dirty = Rect(x: 50, y: 100, w: 100, h: 200)
        #expect(RegionDirt.intersectionArea(dirty, region) == 50 * 200)
        #expect(RegionDirt.dirtyFraction([dirty], in: region) == 10000.0 / 40000.0)
    }

    @Test("a dirty rect outside the region contributes nothing")
    func outside() {
        let dirty = Rect(x: 0, y: 0, w: 50, h: 50)
        #expect(RegionDirt.intersection(dirty, region) == nil)
        #expect(RegionDirt.intersectionArea(dirty, region) == 0)
        #expect(RegionDirt.dirtyFraction([dirty], in: region) == 0)
    }

    @Test("touching edges do not overlap")
    func edgeTouch() {
        #expect(RegionDirt.intersectionArea(Rect(x: 0, y: 100, w: 100, h: 200), region) == 0)
    }

    @Test("a dirty rect covering the region reads as fully dirty")
    func covered() {
        #expect(RegionDirt.dirtyFraction([Rect(x: 0, y: 0, w: 1000, h: 1000)], in: region) == 1)
    }

    @Test("overlapping dirty rects are not double counted")
    func overlapping() {
        let a = Rect(x: 100, y: 100, w: 100, h: 200)
        let b = Rect(x: 150, y: 100, w: 100, h: 200)
        // Union is 150 wide, not 200; summing the two would report 100%.
        #expect(RegionDirt.unionArea([a, b]) == 150 * 200)
        #expect(RegionDirt.dirtyFraction([a, b], in: region) == 30000.0 / 40000.0)
    }

    @Test("a region with no area is unmeasurable, not quiet")
    func degenerate() {
        // Reporting 0 would say the region was quiet, which is a claim about a
        // rectangle nothing was ever measured in.
        #expect(RegionDirt.dirtyFraction([], in: Rect(x: 10, y: 10, w: 0, h: 50)) == nil)
    }

    @Test("no dirty rects at all is a measured zero")
    func noDirt() {
        #expect(RegionDirt.dirtyFraction([], in: region) == 0)
    }
}

@Suite("Error remedies")
struct ErrorTests {
    @Test("a permission error carries a remedy, because a model will otherwise retry it")
    func remedyPresent() {
        let e = AgentError(code: .permissionAccessibility,
                           message: "Accessibility is not granted",
                           remedy: Grantless.fix)
        #expect(e.remedy?.isEmpty == false)
    }

    private enum Grantless {
        static let fix = "System Settings ▸ Privacy & Security ▸ Accessibility, enable Proctor."
    }
}

// MARK: - CUA schema façade

@Suite("CUA schema façade")
struct CUAFacadeTests {

    // A window whose top-left is not the origin, so a coordinate that was mapped
    // and one that was not are distinguishable.
    private let frame = Rect(x: 100, y: 50, w: 800, h: 600)

    private func step(_ cua: CUAStep) -> ActionStep? {
        if case .act(let s) = cua.operation { return s }
        return nil
    }

    // MARK: Anthropic

    @Test("left_click maps to a synthetic click at the window-mapped global point")
    func anthropicLeftClick() throws {
        let plan = try CUATranslator.anthropic(
            .object(["action": .string("left_click"),
                     "coordinate": .array([.number(10), .number(20)])]),
            windowFrame: frame)
        #expect(plan.count == 1)
        let s = try #require(step(plan[0]))
        #expect(s.kind == .click)
        #expect(s.point == [110, 70])   // 100+10, 50+20
    }

    @Test("type carries the text through")
    func anthropicType() throws {
        let plan = try CUATranslator.anthropic(
            .object(["action": .string("type"), "text": .string("hello world")]),
            windowFrame: frame)
        let s = try #require(step(plan[0]))
        #expect(s.kind == .type)
        #expect(s.text == "hello world")
    }

    @Test("key combos split into a key and its modifiers")
    func anthropicKey() throws {
        func parse(_ combo: String) throws -> ActionStep {
            let plan = try CUATranslator.anthropic(
                .object(["action": .string("key"), "text": .string(combo)]), windowFrame: frame)
            return try #require(step(plan[0]))
        }
        let save = try parse("cmd+s")
        #expect(save.kind == .key)
        #expect(save.key == "s")
        #expect(save.modifiers == ["cmd"])

        let ret = try parse("Return")
        #expect(ret.key == "return")
        #expect(ret.modifiers?.isEmpty ?? true)

        let combo = try parse("ctrl+shift+t")
        #expect(combo.key == "t")
        #expect(Set(combo.modifiers ?? []) == ["ctrl", "shift"])
    }

    @Test("mouse_move maps to a hover at the mapped point")
    func anthropicMouseMove() throws {
        let plan = try CUATranslator.anthropic(
            .object(["action": .string("mouse_move"),
                     "coordinate": .array([.number(5), .number(5)])]),
            windowFrame: frame)
        let s = try #require(step(plan[0]))
        #expect(s.kind == .hover)
        #expect(s.point == [105, 55])
    }

    @Test("scroll down becomes a negative dy the actuator reads as down")
    func anthropicScroll() throws {
        let plan = try CUATranslator.anthropic(
            .object(["action": .string("scroll"),
                     "coordinate": .array([.number(5), .number(5)]),
                     "scroll_direction": .string("down"),
                     "scroll_amount": .number(3)]),
            windowFrame: frame)
        let s = try #require(step(plan[0]))
        #expect(s.kind == .scroll)
        #expect(s.delta == [0, -3])
    }

    @Test("screenshot maps to the screenshot operation")
    func anthropicScreenshot() throws {
        let plan = try CUATranslator.anthropic(
            .object(["action": .string("screenshot")]), windowFrame: frame)
        #expect(plan.count == 1)
        if case .screenshot = plan[0].operation {} else {
            Issue.record("expected a screenshot operation")
        }
    }

    @Test("double_click expands to two clicks at the same point")
    func anthropicDoubleClick() throws {
        let plan = try CUATranslator.anthropic(
            .object(["action": .string("double_click"),
                     "coordinate": .array([.number(10), .number(20)])]),
            windowFrame: frame)
        #expect(plan.count == 2)
        for cua in plan {
            let s = try #require(step(cua))
            #expect(s.kind == .click)
            #expect(s.point == [110, 70])
        }
    }

    @Test("left_click_drag maps to a dragPath from start to end, both in global coords")
    func anthropicDrag() throws {
        let plan = try CUATranslator.anthropic(
            .object(["action": .string("left_click_drag"),
                     "start_coordinate": .array([.number(0), .number(0)]),
                     "coordinate": .array([.number(10), .number(20)])]),
            windowFrame: frame)
        let s = try #require(step(plan[0]))
        #expect(s.kind == .dragPath)
        #expect(s.path == [[100, 50], [110, 70]])
    }

    @Test("wait becomes a wait operation with the duration in milliseconds")
    func anthropicWait() throws {
        let plan = try CUATranslator.anthropic(
            .object(["action": .string("wait"), "duration": .number(2)]), windowFrame: frame)
        if case .wait(let ms) = plan[0].operation {
            #expect(ms == 2000)
        } else {
            Issue.record("expected a wait operation")
        }
    }

    @Test("an unmapped action is refused, not silently dropped")
    func anthropicUnknownRefused() {
        #expect(throws: AgentError.self) {
            _ = try CUATranslator.anthropic(
                .object(["action": .string("teleport")]), windowFrame: frame)
        }
    }

    @Test("right_click is refused rather than turned into a left click")
    func anthropicRightClickRefused() {
        #expect(throws: AgentError.self) {
            _ = try CUATranslator.anthropic(
                .object(["action": .string("right_click"),
                         "coordinate": .array([.number(1), .number(1)])]), windowFrame: frame)
        }
    }

    // MARK: OpenAI

    @Test("an OpenAI batch flattens into an ordered plan")
    func openaiBatch() throws {
        let plan = try CUATranslator.openai(
            .array([
                .object(["type": .string("click"), "button": .string("left"),
                         "x": .number(10), "y": .number(20)]),
                .object(["type": .string("type"), "text": .string("hi")]),
                .object(["type": .string("keypress"),
                         "keys": .array([.string("ctrl"), .string("c")])])
            ]),
            windowFrame: frame)
        #expect(plan.count == 3)

        let click = try #require(step(plan[0]))
        #expect(click.kind == .click)
        #expect(click.point == [110, 70])

        let type = try #require(step(plan[1]))
        #expect(type.kind == .type)
        #expect(type.text == "hi")

        let key = try #require(step(plan[2]))
        #expect(key.kind == .key)
        #expect(key.key == "c")
        #expect(key.modifiers == ["ctrl"])
    }

    @Test("a single OpenAI action object is accepted without an array wrapper")
    func openaiSingle() throws {
        let plan = try CUATranslator.openai(
            .object(["type": .string("type"), "text": .string("x")]), windowFrame: frame)
        #expect(plan.count == 1)
        #expect(step(plan[0])?.kind == .type)
    }

    @Test("OpenAI scroll flips the sign so positive scroll_y reads as scroll down")
    func openaiScroll() throws {
        let plan = try CUATranslator.openai(
            .object(["type": .string("scroll"), "x": .number(5), "y": .number(5),
                     "scroll_x": .number(0), "scroll_y": .number(3)]),
            windowFrame: frame)
        let s = try #require(step(plan[0]))
        #expect(s.kind == .scroll)
        #expect(s.delta == [0, -3])
    }

    @Test("OpenAI drag maps its path into global coordinates")
    func openaiDrag() throws {
        let plan = try CUATranslator.openai(
            .object(["type": .string("drag"), "path": .array([
                .object(["x": .number(0), "y": .number(0)]),
                .object(["x": .number(10), "y": .number(20)])
            ])]),
            windowFrame: frame)
        let s = try #require(step(plan[0]))
        #expect(s.kind == .dragPath)
        #expect(s.path == [[100, 50], [110, 70]])
    }

    @Test("a non-left OpenAI click button is refused")
    func openaiRightClickRefused() {
        #expect(throws: AgentError.self) {
            _ = try CUATranslator.openai(
                .object(["type": .string("click"), "button": .string("right"),
                         "x": .number(1), "y": .number(1)]), windowFrame: frame)
        }
    }

    // MARK: Coordinate mapping

    @Test("scale divides the CUA offset before it is added to the window origin")
    func scaleMapping() throws {
        let plan = try CUATranslator.anthropic(
            .object(["action": .string("left_click"),
                     "coordinate": .array([.number(20), .number(40)])]),
            windowFrame: frame, scale: 2)
        let s = try #require(step(plan[0]))
        #expect(s.point == [110, 70])   // 100 + 20/2, 50 + 40/2
    }
}

@Suite("Set of marks")
struct SetOfMarksTests {

    private func element(_ node: String, _ x: Double, _ y: Double,
                         _ w: Double = 10, _ h: Double = 10,
                         role: String = "AXButton", label: String? = nil) -> SetOfMarks.Element {
        SetOfMarks.Element(node: node, role: role, label: label, frame: Rect(x: x, y: y, w: w, h: h))
    }

    @Test("an element frame maps to the expected pixel box, window origin subtracted then scaled")
    func transform() {
        // A wrong transform is the failure that makes every mark point at the
        // wrong place, so it is pinned to an exact expected rectangle.
        let plan = SetOfMarks.plan(
            elements: [element("a", 150, 260, 40, 20)],
            window: Rect(x: 100, y: 200, w: 400, h: 300),
            imageWidth: 800, imageHeight: 600, scale: 2)
        #expect(plan.marks.count == 1)
        let m = plan.marks[0]
        #expect(m.pixelRect == Rect(x: 100, y: 120, w: 80, h: 40))
        #expect(m.id == 1)
        #expect(m.node == "a")
        #expect(m.frame == Rect(x: 150, y: 260, w: 40, h: 20))
    }

    @Test("marks are numbered in reading order: top to bottom, then left to right")
    func readingOrder() {
        let plan = SetOfMarks.plan(
            elements: [element("a", 50, 100), element("b", 50, 50), element("c", 200, 50)],
            window: Rect(x: 0, y: 0, w: 1000, h: 1000),
            imageWidth: 1000, imageHeight: 1000, scale: 1)
        let ids = Dictionary(uniqueKeysWithValues: plan.marks.map { ($0.node, $0.id) })
        #expect(ids["b"] == 1)   // topmost
        #expect(ids["c"] == 2)   // same row, further right
        #expect(ids["a"] == 3)
    }

    @Test("the same elements produce the same ids, regardless of input order")
    func stableIds() {
        // Stable ids within a snapshot revision is a binding assumption of the
        // spec: "click mark 7" has to mean the same element on a re-capture.
        let els = [element("a", 50, 100), element("b", 50, 50), element("c", 200, 50)]
        let window = Rect(x: 0, y: 0, w: 1000, h: 1000)
        let first = SetOfMarks.plan(elements: els, window: window,
                                    imageWidth: 1000, imageHeight: 1000, scale: 1)
        let shuffled = SetOfMarks.plan(elements: els.reversed(), window: window,
                                       imageWidth: 1000, imageHeight: 1000, scale: 1)
        #expect(first.marks == shuffled.marks)
    }

    @Test("an element outside the captured frame gets no mark")
    func culledWhenOffFrame() {
        let plan = SetOfMarks.plan(
            elements: [element("on", 10, 10), element("off", 1000, 10)],
            window: Rect(x: 0, y: 0, w: 2000, h: 600),
            imageWidth: 800, imageHeight: 600, scale: 1)
        let nodes = Set(plan.marks.map(\.node))
        #expect(nodes.contains("on"))
        #expect(!nodes.contains("off"))
        #expect(plan.elementsConsidered == 2)
        #expect(plan.markedCount == 1)
    }

    @Test("a partially visible element is marked with its box clamped to the image")
    func clampedWhenPartlyOff() {
        let plan = SetOfMarks.plan(
            elements: [element("edge", -10, 10, 40, 20)],
            window: Rect(x: 0, y: 0, w: 800, h: 600),
            imageWidth: 800, imageHeight: 600, scale: 1)
        #expect(plan.marks.count == 1)
        // Raw box (-10,10,40,20) clipped to the image starts at x=0 and keeps 30 wide.
        #expect(plan.marks[0].pixelRect == Rect(x: 0, y: 10, w: 30, h: 20))
        // The map still points at the true element frame, so actuation resolves it.
        #expect(plan.marks[0].frame == Rect(x: -10, y: 10, w: 40, h: 20))
    }

    @Test("a zero-area element carries no place to draw a box and is dropped")
    func zeroAreaDropped() {
        let plan = SetOfMarks.plan(
            elements: [element("real", 10, 10, 20, 20), element("empty", 40, 40, 0, 12)],
            window: Rect(x: 0, y: 0, w: 800, h: 600),
            imageWidth: 800, imageHeight: 600, scale: 1)
        #expect(plan.marks.map(\.node) == ["real"])
    }

    @Test("the mark cap truncates in reading order and reports what it dropped")
    func capped() {
        let els = (0..<5).map { element("n\($0)", 10, Double($0) * 30) }
        let plan = SetOfMarks.plan(elements: els, window: Rect(x: 0, y: 0, w: 800, h: 600),
                                   imageWidth: 800, imageHeight: 600, scale: 1, maxMarks: 3)
        #expect(plan.markedCount == 3)
        #expect(plan.elementsConsidered == 5)
        #expect(plan.truncated == true)
        #expect(plan.marks.map(\.node) == ["n0", "n1", "n2"])
    }

    @Test("every mark carries its source node, role and label for the map back")
    func mapBack() {
        let plan = SetOfMarks.plan(
            elements: [element("btn", 10, 10, role: "AXButton", label: "Save")],
            window: Rect(x: 0, y: 0, w: 800, h: 600),
            imageWidth: 800, imageHeight: 600, scale: 1)
        let m = try! #require(plan.marks.first)
        #expect(m.node == "btn")
        #expect(m.role == "AXButton")
        #expect(m.label == "Save")
    }

    @Test("a grid places interior lines every spacing*scale pixels")
    func gridLines() {
        let plan = SetOfMarks.plan(
            elements: [], window: Rect(x: 0, y: 0, w: 400, h: 300),
            imageWidth: 800, imageHeight: 600, scale: 2,
            grid: SetOfMarks.GridOptions(enabled: true, spacingPoints: 100))
        let grid = try! #require(plan.grid)
        #expect(grid.verticals == [200, 400, 600])     // step 200px, under 800
        #expect(grid.horizontals == [200, 400])        // under 600
        #expect(grid.spacingPoints == 100)
        #expect(grid.scale == 2)
    }

    @Test("no grid is produced when it is not asked for")
    func noGrid() {
        let plan = SetOfMarks.plan(
            elements: [element("a", 10, 10)], window: Rect(x: 0, y: 0, w: 800, h: 600),
            imageWidth: 800, imageHeight: 600, scale: 1)
        #expect(plan.grid == nil)
    }

    @Test("proctor_capture advertises the annotate flag and stays read-only")
    func captureSchema() {
        let cap = try! #require(ToolCatalogue.spec(named: "proctor_capture"))
        let props = cap.inputSchema["properties"]?.objectValue
        #expect(props?["annotate"] != nil)
        #expect(props?["grid"] != nil)
        #expect(props?["maxMarks"] != nil)
        #expect(cap.readOnly == true)   // annotation adds an output, it does not act on the app
    }
}

@Suite("Menu key-equivalents")
struct MenuKeyEquivalentTests {

    // MARK: AC1 — Carbon modifier decode (command implied)

    @Test("command is implied unless the no-command bit is set")
    func modifierDecode() {
        // A wrong reading here inverts every shortcut the tool reports, so each
        // case is pinned. Order is canonical: cmd, ctrl, opt, shift.
        #expect(MenuKeyEquivalent.modifiers(fromCarbonMask: 0x00) == ["cmd"])
        #expect(MenuKeyEquivalent.modifiers(fromCarbonMask: 0x01) == ["cmd", "shift"])
        #expect(MenuKeyEquivalent.modifiers(fromCarbonMask: 0x02) == ["cmd", "opt"])
        #expect(MenuKeyEquivalent.modifiers(fromCarbonMask: 0x04) == ["cmd", "ctrl"])
        // The no-command bit removes ⌘ — a menu item whose equivalent is a bare F-key.
        #expect(MenuKeyEquivalent.modifiers(fromCarbonMask: 0x08) == [])
        #expect(MenuKeyEquivalent.modifiers(fromCarbonMask: 0x09) == ["shift"])
        // Everything at once, command still implied.
        #expect(MenuKeyEquivalent.modifiers(fromCarbonMask: 0x07) == ["cmd", "ctrl", "opt", "shift"])
    }

    // MARK: AC2 — normalised shortcut string

    @Test("a character equivalent normalises cmd-first and lowercased")
    func shortcutFromChar() {
        #expect(MenuKeyEquivalent.shortcut(char: "N", virtualKey: nil, glyph: nil, carbonMask: 0)
                == "cmd+n")
        // The spec's own example.
        #expect(MenuKeyEquivalent.shortcut(char: "N", virtualKey: nil, glyph: nil, carbonMask: 0x01)
                == "cmd+shift+n")
    }

    @Test("no resolvable key means no shortcut, whatever the modifiers say")
    func noKeyNoShortcut() {
        // A parent menu ("File") carries no equivalent; modifiers alone are not one.
        #expect(MenuKeyEquivalent.shortcut(char: nil, virtualKey: nil, glyph: nil, carbonMask: 0)
                == nil)
        #expect(MenuKeyEquivalent.shortcut(char: "", virtualKey: nil, glyph: nil, carbonMask: 0)
                == nil)
    }

    // MARK: AC3 — non-character equivalents (virtual key + glyph)

    @Test("a virtual keycode resolves to its key name")
    func shortcutFromVirtualKey() {
        // cmd + left arrow — no printable char, so it arrives as a virtual key.
        #expect(MenuKeyEquivalent.shortcut(char: nil, virtualKey: 123, glyph: nil, carbonMask: 0)
                == "cmd+left")
        // Bare F2 (no-command bit set), the classic modifier-less menu equivalent.
        #expect(MenuKeyEquivalent.shortcut(char: nil, virtualKey: 120, glyph: nil, carbonMask: 0x08)
                == "f2")
    }

    @Test("a menu glyph resolves to its key name")
    func shortcutFromGlyph() {
        // Page Up glyph (0x62) and Escape glyph (0x1B).
        #expect(MenuKeyEquivalent.shortcut(char: nil, virtualKey: nil, glyph: 0x62, carbonMask: 0)
                == "cmd+pageup")
        #expect(MenuKeyEquivalent.shortcut(char: nil, virtualKey: nil, glyph: 0x1B, carbonMask: 0x08)
                == "escape")
    }

    @Test("a function-key character is rejected so the virtual key wins")
    func functionKeyCharFallsThrough() {
        // AppKit reports arrow/function equivalents with a private-use scalar in
        // cmdChar; treating it as printable would emit a garbage shortcut, so it is
        // rejected and the virtual key is used instead.
        let functionKeyChar = String(UnicodeScalar(0xF702)!)   // NSLeftArrowFunctionKey
        #expect(MenuKeyEquivalent.normalisedChar(functionKeyChar) == nil)
        #expect(MenuKeyEquivalent.shortcut(char: functionKeyChar, virtualKey: 123, glyph: nil,
                                           carbonMask: 0) == "cmd+left")
    }

    // MARK: AC5 — flatten

    private func tree() -> [RawMenuItem] {
        [
            RawMenuItem(title: "File", enabled: true, hasSubmenu: true, submenuPopulated: true,
                        children: [
                            RawMenuItem(title: "New", enabled: true, cmdChar: "N", cmdModifiers: 0),
                            RawMenuItem(title: nil, enabled: false, isSeparator: true),
                            RawMenuItem(title: "New from Clipboard", enabled: false,
                                        cmdChar: "N", cmdModifiers: 0x01),
                            // A submenu macOS has not built yet — must not be fabricated.
                            RawMenuItem(title: "Open Recent", enabled: true,
                                        hasSubmenu: true, submenuPopulated: false,
                                        children: []),
                        ]),
        ]
    }

    @Test("every non-separator item becomes a row with its full menu path")
    func flattenPaths() {
        let rows = MenuKeyEquivalent.flatten(bar: tree())
        let paths = rows.map(\.path)
        #expect(paths.contains(["File"]))
        #expect(paths.contains(["File", "New"]))
        #expect(paths.contains(["File", "New from Clipboard"]))
        #expect(paths.contains(["File", "Open Recent"]))
    }

    @Test("separators are dropped, not emitted as blank rows")
    func flattenDropsSeparators() {
        let rows = MenuKeyEquivalent.flatten(bar: tree())
        // File, New, New from Clipboard, Open Recent — the separator is gone.
        #expect(rows.count == 4)
        #expect(rows.allSatisfy { !$0.title.isEmpty })
    }

    @Test("a leaf carries its shortcut decomposed for the act key step")
    func flattenLeafShortcut() {
        let rows = MenuKeyEquivalent.flatten(bar: tree())
        let new = try! #require(rows.first { $0.path == ["File", "New"] })
        #expect(new.shortcut == "cmd+n")
        #expect(new.key == "n")
        #expect(new.modifiers == ["cmd"])
        #expect(new.enabled == true)
        #expect(new.hasSubmenu == false)

        let shifted = try! #require(rows.first { $0.path == ["File", "New from Clipboard"] })
        #expect(shifted.shortcut == "cmd+shift+n")
        #expect(shifted.enabled == false)
    }

    @Test("a parent menu is a row with a submenu and no shortcut")
    func flattenParentRow() {
        let rows = MenuKeyEquivalent.flatten(bar: tree())
        let file = try! #require(rows.first { $0.path == ["File"] })
        #expect(file.hasSubmenu == true)
        #expect(file.submenuPopulated == true)
        #expect(file.shortcut == nil)
        #expect(file.key == nil)
    }

    @Test("a lazily-populated submenu is one row and its contents are not fabricated")
    func flattenLazySubmenu() {
        let rows = MenuKeyEquivalent.flatten(bar: tree())
        let recent = try! #require(rows.first { $0.path == ["File", "Open Recent"] })
        #expect(recent.hasSubmenu == true)
        #expect(recent.submenuPopulated == false)
        // Nothing was invented beneath a submenu that had not been read.
        #expect(rows.allSatisfy { $0.path.count <= 2 })
        #expect(!rows.contains { $0.path.starts(with: ["File", "Open Recent"]) && $0.path.count > 2 })
    }

    // MARK: AC4 — catalogue

    @Test("proctor_menu is advertised, read-only, non-destructive and idempotent")
    func catalogueEntry() {
        let menu = try! #require(ToolCatalogue.spec(named: "proctor_menu"))
        #expect(menu.readOnly == true)
        #expect(menu.destructive == false)
        #expect(menu.idempotent == true)
        #expect(menu.name.hasPrefix("proctor_"))
        #expect(menu.inputSchema["type"]?.stringValue == "object")
        #expect(ToolCatalogue.outputSchema(for: "proctor_menu")["type"]?.stringValue == "object")
    }

    @Test("every tool profile exposes proctor_menu, since it is a pure accessibility read")
    func inEveryProfile() {
        for profile in ToolProfile.allCases {
            #expect(ToolCatalogue.toolNames(for: profile).contains("proctor_menu"),
                    "\(profile.rawValue) drops proctor_menu")
        }
    }
}

@Suite("Scripting dictionary")
struct ScriptingDictionaryTests {

    // A compact but faithful sdef: a standard suite with commands, a class with
    // properties and elements, and an enumeration; an app suite that extends the
    // application class. Modelled on real merged `sdef` output.
    private static let sdef = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE dictionary SYSTEM "file://localhost/System/Library/DTDs/sdef.dtd">
    <dictionary>
      <suite name="Standard Suite" code="????" description="Common commands.">
        <command name="open" code="aevtodoc" description="Open an object.">
          <direct-parameter type="alias" description="The file(s) to open."/>
          <result type="document"/>
        </command>
        <command name="save" code="coresave" description="Save an object.">
          <direct-parameter type="specifier" description="the object"/>
          <parameter name="in" code="kfil" type="alias" optional="yes" description="The file."/>
        </command>
        <class name="document" code="docu" description="A document." inherits="item" plural="documents">
          <element type="window"/>
          <property name="name" code="pnam" type="text" description="The name."/>
          <property name="modified" code="imod" type="boolean" access="r" description="Modified?"/>
        </class>
        <enumeration name="savo" code="savo">
          <enumerator name="yes" code="yes " description="Save."/>
          <enumerator name="no" code="no  " description="Do not save."/>
        </enumeration>
      </suite>
      <suite name="App Suite" code="txdt" description="App specific.">
        <class-extension extends="application" description="Top level object.">
          <property name="frontDocument" code="pfrd" type="document" access="r" description="Front doc."/>
        </class-extension>
      </suite>
    </dictionary>
    """

    private func parsed() -> AppScriptingDictionary {
        ScriptingDictionary.parse(sdefXML: Data(Self.sdef.utf8), appName: "Editor")
    }

    @Test("a realistic sdef parses into suites, commands, classes and enumerations")
    func parsesSdefIntoStructure() {
        let dict = parsed()
        #expect(dict.appName == "Editor")
        #expect(dict.scriptable == true)
        #expect(dict.suites.count == 2)

        let standard = try! #require(dict.suites.first { $0.name == "Standard Suite" })
        #expect(standard.code == "????")
        #expect(standard.commands.map(\.name) == ["open", "save"])

        let open = try! #require(standard.commands.first { $0.name == "open" })
        #expect(open.code == "aevtodoc")
        #expect(open.resultType == "document")
        #expect(open.parameters.first?.direct == true)

        let save = try! #require(standard.commands.first { $0.name == "save" })
        // A named optional parameter carries its code and its optional flag.
        let inParam = try! #require(save.parameters.first { $0.name == "in" })
        #expect(inParam.code == "kfil")
        #expect(inParam.optional == true)
        #expect(inParam.direct == false)

        let document = try! #require(standard.classes.first { $0.name == "document" })
        #expect(document.code == "docu")
        #expect(document.inherits == "item")
        #expect(document.plural == "documents")
        #expect(document.elements == ["window"])
        #expect(document.properties.map(\.name) == ["name", "modified"])
        // sdef omits access for read-write; a read-only property keeps its "r".
        #expect(document.properties.first { $0.name == "name" }?.access == "rw")
        #expect(document.properties.first { $0.name == "modified" }?.access == "r")

        let savo = try! #require(standard.enumerations.first { $0.name == "savo" })
        #expect(savo.enumerators.map(\.name) == ["yes", "no"])
    }

    @Test("counts aggregate across every suite")
    func countsAggregateAcrossSuites() {
        let c = parsed().counts
        #expect(c.suites == 2)
        #expect(c.commands == 2)          // open, save
        #expect(c.classes == 2)           // document + the application extension
        #expect(c.properties == 3)        // name, modified, frontDocument
        #expect(c.enumerations == 1)
    }

    @Test("a class-extension is captured, named by what it extends, and its properties count")
    func classExtensionCaptured() {
        let dict = parsed()
        let appSuite = try! #require(dict.suites.first { $0.name == "App Suite" })
        let ext = try! #require(appSuite.classes.first)
        #expect(ext.isExtension == true)
        #expect(ext.name == "application")     // the class it extends, not a new name
        #expect(ext.properties.map(\.name) == ["frontDocument"])
    }

    @Test("the capability summary is one line naming the app, scriptability and counts")
    func summaryIsOneLine() {
        let summary = parsed().summary
        #expect(!summary.contains("\n"))
        #expect(summary.contains("Editor"))
        #expect(summary.contains("scriptable"))
        #expect(summary.contains("2 commands"))
        #expect(summary.contains("open"))   // a few command names for orientation
    }

    @Test("an app with no commands is classified not scriptable with a route hint")
    func noCommandsIsNotScriptable() {
        let onlyTypes = """
        <?xml version="1.0"?>
        <dictionary>
          <suite name="Type Definitions" code="tpdf" description="Records only.">
            <class name="print settings" code="pset">
              <property name="copies" code="lwcp" type="integer"/>
            </class>
          </suite>
        </dictionary>
        """
        let dict = ScriptingDictionary.parse(sdefXML: Data(onlyTypes.utf8), appName: "Widget")
        #expect(dict.scriptable == false)
        #expect(dict.counts.commands == 0)
        #expect(dict.summary.contains("not scriptable"))
        #expect(dict.summary.lowercased().contains("accessibility"))
    }

    @Test("empty or malformed input degrades to a not-scriptable result rather than throwing")
    func emptyInputDoesNotThrow() {
        let empty = ScriptingDictionary.parse(sdefXML: Data(), appName: "Nothing")
        #expect(empty.scriptable == false)
        #expect(empty.suites.isEmpty)
        #expect(empty.summary.contains("not scriptable"))

        let junk = ScriptingDictionary.parse(sdefXML: Data("not xml at all <<<".utf8), appName: "Junk")
        #expect(junk.scriptable == false)
        #expect(junk.suites.isEmpty)
    }

    @Test("the per-app cache hits for the same handle and misses after a relaunch")
    func cacheInvalidatesOnRelaunch() {
        // A relaunch keeps the pid but advances the epoch in the handle id, so a
        // cache keyed on the id serves per-PID and invalidates on relaunch.
        let before = AppHandle(id: "app:4242:100", pid: 4242, bundleId: "com.example.editor", name: "Editor")
        let afterRelaunch = AppHandle(id: "app:4242:200", pid: 4242, bundleId: "com.example.editor", name: "Editor")

        var cache = ScriptingDictionaryCache()
        cache.store(parsed(), for: before)

        #expect(cache.value(for: before) != nil)          // same handle: a hit
        #expect(cache.value(for: afterRelaunch) == nil)   // relaunched: a miss, so a fresh read

        cache.store(parsed(), for: afterRelaunch)
        #expect(cache.count == 2)
        cache.drop(for: before)
        #expect(cache.value(for: before) == nil)
        #expect(cache.value(for: afterRelaunch) != nil)
    }

    @Test("proctor_dictionary is advertised, read-only, non-destructive and object-schema'd")
    func dictionaryToolAdvertised() {
        let spec = try! #require(ToolCatalogue.spec(named: "proctor_dictionary"))
        #expect(spec.readOnly == true)
        #expect(spec.destructive == false)
        #expect(spec.idempotent == true)
        let props = spec.inputSchema["properties"]?.objectValue
        #expect(props?["app"] != nil)
        #expect(props?["window"] != nil)
        let schema = ToolCatalogue.outputSchema(for: "proctor_dictionary")
        #expect(schema["type"]?.stringValue == "object")
        #expect(schema["properties"]?["scriptable"] != nil)
    }

    @Test("the dictionary tool sits in the scripting profile, preserving the nesting")
    func dictionaryInScriptingProfile() {
        #expect(ToolCatalogue.toolNames(for: .scripting).contains("proctor_dictionary"))
        #expect(!ToolCatalogue.toolNames(for: .core).contains("proctor_dictionary"))
    }
}
// MARK: - Policy gate

@Suite("Policy gate")
struct PolicyGateTests {

    @Test("a blocked bundle id is refused with a reason, not driven")
    func blockedIsRefused() {
        // Fail-closed is the whole point: the gate exists to stop an agent
        // wandering into a password manager, so a blocked app must never resolve
        // to .allow, and the refusal has to say why.
        let policy = AppPolicy(block: ["com.apple.keychainaccess"])
        let decision = policy.decide(bundleId: "com.apple.keychainaccess", hasValidToken: false)
        guard case .blocked(let reason) = decision else {
            Issue.record("a blocked app should be refused, got \(decision)")
            return
        }
        #expect(reason.contains("com.apple.keychainaccess"))
    }

    @Test("block wins even when the same app is also on the allow list")
    func blockBeatsAllow() {
        let policy = AppPolicy(allow: ["com.example.app"], block: ["com.example.app"])
        #expect(policy.decide(bundleId: "com.example.app", hasValidToken: true)
                == .blocked(reason: "com.example.app is on the block list; actuation is refused."))
    }

    @Test("an allow list refuses anything it does not name, including an unidentifiable app")
    func allowListFailsClosed() {
        let policy = AppPolicy(allow: ["com.example.underTest"])
        // A different app is refused.
        if case .allow = policy.decide(bundleId: "com.other.app", hasValidToken: false) {
            Issue.record("an app not on the allow list should be refused")
        }
        // An app whose bundle id could not be resolved is refused rather than
        // driven — the gate cannot vouch for what it cannot identify.
        if case .allow = policy.decide(bundleId: nil, hasValidToken: false) {
            Issue.record("an unidentifiable app should be refused under an allow list")
        }
        // The named app is allowed.
        #expect(policy.decide(bundleId: "com.example.underTest", hasValidToken: false) == .allow)
    }

    @Test("a sensitive app needs a token: refused without, allowed with")
    func sensitiveNeedsToken() {
        let policy = AppPolicy(sensitive: ["com.apple.Passwords"])
        let without = policy.decide(bundleId: "com.apple.Passwords", hasValidToken: false)
        guard case .needsApproval = without else {
            Issue.record("a sensitive app without a token should need approval, got \(without)")
            return
        }
        #expect(policy.decide(bundleId: "com.apple.Passwords", hasValidToken: true) == .allow)
    }

    @Test("an unlisted app under no allow list is allowed")
    func ordinaryAppAllowed() {
        let policy = AppPolicy(block: ["com.apple.keychainaccess"],
                               sensitive: ["com.apple.Passwords"])
        #expect(policy.decide(bundleId: "com.apple.TextEdit", hasValidToken: false) == .allow)
    }
}

@Suite("Approval token TTL")
struct ApprovalTokenTests {

    @Test("a token is valid before its expiry and invalid after, like the unlock turn")
    func ttlBounds() {
        let t = ApprovalToken.mint(bundleId: nil, ttl: 15, now: 1_000)
        #expect(t.isValid(at: 1_000, for: "com.example.app"))   // at issue
        #expect(t.isValid(at: 1_014, for: "com.example.app"))   // inside TTL
        #expect(!t.isValid(at: 1_015, for: "com.example.app"))  // at expiry
        #expect(!t.isValid(at: 2_000, for: "com.example.app"))  // well past
    }

    @Test("a scoped token authorizes only its own bundle id; nil scope authorizes any")
    func scope() {
        let scoped = ApprovalToken.mint(bundleId: "com.apple.Passwords", ttl: 15, now: 0)
        #expect(scoped.isValid(at: 5, for: "com.apple.Passwords"))
        #expect(!scoped.isValid(at: 5, for: "com.other.app"))

        let anyApp = ApprovalToken.mint(bundleId: nil, ttl: 15, now: 0)
        #expect(anyApp.isValid(at: 5, for: "com.apple.Passwords"))
        #expect(anyApp.isValid(at: 5, for: "com.other.app"))
    }

    @Test("a minted token carries a non-empty secret")
    func hasSecret() {
        #expect(!ApprovalToken.mint(bundleId: nil, ttl: 15, now: 0).token.isEmpty)
    }
}

// MARK: - Redacting audit

@Suite("Redacting audit")
struct RedactingAuditTests {

    private func typeStep(_ text: String) -> ActionStep {
        ActionStep(kind: .type, text: text)
    }

    @Test("a value is stored as length plus SHA-256, verifiable against a known input")
    func redactionShape() {
        let secret = "hunter2-the-password"
        let r = Redaction(of: secret)
        #expect(r.len == secret.utf8.count)
        // The hash matches what an independent SHA-256 of the same bytes produces,
        // so the log proves the value without storing it.
        #expect(r.sha256 == Redaction(of: "hunter2-the-password").sha256)
        #expect(r.sha256 != Redaction(of: "hunter3-the-password").sha256)
        #expect(r.sha256.count == 64)   // 32 bytes, hex
    }

    @Test("a typed secret never appears in the audit line in the clear")
    func noCleartextInLine() {
        // This is the property the whole redaction exists for: the serialised
        // record must not contain the secret, only its length and hash.
        let secret = "S3cr3t-Bank-PIN-4291"
        let record = AuditRecord.forStep(
            typeStep(secret), tool: "proctor_act", timestamp: 1_700_000_000,
            app: "app:42:1", bundleId: "com.example.bank", window: "win:1:1",
            outcome: "ok", postStateHash: "abc123")
        let line = record.jsonLine()
        #expect(!line.contains(secret))
        #expect(line.contains(Redaction(of: secret).sha256))
        #expect(record.value == Redaction(of: secret))
        #expect(record.script == nil)
    }

    @Test("a script body is redacted into the script slot, not the value slot")
    func scriptRedacted() {
        let body = "tell application \"Finder\" to empty trash"
        let record = AuditRecord.forStep(
            ActionStep(kind: .appleScript, text: body), tool: "proctor_act",
            timestamp: 0, app: nil, bundleId: nil, window: nil, outcome: "ok",
            postStateHash: nil)
        #expect(record.script == Redaction(of: body))
        #expect(record.value == nil)
        #expect(!record.jsonLine().contains("empty trash"))
    }

    @Test("a setValue string is redacted the same way a typed value is")
    func setValueRedacted() {
        let record = AuditRecord.forStep(
            ActionStep(kind: .setValue, value: .string("token-abc")), tool: "proctor_act",
            timestamp: 0, app: nil, bundleId: nil, window: nil, outcome: "ok",
            postStateHash: nil)
        #expect(record.value == Redaction(of: "token-abc"))
        #expect(!record.jsonLine().contains("token-abc"))
    }

    @Test("a non-secret step carries no redaction but still accounts for the action")
    func accountsForActionWithoutSecret() {
        // Every action is accounted for: even a press with no free text records
        // the tool, the target and the resulting state hash, so the trail is
        // complete rather than only covering the steps that carried a secret.
        let record = AuditRecord.forStep(
            ActionStep(kind: .press, node: "n7"), tool: "proctor_act", timestamp: 1_700_000_000,
            app: "app:42:1", bundleId: "com.example.app", window: "win:1:1",
            outcome: "ok", postStateHash: "deadbeef")
        #expect(record.value == nil && record.script == nil)
        #expect(record.tool == "proctor_act")
        #expect(record.node == "n7")
        #expect(record.window == "win:1:1")
        #expect(record.outcome == "ok")
        #expect(record.postStateHash == "deadbeef")
    }

    @Test("a refusal is recorded as its own accounted-for event with a reason")
    func refusalRecorded() {
        let record = AuditRecord(timestamp: 1_700_000_000, tool: "proctor_act",
                                 app: "app:9:1", bundleId: "com.apple.keychainaccess",
                                 window: "win:1:1", outcome: "refused",
                                 reason: "on the block list")
        #expect(record.outcome == "refused")
        #expect(record.reason == "on the block list")
        #expect(record.jsonLine().contains("refused"))
    }
}


@Suite("Vision-capture normalisation")
struct VisionCaptureTests {

    // The whole feature exists to stop a vision API silently downsampling an
    // oversized frame to an unknown factor. These pin the factor it must apply
    // and prove the coordinate round-trip that factor is reported for.

    // MARK: AC1 — the long-edge ceiling binds and aspect is preserved

    @Test("a frame over the long-edge ceiling scales its long edge to the ceiling")
    func longEdgeCeiling() {
        // 3000x1500 is under 1.15MP-per-nothing on the edge but way over 1568 wide.
        let fit = VisionCapture.fit(width: 3000, height: 1500,
                                    maxLongEdge: 1568, maxPixels: 100_000_000)
        #expect(fit.applied)
        #expect(fit.width == 1568)                      // long edge sits exactly on the ceiling
        #expect(fit.height == 784)                      // aspect 2:1 preserved
        #expect(abs(fit.scale - 1568.0 / 3000.0) < 1e-9) // scale == out/in
        #expect(fit.scale < 1)
    }

    // MARK: AC2 — the pixel-count ceiling binds independently of the long edge

    @Test("a near-square frame under the edge ceiling is scaled by the pixel budget")
    func pixelCountCeiling() {
        // 1500x1500 = 2.25MP: each side is under 1568, but the area is over 1.15MP.
        let fit = VisionCapture.fit(width: 1500, height: 1500,
                                    maxLongEdge: 1568, maxPixels: 1_150_000)
        #expect(fit.applied)
        #expect(fit.width * fit.height <= 1_150_000)     // brought under the pixel budget
        // One pixel more per side would breach it, so the fit is tight, not timid.
        #expect((fit.width + 1) * (fit.height + 1) > 1_150_000)
        let expected = (1_150_000.0 / (1500.0 * 1500.0)).squareRoot()
        #expect(abs(fit.scale - expected) < 1e-9)
    }

    // MARK: AC3 — opting in never touches a frame already within the ceilings

    @Test("a frame within both ceilings is returned unchanged with scale 1")
    func withinCeilingIsNoOp() {
        let fit = VisionCapture.fit(width: 1200, height: 800,
                                    maxLongEdge: 1568, maxPixels: 1_150_000)
        #expect(!fit.applied)
        #expect(fit.scale == 1)
        #expect(fit.width == 1200 && fit.height == 800) // no upscale, no degrade
    }

    // MARK: AC4 — the reported factor makes the coordinate round-trip exact

    @Test("mapping a coordinate to normalised space and back returns it")
    func roundTripIsExact() {
        let fit = VisionCapture.fit(width: 3000, height: 1500)   // real ceilings
        let nativeX = 2200.0, nativeY = 900.0
        let nx = VisionCapture.toNormalized(nativeX, scale: fit.scale)
        let ny = VisionCapture.toNormalized(nativeY, scale: fit.scale)
        #expect(abs(VisionCapture.toNative(nx, scale: fit.scale) - nativeX) < 1e-9)
        #expect(abs(VisionCapture.toNative(ny, scale: fit.scale) - nativeY) < 1e-9)
    }

    @Test("a model coordinate in the normalised frame maps onto native geometry")
    func modelCoordinateMapsToNative() {
        // A model looking at the downscaled 1568-wide frame clicks its centre.
        let fit = VisionCapture.fit(width: 3136, height: 1568,
                                    maxLongEdge: 1568, maxPixels: 100_000_000)
        #expect(fit.scale == 0.5)
        let modelX = 784.0            // centre of the 1568-wide normalised frame
        #expect(VisionCapture.toNative(modelX, scale: fit.scale) == 1568.0) // native centre of 3136
        // A rectangle maps whole, so a set-of-marks box round-trips too.
        let box = VisionCapture.toNative(Rect(x: 100, y: 50, w: 40, h: 20), scale: fit.scale)
        #expect(box == Rect(x: 200, y: 100, w: 80, h: 40))
    }

    @Test("a non-positive scale is treated as identity rather than dividing by zero")
    func degenerateScaleIsIdentity() {
        #expect(VisionCapture.toNative(123.0, scale: 0) == 123.0)
        #expect(VisionCapture.toNormalized(123.0, scale: -1) == 123.0)
    }

    // MARK: AC5 — the result carries the factor, and stays byte-compatible when absent

    @Test("a CaptureResult round-trips its normalization block through JSON")
    func normalizationEncodes() throws {
        let norm = CaptureNormalization(scale: 0.5, applied: true,
                                        originalWidth: 3136, originalHeight: 1568,
                                        width: 1568, height: 784,
                                        maxLongEdge: 1568, maxPixels: 1_150_000)
        let result = CaptureResult(window: "win:1:1", path: "/tmp/x.png",
                                   width: 1568, height: 784, scale: 1.0,
                                   status: .complete, contentRect: nil,
                                   dirtyRectCount: 0, dirtyArea: 0, capturedAt: 1,
                                   framesWaited: 1, trustworthy: true,
                                   normalization: norm)
        let data = try JSONEncoder().encode(result)
        let back = try JSONDecoder().decode(CaptureResult.self, from: data)
        #expect(back.normalization == norm)
        #expect(back.normalization?.scale == 0.5)
    }

    @Test("a raw capture omits the normalization key entirely")
    func rawCaptureHasNoNormalizationKey() throws {
        let result = CaptureResult(window: "win:1:1", path: "/tmp/x.png",
                                   width: 800, height: 600, scale: 2.0,
                                   status: .complete, contentRect: nil,
                                   dirtyRectCount: 0, dirtyArea: 0, capturedAt: 1,
                                   framesWaited: 1, trustworthy: true)
        let json = String(data: try JSONEncoder().encode(result), encoding: .utf8) ?? ""
        #expect(!json.contains("normalization"))   // default stays byte-compatible
    }

    // MARK: AC6 — normalisation is an option on capture, not a new tool

    @Test("proctor_capture advertises normalize and the catalogue stays at 17 tools")
    func captureAdvertisesNormalizeWithoutANewTool() {
        #expect(ToolCatalogue.all.count == 17)      // extended, not added
        let cap = try! #require(ToolCatalogue.spec(named: "proctor_capture"))
        let props = cap.inputSchema["properties"]?.objectValue
        #expect(props?["normalize"] != nil)
        #expect(props?["normalizeMaxLongEdge"] != nil)
        #expect(props?["normalizeMaxPixels"] != nil)
        #expect(cap.readOnly == true)               // normalisation is a read, not an act
        let out = ToolCatalogue.outputSchema(for: "proctor_capture")
        #expect(out["properties"]?["normalization"] != nil)
    }
}
