import Foundation
import Testing
import ProctorCore
@testable import ProctorAgent

// PRO-0089, DEF-042 — the suite must not configure the operator's Mac.
//
// `PolicyStore` was a namespace of statics that derived its own directory from
// the home directory, so `proctor_policy action "configure"` in a test wrote
// `~/Library/Application Support/app.fledgeling.procter/policy/policy.json` —
// the real one, on the machine running the suite, changing what the agent is
// allowed to drive. Nothing announced it and nothing put it back.
//
// The fix is a root the store is told (`PolicyStore(directory:)`, injected into
// a session with `setPolicyStore`) rather than one it assumes, plus the same
// interlock `AuditLog` carries: in a test process `PolicyStore.live` is a
// temporary directory, so a suite that forgets to inject still cannot reach the
// operator's file.
//
// **Not by write-and-restore**, which was the other candidate and is worse: a
// restore that does not run — the process killed, an assertion thrown — leaves
// the policy changed and the failure is invisible.
//
// These cases do not trust the seam. They read the operator's real file before
// and after, and they prove the reading could have reported a change.
@Suite("Policy store seam")
struct PolicyStoreSeamTests {

    // PRO-0098. `FileWitness` moved to Support/FileWitness.swift so REQ-055's own
    // witness can stand on the same armed reader rather than on a second copy of
    // it. Same type, same `==`, plus a sha256 these cases now also compare.

    private func temporaryRoot() -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("pro-0089-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func session() -> Session {
        Session(ax: FakeAX(bundleId: "com.example.target"), capture: FakeCapture())
    }

    // MARK: CASE-0130 — the injected root is where the policy lands

    @Test("a configure through an injected store writes that store's directory")
    func configureWritesTheInjectedRoot() async throws {
        let root = temporaryRoot()
        let session = session()
        await session.setPolicyStore(PolicyStore(directory: root))

        let status = try await session.configurePolicy(allow: ["com.example.one"],
                                                       block: ["com.example.two"],
                                                       sensitive: nil)

        let written = root.appendingPathComponent("policy.json")
        #expect(FileManager.default.fileExists(atPath: written.path))

        // Read back through a second store rather than through the session that
        // wrote it, and compared against what the tool reported rather than against
        // the argument this test passed in: what is asserted is that the file on
        // disk and the answer the caller got describe the same policy.
        let reread = PolicyStore(directory: root).load()
        let reported = status.objectValue
        #expect(reread.allow.sorted().map(JSONValue.string)
                == reported?["allow"]?.arrayValue)
        #expect(reread.block.sorted().map(JSONValue.string)
                == reported?["block"]?.arrayValue)
        #expect(reread.sensitive.isEmpty)
    }

    // MARK: CASE-0131 — the operator's own file is untouched, and the instrument works

    @Test("configuring a policy in a test leaves the operator's real policy file alone")
    func theOperatorsPolicyIsNotTouched() async throws {
        let operatorFile = PolicyStore.operatorDirectory
            .appendingPathComponent("policy.json", isDirectory: false)
        let root = temporaryRoot()
        let injectedFile = root.appendingPathComponent("policy.json", isDirectory: false)

        let operatorBefore = FileWitness.read(operatorFile)
        let injectedBefore = FileWitness.read(injectedFile)

        let session = session()
        await session.setPolicyStore(PolicyStore(directory: root))
        _ = try await session.configurePolicy(allow: ["com.example.written-by-a-test"],
                                              block: nil, sensitive: nil)

        let operatorAfter = FileWitness.read(operatorFile)
        let injectedAfter = FileWitness.read(injectedFile)

        // The claim.
        #expect(operatorBefore == operatorAfter,
                "the suite changed the operator's policy: \(operatorBefore) → \(operatorAfter)")

        // And the arming, without which the line above is a witness that cannot
        // fail. The same reader, over the same call, reports the injected file
        // changing from absent to written — so "unchanged" above is a measurement
        // rather than a reader that reports "unchanged" whatever happens.
        #expect(injectedBefore != injectedAfter)
        #expect(injectedBefore.exists == false)
        #expect(injectedAfter.exists == true)
    }

    // MARK: CASE-0132 — the floor: no injection is still safe

    @Test("a session that injects nothing still cannot reach the operator's policy")
    func theInterlockCatchesAnUninjectedSession() async throws {
        let operatorFile = PolicyStore.operatorDirectory
            .appendingPathComponent("policy.json", isDirectory: false)
        let before = FileWitness.read(operatorFile)

        // Deliberately no `setPolicyStore`. This is the case that used to write the
        // operator's file, and it is the case a future test will forget.
        let session = session()
        _ = try await session.configurePolicy(allow: ["com.example.uninjected"],
                                              block: nil, sensitive: nil)

        #expect(FileWitness.read(operatorFile) == before,
                "an un-injected session reached the operator's policy")

        // It wrote somewhere — just not there. Asked of the session's own store
        // rather than of `PolicyStore.live`, because in a test process every read of
        // `live` is a fresh directory and the two would not be the same one.
        let fallback = await session.policyStore.directory
        #expect(FileManager.default.fileExists(
            atPath: fallback.appendingPathComponent("policy.json").path))
        #expect(!fallback.path.hasPrefix(PolicyStore.operatorDirectory.path))
        #expect(fallback.path.hasPrefix(PolicyStore.testFallbackRoot.path))
    }

    @Test("two un-injected sessions do not share one policy file")
    func theFallbackIsNotSharedBetweenSessions() async throws {
        // The failure this shape exists to prevent, and it is not hypothetical: a
        // single shared fallback produced 67 issues across 11 suites, every one a
        // `policyDenied` for an app the failing test had never named. The pre-fix
        // code shared a file the same way — the operator's own — so what the suite
        // did depended on what the person running it had configured.
        let configuring = session()
        _ = try await configuring.configurePolicy(allow: ["com.example.only-here"],
                                                  block: nil, sensitive: nil)

        let later = session()
        await later.loadPolicyIfNeeded()
        #expect(await later.policy.isEmpty)
        #expect(await later.policyStore.directory != configuring.policyStore.directory)
    }

    // MARK: CASE-0133 — the interlock is armed, and it is watching the right file

    @Test("the interlock is active in this process and the operator path is the real one")
    func theInterlockIsArmed() {
        // Without this, CASE-0132 could pass because the interlock never engaged and
        // the operator simply has no policy file — a zero from an instrument that
        // could not have reported anything else.
        #expect(AuditLog.isTestProcess)
        #expect(!PolicyStore.live.directory.path.hasPrefix(PolicyStore.operatorDirectory.path))

        // And the file being watched is the agent's own, derived from the same
        // identifier every other store in the tree derives from. `procter` is not a
        // typo; `SwitchStore.swift` records why.
        #expect(PolicyStore.operatorDirectory.path.contains(Wire.bundleIdentifier))
        #expect(PolicyStore.operatorDirectory.lastPathComponent == "policy")
        #expect(PolicyStore.operatorDirectory.path.hasPrefix(
            FileManager.default.homeDirectoryForCurrentUser.path))
    }

    // MARK: CASE-0134 — the contract the statics used to carry, now on the instance

    @Test("an absent policy loads empty, and a saved one loads back")
    func theStoreRoundTrips() throws {
        let store = PolicyStore(directory: temporaryRoot())
        #expect(store.load().isEmpty)

        try store.save(AppPolicy(allow: ["a"], block: ["b"], sensitive: ["c"]))
        let loaded = PolicyStore(directory: store.directory).load()
        #expect(loaded.allow == ["a"])
        #expect(loaded.block == ["b"])
        #expect(loaded.sensitive == ["c"])

        // Two stores with different roots are two policies, which is the whole
        // point of the root being told rather than assumed.
        #expect(PolicyStore(directory: temporaryRoot()).load().isEmpty)
    }
}

