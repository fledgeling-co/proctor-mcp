import Foundation
import ProctorCore

// PRO-0044, slice 4. The two clients, and the process supervision one of them
// needs.
//
// Both speak the same JSON line protocol; they differ only in whether the process
// they speak to outlives the step. That is the whole of the transport question as
// this repo can answer it today, and the answer is unverified — see the note at
// the top of `CuaTransport.swift`, and the first-contact checklist in the plan.

/// A long-lived `cua-driver` child, spoken to over its stdio.
///
/// One process per agent, started on the first delegated step rather than at
/// launch: an agent whose operator never selects this lane should never spawn
/// anything. It is not restarted automatically after a death mid-step, because a
/// silent restart mid-run would hide exactly the event a run record should carry.
final class CuaEndpointTransport: CuaTransport, @unchecked Sendable {

    private let path: String
    private let lock = NSLock()
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?

    /// How long a single call may take before the driver is presumed gone. A
    /// step that never returns would hold the lane and the panel open forever,
    /// which is worse than a refusal.
    static let callTimeout: TimeInterval = 30

    init(path: String) {
        self.path = path
    }

    func send(_ request: CuaRequest) async throws -> CuaResponse {
        let line = try CuaWire.encode(request)
        let reply = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                do {
                    continuation.resume(returning: try exchange(line))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
        return try CuaWire.decode(reply)
    }

    private func exchange(_ line: String) throws -> Data {
        lock.lock()
        defer { lock.unlock() }
        try startIfNeeded()
        guard let input, let output, process?.isRunning == true else {
            throw CuaEndpointTransport.gone(nil)
        }
        do {
            try input.write(contentsOf: Data((line + "\n").utf8))
        } catch {
            throw CuaEndpointTransport.gone(error)
        }
        // One line per reply. A driver that closes its output has exited, which
        // is a refusal rather than something to retry on another plane.
        guard let data = try? readLine(from: output), !data.isEmpty else {
            throw CuaEndpointTransport.gone(nil)
        }
        return data
    }

    private func startIfNeeded() throws {
        if process?.isRunning == true { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["serve", "--stdio"]
        let toDriver = Pipe(), fromDriver = Pipe()
        process.standardInput = toDriver
        process.standardOutput = fromDriver
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw AgentError(
                code: .backendUnavailable,
                message: "cua-driver could not be started: \(error.localizedDescription)",
                remedy: "Check the driver's own doctor. Proctor will not fall back to its own "
                      + "actuation planes on its own, because a run that changes how it reaches "
                      + "the machine partway through cannot be scored.")
        }
        self.process = process
        self.input = toDriver.fileHandleForWriting
        self.output = fromDriver.fileHandleForReading
    }

    private func readLine(from handle: FileHandle) throws -> Data {
        var buffer = Data()
        while let chunk = try handle.read(upToCount: 1), !chunk.isEmpty {
            if chunk.first == UInt8(ascii: "\n") { break }
            buffer.append(chunk)
        }
        return buffer
    }

    static func gone(_ error: Error?) -> AgentError {
        AgentError(
            code: .backendUnavailable,
            message: "cua-driver stopped answering mid-step"
                   + (error.map { ": \($0.localizedDescription)" } ?? ""),
            remedy: "Nothing was retried on another actuation path: a run that silently changes "
                  + "plane partway through makes its own determinism score meaningless. Re-run "
                  + "the batch once the driver is healthy.")
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        process?.terminate()
        process = nil
    }
}

/// A fresh `cua-driver` invocation per call.
///
/// Kept so the default above is falsifiable rather than merely argued: every step
/// records its own round trip, so a sweep on a machine that has the binary
/// produces the comparison directly. Selected explicitly and never reached by
/// falling back.
final class CuaOneShotTransport: CuaTransport, @unchecked Sendable {

    private let path: String

    init(path: String) {
        self.path = path
    }

    func send(_ request: CuaRequest) async throws -> CuaResponse {
        let line = try CuaWire.encode(request)
        let reply: Data = try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = ["call", "--json", line]
                let out = Pipe()
                process.standardOutput = out
                process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: AgentError(
                        code: .backendUnavailable,
                        message: "cua-driver could not be run: \(error.localizedDescription)"))
                    return
                }
                let data = out.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else {
                    continuation.resume(throwing: AgentError(
                        code: .backendUnavailable,
                        message: "cua-driver exited \(process.terminationStatus)"))
                    return
                }
                continuation.resume(returning: data)
            }
        }
        return try CuaWire.decode(reply)
    }
}

/// The line protocol, in one place so both clients cannot drift apart.
enum CuaWire {

    static func encode(_ request: CuaRequest) throws -> String {
        var body: [String: JSONValue] = ["verb": .string(request.verb.rawValue)]
        if let window = request.windowID { body["windowId"] = .number(Double(window)) }
        if let pid = request.pid { body["pid"] = .number(Double(pid)) }
        if let action = request.action { body["action"] = .string(action) }
        if !request.arguments.isEmpty { body["arguments"] = .object(request.arguments) }
        if let token = request.elementToken { body["elementToken"] = .string(token) }
        // Always sent when there is one: an unrecognised delivery mode is
        // reported to fall back to background silently, so leaving it out would
        // let a version mismatch decide whether a machine gets taken.
        if let mode = request.deliveryMode { body["deliveryMode"] = .string(mode) }
        let data = try JSONEncoder().encode(JSONValue.object(body))
        return String(decoding: data, as: UTF8.self)
    }

    static func decode(_ data: Data) throws -> CuaResponse {
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: data),
              let object = value.objectValue else {
            throw AgentError(code: .backendUnavailable,
                             message: "cua-driver returned something this build could not read",
                             remedy: "Check the driver's version against the supported range "
                                   + CuaVersion.supportedRangeDescription + ".")
        }
        var reply = CuaResponse()
        reply.ok = object["ok"]?.boolValue ?? true
        reply.errorCode = object["error"]?.stringValue
        reply.message = object["message"]?.stringValue
        reply.path = object["path"]?.stringValue
        reply.effect = object["effect"]?.stringValue
        reply.truncated = object["truncated"]?.boolValue ?? false
        reply.offSpace = object["offSpace"]?.boolValue ?? false
        reply.version = object["version"]?.stringValue
        reply.vocabulary = object["paths"]?.arrayValue?.compactMap(\.stringValue)
        reply.elements = object["elements"]?.arrayValue?.enumerated().compactMap { index, raw in
            guard let element = raw.objectValue else { return nil }
            return ElementCandidate(
                index: element["index"]?.doubleValue.map(Int.init) ?? index,
                role: element["role"]?.stringValue ?? "",
                label: element["label"]?.stringValue,
                frame: frame(from: element["frame"]),
                parentIndex: element["parentIndex"]?.doubleValue.map(Int.init),
                depth: element["depth"]?.doubleValue.map(Int.init) ?? 0)
        }
        return reply
    }

    private static func frame(from value: JSONValue?) -> Rect? {
        guard let object = value?.objectValue,
              let x = object["x"]?.doubleValue, let y = object["y"]?.doubleValue,
              let w = object["w"]?.doubleValue ?? object["width"]?.doubleValue,
              let h = object["h"]?.doubleValue ?? object["height"]?.doubleValue
        else { return nil }
        return Rect(x: x, y: y, w: w, h: h)
    }
}
