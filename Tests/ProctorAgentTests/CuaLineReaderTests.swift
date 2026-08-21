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

    private func pipeAndReader(clock: TestClock) -> (Pipe, CuaLineReader) {
        let pipe = Pipe()
        return (pipe, CuaLineReader(fd: pipe.fileHandleForReading.fileDescriptor,
                                    now: { clock.read() }))
    }

    /// A monotonic clock the test drives. `step` is what each reading advances it
    /// by, so a budget can be spent without any of it being waited out; a step of
    /// zero freezes it, which is the arm that says what the reader does while its
    /// budget is *not* spent.
    private final class TestClock: @unchecked Sendable {
        private let lock = NSLock()
        private let step: UInt64
        private var t: UInt64 = 0
        private var readings = 0

        init(stepNanoseconds: UInt64) { self.step = stepNanoseconds }

        func read() -> UInt64 {
            lock.lock(); defer { lock.unlock() }
            let value = t
            t &+= step
            readings += 1
            return value
        }

        var elapsed: UInt64 { lock.lock(); defer { lock.unlock() }; return t }
        var count: Int { lock.lock(); defer { lock.unlock() }; return readings }
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

    @Test("a driver that never answers gives up when the budget it was given is spent")
    func silenceExpiresOnTheBudget() throws {
        // The defect this slice exists to fix. `callTimeout` was declared in
        // PRO-0044 and never read, so this read was unbounded: a driver that
        // accepted a request and never replied held the step, the batch and the
        // run panel for as long as the agent lived.
        //
        // This used to end with `#expect(Date().timeIntervalSince(started) < 2)`,
        // which asserts how fast this Mac is. The claim worth making is that the
        // reader gives up on *its budget* — so the clock is told to it, stepped 100ms
        // per reading, so the 200ms budget is spent in three readings: one to set
        // the deadline, one inside it that polls, and one past it that gives up.
        let clock = TestClock(stepNanoseconds: 100_000_000)
        let (pipe, reader) = pipeAndReader(clock: clock)
        #expect(throws: CuaLineReader.Fault.timedOut) {
            _ = try reader.readLine(within: 0.2)
        }
        // Three readings, not one: the deadline was re-read inside the loop rather
        // than decided once, so the reader polled and came back before giving up. A
        // reader that read the clock only twice never entered the loop body.
        #expect(clock.count >= 3)
        #expect(clock.elapsed >= 200_000_000)
        _ = pipe
    }

    @Test("it does not give up while the budget it was given is unspent, however long that takes")
    func aFrozenBudgetIsNeverSpent() throws {
        // The other arm, and the one a stopwatch cannot give. With the clock frozen
        // the budget never runs down, so a reply arriving 300ms late is still served
        // — which on the real clock, against this 200ms budget, would be a timeout.
        // That is what makes the pair discriminating: the two arms disagree unless
        // the deadline really is judged against the injected clock.
        let clock = TestClock(stepNanoseconds: 0)
        let (pipe, reader) = pipeAndReader(clock: clock)
        // The writer holds the whole `Pipe`, not just the writing half. Measured
        // while arming this case: with only the write handle captured, a run in
        // which the reader gave up early released the reading end first and the
        // late write took SIGPIPE, killing the test process — so a failure crashed
        // the run instead of reporting itself.
        Thread.detachNewThread {
            Thread.sleep(forTimeInterval: 0.3)
            try? pipe.fileHandleForWriting.write(contentsOf: Data("late\n".utf8))
        }
        let line = try reader.readLine(within: 0.2)
        #expect(String(decoding: line, as: UTF8.self) == "late")
    }
}
