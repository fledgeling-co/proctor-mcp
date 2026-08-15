import Testing
import Foundation
@testable import ProctorCore

// PRO-0049, the governance half. Executing a caller-named YAML from a process
// holding Accessibility and Screen Recording is the sharpest thing in this item,
// and the gate here is deliberately weaker than the one `proctor_ios` action
// `open` applies: `open` judges the app the DEVICE resolves a URL to, and a flow
// file can only be judged on what it DECLARES.
//
// Every test below is about not overstating that. The scan over-detects on
// purpose — an extra app id can only cause a refusal and never authorise one —
// and where a YAML construct structurally defeats a line-oriented scan, the scan
// says so rather than guessing.

@Suite("PRO-0049 · Maestro flow gate")
struct MaestroGateTests {

    static func scan(_ text: String) -> MaestroDeclaration {
        MaestroFlowScan.scan(text: text, source: "flow.yaml")
    }

    static let simpleFlow = """
    appId: com.example.app
    ---
    - launchApp
    - tapOn: "General"
    """

    // MARK: - AC7 · every declared app is gated

    @Test("the header appId and a different launchApp target are both collected")
    func collectsEveryDeclaredApp() {
        let declaration = Self.scan("""
        appId: com.example.app
        ---
        - launchApp:
            appId: com.example.other
        - tapOn: "Go"
        """)
        #expect(declaration.declaredApps.contains("com.example.app"))
        #expect(declaration.declaredApps.contains("com.example.other"))
    }

