import Foundation
import ProctorCore

// On-disk homes for the two rails, mirroring FlowStore: the policy is a small
// JSON document, the audit trail an append-only JSONL file. Both live under the
// agent's Application Support directory at 0700, so a locked, unattended run
// leaves a record on the same machine that produced it.

/// The persisted app policy. Loading a missing or unreadable file yields an empty
/// policy — no lists means the gate allows every app, which is the pre-feature
/// behaviour, so installing the tool changes nothing until an operator configures it.
///
/// **The root is told, not assumed.** This was a namespace of statics computing its
/// own path from the home directory, and the consequence was that a test which
/// configured a policy wrote the operator's real one — silently, on their own Mac,
/// changing what the agent is allowed to drive. The shape here is the one
/// `GuestProvider(executable:timeoutMs:run:)` and `SignatureVerdictCache(identify:verify:)`
/// already use: an instance told its dependency, beside a `live` binding the real
/// thing. A test points a store at a temporary directory and the operator's file is
/// not in the path at all, rather than being written and put back — a restore that
/// does not run, because the process was killed or an assertion threw, leaves the
/// policy changed and says nothing about it.
struct PolicyStore: Sendable {

    /// Where `policy.json` lives for this store.
    let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    var url: URL { directory.appendingPathComponent("policy.json", isDirectory: false) }

    func load() -> AppPolicy {
        guard let data = try? Data(contentsOf: url),
              let policy = try? JSONDecoder().decode(AppPolicy.self, from: data) else {
            return AppPolicy()
        }
        return policy
    }

    func save(_ policy: AppPolicy) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(policy).write(to: url, options: .atomic)
    }

    /// The operator's own policy directory, always — this is the path the agent
    /// reads and writes on a real Mac, and it stays truthful in a test process so a
    /// test can name the file it must not touch.
    static var operatorDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/\(Wire.bundleIdentifier)/policy",
                                    isDirectory: true)
    }

    /// The store the agent uses. Injection is what makes a test safe; this is the
    /// floor under it, and it is the same floor `AuditLog.directory` puts under the
    /// trail a few lines below, for the same reason: relying on every future test
    /// remembering to inject puts the operator's real configuration one forgotten
    /// line away.
    ///
    /// **In a test process every read of this is a fresh, empty directory**, which
    /// is deliberate and was measured. One shared temporary directory is the first
    /// thing anyone writes here, and it reproduces the second half of the defect
    /// with the operator's file swapped for a temporary one: 67 issues across 11
    /// suites, every one of them `policyDenied` on an app the failing test had
    /// never heard of, because one suite configured an allow list and every
    /// un-injected `Session` afterwards loaded it. The pre-fix code shared a file
    /// the same way — it shared the operator's own, so the whole suite's behaviour
    /// depended on what the person running it had configured, and it looked fine
    /// only because an empty policy allows everything.
    ///
    /// A `Session` reads this once at init, so its store is stable for its life;
    /// two sessions simply do not share one. Nothing is created on disk until
    /// something saves.
    static var live: PolicyStore {
        guard AuditLog.isTestProcess else { return PolicyStore(directory: operatorDirectory) }
        return PolicyStore(directory: testFallbackRoot
            .appendingPathComponent(UUID().uuidString, isDirectory: true))
    }

    /// Where an un-injected store lands in a test process. Named for what it is, so
    /// a stray directory in `/tmp` explains itself.
    static let testFallbackRoot = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("proctor-test-policy-\(ProcessInfo.processInfo.processIdentifier)",
                                isDirectory: true)
}

/// The append-only redacting audit trail, sealed at rest. One JSONL line per
/// event, each line encrypted on its own to a public key held beside the log, so
/// an append is still a single write and a file copied off the machine is
/// unreadable without the Keychain half (`AuditKeyStore`).
///
/// Appending is best-effort in one direction only: a write that fails must not
/// fail the action it was recording, but it must never fall back to plaintext.
/// A failure is remembered in `status` so a run that expected an audit and got
/// none can tell — before this the failure was silent.
enum AuditLog {

    /// What a stored line came back as. A line that cannot be opened is marked
    /// rather than dropped, so one bad or older entry does not blind the trail.
    enum Entry {
        case opened(String)
        case unreadable(kid: String?, reason: String)
    }

    /// Process-wide trail state, guarded the way the rest of the agent guards
    /// shared mutable state (`UnlockCoordinator`, `AXQuietTracker`).
    final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var migrationDone = false
        private var unavailable = false
        private var lastError: String?
        private var dropped = 0
        private var converted: Int?
        private var keyMismatch = false
        private var rotatedCount: Int?
        private var rotatedReason: HistoryRetention.Reason?
        private var seenCount: Int?

        func withLock<T>(_ body: () -> T) -> T {
            lock.lock(); defer { lock.unlock() }
            return body()
        }

