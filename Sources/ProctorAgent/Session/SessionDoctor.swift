import Foundation
import ScreenCaptureKit
import ProctorCore

// Readiness. Getting a grant wrong presents as elements not being found, which
// a model retries indefinitely, so every probe here reports a definite state
// and every missing grant carries the fix text for the running OS.

extension Session {

    func doctor(verbose: Bool) async -> DoctorReport {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let osMajor = version.majorVersion
        let osVersion = "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"

        let accessibilityGranted = Grants.accessibility()
        let screenRecordingGranted = await Self.probeScreenRecording()
        let shortcutsAvailable = FileManager.default.isExecutableFile(atPath: "/usr/bin/shortcuts")
        let secureInput = Grants.secureEventInputActive()
        let (attached, observers) = healthSnapshot()
        // Re-probed rather than read from the cache, and written back through it:
        // this is the "now" answer, and after it the health report and the browser
        // handoffs cannot disagree. The status window's Re-check drives this path.
        let (obscura, browserUse) = tools.refreshBoth()
        let lanes = BrowserLanes.make(obscura: obscura, browserUse: browserUse,
                                      environment: tools.environment)

        var grants: [DoctorReport.Grant] = [
            .init(name: "Accessibility", granted: accessibilityGranted, required: true,
                  howToFix: Grants.accessibilityFixText(osMajor: osMajor)),
            .init(name: "Screen Recording", granted: screenRecordingGranted, required: true,
                  howToFix: Grants.screenRecordingFixText(osMajor: osMajor)),
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
            blockers.append("\(grant.name) is not granted. \(grant.howToFix)")
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
            obscuraAvailable: obscura.available,
            obscura: obscura,
            obscuraUnavailable: obscura.available ? nil : ObscuraTool.absence,
            // The growth surface. Every *located* tool, in a fixed order, present
            // or absent; a fourth goes here rather than becoming a fourth boolean.
            // /usr/bin/shortcuts stays out on merit: it is an OS component at a
            // fixed absolute path, so a ToolPresence for it would be a shape with
            // three empty fields.
            // browser-use is listed **only when the operator named it**. With the
            // lane off the string does not appear in a tool result at all, which
            // makes the gate a total invariant rather than one about handoffs.
            tools: lanes.secondLane == .off ? [obscura] : [obscura, browserUse],
            // Three states, not two: "enabled and not installed" is a real
            // situation an operator who set the variable has to be able to see.
            secondLane: lanes.secondLane.rawValue,
            // The parts behind `agentVersion`, for a reader that wants a field rather
            // than a string to parse.
            agentBuild: BuildInfo.current,
            ready: blockers.isEmpty,
            blockers: blockers)
    }

    /// Screen Recording has no query API. Asking ScreenCaptureKit for shareable
    /// content either answers or throws, and the throw is the denial.
    private static func probeScreenRecording() async -> Bool {
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            return true
        } catch {
            return false
        }
    }
}
