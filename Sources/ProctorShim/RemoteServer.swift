import Foundation
import Darwin
import ProctorCore

// Remote MCP transport: a minimal HTTP/1.1 listener that speaks the MCP
// "Streamable HTTP" shape for the request/response case — POST a JSON-RPC
// message to /mcp, get the JSON-RPC reply back. It exists so a model on another
// machine (or another host process) can drive Proctor without a local stdio
// pipe, which is what "remote access" needs.
//
// It forwards to exactly the same MCPServer.response(for:) the stdio path uses,
// so a tool behaves identically over either wire. The shim still holds no
// permissions and keeps no state; adding a network front door does not change
// what it is allowed to do, only who can reach it — which is why the auth and
// bind rules below are the load-bearing part of this file.

struct RemoteConfig {
    var host: String
    var port: UInt16
    /// The bearer token a client must present. `nil` means no auth, which is
    /// only permitted on a loopback bind — see `run()`.
    var token: String?
    /// The advertised tool profile, applied identically to the HTTP path.
    var profile: ToolProfile = .full
}

final class RemoteServer: @unchecked Sendable {
    private let config: RemoteConfig
    private let mcp: MCPServer
    private let acceptQueue = DispatchQueue(label: "app.fledgeling.procter.remote.accept")
    private let workerQueue = DispatchQueue(
        label: "app.fledgeling.procter.remote.worker", attributes: .concurrent)
    // A cap so a burst of connections cannot spawn unbounded work. Tool calls
    // serialise at the agent anyway; this only bounds the front door.
    private let slots = DispatchSemaphore(value: 16)
    private let maxBodyBytes = 16 * 1024 * 1024

    init(config: RemoteConfig) {
        self.config = config
        self.mcp = MCPServer(profile: config.profile)
    }

    private var isLoopback: Bool {
        config.host == "127.0.0.1" || config.host == "localhost" || config.host == "::1"
    }

    // MARK: - Lifecycle

    func run() -> Never {
        // Fail closed: an unauthenticated listener on anything but loopback is a
        // machine offered to the network, so refuse rather than serve it.
        if config.token == nil && !isLoopback {
            fail("""
                refusing to serve on \(config.host) without a token. Anyone who can reach that \
                address could drive this Mac. Set PROCTOR_MCP_TOKEN (or pass --token), or bind \
                127.0.0.1 and reach it over an SSH tunnel.
                """)
        }
        if config.host == "::1" {
            fail("IPv6 is not supported by this listener; use 127.0.0.1 and an SSH tunnel for remote access.")
        }

        let host = config.host == "localhost" ? "127.0.0.1" : config.host
        var inaddr = in_addr()
        guard inet_pton(AF_INET, host, &inaddr) == 1 else {
            fail("not an IPv4 address to bind: \(config.host)")
        }

        let fd = socket(AF_INET, SOCK_STREAM, 0)
        // DEF-342, and the only one of this package's four socket servers where
        // the fault was reachable: neither this listener nor the descriptors it
        // accepted carried SO_NOSIGPIPE, so a write to a peer that had gone
        // raised SIGPIPE and terminated proctor-shim. The other three suppressed
        // on the listener and their accepted descriptors inherited it.
        if fd >= 0 { proctorSuppressSIGPIPE(fd) }
        guard fd >= 0 else { fail("socket() failed: \(String(cString: strerror(errno)))") }
        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = config.port.bigEndian
        addr.sin_addr = inaddr
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else {
            fail("bind \(host):\(config.port) failed: \(String(cString: strerror(errno)))")
        }
        guard listen(fd, 32) == 0 else {
            fail("listen failed: \(String(cString: strerror(errno)))")
        }

        let auth = config.token == nil ? "no auth (loopback only)" : "bearer token required"
        shimLog("serving MCP over HTTP on http://\(host):\(config.port)/mcp — \(auth); profile \(config.profile.rawValue); agent socket \(Wire.socketPath)")

        while true {
            let client = accept(fd, nil, nil)
            // The descriptor `respond` writes the HTTP reply down. A model on
            // another machine that closes the connection mid-reply is ordinary.
            // It inherits the option set on the listener above; this makes it
            // explicit, as the other three servers do.
            if client >= 0 { proctorSuppressSIGPIPE(client) }
            if client < 0 { if errno == EINTR { continue }; break }
            slots.wait()
            workerQueue.async { [weak self] in
                defer { self?.slots.signal() }
                self?.serve(client)
            }
        }
        fail("accept loop ended: \(String(cString: strerror(errno)))")
    }

