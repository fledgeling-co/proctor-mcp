import Foundation
import ProctorCore

// PRO-0050. What a binary's code signature says, cached on the file's identity.
//
// This is the strongest thing `proctor_doctor` can establish about `cua-driver`
// without running it, and running it is not on offer: a health check that spawns
// a subprocess is a side-effect channel, and the first call the Proctor skill
// tells a model to make is the worst possible place for one. A signature check
// reads the file and executes nothing, and it is the same check that decides
// whether the binary may ever be executed — so a driver that would be refused at
// the lane's first step is refused in the health report too, in advance, with
// the same reason.
//
// **MEASURED, 2026-08-15:** verifying an 82 MB binary costs 0.32-0.39 s, against
// 0.01 s for a small one. The status window polls doctor every 2.0 s, so this
// has to be cached or a fifth of every poll goes into re-hashing a file that has
// not changed.
//
// Three rules, and the third of them is PRO-0087 correcting the first version of
// this note:
//
//   - **The verification runs outside the lock.** Holding it across a 0.39 s hash
//     would put every concurrent doctor call behind one cache miss. This is the
//     rule `GrantProbeKeeper` already follows, and it stands.
//   - **No `await` inside the critical section**, so the lock is never held
//     across a suspension and cannot deadlock against the reentrant actor.
//   - **The dedupe is process-wide and single-flight, and nothing waits on a
//     cooperative thread.** The original note argued that two callers arriving
//     together on a cold cache both verifying was "wasted work and nothing else",
//     and that single-flight "would buy one saved hash and a state machine to get
//     wrong". Both halves were wrong, and DEF-044 is what wrong looked like: a
//     cache was built per `ToolProbes` and so per `Session`, while the verdict it
//     holds is a fact about a file and is the same for every session on the
//     machine. Fifteen sessions therefore verified one 82 MB binary fifteen times
//     at once. A `sample` taken during the wedge found 15 of 22 threads parked in
//     `SecStaticCodeCheckValidity`, every one of them on
//     `com.apple.root.default-qos.cooperative`; `Server.dispatchBlocking` could
//     not get a thread for its `Task.detached`, and a peer with a 10 s receive
//     timeout went unserved — which took REQ-035's security witness with it,
//     three runs in five.
//
//     So the store is shared by default (`SignatureVerdictCache.shared`, which
//     `ToolProbes` takes as its default), and callers arriving on an identity
//     that is already being verified join that verification rather than starting
//     another. Fifteen callers on a cold entry are one verification and fourteen
//     waiters.
//
//     **MEASURED, 2026-08-21, and it is why `verdict(for:)` is `async`.** Making
//     those fourteen waiters block on a condition variable fixed the wasted work
//     and not the wedge. A sample of a run that hung with that version showed all
//     sixteen cooperative threads blocked — fifteen in `__psynch_cvwait` inside
//     this file, one in `Security::Dispatch::Group::wait()` — and **no
//     non-cooperative `com.apple.root.default-qos` worker thread in the process
//     at all**. The pool is strictly capped at the core count and does not
//     replace a worker that blocks, so a blocked pool cannot lend Security's own
//     dispatch group the thread it is waiting for. Fifteen threads blocked
//     waiting for one verification starve it exactly as fifteen threads each
//     running one did.
//
//     So a caller **suspends** instead: it registers a continuation and gives its
//     thread back. The verification runs on a `Thread` of its own, off the pool
//     entirely, and resumes every waiter when it lands. Nothing in this path
//     holds a cooperative thread, so a slow verification costs the callers that
//     asked for it and costs the rest of the process nothing.
//
//     The seam survives it. `init(identify:verify:)` still takes both halves and
//     `ToolProbes` still takes the cache, so a test gets an isolated store by
//     passing one: this is a shared default rather than a singleton.
//
// And the key is the file's identity rather than its timestamp. `(path, size,
// mtime)` aliases two different binaries: a same-second write, a `copyfile` or
// `utimes` that preserves the modification time, and an unlink-and-recreate at
// the same path all defeat it. `ctime` cannot be set with `utimes`, and the
// device and inode catch a replacement in place. Identity is also what makes the
// store shareable: it is read with `stat`, which follows symlinks, so the
// `~/.local/bin/cua-driver` symlink and the binary it points at are one entry.
//
// What this is NOT: authorisation. `CuaPreflight` re-verifies immediately before
// it executes anything. A cached verdict is a statement about the file as it
// stood at `checkedAt`, which is what the report says it is.

/// Enough of a file's identity that a different file cannot wear it.
struct FileIdentity: Hashable, Sendable {
    var device: Int64
    var inode: UInt64
    var size: Int64
    var modified: Double
    /// Inode change time. Unlike `modified`, it cannot be set to an arbitrary
    /// value by the writer.
    var changed: Double

