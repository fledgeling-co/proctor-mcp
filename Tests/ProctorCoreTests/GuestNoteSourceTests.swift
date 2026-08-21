import Testing
import Foundation
@testable import ProctorCore

// PRO-0094. The Tahoe note has one source, and that source is bound to the
// measurement it cites.
//
// Two different failures live here and they need different instruments.
//
// **A second copy** is a source-tree fact, not a value a build can hold: three
// hand-written copies of one sentence compile just as happily as one constant
// does, and every unit test over the constant passes while the other two copies
// say the old thing. So these cases read `Sources/` off disk and count.
//
// **A drifted claim** is a fact about two files. The note states a version, a
// date and three application names; the spec section that recorded them is at
// `docs/specs/spec-PRO-0076.md`. Nothing but a test can keep an edit to one from
// leaving the other stale, and the note carries its own citation precisely so
// this check has something to check.
@Suite("PRO-0094 · one Tahoe note, bound to its measurement")
struct GuestNoteSourceTests {

    /// The repo root, found from this file rather than from a working directory
    /// `swift test` does not promise. The pattern `ToolchainShellFragmentTests`
    /// already uses.
    static var repositoryRoot: URL {
        URL(fileURLWithPath: #filePath)   // Tests/ProctorCoreTests/GuestNoteSourceTests.swift
            .deletingLastPathComponent()  // Tests/ProctorCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
    }

    /// Every `.swift` file under `Sources/`, as (path, contents).
    ///
    /// Returned as a list so callers count with `count` over a population rather
    /// than eyeballing printed output — a printed list is not a denominator.
    static func sourceFiles() throws -> [(path: String, text: String)] {
        let root = repositoryRoot.appendingPathComponent("Sources")
        guard let walker = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: nil) else { return [] }
        var out: [(String, String)] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            out.append((url.path, try String(contentsOf: url, encoding: .utf8)))
        }
        return out
    }

    /// How many source files contain `needle`, and which.
    static func filesContaining(_ needle: String,
                                in files: [(path: String, text: String)]) -> [String] {
        files.filter { $0.text.contains(needle) }.map(\.path)
    }

    /// Total occurrences of `needle` across every source file.
    static func occurrences(of needle: String,
                            in files: [(path: String, text: String)]) -> Int {
        files.reduce(0) { $0 + $1.text.components(separatedBy: needle).count - 1 }
    }

    // MARK: - CASE-0180

    @Test("each upstream issue id appears exactly once in Sources")
    func theIssueIdsHaveOneHomeEach() throws {
        let files = try Self.sourceFiles()
        // The instrument first: a walk that enumerated nothing would report zero
        // for every needle below, and zero is the answer two of these cases want.
        #expect(files.count > 100,
                "the source walk found \(files.count) swift files, which is too few to be the whole of Sources/ — a zero from this instrument would mean nothing")

        for id in ["FB21748086", "#870"] {
            let hits = Self.occurrences(of: id, in: files)
            let where_ = Self.filesContaining(id, in: files)
            let names = where_.map { ($0 as NSString).lastPathComponent }.sorted()
            #expect(hits == 1,
                    "\(id) occurs \(hits) times across \(where_.count) file(s): \(names). A second occurrence is a second source, which is the defect this closes.")
        }
    }

    // MARK: - CASE-0183

    @Test("nothing in Sources still tells a reader to verify against Sequoia")
    func theUnactionableAdviceIsGone() throws {
        let files = try Self.sourceFiles()
        // The control, so this zero is a measurement rather than a broken walk:
        // the same population, the same method, a needle that IS present.
        #expect(Self.occurrences(of: "FB21748086", in: files) > 0,
                "control: the walk must be able to find a string that is present")

        let stale = Self.filesContaining("verify against Sequoia", in: files)
        #expect(stale.isEmpty,
                "still advising a Sequoia check in \(stale.count) file(s): \(stale). proctor_guest action status is the actionable form of that instruction.")
    }

    // MARK: - CASE-0181a and CASE-0181b

    @Test("the doctor's guest lane carries the constant, not a copy of it")
    func theGuestLaneNoteIsTheConstant() {
        let lanes = Toolchain.lanes(tools: [], grants: [], secondLane: .off,
                                    cuaLaneSelected: false)
        let guest = lanes.first { $0.lane == "guest" }
        #expect(guest != nil, "there must be a guest lane to carry the note")
        #expect(guest?.note?.contains(GuestNotes.tahoeRendering) == true,
                "the guest lane note must interpolate GuestNotes.tahoeRendering")
    }

    @Test("the proctor_guest description carries the constant, not a copy of it")
    func theToolDescriptionIsTheConstant() {
        #expect(ToolCatalogue.guest.description.contains(GuestNotes.tahoeRendering),
                "the tool description must interpolate GuestNotes.tahoeRendering")
    }

    // MARK: - CASE-0182

    @Test("every measurement the note states is in the spec section it cites")
    func theNoteCitesSomethingThatSaysIt() throws {
        let cited = Self.repositoryRoot
            .appendingPathComponent(GuestNotes.TahoeRendering.citation)
        #expect(FileManager.default.fileExists(atPath: cited.path),
                "the note cites \(GuestNotes.TahoeRendering.citation), which must exist")
        let spec = try String(contentsOf: cited, encoding: .utf8)

        // The control again: a file read that silently produced an empty string
        // would fail every claim below for the wrong reason.
        #expect(spec.contains("Tahoe"),
                "control: the cited spec must be the document that discusses Tahoe")

        var claims = [GuestNotes.TahoeRendering.guestOS,
                      GuestNotes.TahoeRendering.measuredOn]
        claims.append(contentsOf: GuestNotes.TahoeRendering.applications)
        #expect(claims.count == 5, "five claims: a version, a date and three applications")

        for claim in claims {
            #expect(spec.contains(claim),
                    "the note states \(claim.debugDescription), which does not appear in \(GuestNotes.TahoeRendering.citation). The note and the record it cites have drifted apart.")
        }

        // And the sentence a reader sees actually renders those fields, rather
        // than being prose that happens to sit beside them.
        let sentence = GuestNotes.tahoeRendering
        for claim in claims {
            #expect(sentence.contains(claim),
                    "the rendered sentence omits \(claim.debugDescription)")
        }
        #expect(sentence.contains(GuestNotes.TahoeRendering.citation),
                "the sentence must carry its own citation")
        #expect(sentence.contains("still open"),
                "the sentence must say the upstream reports remain open")
    }

    // MARK: - CASE-0189 (the ProctorCore half)

    @Test("the guest tool's provider enum admits all three providers")
    func theSchemaNamesTart() {
        let providers = ToolCatalogue.guest.inputSchema
            .objectValue?["properties"]?.objectValue?["provider"]?
            .objectValue?["enum"]?.arrayValue?.compactMap(\.stringValue)
        #expect(providers != nil, "proctor_guest must declare a provider enum")
        #expect(Set(providers ?? []) == ["lume", "prlctl", "tart"],
                "the schema enumerates \(providers ?? []); a caller naming a provider this omits is refused by validation before any of this repo's code sees it")
    }

    @Test("no prose on the guest tool describes a two-provider world")
    func theDescriptionNamesTart() {
        let text = ToolCatalogue.guest.description
        for stale in ["lume or prlctl", "lume, prlctl, or both", "lume and prlctl"] {
            #expect(!text.contains(stale),
                    "the description still says \(stale.debugDescription); tart is supported")
        }
        #expect(text.contains("tart"), "the description must name tart")
    }
}
