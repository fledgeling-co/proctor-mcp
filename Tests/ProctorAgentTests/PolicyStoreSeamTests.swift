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

    /// What the operator's file looked like at a moment: whether it is there, its
    /// bytes, and its modification time. Equality across a call is the claim.
    private struct FileWitness: Equatable, CustomStringConvertible {
        let exists: Bool
        let bytes: Data?
        let modified: Date?

        static func read(_ url: URL) -> FileWitness {
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            return FileWitness(exists: FileManager.default.fileExists(atPath: url.path),
                               bytes: try? Data(contentsOf: url),
                               modified: attributes?[.modificationDate] as? Date)
        }

        var description: String {
            guard exists else { return "absent" }
            return "\(bytes?.count ?? -1) bytes, modified \(modified.map(String.init(describing:)) ?? "unknown")"
        }
    }

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
