import Foundation
import Testing
@testable import ProctorCore

// The defect: SwiftPM's generated `Bundle.module` looks in the app bundle ROOT
// and in an absolute path inside the build directory of whichever machine
// compiled it. A packaged `.app` puts resources in `Contents/Resources`, so the
// first never matches; the second exists only on the build machine. Result: the
// notarised wave-9 bundle ran fine here and crash-looped its agent inside a
// macOS guest, on the first call that drew the run character.
//
// Measured 2026-08-20 against /Applications/Proctor.app in a lume guest:
//   Fatal error: could not load resource bundle: from
//   /Applications/Proctor.app/proctor-mcp_ProctorAgent.bundle or
//   /Users/lukerhodes/…/.build/arm64-apple-macosx/release/proctor-mcp_ProctorAgent.bundle
@Suite("Resource bundles are found where they actually ship")
struct ResourceBundlesTests {

    private static let appRoot = URL(fileURLWithPath: "/tmp/does-not-exist/Proctor.app")

    private static func packagedOrder() -> [String] {
        ResourceBundles.searchDirectories(
            mainResource: appRoot.appendingPathComponent("Contents/Resources"),
            mainBundle: appRoot,
            mainExecutable: appRoot.appendingPathComponent("Contents/MacOS/proctor-agent"),
            anchorResource: appRoot.appendingPathComponent("Contents/Resources"),
            anchorBundle: appRoot
        ).map(\.path)
    }

    @Test("Contents/Resources is searched before the app root")
    func packagedLayoutIsSearchedFirst() throws {
        let paths = Self.packagedOrder()
        let resources = try #require(
            paths.firstIndex(of: Self.appRoot.appendingPathComponent("Contents/Resources").path),
            "the packaged layout has to be searched at all")
        let appRoot = try #require(paths.firstIndex(of: Self.appRoot.path))
        #expect(resources < appRoot,
                "Contents/Resources is where packaging puts them, so it is asked first")
    }

    @Test("the executable's own directory is searched, which is how a dev build finds them")
    func executableDirectoryIsSearched() {
        #expect(Self.packagedOrder()
            .contains(Self.appRoot.appendingPathComponent("Contents/MacOS").path))
    }

    // Under `swift test` neither of `Bundle.main`'s URLs points at this package
    // at all — measured 2026-08-20, main is the toolchain's `swiftpm-testing-helper`.
    // The bundle this code was loaded from is what finds them, so its parent
    // directory has to be in the list.
    @Test("the build directory beside the test bundle is searched")
    func theTestLayoutIsSearched() {
        let xctest = URL(fileURLWithPath: "/repo/.build/arm64-apple-macosx/debug/Pkg.xctest")
        let paths = ResourceBundles.searchDirectories(
            mainResource: URL(fileURLWithPath: "/toolchain/usr/libexec/swift/pm"),
            mainBundle: URL(fileURLWithPath: "/toolchain/usr/libexec/swift/pm"),
            mainExecutable: URL(fileURLWithPath: "/toolchain/usr/libexec/swift/pm/swiftpm-testing-helper"),
            anchorResource: xctest.appendingPathComponent("Contents/Resources"),
            anchorBundle: xctest
        ).map(\.path)
        #expect(paths.contains("/repo/.build/arm64-apple-macosx/debug"),
                "the resource bundles are siblings of the .xctest package")
    }

    // The half that matters more than finding it: a missing decorative PNG must
    // not be able to stop the agent. `Bundle.module` traps here; this does not.
    @Test("a bundle that is nowhere returns nil instead of trapping")
    func aMissingBundleIsNil() {
        #expect(ResourceBundles.bundle(named: "proctor-mcp_NoSuchBundleAnywhere") == nil)
        #expect(ResourceBundles.url(inBundleNamed: "proctor-mcp_NoSuchBundleAnywhere",
                                    resource: "idle-0", extension: "png",
                                    subdirectory: "character-menubar") == nil)
    }

    // And the path that has to keep working: the pictures this package ships are
    // still found from wherever the tests run.
    @Test("the menu bar pictures this package ships still resolve")
    func shippedMenuBarAssetsResolve() throws {
        let url = try #require(RunHUDCharacter.menuBarAssetURL(asset: "idle-0", scale: 2),
                               "the shipped menu bar sprite must still be found")
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(url.pathExtension == "png")
    }
}