// PRO-0095, DEF-068 — the policy file's mode, read off disk rather than trusted.
//
// `PolicyStore.save` created its directory `0o700` and then wrote the file with
// `Data.write(to:options:.atomic)`, which takes no mode and so takes the umask
// default: measured `-rw-r--r-- policy.json` inside `drwx------ policy/`, while
// `AuditLog` in the same file opens `audit.jsonl`, `audit.lock` and `audit.pub`
// explicitly `0o600`.
//
// **Not overstated.** The `0700` directory carries the protection today, so this
// was an inconsistency with the neighbouring code rather than an exposure. It
// becomes one when the file is copied, backed up, or the directory's mode is
// loosened, and the file records which applications an agent may drive.
//
// Every case here reads the mode back with `attributesOfItem`. Asserting the
// options passed to the write would be asserting the call rather than the file,
// and the defect was precisely a call whose options said nothing about the mode.
// `.serialized` because CASE-0192 changes the process umask, which is
// process-wide: run in parallel with CASE-0190 it decides which wide mode the
// pre-fix code produces there. Measured in the arming run below — CASE-0190 read
// 0o666 rather than the 0o644 its own umask would give. It changes no verdict
// under the fix, where every mode is explicit, but it makes an arming run's
// numbers describe the wrong case. The window against the rest of the suite is
// one `open` inside one test, and nothing outside this file asserts on a mode.
@Suite("Policy file mode", .serialized)
struct PolicyFileModeTests {

