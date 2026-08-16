import Foundation
import CoreGraphics
import ProctorCore

// Assertions. The one rule that shapes this file: an assertion that could not
// be evaluated is reported `skipped` with the reason, never as a pass. A suite
// whose unevaluated checks read as green is worth less than no suite, because
// it is trusted.

extension Session {

    private enum Verdict: String {
        case pass, fail, skipped
    }

    private struct Outcome {
        var status: Verdict
        var observed: JSONValue = .null
        var expected: JSONValue = .null
        var reason: String?
        var node: String?
        var detail: JSONValue?
    }

    func assertAll(window id: String, assertions: [JSONValue],
                   captureEvidence: Bool) async throws -> JSONValue {
        let window = try windowHandle(id)
        let outcome = try walk(window: id)
        var index: [String: AXNode] = [:]
        for node in outcome.root.inTreeOrder() { index[node.id] = node }

        var evidencePath: String?
        var rendered: [JSONValue] = []
        var passed = 0, failed = 0, skipped = 0

        for (position, raw) in assertions.enumerated() {
            let kind = raw["kind"]?.stringValue ?? ""
            let label = raw["label"]?.stringValue
            let result = await evaluate(kind: kind, spec: raw, window: window,
                                        tree: outcome.root, index: index)

            var entry: [String: JSONValue] = [
                "index": .number(Double(position)),
                "kind": .string(kind),
                "status": .string(result.status.rawValue),
                "expected": result.expected,
                "observed": result.observed
            ]
            if let label { entry["label"] = .string(label) }
            if let reason = result.reason { entry["reason"] = .string(reason) }
            if let node = result.node { entry["node"] = .string(node) }
            if let detail = result.detail { entry["detail"] = detail }

            switch result.status {
            case .pass: passed += 1
            case .skipped: skipped += 1
            case .fail:
                failed += 1
                if captureEvidence {
                    if evidencePath == nil {
                        evidencePath = try? await capture.capture(
                            window: window, to: nil, waitForComplete: true, timeoutMs: 3000,
                            scale: nil, tileHashes: false, includeCursor: false).path
                    }
                    if let evidencePath { entry["evidence"] = .string(evidencePath) }
                }
            }
            rendered.append(.object(entry))
        }

        var out: [String: JSONValue] = [
            "window": .string(id),
            "revision": .number(Double(outcome.revision)),
            "stateHash": .string(outcome.hash),
            "assertions": .array(rendered),
            "passed": .number(Double(passed)),
            "failed": .number(Double(failed)),
            "skipped": .number(Double(skipped)),
            // ok requires that everything was actually evaluated. A skipped
            // assertion is an unanswered question, not a satisfied one.
            "ok": .bool(failed == 0 && skipped == 0)
        ]
        if skipped > 0 {
            out["note"] = .string("\(skipped) assertion(s) could not be evaluated and are reported "
                                + "skipped with a reason. They are not passes; the state they check "
                                + "is unknown.")
        }
        return .object(out)
    }

    // MARK: - One assertion

