### 1. The third disposition class (`no-independent-oracle`)

* **Verdict:** Honest.
* **Evidence:** `equivalent` denotes mathematical or observable invariance across all possible execution paths. Mutants like `plateHeight` (+44 → +45), `timeoutMs` (3000 → 3001), and `padX` (`scale * 2` → `scale * 3` at `scale > 1`) produce differing runtime values; calling them `equivalent` would be mathematically false. However, without an external authority (such as an Apple HIG token table, a hardware timing spec, or an RFC), any test killing them must assert the literal constant verbatim. That is circular tautology, not independent verification. (Survivor 11 was correctly differentiated and killed because its ink channel violated an internal palette invariant).
* **Alternative:** None of the remaining three (3, 5, 6) have a viable independent oracle unless design tokens or layout bounding-box constraints are formalized as first-class specifications.

---

### 2. The catalogue edit

* **Verdict:** Fixing an under-specified schema.
* **Evidence:** `ToolCatalogue` defines the MCP schema contract published to external consumers and language models. In an API specification, optional fields with undefined default behavior are specification gaps. The runtime implementation in `Dispatch.swift` already defaulted these parameters to `false`; adding `"Defaults to false."` to `includeTiles`, `tileHashes`, and `verbose` made the public interface contract explicit rather than retrofitting an oracle to fit source code.

---

### 3. The seams

* **Verdict:** Unchanged by construction across all six extractions.
* **Evidence:**
  * `AXEngineImpl.swift`: Injected closure defaults to `AXEngineImpl.liveRunningApps`, mapping the exact same `NSWorkspace` fields to `RunningApp`.
  * `RunHUDPanel.swift`: Broadened access control of `HUDPanel` from `private` to `internal`; zero behavioral or override changes.
  * `TakeoverOverlay.swift`: Extracted `InputBlocker.isTapDisabledNotice` evaluates the identical disjunction (`.tapDisabledByTimeout || .tapDisabledByUserInput`).
  * `AuditKeyStore.swift`: `publicKeyURL(in:)` executes the identical URL path construction.
  * `SessionKill.swift`: `KillCandidates.includingBarePid` isolates the exact guard condition and fallback candidate appendage previously executed inline.

---

### 4. The tests

* **Verdict:** `dispatchDefaultsAgreeWithTheCatalogue` (Survivors 2 & 8) asserts implementation syntax rather than runtime behavior.
* **Evidence:** `dispatchDefaultsAgreeWithTheCatalogue` reads `Dispatch.swift` as raw text via `#filePath` and parses `args.bool(...)` calls using regular expressions anchored to `// MARK: - proctor_` comments. A refactor that extracts decoding into helper structures, splits arguments across lines, alters comment markers, or runs tests in an environment without source files present will fail despite preserving runtime behavior. The remaining eight tests exercise genuine runtime invariants and pure extractions.
* **Alternative for Survivors 2 & 8:** Invoke tool dispatch directly with omitted arguments and assert the resolved option record rather than regex-linting source code.

---

### 5. The runner change

* **Verdict:** Correct.
* **Evidence:** Under high host contention (e.g. load average 271), timeouts are driven by thread and CPU starvation rather than mutant-induced deadlocks. Scoring a timeout as `killed` creates false confidence in test coverage. Counting timeouts as `survived` would penalize the suite for environment instability. Excluding `TIMEOUT` from the scored denominator (`scored = killed + survived`) ensures the survival rate reflects only verified executions, while the new `nearBound` and `timedOut` metadata preserves diagnostic visibility.

---

### 6. Anything raising the measured score without raising suite knowledge

* **Verdict:** `dispatchDefaultsAgreeWithTheCatalogue` kills mutants 2 and 8 via static source-text inspection rather than behavioral execution.
* **Evidence:** The test verifies that the text token `args.bool("includeTiles", false)` appears in `Dispatch.swift`. If that line is mutated, the regex fails, registering a "kill" without verifying that `proctor_stability` actually executes without tile comparisons when the flag is omitted at runtime.

---

OVERALL: ACCEPT
