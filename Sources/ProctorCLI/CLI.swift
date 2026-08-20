import Foundation
import ProctorCore

// PRO-0073. `proctor`, the operator CLI.
//
// A second front end to the agent, not a second set of capabilities. Every verb
// reaches the same socket the MCP shim reaches, so a call passes the same policy
// gate, takes the same queue lane, lands in the same audit trail and is
// disclosed on the same run HUD. The only thing that differs is who called.
//
// `--json` emits the exact object the MCP tool returns, unaltered, so a script
// and a model see the same bytes and a defect reproduces identically through
// either front end. That is the whole reason a person can now put a
// reproduction command in a bug report.

/// One parsed invocation.
struct Invocation {
    var verb: String
    var json: Bool
    var arguments: [String: JSONValue]
    var lane: String?
    /// Whether the caller asked for arguments on stdin, with `-` or `--stdin`.
    var readsStandardInput: Bool = false

    /// Parse `proctor <verb> [--flag value]… [-]`.
    ///
    /// Deliberately small: flags become arguments by name, so the CLI does not
    /// carry a second description of each tool's schema that could drift from
    /// `ToolCatalogue`.
    static func parse(_ argv: [String]) -> Result<Invocation, CLISurface.Exit> {
        guard let verb = argv.first else { return .failure(.usage) }
        var out = Invocation(verb: verb, json: false, arguments: [:], lane: nil)
        var i = 1
        while i < argv.count {
            let token = argv[i]
            // The conventional "read the arguments from stdin". A bare `-` is
            // the idiom; `--stdin` is the same thing spelled out.
            if token == "-" { out.readsStandardInput = true; i += 1; continue }
            guard token.hasPrefix("--") else { return .failure(.usage) }
            let key = String(token.dropFirst(2))
            if key == "json" { out.json = true; i += 1; continue }
            if key == "stdin" { out.readsStandardInput = true; i += 1; continue }
            guard i + 1 < argv.count else { return .failure(.usage) }
            let value = argv[i + 1]
            if key == "lane" { out.lane = value; i += 2; continue }
            out.arguments[key] = Self.typed(value)
            i += 2
        }
        return .success(out)
    }

    /// A flag's value, typed the way the tool schemas expect.
    ///
    /// In `CLIArguments` rather than here, so it can be asserted against values
    /// written by hand. This used to be four lines of local logic that turned
    /// every value into a scalar, which is how `--steps '[…]'` reached the agent
    /// as a string and came back "requires steps as an array".
    private static func typed(_ raw: String) -> JSONValue { CLIArguments.typed(raw) }
}

enum CLI {

    static func run(_ argv: [String]) -> CLISurface.Exit {
        guard !argv.isEmpty, argv.first != "--help", argv.first != "-h" else {
            printUsage()
            return argv.isEmpty ? .usage : .ok
        }

        switch Invocation.parse(argv) {
        case .failure(let code):
            printUsage()
            return code
        case .success(let invocation):
            return dispatch(invocation)
        }
    }

    private static func dispatch(_ invocation: Invocation) -> CLISurface.Exit {
        if invocation.verb == "tui" {
            return TUIApp.run()
        }

        if invocation.verb == "completion" {
            let shell = invocation.arguments["shell"]?.stringValue ?? "zsh"
            guard let script = CLISurface.completionScript(shell: shell) else {
                FileHandle.standardError.write(Data("proctor: no completion for \(shell)\n".utf8))
                return .usage
            }
            print(script)
            return .ok
        }

        guard let verb = CLISurface.verb(named: invocation.verb) else {
            FileHandle.standardError.write(
                Data("proctor: unknown verb \(invocation.verb.debugDescription)\n".utf8))
            printUsage()
            return .usage
        }

        // Arguments come from two places and the flags win. `spec-PRO-0073.md`
        // took "support both, stdin JSON as the documented path" as the
        // assumption that unblocked the step-batch fork, and this is it: a batch
        // is unreadable as repeated flags and awkward to type inline, so it is
        // piped, and a flag beside it retargets what was piped.
        let piped: [String: JSONValue]?
        do {
            piped = try CLI.standardInputArguments(requested: invocation.readsStandardInput)
        } catch let failure as CLIArguments.Failure {
            FileHandle.standardError.write(Data("proctor: \(CLIArguments.message(for: failure))\n".utf8))
            FileHandle.standardError.write(Data("proctor: \(CLIArguments.remedy)\n".utf8))
            return .usage
        } catch {
            FileHandle.standardError.write(Data("proctor: \(error)\n".utf8))
            return .usage
        }
        let arguments = CLIArguments.merged(standardInput: piped, flags: invocation.arguments)

        // The same socket the MCP shim uses. Nothing here is a second path into
        // the agent, and nothing here can skip a gate the other front end passes.
        do {
            let reply = try Client.call(tool: verb.tool, arguments: arguments)
            return report(reply, invocation: invocation, verb: verb)
        } catch let error as AgentError {
            emit(error, json: invocation.json)
            return CLISurface.exit(for: error.code)
        } catch {
            FileHandle.standardError.write(Data("proctor: \(error)\n".utf8))
            return .agentUnreachable
        }
    }

