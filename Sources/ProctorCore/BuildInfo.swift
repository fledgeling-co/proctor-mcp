import Foundation
import Darwin

/// Which build this is.
///
/// The constant this replaces was a hardcoded `0.1.0` that had never been bumped, so
/// two machines running builds three months apart reported the same string, and the
/// staleness check in `BuildStamp` could not ask a version a useful question.
///
/// The fix is not a better single string. One field cannot carry this, because it is
/// several questions and their answers have different shapes:
///
///   version        which RELEASE LINE — the words the tag, the CHANGELOG heading and
///                  the release asset use. Stale between releases on purpose: it names
///                  a release, not a binary.
///   commit         whether this is the SAME CODE as that. Exact, comparable between
///                  two machines without trusting a clock, and unreadable to a person.
///   dirty          whether it is that commit, or that commit PLUS somebody's edits.
///   configuration  whether it is the SAME PROGRAM. A debug and a release build of one
///                  commit are not interchangeable, and "why is this slow" is answered
///                  here and nowhere else.
///   builtAt        which of two builds is NEWER, and the only field that separates two
///                  builds of one dirty tree — which is a developer's normal state.
///
/// `descriptor` folds the first four into one string to quote. It identifies the
/// *program*; `builtAt` identifies the *build event*. They are separate deliberately:
/// two clean release builds of one commit are the same program and say so.
public struct BuildIdentity: Codable, Sendable, Equatable {
    /// The release line, e.g. `0.1.0`. Read at build time from
    /// `Apps/Proctor/Info.plist`, which is the same file the release workflow reads
    /// for the asset name and the CHANGELOG match — one source, so they cannot drift.
    public let version: String

    /// The short commit, e.g. `e1f6cbf4fd1c`, or one of two sentinels that mean
    /// different things and call for different responses:
    ///
    ///   `unknown`      not a git checkout — a tarball, an unpacked release. Expected.
    ///   `unavailable`  git is present and could not answer. Someone should look, and a
    ///                  single `unknown` would have sent them hunting for a tarball that
    ///                  does not exist.
    public let commit: String

    /// Whether uncommitted or untracked changes were present when this was built. A
    /// dirty build is not identified by its commit and does not pretend to be.
    public let dirty: Bool

    /// `debug` or `release`. Same source, different program.
    public let configuration: String

    /// When the running executable's file was last written, ISO-8601 in UTC, or nil
    /// when that could not be read.
    ///
    /// Stated plainly because the name over-promises: for a plain `swift build` this is
    /// link time; for a packaged bundle it is assembly-and-sign time, because
    /// `scripts/build-app.sh` copies each binary in and re-signs it, and `cp` sets the
    /// destination's modification time to the copy. For a bundle that is the better
    /// answer anyway — a cached link can predate the build that shipped it.
    ///
    /// `BuildStamp` rejected modification time and this uses it, which is not a
    /// contradiction: there it triggers a DECISION, where a stray `touch` would raise a
    /// banner nobody could clear. Here it is a REPORT, and nothing keys on it. A forged
    /// date misleads a reader; it cannot make Proctor do anything.
    public let builtAt: String?

    public init(version: String, commit: String, dirty: Bool,
                configuration: String, builtAt: String?) {
        self.version = version
        self.commit = commit
        self.dirty = dirty
        self.configuration = configuration
        self.builtAt = builtAt
    }

    /// The one string to quote: `0.1.0+e1f6cbf4fd1c`, `0.1.0+e1f6cbf4fd1c.dirty`,
    /// `0.1.0+e1f6cbf4fd1c.debug`, `0.1.0+unknown`.
    ///
    /// The `+` is semantic versioning's build metadata, which the standard defines as
    /// ignored when comparing precedence — which is exactly what this means. Two builds
    /// of one release line are one release. A parser that ever compares these gets the
    /// right answer for the right reason.
    ///
    /// A clean release build adds no suffix, so the string that ships to other people
    /// stays short and the suffixes are all abnormal states.
    ///
    /// `builtAt` is deliberately absent: it is the build event, not the program.
    public var descriptor: String {
        var text = "\(version)+\(commit)"
        if dirty { text += ".dirty" }
        if configuration == "debug" { text += ".debug" }
        return text
    }
}

