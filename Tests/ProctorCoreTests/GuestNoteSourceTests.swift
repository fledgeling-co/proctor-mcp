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

    /// Every readable text file under `Sources/`, as (path, contents).
    ///
    /// **Not just `.swift`.** The first draft filtered on the extension, which
    /// meant a copy of the note living in a resource, a plist or a generated
    /// fragment shipped uncounted. Anything that will not decode as UTF-8 is
    /// skipped as binary rather than silently counted as empty.
    ///
    /// Returned as a list so callers count with `count` over a population rather
    /// than eyeballing printed output; a printed list is not a denominator.
    static func sourceFiles() throws -> [(path: String, text: String)] {
        let root = repositoryRoot.appendingPathComponent("Sources")
        guard let walker = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        var out: [(String, String)] = []
        for case let url as URL in walker {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?
                    .isRegularFile == true else { continue }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            out.append((url.path, text))
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

        // The issue ids, and the claim's own distinctive wording. A paraphrase
        // that drops both ids still ships undetected, and that limit is recorded
        // in the spec rather than papered over; catching a copy that keeps the
        // phrasing is the reachable half. Raised by the PRO-0094 critic.
        for id in ["FB21748086", "#870", "render no application windows"] {
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

        // **Scoped to the recorded measurement, not to the whole document.**
        // Every claim the note makes also appears elsewhere in that spec
        // (`26.6.2` three times, `2026-08-21` six, `Calculator` four), so a
        // whole-file search stays green after the measurement paragraph is
        // deleted, which is precisely the drift this case exists to catch.
        let anchor = GuestNotes.TahoeRendering.measurementAnchor
        let anchorAt = try #require(spec.range(of: anchor),
                                    "the recorded measurement opens with \(anchor.debugDescription) and is not in the cited spec, so the note cites nothing")
        let headings = spec.ranges(of: "\n## ")
        let sectionStart = headings.last { $0.lowerBound < anchorAt.lowerBound }?.lowerBound
                        ?? spec.startIndex
        let sectionEnd = headings.first { $0.lowerBound > anchorAt.lowerBound }?.lowerBound
                      ?? spec.endIndex
        let measurement = String(spec[sectionStart..<sectionEnd])
        #expect(measurement.count < spec.count,
                "control: the section must be a proper part of the document, not all of it")

        var claims = [GuestNotes.TahoeRendering.guestOS,
                      GuestNotes.TahoeRendering.measuredOn]
        claims.append(contentsOf: GuestNotes.TahoeRendering.applications)
        // The population is production data, not something assembled here: the
        // first draft asserted `claims.count == 5` right after appending to it,
        // which measures the test. This measures the constant.
        #expect(GuestNotes.TahoeRendering.applications.count == 3,
                "the note names three applications that rendered")

        for claim in claims {
            #expect(measurement.contains(claim),
                    "the note states \(claim.debugDescription), which does not appear in the recorded measurement inside \(GuestNotes.TahoeRendering.citation). The note and the record it cites have drifted apart.")
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
        /// Every string anywhere in a JSONValue, so a stale provider pair hiding
        /// in a nested property description is counted. Checking only the tool's
        /// top-level `description` was the first draft; the critic pointed out
        /// that the per-argument descriptions are prose a caller reads too.
        func strings(in value: JSONValue) -> [String] {
            switch value {
            case .string(let s):  return [s]
            case .array(let a):   return a.flatMap(strings(in:))
            case .object(let o):  return o.values.flatMap(strings(in:))
            default:              return []
            }
        }
        var prose = strings(in: ToolCatalogue.guest.inputSchema)
        prose.append(ToolCatalogue.guest.description)
        prose.append(ToolCatalogue.guest.title)
        #expect(prose.count > 10,
                "control: the schema walk found \(prose.count) strings, too few to be the whole tool surface")

        for stale in ["lume or prlctl", "lume, prlctl, or both", "lume and prlctl"] {
            let offenders = prose.filter { $0.contains(stale) }
            #expect(offenders.isEmpty,
                    "\(offenders.count) string(s) on the guest tool still say \(stale.debugDescription); tart is supported and a reader going by this concludes otherwise")
        }
        #expect(prose.contains { $0.contains("tart") }, "the tool surface must name tart")
    }
}
