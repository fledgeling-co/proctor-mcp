import Foundation
import Darwin

// PRO-0045, slice 4. Reading a line from a subprocess with a deadline that can
// actually expire.
//
// `CuaEndpointTransport.callTimeout` has existed since PRO-0044 and was never
// read: `exchange` did an unbounded blocking read, so a driver that accepted a
// request and never replied hung the step, the batch, the run panel and the lane
// for as long as the agent lived. Auditing "the driver answered late" would have
// been theatre while that was true, so the deadline is made real here.
//
// The type exists separately from the transport for one reason beyond tidiness:
// it takes a file descriptor, so a test drives it against a bare `Pipe()` and the
// whole deadline path is exercised on a machine that does not have the driver
// installed. Every bug below was found by review of the first sketch rather than
// in production, and each has a test.

/// Reads newline-delimited frames from a descriptor under a monotonic deadline.
final class CuaLineReader {

    /// Why a read did not produce a line.
    enum Fault: Error, Equatable {
        /// The deadline passed with no complete line available.
        case timedOut
        /// The far end closed. Distinct from a timeout, because a child that
        /// finished and closed is not a child that stopped answering — and
        /// treating one as the other would poison a lane over an orderly exit.
        case closed
    }

    private let fd: Int32
    /// Bytes read past the end of the line that was returned. Kept because a
    /// single `read(2)` can span frames: dropping the remainder would silently
    /// lose the reply after the one being served.
    private var residual = Data()

    init(fd: Int32) {
        self.fd = fd
    }

    /// One complete line, without its terminator, or a fault.
    func readLine(within budget: TimeInterval) throws -> Data {
        // A line already in hand is served without a syscall. Polling first would
        // let a healthy driver whose answer had already arrived blow the deadline
        // and poison its own lane over a reply that was sitting in this buffer.
        if let line = takeBufferedLine() { return line }

        // Monotonic. A wall clock jumps when the machine sleeps, which would make
        // a lid closed for an hour look like a driver that stopped answering.
        let deadline = DispatchTime.now().uptimeNanoseconds
            &+ UInt64(max(0, budget) * 1_000_000_000)

        while true {
            let now = DispatchTime.now().uptimeNanoseconds
            guard now < deadline else {
                // The budget is spent, so look once more before giving up: a line
                // can have landed in the residual during the last read of the
                // loop, and discarding it here would throw away an answer that
                // did arrive in time.
                if let line = takeBufferedLine() { return line }
                throw Fault.timedOut
            }

            // Integer milliseconds, floored at one. Truncation would turn a
            // remaining 400µs into `poll(…, 0)`, which returns immediately and
            // would poison the lane a fraction of a millisecond early.
            let remainingMs = Int32(min(Double((deadline &- now) / 1_000_000), 1_000_000))
            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let ready = poll(&pfd, 1, max(1, remainingMs))
            if ready < 0 {
                if errno == EINTR { continue }
                throw Fault.closed
            }
            if ready == 0 { continue }

            // POLLHUP arrives with POLLIN when the peer closed on data still
            // buffered, so a read is attempted whenever either is set and EOF is
            // decided by the read returning zero rather than by the flag.
            var chunk = [UInt8](repeating: 0, count: 4096)
            let n = chunk.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, 4096) }
            if n < 0 {
                if errno == EINTR || errno == EAGAIN { continue }
                throw Fault.closed
            }
            if n == 0 {
                // Clean EOF. A trailing line with no terminator is still a line
                // the driver wrote, and is returned rather than discarded.
                if !residual.isEmpty {
                    let line = residual
                    residual.removeAll()
                    return line
                }
                throw Fault.closed
            }
            residual.append(contentsOf: chunk[0..<n])
            if let line = takeBufferedLine() { return line }
        }
    }

    /// The first complete line in the buffer, if there is one.
    private func takeBufferedLine() -> Data? {
        guard let index = residual.firstIndex(of: UInt8(ascii: "\n")) else { return nil }
        let line = residual[residual.startIndex..<index]
        residual = residual[residual.index(after: index)...]
        return Data(line)
    }
}
