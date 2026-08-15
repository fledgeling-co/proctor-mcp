import Foundation
import PackagePlugin

/// Runs `scripts/gen-build-identity.sh` before every build of ProctorCore.
///
/// A *prebuild* command rather than a build command, because a prebuild command is
/// scheduled on every build with no up-to-date check of its own. The economy is the
/// generator's own write-if-changed: an unchanged tree leaves the file alone, so
/// nothing downstream recompiles.
///
/// **That is not the same as running every time, and this comment used to claim it
/// was.** Measured on 2026-08-15 (PRO-0043): when llbuild considers the build plan
/// fully up to date it runs no commands at all, prebuild included. `swift build`
/// prints `Build complete! (0.11s)` and the generator does not execute, over
/// repeated builds. `swift build` and `swift test` also keep separate build plans,
/// so whichever was last brought up to date decides how fresh the identity is.
///
/// So the compiled identity can lag the checkout after an amend or a rebase that
/// moves HEAD without touching a source file, and `rm -rf .build/plugins` is what
/// forces it. There is no set of declared inputs to add here — a prebuild command
/// declares none, and the step being skipped is the whole plan — so closing this
/// means a different mechanism. It is recorded as child work on
/// `docs/specs/spec-PRO-0043.md` rather than fixed there, and the test suite no
/// longer asserts a freshness this cannot promise.
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