    private func evaluate(kind: String, spec: JSONValue, window: WindowHandle,
                          tree: AXNode, index: [String: AXNode]) async -> Outcome {
        let expected = spec["expected"] ?? .null
        let tolerance = spec["tolerance"]?.doubleValue

        func subject() -> AXNode? {
            if let nodeID = spec["node"]?.stringValue {
                return index[nodeID] ?? (try? ax.node(id: nodeID))
            }
            let predicate = FindPredicate(json: spec["find"])
            guard !predicate.isEmpty else { return nil }
            return (try? ax.find(window: window.id, predicate: predicate, limit: 1))?.first
        }

        func missingSubject() -> Outcome {
            Outcome(status: .fail, observed: .object(["found": .bool(false)]), expected: expected,
                    reason: "no node matched; supply `node` with an id from proctor_snapshot or "
                          + "`find` with a predicate")
        }

        // What this machine can be asked at all, before anything is measured.
        //
        // Checked here rather than inside each kind, because the question is
        // about the substrate rather than about the assertion: on a delegated
        // machine there is no accessibility tree for any of them to read, and a
        // per-kind check would be sixteen places to forget it. A kind added later
        // is refused by this shape until somebody says otherwise, which is the
        // safe direction — a refusal on a kind that would have worked is visible,
        // and a permission on one that cannot be evaluated is a pass nobody took.
        if let why = machine.tier.cannotEvaluate(kind) {
            return Outcome(status: .skipped, observed: .null,
                           expected: expected, reason: why)
        }

        switch kind {
        case "exists":
            let node = subject()
            return Outcome(status: node == nil ? .fail : .pass,
                           observed: node?.summary ?? .object(["found": .bool(false)]),
                           expected: .string("a matching node exists"),
                           node: node?.id)

        case "absent":
            let node = subject()
            return Outcome(status: node == nil ? .pass : .fail,
                           observed: node?.summary ?? .object(["found": .bool(false)]),
                           expected: .string("no matching node"),
                           node: node?.id)

        case "valueEquals", "valueContains":
            guard let node = subject() else { return missingSubject() }
            let observed = node.value
            let hit = kind == "valueEquals"
                ? JSONText.equal(observed, expected)
                : JSONText.describe(observed).contains(JSONText.describe(expected))
            return Outcome(status: hit ? .pass : .fail, observed: observed ?? .null,
                           expected: expected, node: node.id)

        case "enabled", "disabled":
            guard let node = subject() else { return missingSubject() }
            guard let enabled = node.enabled else {
                return Outcome(status: .skipped, observed: .null,
                               expected: .bool(kind == "enabled"),
                               reason: "\(node.role) does not expose AXEnabled, so its enabled state "
                                     + "cannot be read", node: node.id)
            }
            return Outcome(status: enabled == (kind == "enabled") ? .pass : .fail,
                           observed: .bool(enabled), expected: .bool(kind == "enabled"),
                           node: node.id)

        case "focused":
            guard let node = subject() else { return missingSubject() }
            guard let focused = node.focused else {
                return Outcome(status: .skipped, observed: .null, expected: .bool(true),
                               reason: "\(node.role) does not expose AXFocused, so its focus state "
                                     + "cannot be read", node: node.id)
            }
            return Outcome(status: focused ? .pass : .fail, observed: .bool(focused),
                           expected: .bool(true), node: node.id)

        case "hasLabel":
            guard let node = subject() else { return missingSubject() }
            let name = node.accessibleName
            return Outcome(status: name == nil ? .fail : .pass,
                           observed: name.map(JSONValue.string) ?? .null,
                           expected: .string("a non-empty AXDescription, AXTitle, AXHelp or AXIdentifier"),
                           node: node.id)

        case "frameEquals":
            guard let node = subject() else { return missingSubject() }
            guard let frame = node.frame else {
                return Outcome(status: .skipped, observed: .null, expected: expected,
                               reason: "\(node.role) exposes no frame", node: node.id)
            }
            guard let want = Rect.from(expected) else {
                return Outcome(status: .skipped, observed: frame.json, expected: expected,
                               reason: "expected must be [x,y,w,h] or {x,y,w,h}", node: node.id)
            }
            let epsilon = tolerance ?? 1.0
            let ok = abs(frame.x - want.x) <= epsilon && abs(frame.y - want.y) <= epsilon
                  && abs(frame.w - want.w) <= epsilon && abs(frame.h - want.h) <= epsilon
            return Outcome(status: ok ? .pass : .fail, observed: frame.json,
                           expected: want.json, node: node.id,
                           detail: .object(["tolerance": .number(epsilon)]))

        case "containedIn":
            return containment(spec: spec, subject: subject(), expected: expected,
                               tolerance: tolerance ?? 0, index: index, window: window)

        case "alignedWith":
            return alignment(spec: spec, subject: subject(), expected: expected,
                             tolerance: tolerance ?? 1.0, index: index, window: window)

        case "horizontalAlignment":
            return horizontalAlignment(spec: spec, subject: subject(), expected: expected,
                                       tolerance: tolerance ?? HorizontalPlacement.defaultTolerance,
                                       index: index, window: window)

        case "minHitSize":
            return await hitSize(subject: subject(), expected: expected, window: window)

        case "contrast":
            return await contrastCheck(subject: subject(), expected: expected, window: window)

        case "focusOrder":
            return focusOrder(tree: tree, tolerance: tolerance ?? 8.0)

        case "regionMatches":
            var outcome = await regionMatches(spec: spec, subject: subject(),
                                              tolerance: tolerance ?? 0.02, window: window)
            // The one kind a delegated machine can attempt, so it is the one that
            // needs the qualification. The comparison genuinely ran; what is
            // missing is any guarantee that the frame it ran against was
            // complete. Attached rather than folded into the verdict, because
            // downgrading a real pass to a fail would be inventing a defect, and
            // reporting it unqualified would be claiming evidence Proctor did not
            // have.
            if let caveat = machine.tier.pixelCaveat {
                outcome.reason = [outcome.reason, caveat].compactMap { $0 }.joined(separator: " ")
            }
            return outcome

        case "agree":
            return await agree(tree: tree, window: window)

        default:
            return Outcome(status: .skipped, observed: .null, expected: .null,
                           reason: "unknown assertion kind \(kind.debugDescription)")
        }
    }

