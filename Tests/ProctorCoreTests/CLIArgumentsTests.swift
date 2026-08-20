import Foundation
import Testing
@testable import ProctorCore

// PRO-0073. The CLI could not actuate anything, and this is what settles it.
//
// Found by checking a parked assumption against the code. `spec-PRO-0073.md`
// recorded "support both, stdin JSON as the documented path" as the assumption
// taken to unblock the step-batch fork, and neither half existed: a flag value
// became a string, a number or a bool and nothing read stdin. `--steps '[…]'`
// reached the agent as a string and came back `proctor_act requires steps as an
// array`, which is what a person would have seen for every one of the eight
// verbs that take an array or an object.

@Suite("CLI arguments")
struct CLIArgumentsTests {

    @Test("a bracketed value is parsed as JSON, so a step batch survives the flag")
    func jsonFlagValues() throws {
        let steps = CLIArguments.typed(#"[{"kind":"key","key":"escape"}]"#)
        let array = try #require(steps.arrayValue)
        #expect(array.count == 1)
        #expect(array[0]["kind"]?.stringValue == "key")

        let object = CLIArguments.typed(#"{"role":"AXButton"}"#)
        #expect(object["role"]?.stringValue == "AXButton")
    }

    @Test("the scalars the wire distinguishes are still distinguished")
    func scalarsAreUnchanged() {
        #expect(CLIArguments.typed("true") == .bool(true))
        #expect(CLIArguments.typed("false") == .bool(false))
        #expect(CLIArguments.typed("12") == .number(12))
        #expect(CLIArguments.typed("1.5") == .number(1.5))
        #expect(CLIArguments.typed("win:1:0") == .string("win:1:0"))
    }

    @Test("a value that opens like JSON and is not JSON stays the string it is")
    func malformedJSONIsAString() {
        // A caller who typed a selector should not be told their selector is
        // malformed JSON. The tool will reject it, in the tool's own words.
        #expect(CLIArguments.typed("[not json") == .string("[not json"))
        #expect(CLIArguments.typed("{AXButton}") == .string("{AXButton}"))
    }

    @Test("an object on stdin names arguments")
    func stdinObject() throws {
        let args = try #require(try CLIArguments.fromStandardInput(
            #"{"window":"win:1:0","steps":[{"kind":"key"}]}"#))
        #expect(args["window"]?.stringValue == "win:1:0")
        #expect(args["steps"]?.arrayValue?.count == 1)
    }

    @Test("nothing piped is nothing piped, not a malformed document")
    func emptyStdinIsNil() throws {
        #expect(try CLIArguments.fromStandardInput("") == nil)
        #expect(try CLIArguments.fromStandardInput("   \n\t ") == nil)
    }

    @Test("stdin that is not JSON, and stdin that is JSON but not an object, differ")
    func stdinFailuresAreDistinct() {
        #expect(throws: CLIArguments.Failure.standardInputNotJSON("hello")) {
            try CLIArguments.fromStandardInput("hello")
        }
        #expect(throws: CLIArguments.Failure.standardInputNotAnObject) {
            try CLIArguments.fromStandardInput("[1,2,3]")
        }
    }

    @Test("a flag wins over the same key on stdin")
    func flagsWin() {
        // `cat run.json | proctor act --window win:2:0` retargets a recorded
        // batch. The other order makes the flag silently do nothing, which
        // looks like it worked.
        let merged = CLIArguments.merged(
            standardInput: ["window": .string("win:1:0"), "steps": .array([.object([:])])],
            flags: ["window": .string("win:2:0")])
        #expect(merged["window"]?.stringValue == "win:2:0")
        #expect(merged["steps"]?.arrayValue?.count == 1, "and the batch it did not name survives")
    }

    @Test("with nothing piped, the flags are the arguments")
    func flagsAloneAreEnough() {
        let merged = CLIArguments.merged(standardInput: nil, flags: ["app": .string("app:1:0")])
        #expect(merged == ["app": .string("app:1:0")])
    }

    @Test("every verb whose schema needs an array or an object can now be given one")
    func theEightVerbsAreReachable() throws {
        // The list is derived rather than typed: a tool that grows an array
        // argument joins this test on the next build instead of being noticed
        // later. What is asserted is that a JSON value for each such property
        // survives typing as the shape the schema declares.
        var checked = 0
        for spec in ToolCatalogue.all {
            guard let properties = spec.inputSchema["properties"]?.objectValue else { continue }
            for (name, schema) in properties {
                guard let kind = schema["type"]?.stringValue,
                      kind == "array" || kind == "object" else { continue }
                let sample = kind == "array" ? "[1]" : #"{"a":1}"#
                let typed = CLIArguments.typed(sample)
                if kind == "array" {
                    #expect(typed.arrayValue != nil,
                            "\(spec.name).\(name) declares an array and the CLI would send a string")
                } else {
                    #expect(typed.objectValue != nil,
                            "\(spec.name).\(name) declares an object and the CLI would send a string")
                }
                checked += 1
            }
        }
        #expect(checked >= 8, "the catalogue declares fewer non-scalar arguments than expected: \(checked)")
    }

    @Test("the remedy names the token the parser actually takes")
    func remedyMatchesTheParser() {
        // The remedy used to describe a pipe with no token on it, because
        // reading stdin had been inferred from isatty rather than asked for —
        // and inferring it hung any caller whose stdin was an open pipe nothing
        // wrote to. The prose and the parser are pinned together here so the
        // next change to one has to move the other.
        #expect(CLIArguments.remedy.contains("proctor act \(CLIArguments.standardInputToken)"))
        #expect(CLIArguments.standardInputToken == "-")
        #expect(CLIArguments.standardInputFlag == "--stdin")
    }
}
