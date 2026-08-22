# DEF-136 — all 28 force-unwrap sites in `Tests`, classed

Denominator: `grep -rn ')!' Tests`, recorded verbatim in `unwrap-census-raw.txt` before any edit.
It returned **29 lines at `4d62f33`**. One of them — `CommandSurfaceTests.swift:47` — is prose
inside a comment recording PRO-0090's own fix, so the real population is **28 sites**.

**The brief counted 27.** The extra one is in `ProctorCoreTests.swift`, which the brief listed at 3
and which now holds 4. The drift is recorded rather than reconciled away: a denominator that
quietly changes size between the brief and the fix is the first thing this campaign's own notes
warn about.

## Why two groups and not one

Converting all 28 blind would have been faster and would have said nothing. `TimeZone(identifier:
"UTC")!` cannot fail; `Toolchain.entry(for: "cua-driver")!` can, and that is the shape that bit —
DEF-135 was a `command(id)!` on a literal id, and under mutation it produced signal 5, `0 tests`,
`0 suites` and no verdict line at all, masking four honest failures the same run had already found.
The classification is the deliverable, so a later sweep of `)!` in `Tests` reads this file instead
of re-deciding.

The test for *unfailable* is not "it has never failed". It is: **name the input space, and show the
failing branch is not in it.**

## Group 1 — unfailable by construction (4 sites, left as they are)

Each carries the reason in a comment beside it, pointing here.

| Site | Expression | Why the failing branch is unreachable |
|---|---|---|
| `TUIHistoryPaneTests.swift:40` | `TimeZone(identifier: "UTC")!` | `"UTC"` is the one identifier Foundation guarantees on every Darwin platform — it is what the framework itself falls back to. No tzdata this package can be built against omits it. |
| `SwitchSettingsTests.swift:498` | `bad.data(using: .utf8)!` | A Swift `String` is always well-formed Unicode and UTF-8 encodes every scalar, so `data(using: .utf8)` on one is total. The argument is a literal from an array of literals in the same expression. |
| `SwitchSettingsTests.swift:521` | `"…".data(using: .utf8)!` | Same, over a single raw-string literal. |
| `ProctorCoreTests.swift:1231` | `UnicodeScalar(0xF702)!` | `UnicodeScalar(_: UInt32)` returns nil only for a surrogate (D800–DFFF) or a value above 10FFFF. `0xF702` is a literal in the BMP private-use area — `NSLeftArrowFunctionKey` — so no input reaches the failing branch. |

## Group 2 — live, and converted (24 sites)

Every one unwraps a lookup, a parse or a crypto call against production code or production data.
That is DEF-135's shape exactly: the regression the test exists to catch is the input that makes
the unwrap nil, so the trap fires instead of the assertion, and the runner dies with nothing to say.

| File | Sites | What is unwrapped | Conversion |
|---|---|---|---|
| `AuditChainTests.swift` | 11 | `AuditSeal.seal` / `sealLine` / `encode` / `decode` over records this suite seals and the chain verifier reads | `try #require`; the `Trail` fixture's `init`, `sealUnchained` and `append` became `throws`, and 34 call sites gained `try` |
| `AuditChainWiringTests.swift` | 4 | `AuditSeal.seal` over pre-chain history, including inside a `rethrows` closure | `try #require`; four tests became `throws` |
| `ProctorCoreTests.swift` | 3 | `Data(base64Encoded: box.ct)`, `AuditSeal.seal`, `String(data:encoding:)` | two `try #require`; the third **restructured** to `String(decoding:as: UTF8.self)`, which is total, so the unwrap is gone rather than deferred |
| `ToolchainTests.swift` | 2 | `Toolchain.entry(for:)` — a catalogue lookup by literal id, the named shape | `try #require`; the `entry(_:)` helper became `throws` and 11 call sites gained `try` |
| `TUIHistoryPaneTests.swift` | 1 | `TimeZone(identifier: "Australia/Adelaide")` — a *regional* lookup, which a trimmed tzdata resolves to nil | `try #require` |
| `SwitchSettingsTests.swift` | 0 | — | both sites are group 1 |
| `MenuBarReadinessTests.swift` | 2 (one line) | `script.range(of: "kill -0")` and `range(of: "open ")` over a script the product generates | `try #require`, one per range, named separately so a failure says which token went missing |
| `GuestInventoryTests.swift` | 1 | `Toolchain.entry(for: tool)` | `try #require` |
| `RunHUDCharacterAssetTests.swift` | 1 | `CGContext(data:…)` over a decoded bundle asset — a zero-dimension image, the shape a missing or truncated asset produces, makes it nil | `try #require`; `pixels` and `inkBox` became `throws` |

24 converted + 4 unfailable = 28.

**After the change the same grep returns 6 lines**, and none of them is a live site: the 4 recorded
above, plus 2 comment lines. One is PRO-0090's note in `CommandSurfaceTests.swift`; the other is a
comment this item added, which quotes `)!` while explaining why the site beside it is unfailable.
Recorded exactly rather than rounded to the 5 a first count gave, because a census whose own
arithmetic drifts is the failure this file exists to prevent.

## Named, and deliberately not swept here

`grep -rn ')!' Tests` is the brief's denominator and it is not the whole hazard. Two shapes sit
outside it and are recorded so the next sweep starts from a true statement rather than from this
one's boundary:

- **`try!`** — e.g. `try! key.signature(for: material)` in `AuditChainTests`, `try! String(contentsOf:)`
  in `AuditChainWiringTests`. Identical failure mode: a throw aborts the runner rather than failing
  the test.
- **`!` on a property or a subscript rather than a call** — e.g. `args.last!` at
  `MenuBarReadinessTests.swift:355`, which `)!` cannot match.

Neither is in this item's contract. Both belong in the follow-on defect recorded as **DEF-140**.