    // MARK: - Geometry

    private func referenceRect(_ expected: JSONValue, index: [String: AXNode],
                               window: WindowHandle) -> (Rect?, String?) {
        if let rect = Rect.from(expected) { return (rect, nil) }
        let nodeID = expected.stringValue ?? expected["node"]?.stringValue
        guard let nodeID else { return (nil, nil) }
        let node = index[nodeID] ?? (try? ax.node(id: nodeID))
        return (node?.frame, nodeID)
    }

    private func containment(spec: JSONValue, subject: AXNode?, expected: JSONValue,
                             tolerance: Double, index: [String: AXNode],
                             window: WindowHandle) -> Outcome {
        guard let node = subject else {
            return Outcome(status: .fail, observed: .object(["found": .bool(false)]),
                           expected: expected, reason: "no node matched")
        }
        guard let frame = node.frame else {
            return Outcome(status: .skipped, observed: .null, expected: expected,
                           reason: "\(node.role) exposes no frame", node: node.id)
        }
        let (container, containerID) = referenceRect(expected, index: index, window: window)
        guard let container else {
            return Outcome(status: .skipped, observed: frame.json, expected: expected,
                           reason: "the container has no readable frame; give expected as a node id "
                                 + "or as [x,y,w,h]", node: node.id)
        }
        let ok = frame.x >= container.x - tolerance
              && frame.y >= container.y - tolerance
              && frame.maxX <= container.maxX + tolerance
              && frame.maxY <= container.maxY + tolerance
        var detail: [String: JSONValue] = ["container": container.json,
                                           "tolerance": .number(tolerance)]
        if let containerID { detail["containerNode"] = .string(containerID) }
        return Outcome(status: ok ? .pass : .fail, observed: frame.json,
                       expected: .string("contained in \(containerID ?? "the given rect")"),
                       node: node.id, detail: .object(detail))
    }

    private func alignment(spec: JSONValue, subject: AXNode?, expected: JSONValue,
                           tolerance: Double, index: [String: AXNode],
                           window: WindowHandle) -> Outcome {
        guard let node = subject else {
            return Outcome(status: .fail, observed: .object(["found": .bool(false)]),
                           expected: expected, reason: "no node matched")
        }
        guard let frame = node.frame else {
            return Outcome(status: .skipped, observed: .null, expected: expected,
                           reason: "\(node.role) exposes no frame", node: node.id)
        }
        let (other, otherID) = referenceRect(expected, index: index, window: window)
        guard let other else {
            return Outcome(status: .skipped, observed: frame.json, expected: expected,
                           reason: "the reference has no readable frame; give expected as a node id, "
                                 + "as [x,y,w,h], or as {node, edge}", node: node.id)
        }
        let deltas: [String: Double] = [
            "left": frame.x - other.x,
            "right": frame.maxX - other.maxX,
            "top": frame.y - other.y,
            "bottom": frame.maxY - other.maxY,
            "centerX": frame.centerX - other.centerX,
            "centerY": frame.centerY - other.centerY
        ]
        let wanted = expected["edge"]?.stringValue
        let ok: Bool
        if let wanted {
            guard let delta = deltas[wanted] else {
                return Outcome(status: .skipped, observed: frame.json, expected: expected,
                               reason: "unknown edge \(wanted.debugDescription); use left, right, "
                                     + "top, bottom, centerX or centerY", node: node.id)
            }
            ok = abs(delta) <= tolerance
        } else {
            ok = deltas.values.contains { abs($0) <= tolerance }
        }
        return Outcome(status: ok ? .pass : .fail,
                       observed: .object(deltas.mapValues { JSONValue.number($0) }),
                       expected: .string("aligned with \(otherID ?? "the given rect")"
                                       + (wanted.map { " on \($0)" } ?? "")
                                       + " within \(tolerance)pt"),
                       node: node.id)
    }

