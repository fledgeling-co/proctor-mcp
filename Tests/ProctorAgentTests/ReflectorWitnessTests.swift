import Testing
import Foundation
import Darwin
import AppKit
import ProctorReflector

// PRO-0083, W9. REQ-023: `ProctorReflector` inspection reads resolved layout
// constraints, colours and CALayer models over its own socket.
//
// **A second socket, and that is why it is its own case.** Five of this item's
// other witnesses stand on the agent's `AF_UNIX` listener in `Server.swift`.
// This one stands on `ProctorReflector/SocketServer.swift` — a different
// `Darwin.bind`/`listen`/`accept`, in a different target, embedded in other
// people's applications and taking no dependency on the agent. Folding it into
// the agent-socket cases would let one listener's silence hide behind the
// other's noise.
//
// **What is asked, and what answers.** `ProctorReflector.start(socketPath:)` is
// the one-line adoption API an app calls from `applicationDidFinishLaunching`.
// It binds, listens, `chmod 0600`s and serves. This test connects with a raw
// `Darwin.socket`/`connect` client of its own, frames the request by hand and
// decodes the reply with `JSONSerialization` — no framing, no decoder and no
// client belonging to the target under test participates in the reading.
//
// **The resolved half, which is what REQ-023 actually claims.** The window is
// built with Auto Layout and no explicit child frame, so the label's width and
// height are AppKit's own measurement of the string and its origin is the
// constraint solver's. Its colour is `labelColor` resolved against the window's
// effective appearance, which nothing here sets. Its layer is CoreAnimation's.
// No literal in this file names any of those values; what is checked is the
// RELATION the solver produced over a height nothing here wrote, and the shape
// of values only AppKit could have computed.
//
// **The ceiling, recorded rather than implied.** Server and client are the same
// process. What is witnessed is a real `AF_UNIX` round trip through the kernel
// and a real AppKit walk, not a cross-process one. The agent ships
// `NullReflectorBridge`, so there is no in-repo production client to drive this
// from a second process, and writing one would be building the subject rather
// than witnessing it.
//
// Serialized because `Runtime.shared` is process-wide and the walk reaches
// `NSApplication.shared.windows`.
@Suite("External effect witnesses: the Reflector's own socket", .serialized)
struct ReflectorWitnessTests {

    // MARK: - Apparatus: a raw client that shares nothing with the server

    /// One request, one connection, one reply — deliberately, so the count is an
    /// accept count. `SocketServer.serve` reads many frames from one descriptor,
    /// so a per-request count over one connection would report three where the
    /// accept loop took one.
    enum RawClient {

        enum Failure: Error, CustomStringConvertible {
            case connect(Int32)
            case write
            case shortRead(Int)
            case decode

            var description: String {
                switch self {
                case .connect(let code): return "connect failed with errno \(code)"
                case .write: return "the write did not complete"
                case .shortRead(let n): return "the stream ended after \(n) bytes"
                case .decode: return "the reply was not a JSON object"
                }
            }
        }

        /// Returns the reply's RAW BYTES. Decoding happens on the test's side of
        /// the thread boundary, both because `Any` is not `Sendable` and because
        /// bytes off a socket are the honest recorder: what crosses is what the
        /// server wrote, not a structure this file chose.
        static func ask(_ request: [String: Any], at path: String) throws -> Data {
            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else { throw Failure.connect(errno) }
            defer { close(fd) }

            var address = sockaddr_un()
            address.sun_family = sa_family_t(AF_UNIX)
            let bytes = Array(path.utf8)
            precondition(bytes.count < MemoryLayout.size(ofValue: address.sun_path))
            withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
            let size = socklen_t(MemoryLayout<sockaddr_un>.size)
            let joined = withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(fd, $0, size)
                }
            }
            guard joined == 0 else { throw Failure.connect(errno) }

            // 4-byte big-endian length then the JSON body, written by hand.
            let body = try JSONSerialization.data(withJSONObject: request)
            var frame = Data()
            var length = UInt32(body.count).bigEndian
            withUnsafeBytes(of: &length) { frame.append(contentsOf: $0) }
            frame.append(body)
            let outgoing = [UInt8](frame)
            guard Darwin.write(fd, outgoing, outgoing.count) == outgoing.count else {
                throw Failure.write
            }

