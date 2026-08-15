import Foundation
import Testing
@testable import ProctorCore

// PRO-0036 — what each check in the status window can actually establish.
//
// Everything the feature decides is here, because there is no test target for
// `ProctorUI` and no window server under `swift test`. A rule written in a view
// body is a rule this repo cannot prove, so the rules live in `StatusChecks` and
// the window renders them. What a test here CANNOT reach: whether the window
// draws at all, where the restart offer lands, whether a disclosure opens, and
// the end-to-end permission trap. Those are recorded in the spec as needing a
// person, and a green run here is not evidence for any of them.

@Suite("Status checks")
struct StatusChecksTests {

    private static func grant(_ name: String, state: GrantState = .denied,
                              required: Bool = true) -> DoctorReport.Grant {
        DoctorReport.Grant(name: name, state: state, required: required, howToFix: "…")
    }

    // MARK: - Clause 1: every check knows what moves it

    @Test("every name the agent can emit resolves to exactly one kind")
    func everyKnownNameClassifies() {
        for name in [StatusChecks.accessibility, StatusChecks.screenRecording,
                     StatusChecks.automation, StatusChecks.shortcutsCLI] {
            #expect(StatusChecks.kind(ofCheckNamed: name) != nil,
                    "\(name) has no kind, so nothing can say what would move it")
        }
        #expect(StatusChecks.known.count == 4)
    }

    @Test("every kind is reachable from a real name")
    func everyKindIsUsed() {
        let used = Set(StatusChecks.known.values)
        for kind in StatusCheckKind.allCases {
            #expect(used.contains(kind), "\(kind) is a case nothing produces")
        }
    }

    @Test("an unrecognised name falls to the tools side, never to permissions")
    func unknownFallsToTools() {
        // The direction is load-bearing and was reversed by the plan's
        // out-of-family review. The permission names are a closed set macOS
        // fixes; tools are the half that grows, so defaulting an unknown name
        // into the permissions list would re-create the very defect clause 2
        // removes.
        #expect(StatusChecks.kind(ofCheckNamed: "Full Disk Access") == nil)
        #expect(StatusChecks.resolvedKind(ofCheckNamed: "Full Disk Access") == .tool)
        let odd = Self.grant("Something New", required: false)
        #expect(StatusChecks.permissions(in: [odd]).isEmpty)
        #expect(StatusChecks.misfiledTools(in: [odd]).count == 1)
        #expect(StatusChecks.mobility(of: odd) == nil)
    }

    // MARK: - Clause 2: a tool never appears among the permissions

    @Test("the Shortcuts CLI leaves the permissions list and joins the tools")
    func shortcutsIsATool() {
        let grants = [Self.grant(StatusChecks.accessibility),
                      Self.grant(StatusChecks.screenRecording),
                      Self.grant(StatusChecks.automation, required: false),
                      Self.grant(StatusChecks.shortcutsCLI, required: false)]

        let permissions = StatusChecks.permissions(in: grants).map(\.name)
        #expect(permissions == [StatusChecks.accessibility, StatusChecks.screenRecording,
                                StatusChecks.automation])
        #expect(!permissions.contains(StatusChecks.shortcutsCLI))
        #expect(StatusChecks.misfiledTools(in: grants).map(\.name) == [StatusChecks.shortcutsCLI])

        let rows = StatusChecks.toolRows(tools: [], shortcutsCLIAvailable: false)
        #expect(rows.contains { $0.tool == StatusChecks.shortcutsCLI })
    }

    // MARK: - Clause 3: "Optional — asked for per app" is Automation's sentence

    @Test("only Automation is ever described as asked for per app")
    func perAppTextIsAutomationsAlone() {
        let perApp = "Optional — asked for per app"
        for name in StatusChecks.known.keys {
            for state in GrantState.allCases {
                for required in [true, false] {
                    let text = StatusChecks.statusText(
                        for: Self.grant(name, state: state, required: required))
                    if text == perApp {
                        #expect(name == StatusChecks.automation,
                                "\(name) must not be described as asked for per app")
                    }
                }
            }
        }
        // And it is still produced where it is correct.
        #expect(StatusChecks.statusText(
            for: Self.grant(StatusChecks.automation, required: false)) == perApp)
    }

    @Test("the other three status sentences are unchanged")
    func statusTextIsUnchanged() {
        #expect(StatusChecks.statusText(
            for: Self.grant(StatusChecks.accessibility, state: .granted)) == "Granted")
        #expect(StatusChecks.statusText(
            for: Self.grant(StatusChecks.screenRecording, state: .unconfirmed))
                == "Not established — macOS did not answer")
        #expect(StatusChecks.statusText(
            for: Self.grant(StatusChecks.accessibility)) == "Required — not granted yet")
    }

    // MARK: - Clause 4: the sentence belongs to the state, not the permission

    @Test("a live-read permission says Proctor will notice on its own")
    func liveReadMobility() throws {
        let text = try #require(StatusChecks.mobility(of: Self.grant(StatusChecks.accessibility)))
        #expect(text.contains("on its own"))
        #expect(!text.contains("restart"))
    }

    @Test("a denied settled-at-launch permission names the restart and Settings")
    func settledAtLaunchDeniedMobility() throws {
        let text = try #require(
            StatusChecks.mobility(of: Self.grant(StatusChecks.screenRecording)))
        #expect(text.contains("restarts"))
        #expect(text.contains("Settings"))
    }

    @Test("an unconfirmed permission claims no restart and names no settings pane")
    func unconfirmedMobilityDemandsNothing() throws {
        // The first draft flattened Screen Recording into one sentence, which the
        // out-of-family review caught: an unconfirmed probe is NOT cached and is
        // retried on a backoff, so telling somebody to restart would be false.
        let text = try #require(
            StatusChecks.mobility(of: Self.grant(StatusChecks.screenRecording,
                                                 state: .unconfirmed)))
        #expect(!text.lowercased().contains("restart"))
        #expect(!text.contains("Settings"))
        #expect(text.contains("asks again"))
    }

    @Test("a granted permission says nothing at all")
    func grantedIsSilent() {
        for name in StatusChecks.known.keys {
            #expect(StatusChecks.mobility(of: Self.grant(name, state: .granted)) == nil)
        }
    }

    @Test("Automation carries no mobility sentence")
    func automationIsSilent() {
        #expect(StatusChecks.mobility(
            of: Self.grant(StatusChecks.automation, required: false)) == nil)
    }

    // MARK: - Clause 5: an unconfirmed grant is never dressed as a denial

    @Test("nothing said about an unconfirmed grant claims a refusal")
    func unconfirmedIsNotADenial() {
        let grant = Self.grant(StatusChecks.screenRecording, state: .unconfirmed)
        let said = [StatusChecks.statusText(for: grant), StatusChecks.mobility(of: grant) ?? ""]
        for text in said {
            for word in ["denied", "refused", "not granted"] {
                #expect(!text.lowercased().contains(word),
                        "an unconfirmed grant must not read as a denial: \(text)")
            }
        }
    }

    // MARK: - Clause 7 and 8: tool rows render the report's own verdicts

    private static func presence(_ tool: String, available: Bool = true,
                                 usability: ToolUsability? = .usable,
                                 evidence: ToolEvidence? = .presence,
                                 version: String? = nil,
                                 detail: String? = "Proctor's own sentence.",
                                 path: String? = "/opt/homebrew/bin/x") -> ToolPresence {
        ToolPresence(tool: tool, available: available, path: available ? path : nil,
                     searched: ["/opt/homebrew/bin/\(tool)", "/usr/local/bin/\(tool)"],
                     usability: usability, evidence: evidence, version: version, detail: detail)
    }

    @Test("one row per reported tool, in the report's order, verdicts preserved")
    func rowsMirrorTheReport() {
        let tools = [Self.presence("obscura", evidence: .installPath, version: "0.2.0"),
                     Self.presence("simctl"),
                     Self.presence("cua-driver", usability: .unconfirmed, evidence: .signature),
                     Self.presence("maestro", available: false, usability: .unusable,
                                   evidence: .absent, detail: "Not found anywhere.")]
        let rows = StatusChecks.toolRows(tools: tools, shortcutsCLIAvailable: true)

        #expect(rows.map(\.tool) == ["obscura", "simctl", "cua-driver", "maestro",
                                     StatusChecks.shortcutsCLI])
        #expect(rows[0].version == "0.2.0")
        #expect(rows[0].tone == .good)
        #expect(rows[2].tone == .unknown)
        #expect(rows[3].tone == .bad)
        // The report's sentence travels unedited: the window writes no second
        // verdict about a tool the report already decided.
        for (row, tool) in zip(rows, tools) {
            #expect(row.detail == tool.detail)
            #expect(row.searched == tool.searched)
        }
    }

    @Test("the short line follows from usability and evidence alone")
    func statusIgnoresPathAndVersion() {
        let a = Self.presence("obscura", version: "1.0.0", path: "/usr/local/bin/obscura")
        let b = Self.presence("obscura", version: nil, path: "/opt/homebrew/bin/obscura")
        #expect(StatusChecks.status(for: a) == StatusChecks.status(for: b))

        let signed = Self.presence("cua-driver", usability: .unconfirmed, evidence: .signature)
        let bare = Self.presence("cua-driver", usability: .unconfirmed, evidence: .presence)
        #expect(StatusChecks.status(for: signed) != StatusChecks.status(for: bare))
    }

    @Test("a report from an older agent still produces a row")
    func rowsSurviveAReportWithoutTheUsabilityAxis() {
        let old = ToolPresence(tool: "obscura", available: true, path: "/x/obscura",
                               searched: ["/x/obscura"])
        let row = StatusChecks.row(for: old)
        #expect(row.status == "Found")
        #expect(row.tone == .unknown)
    }

    // MARK: - Clause 9: the second lane's gate holds at this surface too

    @Test("with the lane off, browser-use appears in no field of any row")
    func secondLaneStaysBehindItsSwitch() {
        // The agent omits it from the report unless an operator named the lane,
        // so the window has nothing to draw. Asserted over every field rather
        // than over the row's name, because the invariant is about the string.
        let rows = StatusChecks.toolRows(
            tools: [Self.presence("obscura"), Self.presence("simctl")],
            shortcutsCLIAvailable: true)
        for row in rows {
            let fields = [row.tool, row.status, row.version ?? "", row.detail ?? "",
                          row.path ?? ""] + row.searched
            for field in fields {
                #expect(!field.contains(BrowserUseTool.binary),
                        "the second lane must not appear with the lane off: \(field)")
            }
        }
    }

    // MARK: - Clause 10: freshness is claimed only where it is true

    @Test("the footer says the report was asked for, not that everything was checked")
    func freshnessNamesTheAsking() {
        let line = StatusChecks.reportFreshness(at: "14:32:01")
        #expect(line.contains("Asked"))
        #expect(!line.contains("Checked"))
        #expect(line.contains("14:32:01"))
    }

    // MARK: - The empty and absent report

    @Test("an empty tools array still yields the Shortcuts CLI row")
    func emptyToolsIsNeverAHeadingOverNothing() {
        let rows = StatusChecks.toolRows(tools: [], shortcutsCLIAvailable: true)
        #expect(rows.count == 1)
        #expect(rows[0].tool == StatusChecks.shortcutsCLI)
        #expect(rows[0].tone == .good)

        let missing = StatusChecks.toolRows(tools: [], shortcutsCLIAvailable: false)
        #expect(missing[0].tone == .bad)
        #expect(missing[0].status == "Not on this Mac")
    }
}

