import Foundation

// PRO-0044. Where `cua-driver` is looked for, and the two switches that select
// and force the lane.
//
// Detection reads the filesystem and executes nothing, exactly as it does for
// every other tool Proctor knows about (see `ToolPresence`). Running the driver
// is a separate act, gated behind lane selection and a signature check, and it
// happens in `CuaPreflight` rather than here.

public enum CuaDriverTool {

    public static let binary = "cua-driver"

    public static let docs = "https://github.com/trycua/cua"

    /// Checked in addition to whatever `PATH` the agent inherited, because a
    /// launchd agent's `PATH` is usually /usr/bin:/bin:/usr/sbin:/sbin and the
    /// directories a per-user install writes to are not on it.
    public static let extraDirectories = ToolLocator.commonToolDirectories

    /// The macOS application the CLI is a client of.
    ///
    /// It matters for a reason that is easy to miss: the Accessibility grant that
    /// actually performs a delegated click belongs to THIS bundle's identity, not
    /// to Proctor's and not to the CLI's. So Proctor's own grants stop describing
    /// whether actuation will work the moment this lane is selected, which is why
    /// preflight asks the driver about itself instead of inferring.
    public static let appBundlePath = "/Applications/CuaDriver.app"

    /// Selects the actuation lane. Absent or anything else means Proctor's own
    /// planes, which stay the default until the item that decides their future
    /// says otherwise.
    public static let laneEnv = "PROCTOR_ACTUATION"
    public static let laneValue = "cua"

    /// Which client talks to the driver. The long-lived endpoint is the default;
    /// `oneshot` spawns a CLI per step. Neither is ever an automatic fallback for
    /// the other — a run that silently changes how it reaches the machine cannot
    /// be scored, and the direction file is explicit that a fallback is a
    /// decision rather than a safety net.
    public static let transportEnv = "PROCTOR_CUA_TRANSPORT"

    /// Whether the operator asked for the delegated lane.
    public static func laneSelected(
        _ environment: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
        environment[laneEnv]?.lowercased() == laneValue
    }
}
