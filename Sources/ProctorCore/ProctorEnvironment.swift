import Foundation

// PRO-0029. The one dictionary every switch is read from.
//
// Seven call sites already take a `[String: String]` and read a switch out of it:
// `CursorOverlay.isEnabled`, `InputBlocker.isEnabled`, `TakeoverOverlay.isEnabled`,
// `ContentionMonitor.enabled` / `.inputObserved`, `SessionHUD.hudEnabledByDefault`,
// `BrowserUseTool.enabled` and `CuaDriverTool.laneSelected`. Each reads it once,
// several with reasoning that says re-reading would be a defect — "a tap that could
// switch itself on mid-process would be a tap nobody agreed to".
//
// So a saved preference reaches them by changing what the dictionary CONTAINS, not
// by changing how any of them reads. `SwitchResolver.effectiveEnvironment` folds
// the saved values into the process environment under the precedence rule, the
// agent installs the result here as its first act, and every existing site reads
// this instead of `ProcessInfo.processInfo.environment`. Nothing downstream learns
// that preferences exist.
//
// **Set once, before anything reads it.** `install` runs as the first statement of
// the agent's `main`, ahead of any `static let` that would otherwise capture the
// raw environment on first touch. A site that read this before the install would
// get the process environment — correct but preference-blind — rather than
// anything wrong, which is the right way for the hazard to fail.

public enum ProctorEnvironment {

    /// Defaults to the process environment, so a target that never installs
    /// anything — the shim, the reflector, a test — behaves exactly as it did
    /// before this existed.
    nonisolated(unsafe) private static var storage: [String: String] =
        ProcessInfo.processInfo.environment

    /// The environment as the agent actually inherited it, kept beside the
    /// effective one.
    ///
    /// Both are needed and they are not interchangeable. The effective dictionary
    /// is what switches are READ from; the raw one is what the precedence rule is
    /// resolved AGAINST. Resolving against the effective dictionary would report
    /// every saved preference as having come from the environment — and therefore
    /// as locked — which is precisely the misreport this feature exists to prevent.
    nonisolated(unsafe) private static var rawStorage: [String: String] =
        ProcessInfo.processInfo.environment

    /// The dictionary every switch is read from.
    public static var current: [String: String] { storage }

    /// The environment this process inherited, before any preference was folded
    /// in. Resolve precedence against this.
    public static var inherited: [String: String] { rawStorage }

    /// Fold the saved preferences in. Called once, first, by the agent.
    public static func install(saved: SavedSwitches,
                               processEnvironment: [String: String]
                                   = ProcessInfo.processInfo.environment) {
        rawStorage = processEnvironment
        storage = SwitchResolver.effectiveEnvironment(processEnvironment: processEnvironment,
                                                      saved: saved.values)
    }

    /// Put it back. For tests, which must not leak one case's environment into
    /// the next.
    public static func reset(to environment: [String: String]
                                = ProcessInfo.processInfo.environment) {
        storage = environment
        rawStorage = environment
    }
}