    private func horizontalAlignment(spec: JSONValue, subject: AXNode?, expected: JSONValue,
                                    tolerance: Double, index: [String: AXNode],
                                    window: WindowHandle) -> Outcome {
        guard let node = subject else {
            return Outcome(status: .fail, observed: .object(["found": .bool(false)]),
                           expected: expected, reason: "no node matched")
        }
        guard let frame = node.frame else {
            return Outcome(status: .skipped, observed: .null, expected: expected,
                           reason: "\(node.role) exposes no frame", node: node.id)
        }
        guard HorizontalPlacement.isMeasurable(frame) else {
            // A NaN width compares false against everything, so without this the
            // element would come back a confident `custom`; a finite origin with
            // a NaN width would come back a confident `left`.
            return Outcome(status: .skipped, observed: frame.json, expected: expected,
                           reason: "\(node.role) reports a frame that cannot be measured "
                                 + "horizontally (x \(frame.x), width \(frame.w))", node: node.id)
        }

        // A container that was asked for must resolve. `referenceRect` returns
        // nil both for "none given" and for "given but unreadable", and
        // answering the second against the window would be a confident verdict
        // about a different rectangle — with nothing in the outcome saying so.
        let containerSpec = spec["container"] ?? .null
        var containerID: String?
        var refRect: Rect
        var defaultedToWindow = false
        if containerSpec != .null {
            let (rect, id) = referenceRect(containerSpec, index: index, window: window)
            guard let rect else {
                return Outcome(status: .skipped, observed: frame.json, expected: expected,
                               reason: "the container has no readable frame; give `container` as a "
                                     + "node id or as [x,y,w,h], or omit it to use the window",
                               node: node.id)
            }
            refRect = rect
            containerID = id
        } else {
            guard let windowFrame = (try? ax.node(id: window.id))?.frame else {
                return Outcome(status: .skipped, observed: frame.json, expected: expected,
                               reason: "no `container` was given and the window exposes no frame, "
                                     + "so there is nothing to measure the element against",
                               node: node.id)
            }
            refRect = windowFrame
            defaultedToWindow = true
        }
        guard HorizontalPlacement.isMeasurable(refRect) else {
            return Outcome(status: .skipped, observed: frame.json, expected: expected,
                           reason: "the \(defaultedToWindow ? "window" : "container") reports a "
                                 + "frame that cannot be measured horizontally "
                                 + "(x \(refRect.x), width \(refRect.w))", node: node.id)
        }

        let reading = HorizontalPlacement.read(element: frame, container: refRect,
                                               tolerance: tolerance)
        let observedWord: JSONValue = {
            if reading.isCustom { return .string("custom") }
            if let single = reading.placement { return .string(single.rawValue) }
            return .array(reading.nearest.map { .string($0.rawValue) })
        }()
        var detail: [String: JSONValue] = [
            "tolerance": .number(reading.tolerance),
            "leftOffset": .number(reading.leftOffset),
            "rightOffset": .number(reading.rightOffset),
            "centreOffset": .number(reading.centreOffset),
            "container": refRect.json,
            "containerDefaultedToWindow": .bool(defaultedToWindow)
        ]
        if let containerID { detail["containerNode"] = .string(containerID) }

        // Naming the likely cause only when it is likely. It belongs to the
        // `custom` failure alone: an inset container is why nothing matched. On a
        // placement that was measured cleanly and is simply not the one asked
        // for, it would be advice about a different problem.
        let containerHint = defaultedToWindow
            ? " The container defaulted to the window frame — pass `container` with the content "
            + "view's node id if the element is aligned inside an inset area."
            : ""

        func outcome(_ status: Verdict, expected want: JSONValue, reason: String?) -> Outcome {
            Outcome(status: status, observed: observedWord, expected: want,
                    reason: reason, node: node.id, detail: .object(detail))
        }

        // An expectation is what makes this an assertion. Without one the
        // reading is still returned — it answers "what is this?" — but it is
        // not reported as verified.
        guard let word = expected.stringValue else {
            return outcome(.skipped, expected: expected,
                           reason: "horizontalAlignment needs `expected` to be one of "
                                 + "\(HorizontalPlacement.acceptedWords); the observed placement is "
                                 + "reported but nothing was asserted")
        }
        guard let wanted = HorizontalPlacement.parse(word) else {
            return outcome(.skipped, expected: expected,
                           reason: "unknown alignment \(word.debugDescription); use "
                                 + HorizontalPlacement.acceptedWords)
        }
        // The normalised word, so a spec written as `leading` reports
        // `expected: "left"` against `observed: "left"` rather than a pass that
        // reads like a mismatch.
        let want = JSONValue.string(wanted.rawValue)

        if reading.isCustom {
            return outcome(.fail, expected: want,
                           reason: "not left, center or right aligned within "
                                 + "\(reading.tolerance)pt of the container: "
                                 + reading.describeOffsets() + "." + containerHint)
        }
        if reading.isTied {
            let words = reading.nearest.map(\.rawValue).joined(separator: ", ")
            return outcome(.skipped, expected: want,
                           reason: "the container is too close in width to the element to tell "
                                 + "\(words) apart within \(reading.tolerance)pt — "
                                 + reading.describeOffsets() + ". The placement is unknown rather "
                                 + "than wrong.")
        }
        let placement = reading.placement
        let ok = placement == wanted
        return outcome(ok ? .pass : .fail, expected: want,
                       reason: ok ? nil
                                  : "aligned \(placement?.rawValue ?? "custom") in the container, "
                                  + "not \(wanted.rawValue): " + reading.describeOffsets() + ".")
    }

