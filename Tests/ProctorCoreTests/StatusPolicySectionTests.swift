import Foundation
import Testing
@testable import ProctorCore

// PRO-0082, A3 and DEF-183. The policy posture has been on the wire since
// PRO-0050 and no surface read it.
//
// The card is judged here rather than in the window for the reason every other
// decision on this surface is: a rule written inside a SwiftUI `body` is one this
// repo cannot prove. `status_literals.py` is the gate on the drawing half; this
// file is the gate on the deciding half.

@Suite("Status surface — the policy card")
struct StatusPolicySectionTests {

    /// A posture with every field named at its call site, so a test below that
    /// changes one field says which one it changed.
    static func posture(mode: String = "allowList",
                        allow: Int = 3, block: Int = 0, sensitive: Int = 0,
                        approvalTokenLive: Bool = false,
                        fsJailDeclared: Bool = true, fsRoots: Int = 2,
                        writable: Bool = true, sealed: Bool = false, signed: Bool = false,
                        clean: Bool = true, keyConfirmed: Bool = false,
                        entries: Int = 12, dropped: Int? = nil) -> DoctorReport.PolicyPosture {
        DoctorReport.PolicyPosture(mode: mode, allowCount: allow, blockCount: block,
                                   sensitiveCount: sensitive,
                                   approvalTokenLive: approvalTokenLive,
                                   fsJailDeclared: fsJailDeclared, fsRootCount: fsRoots,
                                   auditWritable: writable, auditSealed: sealed,
                                   auditSigned: signed, auditClean: clean,
                                   auditKeyConfirmed: keyConfirmed, auditEntries: entries,
                                   auditDroppedThisRun: dropped, note: "")
    }

    // MARK: - The section exists and is placed

    @Test("the policy section is drawn in both usable states and in neither other one")
    func theSectionIsPlaced() throws {
        for state in [StatusSurface.State.ready, .partial] {
            let sections = StatusSurface.sections(for: state)
            #expect(sections.contains(.policy))
            // Placed between the switches and the activity, which is the order the
            // card was written for: what Proctor may do, then what it did.
            let policy = try #require(sections.firstIndex(of: .policy))
            let switches = try #require(sections.firstIndex(of: .switches))
            let activity = try #require(sections.firstIndex(of: .activity))
            #expect(switches < policy)
            #expect(policy < activity)
        }
        // The agent-down block replaces everything, posture included: a card drawn
        // from a report nobody could fetch is a statement about a gate that was
        // never read.
        #expect(!StatusSurface.sections(for: .down).contains(.policy))
        #expect(!StatusSurface.sections(for: .checking).contains(.policy))
    }

    // MARK: - An absent posture is not a posture

