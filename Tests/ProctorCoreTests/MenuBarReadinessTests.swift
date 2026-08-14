import Testing
import Foundation
@testable import ProctorCore

// The rung the bug report was about.
//
// PRO-0021 tested `decide` against booleans and nothing tested what produced
// them, which is where all three of PRO-0027's suspected causes lived — so
// "which of the three is it" needed a live Mac and a screenshot rather than a
// test run. These are the assertions that would have answered it, plus the one
// real defect the investigation turned up: the doctor's `ready` folds Secure
// Event Input in with the grants, and the two are not the same fact.
@Suite("Menu bar readiness")
struct MenuBarReadinessTests {

    /// The exact payload `proctor_doctor` returned on a healthy Mac while the
    /// bug was being reported. It decides to the character, which is what made
    /// the readiness ladder innocent.
    private func healthy(secureInput: Bool = false) -> MenuBarBlock? {
        MenuBarIcon.block(requiredGrantsGranted: true,
                          secureEventInputActive: secureInput,
                          ready: !secureInput)
    }

    @Test("a healthy Mac at rest shows the character, not a symbol")
    func healthyIdleIsTheCharacter() {
        #expect(healthy() == nil)
        #expect(MenuBarIcon.decide(reachable: true, block: healthy(), phase: .idle)
                == .character(.idle))
    }

    @Test("a grant that is not required never sinks readiness")
    func optionalGrantsDoNotBlock() {
        // Automation is reported as a grant and reads `granted: false` until an
        // Apple Event is first sent, so it is never granted on a Mac that has not
        // driven a scriptable app. Folding it into readiness would leave a
        // perfectly healthy machine wearing a warning triangle forever.
        let grants = [(required: true, granted: true),     // Accessibility
                      (required: true, granted: true),     // Screen Recording
                      (required: false, granted: false)]   // Automation
        let requiredGranted = grants.filter(\.required).allSatisfy(\.granted)
        #expect(requiredGranted)
        #expect(MenuBarIcon.block(requiredGrantsGranted: requiredGranted,
                                  secureEventInputActive: false, ready: true) == nil)
    }

    @Test("a required grant that is missing keeps the permission symbol")
    func missingRequiredGrantBlocks() {
        let block = MenuBarIcon.block(requiredGrantsGranted: false,
                                      secureEventInputActive: false, ready: false)
        #expect(block == .missingGrant)
        for phase in RunHUDPhase.allCases {
            #expect(MenuBarIcon.decide(reachable: true, block: block, phase: phase)
                    == .symbol("exclamationmark.triangle"), "\(phase)")
        }
    }

    @Test("secure event input has its own symbol, never the permission one")
    func secureInputIsItsOwnState() {
        let block = healthy(secureInput: true)
        #expect(block == .secureInput)
        #expect(MenuBarIcon.decide(reachable: true, block: block, phase: .idle)
                == .symbol("lock.laptopcomputer"))
        #expect(MenuBarBlock.secureInput.symbol != MenuBarBlock.missingGrant.symbol)
    }

    @Test("a missing permission outranks a locked keyboard when both are true")
    func grantOutranksSecureInput() {
        #expect(MenuBarIcon.block(requiredGrantsGranted: false,
                                  secureEventInputActive: true, ready: false) == .missingGrant)
    }

    @Test("secure event input outranks the foreground notice and the phase")
    func secureInputSitsOnTheReadinessRung() {
        // It is a block, so it sits where blocks sit — above the foreground
        // notice and above whatever the run is doing. A password field hiding the
        // character is deliberate: click, key, hover and dragPath are dead while
        // it is on, and that is worth knowing before a run starts.
        #expect(MenuBarIcon.decide(reachable: true, block: .secureInput, phase: .acting,
                                   takingForeground: true) == .symbol("lock.laptopcomputer"))
    }

    @Test("an unreachable agent still outranks every block")
    func unreachableIsFirst() {
        for block in [MenuBarBlock.missingGrant, .secureInput] {
            #expect(MenuBarIcon.decide(reachable: false, block: block, phase: .idle)
                    == .symbol("bolt.horizontal.circle"), "\(block)")
        }
    }

    @Test("a ready that is false for an unrecognised reason still blocks")
    func failsClosedOnAnUnknownBlocker() {
        // The doctor's blockers are a list, and a later change can add to it.
        // A rung whose job is keeping a calm face off a Proctor that cannot work
        // has to fail closed, or the next blocker silently puts the character up.
        #expect(MenuBarIcon.block(requiredGrantsGranted: true,
                                  secureEventInputActive: false, ready: false) == .missingGrant)
    }

    @Test("idle at rest is the character and it is one still frame")
    func idleIsStillAndIsTheCharacter() {
        #expect(MenuBarIcon.decide(reachable: true, block: nil, phase: .idle)
                == .character(.idle))
        for reduced in [false, true] {
            let frames = RunHUDMotion.menuBar(for: .idle, reduceMotion: reduced)
            #expect(frames.count == 1, "reduceMotion \(reduced)")
            #expect(RunHUDMotion.menuBarTick(for: frames) == nil, "reduceMotion \(reduced)")
        }
    }

    @Test("a phase that never arrives rests at idle rather than falling to a symbol")
    func aSilentAgentRestsAtIdle() {
        // The third suspected cause. An agent that publishes no phase leaves the
        // model on its initial value, and that value is idle — so the worst a
        // never-arriving phase can do is show a resting character.
        let fresh = RunHUDState()
        #expect(fresh.model.menuBarPhase == .idle)
        #expect(MenuBarIcon.decide(reachable: true, block: nil, phase: fresh.model.menuBarPhase)
                == .character(.idle))
    }
}

