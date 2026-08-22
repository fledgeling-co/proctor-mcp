### 1. Acceptance Criteria vs. Spec & Triage Assumptions

* **Testability:** All nine criteria (A1–A9) are testable and falsifiable with concrete observations or exit-code checks.
* **Dropped / Silently Narrowed Items:**
  1. **Spec Acceptance Sketch bullet 1 dropped clause:** The spec requires *"with the reason recorded where they were made to differ"* ([spec-PRO-0100.md:47-48](file:///Users/lukerhodes/Dev/proctor-mcp/.worktrees/PRO-0100/docs/specs/spec-PRO-0100.md#L47-L48)). Slice 1's prose notes adding an explanatory sentence to the caption in [`design/surfaces/proctor-surfaces.html:1008`](file:///Users/lukerhodes/Dev/proctor-mcp/.worktrees/PRO-0100/design/surfaces/proctor-surfaces.html#L1008), but criterion **A1** checks only that `Skip setup` is drawn between `Back` and the primary button, omitting verification of the caption reason text.
  2. **Triage Assumption 5 silently narrowed:** Assumption 5 specifies: *"Both remaining unsafe shapes are converted, not exempted"* ([spec-PRO-0100.md:94](file:///Users/lukerhodes/Dev/proctor-mcp/.worktrees/PRO-0100/docs/specs/spec-PRO-0100.md#L94), reinforced at [line 60](file:///Users/lukerhodes/Dev/proctor-mcp/.worktrees/PRO-0100/docs/specs/spec-PRO-0100.md#L60)). The plan silently narrows this by creating an exemption class ("Group 1 — total over a closed input space, kept") for 3 bare force-unwraps in [`ExternalWitnessTests.swift`](file:///Users/lukerhodes/Dev/proctor-mcp/.worktrees/PRO-0100/Tests/ProctorAgentTests/ExternalWitnessTests.swift) and narrowing **A6** to *"no unclassed bare `!` remains in `Tests`"*.

---

### 2. Slice 2 Reasoning, Guard Verification & SwiftUI ButtonStyle

* **Correctness of reasoning:** Correct. [`WalkthroughFlowTests.swift:468-471`](file:///Users/lukerhodes/Dev/proctor-mcp/.worktrees/PRO-0100/Tests/ProctorCoreTests/WalkthroughFlowTests.swift#L468-L471) (`skipIsNeverClosed`) asserts `source.components(separatedBy: ".disabled(").count - 1 == 1`. Wrapping the `Button` in an `if/else` branch duplicates `.disabled(`, raising the count to 2 and failing the guard.
* **All three named clauses pass unedited:**
  1. `skipIsNeverClosed` ([WalkthroughFlowTests.swift:468-481](file:///Users/lukerhodes/Dev/proctor-mcp/.worktrees/PRO-0100/Tests/ProctorCoreTests/WalkthroughFlowTests.swift#L468-L481)): Passes. `PrimaryProminence` contains no `.disabled(`, keeping the file count at 1, and preserves the token order `ID.skip` < `ID.primary` < `.disabled(!WalkthroughFlow.primaryEnabled(`.
  2. `theViewDisablesRatherThanHides` ([WalkthroughFlowTests.swift:153-160](file:///Users/lukerhodes/Dev/proctor-mcp/.worktrees/PRO-0100/Tests/ProctorCoreTests/WalkthroughFlowTests.swift#L153-L160)): Passes. Replacing `.buttonStyle(.borderedProminent)` at [`Walkthrough.swift:115`](file:///Users/lukerhodes/Dev/proctor-mcp/.worktrees/PRO-0100/Sources/ProctorUI/Walkthrough.swift#L115) with `.modifier(PrimaryProminence(...))` keeps `.disabled(!WalkthroughFlow.primaryEnabled(` within ~230 characters of `WalkthroughFlow.ID.primary` (under the 400-character budget).
  3. `theRowDoesNotDecideItsOwnProminence` ([WalkthroughFlowTests.swift:228-238](file:///Users/lukerhodes/Dev/proctor-mcp/.worktrees/PRO-0100/Tests/ProctorCoreTests/WalkthroughFlowTests.swift#L228-L238)): Passes. Placing `PrimaryProminence` before `HeroPermRow` excludes its `.borderedProminent` from the scanned range.
* **SwiftUI `.buttonStyle` propagation:** Yes. In SwiftUI, `buttonStyle` writes to the environment (`EnvironmentValues`). Environment values propagate down the view tree to descendant views regardless of intermediate modifiers like `.disabled` or `.hint` (`.accessibilityHint`).

---

### 3. Declaration Order of `PrimaryProminence` vs. `HeroPermRow`

* **Verification:** Verified. [`WalkthroughFlowTests.swift:229-233`](file:///Users/lukerhodes/Dev/proctor-mcp/.worktrees/PRO-0100/Tests/ProctorCoreTests/WalkthroughFlowTests.swift#L229-L233) defines `row` from `range(of: "private struct HeroPermRow")` through to EOF and asserts `row.components(separatedBy: ".borderedProminent").count - 1 == 1`. Declaring `PrimaryProminence` after `HeroPermRow` would place a second `.borderedProminent` into `row`, raising the count to 2 and failing the test. Declaring it before `HeroPermRow` prevents this.

---

### 4. Slice 5 Force-Unwrap Classifications in `ExternalWitnessTests.swift`

* **Site 1 — [ExternalWitnessTests.swift:102](file:///Users/lukerhodes/Dev/proctor-mcp/.worktrees/PRO-0100/Tests/ProctorAgentTests/ExternalWitnessTests.swift#L102) (`box.value!.get()`):** **Holds.** In [`offPool`](file:///Users/lukerhodes/Dev/proctor-mcp/.worktrees/PRO-0100/Tests/ProctorAgentTests/ExternalWitnessTests.swift#L91-L103), `worker` calls `box.set(...)` in both `do` and `catch` arms before calling `continuation.resume()`. `withCheckedContinuation` cannot unblock before `resume()` executes, and `OutcomeBox` synchronizes via `NSLock`. `box.value` is guaranteed non-nil.
* **Site 2 — [ExternalWitnessTests.swift:498](file:///Users/lukerhodes/Dev/proctor-mcp/.worktrees/PRO-0100/Tests/ProctorAgentTests/ExternalWitnessTests.swift#L498) (`raw.baseAddress!`):** **Holds.** [Lines 494–497](file:///Users/lukerhodes/Dev/proctor-mcp/.worktrees/PRO-0100/Tests/ProctorAgentTests/ExternalWitnessTests.swift#L494-L497) unconditionally append 4 bytes (`declared`) to `frame`. For non-empty `Data` (`count >= 4`), `Data.withUnsafeBytes` guarantees `raw.baseAddress` is non-nil.
* **Site 3 — [ExternalWitnessTests.swift:1106](file:///Users/lukerhodes/Dev/proctor-mcp/.worktrees/PRO-0100/Tests/ProctorAgentTests/ExternalWitnessTests.swift#L1106) (`raw.baseAddress!`):** **Safety holds, but plan rationale is inaccurate.** The plan claims *"Same construction, same file."* Line 498 constructs the buffer inline with an explicit 4-byte append, whereas [line 1103](file:///Users/lukerhodes/Dev/proctor-mcp/.worktrees/PRO-0100/Tests/ProctorAgentTests/ExternalWitnessTests.swift#L1103) obtains `frame` from `FrameCodec.encode(...)`. Because `FrameCodec.encode` ([Transport.swift:17-21](file:///Users/lukerhodes/Dev/proctor-mcp/.worktrees/PRO-0100/Sources/ProctorCore/Transport.swift#L17-L21)) prepends a 4-byte length prefix, a decoded frame is non-empty (`count >= 4`) and safe, but it is not the same local construction.

---

### 5. Realness of Analogues & Slice Ordering

* **Realness:** Every cited analogue is real and matches the exact lines and symbols in the worktree:
  * `WalkthroughFlow.showsSkip` ([WalkthroughFlow.swift:159-163](file:///Users/lukerhodes/Dev/proctor-mcp/.worktrees/PRO-0100/Sources/ProctorCore/WalkthroughFlow.swift#L159-L163)) and `wt-foot` in [`proctor-surfaces.html:1000-1005`](file:///Users/lukerhodes/Dev/proctor-mcp/.worktrees/PRO-0100/design/surfaces/proctor-surfaces.html#L1000-L1005).
  * `HeroPermRow.allowButton` ([Walkthrough.swift:350-360](file:///Users/lukerhodes/Dev/proctor-mcp/.worktrees/PRO-0100/Sources/ProctorUI/Walkthrough.swift#L350-L360)).
  * `BrowserLaneWiringTests.harness` ([BrowserLaneWiringTests.swift:62-80](file:///Users/lukerhodes/Dev/proctor-mcp/.worktrees/PRO-0100/Tests/ProctorAgentTests/BrowserLaneWiringTests.swift#L62-L80)), `Session.swift:743,747` default probes, and `SessionDoctor.swift:25,28`.
  * `HoldAttributionWiringTests.everyEndingPathLeavesNothingHeld` ([HoldAttributionWiringTests.swift:367-374](file:///Users/lukerhodes/Dev/proctor-mcp/.worktrees/PRO-0100/Tests/ProctorAgentTests/HoldAttributionWiringTests.swift#L367-L374)).
  * All 7 listed bare-`!` test sites in Slice 5.
  * `gemini.md:21` ("twenty tools"), `ToolCatalogue.swift` (21 tools), and the stale PRO-0085 path in [`skill_doc_measure.py:36`](file:///Users/lukerhodes/Dev/proctor-mcp/.worktrees/PRO-0100/scripts/campaign/skill_doc_measure.py#L36).
* **Slice Ordering:** Closes cleanly. Slices 1–6 modify mutually disjoint files and systems (design HTML, UI view, agent wiring test harnesses, test suite unwraps, external skill doc/scripts) with zero inter-slice ordering dependencies.

---

### 6. Single Largest Unnamed Risk

* **Cascading signature & closure type breakages across ~50 non-throwing test methods in Slice 5:**
  Converting 86 `try!` occurrences to `try` across 11 test files cannot be solved everywhere by simply adding `throws` to `@Test` functions. `try!` sites located within non-throwing closures (e.g. `Thread { ... }`, `DispatchQueue` blocks, custom assertions, or non-throwing test helpers) will produce compiler errors unless wrapped in explicit `do/catch` or bridged via `#require`. Making shared test helpers `throws` cascades signature changes and `try` annotations to all caller sites throughout the test suite.