    // MARK: - One connection

    private func serve(_ client: Int32) {
        defer { close(client) }
        var tv = timeval(tv_sec: 30, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        guard let request = readRequest(client) else {
            writeResponse(client, status: 400, reason: "Bad Request",
                          contentType: "text/plain", body: Data("malformed request\n".utf8))
            return
        }

        // DNS-rebinding guard: a browser page on another origin can POST here,
        // but only a same-origin (or origin-less, i.e. non-browser) client is
        // trusted. Non-browser agents send no Origin and pass freely.
        if let origin = request.headers["origin"], !originIsLocal(origin) {
            writeResponse(client, status: 403, reason: "Forbidden",
                          contentType: "text/plain", body: Data("origin not allowed\n".utf8))
            return
        }

        // Liveness, deliberately unauthenticated and side-effect free.
        if request.method == "GET" && request.path == "/health" {
            writeResponse(client, status: 200, reason: "OK",
                          contentType: "application/json",
                          body: Data("{\"ok\":true,\"server\":\"proctor\",\"version\":\"\(BuildInfo.current.descriptor)\"}\n".utf8))
            return
        }

        guard authorized(request) else {
            writeResponse(client, status: 401, reason: "Unauthorized",
                          contentType: "text/plain",
                          extraHeaders: ["WWW-Authenticate": "Bearer"],
                          body: Data("a bearer token is required\n".utf8))
            return
        }

        guard request.method == "POST", request.path == "/mcp" || request.path == "/" else {
            // A GET to /mcp would be the server-initiated SSE stream, which this
            // request/response listener does not open.
            writeResponse(client, status: 405, reason: "Method Not Allowed",
                          contentType: "text/plain",
                          extraHeaders: ["Allow": "POST"],
                          body: Data("POST a JSON-RPC message to /mcp\n".utf8))
            return
        }

        // Require application/json, which the MCP Streamable HTTP spec mandates.
        // It also closes the cross-origin CSRF path: a browser can only omit the
        // CORS preflight for a "simple request", and a simple request cannot
        // carry this content type — so a malicious page cannot POST here without
        // a preflight this server never answers.
        let contentType = (request.headers["content-type"] ?? "").lowercased()
        guard contentType.hasPrefix("application/json") else {
            writeResponse(client, status: 415, reason: "Unsupported Media Type",
                          contentType: "text/plain",
                          body: Data("POST /mcp requires Content-Type: application/json\n".utf8))
            return
        }

        let message: JSONValue
        do {
            message = try JSONDecoder().decode(JSONValue.self, from: request.body)
        } catch {
            let err = mcp.encode(errorEnvelope(code: -32700, message: "parse error")) ?? Data()
            writeResponse(client, status: 400, reason: "Bad Request",
                          contentType: "application/json", body: err)
            return
        }

        guard let reply = mcp.response(for: message) else {
            // A notification carries no id and is answered with 202 + no body,
            // exactly as the Streamable HTTP spec asks.
            writeResponse(client, status: 202, reason: "Accepted",
                          contentType: "text/plain", body: Data())
            return
        }
        let body = mcp.encode(reply) ?? Data("{}".utf8)
        writeResponse(client, status: 200, reason: "OK",
                      contentType: "application/json", body: body)
    }

    // MARK: - Auth

    private func authorized(_ request: HTTPRequest) -> Bool {
        guard let expected = config.token else { return true }  // loopback no-auth
        guard let header = request.headers["authorization"] else { return false }
        let parts = header.split(separator: " ", maxSplits: 1)
        guard parts.count == 2, parts[0].lowercased() == "bearer" else { return false }
        return constantTimeEquals(String(parts[1]), expected)
    }

    private func originIsLocal(_ origin: String) -> Bool {
        // Match the host exactly — a prefix test treats http://localhost.evil.com
        // and http://127.0.0.1.evil.com as local and hands a malicious page the
        // unauthenticated loopback door. An opaque origin ("null", from a
        // sandboxed iframe or file://) is not trusted either.
        if origin.lowercased() == "null" { return false }
        guard let host = URL(string: origin)?.host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }

    // MARK: - HTTP plumbing

    private struct HTTPRequest {
        var method: String
        var path: String
        var headers: [String: String]  // keys lowercased
        var body: Data
    }

    private func readRequest(_ client: Int32) -> HTTPRequest? {
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 65536)

        // Read until the header terminator is in hand.
        func headerEnd() -> Int? {
            let sep: [UInt8] = [0x0D, 0x0A, 0x0D, 0x0A]
            guard buffer.count >= sep.count else { return nil }
            let bytes = [UInt8](buffer)
            for i in 0...(bytes.count - sep.count) where Array(bytes[i..<i+sep.count]) == sep {
                return i + sep.count
            }
            return nil
        }

        var bodyStart = headerEnd()
        while bodyStart == nil {
            let n = read(client, &chunk, chunk.count)
            if n <= 0 { return nil }
            buffer.append(contentsOf: chunk[0..<n])
            if buffer.count > maxBodyBytes { return nil }
            bodyStart = headerEnd()
        }
        guard let headerLen = bodyStart,
              let headerText = String(data: buffer.prefix(headerLen), encoding: .utf8) else { return nil }

        var lines = headerText.split(separator: "\r\n", omittingEmptySubsequences: false)
        guard let requestLine = lines.first else { return nil }
        let requestParts = requestLine.split(separator: " ")
        guard requestParts.count >= 2 else { return nil }
        let method = String(requestParts[0])
        let path = String(requestParts[1])

        var headers: [String: String] = [:]
        lines.removeFirst()
        for line in lines where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[line.startIndex..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        var body = buffer.suffix(from: headerLen)
        let declared = Int(headers["content-length"] ?? "0") ?? 0
        if declared > maxBodyBytes { return nil }
        while body.count < declared {
            let n = read(client, &chunk, chunk.count)
            if n <= 0 { break }
            buffer.append(contentsOf: chunk[0..<n])
            if buffer.count > maxBodyBytes { return nil }
            body = buffer.suffix(from: headerLen)
        }
        return HTTPRequest(method: method, path: path, headers: headers, body: Data(body.prefix(declared)))
    }

    private func writeResponse(_ client: Int32, status: Int, reason: String,
                               contentType: String,
                               extraHeaders: [String: String] = [:],
                               body: Data) {
        var head = "HTTP/1.1 \(status) \(reason)\r\n"
        head += "Content-Type: \(contentType)\r\n"
        head += "Content-Length: \(body.count)\r\n"
        head += "Connection: close\r\n"
        for (k, v) in extraHeaders { head += "\(k): \(v)\r\n" }
        head += "\r\n"
        var out = Data(head.utf8)
        out.append(body)
        out.withUnsafeBytes { raw in
            var sent = 0
            while sent < raw.count {
                let n = write(client, raw.baseAddress!.advanced(by: sent), raw.count - sent)
                if n <= 0 { break }
                sent += n
            }
        }
    }

    private func errorEnvelope(code: Int, message: String) -> JSONValue {
        .object([
            "jsonrpc": .string("2.0"),
            "id": .null,
            "error": .object(["code": .number(Double(code)), "message": .string(message)])
        ])
    }

    private func constantTimeEquals(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        var diff = UInt8(x.count == y.count ? 0 : 1)
        let n = max(x.count, y.count)
        for i in 0..<n {
            let xv = i < x.count ? x[i] : 0
            let yv = i < y.count ? y[i] : 0
            diff |= xv ^ yv
        }
        return diff == 0
    }

    private func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data("proctor-shim: \(message)\n".utf8))
        exit(2)
    }
}
