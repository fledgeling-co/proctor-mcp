import Foundation
import ProctorCore

// The installer is the only part of the shim that writes anything. It exists
// because macOS attributes a TCC grant to the responsible process, walking up
// the process ancestry: a helper spawned by an MCP host, or by node under npx,
// has the grant attributed to the host or to node, and one running from an npx
// temp path loses the responsibility chain outright. A launchd user agent is
// its own responsible process, so the grant attaches to a stable bundle
// identity and survives host changes and upgrades.

enum Installer {

    // MARK: - Paths

    private static var home: String { FileManager.default.homeDirectoryForCurrentUser.path }
    private static var plistPath: String { "\(home)/Library/LaunchAgents/\(Wire.agentLabel).plist" }
    private static var logDirectory: String { "\(home)/Library/Logs/Proctor" }
    private static var logPath: String { "\(logDirectory)/agent.log" }
    private static var socketDirectory: String {
        (Wire.socketPath as NSString).deletingLastPathComponent
    }

    private static var shimPath: String {
        if let path = Bundle.main.executablePath { return path }
        let argv0 = CommandLine.arguments.first ?? "proctor-shim"
        return (argv0 as NSString).isAbsolutePath
            ? argv0
            : FileManager.default.currentDirectoryPath + "/" + argv0
    }

    private static var searchedAppPaths: [String] {
        let beside = (shimPath as NSString).deletingLastPathComponent
        return [
            "\(beside)/Proctor.app",
            "/Applications/Proctor.app",
            "\(home)/Applications/Proctor.app"
        ]
    }

    private static func locateApp() -> String? {
        // The shim may itself be shipped inside the bundle it is looking for.
        if let range = shimPath.range(of: "/Proctor.app/") {
            let candidate = String(shimPath[shimPath.startIndex..<range.upperBound]).dropLast()
            if isDirectory(String(candidate)) { return String(candidate) }
        }
        return searchedAppPaths.first(where: isDirectory)
    }

    private static func agentBinary(inApp app: String) -> String {
        "\(app)/Contents/MacOS/proctor-agent"
    }

    private static func isDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    // MARK: - install

    static func install() -> Bool {
        guard let app = locateApp() else {
            print("proctor: could not find Proctor.app. Looked in:")
            for path in searchedAppPaths { print("  \(path)") }
            print("")
            print("Build or download Proctor.app, put it in /Applications, and run this again.")
            return false
        }
        let binary = agentBinary(inApp: app)
        guard FileManager.default.isExecutableFile(atPath: binary) else {
            print("proctor: found \(app) but no runnable agent at \(binary).")
            return false
        }
        print("proctor: found the app bundle at \(app)")

        // The agent binds the socket on first launch, so its parent directory
        // has to exist before launchd starts it.
        for directory in [socketDirectory, logDirectory, "\(home)/Library/LaunchAgents"] {
            do {
                try FileManager.default.createDirectory(atPath: directory,
                                                        withIntermediateDirectories: true)
            } catch {
                print("proctor: could not create \(directory): \(error.localizedDescription)")
                return false
            }
        }

        // Keep these keys in step with scripts/install.sh, which writes the
        // same job for a source build. The two are not copies of one routine —
        // the script builds, signs and copies the bundle and this only
        // registers one that already exists — but they must agree on the job.
        //
        // ProcessType Interactive keeps launchd from throttling CPU and I/O.
        // Without it a settling agent is quietly starved, which reads as flaky
        // waits rather than as a configuration problem.
        let plist: [String: Any] = [
            "Label": Wire.agentLabel,
            "ProgramArguments": [binary],
            "RunAtLoad": true,
            "KeepAlive": ["SuccessfulExit": false],
            "ProcessType": "Interactive",
            "StandardErrorPath": logPath
        ]
        do {
            let data = try PropertyListSerialization.data(fromPropertyList: plist,
                                                          format: .xml, options: 0)
            try data.write(to: URL(fileURLWithPath: plistPath), options: .atomic)
        } catch {
            print("proctor: could not write \(plistPath): \(error.localizedDescription)")
            return false
        }
        print("proctor: wrote \(plistPath)")

        let target = "gui/\(getuid())"
        // A previous load is booted out first; failure here means it was not loaded.
        _ = launchctl(["bootout", "\(target)/\(Wire.agentLabel)"])

        let bootstrap = launchctl(["bootstrap", target, plistPath])
        if bootstrap.status != 0 {
            print("proctor: launchctl bootstrap failed (\(bootstrap.status)): \(bootstrap.output)")
            return false
        }
        let kickstart = launchctl(["kickstart", "-k", "\(target)/\(Wire.agentLabel)"])
        if kickstart.status != 0 {
            print("proctor: launchctl kickstart failed (\(kickstart.status)): \(kickstart.output)")
        }
        print("proctor: loaded \(Wire.agentLabel)")

        let up = waitForSocket(seconds: 10)
        if up {
            print("proctor: the agent answered on \(Wire.socketPath)")
        } else {
            print("proctor: the agent did not answer on \(Wire.socketPath) within 10 seconds.")
            print("         Check \(logPath), then run `proctor-shim status`.")
        }

        printHostConfiguration()
        printGrantsNote()
        return up
    }

