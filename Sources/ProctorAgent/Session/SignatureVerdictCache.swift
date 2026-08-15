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
// Two rules the plan review forced, and they are the rules `GrantProbeKeeper`
// already follows:
//
//   - **The verification runs outside the lock.** Holding it across a 0.39 s hash
//     would put every concurrent doctor call behind one cache miss. The cost is
//     that two callers arriving together on a cold cache may both verify; that is
//     wasted work and nothing else, because the check is pure, idempotent and has
//     no timeout to mismanage. Single-flight would buy one saved hash and a state
//     machine to get wrong.
//   - **No `await` inside the critical section**, so the lock is never held
//     across a suspension and cannot deadlock against the reentrant actor.
//
// And the key is the file's identity rather than its timestamp. `(path, size,
// mtime)` aliases two different binaries: a same-second write, a `copyfile` or
// `utimes` that preserves the modification time, and an unlink-and-recreate at
// the same path all defeat it. `ctime` cannot be set with `utimes`, and the
// device and inode catch a replacement in place.
//
// What this is NOT: authorisation. `CuaPreflight` re-verifies immediately before
// it executes anything. A cached verdict is a statement about the file as it
// stood at `checkedAt`, which is what the report says it is.

/// Enough of a file's identity that a different file cannot wear it.
struct FileIdentity: Equatable, Sendable {
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

    private let lock = NSLock()
    private var cached: (identity: FileIdentity, verdict: ToolSignature)?
    private let identify: @Sendable (String) -> FileIdentity?
    private let verify: @Sendable (String) -> ToolSignature
    /// How many times the underlying verification actually ran. Read by the test
    /// that proves a second call on an unchanged file costs nothing.
    private var verifications = 0

    init(identify: @escaping @Sendable (String) -> FileIdentity? = FileIdentity.read,
         verify: @escaping @Sendable (String) -> ToolSignature = SignatureVerdictCache.verifyCua) {
        self.identify = identify
        self.verify = verify
    }

    /// The verdict for a path, verifying only when the file is one this cache has
    /// not already seen.
    func verdict(for path: String?) -> ToolSignature {
        guard let path, !path.isEmpty, let identity = identify(path) else { return .notChecked }

        lock.lock()
        if let cached, cached.identity == identity {
            defer { lock.unlock() }
            return cached.verdict
        }
        lock.unlock()

        let verdict = verify(path)

        lock.lock()
        cached = (identity, verdict)
        verifications += 1
        lock.unlock()
        return verdict
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
