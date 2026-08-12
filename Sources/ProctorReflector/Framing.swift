#if DEBUG || PROCTOR_REFLECTOR

import Foundation

// The same framing the rest of Proctor uses: 4-byte big-endian byte count then a
// JSON payload. Newline framing loses to newlines inside captured UI text, which
// is exactly what this carries. Duplicated rather than shared because this target
// is embedded in other people's applications and takes no dependencies.

enum Frame {
    static let maxBytes = 64 * 1024 * 1024

    static func encode(_ value: JSONValue) throws -> Data {
        let body = try JSONEncoder().encode(value)
        guard body.count <= maxBytes else {
            throw ReflectorError.frameTooLarge(body.count)
        }
        var out = Data(capacity: body.count + 4)
        var be = UInt32(body.count).bigEndian
        withUnsafeBytes(of: &be) { out.append(contentsOf: $0) }
        out.append(body)
        return out
    }

    /// Incremental reader: feed bytes, pull whole frames.
    final class Reader {
        private var buffer = Data()

        func feed(_ data: Data) { buffer.append(data) }

        func next() throws -> Data? {
            guard buffer.count >= 4 else { return nil }
            let length = buffer.prefix(4).withUnsafeBytes {
                UInt32(bigEndian: $0.loadUnaligned(as: UInt32.self))
            }
            guard length <= UInt32(maxBytes) else {
                throw ReflectorError.streamDesynchronised(Int(length))
            }
            guard buffer.count >= 4 + Int(length) else { return nil }
            let body = buffer.subdata(in: 4..<(4 + Int(length)))
            buffer.removeSubrange(0..<(4 + Int(length)))
            return body
        }
    }
}

enum ReflectorError: Error, CustomStringConvertible {
    case frameTooLarge(Int)
    case streamDesynchronised(Int)
    case badRequest(String)
    case unknownOperation(String)
    case notFound(String)

    var description: String {
        switch self {
        case .frameTooLarge(let n):
            return "response of \(n) bytes exceeds the \(Frame.maxBytes) byte frame limit; lower maxDepth or maxNodes"
        case .streamDesynchronised(let n):
            return "declared frame length \(n) exceeds the limit; the stream is out of sync, reconnect"
        case .badRequest(let why):
            return "malformed request: \(why)"
        case .unknownOperation(let op):
            return "unknown operation \"\(op)\"; supported: hierarchy, node, idle, revision, ping"
        case .notFound(let what):
            return what
        }
    }
}

// MARK: - JSON

/// A minimal Codable any-JSON box. Values inside a view tree are genuinely
/// heterogeneous, and this target cannot import the one in ProctorCore.
enum JSONValue: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) }
        else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "unsupported JSON") }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }

    /// Non-finite doubles are not representable in JSON, so they become null
    /// rather than failing the whole frame.
    static func num(_ d: Double) -> JSONValue { d.isFinite ? .number(d) : .null }
    static func num(_ i: Int) -> JSONValue { .number(Double(i)) }
    static func num(_ f: CGFloat) -> JSONValue { num(Double(f)) }
    static func str(_ s: String?) -> JSONValue { s.map { .string($0) } ?? .null }

    var stringValue: String? { if case .string(let s) = self { return s }; return nil }
    var intValue: Int? { if case .number(let n) = self { return Int(n) }; return nil }
    var boolValue: Bool? { if case .bool(let b) = self { return b }; return nil }
    subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }
}

extension JSONValue {
    static func rect(_ r: CGRect) -> JSONValue {
        .object(["x": num(r.origin.x), "y": num(r.origin.y),
                 "w": num(r.size.width), "h": num(r.size.height)])
    }
}

#endif