    /// A counter the concurrent case can bump from several tasks at once.
    private final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 0
        func bump() -> Int { lock.lock(); defer { lock.unlock() }; value += 1; return value }
        var count: Int { lock.lock(); defer { lock.unlock() }; return value }
    }

    private func temporaryRoot() -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("pro-0095-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    /// The permission bits on disk, or nil when the file is not there. `stat`
    /// through Foundation; the number is the low twelve bits, so a `0644` reads
    /// 420 and a `0600` reads 384.
    private func mode(_ url: URL) -> Int? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        else { return nil }
        return (attributes[.posixPermissions] as? NSNumber)?.intValue
    }

    // MARK: CASE-0274, CASE-0275 — the WRITE watched, rather than its result stated
    //
    // PRO-0098, DEF-111. Every case below CASE-0190 stats the file the save left
    // behind. That is the outcome of the write; the effect is the write. The
    // difference is not pedantry — a `save` that created three files and left two
    // of them at 0644 passes every stat below, because a stat only ever looks at
    // the one path it was handed.
    //
    // So: a recorder that is not `PolicyStore`, over the directory rather than the
    // file, reporting what the call created and the mode of each entry read back
    // off disk through a fresh `attributesOfItem`.

    @Test("the write is watched: every path it creates is recorded, and each is 0600")
    func theWriteItselfIsWitnessed() throws {
        let directory = temporaryRoot().appendingPathComponent("policy", isDirectory: true)
        let store = PolicyStore(directory: directory)

        let before = DirectoryWitness.read(directory)
        #expect(before.files.isEmpty, "the fixture directory was not empty")

        try store.save(AppPolicy(allow: ["com.example.a"], block: ["com.example.b"], sensitive: []))

        let after = DirectoryWitness.read(directory)
        let created = DirectoryWitness.changed(from: before, to: after)

        // The witness count: what the effect actually produced, counted rather
        // than assumed. Non-zero is the whole point — a recorder that saw nothing
        // is the condition this rung exists to catch, not the proof.
        #expect(created.count >= 1, "the recorder saw no write at all")
        #expect(created == ["policy.json"],
                "the save produced \(created), not policy.json alone")

        // EVERY path it produced, not the one path a stat was pointed at.
        for path in created {
            let url = directory.appendingPathComponent(path)
            #expect(mode(url) == 0o600,
                    "\(path) is \(mode(url).map { String($0, radix: 8) } ?? "absent"), not 600")
        }
        #expect(after.files["policy.json"]?.digest != nil)
    }

    @Test("a second save is watched too: it rewrites the one file and leaves no other behind")
    func theReplaceIsWitnessed() throws {
        // The create path and the replace path are different code — `Darwin.open`
        // with O_EXCL, then `replaceItemAt`. A recorder over the directory sees
        // both, including a temporary that outlived the call, which is the failure
        // a stat of `policy.json` cannot report.
        let directory = temporaryRoot().appendingPathComponent("policy", isDirectory: true)
        let store = PolicyStore(directory: directory)
        try store.save(AppPolicy(allow: ["com.example.first"], block: [], sensitive: []))

        let before = DirectoryWitness.read(directory)
        try store.save(AppPolicy(allow: ["com.example.second"], block: [], sensitive: []))
        let after = DirectoryWitness.read(directory)

        let touched = DirectoryWitness.changed(from: before, to: after)
        #expect(touched.count >= 1, "the recorder saw no second write")
        #expect(touched == ["policy.json"],
                "the replace left \(touched) rather than rewriting one file")
        #expect(after.files.count == 1, "a temporary outlived the replace: \(after.files.keys.sorted())")
        #expect(before.files["policy.json"]?.digest != after.files["policy.json"]?.digest)
        #expect(mode(store.url) == 0o600)
    }

    // MARK: CASE-0190 — a fresh save lands 0600 inside a 0700 directory

    @Test("a policy file created by save is 0600, and its directory is still 0700")
    func aFreshSaveIs0600() throws {
        let store = PolicyStore(directory: temporaryRoot()
            .appendingPathComponent("policy", isDirectory: true))
        try store.save(AppPolicy(allow: ["com.example.a"], block: [], sensitive: []))

        #expect(mode(store.url) == 0o600,
                "policy.json is \(mode(store.url).map { String($0, radix: 8) } ?? "absent"), not 600")
        #expect(mode(store.directory) == 0o700,
                "the directory is \(mode(store.directory).map { String($0, radix: 8) } ?? "absent"), not 700")

        // The temporary the write goes through does not survive it. A leftover
        // would be a second copy of the same app list sitting beside the file,
        // and the temporaries are uniquely named, so this asks the directory what
        // is in it rather than probing one expected name.
        let left = (try? FileManager.default.contentsOfDirectory(atPath: store.directory.path)) ?? []
        #expect(left == ["policy.json"], "the directory holds \(left)")
    }

    // MARK: CASE-0191 — an operator's existing 0644 file is narrowed by the next save

    @Test("a policy file already on disk at 0644 is 0600 after the next save")
    func anExistingWideFileIsNarrowed() throws {
        // The upgrade half of DEF-068, and the half that is easy to ship broken:
        // `replaceItemAt` carries the original item's metadata across unless it is
        // told not to, so without `.usingNewMetadataOnly` an operator whose file
        // was created by an earlier build keeps `0644` through every future save.
        let store = PolicyStore(directory: temporaryRoot()
            .appendingPathComponent("policy", isDirectory: true))
        try FileManager.default.createDirectory(at: store.directory,
                                                withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        // The pre-fix write, put back by hand: this is the file an operator who ran
        // an earlier build actually has.
        try Data("{}".utf8).write(to: store.url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o644],
                                              ofItemAtPath: store.url.path)
        #expect(mode(store.url) == 0o644, "the fixture did not start wide, so this proves nothing")

        try store.save(AppPolicy(allow: ["com.example.b"], block: [], sensitive: []))

        #expect(mode(store.url) == 0o600,
                "policy.json stayed \(mode(store.url).map { String($0, radix: 8) } ?? "absent") through a save")
        #expect(PolicyStore(directory: store.directory).load().allow == ["com.example.b"],
                "the narrowing replaced the file without carrying the new contents")
    }

    // MARK: CASE-0192 — the mode is set rather than inherited

    @Test("a save under a permissive umask still lands 0600")
    func theModeIsSetRatherThanInherited() throws {
        // The case that discriminates. `Data.write` takes the umask default, so
        // under `umask(0)` the pre-fix code produces `0666` and any fix that only
        // narrows the *usual* default would still pass CASE-0190 on this machine.
        //
        // `umask` is process-wide and this suite runs in parallel with others, so
        // it is restored immediately and nothing else is asserted while it is
        // changed. The window is one `open`.
        let store = PolicyStore(directory: temporaryRoot()
            .appendingPathComponent("policy", isDirectory: true))
        let previous = umask(0)
        do {
            try store.save(AppPolicy(allow: ["com.example.c"], block: [], sensitive: []))
        } catch {
            umask(previous)
            throw error
        }
        umask(previous)

        #expect(mode(store.url) == 0o600,
                "under umask(0) policy.json is \(mode(store.url).map { String($0, radix: 8) } ?? "absent") — the mode is coming from the umask, not from the write")
    }

    // MARK: CASE-0193 — the narrowed write still round-trips

    @Test("a policy saved through the explicit open loads back equal")
    func theNarrowedWriteStillRoundTrips() throws {
        // The mode is worth nothing if the file stopped being a policy. Three
        // saves, because the second and third take the replace path over an
        // existing file rather than the create path.
        let store = PolicyStore(directory: temporaryRoot()
            .appendingPathComponent("policy", isDirectory: true))
        for (index, allow) in [["a"], ["a", "b"], ["c"]].enumerated() {
            try store.save(AppPolicy(allow: Set(allow), block: ["blocked"], sensitive: ["s"]))
            let loaded = PolicyStore(directory: store.directory).load()
            #expect(loaded.allow == Set(allow), "save \(index + 1) did not round-trip")
            #expect(loaded.block == ["blocked"])
            #expect(loaded.sensitive == ["s"])
            #expect(mode(store.url) == 0o600, "save \(index + 1) left the file wider than 600")
        }
    }

    // MARK: CASE-0198 — the narrowing did not start refusing concurrent saves

    @Test("saves arriving together all complete, and the file is still 0600")
    func concurrentSavesAllComplete() async throws {
        // A regression this item nearly shipped. Data.write(options: .atomic) uses
        // a temporary of its own per call, so two sessions saving at once both
        // succeeded and the last one won. An explicit open with O_EXCL on one
        // fixed temporary name turns the same race into a thrown error, and two
        // sessions in one agent share operatorDirectory, so it is reachable.
        //
        // The temporaries are uniquely named for that reason, with a sweep of
        // anything an earlier process left behind. This case is what says so.
        let store = PolicyStore(directory: temporaryRoot()
            .appendingPathComponent("policy", isDirectory: true))
        let failures = Counter()
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<12 {
                group.addTask {
                    do { try store.save(AppPolicy(allow: ["com.example.\(i)"], block: [], sensitive: [])) }
                    catch { _ = failures.bump() }
                }
            }
        }
        #expect(failures.count == 0, "\(failures.count) of 12 concurrent saves threw")
        #expect(mode(store.url) == 0o600)
        // Whichever won, the file is a whole policy rather than a torn one, and
        // no temporary outlived the run.
        let loaded = PolicyStore(directory: store.directory).load()
        #expect(loaded.allow.count == 1, "the surviving file holds \(loaded.allow)")
        let left = (try? FileManager.default.contentsOfDirectory(atPath: store.directory.path)) ?? []
        #expect(left == ["policy.json"], "the directory holds \(left)")
    }
}
