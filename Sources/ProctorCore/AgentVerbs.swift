import Foundation

/// The verbs Proctor's own window speaks to Proctor's own agent, and the keys of
/// the payloads that come back.
///
/// PRO-0090, DEF-039 and DEF-035 one layer down. `AgentModel.swift` read
/// `value["canShow"]`, `value["queueWaiting"]`, `f?["yield"]?["line"]` and
/// eighteen more like them, and every one of those spellings had a second,
/// unbound definition on the agent side — `RunHUDFeed.wire` writes the HUD four,
/// `Session.recentActivity` writes the activity feed, `Session.foregroundJSON`
/// writes the foreground block. Nothing failed when the two parted: a renamed key
/// reads back as the `?? false` default, so the menu bar would have gone quietly
/// wrong about whether a run was taking the machine rather than failing loudly
/// about a contract.
///
/// This is `HistorySurface.Wire`'s handling applied to the second pair of ends,
/// and it is here rather than in a `Copy` enum for the reason that one is: these
/// strings address the machine, and nobody reads them.
///
/// The verbs below are **internal**. None is in `ToolCatalogue`, so the shim —
/// which gates `tools/call` on the catalogue — cannot reach them and no MCP host
/// can put a person's stop button away or read their activity feed through this
/// path. `proctor_doctor` is the exception and is a catalogue tool; it is named
/// here because the window calls it by the same name.
public enum AgentVerbs {

    /// The full report the status window polls. A catalogue tool.
    public static let doctor = "proctor_doctor"
    /// The "what is it doing now" feed the menu bar polls.
    public static let recentActivity = "proctor_recent_activity"
    /// The run panel's switch, and the run's Pause, Resume and Stop.
    public static let hud = "proctor_hud"
    /// The queue's own Hold and Clear, kept apart from the run's pair because
    /// calling both "pause" is how somebody stops the wrong thing.
    public static let queue = "proctor_queue"

    /// The argument both control verbs take.
    public static let actionArgument = "action"

    /// The two flags on a doctor call that ask macOS for a consent dialog rather
    /// than only reading the recorded answer.
    public enum DoctorFlag {
        public static let requestAccessibility = "requestAccessibility"
        public static let requestScreenRecording = "requestScreenRecording"
    }

    /// `Session.recentActivity`'s projection.
    public enum Activity {
        public static let current = "current"
        public static let recent = "recent"
        public static let queueWaiting = "queueWaiting"
        public static let hud = "hud"
        public static let foreground = "foreground"

        /// One row of `recent`.
        public static let tool = "tool"
        public static let at = "at"
        public static let ok = "ok"
    }

    /// `Session.foregroundJSON`, of which the window reads seven keys. The block
    /// carries more than these; what is named here is what has two ends.
    public enum Foreground {
        public static let running = "running"
        public static let active = "active"
        public static let takesForeground = "takesForeground"
        public static let mayTakeForeground = "mayTakeForeground"
        public static let notice = "notice"
        /// Held, and why — its own nested object.
        public static let yield = "yield"
        public static let line = "line"
    }

    /// `RunHUDFeed.wire`, in full. All four have both ends.
    public enum HUD {
        public static let phase = "phase"
        public static let running = "running"
        public static let drawing = "drawing"
        public static let canShow = "canShow"
        /// Sits beside `hud` in a control verb's reply rather than inside it: it
        /// is about the request, not about the panel.
        public static let refused = "refused"
    }
}

/// What `codesign -dv` writes about this bundle, and what Proctor reads out of it.
///
/// PRO-0090. `SignatureInfo.current()` parsed three field names and matched one
/// whole line out of the tool's output with the spellings inline. They are the
/// tool's vocabulary rather than Proctor's, which is what makes them worth
/// naming: a reader of that function cannot tell a typo from the real thing, and
/// a mistyped field returns nil, which the window draws as "Unsigned" — a claim
/// about a security property, made from a parse failure.
public enum CodesignOutput {
    public static let teamIdentifier = "TeamIdentifier"
    public static let authority = "Authority"
    /// The whole line, matched as a substring. `codesign` writes it only for an
    /// ad-hoc signature.
    public static let adHocMarker = "Signature=adhoc"
    /// What `TeamIdentifier` says when there is no team, which is not a team id.
    public static let teamNotSet = "not set"
}