// MARK: - The two tripwires

/// Source scans, in the idiom `ToolchainDoctorTests.doctorPathSpawnsNothing`
/// already uses here. A tripwire rather than a proof — a determined indirection
/// defeats either — but each catches the thing that actually happens.
@Suite("Status window tripwires")
struct StatusWindowSourceTests {

    private static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private static func source(_ path: String) throws -> String {
        try String(contentsOf: repositoryRoot.appendingPathComponent(path), encoding: .utf8)
    }

    @Test("the agent's grant names and Core's map cannot drift apart")
    func grantNamesMatchTheMap() throws {
        // SET EQUALITY, not "each name classifies to something". A non-nil check
        // would pass a newly added tool that Core happened to map to a
        // permission, which is this feature's own defect wearing a green test.
        //
        // The runtime route cannot stand in for this: `shortcutsAvailable` reads
        // /usr/bin/shortcuts off the real filesystem, is not injected, and the
        // fourth grant is appended only when it is ABSENT — so on a Mac that has
        // it, that name never appears in a built report at all.
        let source = try Self.source("Sources/ProctorAgent/Session/SessionDoctor.swift")
        var emitted: Set<String> = []
        var index = source.startIndex
        while let found = source.range(of: ".init(name: \"", range: index..<source.endIndex) {
            guard let close = source.range(of: "\"", range: found.upperBound..<source.endIndex)
            else { break }
            emitted.insert(String(source[found.upperBound..<close.lowerBound]))
            index = close.upperBound
        }

        #expect(!emitted.isEmpty, "the scan found no grant names; the pattern has moved")
        #expect(emitted == Set(StatusChecks.known.keys),
                """
                the agent emits \(emitted.sorted()) and StatusChecks carries \
                \(StatusChecks.known.keys.sorted()). Classify the new name deliberately \
                rather than letting it fall to the default.
                """)
    }

    @Test("the footer's Re-check is gone and the other two are not")
    func theRightRecheckWasDeleted() throws {
        // Which one went, not how many are left. A bare count would pass a change
        // that deleted one of the two honest buttons and kept the footer's. The
        // spec's verdict table says what each of the three reads, whether that
        // read is cached, and whether pressing it can change the answer.
        let source = try Self.source("Sources/ProctorUI/MainWindow.swift")

        let footer = try #require(source.range(of: "private struct FooterSection"))
        let footerBody = String(source[footer.lowerBound...])
        #expect(!footerBody.contains("Button(\"Re-check\")"),
                """
                the footer's Re-check refreshed rows that refresh themselves, beside a clock \
                that already ticks. See the spec's per-button verdict table.
                """)
        #expect(footerBody.contains("Restart agent"))
        #expect(footerBody.contains("Open log"))

        let remaining = source.components(separatedBy: "Button(\"Re-check\")").count - 1
        #expect(remaining == 2,
                """
                two Re-check buttons are honest and stay: the one beside Start the agent, and \
                the one under Obscura's install commands. See the verdict table.
                """)

        // The window's second opinion about a tool the report already judged.
        #expect(!source.contains("obscuraSummary"),
                "the report decides a tool's verdict; the window renders it")
    }
}
