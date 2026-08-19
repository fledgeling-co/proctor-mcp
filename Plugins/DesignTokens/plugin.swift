import Foundation
import PackagePlugin

/// Generates `ProctorTokens` from the design of record before every build of
/// ProctorCore.
///
/// Same shape as `BuildIdentity` and for the same reason: a prebuild command is
/// scheduled without an up-to-date check of its own, and the generator's
/// write-if-changed is what stops an unchanged tree recompiling Core.
///
/// It inherits `BuildIdentity`'s known limit too, and it matters more here. When
/// llbuild considers the plan fully up to date it runs no commands at all,
/// prebuild included — so an edit to `design/surfaces/parts/head.html` alone may
/// not regenerate on the next `swift build`. That is why the drift test exists
/// rather than being redundant: it re-parses the mock and fails when the
/// generated source disagrees, which is the case this mechanism cannot prevent.
@main
struct DesignTokens: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        let outputDirectory = context.pluginWorkDirectoryURL.appending(path: "Generated")
        let generator = context.package.directoryURL.appending(path: "scripts/gen-design-tokens.py")
        return [
            .prebuildCommand(
                displayName: "Generating design tokens from the mock",
                executable: URL(fileURLWithPath: "/usr/bin/python3"),
                arguments: [generator.path, outputDirectory.path, context.package.directoryURL.path],
                outputFilesDirectory: outputDirectory)
        ]
    }
}