    /// Read a path's identity with one `stat`. Nil when there is nothing there.
    static func read(_ path: String) -> FileIdentity? {
        var buffer = stat()
        guard stat(path, &buffer) == 0 else { return nil }
        return FileIdentity(
            device: Int64(buffer.st_dev),
            inode: UInt64(buffer.st_ino),
            size: Int64(buffer.st_size),
            modified: Double(buffer.st_mtimespec.tv_sec)
                    + Double(buffer.st_mtimespec.tv_nsec) / 1_000_000_000,
            changed: Double(buffer.st_ctimespec.tv_sec)
                   + Double(buffer.st_ctimespec.tv_nsec) / 1_000_000_000)
    }
}

final class SignatureVerdictCache: @unchecked Sendable {

    /// The store every probe set shares unless a caller hands it another one.
    /// A verdict is a fact about a file rather than about a session, so one
    /// process asks once. DEF-044, recorded in this repo's registry as DEF-050.
    static let shared = SignatureVerdictCache()

    /// A plain lock. Every critical section below is a few dictionary operations
    /// with no suspension and no blocking call inside it, so there is nothing for
    /// a condition variable to do: a caller that finds a verification already
    /// running leaves a continuation behind and returns rather than waiting here.
    private let lock = NSLock()
    private var cached: [FileIdentity: ToolSignature] = [:]
    /// Insertion order, so a process that outlives several rebuilds of the same
    /// binary does not accumulate an entry per rebuild. Proctor asks about one
    /// binary; the bound is here because the store is now process-wide and
    /// nothing else would ever evict from it.
    private var order: [FileIdentity] = []
    private static let capacity = 16
    /// Everyone waiting on a verification that is running now, by identity. The
    /// key's presence is the in-flight flag; the array is who to resume.
    private var waiting: [FileIdentity: [CheckedContinuation<ToolSignature, Never>]] = [:]
    private let identify: @Sendable (String) -> FileIdentity?
    private let verify: @Sendable (String) -> ToolSignature
    /// How many times the underlying verification actually ran. Read by the tests
    /// that prove a second call on an unchanged file costs nothing and that
    /// fifteen callers arriving together cost one verification.
    private var verifications = 0

    init(identify: @escaping @Sendable (String) -> FileIdentity? = FileIdentity.read,
         verify: @escaping @Sendable (String) -> ToolSignature = SignatureVerdictCache.verifyCua) {
        self.identify = identify
        self.verify = verify
    }

    /// The verdict for a path, verifying only when the file is one no caller in
    /// this process has already verified or is verifying now.
    ///
    /// `async` because a caller that has to wait gives its thread back while it
    /// waits. `identify` is one `stat` and runs inline; only the verification
    /// leaves the caller.
    func verdict(for path: String?) async -> ToolSignature {
        guard let path, !path.isEmpty, let identity = identify(path) else { return .notChecked }

        return await withCheckedContinuation { continuation in
            lock.lock()
            if let verdict = cached[identity] {
                lock.unlock()
                continuation.resume(returning: verdict)
                return
            }
            if waiting[identity] != nil {
                waiting[identity]?.append(continuation)
                lock.unlock()
                return
            }
            // First one here owns the verification, and waits for it the same way
            // everyone else does.
            waiting[identity] = [continuation]
            lock.unlock()
            verifyOffThePool(identity, at: path)
        }
    }

    /// The verification, on a thread of its own.
    ///
    /// A `Thread` rather than `DispatchQueue.global()`: the thing being avoided is
    /// a verification that cannot get a worker, and asking the same starved
    /// workqueue for one would be asking the question that already went
    /// unanswered. One thread per verification is affordable because single-flight
    /// is what bounds them — one per file identity, and the shared store means one
    /// per identity for the whole process.
    private func verifyOffThePool(_ identity: FileIdentity, at path: String) {
        let thread = Thread { [self] in
            let verdict = verify(path)
            lock.lock()
            remember(identity, verdict)
            verifications += 1
            let toResume = waiting.removeValue(forKey: identity) ?? []
            lock.unlock()
            // Outside the lock: a continuation resumes a task, and a task should
            // never start running while this holds a lock it might ask for.
            for continuation in toResume { continuation.resume(returning: verdict) }
        }
        thread.name = "signature-verdict"
        thread.start()
    }

    /// Under the lock. The oldest entry goes when the map is full.
    private func remember(_ identity: FileIdentity, _ verdict: ToolSignature) {
        if cached.updateValue(verdict, forKey: identity) == nil {
            order.append(identity)
            if order.count > Self.capacity {
                cached.removeValue(forKey: order.removeFirst())
            }
        }
    }

    var verificationCount: Int {
        lock.lock(); defer { lock.unlock() }
        return verifications
    }

    /// The real check: `CuaPreflight`'s own, so the health report and the refusal
    /// a delegated step would produce cannot disagree about the same file.
    static func verifyCua(_ path: String) -> ToolSignature {
        switch CuaPreflight.verifySignature(path: path) {
        case .valid:                    return .valid
        case .unsigned:                 return .unsigned
        case .adhoc:                    return .adhoc
        case .wrongIdentity(let who):   return .wrongIdentity(who)
        case .unreadable(let why):      return .unreadable(why)
        }
    }
}
