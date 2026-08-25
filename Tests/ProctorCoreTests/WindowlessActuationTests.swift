import Testing
@testable import ProctorCore

/// DEF-336. `proctor_act` resolved a window handle before any step ran, so a
/// menu-bar-only application — one whose first window is opened by a menu
/// command — could not be driven at all. The menu tree hangs off the
/// application element, so the step never needed a window; the resolution in
/// front of it did.
@Suite("Windowless actuation: the app plane is a real target")
struct WindowlessActuationTests {

    @Test("an app handle is told apart from a window handle by shape, not by hope")
    func handleShapes() {
        #expect(WindowlessActuation.isAppHandle("app:2614:5"))
        #expect(WindowlessActuation.isWindowHandle("win:5:0"))
        #expect(!WindowlessActuation.isAppHandle("win:5:0"))
        #expect(!WindowlessActuation.isWindowHandle("app:2614:5"))
        // A handle from another category is not an app handle wearing a hat.
        #expect(!WindowlessActuation.isAppHandle("gst-sequoia-01"))
        #expect(!WindowlessActuation.isAppHandle("dev-booted-1"))
        // The pid and the epoch are both numbers, and a shape check that skips
        // that admits "app:notapid:x" — which then fails somewhere less useful.
        #expect(!WindowlessActuation.isAppHandle("app:notapid:5"))
        #expect(!WindowlessActuation.isAppHandle("app:2614"))
        #expect(!WindowlessActuation.isAppHandle("app:2614:5:6"))
    }

    @Test("a batch of menu steps runs against an application, and a click does not")
    func admission() {
        #expect(WindowlessActuation.canRunWithoutWindow([.menu]))
        #expect(WindowlessActuation.canRunWithoutWindow([.menu, .waitFor, .appleScript]))
        #expect(!WindowlessActuation.canRunWithoutWindow([.menu, .press]))
        #expect(!WindowlessActuation.canRunWithoutWindow([.click]))
        // An empty batch is not admitted: there is nothing to serve, and saying
        // yes to it would report a run that actuated nothing as a windowless one.
        #expect(!WindowlessActuation.canRunWithoutWindow([]))
    }

    @Test("the refusal names every offending kind once, not the count and not twenty times")
    func refusalNamesKinds() {
        let kinds: [ActionStep.Kind] = [.menu, .press, .press, .setValue, .menu, .press]
        let needing = WindowlessActuation.kindsNeedingAWindow(kinds)
        #expect(needing == [.press, .setValue])

        let r = WindowlessActuation.refusal(kinds: kinds, app: "app:2614:5")
        #expect(r.message.contains("app:2614:5"))
        #expect(r.message.contains("press"))
        #expect(r.message.contains("setValue"))
        #expect(!r.message.contains("menu"))
        // The old refusal said "no window with handle app:2614:5", which sent the
        // caller looking for a window that the app does not have and cannot get
        // without the very command it was trying to press.
        #expect(!r.message.contains("no window with handle"))
        #expect(r.remedy.contains("menu"))
    }

    @Test("one offending kind reads as singular, and several read as plural")
    func refusalGrammar() {
        #expect(WindowlessActuation.refusal(kinds: [.menu, .press], app: "app:1:1")
            .message.hasSuffix("addresses something inside a window"))
        #expect(WindowlessActuation.refusal(kinds: [.press, .scroll], app: "app:1:1")
            .message.hasSuffix("address something inside a window"))
    }

    @Test("an app handle naming nothing attached is refused as unattached, not as windowless")
    func notAttached() {
        let r = WindowlessActuation.notAttached("app:999:1")
        #expect(r.message.contains("no attached application"))
        #expect(r.remedy.contains("attach"))
        // The two refusals are different answers to different questions, and
        // collapsing them is what sent a caller round a retry loop.
        #expect(r.message != WindowlessActuation.refusal(kinds: [.press],
                                                         app: "app:999:1").message)
    }

    @Test("every step kind is classified, so a new one cannot arrive unjudged")
    func totality() {
        for kind in ActionStep.Kind.allCases {
            let admitted = WindowlessActuation.appPlaneKinds.contains(kind)
            let needing = WindowlessActuation.kindsNeedingAWindow([kind])
            #expect(admitted == needing.isEmpty,
                    "\(kind.rawValue) is admitted and needed a window, or neither")
        }
        // And the admitted set is exactly the three that address the process:
        // widening it silently is how a click reaches a nil window element and
        // fails somewhere with no name on it.
        #expect(WindowlessActuation.appPlaneKinds == [.menu, .appleScript, .waitFor])
    }
}
