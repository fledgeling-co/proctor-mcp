import Foundation

// Whether this process is the agent, which is the process entitled to paint on
// this Mac.
//
// PRO-0075. Reported from real use: the full-screen statement read
// `Proctor is driving "Fake"`. No application on the machine is called Fake and
// no shipped string contains the word. It is `FakeAX`'s app handle, from
// `Tests/ProctorAgentTests/Fakes.swift`, and it reached the screen because
// `Session.takeover` defaults to `LiveTakeover` and thirty-two test files build
// a session without replacing it. Measured while one suite ran: two windows at
// level 1000 covering the whole of both displays, owned by
// `swiftpm-testing-helper`.
//
// The switches could not catch it. `PROCTOR_TAKEOVER` and `PROCTOR_CURSOR` are
// on when unset, which is right for the agent and wrong as a default for
// everything else that links this target — a test binary, a future tool,
// anything that imports the module to reach one type and constructs a session
// on the way. Each of those is a process nobody asked to draw on their screen.
//
// So entitlement is claimed rather than assumed, by the one entry point that
// can honestly claim it. `main.swift` says so before it starts serving; nothing
// else says it, and there is no environment variable that can. A surface whose
// switch is on still draws nothing until somebody has.
//
// Deliberately not the AppKit event loop, which `RunHUDPanel` gates on and which
// would look like the same fact. It is not: an agent launched with
// `PROCTOR_HUD=0` runs `CFRunLoopRun()` and enters no AppKit loop, and that
// operator opted out of the run panel rather than out of being told their Mac is
// being driven.
enum AgentProcess {

    /// Written once, on the main thread, before the agent serves anything, and
    /// only read afterwards. Same shape as `RunHUDPanel.eventLoopRunning`, for
    /// the same reason: a flag set once at startup needs no lock, and taking one
    /// here would put it on every step's path.
    nonisolated(unsafe) private static var claimed = false

    /// Called by `main.swift`. There is no matching way to give the claim up: a
    /// process that was the agent stays the agent for as long as it runs.
    static func claimIsAgent() { claimed = true }

    static var isAgent: Bool { claimed }
}
