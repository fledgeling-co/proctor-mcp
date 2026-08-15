import Foundation
import PackagePlugin

/// Runs `scripts/gen-build-identity.sh` before every build of ProctorCore.
///
/// A *prebuild* command rather than a build command, because prebuild commands run
/// every time with no up-to-date check — which is the freshness. The economy is the
/// generator's own write-if-changed: an unchanged tree leaves the file alone, so
/// nothing downstream recompiles.
///
/// This is the only mechanism the three build paths in the brief already share.
/// `swift build`, `scripts/install.sh` (through `build-app.sh`) and the release
/// workflow (also through `build-app.sh`) all run `swift build`, and nothing else.
///
/// Measured before it was specified: this runs under SwiftPM's default plugin
/// sandbox with no flags, inside a git worktree where `.git` is a pointer file to
/// objects outside the package directory, and produces a real sha. The sandbox
/// restricts writes, not reads.
@main
struct BuildIdentity: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        let outputDirectory = context.pluginWorkDirectoryURL.appending(path: "Generated")
        let generator = context.package.directoryURL.appending(path: "scripts/gen-build-identity.sh")
        return [
            .prebuildCommand(
                displayName: "Recording the build identity",
                executable: URL(fileURLWithPath: "/bin/sh"),
                arguments: [generator.path, outputDirectory.path, context.package.directoryURL.path],
                outputFilesDirectory: outputDirectory)
        ]
    }
}
