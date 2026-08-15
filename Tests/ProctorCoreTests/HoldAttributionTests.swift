import Testing
import Foundation
@testable import ProctorCore

// PRO-0037 A1 — a hold names its session, its app and its display, all derived.
//
// The display arithmetic is `RunHUDPlacement`'s, reused rather than copied, so
// what is asserted here is that a hold reaches for it correctly and names the
// answer in words a person can act on.

@Suite("Hold attribution")
struct HoldAttributionTests {

    private let laptop = Rect(x: 0, y: 0, w: 1728, h: 1117)
    private let external = Rect(x: 1728, y: 0, w: 2560, h: 1440)

    @Test("the display is the one holding most of the window")
    func theDisplayIsTheOneHoldingMostOfTheWindow() {
        // Straddling, but mostly on the external one.
        let window = Rect(x: 1600, y: 200, w: 800, h: 600)
        let display = HoldAttribution.display(for: window, in: [laptop, external], mainIndex: 0)
        #expect(display?.index == 1)
        #expect(display?.isMain == false)
        #expect(display?.name == "display 2")
    }

    @Test("a window off every screen takes the nearest rather than none")
    func aWindowOffEveryScreenTakesTheNearest() {
        // A window left behind on a display that has been unplugged. An absent
        // attribution would say nothing where a nearly-right one says where to
        // look.
        let orphan = Rect(x: 6000, y: 200, w: 400, h: 300)
        let display = HoldAttribution.display(for: orphan, in: [laptop, external], mainIndex: 0)
        #expect(display?.index == 1)
    }

    @Test("the main display is named as such rather than numbered")
    func theMainDisplayIsNamedAsSuch() {
        let window = Rect(x: 100, y: 100, w: 400, h: 300)
        let display = HoldAttribution.display(for: window, in: [laptop, external], mainIndex: 0)
        #expect(display?.isMain == true)
        #expect(display?.name == "the main display")
    }

    @Test("no screens means no display rather than a guess")
    func noScreensMeansNoDisplay() {
        #expect(HoldAttribution.display(for: laptop, in: [], mainIndex: 0) == nil)
    }

    @Test("no window at all still names a display, because the run is somewhere")
    func noWindowStillNamesADisplay() {
        // `screenIndex` answers 0 for a nil target, which is the primary. A run
        // whose window frame was not resolved is still running on a screen.
        let display = HoldAttribution.display(for: nil, in: [laptop, external], mainIndex: 0)
        #expect(display?.index == 0)
        #expect(display?.isMain == true)
    }

    @Test("the line degrades by dropping clauses rather than printing an absence")
    func theLineDegradesRatherThanPrintingNil() {
        let bare = HoldAttribution(reason: .frontmostChanged, session: "proctor-mcp a3f1")
        #expect(bare.line == "Paused — you moved to another app — proctor-mcp a3f1")
        #expect(!bare.line.contains("nil"))

        let full = HoldAttribution(
            reason: .secureInput, session: "diolog-web 7c02", app: "Acme Console",
            display: HoldDisplay(index: 1, isMain: false, name: "display 2"))
        #expect(full.line
            == "Paused — secure keyboard entry is on — diolog-web 7c02 · Acme Console on display 2")
    }

    @Test("an empty app name is dropped rather than left as a dangling separator")
    func anEmptyAppNameIsDropped() {
        let hold = HoldAttribution(reason: .userInput, session: "armada b915", app: "")
        #expect(!hold.line.contains("·"))
    }

    @Test("the session is whatever the derived identity says, and nothing else")
    func theSessionIsTheDerivedLabel() {
        // The label is `RunSessionIdentity`'s, which is built from the peer
        // process. Nothing in this type accepts a name from a client, and this
        // pins that the hold prints the derived pair rather than a project name
        // on its own.
        let identity = RunSessionIdentity(project: "proctor-mcp", connection: "a3f1",
                                          key: "4212:1755200000")
        let hold = HoldAttribution(reason: .frontmostChanged, session: identity.label)
        #expect(hold.session == "proctor-mcp a3f1")
        #expect(!hold.session.contains("4212"))
    }

    @Test("every reason can be attributed, so no hold is unnameable")
    func everyReasonCanBeAttributed() {
        for reason in YieldReason.allCases {
            let hold = HoldAttribution(reason: reason, session: "armada b915")
            #expect(hold.line.hasPrefix(reason.line))
            #expect(hold.line.contains("armada b915"))
        }
    }

    @Test("it round-trips, because the health report and the wire both carry it")
    func itRoundTrips() throws {
        let hold = HoldAttribution(
            reason: .secureInput, session: "proctor-mcp a3f1", app: "Mail",
            display: HoldDisplay(index: 0, isMain: true, name: "the main display"))
        let data = try JSONEncoder().encode(hold)
        #expect(try JSONDecoder().decode(HoldAttribution.self, from: data) == hold)
    }
}
