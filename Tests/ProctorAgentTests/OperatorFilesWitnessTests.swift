import Foundation
import Testing
import ProctorCore
@testable import ProctorAgent

// PRO-0098, DEF-110 — REQ-055 at the rung it declares.
//
// REQ-055 says "running the test suite does not read or write any state belonging
// to the operator of the machine it runs on". It declares a `filesystem-write`
// effect, records `observed`, names no provider, and every case backing it sits at
// `outcome`. So the campaign's external-effect pass has named it since the census
// closed, and correctly: nothing here had watched a filesystem.
//
// THE CLAIM IS A NEGATIVE, AND THAT IS THE WHOLE DIFFICULTY. A witness reporting
// zero writes is indistinguishable from a witness that cannot report a write at
// all — a reader pointed at the wrong path, a sweep that skipped the file, a
// comparison that could not have come out unequal. Six dead predicates have been
// found in this campaign and every one was found by arming rather than by reading.
//
// So every case below has two arms over ONE call:
//
//   the claim   — the operator's own root, swept before and after, zero changed;
//   the control — a root the same call does write, swept by the SAME instrument
//                 over the SAME call, N changed with N ≥ 1.
//
// The control's N is the number these cases record as their witness count. That
// is stated plainly rather than dressed up: the count belongs to the arming arm,
// because the claim's honest count is zero and a zero from an unarmed instrument
// is not evidence of anything.
//
// PRO-0089's `FileWitness` is the reader, reused rather than rebuilt (it is now in
// Support/FileWitness.swift), because it is already the armed one.
//
// WHAT THIS CERTIFIES, AND WHAT IT DOES NOT. REQ-055 was written as "does not read
// or write any state belonging to the operator", and that sentence is wider than
// anything on this machine can measure. It has been narrowed to what is watched
// here, and the remainder recorded as DEF-141 rather than left standing:
//
//   watched   — WRITES, under the operator's Proctor application-support root
//               (`~/Library/Application Support/app.fledgeling.procter`), swept
//               whole and reported as `changed / len(files)`, across a policy
//               configure with a caller-supplied root and with none.
//   not       — READS. `atime` is not compared, and this reader could not compare
//               it honestly if it wanted to: it opens every file to digest it, so
//               the instrument perturbs the one attribute a read would show.
//   not       — the WHOLE suite. Two calls are watched, not 1,992 tests; a sweep
//               either side of the whole run would be measuring the machine.
//   not       — the operator's Proctor state OUTSIDE that root:
//               `~/Library/Logs/Proctor/agent.log`, the LaunchAgent plist at
//               `~/Library/LaunchAgents/app.fledgeling.procter.agent.plist`, and
//               the `UserDefaults` domain `ProctorUIApp` reads. The log is
//               appended to by the installed agent while the suite runs, so a
//               sweep of it reports that agent rather than this suite.
//
// The narrowing found something within one run. The sweep went red on a real
// write — `captures/win-1-zoom-1787361639249.full.png` — which the suite had been
// making since PRO-0089 and catching only when it fell between two readings.
// DEF-142, and CASE-0285 below is the deterministic guard that replaced the race.
//
// AND IT FOUND A SECOND ONE, on the next clean run after the merge: two of the
// operator's own recorded flows, `login-flow.json` and `sweep.json`, rewritten by
// `AcceptanceE2ETests`, `NativePlaneLaneTests` and `StabilityPageContentTests`
// through a `FlowStore.directory` that had no injection seam either. DEF-164, and
// CASE-0320 is its deterministic guard. Three paths wrote the operator's state
// without being told where — the policy, the captures, the flows — and each was
// found by this witness rather than by reading, which is the argument for the
// witness and against trusting the sweep's zero on its own.

@Suite("PRO-0098 · the suite writes nothing of the operator's")
struct OperatorFilesWitnessTests {

