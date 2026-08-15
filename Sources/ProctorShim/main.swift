import Foundation
import ProctorCore

// Argument dispatch. Everything here is either forwarding (serve) or the one
// thing the shim is allowed to write (install).

let usage = """
proctor-shim \(BuildInfo.current.descriptor) — the permissionless MCP front end for Proctor.

Usage:
  proctor-shim [serve]     Speak MCP over stdio and forward tool calls to the agent.
  proctor-shim serve --remote [--host H] [--port N] [--token T]
                           Speak MCP over HTTP (POST /mcp) for remote access.
                           Binds 127.0.0.1:8787 by default. A non-loopback --host
                           requires a token. The token is read from --token or the
                           PROCTOR_MCP_TOKEN environment variable; with neither, a
                           loopback bind runs unauthenticated for local use.
  proctor-shim serve --profile P
                           Advertise a trimmed tool surface: core, ax, scripting or
                           full (default). Also read from PROCTOR_PROFILE. Nested:
                           ax ⊂ core ⊂ scripting ⊂ full. Trims discovery only —
                           tools/call still accepts any tool.
  proctor-shim install     Install and load the launchd user agent, then print host config.
  proctor-shim uninstall   Unload the agent and remove its launchd plist.
  proctor-shim status      Report whether the agent is reachable. Exits 0 when it is.
  proctor-shim --version   Print the version.
  proctor-shim --help      Print this.

The shim holds no permissions and keeps no state. Accessibility and Screen Recording
are granted to Proctor itself, which runs as its own launchd process so that macOS
attributes those grants to a stable identity rather than to whichever host launched
this binary. The remote mode adds a network front door but not a new permission — a
remote caller reaches exactly the same tools a local one does, gated by the token.
"""

/// Parse the flags that follow `serve` into a remote-listener config. The token
/// falls back to PROCTOR_MCP_TOKEN so it need never appear in a process listing.
func parseRemoteConfig(_ args: [String]) -> RemoteConfig {
    var host = "127.0.0.1"
    var port: UInt16 = 8787
    var token = ProcessInfo.processInfo.environment["PROCTOR_MCP_TOKEN"]
    var i = 0
    while i < args.count {
        switch args[i] {
        case "--host": i += 1; if i < args.count { host = args[i] }
        case "--port": i += 1; if i < args.count, let p = UInt16(args[i]) { port = p }
        case "--token": i += 1; if i < args.count { token = args[i] }
        default: break
        }
        i += 1
    }
    if let t = token, t.isEmpty { token = nil }
    return RemoteConfig(host: host, port: port, token: token)
}

/// The advertised tool profile: `--profile` wins over PROCTOR_PROFILE, and an
/// unrecognised value falls back to `full` with a warning rather than a silent
/// wrong surface.
func parseProfile(_ args: [String]) -> ToolProfile {
    var raw = ProcessInfo.processInfo.environment["PROCTOR_PROFILE"]
    var i = 0
    while i < args.count {
        if args[i] == "--profile" { i += 1; if i < args.count { raw = args[i] } }
        i += 1
    }
    if let raw, !raw.isEmpty, ToolProfile(argument: raw) == nil {
        shimLog("unknown profile \(raw.debugDescription); serving the full tool surface. "
              + "Valid: \(ToolProfile.names.joined(separator: ", ")).")
    }
    return ToolProfile(argument: raw) ?? .full
}

let arguments = Array(CommandLine.arguments.dropFirst())
switch arguments.first {
case nil, "serve":
    let rest = Array(arguments.dropFirst())
    let profile = parseProfile(rest)
    if rest.contains("--remote") || rest.contains("--http") {
        var config = parseRemoteConfig(rest)
        config.profile = profile
        RemoteServer(config: config).run()
    } else {
        MCPServer(profile: profile).run()
    }

case "install":
    exit(Installer.install() ? 0 : 1)

case "uninstall":
    exit(Installer.uninstall() ? 0 : 1)

case "status":
    exit(Installer.status() ? 0 : 1)

case "--version", "-v", "version":
    print(BuildInfo.current.descriptor)

case "--help", "-h", "help":
    print(usage)

case .some(let unknown):
    FileHandle.standardError.write(Data("proctor-shim: unknown command: \(unknown)\n\n".utf8))
    FileHandle.standardError.write(Data((usage + "\n").utf8))
    exit(2)
}
