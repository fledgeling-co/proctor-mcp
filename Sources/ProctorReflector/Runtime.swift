#if DEBUG || PROCTOR_REFLECTOR

import AppKit
import Foundation

/// Process-wide reflector state. Reachable from any thread, so everything it
/// owns is behind a lock; anything that touches AppKit hops to the main thread.
final class Runtime: @unchecked Sendable {
    static let shared = Runtime()

    private let lock = NSLock()
    private var server: SocketServer?
    private var activities: [UInt64: String] = [:]
    private var nextSerial: UInt64 = 1
    private var revisionCounter = 0

    private init() {}

    // MARK: - Lifecycle

    var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return server != nil
    }

    func start(socketPath: String) {
        lock.lock()
        guard server == nil else { lock.unlock(); return }
        let server = SocketServer(path: socketPath) { [weak self] request in
            self?.handle(request) ?? .object(["ok": .bool(false), "error": .string("reflector gone")])
        }
        self.server = server
        lock.unlock()

        onMain { MainState.shared.startObserving() }
        server.start()
    }

    func stop() {
        lock.lock()
        let server = self.server
        self.server = nil
        lock.unlock()

        server?.stop()
        onMain { MainState.shared.stopObserving() }
    }

    // MARK: - Activity

    func beginActivity(_ name: String) -> ActivityToken {
        lock.lock(); defer { lock.unlock() }
        let serial = nextSerial
        nextSerial += 1
        activities[serial] = name
        return ActivityToken(name: name, serial: serial)
    }

    func endActivity(_ token: ActivityToken) {
        lock.lock(); defer { lock.unlock() }
        activities.removeValue(forKey: token.serial)
    }

    var activityCount: Int {
        lock.lock(); defer { lock.unlock() }
        return activities.count
    }

    var activityNames: [String] {
        lock.lock(); defer { lock.unlock() }
        return activities.sorted { $0.key < $1.key }.map(\.value)
    }

    func isIdle() -> Bool {
        onMain { MainState.shared.idleNow() }
    }

    // MARK: - Revision

    var revision: Int {
        lock.lock(); defer { lock.unlock() }
        return revisionCounter
    }

    func incrementRevision() {
        lock.lock(); defer { lock.unlock() }
        revisionCounter += 1
    }

    // MARK: - Dispatch

    /// Runs on the socket's queue. Every AppKit read inside happens on the main
    /// thread; the socket queue blocks here, the main thread never blocks on it.
    private func handle(_ request: JSONValue) -> JSONValue {
        let id = request["id"]?.stringValue ?? ""
        do {
            guard let op = request["op"]?.stringValue else {
                throw ReflectorError.badRequest("missing \"op\"")
            }
            let params = request["params"] ?? .object([:])
            let result = try perform(op: op, params: params)
            return .object(["id": .string(id), "ok": .bool(true),
                            "result": result, "error": .null])
        } catch let error as ReflectorError {
            return .object(["id": .string(id), "ok": .bool(false),
                            "result": .null, "error": .string(error.description)])
        } catch {
            return .object(["id": .string(id), "ok": .bool(false),
                            "result": .null, "error": .string("\(error)")])
        }
    }

    private func perform(op: String, params: JSONValue) throws -> JSONValue {
        switch op {
        case "ping":
            return .object([
                "pid": JSONValue.num(Int(ProcessInfo.processInfo.processIdentifier)),
                "protocolVersion": JSONValue.num(ProctorReflector.protocolVersion),
                "processName": .string(ProcessInfo.processInfo.processName),
                "bundleIdentifier": JSONValue.str(Bundle.main.bundleIdentifier),
                "revision": JSONValue.num(revision)
            ])

        case "revision":
            return .object(["revision": JSONValue.num(revision)])

        case "idle":
            return try onMainThrowing { MainState.shared.idleReport() }

        case "hierarchy":
            let options = decode(options: params)
            let window = params["window"]?.intValue
            return try onMainThrowing { try Walker.hierarchy(windowNumber: window, options: options) }

        case "node":
            guard let nodeID = params["id"]?.stringValue ?? params["node"]?.stringValue else {
                throw ReflectorError.badRequest("\"node\" needs an \"id\" parameter")
            }
            let options = decode(options: params)
            return try onMainThrowing { try Walker.node(id: nodeID, options: options) }

        default:
            throw ReflectorError.unknownOperation(op)
        }
    }

    private func decode(options params: JSONValue) -> Walker.Options {
        var options = Walker.Options()
        if let depth = params["maxDepth"]?.intValue { options.maxDepth = max(0, depth) }
        if let nodes = params["maxNodes"]?.intValue { options.maxNodes = max(1, nodes) }
        if let constraints = params["includeConstraints"]?.boolValue { options.constraints = constraints }
        if let presentation = params["presentation"]?.boolValue { options.presentation = presentation }
        return options
    }
}

// MARK: - Main-thread hop

func onMain<T: Sendable>(_ body: @MainActor () -> T) -> T {
    if Thread.isMainThread {
        return MainActor.assumeIsolated { body() }
    }
    return DispatchQueue.main.sync { MainActor.assumeIsolated { body() } }
}

func onMainThrowing<T: Sendable>(_ body: @MainActor () throws -> T) throws -> T {
    if Thread.isMainThread {
        return try MainActor.assumeIsolated { try body() }
    }
    return try DispatchQueue.main.sync { try MainActor.assumeIsolated { try body() } }
}

#endif