    @Test("an app id under a key the scan does not model is collected anyway")
    func collectsAppIdsUnderUnmodelledKeys() {
        // Out-of-family review broke an enumeration of app-id-bearing keys by
        // naming these five. Collecting every reverse-DNS token covers the class
        // rather than the list.
        for key in ["stopApp", "killApp", "clearState", "setPermission", "onFlowStart"] {
            let declaration = Self.scan("appId: com.a.b\n---\n- \(key): com.sneaky.target\n")
            #expect(declaration.declaredApps.contains("com.sneaky.target"),
                    "\(key) should not hide a target")
        }
    }

    @Test("a blocked declared app refuses the flow")
    func blockedAppRefuses() {
        let policy = AppPolicy(allow: [], block: ["com.example.other"], sensitive: [])
        let declaration = Self.scan("""
        appId: com.example.app
        ---
        - launchApp:
            appId: com.example.other
        """)
        let decision = MaestroGate.decide(declaration: declaration, resolvedOpenLinks: [],
                                          policy: policy, hasValidToken: { _ in false })
        #expect(decision.refusal != nil)
    }

    @Test("an allow list judges the ios-qualified key, never the bare bundle id")
    func allowListIsPlatformQualified() {
        let declaration = Self.scan(Self.simpleFlow)
        // The Mac app of the same identifier being allowed must not authorise the
        // iOS one — the asymmetry IOSPolicy already carries.
        let macOnly = AppPolicy(allow: ["com.example.app"], block: [], sensitive: [])
        #expect(MaestroGate.decide(declaration: declaration, resolvedOpenLinks: [],
                                   policy: macOnly, hasValidToken: { _ in false }).refusal != nil)

        let iosAllowed = AppPolicy(allow: [IOSPolicy.key(for: "com.example.app")],
                                   block: [], sensitive: [])
        #expect(MaestroGate.decide(declaration: declaration, resolvedOpenLinks: [],
                                   policy: iosAllowed, hasValidToken: { _ in false }).refusal == nil)
    }

    @Test("a sensitive declared app needs a token")
    func sensitiveAppNeedsAToken() {
        let declaration = Self.scan(Self.simpleFlow)
        let policy = AppPolicy(allow: [], block: [],
                               sensitive: [IOSPolicy.key(for: "com.example.app")])
        #expect(MaestroGate.decide(declaration: declaration, resolvedOpenLinks: [],
                                   policy: policy, hasValidToken: { _ in false }).refusal != nil)
        #expect(MaestroGate.decide(declaration: declaration, resolvedOpenLinks: [],
                                   policy: policy, hasValidToken: { _ in true }).refusal == nil)
    }

    // MARK: - AC8 · unresolvable constructs fail closed under any policy

    @Test("a script is reported as a capability, not as an unresolved app id")
    func scriptIsACapability() {
        for key in ["runScript", "evalScript"] {
            let declaration = Self.scan("appId: com.a.b\n---\n- \(key): helper.js\n")
            let found = declaration.unresolved.first { $0.construct == key }
            #expect(found?.kind == .capability)
            // An application allow list does not govern egress, and the note says so.
            #expect(found?.detail.contains("network") == true)
        }
    }

    @Test("an interpolated app id is an opaque target")
    func interpolatedAppIdIsOpaque() {
        let declaration = Self.scan("appId: ${APP_UNDER_TEST}\n---\n- launchApp\n")
        #expect(declaration.unresolved.contains { $0.kind == .opaqueTarget })
    }

    @Test("YAML constructs a line scan cannot follow are reported rather than scanned past")
    func defeatingYamlIsReported() {
        let cases = [
            "anchor": "appId: &shared com.a.b\n---\n- launchApp\n",
            "alias": "appId: com.a.b\n---\n- runFlow: *shared\n",
            "merge": "appId: com.a.b\n---\n- launchApp:\n    <<: *defaults\n",
            "block scalar": "appId: com.a.b\n---\n- evalScript: |\n    doSomething()\n"
        ]
        for (name, text) in cases {
            #expect(Self.scan(text).unresolved.contains { $0.kind == .opaqueTarget },
                    "\(name) should be reported as unresolved")
        }
    }

    @Test("an unresolvable construct is refused under an allow list, a block list or the sensitive set")
    func anyPolicyInForceRefusesTheUnresolvable() {
        let declaration = Self.scan("appId: com.a.b\n---\n- runScript: x.js\n")
        let policies: [(String, AppPolicy)] = [
            ("allow", AppPolicy(allow: [IOSPolicy.key(for: "com.a.b")], block: [], sensitive: [])),
            // The hole out-of-family review found: a block list with no allow
            // list is a policy in force, and letting an unresolvable construct
            // through would defeat the block.
            ("block", AppPolicy(allow: [], block: ["com.something.else"], sensitive: [])),
            ("sensitive", AppPolicy(allow: [], block: [], sensitive: ["ios:com.other"]))
        ]
        for (name, policy) in policies {
            #expect(MaestroGate.policyInForce(policy), "\(name) should count as in force")
            let decision = MaestroGate.decide(declaration: declaration, resolvedOpenLinks: [],
                                              policy: policy, hasValidToken: { _ in true })
            #expect(decision.refusal != nil, "\(name) list should refuse an unresolvable construct")
            #expect(decision.refusal?.reason.contains("runScript") == true)
        }
    }

    @Test("an empty policy runs the flow and reports the construct instead")
    func emptyPolicyRunsAndReports() {
        // Inert until configured, exactly as AppPolicy and FSJail already are.
        // Refusing here would be stricter than every other path in this codebase
        // on a default install, in a posture where everything is permitted.
        let declaration = Self.scan("appId: com.a.b\n---\n- runScript: x.js\n")
        let empty = AppPolicy(allow: [], block: [], sensitive: [])
        #expect(MaestroGate.policyInForce(empty) == false)
        #expect(MaestroGate.decide(declaration: declaration, resolvedOpenLinks: [],
                                   policy: empty, hasValidToken: { _ in false }).refusal == nil)
        #expect(declaration.unresolved.isEmpty == false)
    }

    // MARK: - AC10 · openLink is gated on what the device resolves

    @Test("an openLink URL is collected for device resolution, not read from the file")
    func openLinkIsCollected() {
        let declaration = Self.scan("appId: com.a.b\n---\n- openLink: other://deep/link\n")
        #expect(declaration.openLinks == ["other://deep/link"])
    }

    @Test("the app a device resolves an openLink to is gated, even when the flow declares another")
    func openLinkIsGatedOnTheDevicesAnswer() {
        let declaration = Self.scan("appId: com.allowed.app\n---\n- openLink: other://x\n")
        let policy = AppPolicy(allow: [IOSPolicy.key(for: "com.allowed.app")],
                               block: [], sensitive: [])
        // Declaring an allowed app while opening a link belonging to another is
        // exactly the substitution PRO-0048's deep-link gate closed.
        let decision = MaestroGate.decide(declaration: declaration,
                                          resolvedOpenLinks: ["com.other.app"],
                                          policy: policy, hasValidToken: { _ in false })
        #expect(decision.refusal != nil)
    }

    @Test("an unresolvable link is refused under an allow list")
    func unresolvableLinkRefusedUnderAllowList() {
        let declaration = Self.scan("appId: com.allowed.app\n---\n- openLink: https://x.example\n")
        let policy = AppPolicy(allow: [IOSPolicy.key(for: "com.allowed.app")],
                               block: [], sensitive: [])
        let decision = MaestroGate.decide(declaration: declaration, resolvedOpenLinks: [nil],
                                          policy: policy, hasValidToken: { _ in false })
        #expect(decision.refusal != nil)
        #expect(decision.refusal?.reason.contains("associated domains") == true)
    }

    @Test("an interpolated openLink is opaque rather than collected")
    func interpolatedOpenLinkIsOpaque() {
        let declaration = Self.scan("appId: com.a.b\n---\n- openLink: ${TARGET_URL}\n")
        #expect(declaration.openLinks.isEmpty)
        #expect(declaration.unresolved.contains { $0.construct == "openLink" })
    }

    // MARK: - AC11 · includes and the adjacent workspace config

    @Test("a runFlow include is followed and its apps are gated with the parent's")
    func includesAreFollowed() {
        let declaration = MaestroFlowScan.resolve(
            rootPath: "/flows/main.yaml",
            rootText: "appId: com.a.b\n---\n- runFlow: child.yaml\n",
            read: { target in
                target.contains("child")
                    ? ("/flows/child.yaml", "appId: com.child.app\n---\n- launchApp\n")
                    : nil
            })
        #expect(declaration.declaredApps.contains("com.child.app"))
        #expect(declaration.includes.contains("/flows/child.yaml"))
    }

    @Test("an include Proctor cannot read is an opaque target, not an error")
    func unreadableIncludeIsOpaque() {
        let declaration = MaestroFlowScan.resolve(
            rootPath: "/flows/main.yaml",
            rootText: "appId: com.a.b\n---\n- runFlow: missing.yaml\n",
            read: { _ in nil })
        #expect(declaration.unresolved.contains { $0.construct == "runFlow" })
    }

    @Test("include cycles and runaway nesting terminate")
    func includeCyclesTerminate() {
        let declaration = MaestroFlowScan.resolve(
            rootPath: "/flows/a.yaml",
            rootText: "appId: com.a.b\n---\n- runFlow: a.yaml\n",
            read: { _ in ("/flows/a.yaml", "appId: com.a.b\n---\n- runFlow: a.yaml\n") })
        #expect(declaration.declaredApps.contains("com.a.b"))
    }

    @Test("a config.yaml beside the flow is scanned with it")
    func adjacentConfigIsScanned() {
        // Maestro reads a workspace config implicitly when --config is not
        // passed, so content outside the named file steers the run.
        let declaration = MaestroFlowScan.resolve(
            rootPath: "/flows/main.yaml",
            rootText: "---\n- launchApp\n",
            siblingConfig: "appId: com.workspace.app\n",
            read: { _ in nil })
        #expect(declaration.declaredApps.contains("com.workspace.app"))
    }

    // MARK: - The scan's own edges

    @Test("a comment does not contribute, and a file name is not a bundle id")
    func scanIgnoresCommentsAndFilenames() {
        let declaration = Self.scan("""
        appId: com.example.app
        # - launchApp: com.commented.out
        ---
        - runFlow: some.nested.yaml
        """)
        #expect(declaration.declaredApps.contains("com.example.app"))
        #expect(declaration.declaredApps.contains("com.commented.out") == false)
        #expect(declaration.declaredApps.contains("some.nested.yaml") == false)
    }

    @Test("a space before the colon does not hide a key")
    func spaceBeforeColonIsTolerated() {
        #expect(Self.scan("appId: com.a.b\n---\n- openLink : x://y\n").openLinks == ["x://y"])
    }

    @Test("quoted values are unwrapped")
    func quotedValuesAreRead() {
        #expect(Self.scan("appId: com.a.b\n---\n- openLink: \"x://y\"\n").openLinks == ["x://y"])
    }
}
