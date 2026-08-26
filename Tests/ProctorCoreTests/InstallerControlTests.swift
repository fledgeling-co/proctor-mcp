import Foundation
import Testing

/// The installer's controls, driven and read back.
///
/// SURF-016's controls are the environment variables an operator sets, and until
/// `PROCTOR_PLAN_ONLY` existed the only way to observe one taking effect was to
/// run an install — which writes to `/Applications` and can submit a build to
/// Apple. So the surface declared eight controls that nothing actuated, and
/// `campaign.py check` refused the campaign for it: a control accepts a value
/// whether or not anything downstream reads it.
///
/// Plan-only prints the decision each variable governs and exits before anything
/// is built, signed, notarised or copied. These tests set one variable at a time
/// and assert the plan moved, which is the effect outside the control.
@Suite("The installer's controls change what it would do")
struct InstallerControlTests {

    private struct Plan {
        let status: Int32
        let text: String
        func line(_ prefix: String) -> String? {
            text.split(separator: "\n")
                .first { $0.trimmingCharacters(in: .whitespaces).hasPrefix(prefix) }
                .map { $0.trimmingCharacters(in: .whitespaces) }
        }
    }

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    /// Run `install.sh` in plan-only mode with `overrides` set.
    private static func plan(_ overrides: [String: String]) throws -> Plan {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [repositoryRoot.appendingPathComponent("scripts/install.sh").path]
        process.currentDirectoryURL = repositoryRoot
        var env = ProcessInfo.processInfo.environment
        env["PROCTOR_PLAN_ONLY"] = "1"
        for (k, v) in overrides { env[k] = v }
        process.environment = env
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return Plan(status: process.terminationStatus,
                    text: String(data: data, encoding: .utf8) ?? "")
    }

    @Test("plan-only exits without building, signing, notarising or installing")
    func planOnlyIsInert() throws {
        let before = try? FileManager.default.attributesOfItem(
            atPath: "/Applications/Proctor.app") as NSDictionary
        let run = try Self.plan([:])
        #expect(run.status == 0, Comment(rawValue: run.text))
        #expect(run.text.contains("nothing will be built, signed, notarised or installed"),
                Comment(rawValue: run.text))
        // The observable that matters: the installed bundle is untouched. If the
        // plan had run the install, this timestamp would have moved.
        let after = try? FileManager.default.attributesOfItem(
            atPath: "/Applications/Proctor.app") as NSDictionary
        #expect(before?.fileModificationDate() == after?.fileModificationDate(),
                "plan-only must not touch the installed bundle")
    }

    @Test("PROCTOR_SKIP_NOTARIZE turns notarisation off, and says which control did it")
    func skipNotarize() throws {
        let on = try Self.plan([:])
        let off = try Self.plan(["PROCTOR_SKIP_NOTARIZE": "1"])
        #expect(on.status == 0 && off.status == 0)
        #expect(on.line("will notarise:") != off.line("will notarise:"),
                Comment(rawValue: "the control changed nothing: \(on.text)\n---\n\(off.text)"))
        #expect(off.text.contains("because PROCTOR_SKIP_NOTARIZE is set"),
                Comment(rawValue: off.text))
    }

    @Test("PROCTOR_NOTARY_PROFILE selects the profile the run would use")
    func notaryProfile() throws {
        let run = try Self.plan(["PROCTOR_NOTARY_PROFILE": "a-profile-nobody-has"])
        #expect(run.status == 0)
        #expect(run.line("notary profile:")?.contains("a-profile-nobody-has") == true,
                Comment(rawValue: run.text))
    }

    @Test("PROCTOR_SIGN_IDENTITY selects the identity, so a machine with none can still be planned")
    func signIdentity() throws {
        let run = try Self.plan(["PROCTOR_SIGN_IDENTITY": "Developer ID Application: Nobody (ZZZZZZZZZZ)"])
        #expect(run.status == 0)
        #expect(run.line("identity:")?.contains("Nobody (ZZZZZZZZZZ)") == true,
                Comment(rawValue: run.text))
    }
}
