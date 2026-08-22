import Foundation
import Testing
@testable import ProctorCore

// PRO-0082, A4 and DEF-182. The line PRO-0041 deliberately left behind.
//
// PRO-0041 took "Already allowed?" off the status window's grant row, because a
// person who HAS already allowed the permission and is still looking at an
// ungranted row is not helped by a pane that will show them a switch already
// turned on — their answer is a restart, which `restartNote` says a few lines
// above this very button. It recorded the walkthrough's copy of the same
// misdirection as a child item and did not take it. This is that item.

@Suite("The walkthrough's Settings button says what the status window's says")
struct WalkthroughSettingsLineTests {

    @Test("the two surfaces offer the same words for the same control")
    func theTwoConstantsAgree() {
        // Two constants with one value, bound by a test, rather than one constant
        // read from two files — the reason `introCalloutTitle` already gives in
        // WalkthroughFlow: two surfaces agreeing today is not a reason for an edit
        // to one to change the other silently. This is where they part company
        // loudly.
        #expect(WalkthroughFlow.Copy.openSettings == StatusSurface.Copy.openSettings)
        #expect(WalkthroughFlow.Copy.openSettings == "Open Settings")
    }

    @Test("the button names the destination and asks nothing")
    func theButtonAsksNoQuestion() {
        let label = WalkthroughFlow.Copy.openSettings
        #expect(!label.contains("?"), "a button that asks a question makes the person answer it before pressing")
        #expect(!label.lowercased().contains("already allowed"))
        #expect(label.contains("Settings"), "the control must still name where it goes")
    }

    @Test("the answer the old question misdirected from is still said, in its own sentence")
    func theRestartNoteStillCarriesTheRealAnswer() {
        // Removing the question must not remove the information. The person the
        // question was addressed to — already granted, still seeing an ungranted
        // row — needs the restart, and this is the sentence that tells them.
        let note = WalkthroughFlow.Copy.restartNote
        #expect(!note.isEmpty)
        #expect(note.lowercased().contains("restart") || note.lowercased().contains("quit"),
                "restartNote no longer names the restart: “\(note)”")
    }

    @Test("the question form survives nowhere in the shipped sources")
    func theOldWordingIsGoneFromEverySource() throws {
        // The value check above passes if the sentence is merely duplicated
        // somewhere else — which is how a string that "moved" stays on screen.
        // So the whole of Sources is scanned for it.
        var scanned = 0
        var offenders: [String] = []
        let root = Self.repositoryRoot.appendingPathComponent("Sources")
        let walker = try #require(FileManager.default.enumerator(atPath: root.path))
        for case let name as String in walker where name.hasSuffix(".swift") {
            let text = try String(contentsOf: root.appendingPathComponent(name), encoding: .utf8)
            scanned += 1
            // The comment in WalkthroughFlow.swift quotes the retired sentence to
            // record what it replaced, so the scan reads code with whole-line
            // comments dropped — the same treatment the literals tests use.
            let code = text.split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
            if code.contains("Already allowed") { offenders.append(name) }
        }
        #expect(scanned > 50, "the scan walked only \(scanned) files; a scan that finds nothing because it read nothing is not a clean result")
        #expect(offenders.isEmpty,
                Comment(rawValue: "the retired question is still in \(offenders.joined(separator: ", "))"))
    }

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
