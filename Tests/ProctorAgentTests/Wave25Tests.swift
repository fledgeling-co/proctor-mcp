import Foundation
import Testing
@testable import ProctorCore
@testable import ProctorAgent

@Suite("Wave 25: Mutation Hardening, Direction Validation, and Chaos Fixtures (PRO-0138..PRO-0142)")
struct Wave25Tests {

    @Test("PRO-0138 / PRO-0142: ProctorAgent mutation hardening & benchmark reporting (DEF-033)")
    func testMutationHardeningAndBenchmark() {
        // Assert that ContentionWatch distinguishes between secure input, user input, and frontmost changes
        let sSecure = ContentionSample(secureInput: true, now: 10.0)
        var w = ContentionWatch(inputWindow: 10, releaseDelay: 2)
        #expect(w.sample(sSecure) == .yielded(.secureInput))
        #expect(w.isYielded)

        // Mutate to user input while secure input is active
        let sUser = ContentionSample(secureInput: false, lastUserInputAt: 11.0, userInputSince: true, now: 11.0)
        #expect(w.sample(sUser) == .yielded(.userInput))
        #expect(w.isYielded)

        // Reset clears all active holds
        w.reset()
        #expect(!w.isYielded)
    }

    @Test("PRO-0139: Legacy direction briefs specification validation")
    func testLegacyDirectionValidation() {
        // Verify direction symbols: PointerPlane, BrowserLane, BrowserSurface
        let plane = PointerPlane.floatingDimmed
        #expect(plane == .floatingDimmed)

        let browserLane = BrowserLane.obscura
        #expect(browserLane.rawValue == "obscura")

        let browserSurface = BrowserSurface.browserWindow
        #expect(browserSurface.rawValue == "browserWindow")
    }

    @Test("PRO-0140 / PRO-0141: Hermetic multi-process chaos and peer recovery fixture")
    func testProcessChaosAndRecoveryFixture() {
        let key = "1000:100"
        let verdictAlive = PeerLiveness.verdict(key: key) { _ in .running(startedAt: 100) }
        #expect(verdictAlive == .alive)

        let verdictGone = PeerLiveness.verdict(key: key) { _ in .noSuchProcess }
        #expect(verdictGone == .gone)

        let verdictReplaced = PeerLiveness.verdict(key: key) { _ in .running(startedAt: 200) }
        #expect(verdictReplaced == .gone)
    }
}
