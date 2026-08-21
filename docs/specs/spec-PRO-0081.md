# PRO-0081 — The carried acceptance clauses: A2's literals, A3's control

**Status:** To Do → Ready for AI · **Brief:** `docs/features-to-triage/74-the-carried-acceptance-clauses.md`
· **Lane:** headless `./scripts/test.sh` for A2, `macos-glass` for A3 · **Branch:** `ai/pro-0081`
· **Ledger id:** allocated upstream, not written here.

## What this closes

Two acceptance clauses merged carried rather than green, each recorded honestly in its own spec.
Both were deferred for a reason that has since expired, and a carried clause that outlives its
reason stops being a deferral and becomes an untested claim.

| Carry | Clause | Why it was carried | What expired |
|---|---|---|---|
| PRO-0066 A2 | every user-facing string comes from `StatusSurface`; a grep for a quoted string literal in `MainWindow.swift` outside an identifier returns nothing | converting five sections risked a working window with no instrument to prove it still worked | `SurfaceFidelity` and the embedded `ProctorReflector` shipped in PRO-0067 |
| PRO-0067 A3 | the disabled next button is present in the tree in every state where it is disabled | there was no `ProctorUI` test target and no way to ask present-versus-absent | the `macos-glass` lane is attached, proved, and has a working capture manifest |

## Measured before any change

`./scripts/test.sh` at `ai/wave-9`: **1,818 tests in 215 suites, exit 0.**

**A2.** `Sources/ProctorUI/MainWindow.swift` holds **176 string literals** by a tokeniser that
skips comments and does not descend into interpolation. Classified by syntactic position,
**132 are user-facing** and 44 are identifiers: 16 SF Symbol names, 20 paths, argv words, URLs and
window ids, 4 switch-case and comparison keys, and 4 literals with no letter in them.

**A3 does not have the population its clause describes.** `Walkthrough.swift` carries no
`.disabled(` modifier on any control. The primary button is never disabled in any state, so
"every state where it is disabled" is the empty set and any pass over it would be vacuous — the
third failure mode wave 11a named, where an instrument reads zero for a structural reason and the
zero looks like a real negative.

The design of record is unambiguous that this is a product gap rather than a design choice.
`design/surfaces/proctor-surfaces.html`, the `walkthrough`/`permissions` pane, draws
`<button class="btn" disabled>Connect a model</button>` and captions it: *"Continue is disabled
and visible rather than absent — a control that disappears makes the layout jump and teaches the
user the step does not exist."* The state matrix says the same of the whole surface class:
*"disabled … Menu bar, walkthrough, history toolbar, status switches. **Drawn.** Every one dims
in place and keeps its shortcut, rather than disappearing."*

So A3 was never only unverified. The behaviour it asserts was not built, and the clause has been
carried over an empty set since PRO-0067 merged.

## Behaviour

### A2 — the strings move, and the grep becomes a program

The clause's own grep is the acceptance evidence, so it has to be runnable rather than described.
A plain `grep` cannot decide the "outside an identifier" half, and a human deciding it per literal
is the judgement the brief asks to keep mechanical. `scripts/campaign/status_literals.py`
decides it **by syntactic position and never by reading the string**:

| Bucket | Position |
|---|---|
| `symbol` | argument to `systemName:`, `systemImage:`, `icon:` — an SF Symbol asset name |
| `system` | argument to `URL`, `sysctlbyname`, `appendingPathComponent`, `launchctl`, `openWindow(id:)`, `forAuxiliaryExecutable:`, or an inline `arguments` array |
| `key` | a `case "…":` label, or the right side of `==` / `!=` |
| `punctuation` | no letter anywhere in the literal — `""`, `", "`, `"\n"` |
| `display` | **everything else** |

It is **default-deny**, and that is the load-bearing choice. A positive "does this look like
prose" rule passes silently for every rendering construct nobody thought to list, so the only way
to make this one green is to move the string to `StatusSurface.Copy` rather than to widen a list.
All five counts print on every run, so the clause's denominator is visible rather than implied.

The five older sections' strings move to `StatusSurface.Copy`, one section at a time with the
suite run between each. Where a literal is an identifier that the classifier cannot see as one
because it is returned from a computed property rather than passed to a call, the mapping moves
to Core beside the value it belongs to — which is where the file's own comments already say such
things go: *"a shell string assembled in a view is a shell string nobody checks."*

### A3 — the control is drawn disabled, then witnessed on glass

The primary action is disabled on the `permissions` step until both grants are in, matching the
design of record. `WalkthroughFlow.primaryEnabled(on:accessibility:screenRecording:)` decides it
in Core, tested at every combination, because a decision made in a view body is one this repo
cannot prove. `Skip setup` is present on that step and stays enabled, so nobody is trapped by a
grant macOS will not give.

The clause is then asked on the glass lane: a signed `.build/Proctor.app` on a private socket,
its walkthrough opened on `permissions` with a grant missing, and the accessibility tree read by
a probe process that is not Proctor. The witness is the primary button appearing in that tree
with `AXEnabled` false — present and disabled, rather than absent.

