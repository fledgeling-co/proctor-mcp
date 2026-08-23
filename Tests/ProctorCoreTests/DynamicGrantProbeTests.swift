import Foundation
import Testing
@testable import ProctorCore

// PRO-0111 / DEF-180 / REQ-162: Dynamic TCC Grant Re-probe Lifecycle & Invalidation.
//
// Formally verifies:
// 1. Definite grant probe outcomes (.granted / .denied) are cached across consecutive claims.
// 2. Calling `invalidateDefinite()` clears the cached state, allowing fresh probes to run dynamically.
// 3. Unconfirmed outcomes back off and are never permanently frozen.
@Suite("PRO-0111 · Dynamic TCC Grant Re-probe Lifecycle")
struct DynamicGrantProbeTests {

    // MARK: - Definite Caching Invariant (CASE-0636)

    @Test("GrantProbeKeeper caches definite outcomes (.granted / .denied) for the process lifecycle")
    func definiteOutcomesAreCached() {
        let keeper = GrantProbeKeeper(bound: 1.5)

        // First claim starts attempt 1
        let decision1 = keeper.claim(now: 100.0)
        #expect(decision1 == .start(token: 1))

        // Record definite .granted
        keeper.record(.granted, token: 1, now: 100.1)
        #expect(keeper.cachedDefinite() == .granted)

        // Subsequent claims return .cached(.granted)
        #expect(keeper.claim(now: 100.5) == .cached(.granted))
        #expect(keeper.claim(now: 500.0) == .cached(.granted))
    }

    // MARK: - Dynamic Invalidation Seam (CASE-0637)

    @Test("invalidateDefinite clears cached state and allows dynamic re-probing on demand")
    func dynamicInvalidationAllowsReprobe() {
        let keeper = GrantProbeKeeper(bound: 1.5)

        // Establish initial .denied state
        let d1 = keeper.claim(now: 10.0)
        #expect(d1 == .start(token: 1))
        keeper.record(.denied, token: 1, now: 10.1)
        #expect(keeper.claim(now: 11.0) == .cached(.denied))

        // Explicit dynamic invalidation
        keeper.invalidateDefinite()
        #expect(keeper.cachedDefinite() == nil)

        // Next claim starts fresh attempt (token 2)
        let d2 = keeper.claim(now: 12.0)
        #expect(d2 == .start(token: 2))

        // Record updated state (.granted)
        keeper.record(.granted, token: 2, now: 12.2)
        #expect(keeper.claim(now: 13.0) == .cached(.granted))
    }

    // MARK: - In-Flight Join and Abandonment Lifecycle (CASE-0638)

    @Test("In-flight calls join running probe and timeout triggers backoff recovery")
    func inFlightJoinAndBackoff() {
        let keeper = GrantProbeKeeper(bound: 1.0)

        // Start probe at t = 50.0
        let start = keeper.claim(now: 50.0)
        #expect(start == .start(token: 1))

        // Call at t = 50.4 joins remaining 0.6s
        if case .join(let remaining) = keeper.claim(now: 50.4) {
            #expect(abs(remaining - 0.6) < 0.001)
        } else {
            Issue.record("Expected .join decision")
        }

        // Abandon at t = 51.0 (bound expired)
        keeper.abandon(token: 1, now: 51.0)

        // During first backoff (delay 2.0s -> next at 53.0s), claim yields .unconfirmed
        #expect(keeper.claim(now: 52.0) == .unconfirmed)

        // After backoff at t = 53.5s, next claim yields new .start(token: 2)
        #expect(keeper.claim(now: 53.5) == .start(token: 2))
    }
}