    /// Focus order against reading order, computed from the tree alone. AX
    /// child order is the focus order, so this needs no pixels — unlike the
    /// three checks below it.
    private func focusOrder(tree: AXNode, tolerance: Double) -> Outcome {
        let focusable = tree.inTreeOrder().filter { node in
            guard let frame = node.frame, frame.w > 0, frame.h > 0 else { return false }
            return node.focused != nil || !node.actions.isEmpty
        }
        guard focusable.count > 1 else {
            return Outcome(status: .skipped, observed: .number(Double(focusable.count)),
                           expected: .string("focus order follows visual order"),
                           reason: "fewer than two focusable nodes with a frame were found, so there "
                                 + "is no order to check")
        }
        // Rows are quantised rather than compared with a tolerance: a tolerance
        // comparison is not transitive, so it is not a valid sort ordering and
        // the result would depend on the input order.
        let visual = focusable.enumerated().sorted { a, b in
            let fa = a.element.frame!, fb = b.element.frame!
            let rowA = (fa.y / tolerance).rounded(.down), rowB = (fb.y / tolerance).rounded(.down)
            if rowA != rowB { return rowA < rowB }
            if fa.x != fb.x { return fa.x < fb.x }
            return a.offset < b.offset
        }
        for (position, entry) in visual.enumerated() where entry.offset != position {
            return Outcome(
                status: .fail,
                observed: .object([
                    "node": .string(entry.element.id),
                    "treePosition": .number(Double(entry.offset)),
                    "visualPosition": .number(Double(position)),
                    "frame": entry.element.frame?.json ?? .null
                ]),
                expected: .string("focus order follows visual order within \(tolerance)pt rows"),
                reason: "the first inversion is reported; later ones usually follow from it",
                node: entry.element.id)
        }
        return Outcome(status: .pass, observed: .number(Double(focusable.count)),
                       expected: .string("focus order follows visual order"))
    }

    // MARK: - Checks that need pixels or layer geometry

    private func hitSize(subject: AXNode?, expected: JSONValue, window: WindowHandle) async -> Outcome {
        let minimum = expected.doubleValue ?? 24.0
        guard let node = subject else {
            return Outcome(status: .fail, observed: .object(["found": .bool(false)]),
                           expected: .number(minimum), reason: "no node matched")
        }
        guard let tri else {
            return Outcome(status: .skipped, observed: node.frame?.json ?? .null,
                           expected: .number(minimum),
                           reason: "a hit-target check is about the area that can actually be hit — "
                                 + "the frame reduced by occlusion and clipping — and no tri-observer "
                                 + "is wired, so only the unreduced AX frame is available. Answering "
                                 + "from that would report a weaker check as this one.",
                           node: node.id)
        }
        do {
            let rect = try await tri.hitSize(window: window, node: node)
            let ok = rect.w >= minimum && rect.h >= minimum
            return Outcome(status: ok ? .pass : .fail, observed: rect.json,
                           expected: .number(minimum), node: node.id)
        } catch {
            return Outcome(status: .skipped, observed: node.frame?.json ?? .null,
                           expected: .number(minimum),
                           reason: "the hit area could not be measured: \(error)", node: node.id)
        }
    }

