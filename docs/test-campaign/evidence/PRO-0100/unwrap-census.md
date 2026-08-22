# DEF-140 — the two force-unwrap shapes `grep -rn ')!' Tests` cannot match, classed

PRO-0098 closed DEF-136 over its own denominator, `grep -rn ')!' Tests`, and recorded that the
denominator was not the whole hazard. This finishes the class. Raw census taken before any edit and
recorded verbatim in `unwrap-census-raw.txt`.

**Why it matters more than one red test.** Both shapes abort the runner. A run that aborts reports
**no swift-testing verdict line at all**, which `scripts/test.sh` correctly refuses to call a pass —
but only after the run is over and the information is gone. DEF-135's original was `command(id)!` on
a literal id: under mutation it produced signal 5, `0 tests`, `0 suites` and no verdict, masking
four honest failures the same run had already found. That is the failure this class is about.

## The denominator, stated as three greps

A census whose own boundary is undeclared is the first failure mode in this campaign's list, so all
three patterns are recorded with before and after counts, at `9f99a0f`:

| Pattern | Before | After | What is left |
|---|---|---|---|
| `grep -rn 'try!' Tests` | **86** | **0** | nothing |
| `grep -rnE '[A-Za-z0-9_\]]!([^=]\|$)' Tests` | **13 lines / 14 unwraps** | **4 lines** | 3 group-1 sites + 1 comment |
| `grep -rn ')!' Tests` | **6** | **6** | DEF-136's own 4 group-1 sites + 2 comments — untouched by this item |

Together these three are the true denominator. The next sweep starts from that statement rather
than from this one's boundary.

## The method, unchanged from PRO-0098

The test for *unfailable* is not "it has never failed". It is: **name the input space, and show the
failing branch is not in it.** Converting all 100 blind would have been faster and would have said
nothing.

## Group 1 — total over a closed input space, kept (3 unwraps)

Each carries its reason in a comment beside it, pointing here.

| Site | Expression | Why the failing branch is unreachable |
|---|---|---|
| `ExternalWitnessTests.swift:109` | `box.value!.get()` | The `withCheckedContinuation` resumes only from inside the worker's `do`/`catch`, and both arms call `box.set` before `resume()`. No path reaches this line with the box unwritten; a worker that never started would hang rather than trap. |
| `ExternalWitnessTests.swift:509` | `raw.baseAddress!` | The four length-prefix bytes are appended to `frame` unconditionally two lines above, so the buffer is never empty, and `baseAddress` is nil only for an empty buffer. |
| `ExternalWitnessTests.swift:1126` | `raw.baseAddress!` | **A different construction from the site above, and the first draft of this file said "same construction, same file" and was wrong.** Here `frame` comes from `FrameCodec.encode` (`Sources/ProctorCore/Transport.swift:10-22`) behind a `try?`/`else return`. The guarantee is the encoder's rather than the caller's: it prepends four length bytes before appending the body, so every `Data` it returns is at least four bytes. Caught by the out-of-family plan review, which opened the file. |

**A reason that is true of the neighbouring site and not of this one is not a reason.** That is the
whole value of writing the input space out rather than pattern-matching on the expression.

## Group 2 — live, converted (11 bare unwraps + all 86 `try!`)

### The bare `!` sites, named because the grep will not find them again

| Site | Expression | Why it is live | Conversion |
|---|---|---|---|
| `GuestPoolWiringTests.swift:416` | `after! >= before!` | The `#expect(before != nil && after != nil)` above **records and returns** — swift-testing's `#expect` does not stop the test — so a nil reached the unwrap | two `try #require` |
| `SwitchSettingsTests.swift:183-184` | `lane.onValue!` | Read off the shipped switch catalogue; a lane that lost its `onValue` is the regression this test exists to catch | one `try #require`, reused |
| `ConsentSurfaceTests.swift:29` | `yieldInput!` | `SwitchCatalogue.named("PROCTOR_YIELD_INPUT")` — a lookup by **literal id against production data**, DEF-135's exact shape | `try #require` |
| `RunHUDTests.swift:550` | `named.first!` | Same non-stopping `#expect` above it | `try #require` |
| `GrantProbeTests.swift:104` | `GrantProbe.backoff.last!` | A production array; an empty one aborts rather than fails | `try #require` |
| `MenuBarReadinessTests.swift:361` | `…arguments(…).last!` | Production function output. The two `range(of:)` unwraps eight lines above already got this treatment under DEF-136 — the same test, the same hazard, one line the grep could not see | `try #require` |
| `StepDescriptionTests.swift:36, 416` | `line.first!` | Same non-stopping `#expect` above each | two `try #require` |

**The `#expect`-does-not-stop shape is four of the eleven**, and it is the one most likely to read
as already-guarded. A reviewer scanning for unguarded unwraps skips right past a `!` with a nil
check on the line above; the check is real and it does not stop anything.

### The `try!` sites

All 86, in 11 files, converted `try!` → `try`. **55 enclosing test functions gained `throws`**
(76 of the 86 sites sat in a non-throwing function; the remaining 21 were already in throwing ones,
and some functions hold several sites). `try! #require(x)` becomes `try #require(x)`: the trap
becomes the failure the `#require` was already written to be.

**One cascade, and it is the risk the out-of-family plan review named.** `throws` on the test
function does not reach a `try` inside a non-throwing closure. Two call sites of
`AuditChainWiringTests.withTrail` needed `try` on the call itself, because the helper was already
`rethrows` with a throwing closure parameter and the closure had only just begun to throw. Found by
the compiler, in one file, because the conversion built between files. A scan for the harder case —
a `try!` inside `Thread { }`, `.map { }` or `withUnsafeBytes { }` — returned **0 of 86**.

## What this does not claim

It does not claim the suite can no longer abort. Two unreproduced SIGTRAPs are recorded in
ORCHESTRATOR.md and neither is diagnosed; DEF-136 and DEF-140 together remove *this* cause from
every site in `Tests`, which is why such a run should now be rare rather than why one is impossible.
