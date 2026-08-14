import Foundation

// Relaunching an app from inside itself, correctly.
//
// The obvious two lines do not work. `open -a` on a running single-instance
// menu bar app activates the instance that is already there rather than starting
// the new build; terminating first and then opening races the launch, because
// LaunchServices can still see the dying process and hand the request to it.
//
// So: hand a wait-then-open to a detached shell, and quit. The shell outlives
// this process by design, watches for the pid to go, and only then opens the
// bundle — by which point LaunchServices agrees there is nothing running.
//
// The command is built here, in Core, because it is the one part of a relaunch
// that can be silently wrong. A shell string assembled in a view is a shell
// string nobody tests.
public enum RelaunchCommand {

    /// `/bin/sh` arguments that wait for `pid` to exit and then open the bundle.
    ///
    /// `kill -0` tests for the process without signalling it, so this is a poll
    /// that cannot itself kill anything. A fifth of a second is below noticing
    /// and costs nothing for the moment or two a quit takes.
    public static func arguments(pid: Int32, bundlePath: String) -> [String] {
        ["-c", "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; open \(quoted(bundlePath))"]
    }

    /// Single-quote a path for `sh`. A quote inside the path is closed, escaped
    /// and reopened, which is the only escape single quoting has. An app in a
    /// folder called `Luke's` would otherwise end the string early and run
    /// whatever followed as a command.
    static func quoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
