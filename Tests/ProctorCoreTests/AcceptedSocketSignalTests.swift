import Darwin
import Foundation
import Testing
@testable import ProctorCore

/// What an accepted descriptor inherits, measured rather than asserted.
///
/// `Server.swift` used to state the opposite of what these tests measure — *"An
/// ACCEPTED descriptor does not inherit SO_NOSIGPIPE from its listener"* — and
/// nothing had ever checked it. On Darwin 25.6.0 it does inherit, on `AF_UNIX`
/// and `AF_INET` alike, which is why three of the four socket servers here were
/// safe while looking bare. The fourth, `ProctorShim/RemoteServer.swift`,
/// suppressed on neither descriptor and was genuinely reachable: that is DEF-342.
/// These tests bind real listeners of both families and read the option back.
///
/// The signal half is measured with a THREAD-SCOPED mask rather than by letting
/// the fault happen. `pthread_sigmask` blocks SIGPIPE on this thread only, so a
/// write that generates it leaves it pending instead of terminating the runner,
/// and `sigpending` reads that back. Swift Testing runs suites in parallel, so a
/// process-wide `signal(SIGPIPE, SIG_IGN)` would change what every other suite is
/// running under; this does not. It also means the armed direction — an
/// unsuppressed descriptor — can be run for real rather than described.
private final class AcceptedPair {
    let listenFD: Int32
    let clientFD: Int32      // this process's connecting end
    let acceptedFD: Int32    // what the server would write down
    private let unixPath: String?

    /// - Parameters:
    ///   - family: `AF_UNIX` for the agent, broker and Reflector sockets;
    ///     `AF_INET` for proctor-shim's remote transport, which is where DEF-342
    ///     was reachable.
    ///   - suppressOnListener: set `SO_NOSIGPIPE` on the listener only. Whether
    ///     that reaches the accepted descriptor is the thing under measurement.
    init?(family: Int32, suppressOnListener: Bool) {
        let l = socket(family, SOCK_STREAM, 0)
        guard l >= 0 else { return nil }
        if suppressOnListener { proctorSuppressSIGPIPE(l) }

        var path: String?
        var client: Int32 = -1

        if family == AF_UNIX {
            let dir = NSTemporaryDirectory() + "proctor-sigpipe-\(UUID().uuidString.prefix(8))"
            try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
            let p = dir + "/s"
            path = p
            var addr = sockaddr_un()
            addr.sun_family = sa_family_t(AF_UNIX)
            let bytes = Array(p.utf8)
            guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { close(l); return nil }
            withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: bytes) }
            let size = socklen_t(MemoryLayout<sockaddr_un>.size)
            let bound = withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(l, $0, size) }
            }
            guard bound == 0, listen(l, 4) == 0 else { close(l); return nil }

            client = socket(AF_UNIX, SOCK_STREAM, 0)
            guard client >= 0 else { close(l); return nil }
            let connected = withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(client, $0, size) }
            }
            guard connected == 0 else { close(l); close(client); return nil }
        } else {
            var addr = sockaddr_in()
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            addr.sin_port = 0                                              // the kernel picks
            addr.sin_addr = in_addr(s_addr: UInt32(0x7F00_0001).bigEndian) // 127.0.0.1
            let size = socklen_t(MemoryLayout<sockaddr_in>.size)
            let bound = withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(l, $0, size) }
            }
            guard bound == 0, listen(l, 4) == 0 else { close(l); return nil }

            // Read back the port the kernel chose, so the connect below reaches
            // this listener rather than a hard-coded one another test may hold.
            var actual = sockaddr_in()
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            let named = withUnsafeMutablePointer(to: &actual) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(l, $0, &length) }
            }
            guard named == 0, actual.sin_port != 0 else { close(l); return nil }

            client = socket(AF_INET, SOCK_STREAM, 0)
            guard client >= 0 else { close(l); return nil }
            let connected = withUnsafePointer(to: &actual) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(client, $0, size) }
            }
            guard connected == 0 else { close(l); close(client); return nil }
        }

        let a = accept(l, nil, nil)
        guard a >= 0 else { close(l); close(client); return nil }

        listenFD = l; clientFD = client; acceptedFD = a; unixPath = path
    }

    /// `SO_NOSIGPIPE` as the kernel reports it for a descriptor.
    static func noSigPipe(_ fd: Int32) -> Int32 {
        var value: Int32 = -1
        var length = socklen_t(MemoryLayout<Int32>.size)
        guard getsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &value, &length) == 0 else { return -1 }
        return value
    }

    deinit {
        close(acceptedFD); close(clientFD); close(listenFD)
        if let unixPath {
            try? FileManager.default.removeItem(
                atPath: (unixPath as NSString).deletingLastPathComponent)
        }
    }
}

