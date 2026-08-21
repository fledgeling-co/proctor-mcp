import Testing
@testable import ProctorCore

// The one switch that can weaken "evidence must not change because somebody was
// watching", and the reason it exists: with the exclusion in place the panels
// cannot be photographed by any channel, so what they draw is uncheckable.
//
// What these tests CANNOT reach: whether the window server honours the sharing
// type, and whether a capture then contains the panel. There is no window server
// under `swift test`; that half is measured on glass and recorded in the campaign
// as CASE-0008 and CASE-0010.

@Suite("Overlay capture switch")
struct OverlayCaptureTests {

    @Test("the exclusion holds unless somebody asks for the opposite")
    func offByDefault() {
        #expect(OverlayCapture.excludedFromCapture(in: [:]))
        #expect(!OverlayCapture.lifted(in: [:]))
        for value in ["", " ", "0", "off", "false", "no"] {
            #expect(OverlayCapture.excludedFromCapture(in: [OverlayCapture.variable: value]),
                    "\(value) must not lift the exclusion")
        }
        // An unrecognised value reads ON, which is every capability's shape here
        // and is deliberately not special-cased: PROCTOR_TAKEOVER_INPUT answers
        // the same way, and one switch parsing its own dialect is the drift the
        // catalogue exists to stop. Setting it to anything but an off-value is
        // taken as asking for it.
        #expect(OverlayCapture.lifted(in: [OverlayCapture.variable: "nonsense"]))
        #expect(SwitchResolver.isOn("nonsense", for: SwitchCatalogue.takeoverInput))
    }

    @Test("an affirmative value lifts it, and only for as long as it is set")
    func liftedWhenAsked() {
        for value in ["1", "true", "on", "yes", "YES"] {
            #expect(OverlayCapture.lifted(in: [OverlayCapture.variable: value]), "\(value)")
            #expect(!OverlayCapture.excludedFromCapture(in: [OverlayCapture.variable: value]), "\(value)")
        }
    }

    @Test("it is a capability, so it is off by default and asks before it goes on")
    func shapedAsACapability() {
        let sw = SwitchCatalogue.overlayCapture
        #expect(sw.kind == .capability)
        #expect(!sw.defaultOn)
        #expect(sw.requiresConsent)
        #expect(sw.timing == .nextStart)
        #expect(sw.variable == OverlayCapture.variable)
        #expect(SwitchCatalogue.all.contains(sw))
    }

    @Test("the takeover spec carries the property, and defaults to excluded")
    func specCarriesIt() {
        let ordinary = Takeover.surface(reduceTransparency: false, reduceMotion: false, hudLevel: 25)
        #expect(ordinary.excludedFromCapture)

        let lifted = Takeover.surface(reduceTransparency: false, reduceMotion: false,
                                      hudLevel: 25, excludedFromCapture: false)
        #expect(!lifted.excludedFromCapture)
        // Everything else about the surface is unchanged by the switch: it moves
        // one property, not the tint, the plate, the fade or the level.
        #expect(lifted.alpha == ordinary.alpha)
        #expect(lifted.labelPlate == ordinary.labelPlate)
        #expect(lifted.fades == ordinary.fades)
        #expect(lifted.level == ordinary.level)
        #expect(lifted.ignoresMouseEvents == ordinary.ignoresMouseEvents)
    }

    @Test("one rule covers every panel Proctor draws over other people's windows")
    func oneRuleForEveryOverlay() {
        // Three surfaces cover other applications: the run panel, the takeover
        // tint and the drawn pointer. The pointer was measured at sharingState 1
        // while the other two were 0, which put Proctor's own cursor into any
        // display-scoped capture taken during a run. They read one function now,
        // so a fourth surface cannot be added with a different answer.
        for environment in [[:], [OverlayCapture.variable: "1"]] as [[String: String]] {
            let expected = OverlayCapture.excludedFromCapture(in: environment)
            #expect(Takeover.surface(reduceTransparency: false, reduceMotion: false,
                                     hudLevel: 25,
                                     excludedFromCapture: expected).excludedFromCapture == expected)
        }
    }

    @Test("resolving through the catalogue agrees with the reader the panels call")
    func noDrift() {
        let probes: [String?] = [nil, "", " ", "0", "off", "false", "no", "1", "true",
                                 "on", "yes", "nonsense"]
        for raw in probes {
            let env = raw.map { [OverlayCapture.variable: $0] } ?? [:]
            #expect(SwitchResolver.isOn(raw, for: SwitchCatalogue.overlayCapture)
                    == OverlayCapture.lifted(in: env),
                    "\(OverlayCapture.variable) on \(raw ?? "<unset>")")
        }
    }
}
