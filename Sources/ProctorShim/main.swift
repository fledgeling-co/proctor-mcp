import Foundation
import ProctorCore

// Argument dispatch. Everything here is either forwarding (serve) or the one
// thing the shim is allowed to write (install).

let usage = """
proctor-shim \(ShimVersion.value) — the permissionless MCP front end for Proctor.

Usage:
  proctor-shim [serve]     Speak MCP over stdio and forward tool calls to the agent.
  proctor-shim install     Install and load the launchd user agent, then print host config.
  proctor-shim uninstall   Unload the agent and remove its launchd plist.
  proctor-shim status      Report whether the agent is reachable. Exits 0 when it is.
  proctor-shim --version   Print the version.
  proctor-shim --help      Print this.

The shim holds no permissions and keeps no state. Accessibility and Screen Recording
are granted to Proctor itself, which runs as its own launchd process so that macOS
attributes those grants to a stable identity rather than to whichever host launched
this binary.
"""

switch CommandLine.arguments.dropFirst().first {
case nil, "serve":
    MCPServer().run()

case "install":
    exit(Installer.install() ? 0 : 1)

case "uninstall":
    exit(Installer.uninstall() ? 0 : 1)

case "status":
    exit(Installer.status() ? 0 : 1)

case "--version", "-v", "version":
    print(ShimVersion.value)

case "--help", "-h", "help":
    print(usage)

case .some(let unknown):
    FileHandle.standardError.write(Data("proctor-shim: unknown command: \(unknown)\n\n".utf8))
    FileHandle.standardError.write(Data((usage + "\n").utf8))
    exit(2)
}