    private func contrastCheck(subject: AXNode?, expected: JSONValue,
                               window: WindowHandle) async -> Outcome {
        let threshold = expected.doubleValue ?? 4.5
        guard let node = subject else {
            return Outcome(status: .fail, observed: .object(["found": .bool(false)]),
                           expected: .number(threshold), reason: "no node matched")
        }
        guard let tri else {
            return Outcome(status: .skipped, observed: .null, expected: .number(threshold),
                           reason: "contrast is measured from pixels and no tri-observer is wired",
                           node: node.id)
        }
        do {
            let ratio = try await tri.contrast(window: window, node: node)
            return Outcome(status: ratio >= threshold ? .pass : .fail, observed: .number(ratio),
                           expected: .number(threshold), node: node.id)
        } catch {
            return Outcome(status: .skipped, observed: .null, expected: .number(threshold),
                           reason: "contrast could not be measured: \(error)", node: node.id)
        }
    }

    private func agree(tree: AXNode, window: WindowHandle) async -> Outcome {
        guard let tri else {
            return Outcome(status: .skipped, observed: .null,
                           expected: .string("no disagreement of severity defect"),
                           reason: "the tri-observer compares the AX tree, the geometry source and "
                                 + "the pixels, and none is wired here")
        }
        do {
            let findings = try await tri.agree(window: window, tree: tree)
            let defects = findings.filter { $0.severity == .defect }
            let encoded = findings.compactMap { try? JSONValue.encode($0) }
            return Outcome(status: defects.isEmpty ? .pass : .fail,
                           observed: .array(encoded),
                           expected: .string("no disagreement of severity defect"),
                           detail: .object(["defects": .number(Double(defects.count)),
                                            "findings": .number(Double(findings.count))]))
        } catch {
            return Outcome(status: .skipped, observed: .null,
                           expected: .string("no disagreement of severity defect"),
                           reason: "the tri-observer comparison failed: \(error)")
        }
    }

    private func regionMatches(spec: JSONValue, subject: AXNode?, tolerance: Double,
                               window: WindowHandle) async -> Outcome {
        guard let reference = spec["reference"]?.stringValue else {
            return Outcome(status: .skipped, observed: .null, expected: .number(tolerance),
                           reason: "regionMatches needs `reference`, a path to a reference PNG")
        }
        let frame: CaptureResult
        do {
            frame = try await capture.capture(window: window, to: nil, waitForComplete: true,
                                              timeoutMs: 3000, scale: nil, tileHashes: false,
                                              includeCursor: false)
        } catch {
            return Outcome(status: .skipped, observed: .null, expected: .number(tolerance),
                           reason: "the window could not be captured, so there is nothing to compare "
                                 + "the reference against: \(error)")
        }
        guard frame.trustworthy else {
            return Outcome(status: .skipped,
                           observed: (try? JSONValue.encode(frame)) ?? .null,
                           expected: .number(tolerance),
                           reason: "the captured frame is not trustworthy"
                                 + (frame.caveat.map { " — \($0)" } ?? "")
                                 + ", and comparing an untrustworthy frame would produce a verdict "
                                 + "about the capture rather than about the UI")
        }

        // The AX frame is in window points; the capture is in pixels.
        var region: CGRect?
        if let subject, let rect = Rect.from(spec["region"]) ?? subject.frame {
            let origin = frame.contentRect ?? Rect(x: 0, y: 0, w: 0, h: 0)
            region = CGRect(x: (rect.x - origin.x) * frame.scale,
                            y: (rect.y - origin.y) * frame.scale,
                            width: rect.w * frame.scale, height: rect.h * frame.scale)
        } else if let rect = Rect.from(spec["region"]) {
            region = CGRect(x: rect.x * frame.scale, y: rect.y * frame.scale,
                            width: rect.w * frame.scale, height: rect.h * frame.scale)
        }

        do {
            let difference = try PixelCompare.meanDifference(frame.path, reference, region: region)
            return Outcome(status: difference <= tolerance ? .pass : .fail,
                           observed: .number(difference), expected: .number(tolerance),
                           node: subject?.id,
                           detail: .object(["capture": .string(frame.path),
                                            "reference": .string(reference),
                                            "metric": .string("mean absolute channel difference, 0..1")]))
        } catch let failure as PixelCompare.Failure {
            return Outcome(status: .skipped, observed: .null, expected: .number(tolerance),
                           reason: failure.reason, node: subject?.id)
        } catch {
            return Outcome(status: .skipped, observed: .null, expected: .number(tolerance),
                           reason: "\(error)", node: subject?.id)
        }
    }
}
