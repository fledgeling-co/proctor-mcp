import Foundation
import ProctorCore

// Readiness. Getting a grant wrong presents as elements not being found, which
// a model retries indefinitely, so every probe here carries the fix text for the
// running OS and every missing grant is named.
//
// One probe cannot promise a definite state, and pretending otherwise is what
// PRO-0041 fixed. Screen Recording has no query API; the way to read it is to ask
// ScreenCaptureKit for shareable content and read the failure, and the comment
// that used to sit here said that "either answers or throws, and the throw is the
// denial". Measured on 2026-08-15 it did neither — the call parked and never came
// back, while the same call from a plain script answered in 0.037s. So the probe
// is bounded, and a grant it could not establish reports `unconfirmed` rather
// than borrowing the word for a denial. See `ScreenRecordingProbe` for the bound
// and `GrantProbe` for what is cached.

extension Session {

    func doctor(verbose: Bool) async -> DoctorReport {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let osMajor = version.majorVersion
        let osVersion = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"

        let accessibilityGranted = accessibilityProbe()
        let screenRecording = await screenRecordingProbe.state()
        let shortcutsAvailable = FileManager.default.isExecutableFile(atPath: "/usr/bin/shortcuts")
        let secureInput = secureInputProbe()
        let (attached, observers) = healthSnapshot()
        // Re-probed rather than read from the cache, and written back through it:
        // this is the "now" answer, and after it the health report and the browser
        // handoffs cannot disagree. The status window's Re-check drives this path.
        let (obscura, browserUse) = tools.refreshBoth()
        // Refreshed on the same call, so the health report and the iOS lane
        // cannot disagree about whether this machine has Xcode.
        let simctl = tools.simctl.refreshed()
        let cuaDriver = tools.cuaDriver.refreshed()
        let maestro = tools.maestro.refreshed()
        let lanes = BrowserLanes.make(obscura: obscura, browserUse: browserUse,
                                      environment: tools.environment)
        let toolRows = await toolchainRows(obscura: obscura, browserUse: browserUse,
                                           simctl: simctl, cuaDriver: cuaDriver,
                                           maestro: maestro, secondLane: lanes.secondLane)
        let obscuraRow = toolRows.first { $0.tool == ObscuraTool.binary }

        var grants: [DoctorReport.Grant] = [
            .init(name: "Accessibility", granted: accessibilityGranted, required: true,
                  howToFix: Grants.accessibilityFixText(osMajor: osMajor)),
            .init(name: "Screen Recording", state: screenRecording, required: true,
                  howToFix: screenRecording == .unconfirmed
                      ? Grants.screenRecordingUnconfirmedText(bound: screenRecordingProbe.bound)
                      : Grants.screenRecordingFixText(osMajor: osMajor)),
            // Automation is granted per target application at first use and
            // there is no way to ask about it in advance without triggering the
            // prompt, so it is reported as not yet established rather than as
            // denied.
            .init(name: "Automation", granted: false, required: false,
                  howToFix: "Granted per target application the first time an Apple Event is sent, "
                          + "and not probeable in advance. If a declared-contract step fails with "
                          + "permissionAutomation, approve the prompt or enable the app under "
                          + "System Settings ▸ Privacy & Security ▸ Automation ▸ Proctor.")
        ]

        var blockers: [String] = []
        for grant in grants where grant.required && !grant.granted {
            // A denial and a non-answer are two different facts about a Mac and
            // must not wear one word. One is a permission somebody has to go and
            // grant; the other is a probe that did not come back, where the
            // permission may be sitting there granted the whole time.
            let lead = grant.resolvedState == .unconfirmed
                ? "\(grant.name) could not be confirmed."
                : "\(grant.name) is not granted."
            blockers.append("\(lead) \(grant.howToFix)")
        }
        if !shortcutsAvailable {
            grants.append(.init(name: "Shortcuts CLI", granted: false, required: false,
                                howToFix: "/usr/bin/shortcuts is missing, so `shortcut` steps cannot "
                                        + "run. Every other actuation plane is unaffected."))
        }
        if secureInput {
            blockers.append("Secure Event Input is active, so synthetic-event steps — dragPath, "
                          + "hover, click, key — cannot be delivered. The accessibility plane is "
                          + "unaffected: press, setValue, focus, menu and type all still work.")
        }

        return DoctorReport(
            agentVersion: BuildInfo.current.descriptor,
            protocolVersion: Wire.protocolVersion,
            osVersion: osVersion,
            agentRunning: true,
            socketPath: Wire.socketPath,
            grants: grants,
            attachedApps: verbose ? attached : attached.map {
                DoctorReport.AttachedAppHealth(app: $0.app, name: $0.name, windows: $0.windows,
                                               manualAccessibility: $0.manualAccessibility,
                                               observerAlive: $0.observerAlive, cachedRefs: 0,
                                               reflectorConnected: $0.reflectorConnected)
            },
            observersLive: observers,
            secureEventInputActive: secureInput,
            shortcutsCLIAvailable: shortcutsAvailable,
            // Deliberately not a blocker and not a grant: Proctor drives native
            // applications without Obscura, so `ready` is unaffected. Obscura is
            // what Proctor recommends for a browser page, which is a different
            // question from whether Proctor works.
            //
            // These two are the grandfathered spelling of the `tools` array's
            // first entry, so they are the *same row*, not a second copy of it.
            // A copy taken before the usability axis was derived would disagree
            // with the array about the same tool, which is the one thing the
            // field's own documentation says must not happen.
            obscuraAvailable: obscuraRow?.available ?? obscura.available,
            obscura: obscuraRow ?? obscura,
            obscuraUnavailable: obscura.available ? nil : ObscuraTool.absence,
            // The growth surface. Every *located* tool, in a fixed order, present
            // or absent; a fourth goes here rather than becoming a fourth boolean.
            // /usr/bin/shortcuts stays out on merit: it is an OS component at a
            // fixed absolute path, so a ToolPresence for it would be a shape with
            // three empty fields.
            // browser-use is listed **only when the operator named it**. With the
            // lane off the string does not appear in a tool result at all, which
            // makes the gate a total invariant rather than one about handoffs.
            // simctl, cua-driver and maestro join the same array rather than
            // becoming three more booleans: the field's own documentation names it
            // as the growth surface, and "is there an iOS lane on this machine" is
            // the same shape of question as "is there a browser lane". None of them
            // is a grant and none is a blocker — Proctor drives Mac apps perfectly
            // well without Xcode, without a driver and without Maestro, so `ready`
            // is untouched by their absence, exactly as it is by Obscura's.
            tools: toolRows,
            // Three states, not two: "enabled and not installed" is a real
            // situation an operator who set the variable has to be able to see.
            secondLane: lanes.secondLane.rawValue,
            // The parts behind `agentVersion`, for a reader that wants a field rather
            // than a string to parse.
            agentBuild: BuildInfo.current,
            // What the machine can actually do, derived from the grants and the
            // rows above rather than reported beside them — a lane that announced
            // itself would be free to disagree with both.
            lanes: Toolchain.lanes(tools: toolRows, grants: grants,
                                   secondLane: lanes.secondLane,
                                   cuaLaneSelected: CuaDriverTool.laneSelected(tools.environment)),
            // Posture and shape, never rules. See `DoctorReport.PolicyPosture`.
            policy: policyPosture(),
            // PRO-0029. What the eight runtime switches are set to in THIS agent,
            // and where each value came from. On the wire because the status
            // window cannot work it out: the window is launched by LaunchServices
            // and this process by launchd, so the window's own `ProcessInfo`
            // describes a different environment — plausibly, which is worse than
            // not knowing.
            //
            // Resolved against the INHERITED environment, never the effective one.
            // The effective dictionary already has the saved values folded in, so
            // resolving against it would report every preference as having come
            // from the environment, and therefore as locked — the exact misreport
            // this feature exists to prevent.
            switches: SwitchResolver.reportStates(
                environment: ProctorEnvironment.inherited,
                saved: SwitchStore.load(from: SwitchStore.defaultURL).values),
            ready: blockers.isEmpty,
            blockers: blockers)
    }

