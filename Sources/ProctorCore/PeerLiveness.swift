import Foundation

// Is the process that took this lane still there?
//
// A run holds its lane for the whole length of the call that asked for it, and
// nothing bounds that call. When the shim driving a run exits mid-flight the
// lane is never given back: every later `proctor_act` is refused as `queueBusy`
// and the machine is unusable until the agent restarts. Measured three times in
// one session — `docs/test-campaign/evidence/witness/a4-stranded-run-queue.json`
// shows the stranded run still active at 932 seconds, past the 900-second pause
// backstop, which bounds a *paused* run rather than a dead peer.
//
// THE IDENTITY IS ALREADY ON THE WIRE AND ALREADY TRUSTED. `SessionIdentity`
// derives every caller from `getsockopt(SOL_LOCAL, LOCAL_PEERPID)` and
// `proc_pidinfo`, and mints `RunSessionIdentity.key` as `"<pid>:<start-time>"`
// precisely so that a reused pid is a different session. That key is enough to
// ask whether the process that took a lane is still running, so this needs no
// heartbeat, no new wire field and no cooperation from the client.
//
// RECLAIM ON DEATH, NEVER ON SILENCE. A peer that has exited is gone. One that
// is slow, stopped at a breakpoint, or blocked in a syscall is not, and taking
// its lane would cut off a live run — which is a worse failure than the one this
// fixes, because the run it kills was doing something. So there are three
// verdicts rather than two, and only the middle one acts: everything that is not
// positive proof of death reads `unknown` and leaves the lane alone.

/// What a probe of a pid found. Three cases rather than a `Bool`, because "I
/// could not tell" and "it is gone" want opposite responses.
public enum PeerProbe: Sendable, Equatable {
    /// The process exists, and this is when it started.
    case running(startedAt: UInt64)
    /// The kernel says there is no such process.
    case noSuchProcess
    /// The process could not be described — a permission failure, a short read.
    /// Never treated as death.
    case unreadable
}

/// Whether the process behind a session identity is still there.
public enum PeerLiveness {

    /// One peer, as the identity key already spells it.
    public struct Peer: Equatable, Sendable {
        public var pid: Int32
        /// Seconds, as `proc_bsdinfo.pbi_start_tvsec` reports them.
        public var startedAt: UInt64

        public init(pid: Int32, startedAt: UInt64) {
            self.pid = pid
            self.startedAt = startedAt
        }
    }

    public enum Verdict: String, Sendable, Equatable {
        case alive
        case gone
        /// Not answerable. Never reclaims.
        case unknown
    }

    /// Read a peer out of `RunSessionIdentity.key`, which is minted in
    /// `SessionIdentity.fromPeer` as `"<pid>:<start-time>"`.
    ///
    /// Nil for anything else, and that is the case that matters most: the
    /// unattributed identity carries the key `"unattributed"`, and every caller
    /// whose peer the kernel would not describe lands on it. A key that does not
    /// parse is a session this cannot judge, so it is never judged.
    public static func peer(fromKey key: String) -> Peer? {
        let parts = key.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let pid = Int32(parts[0]), pid > 0,
              let started = UInt64(parts[1]) else { return nil }
        return Peer(pid: pid, startedAt: started)
    }

    /// The verdict for one identity key, given a probe of the pid it names.
    ///
    /// The start-time comparison is the whole reason the key carries one. Pids
    /// are reused; a new process wearing a dead peer's number would otherwise
    /// keep that peer's lane alive forever, which is the same wedge this exists
    /// to clear, reached from the other side.
    public static func verdict(key: String, probe: (Int32) -> PeerProbe) -> Verdict {
        guard let peer = peer(fromKey: key) else { return .unknown }
        switch probe(peer.pid) {
        case .noSuchProcess:
            return .gone
        case .unreadable:
            return .unknown
        case .running(let startedAt):
            // A start time of zero is what `SessionIdentity.startTime` returns
            // when `proc_pidinfo` fails, and it is also what an identity minted
            // from that failure carries. Two zeroes agreeing is two failures
            // agreeing, not a match, so it decides nothing.
            if peer.startedAt == 0 || startedAt == 0 { return .unknown }
            return peer.startedAt == startedAt ? .alive : .gone
        }
    }
}
