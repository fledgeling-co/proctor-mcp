import Testing
@testable import ProctorCore

@Suite("Window presentation")
struct WindowPresentationTests {

    @Test("the extras item being up is not the Status window being up")
    func extrasDoNotCountAsMain() {
        // hasVisibleWindows is true whenever anything is on screen. After
        // setup that is the extras item, even with Status closed.
        #expect(WindowPresentation.shouldPresentMain(visibleMainExists: false))
        #expect(!WindowPresentation.shouldPresentMain(visibleMainExists: true))
    }

    @Test("a missing Proctor-titled window must be created, not ordered")
    func missingMainPresents() {
        let titles = ["", "History"]
        let visible = [true, false]
        #expect(WindowPresentation.mainWindowIndex(titles: titles, visible: visible) == nil)
        #expect(WindowPresentation.shouldPresentMain(titles: titles, visible: visible))
    }

    @Test("an ordered-out Proctor window still presents")
    func orderedOutMainPresents() {
        let titles = ["Proctor", ""]
        let visible = [false, true]
        #expect(WindowPresentation.mainWindowIndex(titles: titles, visible: visible) == 0)
        #expect(WindowPresentation.shouldPresentMain(titles: titles, visible: visible))
    }

    @Test("a visible Proctor window is left alone")
    func visibleMainIsIdle() {
        let titles = ["Proctor"]
        let visible = [true]
        #expect(!WindowPresentation.shouldPresentMain(titles: titles, visible: visible))
    }

    @Test("History is not the Status window")
    func historyIsNotMain() {
        #expect(!WindowPresentation.isMainWindow(title: "History"))
        #expect(WindowPresentation.isMainWindow(title: "Proctor"))
    }

    @Test("mismatched title and visibility arrays refuse to guess")
    func mismatchedArraysPresent() {
        #expect(WindowPresentation.mainWindowIndex(titles: ["Proctor"], visible: []) == nil)
        #expect(WindowPresentation.shouldPresentMain(titles: ["Proctor"], visible: []))
    }
}
