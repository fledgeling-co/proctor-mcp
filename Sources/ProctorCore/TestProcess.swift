import Foundation

// PRO-0099. The one answer to "is this a test runner", where every layer can
// reach it.
//
// The predicate itself is not new. It was written for `AuditLog.isTestProcess`
// in `ProctorAgent` when a test that drove a real `Session` without redirecting
// its sink wrote 17 entries into a live audit trail, and it has since become the
// floor under three interlocks: the policy store, the capture directory and the
// flow store. Each of those is a static that computes a path under the
// operator's own Application Support directory, and each diverts a test process
// away from it.
//
// **It moved because the fourth one could not see it.** `SwitchStore` lives in
// `ProctorCore`; `AuditLog` lives in `ProctorAgent`, which depends on
// `ProctorCore` and not the other way round. So the settings path — the one that
// holds the operator's own switch preferences — had no way to ask the question
// the other three ask. The body below is the verbatim move of
// `AuditLog.isTestProcess`, which now forwards here, so every existing caller
// and the regression test that guards it are unchanged.
//
// **It reads `ProcessInfo` directly and never `ProctorEnvironment.current`**, and
// that is deliberate rather than incidental. The effective dictionary is
// installed by the agent and can be replaced by a test; an interlock that read it
// could be switched off by the code it exists to contain. This one cannot.
public enum TestProcess {

    /// True in a test runner, false in the agent, the shim, the CLI and the app.
    ///
    /// Xcode's XCTest host announces itself in the environment; `swift test` does
    /// not, and runs the suite inside `swiftpm-testing-helper`, so the host
    /// executable is the only thing that identifies it. Checked rather than
    /// assumed: the first version of this looked only for the XCTest variables,
    /// was inert under `swift test`, and a regression test is what caught it. The
    /// agent's own executable is `proctor-agent` and matches none of these.
    public static var isActive: Bool {
        let env = ProcessInfo.processInfo.environment
        let host = (ProcessInfo.processInfo.arguments.first as NSString?)?
            .lastPathComponent ?? ""
        return env["XCTestConfigurationFilePath"] != nil
            || env["XCTestBundlePath"] != nil
            || host == "swiftpm-testing-helper"
            || host.hasSuffix(".xctest")
            || ProcessInfo.processInfo.arguments.contains { $0.hasSuffix(".xctest") }
            || Bundle.main.bundlePath.hasSuffix(".xctest")
    }
}
