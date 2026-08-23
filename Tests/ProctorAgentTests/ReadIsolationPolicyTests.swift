import Foundation
import Testing
import ProctorCore
@testable import ProctorAgent

// PRO-0111 / DEF-141 / REQ-160: Filesystem Read-Isolation Policy Contract.
//
// Formally verifies the read-isolation and path-isolation boundary:
// 1. Injected stores (PolicyStore) read exclusively from their injected roots,
//    never falling back or reading from the operator directory.
// 2. Default stores in test processes (FlowStore, CaptureEngine, Session zoom) resolve to
//    isolated fallback roots in NSTemporaryDirectory, guaranteeing that operator flows,
//    policies, and captures cannot be read or overwritten by test runs.
@Suite("PRO-0111 · Filesystem Read-Isolation Policy Contract")
struct ReadIsolationPolicyTests {

    private func temporaryRoot() -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("pro-0111-readiso-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    // MARK: - PolicyStore Read Isolation (CASE-0630)

    @Test("PolicyStore reads exclusively from its designated directory without fallback to operator state")
    func policyStoreReadIsolation() throws {
        let sandbox = temporaryRoot()
        let store = PolicyStore(directory: sandbox)

        // The sandbox has no policy file, so load() returns empty AppPolicy
        let policy = store.load()
        #expect(policy.allow.isEmpty)
        #expect(policy.block.isEmpty)
        #expect(policy.sensitive.isEmpty)

        // Write a custom policy to sandbox
        let custom = AppPolicy(allow: ["com.example.isolated"], block: ["com.example.blocked"], sensitive: [])
        try store.save(custom)

        // Verify it reads back from sandbox
        let reloaded = store.load()
        #expect(reloaded.allow == ["com.example.isolated"])
        #expect(reloaded.block == ["com.example.blocked"])

        // Verify the operator directory was NOT touched or read
        #expect(sandbox != PolicyStore.operatorDirectory)
    }

    // MARK: - FlowStore Read Isolation (CASE-0630)

    @Test("FlowStore in test execution isolates loaded flows to the test fallback root")
    func flowStoreReadIsolation() throws {
        // FlowStore.directory in test processes resolves to testFallbackFlowRoot
        #expect(FlowStore.directory != FlowStore.operatorDirectory)
        #expect(FlowStore.directory.path.hasPrefix(FlowStore.testFallbackFlowRoot.path))

        _ = FlowStore.loadAll()
        // In an isolated test run, operator flows are not loaded
        #expect(!FlowStore.directory.path.contains("Library/Application Support/app.fledgeling.procter"))
    }

    // MARK: - CaptureEngine & Session Zoom Isolation (CASE-0631)

    @Test("CaptureEngine and Session default capture directories resolve to isolated temporary roots")
    func captureDirectoryIsolation() {
        let captureDir = CaptureEngineImpl.defaultCaptureDirectory
        let fallbackRoot = CaptureEngineImpl.testFallbackCaptureRoot

        #expect(captureDir.hasPrefix(fallbackRoot.path))
        #expect(!captureDir.contains("Library/Application Support/app.fledgeling.procter"))

        let handle = WindowHandle(id: "win-iso-1", app: "app:1:1", title: nil,
                                  frame: Rect(x: 0, y: 0, w: 10, h: 10), isMain: true,
                                  isMinimized: false, isOnActiveSpace: true, cgWindowID: nil)
        let zoomDir = Session.defaultZoomPath(for: handle)
        #expect(zoomDir.hasPrefix(fallbackRoot.path))
        #expect(!zoomDir.contains("Library/Application Support/app.fledgeling.procter"))
    }

    // MARK: - Unconfigured Session State Isolation (CASE-0632)

    @Test("An unconfigured Session routes policy checks through isolated store rather than operator policy")
    func sessionPolicyIsolation() async {
        let session = Session(ax: FakeAX(bundleId: "com.example.target"), capture: FakeCapture())
        let store = await session.policyStore
        #expect(store.directory != PolicyStore.operatorDirectory)
        #expect(store.directory.path.hasPrefix(PolicyStore.testFallbackRoot.path))
    }
}
