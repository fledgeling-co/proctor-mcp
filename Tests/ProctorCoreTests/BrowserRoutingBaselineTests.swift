import Testing
import Foundation
@testable import ProctorCore

// PRO-0035 clause 10 — routing did not move.
//
// This item changes how a browser is identified and what a handoff reports. It
// promises not to change which windows reach which lane. The cheap way to say
// that is to re-read the diff; the decisive way is to have the code write its
// answers down before the change and compare afterwards.
//
// `Fixtures/browser-routing-baseline.json` was generated from the code as it
// stood at the start of PRO-0035 and is a **regression fence, not a statement of
// correctness**: it freezes whatever PRO-0020, PRO-0023 and PRO-0024 decided,
// bugs included. The two keys this item adds are stripped before comparison, so
// anything else that moves fails here.
//
// To regenerate deliberately, delete the fixture and run the suite twice: the
// first run writes it and fails, the second passes.

@Suite("Browser routing baseline")
struct BrowserRoutingBaselineTests {

    /// Every scheme class the ladder distinguishes, plus a silent area.
    static let urls: [String?] = [
        "https://example.com/dashboard",
        "http://192.168.1.4:3000/report.pdf?t=1",
        "chrome://newtab",
        "chrome://settings",
        "chrome-extension://abcdefghijklmnop/options.html",
        "devtools://devtools/bundled/inspector.html",
        "file:///Users/x/page.html",
        "data:text/html,<p>hi</p>",
        "about:blank",
        nil
    ]

    static let browserIds = ["com.google.Chrome", "com.apple.Safari", "org.mozilla.firefox"]
    static let laneStates: [SecondLaneState] = [.off, .enabled, .unavailable]

    /// Encode, drop the fields PRO-0035 is allowed to move, re-encode with sorted
    /// keys. Both the baseline and the comparison go through this same pipeline, so
    /// the two are never compared across two different serialisers.
    ///
    /// `surface` and `flags` are the two keys this item adds. `continuity` is the
    /// one string it changes: the Obscura lane's sentence gains a clause saying
    /// that nothing Obscura does reaches Proctor's audit trail, which was true and
    /// unsaid, and which the `outsideTheAuditTrail` flag would otherwise assert
    /// with no prose behind it. **Every other field is compared, prose included** —
    /// `boundary`, `why`, `evidence`, `url`, `urlUnavailable`, `notes`, `commands`,
    /// `caveats`, `toolUnavailable` and `use`.
    static let movableKeys = ["surface", "flags", "continuity"]

    static func canonical(_ handoff: BrowserHandoff) throws -> String {
        try canonicalise(try JSONEncoder().encode(handoff))
    }

    /// Both sides of the comparison go through this, so a fixture written by any
    /// other serialiser — one that does not escape a forward slash the way
    /// `JSONSerialization` does, for instance — is still compared on content
    /// rather than on incidental escaping.
    static func canonicalise(_ data: Data) throws -> String {
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BaselineError.notAnObject
        }
        for key in movableKeys { object.removeValue(forKey: key) }
        let out = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return String(decoding: out, as: UTF8.self)
    }

    enum BaselineError: Error { case notAnObject, missingFixture(String) }

    /// The whole sweep, keyed so a failure names the case.
    static func sweep() throws -> [String: String] {
        var out: [String: String] = [:]
        for id in browserIds {
            guard let browser = BrowserCatalogue.identify(bundleId: id) else { continue }
            for url in urls {
                for obscura in [true, false] {
                    for lane in laneStates {
                        for detail in [BrowserTarget.Detail.full, .brief] {
                            let probe = WebContentProbe(areas: [
                                WebArea(url: url, frame: Rect(x: 0, y: 0, w: 1200, h: 800))
                            ])
                            let lanes = BrowserLanes(obscuraAvailable: obscura, secondLane: lane)
                            let key = "\(id)|\(url ?? "<nil>")|obscura=\(obscura)|lane=\(lane.rawValue)|\(detail == .full ? "full" : "brief")"
                            out[key] = try canonical(
                                BrowserTarget.handoff(for: browser, probe: probe,
                                                      detail: detail, lanes: lanes))
                            // The app-level case: a browser was named, no window was.
                            let appKey = "\(id)|<no probe>|obscura=\(obscura)|lane=\(lane.rawValue)|\(detail == .full ? "full" : "brief")"
                            out[appKey] = try canonical(
                                BrowserTarget.handoff(for: browser, probe: nil,
                                                      detail: detail, lanes: lanes))
                        }
                    }
                }
            }
        }
        return out
    }

    static var fixtureURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/browser-routing-baseline.json")
    }

    @Test("every lane decision is byte-identical to the answers recorded before PRO-0035")
    func routingIsUnchanged() throws {
        let current = try Self.sweep()
        let url = Self.fixtureURL

        guard let data = try? Data(contentsOf: url) else {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoded = try JSONSerialization.data(
                withJSONObject: current, options: [.sortedKeys, .prettyPrinted])
            try encoded.write(to: url)
            Issue.record("baseline written to \(url.path); re-run to compare against it")
            return
        }

        let baseline = try JSONSerialization.jsonObject(with: data) as? [String: String] ?? [:]
        #expect(!baseline.isEmpty, "the baseline fixture is empty")
        #expect(Set(current.keys) == Set(baseline.keys),
                "the sweep changed shape: \(Set(current.keys).symmetricDifference(Set(baseline.keys)).sorted().prefix(5))")
        for (key, expected) in baseline.sorted(by: { $0.key < $1.key }) {
            let normalised = try Self.canonicalise(Data(expected.utf8))
            #expect(current[key] == normalised, "routing moved for \(key)")
        }
    }
}
