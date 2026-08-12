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
        // Embeddable in apps you own, to get a real computed-style source.
        .library(name: "ProctorReflector", targets: ["ProctorReflector"]),
    ],
    targets: [
        .target(name: "ProctorCore"),
        .executableTarget(name: "ProctorAgent", dependencies: ["ProctorCore"]),
        .executableTarget(name: "ProctorShim", dependencies: ["ProctorCore"]),
        .target(name: "ProctorReflector", exclude: ["README.md"]),
        .testTarget(name: "ProctorCoreTests", dependencies: ["ProctorCore"]),
    ]
)