`FidelityChannel.settling(.enabled)` returns `.tree`, so this is a property the harness is
declared able to settle. If the tree cannot resolve present-versus-absent for this control, the
case resolves `inconclusive:` naming the instrument, and the ceiling is recorded in structural
terms rather than the clause being dropped.

## What is deliberately not in scope

**No composition decisions from wave 9 are revisited.** The status window keeps its explanation,
its title block and its grant-row treatment. Those were the reader's call and they were made.
Every A2 change moves a string from one file to another and changes no wording.

**No surface the mock and the build already agree on is converted.**

**`/Applications/Proctor.app` is untouched.** Every glass measurement runs against
`.build/Proctor.app` on a private socket, the recipe PRO-0036, PRO-0075 and PRO-0078 all used.

**No second machine and no guest lane.** `proctor-guest` and `anvil-mac-node` stay stopped.

## Failure modes this spec is written against

**A gate edited to make it green.** The classifier is default-deny precisely so that widening it
is visible as a diff to the instrument rather than as a passing run. Its buckets are enumerated
here, and the arming run shows it reporting a violation for a string put back into a `Text(`.

**A vacuous pass over an empty set.** A3's population was empty and the clause would have read
green. The count of states in which the control is disabled is printed beside the count in which
it is present, so a zero is legible as a zero.

**Moving the examined code rather than the strings.** `enum Actions` stays in `MainWindow.swift`.
Relocating the file's machinery to shrink what the classifier examines is the same shape as
editing the gate, and the literal total is printed on every run so a drop in the denominator is
as visible as a drop in the violations.

**A capture that proves nothing but its filename.** The A3 capture is taken through
`capture_with_manifest.py`, and `capture-lineage.py --gate` must exit 0 with the published and
distinct counts having risen. The picture's subject is corroborated by the tree read, not by the
name of the file.

## Acceptance clauses

1. `python3 scripts/campaign/status_literals.py Sources/ProctorUI/MainWindow.swift` exits 0 and
   reports `display 0`, with the total literals examined printed beside it.
2. The same command, run against a copy of the file with one string moved back into a `Text(`,
   exits 1 and names that line. The arming run is recorded as its own artifact.
3. The identifier set is unchanged: `status_literals.py … --baseline=<committed snapshot>` reports
   `0 identifier(s) gone, 0 new`, so the copy moved out of the view and the view's machinery did
   not move out of the file.

   **This clause was redrafted mid-item and the original wording is recorded rather than
   overwritten.** It first read *"the literal total examined at the end is not materially below
   the 176 measured at the start"*. That is unsatisfiable alongside clause 1 and always was:
   moving 132 user-facing literals out of the file necessarily takes the total from 176 to 44,
   so the numeric form could only ever have been failed or waived, never passed. It was a stale
   proxy for the real question — did the machinery leave too? — written before the baseline gate
   existed. An out-of-family review (grok-4.6) had already replaced the count with a set
   comparison on the ground that a count collides where a set does not, and the plan and both
   progress notes were updated to the set form while this clause was not. The set comparison is
   the stricter test: it catches one identifier swapped for another, which any count preserves.
   Armed and shown failing in `a2-arming.txt` run 4.
4. Every string the five older sections lost is reachable from `StatusSurface.Copy` or from a
   Core value beside the type it describes, and the wording is unchanged. A test asserts the copy
   is non-empty and that no two constants hold the same string by accident.
5. `WalkthroughFlow.primaryEnabled(on:accessibility:screenRecording:)` is tested at every
   combination of its inputs, and the `permissions` step with a grant missing is the only
   combination that returns false.
6. On `macos-glass`, the walkthrough's primary control is read out of the accessibility tree by a
   process that is not Proctor, in a state where it is disabled, and reports enabled false with
   the identifier `proctor.walkthrough.action.primary`. The count of states asked and the count in
   which the control was present are both recorded.
7. If the tree cannot resolve present-versus-absent, the case resolves `inconclusive:` naming the
   instrument. The clause is not dropped and the requirement is not marked `n/a`.
8. `python3 capture-lineage.py docs/test-campaign --gate` exits 0, and the published and distinct
   counts are higher than before this item.
9. `./scripts/test.sh` exits 0, with the suite count before and after.
10. PRO-0066's and PRO-0067's progress notes are updated where the carry was recorded. A carry
    closed only in a new document is a carry a future reader finds still open.
11. `cases.json`, `inventory.json` and `campaign.json` are appended to only, within the ranges
    allocated to this item (CASE-0100..0109, DEF-035..039, REQ-048..049).
    `docs/feature-specs/LEDGER.md` is not touched.

## Open questions

**Whether disabling the primary is this item's to do.** The brief presumes states in which the
control is disabled and there are none. Recording the clause as vacuously true would be the exact
dishonesty this wave exists to remove, and the design of record mandates the behaviour by name, so
the item builds it, records the divergence as a defect, and witnesses the clause over a population
that is no longer empty. Reversible, and flagged in the runner's report rather than settled
silently.
