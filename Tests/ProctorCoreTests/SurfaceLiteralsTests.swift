import Foundation
import Testing
@testable import ProctorCore

// PRO-0090. What the surfaces say, where the words live, and the branch that
// could not be reached.
//
// The Python classifier — `scripts/campaign/status_literals.py` — is the other
// half of this and answers a different question: it says a view holds no literal.
// It cannot say the literal that left resolved back to the same sentence, that a
// drawing site points at the constant a reader was promised, or that a branch a
// state machine cannot reach is gone. These are the Swift half.
@Suite("Surface literals")
struct SurfaceLiteralsTests {

    // MARK: - DEF-037 · the branch that cannot be reached

    @Test("A4 · the permissions section has no branch for an unreachable agent")
    func readinessHasNoUnreachableBranch() throws {
        // The state machine says so first, which is why the branch was dead:
        // an unreachable agent is `.down`, and `.down` draws `agentDown` alone.
        #expect(!StatusSurface.sections(for: .down).contains(.permissions))

        let section = try Self.slice(of: Self.codeOnly(Self.mainWindow()),
                                     from: "private struct ReadinessSection: View {",
                                     to: "private struct GrantRow: View {")
        #expect(!section.contains("case .unreachable"),
                "ReadinessSection matches .unreachable again; sections(for: .down) never gives it that state, so the branch draws for nobody")
    }

    @Test("A4 · the agent-down block is what draws while a grant is being applied")
    func agentDownDrawsApplying() throws {
        let section = try Self.slice(of: Self.codeOnly(Self.mainWindow()),
                                     from: "private struct AgentDownSection: View {",
                                     to: "private struct LanesSection: View {")
        // `isApplying` with an unreachable agent is a real state — a grant lands,
        // `reprobeAfterGrant()` restarts the agent, and the 2-second poll meets
        // the gap — and this is the only block on screen in it.
        #expect(section.contains("model.isApplying"),
                "AgentDownSection no longer draws the applying treatment, so a restart Proctor asked for reads as the agent failing")
        #expect(section.contains("StatusSurface.Copy.applying"))
    }

    // MARK: - DEF-035 · the drawing site, not the constant

    @Test("A6 · the Tools card names Copy.toolsNote, and no view draws the twin")
    func toolsCardBindsToShippedNote() throws {
        // A value-level check reads the constant while the window draws the
        // literal, which is how DEF-035 survived a suite that already had one.
        // This binds the *drawing site*. It is source-analysis and claims nothing
        // above that rung: it proves the view references the constant, not that a
        // rendered window carries the sentence.
        let tools = try Self.slice(of: Self.codeOnly(Self.mainWindow()),
                                   from: "private struct ToolsSection: View {",
                                   to: "private struct ToolRowView: View {")
        #expect(tools.contains("StatusSurface.Copy.toolsNote"),
                "the Tools card stopped naming Copy.toolsNote; a literal there is exactly what DEF-035 was")

        // The diverged twins are wave 9's deliberate pairs: the design of record
        // says one thing, the shipped window says another, and both are kept and
        // named. Neither may be what a view draws.
        for file in Self.viewFiles {
            let source = Self.codeOnly(try Self.source("Sources/ProctorUI/\(file)"))
            for twin in ["toolsNoteInDesign", "switchesNoteInDesign"] {
                #expect(!source.contains(twin),
                        "\(file) draws \(twin); the …InDesign constants record what the mock says, never what ships")
            }
        }
    }

    // MARK: - DEF-039 · the command ids and the extra's wording

    @Test("A2 · every named command id resolves, and title returns the catalogue's")
    func commandIdsResolve() {
        for id in CommandSurface.CommandID.all {
            let command = CommandSurface.command(id)
            #expect(command != nil,
                    "CommandID names \(id) and CommandSurface.all has no such command, so commandButton draws nothing at all")
            #expect(CommandSurface.title(id) == command?.title)
        }
        // And the other way, so a command added to the table without a named id
        // leaves a literal for the next caller to write.
        let named = Set(CommandSurface.CommandID.all)
        for command in CommandSurface.all {
            #expect(named.contains(command.id),
                    "\(command.id) is in the catalogue and CommandID does not name it")
        }
    }

    @Test("A2 · the extra's own three wordings are the three that differ")
    func extrasCopyIsOnlyWhatDiffers() {
        // Kept and named rather than reconciled: choosing which wording ships is
        // a reader's call. What this holds is that the pair is deliberate — the
        // two that differ still differ, so a silent convergence is a change
        // somebody made rather than drift nobody noticed.
        #expect(CommandSurface.ExtrasCopy.status
                != CommandSurface.title(CommandSurface.CommandID.status))
        #expect(CommandSurface.ExtrasCopy.history
                != CommandSurface.title(CommandSurface.CommandID.history))
        // And the one that agrees is asserted to agree, so it cannot part quietly.
        #expect(CommandSurface.ExtrasCopy.quit
                == CommandSurface.title(CommandSurface.CommandID.quit))
    }

    @Test("A2 · every shortcut is written with the named glyphs and one key")
    func shortcutsUseNamedGlyphs() {
        let glyphs = Set(CommandSurface.ShortcutGlyph.all)
        #expect(glyphs.count == 4)
        var withShortcut = 0
        for command in CommandSurface.all {
            guard let shortcut = command.shortcut else { continue }
            withShortcut += 1
            let keys = shortcut.filter { !glyphs.contains($0) }
            #expect(keys.count == 1,
                    "\(command.id)'s shortcut \(shortcut) does not reduce to modifiers plus one key, so KeyEquivalentParser cannot read it")
        }
        // The instrument could report zero by finding no shortcuts at all.
        #expect(withShortcut >= 5)
    }

    // MARK: - DEF-039 · the second wire contract

    @Test("A2 · the window reads the agent's payload through named constants")
    func agentModelNamesTheWireKeys() throws {
        let model = Self.codeOnly(try Self.source("Sources/ProctorUI/AgentModel.swift"))
        // Every key the window reads out of the agent's replies. A literal here
        // is a second definition of a contract, and a renamed key does not fail —
        // it reads back as the `?? false` default.
        let bound = ["phase", "running", "drawing", "canShow", "refused",
                     "recent", "tool", "at", "ok", "current", "queueWaiting",
                     "hud", "foreground", "takesForeground", "mayTakeForeground",
                     "notice", "yield", "line", "active",
                     "requestAccessibility", "requestScreenRecording",
                     "proctor_doctor", "proctor_recent_activity",
                     "proctor_hud", "proctor_queue", "action",
                     "TeamIdentifier", "Authority", "Signature=adhoc"]
        for key in bound {
            #expect(!model.contains("\"\(key)\""),
                    "AgentModel.swift spells \"\(key)\" itself; the agent spells it too and nothing binds the two")
        }
        #expect(model.contains("AgentVerbs."))
    }

    @Test("A2 · the agent's own writers reach the same constants")
    func agentWritersNameTheWireKeys() throws {
        for path in ["Sources/ProctorAgent/Overlay/RunHUDFeed.swift",
                     "Sources/ProctorAgent/Session/Session.swift",
                     "Sources/ProctorAgent/Session/SessionHUD.swift",
                     "Sources/ProctorAgent/Dispatch.swift"] {
            #expect(Self.codeOnly(try Self.source(path)).contains("AgentVerbs."),
                    "\(path) writes the payload the window reads and no longer names AgentVerbs")
        }
    }

    // MARK: - A2 · the moved sentences are the shipped sentences

    @Test("A2 · the log line reads exactly as it did before the move")
    func logLineIsVerbatim() {
        // Composed from a prefix and a reason, so the assembly is what can drift.
        #expect(AppLog.loginItemNotRegistered("boom")
                == "Proctor: could not register login item — boom")
    }

    @Test("A2 · the menu bar's lines read exactly as they did before the move")
    func menuBarLinesAreVerbatim() {
        let bar = StatusSurface.MenuBar.self
        #expect(bar.ready(attachedApps: 2) == "Ready · 2 app(s) attached")
        #expect(bar.permissionsNeeded(1) == "1 permission needed")
        #expect(bar.permissionsNeeded(2) == "2 permissions needed")
        #expect(bar.waitingSuffix(0) == "")
        #expect(bar.waitingSuffix(3) == " · 3 waiting")
        #expect(bar.takingForeground(waiting: 0) == "Taking the foreground now")
        #expect(bar.takingForeground(waiting: 1) == "Taking the foreground now · 1 waiting")
        #expect(bar.running("proctor_act", waiting: 0) == "Running proctor_act")
        #expect(bar.lastRan("proctor_act", waiting: 2) == "Last: proctor_act · 2 waiting")
        #expect(bar.held("Held for a password field", waiting: 0)
                == "Held for a password field")
        #expect(bar.sessionsWaiting(1) == "1 session waiting")
        #expect(bar.sessionsWaiting(4) == "4 sessions waiting")
    }

    @Test("A2 · the scene names have one definition, not four")
    func sceneNamesAreNamed() throws {
        let app = Self.codeOnly(try Self.source("Sources/ProctorUI/ProctorUIApp.swift"))
        // The status scene's id is what `openWindow` addresses and its title is
        // what the launch path resizes on; the history scene's id is what keeps
        // opened history out of every screenshot. A drift in either fails silently.
        for spelled in ["\"main\"", "\"history\"", "\"Proctor\"", "\"History\"",
                        "\"walkthroughCompleted\""] {
            #expect(!app.contains(spelled),
                    "ProctorUIApp.swift spells \(spelled) itself again")
        }
        #expect(StatusSurface.sceneID == "main")
        #expect(HistorySurface.sceneID == "history")
        #expect(StatusSurface.Copy.windowTitle == "Proctor")
        #expect(HistorySurface.sceneTitle == "History")
    }

    // MARK: - Harness

    static let viewFiles = ["MainWindow.swift", "ProctorUIApp.swift", "Walkthrough.swift",
                            "HistoryWindow.swift", "HistoryModel.swift", "AgentModel.swift",
                            "MenuBarCharacter.swift", "Motion.swift"]

    private static func mainWindow() throws -> String {
        try source("Sources/ProctorUI/MainWindow.swift")
    }

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func source(_ path: String) throws -> String {
        try String(contentsOf: repositoryRoot.appendingPathComponent(path), encoding: .utf8)
    }

    /// The same source with whole-line comments dropped, so a comment explaining
    /// why a construct moved does not fail a scan for that construct.
    private static func codeOnly(_ source: String) -> String {
        source.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
    }

    /// The text between two anchors, failing loudly when either anchor has moved.
    /// A slice that silently came back empty would make every assertion below it
    /// pass on nothing.
    private static func slice(of source: String, from: String, to: String) throws -> String {
        let start = try #require(source.range(of: from),
                                 "anchor \(from) is gone; this test measured nothing")
        let rest = source[start.upperBound...]
        let end = try #require(rest.range(of: to),
                               "anchor \(to) is gone; this test measured nothing")
        let slice = String(rest[..<end.lowerBound])
        #expect(!slice.isEmpty)
        return slice
    }
}