// The rung against a whole `DoctorReport`, in the shape the agent actually
// answers with — which is the level all three suspected causes lived at and the
// level nothing was asserting.
@Suite("Menu bar readiness from a doctor report")
struct MenuBarReadinessFromReportTests {

    /// The report `proctor_doctor` returned on this Mac, at rest, on 2026-08-15,
    /// while the character was reported missing. Transcribed rather than
    /// invented: it is the evidence that ruled the ladder out.
    private func measuredReport(secureInput: Bool = false,
                                accessibility: Bool = true,
                                screenRecording: Bool = true) -> DoctorReport {
        var blockers: [String] = []
        if !accessibility { blockers.append("Accessibility is not granted.") }
        if !screenRecording { blockers.append("Screen Recording is not granted.") }
        if secureInput { blockers.append("Secure Event Input is active.") }
        return DoctorReport(
            agentVersion: "0.1.0", protocolVersion: 1, osVersion: "26.6.0",
            agentRunning: true, socketPath: "/tmp/agent.sock",
            grants: [
                .init(name: "Accessibility", granted: accessibility, required: true, howToFix: ""),
                .init(name: "Screen Recording", granted: screenRecording, required: true, howToFix: ""),
                // Never granted until an Apple Event is first sent, and not
                // required — the exact grant the brief worried was sinking this.
                .init(name: "Automation", granted: false, required: false, howToFix: ""),
            ],
            attachedApps: [], observersLive: 0, secureEventInputActive: secureInput,
            shortcutsCLIAvailable: true, ready: blockers.isEmpty, blockers: blockers)
    }

    /// The same reduction `AgentModel.menuBarIcon` performs.
    private func icon(_ report: DoctorReport, phase: RunHUDPhase = .idle) -> MenuBarIcon {
        let required = report.grants.filter(\.required)
        return MenuBarIcon.decide(
            reachable: true,
            block: MenuBarIcon.block(
                requiredGrantsGranted: !required.isEmpty && required.allSatisfy(\.granted),
                secureEventInputActive: report.secureEventInputActive,
                ready: report.ready),
            phase: phase)
    }