    /// One row per tool Proctor looks for, in `Toolchain`'s order.
    ///
    /// This function gathers and hands over; **it decides nothing.**
    /// `Toolchain.row` turns what was observed into a verdict, so every usability
    /// and evidence value is chosen in a pure function that tests on a machine
    /// with none of these tools installed. The plan review found the verdicts
    /// being stamped here, which is the half that cannot be tested that way.
    ///
    /// Nothing in here creates a process. The reads are `stat`, `readlink`, one
    /// property list, and a signature verification that hashes a file — the last
    /// of them cached on the file's identity, because it costs 0.32-0.39s on an
    /// 82 MB binary and the status window calls this every 2.0 seconds.
    private func toolchainRows(obscura: ToolPresence, browserUse: ToolPresence,
                               simctl: ToolPresence, cuaDriver: ToolPresence,
                               maestro: ToolPresence,
                               secondLane: SecondLaneState) async -> [ToolPresence] {
        let now = clock()
        let located: [String: ToolPresence] = [
            ObscuraTool.binary: obscura,
            BrowserUseTool.binary: browserUse,
            "simctl": simctl,
            CuaDriverTool.binary: cuaDriver,
            MaestroTool.binary: maestro
        ]
        // Read once, outside the loop: asking a backend for its lane health
        // establishes nothing and starts nothing, but it is still an actor hop.
        let laneHealth = await actuator.laneHealth

        var rows: [ToolPresence] = []
        for entry in Toolchain.entries {
            if entry.operatorGated && secondLane == .off { continue }
            guard let presence = located[entry.tool] else { continue }

            var facts = ToolFacts(located: presence, checkedAt: now)
            switch entry.tool {
            case MaestroTool.binary:
                facts.installVersion = Toolchain.versionFromInstallPath(
                    symlinkTarget: ToolProbe.symlinkTarget(presence.path))
            case "simctl":
                facts.installVersion = ToolProbe.xcodeVersion(simctlPath: presence.path)
            case CuaDriverTool.binary:
                facts.signature = tools.cuaSignature.verdict(for: presence.path)
                facts.laneReport = laneHealth
            default:
                break
            }
            rows.append(Toolchain.row(entry: entry, facts: facts))
        }
        return rows
    }
}