    /// Everything under the agent's own application-support root, which is where
    /// all of the operator's Proctor state lives: `policy/`, `audit/`, `flows/`,
    /// `settings/`, `captures/`, `maestro/`. Swept whole rather than file by file,
    /// because REQ-055's claim is about the operator's state and not about
    /// `policy.json` — a suite that stopped touching the policy and started
    /// touching the flow store would satisfy a one-file reader completely.
    private var operatorRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/\(Wire.bundleIdentifier)",
                                    isDirectory: true)
    }

    private func temporaryRoot() -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("pro-0098-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func session() -> Session {
        Session(ax: FakeAX(bundleId: "com.example.target"), capture: FakeCapture())
    }

    // MARK: CASE-0270 — the sweep over a policy configure, both arms

    @Test("a policy configure changes nothing under the operator's root, and the sweep can tell")
    func aConfigureLeavesTheOperatorsRootAlone() async throws {
        let injected = temporaryRoot()

        let operatorBefore = DirectoryWitness.read(operatorRoot)
        let injectedBefore = DirectoryWitness.read(injected)

        let session = session()
        await session.setPolicyStore(PolicyStore(directory: injected))
        _ = try await session.configurePolicy(allow: ["com.example.written-by-a-test"],
                                              block: ["com.example.blocked-by-a-test"],
                                              sensitive: nil)

        let operatorAfter = DirectoryWitness.read(operatorRoot)
        let injectedAfter = DirectoryWitness.read(injected)

        // THE DENOMINATOR, BEFORE THE CLAIM. A zero is only worth the size of the
        // population it is a zero out of, and a sweep of an absent or empty root
        // reports zero for ever. So the population is asserted and then reported
        // beside the count, as `changed / len(files)`.
        #expect(operatorBefore.rootExists,
                "the operator's root is not there, so its zero is structural rather than measured")
        #expect(operatorBefore.files.count >= 1,
                "the sweep found 0 files under the operator's root: a zero out of nothing")

        // THE CLAIM.
        let touched = DirectoryWitness.changed(from: operatorBefore, to: operatorAfter)
        #expect(touched.isEmpty,
                "the suite changed \(touched.count) of the \(operatorBefore.files.count) file(s) swept under the operator's root: \(touched)")

        // THE CONTROL ARM. Same reader, same call, a root that IS written. Without
        // this the assertion above is a reader that reports "unchanged" whatever
        // happens — including when it is looking at a directory that does not
        // exist, which is the failure mode a negative claim invites.
        let wrote = DirectoryWitness.changed(from: injectedBefore, to: injectedAfter)
        #expect(wrote.count >= 1,
                "the control arm saw no write at all, so the zero above measures nothing")
        #expect(wrote.contains("policy.json"))
        #expect(injectedBefore.files["policy.json"] == nil)
        #expect(injectedAfter.files["policy.json"]?.exists == true)
        // The digest the lift added: a rewrite landing the same byte count within
        // one timestamp tick is a change size and mtime agree about.
        #expect(injectedAfter.files["policy.json"]?.digest != nil)
    }

    // MARK: CASE-0271 — the same, for a session that injected nothing

    @Test("an un-injected session writes somewhere, and that somewhere is not the operator's")
    func anUninjectedSessionIsAlsoWatched() async throws {
        let operatorBefore = DirectoryWitness.read(operatorRoot)

        // Deliberately no `setPolicyStore` — the case that used to write the
        // operator's file, and the case a future test will forget.
        let session = session()
        _ = try await session.configurePolicy(allow: ["com.example.uninjected"],
                                              block: nil, sensitive: nil)

        let operatorAfter = DirectoryWitness.read(operatorRoot)
        #expect(operatorBefore.rootExists,
                "the operator's root is not there, so its zero is structural rather than measured")
        #expect(operatorBefore.files.count >= 1,
                "the sweep found 0 files under the operator's root: a zero out of nothing")
        let touched = DirectoryWitness.changed(from: operatorBefore, to: operatorAfter)
        #expect(touched.isEmpty,
                "an un-injected session reached \(touched.count) of the \(operatorBefore.files.count) file(s) swept under the operator's root: \(touched)")

        // The control arm, and here it also proves the interlock is doing something
        // rather than the configure being a no-op: the fallback root the interlock
        // redirects to holds the write.
        let fallback = DirectoryWitness.read(PolicyStore.testFallbackRoot)
        let written = fallback.files.keys.filter { $0.hasSuffix("policy.json") }
        #expect(written.count >= 1,
                "nothing was written anywhere, so the operator's zero is a no-op rather than an interlock")
        #expect(!PolicyStore.testFallbackRoot.path.hasPrefix(operatorRoot.path))
    }

    // MARK: CASE-0272 — the instrument is pointed at the operator's real paths

    @Test("the swept root is the operator's own, and the reader reports a write into it")
    func theSweepIsPointedAtTheRealThing() throws {
        // A sweep of a path nobody uses reports zero for ever. This case fixes the
        // path: it is derived the same way the product derives it, from
        // `Wire.bundleIdentifier` under this user's home, and it is the parent of
        // the two directories the product's own code names.
        let home = FileManager.default.homeDirectoryForCurrentUser
        #expect(operatorRoot.path.hasPrefix(home.path))
        #expect(operatorRoot.lastPathComponent == Wire.bundleIdentifier)
        #expect(PolicyStore.operatorDirectory.path.hasPrefix(operatorRoot.path + "/"))
        #expect(SwitchStore.url(home: home).path.hasPrefix(operatorRoot.path + "/"))

        // AND THE READER CAN SEE INTO IT. This is the arming for the path rather
        // than for the call: a decoy laid out exactly like the operator's root,
        // swept by the same code, reports the file appearing. If the sweep could
        // not descend into subdirectories — which is precisely how a recursive
        // reader fails silently — this would report zero and the two cases above
        // would be vacuous.
        let decoy = temporaryRoot()
        let nested = decoy.appendingPathComponent("policy", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let before = DirectoryWitness.read(decoy)
        try Data("{\"allow\":[]}".utf8).write(to: nested.appendingPathComponent("policy.json"))
        let after = DirectoryWitness.read(decoy)
        let changed = DirectoryWitness.changed(from: before, to: after)
        #expect(changed == ["policy/policy.json"],
                "the sweep did not see a file written one directory down")

        // And it reports a rewrite in place, not only a creation — the shape a
        // suite that overwrote the operator's policy would leave.
        let rewritten = DirectoryWitness.read(decoy)
        try Data("{\"allow\":[\"com.example.changed\"]}".utf8)
            .write(to: nested.appendingPathComponent("policy.json"))
        #expect(DirectoryWitness.changed(from: rewritten,
                                         to: DirectoryWitness.read(decoy)) == ["policy/policy.json"])
        try? FileManager.default.removeItem(at: decoy)
    }

    // MARK: CASE-0285 — the other path that writes without being told where

    @Test("an un-pathed capture lands outside the operator's root, like an un-injected policy store")
    func anUnpathedCaptureIsRedirectedToo() throws {
        // FOUND BY THE WITNESS ABOVE, not by reading. CASE-0270 and CASE-0271 went
        // red on `touched → ["captures/win-1-zoom-1787361639249.full.png"]`:
        // AcceptanceE2ETests' Journey 5 calls session.zoom(path: nil) twice, and
        // Session.defaultZoomPath hard-coded the operator's captures directory, so
        // every run wrote four PNGs there. The sweep only caught it when a write
        // happened to land between its two readings, which is why REQ-055 read
        // green for as long as it did.
        //
        // The path assertion is here as well as the sweep because the sweep is a
        // race and this is not: it holds on every run whether or not a zoom happens
        // to overlap the window.
        let directory = CaptureEngineImpl.defaultCaptureDirectory
        #expect(!directory.hasPrefix(operatorRoot.path),
                "an un-pathed capture lands in the operator's own captures: \(directory)")
        #expect(directory.hasPrefix(CaptureEngineImpl.testFallbackCaptureRoot.path))

        // And the zoom path, which is the caller that actually did it.
        let handle = WindowHandle(id: "win-1", app: "app:1:1", title: nil,
                                  frame: Rect(x: 0, y: 0, w: 10, h: 10), isMain: true,
                                  isMinimized: false, isOnActiveSpace: true, cgWindowID: nil)
        let zoom = Session.defaultZoomPath(for: handle)
        #expect(!zoom.hasPrefix(operatorRoot.path),
                "an un-pathed zoom crop lands in the operator's own captures: \(zoom)")
        #expect(zoom.hasPrefix(CaptureEngineImpl.testFallbackCaptureRoot.path))

        // The engine still honours a path it is given — the interlock is a floor
        // under an absent path, not an override of a present one.
        let named = temporaryRoot().appendingPathComponent("named").path
        #expect(CaptureEngineImpl(captureDirectory: named).captureDirectory == named)
    }

    // MARK: CASE-0320 — the third path that writes without being told where

    @Test("a recorded flow lands outside the operator's root, like an un-pathed capture")
    func aRecordedFlowIsRedirectedToo() throws {
        // FOUND BY THE WITNESS ABOVE, the same way CASE-0285 was, and one wave
        // later. A clean `./scripts/test.sh` on the merged tree rewrote
        // `login-flow.json` and `sweep.json` under the operator's own flows
        // directory: AcceptanceE2ETests records a flow called `login-flow`,
        // NativePlaneLaneTests and StabilityPageContentTests record one called
        // `sweep`, and `FlowStore.directory` was a static computing the operator's
        // path with no seam to inject. So an operator with a flow of either name
        // had it overwritten by running the tests. DEF-164.
        //
        // Asserted on the resolved path rather than on the sweep, for the reason
        // CASE-0285 gives: CASE-0270's sweep catches this only when a write happens
        // to fall between its two readings, and on the run that motivated this case
        // it did not — the write landed at 11:57:28 and the sweep read either side
        // of it. A path assertion holds on every run.
        #expect(!FlowStore.directory.path.hasPrefix(FlowStore.operatorDirectory.path),
                "a recorded flow lands in the operator's own flows: \(FlowStore.directory.path)")
        #expect(FlowStore.directory.path.hasPrefix(FlowStore.testFallbackFlowRoot.path))
        #expect(!FlowStore.directory.path.hasPrefix(operatorRoot.path),
                "a recorded flow lands under the operator's root: \(FlowStore.directory.path)")

        // The operator's own path stays truthful, so this case can name what it is
        // asserting the absence of rather than comparing two redirected paths and
        // agreeing with itself.
        #expect(FlowStore.operatorDirectory.path.hasPrefix(operatorRoot.path + "/"))
        #expect(FlowStore.operatorDirectory.lastPathComponent == "flows")

        // And the write itself, not only the directory: the name a suite actually
        // records resolves outside the operator's root too, which is the assertion
        // that would have caught `login-flow.json` the moment it was written.
        let recorded = try FlowStore.url(for: "login-flow")
        #expect(!recorded.path.hasPrefix(operatorRoot.path),
                "a flow named login-flow is written into the operator's root: \(recorded.path)")
        #expect(recorded.lastPathComponent == "login-flow.json")
    }

    // MARK: CASE-0273 — the digest catches what size and mtime miss

    @Test("a rewrite of the same length is reported as a change")
    func theDigestClosesTheSameLengthHole() throws {
        // PRO-0089's reader compared existence, bytes and mtime. Bytes catches this
        // one, but the failure it guards against is real and cheap to keep out: a
        // reader that compared only size and mtime — the two attributes a stat
        // gives you — reports "unchanged" across an in-place overwrite of equal
        // length inside one filesystem timestamp tick.
        let root = temporaryRoot()
        let file = root.appendingPathComponent("settings.json")
        try Data("{\"a\":\"1\"}".utf8).write(to: file)
        let before = FileWitness.read(file)

        try Data("{\"a\":\"2\"}".utf8).write(to: file)
        let after = FileWitness.read(file)

        #expect(before.bytes?.count == after.bytes?.count, "the fixture is not equal-length")
        #expect(before.digest != after.digest)
        #expect(before != after)
        try? FileManager.default.removeItem(at: root)
    }
}
