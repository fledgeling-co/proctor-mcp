import Foundation

/// Where a SwiftPM resource bundle actually is at run time, and what to do when
/// it is nowhere.
///
/// SwiftPM generates `Bundle.module` per target. For an executable target — and
/// for a library statically linked into one, which is every target here — the
/// generated accessor looks in exactly two places:
///
/// ```swift
/// let mainPath  = Bundle.main.bundleURL.appendingPathComponent("<name>.bundle").path
/// let buildPath = "/Users/<whoever built it>/.build/<triple>/release/<name>.bundle"
/// guard let bundle = Bundle(path: mainPath) ?? Bundle(path: buildPath) else { fatalError(…) }
/// ```
///
/// Both are wrong for a shipped `.app`, and they fail in a way that only shows up
/// on somebody else's Mac:
///
/// - `mainPath` is the bundle **root** — `Proctor.app/<name>.bundle`. Packaging
///   puts resources in `Proctor.app/Contents/Resources`, which is the layout
///   macOS documents, so this never matches a correctly built app.
/// - `buildPath` is an absolute path into the build directory of the machine
///   that compiled it. On that machine it exists, so everything works and the
///   defect is invisible. On any other Mac it does not, and `Bundle.module`
///   traps.
///
/// Measured on 2026-08-20: the notarised wave-9 bundle, installed into a macOS
/// guest, crash-looped its agent on the first call that drew the run character —
/// `Fatal error: could not load resource bundle` — while the identical bundle on
/// the build machine was fine. Every release asset carries this.
///
/// So this type does the search itself, over the places a bundle is genuinely
/// found, and **returns nil rather than trapping**. That second half is the
/// point: both call sites already treat a missing picture as a missing picture,
/// and `RunHUDCharacter.menuBarAssetURL` says so in as many words. A decorative
/// PNG is not worth an agent.
public enum ResourceBundles {

    /// An Objective-C-visible class in this module, so `Bundle(for:)` can name
    /// whatever bundle this code was loaded from. In a shipped app that is the
    /// app itself; under `swift test` it is the `.xctest` package, whose parent
    /// directory is where SwiftPM leaves the resource bundles. `Bundle.main`
    /// answers neither question there — measured 2026-08-20, it is
    /// `…/XcodeDefault.xctoolchain/usr/libexec/swift/pm`, the toolchain's test
    /// helper, which has nothing to do with this package.
    final class Anchor: NSObject {}

    /// The bundle this code was loaded from.
    public static let ownBundle = Bundle(for: Anchor.self)

    /// The directories a resource bundle is looked for in, in order.
    ///
    /// Pure, taking the URLs rather than the bundles, so the order can be
    /// asserted without a bundle on disk and without subclassing `Bundle` —
    /// which is a class cluster, and a stub subclass of one takes the test
    /// runner down with SIGTRAP rather than failing.
    public static func searchDirectories(mainResource: URL?,
                                         mainBundle: URL,
                                         mainExecutable: URL?,
                                         anchorResource: URL?,
                                         anchorBundle: URL) -> [URL] {
        var out: [URL] = []
        var seen = Set<String>()
        func add(_ url: URL?) {
            guard let url, seen.insert(url.standardizedFileURL.path).inserted else { return }
            out.append(url)
        }
        // 1. `Foo.app/Contents/Resources` — where a packaged app puts them, and
        //    where this repo's own packaging step does.
        add(mainResource)
        // 2. `Foo.app` itself — what SwiftPM's generated accessor expects.
        add(mainBundle)
        // 3. The directory holding the running executable: a loose binary sitting
        //    beside its bundle, which is `swift run` and `.build/<triple>/debug`.
        add(mainExecutable?.deletingLastPathComponent())
        // 4. Whatever bundle this code was loaded from, and its own resources.
        add(anchorResource)
        add(anchorBundle)
        // 5. Last, the directories those two sit in. Under `swift test` this is
        //    the build directory holding the resource bundles; in a shipped app
        //    it is `/Applications`, which is why it is asked last.
        add(anchorBundle.deletingLastPathComponent())
        add(mainBundle.deletingLastPathComponent())
        return out
    }

    /// The same order, read off the running process.
    public static func searchDirectories(main: Bundle = .main,
                                         anchor: Bundle = ResourceBundles.ownBundle) -> [URL] {
        searchDirectories(mainResource: main.resourceURL,
                          mainBundle: main.bundleURL,
                          mainExecutable: main.executableURL,
                          anchorResource: anchor.resourceURL,
                          anchorBundle: anchor.bundleURL)
    }

    /// The bundle named `name`, or nil if it is not in any searched directory.
    public static func bundle(named name: String, main: Bundle = .main) -> Bundle? {
        for directory in searchDirectories(main: main) {
            let candidate = directory.appendingPathComponent("\(name).bundle")
            if let bundle = Bundle(url: candidate) { return bundle }
        }
        return nil
    }

    /// A resource inside that bundle, or nil. Never traps, at either step.
    public static func url(inBundleNamed name: String,
                           resource: String,
                           extension ext: String,
                           subdirectory: String?) -> URL? {
        guard let bundle = bundle(named: name) else { return nil }
        return bundle.url(forResource: resource, withExtension: ext,
                          subdirectory: subdirectory)
    }

    /// The two bundles this package ships. Named rather than spelled at each
    /// call site, because a typo here fails the same silent way the defect did.
    public static let core = "proctor-mcp_ProctorCore"
    public static let agent = "proctor-mcp_ProctorAgent"
}