    @Test("a report naming no required grants is not a report saying they are granted")
    func anEmptyGrantListBlocks() {
        // `allSatisfy` over an empty collection is true, so a malformed or empty
        // report would otherwise put a calm character over something that said
        // nothing at all about permissions. Absence of evidence, not evidence.
        var report = measuredReport()
        report.grants = []
        #expect(icon(report) == .symbol("exclamationmark.triangle"))
    }

    @Test("the measured healthy report shows the idle character")
    func measuredHealthyReportIsTheCharacter() {
        let report = measuredReport()
        #expect(report.ready)
        #expect(report.blockers.isEmpty)
        #expect(icon(report) == .character(.idle))
    }

    @Test("Automation ungranted is not what takes the character away")
    func automationIsNotTheCause() {
        let report = measuredReport()
        #expect(report.grants.contains { $0.name == "Automation" && !$0.granted })
        #expect(icon(report) == .character(.idle))
    }

    @Test("each required grant, missing on its own, takes it")
    func eachRequiredGrantBlocks() {
        #expect(icon(measuredReport(accessibility: false)) == .symbol("exclamationmark.triangle"))
        #expect(icon(measuredReport(screenRecording: false)) == .symbol("exclamationmark.triangle"))
    }

    @Test("secure event input makes ready false, and gets its own symbol anyway")
    func secureInputIsNotAPermissionProblem() {
        let report = measuredReport(secureInput: true)
        // `ready` still folds it in, because a model calling proctor_doctor needs
        // "can every plane work" — that field is unchanged and still says no.
        #expect(!report.ready)
        #expect(report.blockers.count == 1)
        // The menu bar asks the narrower question and answers it precisely.
        #expect(icon(report) == .symbol("lock.laptopcomputer"))
    }
}

// The menu bar's fallback picture, asserted against the source. Not a render
// check — there is no window server here and no test target for ProctorUI — so
// this says what it is: the glyph named in the code.
@Suite("Menu bar fallback glyph")
struct MenuBarFallbackTests {

    @Test("a missing picture never claims everything is fine")
    func fallbackIsNotASuccessGlyph() throws {
        let ui = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/ProctorUI")
        let files = try FileManager.default
            .contentsOfDirectory(at: ui, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        #expect(!files.isEmpty)
        let label = try String(contentsOf: ui.appendingPathComponent("MenuBarCharacter.swift"),
                               encoding: .utf8)
        let drawsUnknown = label.contains("systemName: \"questionmark.circle\"")
        // `checkmark.seal` was both this fallback and the pre-character ready
        // glyph, so one picture meant three things and a stale menu bar read as a
        // broken readiness rule. It is not drawn here any more — the file still
        // names it, in the comment that says why it went.
        let drawsSuccess = label.contains("systemName: \"checkmark.seal\"")
        #expect(drawsUnknown)
        #expect(!drawsSuccess)
    }
}

// Whether the app running is the app on disk — the actual cause of the report
// this feature came from.
@Suite("Build stamp")
struct BuildStampTests {

    private func inTemporaryDirectory(_ body: (URL) throws -> Void) throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("pro-0027-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try body(dir)
    }

    @Test("an unchanged file reads as the build that is running")
    func unchangedIsCurrent() throws {
        try inTemporaryDirectory { dir in
            let file = dir.appendingPathComponent("proctor")
            try Data("build one".utf8).write(to: file)
            let was = BuildStamp.of(path: file.path)
            #expect(was != nil)
            #expect(!BuildStamp.replaced(running: [was], onDisk: [BuildStamp.of(path: file.path)]))
        }
    }

    @Test("a replaced file is a different build even at the same size")
    func replacedFileIsDetected() throws {
        try inTemporaryDirectory { dir in
            let file = dir.appendingPathComponent("proctor")
            try Data("build one".utf8).write(to: file)
            let was = BuildStamp.of(path: file.path)
            // What an upgrade does: unlink and write a new file. Same length, so
            // only the inode moves — which is the case a size check would miss.
            try FileManager.default.removeItem(at: file)
            try Data("build two".utf8).write(to: file)
            let now = BuildStamp.of(path: file.path)
            #expect(was?.size == now?.size)
            #expect(was?.inode != now?.inode)
            #expect(BuildStamp.replaced(running: [was], onDisk: [now]))
        }
    }