        // Callers below already hold the lock via `withLock`.
        var isUnavailable: Bool { unavailable }
        var error: String? { lastError }
        var droppedCount: Int { dropped }
        var convertedCount: Int? { converted }
        var hasMigrated: Bool { migrationDone }
        var hasKeyMismatch: Bool { keyMismatch }
        /// How many records the last append actually saw in the file. The append
        /// reads the whole trail anyway, to take the chain link from disk rather
        /// than from memory, so this number is free and is the one thing that does
        /// not drift when a key store refuses to record a new end-mark.
        var lastSeenCount: Int? { seenCount }
        /// How many entries the last rotation this run discarded, and why. Kept
        /// so the trail's status can say a rotation happened rather than leaving
        /// a suddenly short trail to be discovered.
        var rotated: (count: Int, reason: HistoryRetention.Reason)? {
            guard let rotatedCount, let rotatedReason else { return nil }
            return (rotatedCount, rotatedReason)
        }

        func noteCount(_ n: Int) { seenCount = n }
        func markMigrated() { migrationDone = true }
        func markConverted(_ n: Int) { converted = n }
        func markRotated(discarded: Int, reason: HistoryRetention.Reason) {
            rotatedCount = (rotatedCount ?? 0) + discarded
            rotatedReason = reason
        }
        func markKeyMismatch() { keyMismatch = true }
        func fail(_ reason: String, unavailable: Bool = false, dropped: Bool = true) {
            lastError = reason
            if dropped { self.dropped += 1 }
            if unavailable { self.unavailable = true }
        }
        /// Clears the *current* error only. The dropped count is monotonic on
        /// purpose: a later success must not erase the fact that entries were lost,
        /// which is exactly the silence this feature was asked to remove.
        func clearError() { lastError = nil }
    }

    static let state = State()

    /// Where the signing key and the end-mark come from, and where the trail
    /// lives. Substituted only by a test: `swift test` runs with no live key
    /// store and must never create one, and two suites sharing one trail file
    /// would fight over the chain.
    ///
    /// **In a test process the defaults are inert.** They were the real key store
    /// once, and one run of the suite created a Secure Enclave key in the
    /// operator's login keychain before this was here — harmless in itself, and
    /// exactly the shape of the incident that put the trail interlock in this file
    /// in the first place. A test that means to exercise signing injects a signer;
    /// nothing else can reach the Mac's own.
    final class Seams: @unchecked Sendable {
        private let lock = NSLock()
        private var _signer: AuditSigning = isTestProcess ? InertSigner() : AuditSigningKeyStore.shared
        private var _anchors: AuditAnchoring = isTestProcess ? InertSigner() : AuditSigningKeyStore.shared
        private var _keys: AuditSealKeys = AuditKeyStore.shared
        private var _directory: URL?

        var signer: AuditSigning {
            get { lock.lock(); defer { lock.unlock() }; return _signer }
            set { lock.lock(); defer { lock.unlock() }; _signer = newValue }
        }
        var anchors: AuditAnchoring {
            get { lock.lock(); defer { lock.unlock() }; return _anchors }
            set { lock.lock(); defer { lock.unlock() }; _anchors = newValue }
        }
        /// The sealing pair. Unlike the signer this defaults to the live key store
        /// even in a test process, because the write path reads `audit.pub` from
        /// whatever directory is injected and creating a Keychain item needs that
        /// file to be *absent* — which every trail-touching suite already avoids by
        /// writing one. A suite that needs to read what it wrote injects a pair.
        var keys: AuditSealKeys {
            get { lock.lock(); defer { lock.unlock() }; return _keys }
            set { lock.lock(); defer { lock.unlock() }; _keys = newValue }
        }
        var directory: URL? {
            get { lock.lock(); defer { lock.unlock() }; return _directory }
            set { lock.lock(); defer { lock.unlock() }; _directory = newValue }
        }
    }

    static let seams = Seams()

    /// A test process never writes the operator's trail, whatever it forgets to
    /// inject. This is a safety interlock rather than a test hook, and it earns
    /// its place: a test that drove a real `Session` without redirecting its sink
    /// wrote 17 entries into a live trail and, worse, fired the one-way
    /// plaintext-to-sealed conversion on real history — a conversion that is
    /// deliberately irreversible and is supposed to be a decision somebody makes.
    /// Relying on every future test remembering `setAuditSink` puts real data one
    /// forgotten line away from a destructive migration, so the floor is here.
    static var isTestProcess: Bool {
        let env = ProcessInfo.processInfo.environment
        // Xcode's XCTest host announces itself in the environment; `swift test`
        // does not, and runs the suite inside `swiftpm-testing-helper`, so the
        // host executable is the only thing that identifies it. Checked rather
        // than assumed: the first version of this looked only for the XCTest
        // variables, was inert under `swift test`, and the regression test below
        // is what caught it. The agent's own executable is `proctor-agent` and
        // matches none of these.
        let host = (ProcessInfo.processInfo.arguments.first as NSString?)?
            .lastPathComponent ?? ""
        return env["XCTestConfigurationFilePath"] != nil
            || env["XCTestBundlePath"] != nil
            || host == "swiftpm-testing-helper"
            || host.hasSuffix(".xctest")
            || ProcessInfo.processInfo.arguments.contains { $0.hasSuffix(".xctest") }
            || Bundle.main.bundlePath.hasSuffix(".xctest")
    }

    static var directory: URL {
        if let injected = seams.directory { return injected }
        guard !isTestProcess else {
            return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("proctor-test-audit", isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/\(Wire.bundleIdentifier)/audit",
                                    isDirectory: true)
    }

    static var url: URL { directory.appendingPathComponent("audit.jsonl", isDirectory: false) }

    private static var convertingURL: URL {
        directory.appendingPathComponent("audit.jsonl.converting", isDirectory: false)
    }

    /// Append one record, sealed and signed. Creates the file and directory on
    /// first use, and converts any plaintext trail it finds before writing
    /// anything new. The write is a single `write(2)` of the record plus a
    /// newline, so concurrent appends serialise into whole lines rather than
    /// interleaving.
    ///
    /// Returns false — and writes nothing at all — when the record cannot be
    /// sealed **or cannot be signed**. There is deliberately no plaintext path
    /// out of here and, since PRO-0032, no unsigned one either: a readable
    /// fallback would silently undo the sealing, and an unsigned entry could not
    /// be told apart from a forged one, which would spend the guarantee signing
    /// exists to buy.
    @discardableResult
    static func append(_ record: AuditRecord) -> Bool {
        // In a test process, an append lands only where a test deliberately put
        // the trail. The directory interlock below is the floor — it keeps a test
        // off the operator's trail whatever anybody forgets — and this is the rest
        // of it: without it, every direct caller in the agent (a kill refusal, a
        // HUD decision) writes into whichever suite happens to have a trail
        // injected, and a count-based assertion silently depends on what else is
        // running. Measured: one such run put 59 entries in a file expecting 5.
        guard !isTestProcess || seams.directory != nil else { return false }
        // PRO-0073. Stamp the front end here rather than at each of the ~30 places
        // a record is built: this is the one point every row passes through, and
        // the value comes from the peer process rather than from the record's
        // author, so a caller cannot write itself into the trail as the other one.
        // A record that already names one keeps it — rotation's own attestation
        // is written by the agent, not by a caller.
        let record = stamping(record, frontEnd: SessionIdentity.current.frontEnd)
        return state.withLock {
            // The whole append, migration included, runs under a cross-process
            // advisory lock: the migration reads the file and then replaces it, so
            // a second agent appending in between would have its line dropped by
            // the swap. The in-process lock alone cannot see that. The chain needs
            // it for a second reason — the link is taken from the file under this
            // lock, never from memory, so two agents cannot fork it.
            let result: Bool? = withAuditFileLock {
                completeInterruptedRotationLocked()
                migrateIfNeededLocked()
                if state.isUnavailable { return false }
                return writeRecordLocked(record)
            }
            guard let result else {
                state.fail("The audit trail could not be locked for writing, so the entry was dropped.")
                return false
            }
            return result
        }
    }

    /// Name the front end on a record that does not already name one.
    ///
    /// A record that arrived carrying a value keeps it: rotation writes its own
    /// attestation, which the agent authored rather than a caller, and
    /// overwriting it would attribute Proctor's own bookkeeping to whoever
    /// happened to be connected.
    static func stamping(_ record: AuditRecord, frontEnd: String?) -> AuditRecord {
        guard record.via == nil else { return record }
        var stamped = record
        stamped.via = frontEnd
        return stamped
    }

    /// Seal, sign and append one record. Both locks are already held.
    ///
    /// Split out of `append` because rotation has to write its own attestation
    /// entry while it still holds the lock, and calling back into `append` from
    /// there would deadlock: `flock` is per open file description, so a second
    /// `open` of the lock file in this same process blocks against the first.
    private static func writeRecordLocked(_ record: AuditRecord) -> Bool {
        guard let pub = seams.keys.publicKey() else {
            state.fail("The audit key could not be reached, so nothing is being written to the trail.")
            return false
        }
        guard let sealed = AuditSeal.sealLine(line: record.jsonLine(), to: pub) else {
            state.fail("An audit entry could not be sealed, so it was dropped rather than written readable.")
            return false
        }
        guard let line = signLocked(sealed) else { return false }
        guard appendRawLocked(line.record, terminatePrevious: line.terminatePrevious) else {
            state.fail("The audit trail could not be written to.")
            return false
        }
        state.noteCount(line.anchor.count)
        seams.anchors.saveAnchor(line.anchor)
        state.clearError()
        return true
    }

    /// Chain and sign one sealed record against the trail as it stands on disk.
    /// Nil means the entry is dropped; the reason is already recorded.
    private static func signLocked(_ sealed: AuditSeal.SealedLine)
    -> (record: String, anchor: AuditChain.Anchor, terminatePrevious: Bool)? {
        guard let keyId = seams.signer.signingKeyId,
              let keyClass = seams.signer.signingKeyClass else {
            state.fail("The audit signing key could not be reached, so nothing is being written to "
                       + "the trail. An unsigned entry is not written, because it could not be told "
                       + "apart from a forged one.")
            return nil
        }
        let trail = readTrailLocked()
        let anchor = seams.anchors.loadAnchor()

        // Where the chain starts is answered from the *file*, not from the
        // anchor: an anchor that has been deleted must not silently reclassify
        // signed history as history that predates signing.
        let isGenesis = trail.firstChainedIndex == nil
        let previous = isGenesis
            ? AuditChain.genesisLink(preChainRecords: trail.records)
            : (trail.records.last.map(AuditChain.hash(record:)) ?? "")
        let trailId = anchor?.trailId ?? trail.lastTrailId ?? UUID().uuidString
        let preChainCount = trail.firstChainedIndex ?? trail.records.count

        let material = AuditChain.signedMaterial(
            version: sealed.v, trailId: trailId, previous: previous, keyId: keyId,
            keyClass: keyClass, sealKeyId: sealed.kid, ephemeralKey: sealed.epk,
            ciphertext: sealed.ct)
        guard let signature = seams.signer.sign(material),
              let record = AuditSeal.encode(sealed.signed(
                  prev: previous, tid: trailId, skid: keyId, cls: keyClass.rawValue,
                  sig: signature.base64EncodedString())) else {
            state.fail("An audit entry could not be signed, so it was dropped rather than written "
                       + "unsigned.")
            return nil
        }
        return (record,
                AuditChain.Anchor(trailId: trailId, count: trail.records.count + 1,
                                  head: AuditChain.hash(record: record), keyId: keyId,
                                  preChainCount: preChainCount,
                                  // Carried forward once it exists, and stamped on
                                  // the first entry of a trail that has none, so a
                                  // trail started before retention existed acquires
                                  // an age the first time it is appended to rather
                                  // than never.
                                  startedAt: anchor?.startedAt ?? clockNow()),
                !trail.endsWithNewline)
    }

    /// The wall clock, substitutable so a retention test can cross a fourteen-day
    /// boundary without waiting fourteen days. `nonisolated(unsafe)` for the same
    /// reason `RunHUDPanel.auditSink` is: it is set once, before anything runs,
    /// and read from wherever the trail is written.
    nonisolated(unsafe) static var clockNow: @Sendable () -> Double = {
        Date().timeIntervalSince1970
    }

    /// The trail as it sits on disk. Reads the whole file, which is what the
    /// existing `tail` and `lineCount` already do and is what the anchor's count
    /// needs anyway — and it is the honest version of "find the last record",
    /// since a fixed-size tail read is wrong for a record longer than the window
    /// and would break the chain permanently the first time one appeared.
    private static func readTrailLocked()
    -> (records: [String], endsWithNewline: Bool, firstChainedIndex: Int?, lastTrailId: String?) {
        guard let data = try? Data(contentsOf: url), !data.isEmpty,
              let text = String(data: data, encoding: .utf8) else {
            return ([], true, nil, nil)
        }
        let endsWithNewline = text.hasSuffix("\n")
        let records = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        var firstChained: Int?
        var lastTrailId: String?
        for (index, record) in records.enumerated() {
            guard let line = AuditSeal.decode(record), line.prev != nil, line.sig != nil else {
                continue
            }
            if firstChained == nil { firstChained = index }
            lastTrailId = line.tid
        }
        return (records, endsWithNewline, firstChained, lastTrailId)
    }

    /// Serialise every writer, in this process and any other, around the trail.
    /// The lock is a sidecar file rather than the trail itself, because the
    /// conversion replaces the trail's inode and a lock held on the old one would
    /// stop excluding anybody. Returns nil when the lock could not be taken, which
    /// the caller treats as a dropped entry rather than a licence to write.
    private static func withAuditFileLock<T>(_ body: () -> T) -> T? {
        let fm = FileManager.default
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o700])
        let path = directory.appendingPathComponent("audit.lock", isDirectory: false).path
        let fd = Darwin.open(path, O_RDWR | O_CREAT, 0o600)
        guard fd >= 0 else { return nil }
        defer { Darwin.close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { return nil }
        defer { flock(fd, LOCK_UN) }
        return body()
    }

    /// One append, opened `O_APPEND` so the kernel places the write at the end of
    /// the file atomically. Seeking to the end and writing is not the same thing:
    /// two writers can seek to the same offset and overwrite each other's line.
    ///
    /// `terminatePrevious` closes a torn final write by putting the missing
    /// newline in front of this record, in the same single write. The damage then
    /// stays a permanent, reported scar in the chain instead of being fused with
    /// this record's bytes and hidden.
    ///
    /// The descriptor is flushed before the caller records the new end-mark. The
    /// mark lives in the key store, which the system flushes on its own schedule,
    /// so without this an ordinary crash could leave a mark that is ahead of the
    /// bytes on disk — and a mark ahead of the trail reads as entries missing
    /// from the end, which is an accusation rather than a crash.
    private static func appendRawLocked(_ line: String, terminatePrevious: Bool = false) -> Bool {
        let text = (terminatePrevious ? "\n" : "") + line + "\n"
        guard let data = text.data(using: .utf8) else { return false }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        let fd = Darwin.open(url.path, O_WRONLY | O_APPEND | O_CREAT, 0o600)
        guard fd >= 0 else { return false }
        defer { Darwin.close(fd) }
        let written = data.withUnsafeBytes { buffer -> Bool in
            guard let base = buffer.baseAddress else { return false }
            var written = 0
            while written < buffer.count {
                let n = Darwin.write(fd, base.advanced(by: written), buffer.count - written)
                if n <= 0 { return false }
                written += n
            }
            return true
        }
        guard written else { return false }
        return Darwin.fsync(fd) == 0
    }

    // MARK: - Retention: rotation, which is also Clear

    /// What a rotation is going to do, written down before it starts.
    ///
    /// This is the whole of the crash story. Rotation replaces the trail and
    /// re-anchors it, and whichever of those two happens first there is an
    /// instant where the file and the end-mark disagree — which the verifier
    /// reads, correctly, as entries missing or a trail replaced. That is an
    /// accusation, and the event was a crash. A marker on disk turns the window
    /// into a resumable state: whatever is found next, the rotation is finished
    /// rather than reported.
    struct RotationIntent: Codable, Sendable {
        var trailId: String
        var reason: HistoryRetention.Reason
        /// What was in the trail when the rotation was decided.
        ///
        /// **Never used for the attestation.** The summary that gets signed is
        /// recomputed from the file at the moment of truncation, because this
        /// file is an ordinary file in a directory the user can write: a planted
        /// marker would otherwise have Proctor sign a discard summary that never
        /// happened, which is a forgery wearing Proctor's own signature and is
        /// strictly worse than the deletion the same attacker could already do.
        /// These fields are kept only so an interrupted rotation can say what it
        /// had been told, clearly marked as unverified.
        var discarded: Int
        var from: Double?
        var to: Double
        var oldTrailId: String?
        var head: String?
    }

    private static var rotatingMarkerURL: URL {
        directory.appendingPathComponent("audit.rotating", isDirectory: false)
    }

    /// Rotate if the trail has outgrown what is kept.
    ///
    /// Called at a run boundary — as a tool call begins — and never between the
    /// steps of one. A rotation in the middle of a batch would discard that
    /// batch's own first half while the run panel was still showing it.
    static func rotateIfNeeded(caps: HistoryRetention.Caps
                                = .read(from: ProcessInfo.processInfo.environment)) {
        guard !isTestProcess || seams.directory != nil else { return }
        let now = clockNow()
        let anchor = seams.anchors.loadAnchor()
        // Not a line count of the file. This runs at the start of every tool call,
        // and reading a ten-thousand-line trail off disk to answer "is it ten
        // thousand lines yet" would put an O(trail) read in front of every
        // snapshot a model takes.
        let entries = state.withLock { countLocked(anchor: anchor) }
        guard case .rotate(let reason) = HistoryRetention.decide(
                entries: entries, oldest: anchor?.startedAt, now: now, caps: caps) else { return }
        // The caps travel with it so the decision can be made again under the
        // lock: this one was taken outside it, and two agents can both reach it.
        rotate(reason: reason, caps: caps)
    }

    /// A person's Clear. The same operation, asked for rather than reached.
    @discardableResult
    static func clear() -> Bool {
        guard !isTestProcess || seams.directory != nil else { return false }
        // Nothing to clear is not a failure, and it must not write a rotation
        // record attesting that nothing was discarded — that would grow the trail
        // every time somebody pressed a button on an empty one.
        guard lineCount() > 0 else { return true }
        return rotate(reason: .person)
    }

    /// Replace the trail in whole and open a new one that attests what went.
    ///
    /// Rotation rather than pruning, because pruning is not representable: the
    /// trail is chained from a genesis over its own prefix, so the first survivor
    /// of a front-truncation still links to a record that is gone and the
    /// verifier is right to call that broken. What stops "the history is gone"
    /// and "the history was never there" being the same claim is the record this
    /// writes, which commits to the discarded trail's identity, its length and
    /// the hash of its final entry.
    @discardableResult
    static func rotate(reason: HistoryRetention.Reason,
                       caps: HistoryRetention.Caps? = nil) -> Bool {
        state.withLock {
            let result: Bool? = withAuditFileLock {
                completeInterruptedRotationLocked()
                // The cap is re-tested **inside** the lock, because the check that
                // led here was made outside it. Two agents can both decide to
                // rotate at once; without this the second one wipes the first
                // one's genesis entry, which is the only signed record of what the
                // first one discarded. A person's Clear carries no caps and is not
                // re-tested: they asked.
                if let caps {
                    let anchor = seams.anchors.loadAnchor()
                    guard case .rotate = HistoryRetention.decide(
                            entries: countLocked(anchor: anchor), oldest: anchor?.startedAt,
                            now: clockNow(), caps: caps) else { return false }
                }
                // Checked before anything is destroyed. A rotation that cannot
                // write its own attestation would leave history deleted and
                // nothing saying so, which is the one outcome worse than keeping
                // it — so a trail that cannot be sealed or signed is left alone.
                guard seams.keys.publicKey() != nil,
                      seams.signer.signingKeyId != nil else {
                    state.fail("Proctor's history could not be cleared, because the trail could not "
                               + "be sealed or signed. Nothing was removed.", dropped: false)
                    return false
                }
                let trail = readTrailLocked()
                let anchor = seams.anchors.loadAnchor()
                let intent = RotationIntent(
                    trailId: UUID().uuidString,
                    reason: reason,
                    discarded: trail.records.count,
                    from: anchor?.startedAt,
                    to: clockNow(),
                    oldTrailId: anchor?.trailId ?? trail.lastTrailId,
                    head: trail.records.last.map(AuditChain.hash(record:)))
                guard let data = try? JSONEncoder().encode(intent),
                      (try? data.write(to: rotatingMarkerURL, options: .atomic)) != nil else {
                    state.fail("Proctor's history could not be cleared, because the change could not "
                               + "be recorded first. Nothing was removed.", dropped: false)
                    return false
                }
                return applyRotationLocked(intent)
            }
            return result ?? false
        }
    }

    /// How many entries the trail holds, without reading it when that can be
    /// avoided.
    ///
    /// The end-mark's count is the cheap answer and is right almost always. It can
    /// lag, though: an append writes the line and then records the new mark, and a
    /// key store that refuses the write leaves the count frozen while the file
    /// grows. A retention cap driven by a frozen count would never fire, and the
    /// trail would grow without limit while reporting that it was bounded — which
    /// is the exact failure this feature exists to prevent, arrived at quietly.
    /// So the larger of the mark and what the last append actually saw wins, and a
    /// process that has not appended yet counts the file once.
    private static func countLocked(anchor: AuditChain.Anchor?) -> Int {
        let seen = state.lastSeenCount
        if let anchor { return max(anchor.count, seen ?? 0) }
        return seen ?? lineCount()
    }

    /// Finish a rotation that was written down. Both locks held.
    ///
    /// Idempotent by construction: it re-anchors, truncates and writes the
    /// attestation from the marker, so running it twice on the same marker leaves
    /// the same state as running it once.
    private static func applyRotationLocked(_ intent: RotationIntent) -> Bool {
        let fm = FileManager.default
        guard let keyId = seams.signer.signingKeyId else { return false }

        // The summary that gets signed is taken from the trail as it stands right
        // now, never from the marker. The marker is an ordinary file in a
        // directory the user can write, so trusting its numbers would let anyone
        // who can drop a file there have Proctor sign a discard that never
        // happened — a forgery carrying Proctor's own signature, which is worse
        // than the deletion that same person could already perform. When the trail
        // is already empty the summary is genuinely unrecoverable, and the record
        // says so rather than repeating a claim it cannot check.
        let trail = readTrailLocked()
        let anchor = seams.anchors.loadAnchor()
        let observed: (count: Int, head: String?, oldTrailId: String?)? =
            trail.records.isEmpty
                ? nil
                : (trail.records.count, trail.records.last.map(AuditChain.hash(record:)),
                   anchor?.trailId ?? trail.lastTrailId)

        // The new end-mark first, then the empty file. Either order leaves one
        // inconsistent instant; the marker above is what makes it resumable, and
        // this order means a crash between the two leaves an empty trail with an
        // empty anchor, which verifies as an empty trail rather than as a
        // truncated one.
        seams.anchors.saveAnchor(AuditChain.Anchor(
            trailId: intent.trailId, count: 0, head: "", keyId: keyId,
            preChainCount: 0, startedAt: intent.to))
        state.noteCount(0)

        let temp = directory.appendingPathComponent("audit.jsonl.rotating", isDirectory: false)
        try? fm.removeItem(at: temp)
        do {
            try Data().write(to: temp, options: .atomic)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temp.path)
            // No backup item is requested, so no readable or sealed copy of the
            // discarded trail survives the swap. That is the same rule PRO-0013's
            // conversion follows and this is where somebody would be tempted to
            // break it.
            _ = try fm.replaceItemAt(url, withItemAt: temp)
        } catch {
            try? fm.removeItem(at: temp)
            state.fail("Proctor's history could not be cleared (\(error.localizedDescription)). "
                       + "Nothing was removed.", dropped: false)
            return false
        }

        // The trail is now empty and anchored empty, so this goes through the
        // ordinary write path and becomes a genuine genesis entry rather than a
        // special case the verifier has to know about.
        let sentence = HistoryRetention.rotationNote(
            reason: intent.reason, discarded: observed?.count, from: intent.from,
            to: intent.to, trailId: observed?.oldTrailId, head: observed?.head)
        let wrote = writeRecordLocked(AuditRecord(
            timestamp: intent.to, tool: "proctor_history", outcome: AuditRecord.Outcome.ok,
            reason: sentence))

        try? fm.removeItem(at: rotatingMarkerURL)
        state.markRotated(discarded: observed?.count ?? 0, reason: intent.reason)
        note(sentence)
        return wrote
    }

    /// A rotation that was written down but never finished is finished now,
    /// rather than left for the verifier to report as tampering.
    ///
    /// Three cases, and the last two are why this is not simply "re-run it":
    ///
    /// - the marker does not decode, so it is removed and ignored. A truncated or
    ///   planted file must not be able to drive a wipe;
    /// - the marker's trail is already the live one and the trail is not empty, so
    ///   the rotation finished and only the marker's deletion was lost. Re-running
    ///   it here would destroy the genesis entry it had just written, and on a
    ///   loop, everything appended since;
    /// - otherwise it was genuinely interrupted, and it completes.
    private static func completeInterruptedRotationLocked() {
        guard FileManager.default.fileExists(atPath: rotatingMarkerURL.path) else { return }
        guard let data = try? Data(contentsOf: rotatingMarkerURL),
              let intent = try? JSONDecoder().decode(RotationIntent.self, from: data) else {
            try? FileManager.default.removeItem(at: rotatingMarkerURL)
            return
        }
        if seams.anchors.loadAnchor()?.trailId == intent.trailId,
           !readTrailLocked().records.isEmpty {
            try? FileManager.default.removeItem(at: rotatingMarkerURL)
            return
        }
        _ = applyRotationLocked(intent)
    }

    // MARK: - One-time in-place conversion

    /// Convert a readable trail in place, once per run, before the first new entry.
    ///
    /// This is destructive on purpose and by the product owner's explicit choice:
    /// when it succeeds, the only readable copy of the history that existed is
    /// gone, and there is no backup, sidecar or export. Leaving a plaintext copy
    /// beside a sealed one would keep exactly the exposure the feature removes.
    ///
    /// It is all-or-nothing. If any part fails, the original is left byte for byte
    /// as it was, the trail is marked unavailable and nothing more is appended for
    /// the rest of the run — which stops both a half-converted file and new entries
    /// landing in a still-readable one.
    private static func migrateIfNeededLocked() {
        guard !state.hasMigrated else { return }
        state.markMigrated()

        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return }
        // A file that exists but cannot be read is not the same as no file: reading
        // past it would append sealed lines to a trail that may still hold readable
        // ones, which is the exposure this conversion exists to end.
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            fail(conversion: "the existing trail could not be read")
            return
        }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        let plaintext = lines.filter { !AuditSeal.isSealed($0) }
        guard !plaintext.isEmpty else { return }

        guard let pub = seams.keys.publicKey() else {
            fail(conversion: "the audit key could not be reached")
            return
        }
        var out: [String] = []
        out.reserveCapacity(lines.count)
        for line in lines {
            if AuditSeal.isSealed(line) {
                out.append(line)
            } else if let sealed = AuditSeal.seal(line: line, to: pub) {
                out.append(sealed)
            } else {
                fail(conversion: "an existing entry could not be sealed")
                return
            }
        }

        let temp = convertingURL
        try? fm.removeItem(at: temp)
        do {
            let body = out.joined(separator: "\n") + "\n"
            try body.write(to: temp, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temp.path)
            // An atomic same-directory replace: either the whole converted trail is
            // in place or the original still is. No backup item is requested, so no
            // readable copy survives the swap.
            _ = try fm.replaceItemAt(url, withItemAt: temp)
        } catch {
            try? fm.removeItem(at: temp)
            fail(conversion: "the converted trail could not replace the original (\(error.localizedDescription))")
            return
        }

        state.markConverted(plaintext.count)
        note("audit trail converted to encrypted-at-rest: \(plaintext.count) "
             + "previously readable \(plaintext.count == 1 ? "entry is" : "entries are") now sealed at "
             + "\(url.path). The readable copy is gone and there is no backup; the trail can only be "
             + "read on this Mac with this login keychain.")
    }

    private static func fail(conversion reason: String) {
        state.fail("The existing readable audit trail could not be converted (\(reason)), so it was "
                   + "left untouched and nothing further is being written to it.",
                   unavailable: true, dropped: false)
        note("audit trail NOT being written: conversion failed because \(reason). The existing trail "
             + "is unchanged at \(url.path).")
    }

    /// The conversion is loud rather than silent — it destroys the only readable
    /// copy of the history, so the run that does it says so.
    private static func note(_ message: String) {
        FileHandle.standardError.write(Data("proctor-agent: \(message)\n".utf8))
    }

    // MARK: - Reading

    /// The most recent `limit` stored lines, oldest first, exactly as they sit on
    /// disk. Reads the whole file, which is acceptable for an operator reading a
    /// tail; the file is a session's worth of actions, not an unbounded log.
    static func tail(_ limit: Int) -> [String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        return Array(lines.suffix(max(0, limit)))
    }

    /// The same tail, opened. Needs the Keychain half, which is the attended
    /// operation. A line sealed to a key this Mac no longer holds comes back
    /// marked rather than throwing, so one unreadable entry costs one entry.
    ///
    /// This is also the only moment the two halves can be checked against each
    /// other, so it is where a `audit.pub` that no longer matches the stored key is
    /// caught: sealing needs only that file, so a replaced one would send every
    /// future entry to a key nobody holds while every write still reported success.
    static func openedTail(_ limit: Int) -> [Entry] {
        let lines = tail(limit)
        guard lines.contains(where: { AuditSeal.isSealed($0) }) else {
            return lines.map { .opened($0) }
        }
        guard let priv = seams.keys.privateKey() else {
            return lines.map { line in
                AuditSeal.isSealed(line)
                    ? .unreadable(kid: keyId(of: line),
                                  reason: "The audit key is not available in this login keychain.")
                    : .opened(line)
            }
        }
        if seams.keys.cachedPublicKeyMatches(priv) == false {
            state.withLock { state.markKeyMismatch() }
        }
        return lines.map { line in
            guard AuditSeal.isSealed(line) else { return .opened(line) }
            if let plain = AuditSeal.open(line, with: priv) { return .opened(plain) }
            return .unreadable(kid: keyId(of: line),
                               reason: "This entry was sealed with a key this Mac no longer holds.")
        }
    }

    private static func keyId(of line: String) -> String? {
        guard let data = line.data(using: .utf8),
              let sealed = try? JSONDecoder().decode(AuditSeal.SealedLine.self, from: data)
        else { return nil }
        return sealed.kid
    }

    /// Where the trail is and how many entries it holds — both answerable without
    /// the key, so an operator who cannot read it can still see it is growing.
    static func lineCount() -> Int {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return 0 }
        return text.split(separator: "\n", omittingEmptySubsequences: true).count
    }

    /// Whether the trail is being written, why not when it is not, how many entries
    /// have been lost this run, which key seals it, whether the sealing key on disk
    /// still matches the one this Mac holds, and whether this run performed the
    /// one-time conversion.
    static func status() -> (writable: Bool, error: String?, dropped: Int,
                             keyId: String?, keyMismatch: Bool, converted: Int?,
                             rotated: (count: Int, reason: HistoryRetention.Reason)?,
                             startedAt: Double?) {
        let started = seams.anchors.loadAnchor()?.startedAt
        return state.withLock {
            let kid: String? = seams.keys.hasCachedPublicKey()
                ? seams.keys.publicKey().map(AuditSeal.keyId(for:))
                : nil
            return (writable: !state.isUnavailable && state.error == nil,
                    error: state.error, dropped: state.droppedCount, keyId: kid,
                    keyMismatch: state.hasKeyMismatch, converted: state.convertedCount,
                    rotated: state.rotated, startedAt: started)
        }
    }

    /// Whether the trail is what Proctor wrote: every entry signed by this Mac,
    /// every entry following the one before it, and as many of them as there
    /// should be.
    ///
    /// This needs the **signing** key, not the key that reads the trail, so a
    /// trail whose contents can no longer be opened can still be proved intact —
    /// checking and reading are different privileges and stay that way. Costs a
    /// signature check per entry, measured at 0.088 ms, so a trail of five
    /// thousand entries verifies in under half a second.
    ///
    /// The expectation comes from the key store rather than from the file. A
    /// forger who supplies both the trail and the key that checks it would
    /// otherwise pass: `keyConfirmed` is false when the key store could not be
    /// reached at all, and a verdict that is merely self-consistent is never
    /// reported as clean.
    static func verify() -> AuditChain.Verdict {
        let signer = seams.signer
        let anchor = seams.anchors.loadAnchor()
        var endsWithNewline = true
        var records: [String] = []
        if let data = try? Data(contentsOf: url), !data.isEmpty,
           let text = String(data: data, encoding: .utf8) {
            endsWithNewline = text.hasSuffix("\n")
            records = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        }
        return AuditChain.verify(
            records: records, endsWithNewline: endsWithNewline,
            expected: AuditChain.Expectation(
                trailId: anchor?.trailId, keyId: signer.signingKeyId,
                keyClass: signer.signingKeyClass, anchor: anchor,
                verify: { signature, material in
                    signer.verifySignature(signature, over: material)
                }))
    }
}
