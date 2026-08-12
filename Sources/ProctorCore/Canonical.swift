import Foundation
import CryptoKit

// Canonical hashing. Two states are the same state when their hashes match,
// so everything volatile has to be masked out first or every run diverges at
// step one and the determinism instrument reports noise as a defect.

public enum Canonical {

    /// Fields whose values change between identical runs and carry no meaning
    /// for whether the UI is in the same state.
    public static let volatileValuePatterns: [String] = [
        #"\d{1,2}:\d{2}(:\d{2})?\s*([AaPp][Mm])?"#,          // clock times
        #"\d{4}-\d{2}-\d{2}"#,                                 // ISO dates
        #"\b\d+\s*(ms|milliseconds|seconds|secs|minutes|mins|hours)\b"#,
        #"\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b"#,
        #"0x[0-9a-fA-F]{6,}"#,                                 // pointer-ish
    ]

    /// Geometry is rounded before hashing. Sub-pixel drift between runs is not
    /// a state change, and treating it as one makes every animated view unstable.
    public static let defaultGeometryQuantum: Double = 1.0

    public struct Options: Sendable {
        public var maskVolatileText: Bool
        public var includeFrames: Bool
        public var includeValues: Bool
        public var includeFocus: Bool
        public var geometryQuantum: Double
        public var extraMasks: [String]
        public init(maskVolatileText: Bool = true, includeFrames: Bool = true,
                    includeValues: Bool = true, includeFocus: Bool = true,
                    geometryQuantum: Double = Canonical.defaultGeometryQuantum,
                    extraMasks: [String] = []) {
            self.maskVolatileText = maskVolatileText
            self.includeFrames = includeFrames
            self.includeValues = includeValues
            self.includeFocus = includeFocus
            self.geometryQuantum = geometryQuantum
            self.extraMasks = extraMasks
        }
        public static let `default` = Options()
    }

    public static func hash(_ node: AXNode, options: Options = .default) -> String {
        var out = ""
        write(node, into: &out, options: options)
        return sha256(out)
    }

    public static func hash(_ string: String) -> String { sha256(string) }

    public static func sha256(_ s: String) -> String {
        let digest = SHA256.hash(data: Data(s.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// A stable textual serialisation. Sorted, quantised, masked. This string
    /// is also what a divergence report diffs, so it stays human-readable.
    public static func canonicalString(_ node: AXNode, options: Options = .default) -> String {
        var out = ""
        write(node, into: &out, options: options)
        return out
    }

    private static func write(_ node: AXNode, into out: inout String,
                              options: Options, depth: Int = 0) {
        out += String(repeating: " ", count: min(depth, 40))
        out += node.role
        if let sub = node.subrole { out += "/" + sub }
        if let id = node.identifier, !id.isEmpty { out += " #" + id }
        if let t = node.title, !t.isEmpty { out += " t=" + mask(t, options) }
        if let l = node.label, !l.isEmpty { out += " l=" + mask(l, options) }
        if options.includeValues, let v = node.value {
            out += " v=" + mask(describe(v), options)
        }
        if options.includeFrames, let f = node.frame {
            let q = options.geometryQuantum
            out += String(format: " @%.0f,%.0f,%.0f,%.0f",
                          quantise(f.x, q), quantise(f.y, q), quantise(f.w, q), quantise(f.h, q))
        }
        if let e = node.enabled, !e { out += " disabled" }
        if options.includeFocus, node.focused == true { out += " focused" }
        if node.selected == true { out += " selected" }
        if !node.actions.isEmpty { out += " a=" + node.actions.sorted().joined(separator: ",") }
        out += "\n"

        // Children in tree order. AX order is meaningful — it is the focus order —
        // so it is preserved rather than sorted.
        for child in node.children ?? [] {
            write(child, into: &out, options: options, depth: depth + 1)
        }
    }

    private static func quantise(_ v: Double, _ q: Double) -> Double {
        q > 0 ? (v / q).rounded() * q : v
    }

    private static func describe(_ v: JSONValue) -> String {
        switch v {
        case .null: return "null"
        case .bool(let b): return b ? "true" : "false"
        case .number(let n):
            return n == n.rounded() ? String(Int(n)) : String(format: "%.3f", n)
        case .string(let s): return s
        case .array(let a): return "[" + a.map(describe).joined(separator: ",") + "]"
        case .object(let o):
            return "{" + o.keys.sorted().map { "\($0):\(describe(o[$0]!))" }.joined(separator: ",") + "}"
        }
    }

    private static func mask(_ s: String, _ options: Options) -> String {
        guard options.maskVolatileText else { return s }
        var out = s
        for pattern in volatileValuePatterns + options.extraMasks {
            guard let re = try? NSRegularExpression(pattern: pattern) else { continue }
            out = re.stringByReplacingMatches(
                in: out, range: NSRange(out.startIndex..., in: out), withTemplate: "⟨v⟩")
        }
        return out
    }

    // MARK: Instability

    /// How many distinct states a step produced across runs, scaled 0..1.
    /// One distinct hash over N runs is 0; N distinct hashes over N runs is 1.
    public static func instability(hashes: [String]) -> Double {
        guard hashes.count > 1 else { return 0 }
        let distinct = Set(hashes).count
        return Double(distinct - 1) / Double(hashes.count - 1)
    }

    /// The first step index where runs disagreed, or nil when every step agreed.
    public static func firstDivergence(perRun: [[String]]) -> Int? {
        guard let steps = perRun.first?.count, perRun.count > 1 else { return nil }
        for i in 0..<steps {
            let column = perRun.compactMap { $0.count > i ? $0[i] : nil }
            if Set(column).count > 1 { return i }
        }
        // A run that ended early is itself a divergence.
        let lengths = Set(perRun.map(\.count))
        return lengths.count > 1 ? (perRun.map(\.count).min() ?? 0) : nil
    }
}
