import Foundation
import Testing
@testable import ProctorCore

// PRO-0023 — finding Obscura without running it.
//
// The lookup is pure: the caller supplies the PATH, the home directory and one
// predicate, and this decides. That is what makes the launchd case testable at
// all, because the whole point is that the agent does NOT inherit a login shell's
// PATH, and a test that asked the real environment would prove nothing about a
// machine other than this one.
//
// Not testable here: that the real predicate's regular-file check behaves as
// documented against a live filesystem, and that nothing in this path ever spawns
// a process. The second is a property of there being no such code rather than
// something a test can witness.

@Suite("Tool locator")
struct ToolLocatorTests {

    private static let home = "/Users/tester"
    private static let extras = ObscuraTool.extraDirectories

    /// A launchd agent's PATH. Not a hypothetical: this is what the agent gets,
    /// and it is why the explicit directory list exists.
    private static let launchdPath = "/usr/bin:/bin:/usr/sbin:/sbin"

    private func locate(_ present: Set<String>,
                        path: String? = launchdPath,
                        companions: [String] = ObscuraTool.companions) -> ToolPresence {
        ToolLocator.locate(binary: ObscuraTool.binary, companions: companions,
                           pathEnvironment: path, home: Self.home,
                           extraDirectories: Self.extras,
                           isExecutable: { present.contains($0) })
    }

    @Test("PATH is searched before the explicit list, and the found path is reported")
    func pathEntriesComeFirst() {
        let candidates = ToolLocator.candidatePaths(binary: "obscura",
                                                    pathEnvironment: "/usr/bin:/bin",
                                                    home: Self.home,
                                                    extraDirectories: Self.extras)
        #expect(candidates.first == "/usr/bin/obscura")
        #expect(candidates[1] == "/bin/obscura")
        #expect(candidates[2] == "/opt/homebrew/bin/obscura")

        let found = locate(["/bin/obscura", "/bin/obscura-worker",
                            "/opt/homebrew/bin/obscura", "/opt/homebrew/bin/obscura-worker"],
                           path: "/usr/bin:/bin")
        #expect(found.available)
        #expect(found.path == "/bin/obscura")
    }

    @Test("a launchd PATH still finds a Homebrew install")
    func aLaunchdPathStillFindsHomebrew() {
        let found = locate(["/opt/homebrew/bin/obscura", "/opt/homebrew/bin/obscura-worker"])
        #expect(found.available)
        #expect(found.path == "/opt/homebrew/bin/obscura")
        #expect(found.missingCompanions.isEmpty)
    }

    @Test("~ is expanded from the supplied home and never survives into the search list")
    func tildeIsExpandedFromTheSuppliedHome() {
        let found = locate(["/Users/tester/.local/bin/obscura",
                            "/Users/tester/.local/bin/obscura-worker"])
        #expect(found.path == "/Users/tester/.local/bin/obscura")

        let candidates = ToolLocator.candidatePaths(binary: "obscura",
                                                    pathEnvironment: Self.launchdPath,
                                                    home: Self.home, extraDirectories: Self.extras)
        #expect(candidates.contains("/Users/tester/.cargo/bin/obscura"))
        #expect(!candidates.contains { $0.contains("~") })
    }

    @Test("nothing found reports everywhere it looked, in order and without repeats")
    func nothingFoundReportsEverywhereItLooked() {
        // A PATH that repeats two of the explicit directories, plus a relative
        // entry, which is a real thing to find in a PATH and never a place to
        // look for a tool.
        let path = "/usr/bin:/opt/homebrew/bin:./bin:/usr/local/bin/"
        let found = locate([], path: path)
        #expect(!found.available)
        #expect(found.path == nil)
        #expect(found.missingCompanions.isEmpty)

        #expect(found.searched == ["/usr/bin/obscura",
                                   "/opt/homebrew/bin/obscura",
                                   "/usr/local/bin/obscura",
                                   "/Users/tester/.local/bin/obscura",
                                   "/Users/tester/.cargo/bin/obscura",
                                   "/opt/local/bin/obscura"])
        #expect(Set(found.searched).count == found.searched.count)
    }

    @Test("a candidate the predicate rejects is skipped and the search continues")
    func aRejectedCandidateIsSkipped() {
        // The predicate means "an executable regular file", and a candidate it
        // rejects — not there, not executable, or a directory carrying the execute
        // bit — must not end the search. The directory case is checked against a
        // real filesystem in ProctorAgentTests, where the real predicate lives.
        let found = locate(["/usr/bin/obscura-worker",
                            "/usr/local/bin/obscura", "/usr/local/bin/obscura-worker"])
        #expect(found.available)
        #expect(found.path == "/usr/local/bin/obscura")
        #expect(found.searched.first == "/usr/bin/obscura")
    }

    @Test("a half install is available and says what is missing beside it")
    func aHalfInstallIsAvailableAndSaysWhatIsMissing() {
        let half = locate(["/opt/homebrew/bin/obscura"])
        #expect(half.available)
        #expect(half.path == "/opt/homebrew/bin/obscura")
        #expect(half.missingCompanions == ["obscura-worker"])
    }

    @Test("a complete install wins over an earlier incomplete one")
    func aCompleteInstallWinsOverAnEarlierHalfOne() {
        // First-hit-wins alone would report a permanent half install because of a
        // stray copy on an early PATH entry, while the real one sat unused two
        // directories down.
        let found = locate(["/usr/bin/obscura",
                            "/Users/tester/.local/bin/obscura",
                            "/Users/tester/.local/bin/obscura-worker"])
        #expect(found.path == "/Users/tester/.local/bin/obscura")
        #expect(found.missingCompanions.isEmpty)
    }

    // MARK: - What is said about it

    @Test("the absence carries no shell command anywhere in it")
    func theAbsenceCarriesNoShellCommand() {
        // The finding that changed this feature: data in an MCP result is an
        // action surface. A model holding a shell that is handed a curl of an
        // unsigned tarball runs it, which defers the fetch-and-execute rather than
        // avoiding it. So the commands live in the app and nowhere else.
        let absence = ObscuraTool.absence
        let text = [absence.tool, absence.missing, absence.docs, absence.askThePerson]
            .joined(separator: " ")
        for command in ["curl", "tar ", "sudo", "brew ", "&&", "$(", "chmod", "mv "] {
            #expect(!text.contains(command), "\(command) leaked into the tool surface")
        }
        #expect(absence.docs == ObscuraTool.docs)
        #expect(absence.askThePerson.contains("Proctor has no way to install it"))
        // Says what the answer is a claim about: a launchd agent's environment is
        // not the shell the reader will type into.
        #expect(absence.missing.contains("launchd"))
    }

    @Test("install commands are architecture-specific and land both executables together")
    func installCommandsAreArchitectureSpecific() {
        let silicon = ObscuraTool.installCommands(architecture: .appleSilicon)
        let intel = ObscuraTool.installCommands(architecture: .intel)
        #expect(silicon.contains { $0.contains("obscura-aarch64-macos.tar.gz") })
        #expect(intel.contains { $0.contains("obscura-x86_64-macos.tar.gz") })
        #expect(!silicon.contains { $0.contains("x86_64") })

        // Both executables, one directory, and that directory is one the locator
        // actually searches — otherwise the install succeeds and Proctor still
        // cannot see it.
        let move = try! #require(silicon.last)
        #expect(move.contains("obscura obscura-worker"))
        #expect(move.contains(ObscuraTool.installDestination))
        #expect(ObscuraTool.extraDirectories.contains(ObscuraTool.installDestination))
    }
}
