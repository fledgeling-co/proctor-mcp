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
    private var reader: CuaLineReader?
    private var errorPipe: Pipe?
    private var identity: CuaProcessIdentity?
    /// Why this lane stopped accepting calls, once it has. A lane is never
    /// un-poisoned: see `poison(_:)`.
    private var poisonReason: String?
    /// The lane these events belong to, told to the transport by the backend that
    /// owns both. Empty until then, which only happens in a test that drives the
    /// transport directly.
    private var laneId = ""

    /// How long a single call may take before the driver is presumed gone. A
    /// step that never returns would hold the lane and the panel open forever,
    /// which is worse than a refusal.
    static let callTimeout: TimeInterval = 30

    /// One long-lived child, so what was verified at spawn is what acts for the
    /// lane's life: a process cannot change its own code after `exec`.
    let identityPinned = true
    let kind = "endpoint"

    init(path: String) {
        self.path = path
    }

    deinit {
        stop()
    }

    func adopt(laneId: String) {
        lock.lock(); defer { lock.unlock() }
        self.laneId = laneId
    }

    var processIdentity: CuaProcessIdentity? {
        lock.lock(); defer { lock.unlock() }
        return identity
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
        if let poisonReason { throw CuaEndpointTransport.refusal(poisonReason) }
        try startIfNeeded()
        guard let input, let reader, process?.isRunning == true else {
            throw poison(CuaEndpointTransport.gone(nil, lane: laneId))
        }
        do {
            try input.write(contentsOf: Data((line + "\n").utf8))
        } catch {
            throw poison(CuaEndpointTransport.gone(error, lane: laneId))
        }
        do {
            let data = try reader.readLine(within: CuaEndpointTransport.callTimeout)
            guard !data.isEmpty else { throw poison(CuaEndpointTransport.gone(nil, lane: laneId)) }
            return data
        } catch let fault as CuaLineReader.Fault {
            throw poison(fault == .timedOut
                ? CuaEndpointTransport.late(CuaEndpointTransport.callTimeout, lane: laneId)
                : CuaEndpointTransport.gone(nil, lane: laneId))
        }
    }

    /// Close the lane for good and return the failure that closed it.
    ///
    /// **Why a timeout ends the lane rather than retrying on it.** The line
    /// protocol has no request ids: replies are matched to requests by position.
    /// A reply that arrives after Proctor stopped waiting would be read as the
    /// answer to the *next* call, and every step after it would act on an answer
    /// to a question it did not ask — a silent corruption far worse than the
    /// refusal. Draining to resynchronise cannot help, because without ids there
    /// is nothing to tell the late reply from the next one.
    ///
    /// A fresh child is not started either. `CuaClients` already refuses that
    /// after a death, for the reason the direction file gives: a run that changes
    /// how it reaches the machine partway through cannot be scored. It also risks
    /// a doubled action, since an event the old child had posted can land after
    /// the new one strikes the same target.
    @discardableResult
    private func poison(_ failure: AgentError) -> AgentError {
        poisonReason = failure.message
        if let proc = process, proc.isRunning {
            proc.terminate()
            proc.waitUntilExit()
        }
        process = nil
        input = nil
        reader = nil
        errorPipe = nil
        return failure
    }

    private func startIfNeeded() throws {
        if process?.isRunning == true { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["serve", "--stdio"]
        let toDriver = Pipe(), fromDriver = Pipe(), errDriver = Pipe()
        process.standardInput = toDriver
        process.standardOutput = fromDriver
        process.standardError = errDriver
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
        // Checked against the process that is about to act, not against the file
        // it was launched from. See `CuaProcessCheck` for why that distinction is
        // the difference between an attestation and a guess.
        let checked = CuaProcessCheck.verify(pid: process.processIdentifier,
                                             requirement: CuaPreflight.requirementText)
        self.process = process
        self.input = toDriver.fileHandleForWriting
        self.reader = CuaLineReader(fd: fromDriver.fileHandleForReading.fileDescriptor)
        self.errorPipe = errDriver
        self.identity = checked
    }

    static func refusal(_ reason: String) -> AgentError {
        AgentError(
            code: .backendUnavailable,
            message: "the cua-driver lane was closed and is not accepting calls: \(reason)",
            remedy: "Nothing was retried on another actuation path, and no replacement driver "
                  + "was started. Re-run the batch once the driver is healthy.",
            // This call never reached the driver, so nothing can have happened.
            indeterminate: false)
    }

    static func gone(_ error: Error?, lane: String = "") -> AgentError {
        AgentError(
            code: .actionIndeterminate,
            message: "cua-driver stopped answering mid-step, so whether this action reached "
                   + "the machine could not be established"
                   + (error.map { ": \($0.localizedDescription)" } ?? ""),
            remedy: "The request may have been delivered and performed before the driver went. "
                  + "Proctor's own reading of the window before and after is on the record and "
                  + "is the only evidence available. Nothing was retried on another actuation "
                  + "path: a run that silently changes plane partway through makes its own "
                  + "determinism score meaningless.",
            indeterminate: true,
            lane: LaneEvent(kind: .died, backend: .cua, laneId: lane,
                            reason: "cua-driver stopped answering and the lane was closed. "
                                  + "Whether the step in flight reached the machine is not "
                                  + "established."))
    }

    static func late(_ seconds: TimeInterval, lane: String = "") -> AgentError {
        AgentError(
            code: .actionIndeterminate,
            message: "cua-driver did not answer within \(Int(seconds))s, so whether this "
                   + "action reached the machine could not be established",
            remedy: "The lane was closed rather than reused, because a reply arriving after "
                  + "Proctor stopped waiting would be read as the answer to the next call. "
                  + "The driver may also still act on this request after the step ended.",
            indeterminate: true,
            lane: LaneEvent(kind: .timedOut, backend: .cua, laneId: lane,
                            reason: "cua-driver did not answer within \(Int(seconds))s and the "
                                  + "lane was closed. A late reply cannot be matched to a "
                                  + "request, and the driver may still act on it."))
    }

    func stop() {
        lock.lock()
        defer { lock.unlock() }
        if let proc = process, proc.isRunning {
            proc.terminate()
            proc.waitUntilExit()
        }
        process = nil
        input = nil
        reader = nil
        errorPipe = nil
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

    /// Every call re-execs whatever answers to the path at that moment, so no
    /// lane-wide identity claim is true and the lane record makes none. The
    /// per-batch re-check this enables is **detection, not prevention**: it
    /// notices a build that moved between batches and refuses, and it cannot stop
    /// one that moves between the check and the next `exec`.
    let identityPinned = false
    let kind = "oneshot"

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
                let err = Pipe()
                process.standardOutput = out
                process.standardError = err
                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: AgentError(
                        code: .backendUnavailable,
                        message: "cua-driver could not be run: \(error.localizedDescription)"))
                    return
                }
                let data = out.fileHandleForReading.readDataToEndOfFile()
                let errData = err.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                guard process.terminationStatus == 0 else {
                    let errStr = String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                    let detail = errStr.isEmpty ? "" : ": \(errStr)"
                    continuation.resume(throwing: AgentError(
                        code: .backendUnavailable,
                        message: "cua-driver exited \(process.terminationStatus)\(detail)"))
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
