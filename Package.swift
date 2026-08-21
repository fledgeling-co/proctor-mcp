// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "proctor-mcp",
    platforms: [.macOS(.v14)],
    products: [
        // The privileged core. Ships inside Proctor.app, run as a launchd user agent.
        .executable(name: "proctor-agent", targets: ["ProctorAgent"]),
        // The permissionless thing an MCP host launches. Holds no TCC grants.
        .executable(name: "proctor-shim", targets: ["ProctorShim"]),
        // The face of the app: onboarding, live grant state, and how to connect
        // a model to it. Runs inside the same bundle as the agent, so it shares
        // the identity the TCC grants are attached to.
        .executable(name: "Proctor", targets: ["ProctorUI"]),
        // Embeddable in apps you own, to get a real computed-style source.
        .library(name: "ProctorReflector", targets: ["ProctorReflector"]),
        // PRO-0073. The operator CLI: one verb per tool, over the same socket
        // the MCP shim uses, so a CLI call passes the same gates.
        .executable(name: "proctor-cli", targets: ["ProctorCLI"]),
    ],
    targets: [
        // The menu bar's rendition of the run-HUD character lives here rather
        // than in either executable: both the agent and the UI reach Core, the
        // frame table and the motion rule are already here, and a test can prove
        // every picture is present at every density without a test target for a
        // SwiftUI app. The panel's own 38pt set stays in the agent's bundle,
        // beside the view that draws it.
        .target(name: "ProctorCore", resources: [.copy("Resources/character-menubar")],
                plugins: ["BuildIdentity", "DesignTokens"]),
        // Which build this is, written before every build. It hangs off `swift build`
        // because that is the only step the three build paths — a plain build, the
        // install script, and the release workflow — already have in common, so none
        // of them has to be taught anything. The generator never fails and writes only
        // when its content changes, so an unchanged tree does not recompile Core.
        .plugin(name: "BuildIdentity", capability: .buildTool()),
        // PRO-0064. The mock's token block is the source for every colour, radius
        // and control height the app draws, and this carries it into Swift so
        // nothing transcribes a value by hand.
        .plugin(name: "DesignTokens", capability: .buildTool()),
        // One Objective-C function, and it needs its own target because SwiftPM
        // has no mixed-language ones. Swift cannot catch an NSException, AppKit
        // still raises them, and an uncaught one aborts the process — which for a
        // drawing fault in the run HUD means the panel takes down the agent, the
        // run and the MCP server with it.
        .target(name: "ProctorCatch"),
        // The run HUD's character ships inside the binary's resource bundle: an
        // agent holding these permissions has no business reaching the network
        // to draw itself, and a picture fetched mid-run is a picture that can
        // fail mid-run.
        .executableTarget(name: "ProctorAgent", dependencies: ["ProctorCore", "ProctorCatch"],
                          resources: [.copy("Resources/character")],
                          // The agent's own Info.plist, linked in as a __TEXT section
                          // so it presents its own LaunchServices identity instead of
                          // inheriting the enclosing app's. Without it LaunchServices
                          // records the agent as a running instance of Proctor.app and
                          // `open -a Proctor` activates a process with no window, which
                          // means the app cannot be opened while its agent is up — see
                          // Apps/Proctor/AgentInfo.plist and PRO-0040.
                          //
                          // unsafeFlags because SwiftPM has no first-class -sectcreate.
                          // The restriction it carries is product-scoped, and this is an
                          // executable target that no product exposes, so a package
                          // depending on this one by version for ProctorReflector still
                          // resolves — measured, not assumed.
                          //
                          // Release only, and deliberately. Linker settings propagate to
                          // whatever links the target, and the test bundle links this one:
                          // measured, an unconditional flag put the agent's Info.plist
                          // into proctor-mcpPackageTests.xctest, so every test process ran
                          // holding the agent's identity and LSUIElement. The section only
                          // ever matters in a shipped bundle, and scripts/build-app.sh —
                          // the one step both the local installer and release.yml go
                          // through — always builds `-c release` and then fails the build
                          // if the section is missing. So the artifact that ships is gated
                          // and the test bundle is left alone.
                          linkerSettings: [.unsafeFlags([
                              "-Xlinker", "-sectcreate",
                              "-Xlinker", "__TEXT",
                              "-Xlinker", "__info_plist",
                              "-Xlinker", "Apps/Proctor/AgentInfo.plist",
                          ], .when(configuration: .release))]),
        .executableTarget(name: "ProctorShim", dependencies: ["ProctorCore"]),
        .executableTarget(name: "ProctorCLI", dependencies: ["ProctorCore"]),
        // PRO-0065. The Reflector is embedded here and nowhere else, so
        // `proctor_inspect` can measure Proctor's own view tree and settling on
        // Proctor's own surfaces can report `reflectorIdle`. It compiles to
        // nothing without DEBUG or PROCTOR_REFLECTOR, and scripts/build-app.sh
        // fails a release artifact that carries it: a reflector socket inside a
        // process holding Accessibility and Screen Recording is readable by
        // anything that can reach it.
        .executableTarget(name: "ProctorUI", dependencies: ["ProctorCore", "ProctorReflector"]),
        .target(name: "ProctorReflector", exclude: ["README.md"]),
        .testTarget(name: "ProctorCoreTests", dependencies: ["ProctorCore"],
                    resources: [.copy("Fixtures")]),
        // The agent's own wiring — the policy gate and the audit trail around the
        // drive paths — against fake AX/capture engines. Session takes both as
        // injected protocols, so the gate ordering and the trail contents are
        // checkable without a Mac, a grant, or a real application.
        .testTarget(name: "ProctorAgentTests",
                    dependencies: ["ProctorAgent", "ProctorCore", "ProctorCatch"]),
    ]
)
