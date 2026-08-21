import Testing
import Foundation

// The instruments that measure this project, measured.
//
// Seven findings arrived in one wave about the tools rather than the product, and
// they shared a failure mode: an instrument reporting a clean result over a
// population it never examined. `campaign.py check` printed twelve unwitnessed
// requirements out of eighteen with nothing saying it had cut the list, and a wave
// of work was scoped off the twelve. The census control passed in both directions
// while arming one of the gate's two passes. The mutation runner spent a sampled
// slot on an edit the compiler had to reject. A hand-merge swept two keys of five
// and unpublished a judged capture.
//
// The checks themselves live in `scripts/campaign/test_instruments.py`, which reads
// this repo's own registry and its own generators. This suite exists so that
// `./scripts/test.sh` owns the verdict: a Python file nobody runs is the same shape
// of finding as the ones it was written to close.
@Suite("Campaign instruments")
struct CampaignInstrumentTests {

    /// The repository root, found from this file rather than from a working
    /// directory a test runner does not promise anything about.
    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)      // Tests/ProctorCoreTests/CampaignInstrumentTests.swift
            .deletingLastPathComponent()     // Tests/ProctorCoreTests
            .deletingLastPathComponent()     // Tests
            .deletingLastPathComponent()     // repo root
    }

    private struct Run {
        let status: Int32
        let output: String
    }

    private static func python(_ arguments: [String]) throws -> Run {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3"] + arguments
        process.currentDirectoryURL = repositoryRoot
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        // Read before waiting: a pipe that fills while nobody is draining it
        // deadlocks the child, and this suite prints its whole result.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Run(status: process.terminationStatus,
                   output: String(data: data, encoding: .utf8) ?? "")
    }

    @Test("the campaign instruments pass, and the run says how many checks it made")
    func instrumentsPass() throws {
        let script = Self.repositoryRoot
            .appendingPathComponent("scripts/campaign/test_instruments.py").path
        #expect(FileManager.default.fileExists(atPath: script),
                "scripts/campaign/test_instruments.py is missing")

        let run = try Self.python([script])

        // The count is asserted rather than only the exit code. A suite that
        // discovered nothing exits 0 too, and "0 passed, 0 failed" is the shape of
        // an instrument reporting a clean result over a population it never
        // examined — which is the whole subject of these checks.
        let summary = run.output
            .split(separator: "\n")
            .last { $0.hasPrefix("campaign instruments:") }
            .map(String.init)
        #expect(summary != nil, "no summary line in: \(run.output)")

        let passed = summary.flatMap { line -> Int? in
            guard let range = line.range(of: "campaign instruments: ") else { return nil }
            return Int(line[range.upperBound...].prefix(while: \.isNumber))
        } ?? 0
        #expect(passed >= 15,
                "expected at least 15 instrument checks, got \(passed): \(run.output)")
        #expect(run.status == 0, "campaign instruments failed:\n\(run.output)")
    }

    // DEF-032, asserted here as well as in the Python suite, because this is the
    // one that cost a mutation slot: `$0` and `$1` are closure shorthand
    // parameters and the digit in one is not an integer literal. Mutant 24 of 24
    // rewrote `{ bind(fd, $0, size) }` to `bind(fd, $1, size)`, which cannot
    // compile, and under load it scored as a kill at the timeout rather than as
    // unbuildable.
    @Test("the mutation runner leaves closure shorthand alone")
    func mutationRunnerLeavesClosureShorthandAlone() throws {
        let source = """
        withUnsafePointer(to: &sa) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, size) }
        }
        let retries = 3
        """
        let fixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClosureShorthand-\(UUID().uuidString).swift")
        try source.write(to: fixture, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: fixture) }

        let run = try Self.python(["-c", """
        import importlib.util, json, sys
        spec = importlib.util.spec_from_file_location('m', 'scripts/campaign/mutate_swift.py')
        m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
        from pathlib import Path
        print(json.dumps([(c['line'], c['before'], c['after'])
                          for c in m.candidates(Path(sys.argv[1]))]))
        """, fixture.path])
        #expect(run.status == 0, "\(run.output)")

        // Nothing on the closure line is rewritten as an integer, and the real
        // literal on the last line still is — a fix that stopped the operator
        // firing at all would pass the first assertion alone.
        #expect(!run.output.contains("[2, \"0\""),
                "the integer operator fired on closure shorthand: \(run.output)")
        #expect(run.output.contains("\"3\", \"4\""),
                "the integer operator stopped firing on a real literal: \(run.output)")
    }

    // DEF-058: a registry merge sweeps every key. The hand-merge that lost
    // FLOW-010 merged `defect` and `requirement` and took ours as the base
    // document; the capture stayed on disk and its verdict stayed in
    // witness-verdicts.json, and only the subject left the published set.
    @Test("a registry merge that drops a key is caught")
    func registryMergeCatchesADroppedKey() throws {
        let script = Self.repositoryRoot
            .appendingPathComponent("scripts/campaign/merge_registry.py").path
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("merge-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let ours = #"{"defect": [{"id": "DEF-001"}], "flow": [{"id": "FLOW-001"}]}"#
        let theirs = #"{"defect": [{"id": "DEF-001"}, {"id": "DEF-002"}], "flow": [{"id": "FLOW-001"}, {"id": "FLOW-010"}]}"#
        // The merge as it was performed: the defect list taken from theirs, the
        // flow list left as ours, because flow was not what the conflict was about.
        let hand = #"{"defect": [{"id": "DEF-001"}, {"id": "DEF-002"}], "flow": [{"id": "FLOW-001"}]}"#
        for (name, body) in [("ours", ours), ("theirs", theirs), ("hand", hand)] {
            try body.write(to: dir.appendingPathComponent("\(name).json"),
                           atomically: true, encoding: .utf8)
        }

        let caught = try Self.python([script,
                                      "--base", dir.appendingPathComponent("ours.json").path,
                                      "--theirs", dir.appendingPathComponent("theirs.json").path,
                                      "--verify", dir.appendingPathComponent("hand.json").path])
        #expect(caught.status == 1, "a dropped key was not caught: \(caught.output)")
        #expect(caught.output.contains("flow/FLOW-010"),
                "the dropped row was not named: \(caught.output)")

        // And the same script's own merge keeps it, so the check is watched in
        // both directions rather than only red.
        let merged = try Self.python([script,
                                      "--base", dir.appendingPathComponent("ours.json").path,
                                      "--theirs", dir.appendingPathComponent("theirs.json").path,
                                      "--out", dir.appendingPathComponent("merged.json").path])
        #expect(merged.status == 0, "\(merged.output)")
        let result = try String(contentsOf: dir.appendingPathComponent("merged.json"),
                                encoding: .utf8)
        #expect(result.contains("FLOW-010"),
                "the merge dropped the key it exists to sweep: \(result)")
    }
}
