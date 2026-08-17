import Foundation

// PRO-0061. Whether a batch that would take this Mac is allowed to.
//
// The wave's routing item auto-routes a takeover batch onto a configured
// guest. PRO-0051 rejected automatic fallback because it "hands back a
// verdict that looks fine and measures the plumbing", and executing the
// steps on the host while naming a guest would be that move. This process
// cannot yet perform a step inside a guest — reach (PRO-0060) describes
// the tunnel, it does not attach — so the honest auto-route is a GATE:
// a configured guest plus a batch that would take this Mac is a refusal
// that names the guest, never a silent host run.
//
// Unset is the host, unchanged. A session already marked as a guest is
// already elsewhere and is not refused here.

/// How a takeover batch is placed, decided before anything runs.
public enum GuestRoute: Sendable, Equatable {
    /// No guest is configured, or the batch would not take this Mac.
    case host
    /// The session is already on a guest. The batch runs where it is.
    case alreadyOnGuest(Machine)
    /// A guest is configured and this batch would take the host. Refused.
    case refuseHost(configured: String, demand: String)
}

public enum GuestRouteConfig {

    /// The guest a takeover batch should land on. A `gst-` handle or the
    /// name you type at lume / prlctl. Absent or empty means the host.
    public static let env = "PROCTOR_GUEST"

    public static func configured(
        _ environment: [String: String] = ProctorEnvironment.current) -> String? {
        guard let raw = environment[env]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        return raw
    }

    /// Place the batch. Pure: the session's machine, whether the batch
    /// takes the foreground, and the configured name.
    public static func decide(machine: Machine, takesForeground: Bool,
                              configured: String?) -> GuestRoute {
        if machine.isGuest { return .alreadyOnGuest(machine) }
        guard takesForeground, let configured, !configured.isEmpty else { return .host }
        return .refuseHost(
            configured: configured,
            demand: "This batch would take this Mac (synthetic events enter the "
                  + "system event stream). \(env) names \(configured) as the guest "
                  + "it should run on, so the host is refused rather than taken. "
                  + "Reach that guest with proctor_guest action \"reach\", then "
                  + "drive it through the Proctor running inside it. Running the "
                  + "steps here while naming that guest would be a verdict about "
                  + "the wrong machine.")
    }

    public static func refusal(for route: GuestRoute) -> (message: String, remedy: String)? {
        guard case .refuseHost(let configured, let demand) = route else { return nil }
        return (message: demand,
                remedy: "Unset \(env) to allow this batch on this Mac, or reach "
                      + "\(configured) with proctor_guest action \"reach\" and "
                      + "drive it there. Auto-route does not silently take the host.")
    }
}
