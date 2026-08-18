import Testing
import Foundation
import ProctorCore
@testable import ProctorAgent

// PRO-0045, slice 4. The deadline, against a bare pipe.
//
// `cua-driver` is not installed on this machine and PRO-0023 forbids installing
// it as a side effect, so the whole timeout path would otherwise be unexercised.
// It is testable because the reader takes a file descriptor rather than a
// process: everything below runs against `Pipe()`.
//
// Every case here is a bug the plan review found in the first sketch of this
// type. They are kept as tests rather than as comments because each one fails
// silently in production — a lane poisoned a fraction of a millisecond early, or
// over a reply that had already arrived, looks exactly like a driver that stopped
// answering.

@Suite("Delegated call deadline")
struct CuaLineReaderTests {

    private func pipeAndReader() -> (Pipe, CuaLineReader) {
        let pipe = Pipe()
        return (pipe, CuaLineReader(fd: pipe.fileHandleForReading.fileDescriptor))
    }

    @Test("a line already written comes back whole")
    func readsOneLine() throws {
        let (pipe, reader) = pipeAndReader()
        pipe.fileHandleForWriting.write(Data("{\"ok\":true}\n".utf8))
        let line = try reader.readLine(within: 2)
        #expect(String(decoding: line, as: UTF8.self) == "{\"ok\":true}")
    }

    @Test("two frames arriving in one chunk are both read")
    func residualSurvivesBetweenCalls() throws {
        // A single `read(2)` can span frames. Dropping the remainder would lose
        // the reply after the one being served, which on a protocol matched by
        // position corrupts every call after it.
        let (pipe, reader) = pipeAndReader()
        pipe.fileHandleForWriting.write(Data("first\nsecond\n".utf8))
        #expect(String(decoding: try reader.readLine(within: 2), as: UTF8.self) == "first")
        #expect(String(decoding: try reader.readLine(within: 2), as: UTF8.self) == "second")
    }

    @Test("a buffered line is served without waiting on the deadline")
    func bufferedLineIsNotDelayedByTheClock() throws {
        // Bug: polling before checking the buffer. A healthy driver whose answer
        // had already arrived would blow its own deadline and poison its lane
        // over a reply sitting in this object.
        let (pipe, reader) = pipeAndReader()
        pipe.fileHandleForWriting.write(Data("first\nsecond\n".utf8))
        _ = try reader.readLine(within: 2)
        // Zero budget: the only way this can succeed is by serving the buffer
        // before it consults the clock.
        #expect(String(decoding: try reader.readLine(within: 0), as: UTF8.self) == "second")
    }

    @Test("a sub-millisecond budget does not expire instantly")
    func tinyBudgetIsFlooredRatherThanTruncated() throws {
        // Bug: `poll` takes integer milliseconds, so a remaining 400µs truncates
        // to `poll(…, 0)` — an immediate return, and a lane poisoned early.
        let (pipe, reader) = pipeAndReader()
        Thread.detachNewThread {
            Thread.sleep(forTimeInterval: 0.01)
            pipe.fileHandleForWriting.write(Data("late-but-inside\n".utf8))
        }
        let line = try reader.readLine(within: 0.0004 + 3.0)
        #expect(String(decoding: line, as: UTF8.self) == "late-but-inside")
    }

    @Test("a trailing line with no terminator survives the close")
    func eofReturnsTheUnterminatedTail() throws {
        // Bug: EOF read as a timeout. A driver that wrote its last reply without
        // a newline and exited would have its answer discarded and its lane
        // poisoned, when it had in fact answered.
        let (pipe, reader) = pipeAndReader()
        pipe.fileHandleForWriting.write(Data("no-newline-here".utf8))
        try pipe.fileHandleForWriting.close()
        let line = try reader.readLine(within: 2)
        #expect(String(decoding: line, as: UTF8.self) == "no-newline-here")
    }

    @Test("a clean close is reported as closed, never as a timeout")
    func eofIsNotATimeout() throws {
        // The two are different events: a child that finished and closed is not a
        // child that stopped answering, and only one of them should read as the
        // driver going silent.
        let (pipe, reader) = pipeAndReader()
        try pipe.fileHandleForWriting.close()
        #expect(throws: CuaLineReader.Fault.closed) {
            _ = try reader.readLine(within: 2)
        }
    }

    @Test("a driver that never answers gives up on the deadline instead of hanging")
    func silenceExpires() throws {
        // The defect this slice exists to fix. `callTimeout` was declared in
        // PRO-0044 and never read, so this read was unbounded: a driver that
        // accepted a request and never replied held the step, the batch and the
        // run panel for as long as the agent lived.
        let (pipe, reader) = pipeAndReader()
        let started = Date()
        #expect(throws: CuaLineReader.Fault.timedOut) {
            _ = try reader.readLine(within: 0.2)
        }
        #expect(Date().timeIntervalSince(started) < 2)
        _ = pipe
    }
}
