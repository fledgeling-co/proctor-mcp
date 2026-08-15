import Foundation

/// Which tool call a record belongs to.
///
/// A trail of events is not a history. The unit a person reads in is one call —
/// "that thing it just did" — and until this existed nothing on a record said
/// which call produced it, so a surface could only guess by adjacency and would
/// have guessed wrong the moment two calls overlapped.
///
/// It is a task local rather than a parameter for one reason: the records of a
/// single call are written from several places that do not know about each other
/// — the policy gate before the run, each step inside it, a lane recommendation
/// beside it — and threading an identifier through all of them would mean every
/// future audited call site had to remember to pass it. A task local is set once,
/// at the dispatcher's existing choke point, and is inherited by everything that
/// call does. Task locals follow the task across actor hops, so a write from
/// inside the `Session` actor still sees the value its caller set.
///
/// Nil is a real answer, not a failure: a record written outside a tool call —
/// a person's Stop, a hold, a panel decision — genuinely belongs to no run, and
/// history reads it as its own event rather than folding it into whatever
/// happened to be running.
enum RunIdentity {

    @TaskLocal static var current: String?

    /// Short and random. It only has to separate the calls held in one trail, and
    /// it is written into every record of a call, so it is kept small.
    static func mint() -> String {
        String(UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12)).lowercased()
    }
}
