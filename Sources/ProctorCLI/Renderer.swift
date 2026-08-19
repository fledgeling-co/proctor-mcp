import Foundation
import ProctorCore

// The human rendering. `--json` is the contract a script reads; this is for a
// person at a terminal, and it never invents a field the reply did not carry.
enum Renderer {

    static func human(_ reply: JSONValue, verb: CLISurface.Verb) -> String {
        var lines: [String] = []

        // A step batch: one line per step, naming the plane and the route,
        // because a step that went through the accessibility plane and one that
        // went through the shared event stream prove different things.
        if let steps = reply["steps"]?.arrayValue, !steps.isEmpty {
            for (i, step) in steps.enumerated() {
                let ok = step["ok"]?.boolValue ?? false
                let plane = step["plane"]?.stringValue ?? "?"
                let route = step["route"]?.stringValue ?? "?"
                let ms = step["ms"]?.intValue.map { "\($0)ms" } ?? ""
                lines.append(" \(ok ? "✓" : "✗") \(i + 1)  \(plane)/\(route)  \(ms)")
            }
        }

        if let lanes = reply["lanes"]?.arrayValue, !lanes.isEmpty {
            for lane in lanes {
                let name = lane["lane"]?.stringValue ?? "?"
                let state = lane["state"]?.stringValue ?? "?"
                lines.append("  \(state.padding(toLength: 12, withPad: " ", startingAt: 0)) \(name)")
            }
        }

        if let ready = reply["ready"]?.boolValue {
            lines.append("ready: \(ready)")
        }
        if let settle = reply["settle"]?["reason"]?.stringValue {
            lines.append("settled: \(settle)")
        }

        if lines.isEmpty {
            // Nothing this renderer knows how to shape. Say so rather than
            // printing nothing, and point at the contract that always works.
            lines.append("\(verb.name): ok — use --json for the full reply")
        }
        return lines.joined(separator: "\n")
    }
}
