import Foundation

// PRO-0029. Which of two real inputs wins, and how a window says so honestly.
//
// An environment variable set by whoever launched the agent and a saved
// preference are both genuine statements of intent, and the rule between them is
// not one rule.
//
// **Ordinary switches: the environment wins, and the control locks.** The
// environment is set by whoever started THIS agent — a CI harness, a wrapper, a
// `launchctl setenv` — and applies to this launch. A preference saved months ago
// silently overriding a deliberate `PROCTOR_ACTUATION=cua` would mean a run
// measures a code path its reader did not choose, which is the thing PRO-0051
// settled and the wave 7 direction warns about twice.
//
// **Capability switches: off wins from either source, and the control never
// locks.** THE OUT-OF-FAMILY GATE FOUND THE FIRST DRAFT FAILING UNSAFELY HERE and
// it was right. Under one blanket rule, `PROCTOR_TAKEOVER_INPUT=1` in the agent's
// launch environment creates the event tap that swallows a person's keyboard, and
// the lock rule then DISABLES the only control that could turn it off. The person
// whose keyboard is being eaten is shown a switch they cannot press, and their
// remedy is to find an environment variable and restart a background process.
//
// That inverts the reasoning the switch was built on. `InputBlocker.isEnabled` is
// read once precisely so a tap can never appear without somebody asking, and
// `Takeover`'s own comment refuses to make the stronger capability a default while
// the weaker stays opt-in. A locked-on off-switch is the same mistake in a new
// place. The asymmetry costs the first rule nothing: a capability escalation that
// anyone can decline is not a lane selector whose whole value is that it cannot be
// silently cancelled.
//
// **This file is pure.** The store's IO is in `SwitchStore`; the effective
// environment it produces is consumed by call sites that already take a
// dictionary, so nothing downstream changes how it reads.

/// Where an effective value came from.
public enum SwitchSource: String, Sendable, Equatable, Codable, CaseIterable {
    /// The agent's own process environment. Almost always inherited rather than
    /// written by an installer: `install.sh` writes no `EnvironmentVariables` key,
    /// so a value here usually arrives from `launchctl setenv` or a wrapper — and
    /// survives every reinstall, invisibly, which is why the window says the word.
    case environment
    /// The preference file this feature added.
    case saved
    /// Neither said anything.
    case builtInDefault
}

/// One switch's answer, with everything a window needs to say it honestly.
public struct SwitchResolution: Sendable, Equatable {
    public let variable: String
    /// Whether the switch is on, after precedence.
    public let on: Bool
    /// The raw string the agent would read, or nil when nothing set it.
    public let rawValue: String?
    public let source: SwitchSource
    /// Whether the window's control should be disabled. **Never true for a
    /// capability switch**, whatever the environment says.
    public let locked: Bool
    /// Whether a change lands now or at the next agent start.
    public let timing: ProctorSwitch.Timing

    public init(variable: String, on: Bool, rawValue: String?, source: SwitchSource,
                locked: Bool, timing: ProctorSwitch.Timing) {
        self.variable = variable
        self.on = on
        self.rawValue = rawValue
        self.source = source
        self.locked = locked
        self.timing = timing
    }
}

public enum SwitchResolver {

    // MARK: - Reading one value

    /// Whether a raw string turns this switch on, following the switch's own
    /// shape. One reader for both sources, so the window and the agent can never
    /// disagree about a string.
    ///
    /// The three shapes are the ones already in the tree, not new ones:
    /// `OverlaySwitch`'s "anything but an off-value, including unset", the
    /// opt-ins' "set, non-empty and not an off-value", and the lanes' exact match
    /// on a tool name. A lane is the one that bites — `PROCTOR_SECOND_LANE=1` is
    /// OFF, because `BrowserUseTool.enabled` compares against `browser-use`.
    public static func isOn(_ raw: String?, for aSwitch: ProctorSwitch) -> Bool {
        switch aSwitch.kind {
        case .drawing:
            return OverlaySwitch.isOn(raw)
        case .capability:
            guard let raw else { return false }
            let value = raw.trimmingCharacters(in: .whitespaces).lowercased()
            return !value.isEmpty && !OverlaySwitch.offValues.contains(value)
        case .lane:
            guard let raw, let onValue = aSwitch.onValue else { return false }
            return raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == onValue
        }
    }

    /// The string that turns a switch on when a window saves it.
    ///
    /// For a lane this is the tool's own name, never `1` — a saved `1` would read
    /// as enabled in the window and be off in the agent, which is the precise
    /// failure the brief warned a toggle can have.
    public static func onValue(for aSwitch: ProctorSwitch) -> String {
        aSwitch.onValue ?? "1"
    }

    public static func offValue(for aSwitch: ProctorSwitch) -> String { "0" }

    // MARK: - Precedence

