import Testing
import Foundation
@testable import ProctorCore

// Which build this is.
//
// The constant these replace was a hardcoded `0.1.0` that had never been bumped, so
// two machines running builds three months apart reported the same string. The point
// of a test suite here is that the failure mode being fixed is *silence*: a build
// identity that quietly degrades to a placeholder looks exactly like one that works,
// and the only thing standing between the two is an assertion.
@Suite("Build identity")
struct BuildInfoTests {

    // MARK: - Helpers

    /// The package directory, found from this file rather than from the working
    /// directory, which a test runner does not promise anything about.
    private static var packageDirectory: String {
        URL(fileURLWithPath: #filePath)      // Tests/ProctorCoreTests/BuildInfoTests.swift
            .deletingLastPathComponent()     // Tests/ProctorCoreTests
            .deletingLastPathComponent()     // Tests
            .deletingLastPathComponent()     // <package>
            .path
    }

    /// Run a command and return its trimmed stdout, or nil if it could not run or
    /// exited non-zero.
    @discardableResult
    private static func run(_ launchPath: String, _ arguments: [String],
                            environment: [String: String]? = nil,
                            status: UnsafeMutablePointer<Int32>? = nil) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        if let environment {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        }
        let out = Pipe()
        process.standardOutput = out
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        status?.pointee = process.terminationStatus
        if status == nil && process.terminationStatus != 0 { return nil }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func generator(outputDirectory: String, packageDirectory: String) -> String? {
        run("/bin/sh", ["\(Self.packageDirectory)/scripts/gen-build-identity.sh",
                        outputDirectory, packageDirectory])
        let generated = "\(outputDirectory)/BuildIdentityGenerated.swift"
        return try? String(contentsOfFile: generated, encoding: .utf8)
    }

    private static func temporaryDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("build-identity-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A minimal Info.plist carrying a version, so the generator has something real
    /// to read without depending on the repository's own.
    private static func writePlist(version: String, into root: URL) throws {
        let dir = root.appendingPathComponent("Apps/Proctor")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0">
        <dict>
        \t<key>CFBundleShortVersionString</key>
        \t<string>\(version)</string>
        </dict>
        </plist>
        """
        try plist.write(to: dir.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)
    }

    // MARK: - A1: a plain build carries a real identity

    @Test("the compiled commit is this checkout's actual commit")
    func compiledCommitMatchesGit() throws {
        guard let head = Self.run("/usr/bin/git",
                                  ["--no-optional-locks", "-C", Self.packageDirectory,
                                   "rev-parse", "--short=12", "HEAD"]) else {
            // A source tarball has no commit to compare against, and a suite that
            // went red there would be reporting on the checkout rather than the code.
            withKnownIssue("not a git checkout, so there is no commit to compare against",
                           isIntermittent: true) {
                Issue.record("skipped")
            }
            return
        }
        #expect(BuildInfo.current.commit == head,
                "the build identity should be generated from this checkout, not baked in")
        #expect(BuildInfo.current.commit != "unknown")
        #expect(BuildInfo.current.commit != "unavailable")
    }

    @Test("the compiled dirty flag matches the tree")
    func compiledDirtyMatchesGit() throws {
        var status: Int32 = 0
        guard let porcelain = Self.run("/usr/bin/git",
                                       ["--no-optional-locks", "-C", Self.packageDirectory,
                                        "status", "--porcelain"], status: &status),
              status == 0 else { return }
        #expect(BuildInfo.current.dirty == !porcelain.isEmpty)
    }

    @Test("the compiled version is the app's version")
    func compiledVersionMatchesPlist() throws {
        let plist = "\(Self.packageDirectory)/Apps/Proctor/Info.plist"
        guard let version = Self.run("/usr/libexec/PlistBuddy",
                                     ["-c", "Print :CFBundleShortVersionString", plist]) else { return }
        #expect(BuildInfo.current.version == version,
                "one source for the release line, or the binary and the release can disagree")
    }

    // MARK: - A2: no path produces a null, and a missing commit says which kind

    @Test("outside a git checkout the commit is unknown and everything else is real")
    func withoutGitTheIdentityIsStillReal() throws {
        let root = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.writePlist(version: "9.9.9", into: root)

        let generated = Self.generator(outputDirectory: root.appendingPathComponent("out").path,
                                       packageDirectory: root.path)
        let text = try #require(generated, "the generator must produce a file even with no git")
        #expect(text.contains(#"static let commit = "unknown""#))
        #expect(text.contains("static let dirty = false"))
        #expect(text.contains(#"static let version = "9.9.9""#),
                "the version comes from the plist and does not depend on git")
    }

    @Test("a repository git cannot answer for reads unavailable, not unknown")
    func brokenRepositoryIsUnavailable() throws {
        let root = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.writePlist(version: "9.9.9", into: root)
        // An initialised repository with no commits: git is here and cannot answer,
        // which is a different situation from "this is not a checkout" and calls for
        // a different response from whoever reads it.
        Self.run("/usr/bin/git", ["init", "-q", root.path])

        let generated = Self.generator(outputDirectory: root.appendingPathComponent("out").path,
                                       packageDirectory: root.path)
        let text = try #require(generated)
        #expect(text.contains(#"static let commit = "unavailable""#))
        #expect(text.contains("static let dirty = false"))
    }

    @Test("a package path containing spaces is handled")
    func pathWithSpaces() throws {
        let root = try Self.temporaryDirectory().appendingPathComponent("a dir with spaces")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }
        try Self.writePlist(version: "9.9.9", into: root)

        let generated = Self.generator(outputDirectory: root.appendingPathComponent("out").path,
                                       packageDirectory: root.path)
        let text = try #require(generated, "an unquoted path would split and write nothing")
        #expect(text.contains(#"static let version = "9.9.9""#))
    }

    @Test("the descriptor is never empty, whatever the inputs")
    func descriptorIsNeverEmpty() {
        for commit in ["e1f6cbf4fd1c", "unknown", "unavailable"] {
            for dirty in [true, false] {
                for configuration in ["debug", "release"] {
                    let identity = BuildIdentity(version: "0.1.0", commit: commit, dirty: dirty,
                                                 configuration: configuration, builtAt: nil)
                    #expect(!identity.descriptor.isEmpty)
                    #expect(identity.descriptor.hasPrefix("0.1.0+"))
                }
            }
        }
    }

    // MARK: - A3: each field answers its own question

    @Test("two commits are two descriptors")
    func differentCommitsDifferentDescriptors() {
        let one = BuildIdentity(version: "0.1.0", commit: "aaaaaaaaaaaa", dirty: false,
                                configuration: "release", builtAt: nil)
        let two = BuildIdentity(version: "0.1.0", commit: "bbbbbbbbbbbb", dirty: false,
                                configuration: "release", builtAt: nil)
        #expect(one.descriptor != two.descriptor)
        #expect(one.descriptor == "0.1.0+aaaaaaaaaaaa")
    }

    @Test("a dirty tree is not the commit it was built from")
    func dirtyIsDistinct() {
        let clean = BuildIdentity(version: "0.1.0", commit: "aaaaaaaaaaaa", dirty: false,
                                  configuration: "release", builtAt: nil)
        let dirty = BuildIdentity(version: "0.1.0", commit: "aaaaaaaaaaaa", dirty: true,
                                  configuration: "release", builtAt: nil)
        #expect(clean.descriptor != dirty.descriptor)
        #expect(dirty.descriptor == "0.1.0+aaaaaaaaaaaa.dirty")
    }

    @Test("debug and release are not the same program")
    func configurationIsDistinct() {
        let release = BuildIdentity(version: "0.1.0", commit: "aaaaaaaaaaaa", dirty: false,
                                    configuration: "release", builtAt: nil)
        let debug = BuildIdentity(version: "0.1.0", commit: "aaaaaaaaaaaa", dirty: false,
                                  configuration: "debug", builtAt: nil)
        #expect(release.descriptor != debug.descriptor)
        #expect(debug.descriptor == "0.1.0+aaaaaaaaaaaa.debug")
        #expect(release.descriptor == "0.1.0+aaaaaaaaaaaa",
                "a clean release build carries no suffix, so every suffix is an abnormal state")
    }

    @Test("two builds of one clean commit are one program, separated only by when")
    func sameCodeSameDescriptor() {
        let monday = BuildIdentity(version: "0.1.0", commit: "aaaaaaaaaaaa", dirty: false,
                                   configuration: "release", builtAt: "2026-08-01T09:00:00Z")
        let friday = BuildIdentity(version: "0.1.0", commit: "aaaaaaaaaaaa", dirty: false,
                                   configuration: "release", builtAt: "2026-09-01T09:00:00Z")
        #expect(monday.descriptor == friday.descriptor,
                "the descriptor identifies the program, and these are the same program")
        #expect(monday.builtAt != friday.builtAt,
                "the build event is what separates them, and that is builtAt's whole job")
    }

    // MARK: - A4: builtAt describes the running image

    @Test("builtAt reads a named file's date, and is nil when it cannot")
    func builtAtReadsThePath() throws {
        let root = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("binary")
        try Data("one".utf8).write(to: file)

        let resolved = try #require(BuildInfo.builtAt(ofExecutableAt: file.path))
        #expect(resolved.hasSuffix("Z"), "ISO-8601 in UTC, so two machines can compare it")

        #expect(BuildInfo.builtAt(ofExecutableAt: root.appendingPathComponent("gone").path) == nil,
                "a date nobody can read is nil, never a fabricated one")
        #expect(BuildInfo.builtAt(ofExecutableAt: nil) == nil)
    }

    @Test("a captured identity does not change when the file on disk is replaced")
    func captureSurvivesAReplacement() throws {
        let root = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("binary")
        try Data("one".utf8).write(to: file)

        // What a process does at startup.
        let captured = BuildIdentity(version: "0.1.0", commit: "aaaaaaaaaaaa", dirty: false,
                                     configuration: "release",
                                     builtAt: BuildInfo.builtAt(ofExecutableAt: file.path))

        // What an upgrade does underneath it: the path now holds a different file
        // while this process is still the old image.
        try FileManager.default.removeItem(at: file)
        try Data("two is longer".utf8).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(3600)],
                                              ofItemAtPath: file.path)

        let nowOnDisk = BuildInfo.builtAt(ofExecutableAt: file.path)
        #expect(captured.builtAt != nowOnDisk,
                "the replacement must be visible on disk, or this test proves nothing")
        #expect(captured.builtAt == captured.builtAt,
                "and the captured value is stored, so what the process reports has not moved")
    }

    @Test("the running executable resolves to a real path")
    func runningExecutableResolves() throws {
        let path = try #require(BuildInfo.runningExecutablePath,
                                "without this, builtAt is nil for every process")
        #expect(path.hasPrefix("/"), "an absolute path, resolved from the running image")
        #expect(FileManager.default.fileExists(atPath: path))
    }

    // MARK: - A8: the build stays cheap

    @Test("running the generator twice does not rewrite the file")
    func generatorWritesOnlyOnChange() throws {
        let root = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.writePlist(version: "9.9.9", into: root)
        let outputDirectory = root.appendingPathComponent("out").path

        _ = Self.generator(outputDirectory: outputDirectory, packageDirectory: root.path)
        let generated = "\(outputDirectory)/BuildIdentityGenerated.swift"
        let first = try FileManager.default.attributesOfItem(atPath: generated)

        _ = Self.generator(outputDirectory: outputDirectory, packageDirectory: root.path)
        let second = try FileManager.default.attributesOfItem(atPath: generated)

        // Inode rather than date: the write is a `mv`, so a rewrite replaces the file.
        // If this ever regresses, every build in the package recompiles Core and
        // everything downstream, for a value that did not change.
        #expect((first[.systemFileNumber] as? NSNumber) == (second[.systemFileNumber] as? NSNumber),
                "an unchanged tree must leave the generated file alone")
        #expect((first[.modificationDate] as? Date) == (second[.modificationDate] as? Date))
    }

    // MARK: - A6: the release names cannot drift

    private static func checkRelease(tag: String, plistVersion: String,
                                     changelog: String) throws -> Int32 {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try writePlist(version: plistVersion, into: root)
        let changelogPath = root.appendingPathComponent("CHANGELOG.md")
        try changelog.write(to: changelogPath, atomically: true, encoding: .utf8)

        var status: Int32 = -1
        _ = run("/bin/bash", ["\(packageDirectory)/scripts/check-release-version.sh", tag],
                environment: ["PROCTOR_PLIST": root.appendingPathComponent("Apps/Proctor/Info.plist").path,
                              "PROCTOR_CHANGELOG": changelogPath.path],
                status: &status)
        return status
    }

    private static let realNotes = """
    ## [1.2.3] - 2026-08-15

    ### Added

    - A thing worth telling somebody about.

    ## [1.2.2] - 2026-08-01
    """

    @Test("a tag, a version and real notes that agree pass")
    func releaseNamesAgree() throws {
        #expect(try Self.checkRelease(tag: "v1.2.3", plistVersion: "1.2.3",
                                      changelog: Self.realNotes) == 0)
    }

    @Test("a tag missing its v prefix fails rather than passing on a technicality")
    func tagWithoutVPrefixFails() throws {
        // The tags are `v1.2.3` and the plist holds `1.2.3`. A check comparing them
        // directly can never pass, which is how a guard written the obvious way blocks
        // every release instead of catching the one that is wrong.
        #expect(try Self.checkRelease(tag: "1.2.3", plistVersion: "1.2.3",
                                      changelog: Self.realNotes) != 0)
    }

    @Test("a tag naming a different version than the app fails")
    func tagDisagreesWithPlist() throws {
        #expect(try Self.checkRelease(tag: "v1.2.4", plistVersion: "1.2.3",
                                      changelog: Self.realNotes) != 0)
    }

    @Test("a version with no CHANGELOG section fails")
    func missingChangelogSectionFails() throws {
        #expect(try Self.checkRelease(tag: "v1.2.3", plistVersion: "1.2.3",
                                      changelog: "## [1.2.2] - 2026-08-01\n\n- older\n") != 0)
    }

    @Test("a CHANGELOG section with a heading and nothing under it fails")
    func blankChangelogSectionFails() throws {
        // The one `test -s` cannot catch: an empty section extracts to a single
        // newline, which is a non-empty file, so a release would ship blank notes.
        #expect(try Self.checkRelease(tag: "v1.2.3", plistVersion: "1.2.3",
                                      changelog: "## [1.2.3] - 2026-08-15\n\n## [1.2.2] - 2026-08-01\n\n- older\n") != 0)
    }

    @Test("a heading that only matches as a regex is not this version's section")
    func nearMissHeadingIsNotAMatch() throws {
        // Matching `## [1.2.3]` as a regular expression makes the dots match any
        // character, so this heading would win the slice and a release with no notes
        // of its own would pass on somebody else's.
        let changelog = "## [1x2y3] - 2026-08-15\n\n- notes belonging to something else\n"
        #expect(try Self.checkRelease(tag: "v1.2.3", plistVersion: "1.2.3",
                                      changelog: changelog) != 0)
    }

    @Test("a long section passes rather than tripping on a broken pipe")
    func longSectionStillPasses() throws {
        // `printf ... | grep -q` would exit at the first match and can SIGPIPE the
        // writer, which under `pipefail` reports failure for a section that is fine.
        // The bigger the section, the likelier it is. There is no pipe now; this is
        // the assertion that keeps it that way.
        let body = (1...400).map { "- entry number \($0), with enough text to fill a pipe buffer several times over.\n" }.joined()
        let changelog = "## [1.2.3] - 2026-08-15\n\n\(body)\n## [1.2.2] - 2026-08-01\n\n- older\n"
        #expect(try Self.checkRelease(tag: "v1.2.3", plistVersion: "1.2.3",
                                      changelog: changelog) == 0)
    }

    @Test("the generator writes an identity even when it can read nothing at all")
    func generatorNeverFails() throws {
        // Its one promise. Anything that aborts before the write leaves Core with no
        // generated source, and the build then fails on an undefined symbol — which
        // is the opposite of degrading to a sentinel.
        let root = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        // No Info.plist, no git, nothing.
        let generated = Self.generator(outputDirectory: root.appendingPathComponent("out").path,
                                       packageDirectory: root.path)
        let text = try #require(generated, "a file must exist even with nothing to read")
        #expect(text.contains(#"static let version = "unknown""#))
        #expect(text.contains(#"static let commit = "unknown""#))
        #expect(text.contains("static let dirty = false"))
        #expect(text.contains("enum BuildIdentityGenerated"),
                "and it must still be compilable Swift")
    }

    @Test("nothing read from a file can escape into the generated Swift")
    func generatedValuesAreSanitised() throws {
        let root = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        // A version carrying a quote and a newline would otherwise close the string
        // literal and put whatever follows into the source as code.
        try Self.writePlist(version: "1.0\" + evil() + \"", into: root)

        let generated = Self.generator(outputDirectory: root.appendingPathComponent("out").path,
                                       packageDirectory: root.path)
        let text = try #require(generated)
        #expect(!text.contains("evil()"))
        // Exactly two quotes on the version line: the ones opening and closing it.
        let versionLine = try #require(text.split(separator: "\n")
            .first { $0.contains("static let version") })
        #expect(versionLine.filter { $0 == "\"" }.count == 2, "found: \(versionLine)")
    }

    @Test("the generator leaves no temporary file for the compiler to pick up")
    func generatorLeavesNoStrays() throws {
        let root = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.writePlist(version: "9.9.9", into: root)
        let outputDirectory = root.appendingPathComponent("out")
        _ = Self.generator(outputDirectory: outputDirectory.path, packageDirectory: root.path)
        _ = Self.generator(outputDirectory: outputDirectory.path, packageDirectory: root.path)

        // Everything in this directory is handed to the compiler, so a second Swift
        // file here is a second declaration of the same enum.
        let contents = try FileManager.default.contentsOfDirectory(atPath: outputDirectory.path)
        #expect(contents == ["BuildIdentityGenerated.swift"], "found: \(contents)")
    }
}