    @Test("a file that grew in place is a different build")
    func changedSizeIsDetected() throws {
        try inTemporaryDirectory { dir in
            let file = dir.appendingPathComponent("proctor")
            try Data("build one".utf8).write(to: file)
            let was = BuildStamp.of(path: file.path)
            try Data("build one, but longer".utf8).write(to: file)
            #expect(BuildStamp.replaced(running: [was], onDisk: [BuildStamp.of(path: file.path)]))
        }
    }

    @Test("touching a file replaces nothing and raises nothing")
    func touchIsNotAnUpgrade() throws {
        try inTemporaryDirectory { dir in
            let file = dir.appendingPathComponent("proctor")
            try Data("build one".utf8).write(to: file)
            let was = BuildStamp.of(path: file.path)
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(600)],
                                                 ofItemAtPath: file.path)
            #expect(!BuildStamp.replaced(running: [was], onDisk: [BuildStamp.of(path: file.path)]))
        }
    }

    @Test("a path nobody can stat says nothing either way")
    func unreadablePathsAreSilent() throws {
        try inTemporaryDirectory { dir in
            let file = dir.appendingPathComponent("proctor")
            try Data("build one".utf8).write(to: file)
            let was = BuildStamp.of(path: file.path)
            #expect(BuildStamp.of(path: dir.appendingPathComponent("gone").path) == nil)
            // Nagging about a path that cannot be read is worse than silence, in
            // both directions.
            #expect(!BuildStamp.replaced(running: [was], onDisk: [nil]))
            #expect(!BuildStamp.replaced(running: [nil], onDisk: [was]))
            #expect(!BuildStamp.replaced(running: [nil], onDisk: [nil]))
        }
    }

    @Test("any one of the watched paths moving is enough")
    func anyPathIsEnough() throws {
        try inTemporaryDirectory { dir in
            // The binary and the art are stamped separately because the picture
            // that goes missing is an asset: a reinstall that replaced only the
            // resource bundle would leave a Mach-O stamp untouched.
            let binary = dir.appendingPathComponent("proctor")
            let art = dir.appendingPathComponent("idle-0.png")
            try Data("binary".utf8).write(to: binary)
            try Data("art".utf8).write(to: art)
            let was = [BuildStamp.of(path: binary.path), BuildStamp.of(path: art.path)]
            try Data("art, redrawn".utf8).write(to: art)
            let now = [BuildStamp.of(path: binary.path), BuildStamp.of(path: art.path)]
            #expect(was[0] == now[0])
            #expect(BuildStamp.replaced(running: was, onDisk: now))
        }
    }
}

// The one part of a relaunch that can be silently wrong.
@Suite("Relaunch command")
struct RelaunchCommandTests {

    @Test("it waits for this process to go before opening the bundle")
    func waitsThenOpens() {
        let args = RelaunchCommand.arguments(pid: 4321, bundlePath: "/Applications/Proctor.app")
        #expect(args.first == "-c")
        let script = args.last ?? ""
        // `open` on a running single-instance menu bar app activates the instance
        // already there, so the wait is the whole mechanism, not politeness.
        #expect(script.contains("kill -0 4321"))
        #expect(script.range(of: "kill -0")!.lowerBound < script.range(of: "open ")!.lowerBound)
        #expect(script.contains("open '/Applications/Proctor.app'"))
    }

    @Test("a quote in the path is escaped rather than ending the command")
    func quotesAreEscaped() {
        let script = RelaunchCommand.arguments(pid: 1, bundlePath: "/Users/luke's/Proctor.app").last!
        #expect(script.hasSuffix("open '/Users/luke'\\''s/Proctor.app'"))
        #expect(RelaunchCommand.quoted("plain") == "'plain'")
    }
}
