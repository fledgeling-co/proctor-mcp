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
    ///
    /// `unsetting` REMOVES keys from the child's environment, which merging cannot do and
    /// which the sealed-git tests need — see `sealedGitRemovals`.
    @discardableResult
    private static func run(_ launchPath: String, _ arguments: [String],
                            environment: [String: String]? = nil,
                            unsetting: [String] = [],
                            status: UnsafeMutablePointer<Int32>? = nil) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments
        if environment != nil || !unsetting.isEmpty {
            var child = ProcessInfo.processInfo.environment
            for key in unsetting { child.removeValue(forKey: key) }
            if let environment { child.merge(environment) { _, new in new } }
            process.environment = child
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

    /// The three variables that redirect a git call away from the directory it was given.
    /// They override `-C`, so a test process that inherited one would have both the test
    /// and the generator script reading a repository other than the path they were handed.
    ///
    /// Removed rather than blanked, because measured: `GIT_DIR= git -C <repo> rev-parse HEAD`
    /// fails with `fatal: not a git repository: ''`. An empty string reads as set-and-empty,
    /// so blanking these would break every call instead of sealing it.
    private static let sealedGitRemovals = ["GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE"]

    /// Inherited global and system config, out of reach: identity, hooks, signing and
    /// commit templates. Measured: with these set, `git config --get user.email` exits
    /// non-zero even on a machine whose global config sets one. Overrides work here where
    /// they do not for the three above, because git reads these as paths and `/dev/null`
    /// is a real, empty file.
    private static let sealedGitOverrides = ["GIT_CONFIG_GLOBAL": "/dev/null",
                                             "GIT_CONFIG_SYSTEM": "/dev/null"]

    /// Run a git command against a repository the test built, with nothing inherited from
    /// the machine able to reach it.
    @discardableResult
    private static func sealedGit(_ arguments: [String],
                                  status: UnsafeMutablePointer<Int32>? = nil) -> String? {
        run("/usr/bin/git", ["--no-optional-locks"] + arguments,
            environment: sealedGitOverrides, unsetting: sealedGitRemovals, status: status)
    }

    private static func generator(outputDirectory: String, packageDirectory: String,
                                  environment: [String: String]? = nil,
                                  unsetting: [String] = []) -> String? {
        run("/bin/sh", ["\(Self.packageDirectory)/scripts/gen-build-identity.sh",
                        outputDirectory, packageDirectory],
            environment: environment, unsetting: unsetting)
        let generated = "\(outputDirectory)/BuildIdentityGenerated.swift"
        return try? String(contentsOfFile: generated, encoding: .utf8)
    }

    /// The generator, run against a repository the test owns, with the same seal applied.
    /// The script shells out to git itself and inherits this process's environment, so
    /// sealing only the test's own calls would seal nothing.
    private static func sealedGenerator(outputDirectory: String, packageDirectory: String) -> String? {
        generator(outputDirectory: outputDirectory, packageDirectory: packageDirectory,
                  environment: sealedGitOverrides, unsetting: sealedGitRemovals)
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
    //
    // What these deliberately do NOT assert, and why, because the obvious version was
    // tried and shipped and had to be removed (PRO-0043):
    //
    // The compiled constant is written by a SwiftPM prebuild command. A prebuild command
    // is scheduled every build, but a build llbuild considers fully up to date runs no
    // commands at all — measured: `swift build` prints "Build complete! (0.11s)" and the
    // generator does not execute, over repeated builds. `swift build` and `swift test`
    // also keep separate build plans, so whichever ran last decides freshness.
    //
    // So `BuildInfo.current` describes the checkout as it was at some earlier build, not
    // as it is now. Comparing it against live `git rev-parse HEAD` or live `git status`
    // asserts that SwiftPM rescheduled a command, which is not a property of this feature
    // and is false by construction after any amend or rebase that moves HEAD without
    // touching a source file. That assertion turned the merge gate red during ordinary
    // rebases, which is how a person learns to ignore a red gate.
    //
    // What survives here is what a stale cache cannot break. What needs both sides of the
    // comparison is tested against a repository the test builds itself, below.

    @Test("the compiled commit is a real commit, not a sentinel or a stub")
    func compiledCommitIsARealCommit() throws {
        guard Self.run("/usr/bin/git",
                       ["--no-optional-locks", "-C", Self.packageDirectory,
                        "rev-parse", "--short=12", "HEAD"]) != nil else {
            // A source tarball has no commit at all, and a suite that went red there
            // would be reporting on the checkout rather than the code. The same skip
            // covers a checkout git declines to answer for — dubious ownership, an
            // unreadable .git — where "unavailable" is the generator working correctly.
            withKnownIssue("""
                           git does not answer for this directory, so the generator had \
                           nothing to resolve and a sentinel is the right answer
                           """,
                           isIntermittent: true) {
                Issue.record("skipped")
            }
            return
        }
        // The live call above is a PRECONDITION — proof that git answers here — and its
        // value is deliberately never compared against the compiled one.
        let commit = BuildInfo.current.commit
        #expect(commit != "unknown")
        #expect(commit != "unavailable",
                "git answers for this directory, so a build here should have resolved a commit")
        // Twelve OR MORE: `--short=12` is a minimum width and git lengthens the
        // abbreviation when twelve characters would be ambiguous. An exact-width check
        // passes today and reddens years later in a bigger repository, for no defect.
        #expect(commit.count >= 12 && commit.allSatisfy { $0.isHexDigit && !$0.isUppercase },
                """
                expected a short sha, got \(commit) — if this looks stale rather than \
                malformed, the generated identity predates this checkout: rm -rf .build/plugins
                """)
    }

    @Test("a sentinel commit is never also dirty")
    func sentinelCommitIsNeverDirty() {
        // The generator can only reach dirty = true after resolving a real commit, so a
        // sentinel paired with a dirty flag is a state it cannot produce and means the
        // generated file came from something other than that script.
        //
        // This replaces a comparison against the live working tree, which could not hold:
        // the compiled flag records the tree at the last generator run and the test can
        // only see the tree now, so the two agreed by coincidence and the assertion went
        // red whenever somebody had a file open.
        if BuildInfo.current.commit == "unknown" || BuildInfo.current.commit == "unavailable" {
            #expect(BuildInfo.current.dirty == false)
        }
    }

    @Test("the compiled version is a real release line, not a placeholder")
    func compiledVersionIsReal() throws {
        let plist = "\(Self.packageDirectory)/Apps/Proctor/Info.plist"
        guard Self.run("/usr/libexec/PlistBuddy",
                       ["-c", "Print :CFBundleShortVersionString", plist]) != nil else { return }
        // Precondition only. The plist's VALUE is deliberately not compared against the
        // compiled one, for the same reason as the commit above — and this test is where
        // that was learned the hard way. It survived a first review because a version only
        // moves at a release, which looked safe. Then changing the plist and changing it
        // back left the compiled constant at the intermediate value: the edit rescheduled
        // the generator, the revert did not, and the binary claimed 9.9.9 against a plist
        // reading 0.1.0. Same defect, and it fails in the direction that matters — after a
        // release is reverted or a version bump is rebased away.
        //
        // That the generator READS this plist is proven where the test owns the plist:
        // `withoutGitTheIdentityIsStillReal` and `pathWithSpaces` both write one and assert
        // the version that comes back. The release path is guarded separately by
        // `scripts/check-release-version.sh` (A6 below), so nothing that matters rested on
        // this comparison.
        let version = BuildInfo.current.version
        #expect(version != "unknown",
                """
                the plist is readable here, so a build in this checkout had a version to \
                read — if this looks stale rather than absent: rm -rf .build/plugins
                """)
        #expect(version.first?.isNumber == true,
                "a release line starts with a number, so a sentinel or a stray string shows up here")
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

    // MARK: - A1 (hermetic): the generator reads the checkout it is given
    //
    // Both sides of the comparison belong to the test here. That is the whole point: the
    // compiled constant cannot be compared against the live checkout (see the A1 note
    // above), but the generator's behaviour CAN be pinned exactly, by handing it a
    // repository this test created and knows the answer for.

    /// A repository the test owns: one commit, a clean tree, and an output directory that
    /// is a SIBLING of it rather than a child.
    ///
    /// The sibling is load-bearing. The generator writes its file into the output
    /// directory, so pointing that inside the repository leaves an untracked file behind
    /// and the run meant to observe a clean tree observes the test's own artefact instead,
    /// reporting dirty. The clean case would never have been measured.
    private static func makeRepository() throws -> (root: URL, repo: URL, out: URL, head: String) {
        let root = try temporaryDirectory()
        let repo = root.appendingPathComponent("repo")
        let out = root.appendingPathComponent("out")
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try writePlist(version: "9.9.9", into: repo)

        try #require(sealedGit(["init", "-q", repo.path]) != nil, "git init failed")
        // Local identity, because a commit needs one and the global config is sealed off.
        sealedGit(["-C", repo.path, "config", "user.email", "pro-0043@example.invalid"])
        sealedGit(["-C", repo.path, "config", "user.name", "PRO-0043 Test"])
        sealedGit(["-C", repo.path, "add", "-A"])
        // The plist is committed rather than left untracked, or the tree starts dirty and
        // the clean assertion below would be measuring the fixture, not the generator.
        try #require(sealedGit(["-C", repo.path, "commit", "-q", "-m", "initial"]) != nil,
                     "commit failed")
        let head = try #require(sealedGit(["-C", repo.path, "rev-parse", "--short=12", "HEAD"]),
                                "could not read the temporary repository's HEAD")
        try #require(!head.isEmpty)
        return (root, repo, out, head)
    }

    @Test("the generator writes the commit of the checkout it was handed")
    func generatorReadsTheCommitOfItsCheckout() throws {
        let fixture = try Self.makeRepository()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let text = try #require(Self.sealedGenerator(outputDirectory: fixture.out.path,
                                                     packageDirectory: fixture.repo.path))
        #expect(text.contains(#"static let commit = "\#(fixture.head)""#),
                "the generator should read this repository's HEAD, and nothing else's")
        #expect(text.contains(#"static let version = "9.9.9""#))
    }

    @Test("the generator tells a dirty tree from a clean one")
    func generatorSeesADirtyTree() throws {
        let fixture = try Self.makeRepository()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        // Clean first, in the same test, so what is measured is the FLIP rather than two
        // unrelated observations that happen to differ.
        let clean = try #require(Self.sealedGenerator(outputDirectory: fixture.out.path,
                                                      packageDirectory: fixture.repo.path))
        #expect(clean.contains("static let dirty = false"),
                "a committed tree with the generator writing outside it is clean")

        try Data("an edit nobody committed".utf8)
            .write(to: fixture.repo.appendingPathComponent("scratch.txt"))

        let dirty = try #require(Self.sealedGenerator(outputDirectory: fixture.out.path,
                                                      packageDirectory: fixture.repo.path))
        #expect(dirty.contains("static let dirty = true"),
                "an untracked file changes the build and belongs in the answer")
        #expect(dirty.contains(#"static let commit = "\#(fixture.head)""#),
                "dirtying a tree does not move HEAD, and the two fields answer different questions")
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

        // What a process does at startup, and what it read at the time. The
        // second binding is the whole test: the claim is that `captured` still
        // reports THIS value after the file underneath it changes, and a claim
        // about a value has to be pinned before the thing that might move it.
        let atStartup = BuildInfo.builtAt(ofExecutableAt: file.path)
        let captured = BuildIdentity(version: "0.1.0", commit: "aaaaaaaaaaaa", dirty: false,
                                     configuration: "release", builtAt: atStartup)

        // What an upgrade does underneath it: the path now holds a different file
        // while this process is still the old image.
        try FileManager.default.removeItem(at: file)
        try Data("two is longer".utf8).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(3600)],
                                              ofItemAtPath: file.path)

        let nowOnDisk = BuildInfo.builtAt(ofExecutableAt: file.path)
        #expect(captured.builtAt != nowOnDisk,
                "the replacement must be visible on disk, or this test proves nothing")
        // Found by scripts/campaign/cannotfail_swift.py: this line read
        // `captured.builtAt == captured.builtAt`, which is a stored property
        // compared to itself and cannot fail. It passed on a build where
        // `builtAt` re-read the path on every access, which is exactly the
        // regression the test is named after.
        #expect(captured.builtAt == atStartup,
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