public enum BuildInfo {
    /// The identity of the running executable, resolved once.
    ///
    /// A `static let`, so `builtAt` becomes a STORED property of a value captured the
    /// first time anything asks. Every executable touches this during startup, which is
    /// what makes it describe the image that is actually running: after an upgrade the
    /// *path* holds the new file while the process is still the old one, so a `stat` at
    /// report time would pair this build's compiled commit with the next build's date —
    /// wrong in exactly the situation `BuildStamp` exists for.
    public static let current = BuildIdentity(
        version: BuildIdentityGenerated.version,
        commit: BuildIdentityGenerated.commit,
        dirty: BuildIdentityGenerated.dirty,
        configuration: buildConfiguration,
        builtAt: builtAt(ofExecutableAt: runningExecutablePath))

    /// Resolve the identity now rather than at the first report. Called from each
    /// executable's first lines; a no-op afterwards.
    @discardableResult
    public static func captureAtLaunch() -> BuildIdentity { current }

    static var buildConfiguration: String {
        #if DEBUG
        return "debug"
        #else
        return "release"
        #endif
    }

    /// The path of the image actually running, resolved through symlinks.
    ///
    /// `_NSGetExecutablePath` rather than `Bundle.main.executableURL`, because it names
    /// the running image by definition where `Bundle.main` infers one. Three binaries
    /// ship inside `Proctor.app` — the UI, the agent and the shim — and only the first
    /// is `CFBundleExecutable`, so an inference that went the other way would have the
    /// agent reporting the UI binary's date: wrong on its own, and wrong twice over for
    /// the case this feature exists to describe, an upgrade that left the two halves of
    /// one bundle on different builds.
    ///
    /// **Measured rather than assumed, and the measurement is mixed.** Run from
    /// `Contents/MacOS/` inside the bundle, `Bundle.main.executableURL` returned the
    /// helper's own path and not `CFBundleExecutable`, so that particular
    /// misattribution did not reproduce. Run as a bare command-line binary the two
    /// disagreed: `Bundle.main` gave the symlinked `.build/release/proctor-shim` while
    /// this gives the canonical `.build/arm64-apple-macosx/release/proctor-shim`. Both
    /// stat the same file, so the date came out the same.
    ///
    /// So this is not fixing a reproduced bug; it is declining to depend on CFBundle's
    /// inference for a fact the kernel already knows exactly.
    ///
    /// `CommandLine.arguments.first` is argv[0], which is whatever the launcher chose
    /// to pass and can be a bare name.
    static var runningExecutablePath: String? {
        var size = UInt32(0)
        _ = _NSGetExecutablePath(nil, &size)
        guard size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: Int(size))
        let result = buffer.withUnsafeMutableBytes { raw -> Int32 in
            guard let base = raw.baseAddress else { return -1 }
            return _NSGetExecutablePath(base.assumingMemoryBound(to: CChar.self), &size)
        }
        guard result == 0 else { return nil }
        // Truncate at the NUL rather than decoding the whole buffer: the call writes a
        // C string into a buffer it does not have to fill.
        let path = String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
        guard !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    /// The modification time of a named executable, ISO-8601 in UTC, or nil when the
    /// path cannot be read. Nil rather than a fabricated date: a build whose date
    /// nobody can read should say so.
    ///
    /// Pure over its argument so the capture semantics can be tested without replacing
    /// the running binary.
    public static func builtAt(ofExecutableAt path: String?) -> String? {
        guard let path,
              let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let modified = attrs[.modificationDate] as? Date
        else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: modified)
    }
}
