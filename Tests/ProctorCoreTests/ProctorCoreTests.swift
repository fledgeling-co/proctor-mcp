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

    @Test("eleven tools are advertised")
    func count() {
        #expect(ToolCatalogue.all.count == 11)
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
        let mutating = ["proctor_act", "proctor_apps", "proctor_flow", "proctor_stability"]
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