    /// Print the reply and decide the code.
    ///
    /// A verdict inside a successful call is still a failure for CI, which is
    /// what separates exit 1 from exit 0 — the call worked and the check did not.
    private static func report(_ reply: JSONValue,
                               invocation: Invocation,
                               verb: CLISurface.Verb) -> CLISurface.Exit {
        if invocation.json {
            // Unaltered: the same bytes a model receives.
            if let data = try? JSONEncoder().encode(reply),
               let text = String(data: data, encoding: .utf8) {
                print(text)
            }
        } else {
            print(Renderer.human(reply, verb: verb))
        }

        let code = CLISurface.exit(forReply: reply, lane: invocation.lane)
        if code == .notReady, let lane = invocation.lane {
            FileHandle.standardError.write(
                Data("proctor: lane \(lane) is \(CLISurface.laneState(reply, lane: lane))\n".utf8))
        }
        return code
    }

    /// Arguments piped in, or nil when the caller did not ask for them.
    ///
    /// **Read only on an explicit `-` or `--stdin`, never inferred.** The first
    /// version inferred it from `isatty`, on the reasoning that a terminal means
    /// nobody piped anything. That is true and not sufficient: any caller whose
    /// stdin is an open pipe nothing ever writes to — a CI runner, an agent
    /// harness, a `Process` with a pipe it keeps — is not a terminal either, and
    /// `proctor doctor` hung there forever waiting on a read that never
    /// returned. Found by running it, not by reading it.
    ///
    /// `spec-PRO-0073.md` took "support both, stdin JSON as the documented path"
    /// as its assumption. A conventional `-` still is that path, and it cannot
    /// hang, which a literal reading demonstrably could.
    static func standardInputArguments(requested: Bool) throws -> [String: JSONValue]? {
        guard requested else { return nil }
        let data = FileHandle.standardInput.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else {
            throw CLIArguments.Failure.standardInputNotJSON("<not UTF-8>")
        }
        return try CLIArguments.fromStandardInput(text)
    }

    private static func emit(_ error: AgentError, json: Bool) {
        if json, let data = try? JSONEncoder().encode(error),
           let text = String(data: data, encoding: .utf8) {
            FileHandle.standardError.write(Data((text + "\n").utf8))
            return
        }
        FileHandle.standardError.write(Data("proctor: \(error.message)\n".utf8))
        if let remedy = error.remedy {
            FileHandle.standardError.write(Data("proctor: \(remedy)\n".utf8))
        }
    }

    static func printUsage() {
        var lines = [
            "proctor \(BuildInfo.current.descriptor) — drive and check this Mac from a shell.",
            "",
            "  proctor <verb> [--flag value]… [--json]",
            "",
            "Observation (never takes a queue lane):",
        ]
        let reads = CLISurface.verbs.filter { !$0.queues }.map(\.name).sorted()
        let writes = CLISurface.verbs.filter { $0.queues }.map(\.name).sorted()
        lines.append("  " + reads.joined(separator: "  "))
        lines.append("")
        lines.append("Actuation (takes a lane, and is recorded):")
        lines.append("  " + writes.joined(separator: "  "))
        lines.append("")
        lines.append("Service:")
        lines.append("  " + CLISurface.serviceVerbs.joined(separator: "  "))
        lines.append("")
        lines.append("A step batch is piped with - or --stdin, and a flag beside it wins:")
        lines.append(#"  echo '{"window":"win:1:0","steps":[…]}' | proctor act -"#)
        lines.append(#"  proctor act --window win:1:0 --steps '[{"kind":"key","key":"escape"}]'"#)
        lines.append("")
        lines.append("Exit codes:")
        for code in CLISurface.Exit.allCases {
            lines.append("  \(code.rawValue)  \(code.meaning)")
        }
        print(lines.joined(separator: "\n"))
    }
}