            let header = try readExactly(fd, 4)
            let replyLength = Int(header.withUnsafeBytes {
                UInt32(bigEndian: $0.loadUnaligned(as: UInt32.self))
            })
            return try readExactly(fd, replyLength)
        }

        /// Decoded with `JSONSerialization` — Foundation's parser, not the
        /// target's `JSONValue` decoder.
        static func decode(_ payload: Data) throws -> [String: Any] {
            guard let object = try JSONSerialization.jsonObject(with: payload) as? [String: Any]
            else { throw Failure.decode }
            return object
        }

        private static func readExactly(_ fd: Int32, _ count: Int) throws -> Data {
            var out = Data()
            var buffer = [UInt8](repeating: 0, count: max(count, 1))
            while out.count < count {
                let n = Darwin.read(fd, &buffer, count - out.count)
                if n > 0 { out.append(contentsOf: buffer[0..<n]) } else { break }
            }
            guard out.count == count else { throw Failure.shortRead(out.count) }
            return out
        }
    }

    /// Socket I/O off the cooperative pool, so the main thread stays free.
    ///
    /// The reflector's handler hops to the main thread for every AppKit read
    /// (`onMainThrowing` → `DispatchQueue.main.sync`). A client that blocked the
    /// main thread waiting for that reply would deadlock against it, and a client
    /// on a cooperative thread would spend a pool worker on a blocking read. So
    /// the client half runs on a `Thread` this function owns — the same shape
    /// PRO-0077's trail witness used, for a related reason.
    static func onOwnThread<T: Sendable>(
        _ body: @escaping @Sendable () throws -> T
    ) async throws -> T {
        let box = ResultBox<T>()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let worker = Thread {
                do { box.set(.success(try body())) } catch { box.set(.failure(error)) }
                continuation.resume()
            }
            worker.name = "pro83.reflector-client"
            worker.stackSize = 1024 * 1024
            worker.start()
        }
        switch box.value {
        case .success(let value): return value
        case .failure(let error): throw error
        case nil: throw RawClient.Failure.shortRead(0)
        }
    }

    final class ResultBox<V>: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: Result<V, Error>?
        func set(_ value: Result<V, Error>) { lock.withLock { stored = value } }
        var value: Result<V, Error>? { lock.withLock { stored } }
    }

    // MARK: - Apparatus: a window whose geometry nothing here writes

    static let contentWidth: CGFloat = 480
    static let contentHeight: CGFloat = 320
    static let leadingInset: CGFloat = 24
    static let topInset: CGFloat = 32

    /// Holds the witness window so the test body never carries an `NSWindow`
    /// across a concurrency boundary. Only the window number crosses, and that is
    /// an `Int`.
    @MainActor
    final class WindowHolder {
        static let shared = WindowHolder()
        var window: NSWindow?

        /// A real `NSWindow` with a real backing view tree, laid out by the
        /// constraint solver. The label carries no frame of its own: its width
        /// and height are AppKit's measurement of the string in the system font,
        /// and its origin is what the solver put it at.
        func build(labelled text: String) -> Int {
            _ = NSApplication.shared
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: contentWidth, height: contentHeight),
                styleMask: [.titled], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.title = "PRO-0083 reflector witness"

            let content = NSView(frame: NSRect(x: 0, y: 0,
                                               width: contentWidth, height: contentHeight))
            content.wantsLayer = true
            window.contentView = content

            let label = NSTextField(labelWithString: text)
            label.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(label)
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: content.leadingAnchor,
                                               constant: leadingInset),
                label.topAnchor.constraint(equalTo: content.topAnchor, constant: topInset)
            ])
            content.layoutSubtreeIfNeeded()

            self.window = window
            return window.windowNumber
        }

        func tearDown() {
            window?.close()
            window = nil
        }
    }

    /// Every node the walk resolved, flattened out of the decoded reply — so the
    /// count is what came back over the socket rather than what the walker says
    /// it did.
    static func flatten(_ node: Any?) -> [[String: Any]] {
        guard let node = node as? [String: Any], node["id"] is String else { return [] }
        var out = [node]
        for child in (node["children"] as? [Any]) ?? [] {
            out.append(contentsOf: flatten(child))
        }
        return out
    }

    static func rect(_ value: Any?) -> (x: Double, y: Double, w: Double, h: Double)? {
        guard let value = value as? [String: Any],
              let x = value["x"] as? Double, let y = value["y"] as? Double,
              let w = value["w"] as? Double, let h = value["h"] as? Double
        else { return nil }
        return (x, y, w, h)
    }

    // MARK: - W9 · REQ-023 · ipc · the Reflector's own socket

    @Test("REQ-023 effect witness: the Reflector's own socket answers real connections with values AppKit resolved, and a stopped one answers none")
    func reflectorSocketAnswersWithResolvedValues() async throws {
        let directory = "/tmp/pro83r-\(UUID().uuidString.prefix(8).lowercased())"
        try FileManager.default.createDirectory(atPath: directory,
                                                withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let path = "\(directory)/reflector-witness.sock"
        let label = "resolved-\(UUID().uuidString.prefix(6))"

        let windowNumber = await MainActor.run { WindowHolder.shared.build(labelled: label) }
        #expect(windowNumber != 0, "the window server gave the witness window no number")

        // --- The witness -----------------------------------------------------
        await MainActor.run { ProctorReflector.start(socketPath: path) }
        #expect(FileManager.default.fileExists(atPath: path),
                "start() left no socket at \(path)")

        // The listener's own file mode, read off the inode rather than taken from
        // the code that set it.
        let mode = (try FileManager.default.attributesOfItem(atPath: path)[.posixPermissions]
                        as? NSNumber)?.intValue ?? -1
        #expect(mode == 0o600,
                "the socket is mode \(String(mode, radix: 8)), not 0600")

        let mine = Int(ProcessInfo.processInfo.processIdentifier)
        let raw = try await Self.onOwnThread {
            [
                "ping": try RawClient.ask(["id": "w9-ping", "op": "ping"], at: path),
                "revision": try RawClient.ask(["id": "w9-revision", "op": "revision"], at: path),
                "hierarchy": try RawClient.ask(
                    ["id": "w9-hierarchy", "op": "hierarchy",
                     "params": ["window": windowNumber, "includeConstraints": true,
                                "presentation": true, "maxDepth": 12]],
                    at: path)
            ]
        }
        let replies = try raw.mapValues { try RawClient.decode($0) }

        // COUNT ONE: connections the reflector answered. One request per
        // connection, so a reply is an accept.
        let answered = replies.values.filter { ($0["ok"] as? Bool) == true }.count
        let errors = replies.compactMapValues { $0["error"] as? String }
        #expect(answered == 3,
                "\(answered) of 3 connections were answered · errors \(errors)")

        // The pid in the ping is read by the server out of its own process; the
        // request never carried it.
        let ping = try #require(replies["ping"]?["result"] as? [String: Any])
        #expect(ping["pid"] as? Int == mine,
                "ping named pid \(String(describing: ping["pid"])), not \(mine)")
        #expect(ping["protocolVersion"] as? Int == ProctorReflector.protocolVersion)

        let hierarchy = try #require(replies["hierarchy"]?["result"] as? [String: Any],
                                     "hierarchy answered \(String(describing: errors["hierarchy"]))")
        let windows = try #require(hierarchy["windows"] as? [[String: Any]])
        let subject = try #require(
            windows.first { $0["windowNumber"] as? Int == windowNumber },
            "the walk returned \(windows.count) windows, none numbered \(windowNumber)")
        #expect((subject["backingScaleFactor"] as? Double ?? 0) >= 1)
        #expect(!((subject["effectiveAppearance"] as? String) ?? "").isEmpty,
                "the window reported no effective appearance, so nothing was resolved")

        // COUNT TWO: nodes the walk resolved, counted off the decoded reply.
        let nodes = Self.flatten(subject["root"])
        let classes = nodes.compactMap { $0["class"] as? String }
        #expect(nodes.count >= 2,
                "the walk resolved \(nodes.count) nodes over a content view and a label · \(classes)")

        let labelNode = try #require(
            nodes.first { ((($0["text"] as? [String: Any])?["string"]) as? String) == label },
            "no node carried the label's string · classes \(classes)")

        // THE RESOLVED GEOMETRY. Width and height are AppKit's measurement of the
        // string; the origin is the solver's. What is checked is the relation the
        // solver produced over a height nothing in this file wrote.
        let frame = try #require(Self.rect(labelNode["frame"]),
                                 "the label node carried no frame")
        #expect(frame.w > 0 && frame.h > 0,
                "the label resolved to \(frame.w)x\(frame.h), so nothing was laid out")
        // The resolved x is NOT the constant the constraint was written with, and
        // that gap is the clearest evidence in this test that the number came back
        // from AppKit rather than from the request: `NSTextField`'s alignment rect
        // is inset from its frame, so the solver satisfies the leading constraint
        // on the alignment rect and the frame lands to the left of it. Measured at
        // 22.0 against a constant of 24 on 2026-08-21. Nothing was laid out at all
        // would read 0.
        #expect(frame.x > 0 && frame.x < Double(Self.leadingInset),
                "the label resolved to x=\(frame.x) against a leading constant of \(Self.leadingInset)")
        #expect(abs((frame.y + frame.h) - Double(Self.contentHeight - Self.topInset)) < 0.5,
                "the solver put the label's top at \(frame.y + frame.h), not \(Self.contentHeight - Self.topInset) · frame \(frame)")
        #expect(Self.rect(labelNode["frameInWindow"]) != nil,
                "the node carried no window-space frame")

        // THE RESOLVED COLOUR. `labelWithString:` leaves `textColor` at the
        // dynamic system `labelColor`; the walk resolves it against the window's
        // effective appearance. The hex is a value nothing here named.
        let text = try #require(labelNode["text"] as? [String: Any])
        let colour = try #require(text["color"] as? [String: Any],
                                  "the label node carried no resolved colour")
        let hex = try #require(colour["hex"] as? String, "the colour did not resolve")
        #expect(hex.range(of: "^#[0-9A-F]{6}$", options: .regularExpression) != nil,
                "the resolved colour reads \(hex)")
        #expect(colour["catalog"] as? String != nil && colour["name"] as? String != nil,
                "the colour resolved to \(hex) with no catalog identity, so it was not a system colour resolved through an appearance")
        #expect(text["font"] != nil, "the label node carried no resolved font")

        // THE CALAYER MODEL. `wantsLayer` was asked for; the layer itself and
        // every property in this dictionary are CoreAnimation's.
        let contentNode = try #require(nodes.first)
        let layer = try #require(contentNode["layer"] as? [String: Any],
                                 "the layer-backed content view reported no layer")
        let model = try #require(layer["model"] as? [String: Any])
        for key in ["backgroundColor", "borderWidth", "cornerRadius", "opacity", "shadowRadius"] {
            #expect(model[key] != nil, "the layer model is missing \(key)")
        }

        // THE RESOLVED CONSTRAINTS, held by the common ancestor rather than by
        // the label — which is where AppKit installs a constraint between two
        // views, and the reason this reads the content node.
        let constraints = try #require(contentNode["constraints"] as? [[String: Any]],
                                       "constraints were requested and the node carried none")
        #expect(constraints.count >= 2,
                "the content view reported \(constraints.count) constraints over the two activated")
        #expect(constraints.allSatisfy { ($0["active"] as? Bool) == true },
                "a constraint came back inactive")
        let attributes = Set(constraints.compactMap { $0["firstAttribute"] as? String })
        #expect(!attributes.isEmpty, "no constraint named an attribute")

        // --- The sabotage ----------------------------------------------------
        // `stop()` closes the listening descriptor and unlinks the path. Nothing
        // else changes: same client, same window, same tree.
        await MainActor.run { ProctorReflector.stop() }
        #expect(!FileManager.default.fileExists(atPath: path),
                "stop() left the socket behind at \(path)")

        let afterStop = try await Self.onOwnThread { () -> [String: String] in
            var outcome: [String: String] = [:]
            for op in ["ping", "revision", "hierarchy"] {
                do {
                    _ = try RawClient.ask(["id": "w9-dead-\(op)", "op": op], at: path)
                    outcome[op] = "answered"
                } catch {
                    outcome[op] = "\(error)"
                }
            }
            return outcome
        }
        let stillAnswered = afterStop.values.filter { $0 == "answered" }.count
        #expect(stillAnswered == 0,
                "\(stillAnswered) connections were answered after stop() · \(afterStop)")
        #expect(afterStop.values.allSatisfy { $0.contains("connect failed") },
                "a refusal after stop() was not a connect failure · \(afterStop)")
        #expect(!ProctorReflector.isRunning)

        await MainActor.run { WindowHolder.shared.tearDown() }
    }
}