    @Test("no posture draws no rows, rather than rows saying nothing is enforced")
    func anAbsentPostureDrawsNothing() {
        #expect(StatusSurface.policyRows(from: nil).isEmpty)
        // And the two facts are kept apart in the copy as well: the sentence the
        // view says instead names what is unknown rather than dressing it as a
        // value.
        #expect(StatusSurface.Copy.policyAbsent.contains("did not report"))
        #expect(!StatusSurface.policyRows(from: Self.posture()).isEmpty,
                "a reported posture must draw rows, or the check above is vacuous")
    }

    // MARK: - Every row, every kind, an identifier each

    @Test("a reported posture draws one row per kind, in the kind's own order")
    func everyKindIsDrawnOnce() {
        let rows = StatusSurface.policyRows(from: Self.posture())
        #expect(rows.map(\.kind) == StatusSurface.PolicyRow.Kind.allCases)
        for row in rows {
            #expect(!row.label.isEmpty)
            #expect(!row.value.isEmpty, "\(row.kind) draws an empty value")
            #expect(row.detail != "", "\(row.kind) carries an empty detail rather than none")
            #expect(StatusSurface.ID.all.contains(StatusSurface.ID.policyRow(row.kind)),
                    "\(row.kind) has no identifier a test or a screen reader can name it by")
        }
    }

    @Test("every string a policy row says is a named constant, not a sentence built in the card")
    func everyRowStringIsEnumerable() {
        // The clause's own words: every string from `Copy`. A row whose value is
        // assembled from a literal here would render fine and be invisible to the
        // copy inventory, which is the defect PRO-0090 removed from the view.
        let labels = Set(StatusSurface.Copy.all.map(\.text))
        for row in StatusSurface.policyRows(from: Self.posture(sensitive: 2, dropped: 3)) {
            #expect(labels.contains(row.label),
                    "\(row.kind)'s label “\(row.label)” is not in StatusSurface.Copy.all")
        }
    }

    // MARK: - The gate's posture reads as a consequence

    @Test("each gate mode says what happens to the next call, and open says it plainly")
    func modeReadsAsAConsequence() {
        let allow = StatusSurface.policyRows(from: Self.posture(mode: "allowList", allow: 3))[0]
        #expect(allow.value.contains("3 apps"))
        #expect(allow.value.contains("refused"))
        #expect(allow.tone == .good)

        let block = StatusSurface.policyRows(from: Self.posture(mode: "blockOnly", allow: 0, block: 1))[0]
        #expect(block.value.contains("1 app "), "a single app is not “1 apps”")
        #expect(block.tone == .good)

        // The deliberate part. `open` is the most permissive posture Proctor has
        // AND its default, so it is the one an operator is most likely to be in
        // without having chosen it. Drawn plain, the window would agree with a
        // machine that has no gate at all.
        let open = StatusSurface.policyRows(from: Self.posture(mode: "open"))[0]
        #expect(open.value.contains("every app"))
        #expect(open.tone == .warn, "an open gate draws no louder than a closed one")
        #expect(open.tone != allow.tone, "the two postures are drawn identically")
    }

    @Test("a sensitive count appears as the mode's detail and vanishes at zero")
    func sensitiveIsADetail() {
        #expect(StatusSurface.policyRows(from: Self.posture(sensitive: 0))[0].detail == nil)
        let two = StatusSurface.policyRows(from: Self.posture(sensitive: 2))[0]
        #expect(two.detail?.contains("2 marked sensitive") == true)
        #expect(two.detail?.contains("approval") == true)
    }

    @Test("a live approval token is drawn as the louder of the two states")
    func approvalSaysWhatWouldHappenNext() throws {
        let live = try try Self.row(.approval, in: Self.posture(approvalTokenLive: true))
        let dead = try try Self.row(.approval, in: Self.posture(approvalTokenLive: false))
        #expect(live.value.contains("allowed"))
        #expect(dead.value.contains("refused"))
        #expect(live.tone == .warn && dead.tone == .plain,
                "a live token is a window in which a sensitive step would pass, and reads no louder than no token at all")
    }

    @Test("an undeclared filesystem jail is a warning and a declared one names its roots")
    func filesystemStatesItsConfinement() throws {
        let declared = try Self.row(.filesystem, in: Self.posture(fsJailDeclared: true, fsRoots: 1))
        #expect(declared.value.contains("1 root"))
        #expect(!declared.value.contains("1 roots"))
        #expect(declared.tone == .good)

        let none = try Self.row(.filesystem, in: Self.posture(fsJailDeclared: false, fsRoots: 0))
        #expect(none.value.contains("No jail"))
        #expect(none.tone == .warn)
    }

    // MARK: - The trail's honesty

    @Test("an unwritable trail says steps are running unrecorded, whatever else is true")
    func anUnwritableTrailOutranksTheRest() throws {
        // The worst state the block can report, and the one a clean verdict would
        // otherwise paper over: a trail that verifies because it has nothing in it.
        let row = try Self.row(.trail, in: Self.posture(writable: false, sealed: true, signed: true, clean: true))
        #expect(row.value.contains("unrecorded"))
        #expect(!row.value.contains("Verifies clean"))
        #expect(row.tone == .bad)
    }

    @Test("a trail that does not verify is drawn as loudly as one that cannot be written")
    func aBrokenTrailIsBad() throws {
        let broken = try Self.row(.trail, in: Self.posture(writable: true, clean: false))
        #expect(broken.value.contains("Does not verify"))
        #expect(broken.tone == .bad)
        #expect(try Self.row(.trail, in: Self.posture(writable: true, clean: true)).tone == .good,
                "the good case must be reachable, or the check above proves only that the row is always bad")
    }

    @Test("a signed trail says whether the key was confirmed, because the two are different claims")
    func signingNamesItsKey() throws {
        let confirmed = try Self.row(.trail, in: Self.posture(signed: true, keyConfirmed: true))
        let unconfirmed = try Self.row(.trail, in: Self.posture(signed: true, keyConfirmed: false))
        #expect(confirmed.value.contains("key confirmed"))
        #expect(unconfirmed.value.contains("key unconfirmed"))
        #expect(confirmed.value != unconfirmed.value)
        // And an unsigned trail claims neither.
        let plain = try Self.row(.trail, in: Self.posture(signed: false, keyConfirmed: false))
        #expect(!plain.value.contains("signed"))
        #expect(try Self.row(.trail, in: Self.posture(sealed: true)).value.contains("sealed"))
    }

    @Test("a dropped entry reds the count even beside a trail that verifies clean")
    func droppedEntriesAreNotFoldedIntoTheVerdict() throws {
        // The wire's own note: an action that was never recorded leaves no broken
        // link to find, so "clean" and "complete" are two claims. A card that let
        // the first imply the second would report a hole in the trail as health.
        let clean = Self.posture(clean: true, entries: 12, dropped: 3)
        let trail = try Self.row(.trail, in: clean)
        let entries = try Self.row(.entries, in: clean)
        #expect(trail.value.contains("Verifies clean"))
        #expect(trail.tone == .good)
        #expect(entries.value.contains("12 entries"))
        #expect(entries.value.contains("3 could not be written"))
        #expect(entries.tone == .bad, "a hole in the trail is drawn as health")

        let whole = try Self.row(.entries, in: Self.posture(entries: 1, dropped: nil))
        #expect(whole.value == "1 entry", "one entry is not “1 entries”")
        #expect(whole.tone == .plain)
        #expect(try Self.row(.entries, in: Self.posture(entries: 5, dropped: 0)).tone == .plain,
                "zero dropped is not a hole")
    }

    // MARK: - What the card must never carry

    @Test("no row can name an app, a path, a key or a token")
    func theCardCarriesNoRuleContents() {
        // The posture withholds them on purpose — a scope is a rule — and a card
        // is the surface most likely to reach for one. There is nothing on the
        // wire to leak, so this asserts the card did not invent one.
        let rows = StatusSurface.policyRows(from: Self.posture(mode: "open", sensitive: 4,
                                                              approvalTokenLive: true,
                                                              dropped: 2))
        let text = rows.map { "\($0.label) \($0.value) \($0.detail ?? "")" }.joined(separator: " ")
        for leak in ["com.", "/Users", "/private", "bundle", "token=", "-----BEGIN"] {
            #expect(!text.contains(leak), "a policy row says “\(leak)”")
        }
    }

    @Test("every row states its fact in words, so tone is never the only carrier")
    func toneIsNeverTheOnlyCarrier() throws {
        // The rule LanePill already carries. Two postures that differ in tone must
        // differ in words, or the card says something only to a person who can
        // tell the colours apart.
        let pairs: [(DoctorReport.PolicyPosture, DoctorReport.PolicyPosture, StatusSurface.PolicyRow.Kind)] = [
            (Self.posture(mode: "open"), Self.posture(mode: "allowList"), .mode),
            (Self.posture(approvalTokenLive: true), Self.posture(approvalTokenLive: false), .approval),
            (Self.posture(fsJailDeclared: false, fsRoots: 0), Self.posture(fsJailDeclared: true), .filesystem),
            (Self.posture(clean: false), Self.posture(clean: true), .trail),
            (Self.posture(dropped: 2), Self.posture(dropped: nil), .entries)
        ]
        for (loud, quiet, kind) in pairs {
            let a = try Self.row(kind, in: loud)
            let b = try Self.row(kind, in: quiet)
            #expect(a.tone != b.tone, "\(kind) draws both states in the same tone")
            #expect(a.value != b.value, "\(kind) says the same words in two different tones")
        }
    }

    /// The row of a kind, required rather than force-unwrapped: a card that
    /// stopped drawing a kind should fail here saying which one it dropped, not
    /// crash the whole suite on an unwrap.
    private static func row(_ kind: StatusSurface.PolicyRow.Kind,
                            in posture: DoctorReport.PolicyPosture) throws -> StatusSurface.PolicyRow {
        try #require(StatusSurface.policyRows(from: posture).first { $0.kind == kind },
                     "the card drew no \(kind) row")
    }
}