/// Run `sigpipe_disposition_probe.py` in a child and report how it ended.
///
/// The fault under measurement is "the default disposition terminates the
/// process", so the only honest place to run it is a process whose termination
/// is the result. An earlier version blocked SIGPIPE on the writing thread with
/// `pthread_sigmask` and asserted `sigpending`; the mask did not hold and
/// `swift test` came back `exited with unexpected signal code 13`, reporting the
/// four passing tests beside it as a failed run.
private func runDispositionProbe(family: String, suppressOnListener: Bool)
    throws -> (status: Int32, signal: Int32, output: String) {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let script = root.appendingPathComponent("scripts/campaign/sigpipe_disposition_probe.py")
    try #require(FileManager.default.fileExists(atPath: script.path))

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["python3", script.path, "--family", family]
        + (suppressOnListener ? ["--suppress"] : [])
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    process.waitUntilExit()
    return (process.terminationStatus,
            process.terminationReason == .uncaughtSignal ? process.terminationStatus : 0,
            output)
}

@Suite("An accepted socket carries its own signal disposition")
struct AcceptedSocketSignalTests {

    @Test("Measured on Darwin: an accepted AF_UNIX descriptor inherits its listener's SO_NOSIGPIPE")
    func theOptionIsInheritedOnUnix() throws {
        let suppressed = try #require(AcceptedPair(family: AF_UNIX, suppressOnListener: true))
        #expect(AcceptedPair.noSigPipe(suppressed.listenFD) == 1)
        #expect(AcceptedPair.noSigPipe(suppressed.acceptedFD) == 1,
                "the accepted descriptor inherits — the comment that said otherwise was never measured")

        let bare = try #require(AcceptedPair(family: AF_UNIX, suppressOnListener: false))
        #expect(AcceptedPair.noSigPipe(bare.listenFD) == 0)
        #expect(AcceptedPair.noSigPipe(bare.acceptedFD) == 0,
                "and it inherits the absence too, which is why RemoteServer's bare listener mattered")
    }

    @Test("The same holds for AF_INET, which is the family proctor-shim's remote transport listens on")
    func theOptionIsInheritedOnInet() throws {
        let suppressed = try #require(AcceptedPair(family: AF_INET, suppressOnListener: true))
        #expect(AcceptedPair.noSigPipe(suppressed.acceptedFD) == 1)

        let bare = try #require(AcceptedPair(family: AF_INET, suppressOnListener: false))
        #expect(AcceptedPair.noSigPipe(bare.acceptedFD) == 0)
    }

    @Test("Setting it directly on the accepted descriptor also takes")
    func settingItOnTheAcceptedDescriptorTakes() throws {
        let pair = try #require(AcceptedPair(family: AF_UNIX, suppressOnListener: false))
        #expect(AcceptedPair.noSigPipe(pair.acceptedFD) == 0)
        #expect(proctorSuppressSIGPIPE(pair.acceptedFD) == 0)
        #expect(AcceptedPair.noSigPipe(pair.acceptedFD) == 1)
    }

    @Test("DEF-342: a bare AF_INET listener — proctor-shim's shape — dies by SIGPIPE on the reply path",
          arguments: ["unix", "inet"])
    func theFaultItself(family: String) throws {
        let run = try runDispositionProbe(family: family, suppressOnListener: false)
        #expect(run.signal == SIGPIPE,
                Comment(rawValue: "the child should be terminated by signal 13; it ended \(run.status). \(run.output)"))
    }

    @Test("Suppressing the listener is enough: the same write returns EPIPE and the process lives",
          arguments: ["unix", "inet"])
    func theFixMeasuredOnTheSameFixture(family: String) throws {
        let run = try runDispositionProbe(family: family, suppressOnListener: true)
        #expect(run.status == 0,
                Comment(rawValue: "the child should survive; it ended \(run.status). \(run.output)"))
        #expect(run.output.contains("accepted_opt=1"),
                Comment(rawValue: "the accepted descriptor should inherit the option: \(run.output)"))
        // EPIPE when the write is the one after the FIN, ECONNRESET when the
        // peer's RST arrived first. Which one lands on AF_INET is a race, so the
        // claim asserted is the one that matters: an error return, not a signal.
        #expect(run.output.contains("EPIPE on write") || run.output.contains("ECONNRESET on write"),
                Comment(rawValue: "the write should fail with an errno rather than a signal: \(run.output)"))
        #expect(run.output.contains("writes errored"),
                Comment(rawValue: "and the probe should say how many of its writes errored, so a run where none did is not read as a pass: \(run.output)"))
    }

    @Test("Every descriptor Sources/ produces suppresses the signal — the census that would have caught DEF-342")
    func theCensusPasses() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let script = root.appendingPathComponent("scripts/campaign/socket_signal_census.py")
        try #require(FileManager.default.fileExists(atPath: script.path))

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", script.path, "--root", root.path, "--gate"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()

        #expect(process.terminationStatus == 0, Comment(rawValue: output))
        #expect(output.contains("PASS: all 9 descriptor(s)"),
                Comment(rawValue: "the census should name its denominator: \(output)"))
    }
}
