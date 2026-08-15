import Foundation

// Where `simctl` is, established without running anything.
//
// `xcrun simctl` ships with Xcode rather than with macOS, so a machine without
// Xcode has no iOS lane at all. That belongs in the health report, not in a
// runtime surprise part-way through a campaign.
//
// This follows `ToolLocator`'s rule — **detection reads the filesystem and never
// executes a binary** — for the same reason, one step removed. `simctl` itself is
// later run at the absolute path resolved here, which is what `/usr/bin/sdef` and
// `/usr/bin/shortcuts` already do in this agent. The distinction that keeps the
// rule intact: detection executes nothing, and execution only ever targets a path
// under a root-owned developer directory, never a user-writable PATH entry.
//
// Everything is injected — the environment, the symlink read, the executable
// test — so both answers are provable on a machine in either state.

public enum SimctlLocator {

    /// The last-resort developer directory. Named rather than searched, because a
    /// wildcard over `/Applications` would make "which Xcode" unanswerable.
    public static let defaultDeveloperDirectory = "/Applications/Xcode.app/Contents/Developer"

    /// The symlink `xcode-select` maintains. Root-owned, which is what makes
    /// following it safe: a user-writable path could be redirected at a binary
    /// this process would then run holding Accessibility.
    public static let selectLink = "/var/db/xcode_select_link"

    /// `simctl`'s path inside a developer directory.
    public static func simctlPath(inDeveloperDirectory directory: String) -> String {
        directory + "/usr/bin/simctl"
    }

    /// The developer directories to try, in order, and where each came from.
    ///
    /// `DEVELOPER_DIR` first because that is what `xcrun` itself honours, then the
    /// `xcode-select` link, then the conventional location. Duplicates are dropped
    /// with their order preserved, so a machine where all three agree reports one
    /// candidate rather than three.
    public static func candidateDirectories(environment: [String: String],
                                            readSymlink: (String) -> String?) -> [String] {
        var out: [String] = []
        var seen: Set<String> = []
        func add(_ raw: String?) {
            guard var dir = raw, !dir.isEmpty else { return }
            while dir.count > 1 && dir.hasSuffix("/") { dir.removeLast() }
            guard dir.hasPrefix("/"), seen.insert(dir).inserted else { return }
            out.append(dir)
        }
        add(environment["DEVELOPER_DIR"])
        add(readSymlink(selectLink))
        add(defaultDeveloperDirectory)
        return out
    }

    /// Find `simctl`, reporting every path that was checked.
    ///
    /// `searched` is on the wire for the same reason `ToolLocator`'s is: somebody
    /// whose own shell finds `simctl` while Proctor does not can only settle it by
    /// comparing paths. A launchd agent inherits no login shell's environment, so
    /// `DEVELOPER_DIR` being absent here while present in a terminal is a real and
    /// otherwise undiagnosable difference.
    public static func locate(environment: [String: String],
                              readSymlink: (String) -> String?,
                              isExecutable: (String) -> Bool) -> ToolPresence {
        let directories = candidateDirectories(environment: environment, readSymlink: readSymlink)
        let searched = directories.map(simctlPath(inDeveloperDirectory:))
        for path in searched where isExecutable(path) {
            return ToolPresence(tool: "simctl", available: true, path: path, searched: searched)
        }
        return ToolPresence(tool: "simctl", available: false, path: nil, searched: searched)
    }

    /// The real probe: the process environment, a real symlink read, and an
    /// executable-regular-file test. `FileManager.isExecutableFile` answers true
    /// for a directory carrying the execute bit, so the directory case is excluded
    /// explicitly — the same trap `ToolLocator` documents.
    public static func onDisk() -> ToolPresence {
        locate(environment: ProcessInfo.processInfo.environment,
               readSymlink: { try? FileManager.default.destinationOfSymbolicLink(atPath: $0) },
               isExecutable: { path in
                   var isDirectory: ObjCBool = false
                   let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
                   return exists && !isDirectory.boolValue
                       && FileManager.default.isExecutableFile(atPath: path)
               })
    }

    /// What a caller is told when there is no lane here at all. No command text,
    /// following the rule `ToolAbsence` already sets: a model holding a shell that
    /// is handed an install command will run it, and Proctor installs nothing.
    public static let absence = ToolAbsence(
        tool: "simctl",
        missing: "Xcode is not installed, or its command-line tools are not the ones selected, so "
               + "there is no iOS Simulator lane on this machine.",
        docs: "https://developer.apple.com/xcode/",
        askThePerson: "simctl ships inside Xcode rather than with macOS. Ask the person at this Mac "
                    + "to install Xcode from the App Store and select it, then call proctor_doctor "
                    + "again — the iOS actions stay unavailable until it is there.")
}
