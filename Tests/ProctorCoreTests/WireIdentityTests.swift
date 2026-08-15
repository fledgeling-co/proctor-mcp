import Foundation
import Testing
import ProctorCore

// PRO-0040 — the agent has an identity of its own, and it is not its signature.
//
// The defect these pin: the agent is a second Mach-O inside Proctor.app, so it
// used to inherit the bundle's Info.plist. LaunchServices recorded it as a running
// instance of the application, `open -a Proctor` activated a process with no
// window and exited 0, and Proctor could not be opened by any normal means while
// its own agent was running — which is nearly always. A person double-clicking it
// in /Applications got nothing, with no error to read.
//
// Two things now have to stay true, and they pull in opposite directions:
//
//   1. The agent's LaunchServices identity must DIFFER from the app's, or the
//      defect returns.
//   2. The agent's SIGNING identity must stay the SAME as the app's, or the TCC
//      grants stop matching the recorded designated requirement and a person is
//      asked for Accessibility and Screen Recording again. Screen Recording cannot
//      be granted silently on any macOS version, so that is a real cost.
//
// What `swift test` can reach is the first: that the shipped plist and the
// constants the code reasons with agree, and that they are distinct. The second is
// a property of the built binary, so it is gated in `scripts/build-app.sh`, which
// is the one step the local installer and the release workflow both go through,
// and measured end to end on a real install. Stated here rather than implied,
// because a green suite must not read as proof of the half it cannot see.

@Suite("Proctor's own identity")
struct WireIdentityTests {

    /// The repository root, from this file's location.
    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // ProctorCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
    }

    private static func plist(_ relativePath: String) throws -> [String: Any] {
        let url = repoRoot.appendingPathComponent(relativePath)
        let data = try Data(contentsOf: url)
        let parsed = try PropertyListSerialization.propertyList(
            from: data, options: [], format: nil)
        return try #require(parsed as? [String: Any],
                            "\(relativePath) should parse as a dictionary")
    }

    @Test("the agent's identity is the app's, plus a suffix that says what it is")
    func agentIdentityIsDerived() {
        #expect(Wire.agentBundleIdentifier == "app.fledgeling.procter.agent")
        #expect(Wire.agentBundleIdentifier.hasPrefix(Wire.bundleIdentifier))
        #expect(Wire.agentBundleIdentifier != Wire.bundleIdentifier)
    }

    @Test("launchd and LaunchServices know the agent by the same name")
    func oneNameForTheAgent() {
        // Not a coincidence worth leaving to chance: a person reading `launchctl`
        // output and a person reading `lsappinfo` output should be looking at the
        // same string. If either constant is ever edited alone, this is where it
        // is caught.
        #expect(Wire.agentBundleIdentifier == Wire.agentLabel)
    }

    @Test("Proctor recognises its own processes, and nothing else")
    func isProctorRecognisesOurOwn() {
        // The menu-bar app. This is the one that matters: somebody opening
        // Proctor's own menu to release a held run must not be read as a person
        // taking the machine back, or the run holds itself again on the way out.
        #expect(Wire.isProctor(bundleIdentifier: Wire.bundleIdentifier))
        #expect(Wire.isProctor(bundleIdentifier: Wire.agentBundleIdentifier))

        #expect(!Wire.isProctor(bundleIdentifier: nil))
        #expect(!Wire.isProctor(bundleIdentifier: ""))
        #expect(!Wire.isProctor(bundleIdentifier: "com.apple.Safari"))
        // A near miss, because a prefix test would have passed this and would be
        // the wrong rule: somebody else's bundle is not Proctor's.
        #expect(!Wire.isProctor(bundleIdentifier: Wire.bundleIdentifier + ".evil"))
    }

    @Test("the identity is named, not inferred from whatever process is asking")
    func identityIsNotInferred() {
        // This is the regression PRO-0040 would otherwise have shipped, made
        // concrete. `ContentionMonitor.ourOwnPids()` used to find Proctor's own
        // processes with `Bundle.main.bundleIdentifier`, which worked only while
        // the agent inherited the app's Info.plist. The agent now carries its own,
        // so that read returns the agent's identity and matches no running
        // application — the menu-bar app drops out of the set, and releasing a held
        // run from Proctor's own menu reads as a person taking the machine.
        //
        // This test process stands in for that: its own main bundle is the test
        // runner, not Proctor. Inferring would find nothing here; naming works.
        #expect(Bundle.main.bundleIdentifier != Wire.bundleIdentifier)
        #expect(Wire.isProctor(bundleIdentifier: Wire.bundleIdentifier))
    }

    @Test("the shipped agent plist declares the identity the code reasons with")
    func agentPlistMatchesTheConstant() throws {
        let agent = try Self.plist("Apps/Proctor/AgentInfo.plist")

        #expect(agent["CFBundleIdentifier"] as? String == Wire.agentBundleIdentifier)

        // LSUIElement, not LSBackgroundOnly. LSBackgroundOnly is the plist form of
        // the prohibited activation policy, documented as not permitting windows,
        // and the agent draws the run HUD and the cursor overlay.
        #expect(agent["LSUIElement"] as? Bool == true)
        #expect(agent["LSBackgroundOnly"] == nil)

        // A process holding Accessibility and Screen Recording should be nameable
        // in Activity Monitor and in a crash report.
        #expect(agent["CFBundleName"] as? String == "Proctor Agent")

        // No version keys, deliberately: BuildInfo already answers which build the
        // agent is, and a second version string is a second thing that can disagree
        // with the tag scripts/check-release-version.sh gates on.
        #expect(agent["CFBundleShortVersionString"] == nil)
        #expect(agent["CFBundleVersion"] == nil)
    }

    @Test("the app's plist still owns the identity the grants are attached to")
    func appPlistIsUnchanged() throws {
        let app = try Self.plist("Apps/Proctor/Info.plist")

        // The whole design rests on this one staying put. Every nested binary is
        // signed `-i` with it, and that is what the recorded designated requirement
        // names, which is what TCC matches on.
        #expect(app["CFBundleIdentifier"] as? String == Wire.bundleIdentifier)

        // And the two are genuinely distinct, which is the property that makes
        // `open -a Proctor` find the app rather than the agent.
        #expect(app["CFBundleIdentifier"] as? String != Wire.agentBundleIdentifier)
    }
}
