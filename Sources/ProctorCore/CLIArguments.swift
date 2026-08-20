import Foundation

// PRO-0073. How the CLI turns what a person typed into what a tool schema wants.
//
// Split out of `CLISurface` because it is a different question with its own
// invariants, and because a decision only reachable through a live agent is a
// decision nothing checks — the same reason `exit(forReply:lane:)` lives in Core
// rather than in the CLI target.
//
// **It exists because the CLI could not actuate anything.** `spec-PRO-0073.md`
// recorded the fork and the assumption taken to unblock it: "support both,
// stdin JSON as the documented path". Neither half was built. Every flag value
// became a string, a number or a bool, so `--steps '[…]'` reached the agent as
// a *string* and came back `proctor_act requires steps as an array`; and nothing
// read stdin at all. Eight of the twenty-one verbs take an array or an object —
// act, zoom, wait, assert, flow, stability, computer and policy — so 8 of 21
// could not be called for the thing they exist to do. Found by checking a parked
// assumption against the code rather than by anything failing.

public enum CLIArguments {

    public enum Failure: Error, Equatable {
        /// Stdin had bytes and they were not JSON.
        case standardInputNotJSON(String)
        /// Stdin was JSON and was not an object, so it names no arguments.
        case standardInputNotAnObject
    }

    /// A flag's value, typed the way the tool schemas expect.
    ///
    /// A bare `true` is a boolean rather than the string "true", because the
    /// wire distinguishes them and a caller should not have to. A value opening
    /// with `[` or `{` is parsed as JSON, which is what makes `--steps` usable
    /// at all; anything else that opens that way and does not parse is left as
    /// the string it is, because a caller who typed a selector should not be
    /// told their selector is malformed JSON.
    public static func typed(_ raw: String) -> JSONValue {
        if raw == "true" { return .bool(true) }
        if raw == "false" { return .bool(false) }
        if let d = Double(raw) { return .number(d) }
        if let first = raw.first, first == "[" || first == "{",
           let data = raw.data(using: .utf8),
           let value = try? JSONDecoder().decode(JSONValue.self, from: data) {
            return value
        }
        return .string(raw)
    }

    /// Arguments named by a JSON object on stdin, or nil when there were none.
    ///
    /// Whitespace alone is "nothing was piped" rather than a malformed
    /// document: a shell that pipes an empty file should not be told it wrote
    /// bad JSON.
    public static func fromStandardInput(_ text: String) throws -> [String: JSONValue]? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        guard let data = trimmed.data(using: .utf8),
              let value = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            throw Failure.standardInputNotJSON(String(trimmed.prefix(60)))
        }
        guard let object = value.objectValue else { throw Failure.standardInputNotAnObject }
        return object
    }

    /// The arguments a call is made with: stdin underneath, flags on top.
    ///
    /// **A flag wins.** The pipe carries the batch and the flag carries the
    /// correction, so `cat run.json | proctor act --window win:2:0` retargets a
    /// recorded batch rather than being told the two disagree. The other order
    /// would make a flag silently do nothing, which is the worse failure: it
    /// looks like it worked.
    public static func merged(standardInput: [String: JSONValue]?,
                              flags: [String: JSONValue]) -> [String: JSONValue] {
        var out = standardInput ?? [:]
        for (key, value) in flags { out[key] = value }
        return out
    }

    /// What to print when stdin could not be read as arguments.
    public static func message(for failure: Failure) -> String {
        switch failure {
        case .standardInputNotJSON(let head):
            return "what was piped in is not JSON: \(head)"
        case .standardInputNotAnObject:
            return "what was piped in is JSON but not an object, so it names no arguments"
        }
    }

    /// The token that asks for arguments on stdin, and its spelled-out form.
    ///
    /// Named here rather than only in the parser so the remedy below cannot
    /// describe a flag the parser does not take. That drift is not hypothetical:
    /// the first draft of this file printed a remedy without the token at all,
    /// because reading stdin had been inferred rather than asked for.
    public static let standardInputToken = "-"
    public static let standardInputFlag = "--stdin"

    /// The remedy, which names the shape rather than restating the error.
    public static let remedy =
        #"Pipe an object of arguments and ask for it, e.g. echo '{"window":"win:1:0","steps":[…]}' | proctor act -"#
}