    // MARK: - uninstall

    static func uninstall() -> Bool {
        var ok = true
        let result = launchctl(["bootout", "gui/\(getuid())/\(Wire.agentLabel)"])
        if result.status == 0 {
            print("proctor: unloaded \(Wire.agentLabel)")
        } else {
            print("proctor: \(Wire.agentLabel) was not loaded")
        }

        if FileManager.default.fileExists(atPath: plistPath) {
            do {
                try FileManager.default.removeItem(atPath: plistPath)
                print("proctor: removed \(plistPath)")
            } catch {
                print("proctor: could not remove \(plistPath): \(error.localizedDescription)")
                ok = false
            }
        } else {
            print("proctor: no plist at \(plistPath)")
        }

        print("")
        print("The Accessibility and Screen Recording grants for Proctor remain in place.")
        print("An installer cannot revoke a TCC grant. Remove them yourself in")
        print("System Settings > Privacy & Security > Accessibility and > Screen Recording.")
        return ok
    }

    // MARK: - status

    static func status() -> Bool {
        let installed = FileManager.default.fileExists(atPath: plistPath)
        let loaded = launchctl(["print", "gui/\(getuid())/\(Wire.agentLabel)"]).status == 0
        let reachable = probeSocket()

        print("Proctor agent")
        print("  shim:      \(shimPath) (\(ShimVersion.value))")
        print("  app:       \(locateApp() ?? "not found")")
        print("  plist:     \(installed ? plistPath : "not installed")")
        print("  launchd:   \(loaded ? "loaded" : "not loaded")")
        print("  socket:    \(Wire.socketPath)")
        print("  reachable: \(reachable ? "yes" : "no")")
        print("  remote:    off by default — `proctor-shim serve --remote` for HTTP access")

        if !reachable {
            print("")
            if installed {
                print("The agent is installed but not answering. Check \(logPath),")
                print("then run `proctor-shim install` again to reload it.")
            } else {
                print("Run `proctor-shim install` to install and load the agent, then grant")
                print("Accessibility and Screen Recording to Proctor in System Settings.")
            }
        }
        return reachable
    }

    // MARK: - Helpers

    private static func printHostConfiguration() {
        print("")
        print("Add Proctor to an MCP host:")
        print("")
        print("  claude mcp add proctor -- \(shimPath) serve")
        print("")
        print("Or, for a host that takes an mcpServers block:")
        print("")
        print("""
              {
                "mcpServers": {
                  "proctor": {
                    "command": "\(shimPath)",
                    "args": ["serve"]
                  }
                }
              }
              """)
    }

    private static func printGrantsNote() {
        print("")
        print("Then grant, in System Settings > Privacy & Security:")
        print("  Accessibility     -> Proctor")
        print("  Screen Recording  -> Proctor")
        print("")
        print("The grants attach to Proctor, not to this shim or to the MCP host. Confirm with")
        print("`proctor-shim status` or the proctor_doctor tool.")
    }

    private static func waitForSocket(seconds: Int) -> Bool {
        let deadline = Date().addingTimeInterval(TimeInterval(seconds))
        while Date() < deadline {
            if probeSocket() { return true }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return probeSocket()
    }

    private static func probeSocket() -> Bool {
        let client = SocketClient()
        defer { client.disconnect() }
        do {
            try client.connect()
            return true
        } catch {
            return false
        }
    }

    @discardableResult
    private static func launchctl(_ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return (-1, "could not run launchctl: \(error.localizedDescription)")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (process.terminationStatus, output)
    }
}
