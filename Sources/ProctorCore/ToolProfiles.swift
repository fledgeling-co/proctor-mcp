import Foundation

// Tool profiles trim the advertised surface at launch, so a host that only needs
// the core loop is not handed the whole catalogue as noise. The profile is chosen
// where the shim is launched (`--profile`, or PROCTOR_PROFILE), because the shim is
// stateless per message and the HTTP transport closes each connection — a profile
// negotiated inside `initialize` could not survive to the `tools/list` call.
//
// The profiles nest: ax ⊂ core ⊂ scripting ⊂ full. That keeps membership obvious
// and lets a host widen its surface by moving one step out. Every profile carries
// `apps` (nothing works before attach) and `doctor` (the run-first tool).

public enum ToolProfile: String, Sendable, CaseIterable {
    case ax
    case core
    case scripting
    case full

    /// Parse a launch argument. Unknown or empty selects nothing, so a caller can
    /// fall back to `.full` deliberately rather than silently swallowing a typo.
    public init?(argument: String?) {
        guard let argument, !argument.isEmpty else { return nil }
        self.init(rawValue: argument.lowercased())
    }

    public static var names: [String] { allCases.map(\.rawValue) }
}

public extension ToolCatalogue {
    /// The tool names each profile advertises, smallest first. Defined as names so
    /// the nesting is verifiable independently of the spec order in `all`.
    private static let profileNames: [ToolProfile: [String]] = {
        let ax = ["proctor_apps", "proctor_snapshot", "proctor_find", "proctor_menu",
                  "proctor_act", "proctor_wait", "proctor_assert", "proctor_doctor"]
        let core = ax + ["proctor_capture"]
        let scripting = core + ["proctor_flow", "proctor_stability"]
        let full = all.map(\.name)
        return [.ax: ax, .core: core, .scripting: scripting, .full: full]
    }()

    /// The tools advertised for a profile, in catalogue order. Unknown names in a
    /// profile list are ignored rather than crashing, so a catalogue change cannot
    /// silently drop a profile.
    static func tools(for profile: ToolProfile) -> [ToolSpec] {
        let wanted = Set(profileNames[profile] ?? all.map(\.name))
        return all.filter { wanted.contains($0.name) }
    }

    static func toolNames(for profile: ToolProfile) -> [String] {
        tools(for: profile).map(\.name)
    }
}