    /// The whole rule, for one switch.
    public static func resolve(_ aSwitch: ProctorSwitch,
                               environment: [String: String],
                               saved: [String: String]) -> SwitchResolution {
        let envRaw = environment[aSwitch.variable]
        let savedRaw = saved[aSwitch.variable]

        switch aSwitch.kind {
        case .drawing, .lane:
            if let envRaw {
                return SwitchResolution(variable: aSwitch.variable,
                                        on: isOn(envRaw, for: aSwitch), rawValue: envRaw,
                                        source: .environment, locked: true,
                                        timing: aSwitch.timing)
            }
            if let savedRaw {
                return SwitchResolution(variable: aSwitch.variable,
                                        on: isOn(savedRaw, for: aSwitch), rawValue: savedRaw,
                                        source: .saved, locked: false, timing: aSwitch.timing)
            }
            return SwitchResolution(variable: aSwitch.variable, on: aSwitch.defaultOn,
                                    rawValue: nil, source: .builtInDefault, locked: false,
                                    timing: aSwitch.timing)

        case .capability:
            // Off wins from either source. Both must want it on, and the control
            // is never locked, so a person can always decline a capability over
            // their own machine.
            let envOn = isOn(envRaw, for: aSwitch)
            let savedOn = savedRaw.map { isOn($0, for: aSwitch) }
            let on = envOn && (savedOn ?? true)

            let source: SwitchSource
            if !on, savedOn == false, envOn {
                // The saved preference is what turned it off, and saying so is the
                // point: a person looking at a switch they declined should see that
                // their choice is the one in force.
                source = .saved
            } else if envRaw != nil {
                source = .environment
            } else if savedRaw != nil {
                source = .saved
            } else {
                source = .builtInDefault
            }

            return SwitchResolution(variable: aSwitch.variable, on: on,
                                    rawValue: on ? (envRaw ?? savedRaw) : nil,
                                    source: source, locked: false, timing: aSwitch.timing)
        }
    }

    /// Every switch, in catalogue order.
    public static func resolveAll(environment: [String: String],
                                  saved: [String: String]) -> [SwitchResolution] {
        SwitchCatalogue.all.map { resolve($0, environment: environment, saved: saved) }
    }

    // MARK: - The overlay the agent installs

    /// The process environment with the saved preferences folded in, so the seven
    /// existing call sites keep reading a dictionary and none of their settled
    /// read-once reasoning has to change.
    ///
    /// This is the whole mechanism by which a saved preference reaches the agent.
    /// Values are written in each switch's own on/off spelling, so
    /// `BrowserUseTool.enabled` and `CuaDriverTool.laneSelected` — which compare
    /// against a literal — keep working unmodified.
    ///
    /// Only the eight are touched. Every other variable passes through untouched,
    /// including `PATH`, which several tool probes depend on.
    public static func effectiveEnvironment(processEnvironment: [String: String],
                                            saved: [String: String]) -> [String: String] {
        var out = processEnvironment
        for aSwitch in SwitchCatalogue.all {
            let resolution = resolve(aSwitch, environment: processEnvironment, saved: saved)
            switch resolution.source {
            case .environment:
                // Already correct in the dictionary — except for a capability the
                // saved preference declined, which the branch below catches.
                if aSwitch.kind == .capability, !resolution.on {
                    out.removeValue(forKey: aSwitch.variable)
                }
            case .saved:
                if resolution.on {
                    out[aSwitch.variable] = onValue(for: aSwitch)
                } else if aSwitch.kind == .drawing {
                    // A drawing switch reads UNSET as ON, so "off" has to be
                    // written as an off-value. Removing the key here would turn
                    // the thing on — the opposite of what was saved.
                    out[aSwitch.variable] = offValue(for: aSwitch)
                } else {
                    // A capability reads unset and "0" identically, and a lane
                    // reads anything that is not its own name as off, so removal
                    // is correct for both and leaves no value to misread.
                    out.removeValue(forKey: aSwitch.variable)
                }
            case .builtInDefault:
                break
            }
        }
        return out
    }

    // MARK: - What the report carries

    /// Every switch as the agent has it, ready for `DoctorReport.switches`.
    ///
    /// The pairing warnings are computed here rather than in the window, so the
    /// four combinations are testable without a window server — and so the same
    /// sentence reaches a model reading `proctor_doctor` and a person reading the
    /// status window, rather than two sentences that drift.
    public static func reportStates(environment: [String: String],
                                    saved: [String: String]) -> [SwitchState] {
        let resolutions = resolveAll(environment: environment, saved: saved)
        let byName = Dictionary(uniqueKeysWithValues: resolutions.map { ($0.variable, $0) })

        return SwitchCatalogue.all.map { aSwitch in
            let resolution = byName[aSwitch.variable]!
            var warning: String?
            if let pairing = SwitchCatalogue.pairings.first(where: { $0.capability == aSwitch }),
               let announces = byName[pairing.announces.variable] {
                warning = SwitchCatalogue.pairingWarning(capabilityOn: resolution.on,
                                                         announcesOn: announces.on,
                                                         capability: aSwitch)
            }
            return SwitchState(variable: resolution.variable,
                               on: resolution.on,
                               source: resolution.source.rawValue,
                               locked: resolution.locked,
                               timing: resolution.timing.rawValue,
                               pairingWarning: warning)
        }
    }
}
