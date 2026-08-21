# Plan — PRO-0081: the carried acceptance clauses

**Spec:** `docs/specs/spec-PRO-0081.md` · **Branch:** `ai/pro-0081` off `ai/wave-9`
**Tier:** Standard. Two independent tracks, one mechanical and one on glass, no shared code.

## Track A — PRO-0066's A2

### The seam

`Sources/ProctorUI/MainWindow.swift` renders; `Sources/ProctorCore/StatusSurface.swift` holds
what it says. The seam already exists for three sections and this extends it to the rest. No
wording changes: every string is moved character for character, and the tests below are what
prove that rather than a reading of the diff.

### Order of work, with the suite between each

1. **The instrument first.** `scripts/campaign/status_literals.py`, default-deny, five buckets.
   Nothing moves until the clause can be asked, because a conversion with no instrument is the
   thing PRO-0066 refused to do.
2. Header and Permissions → `Copy`. Suite.
3. Tools → `Copy`, and the tool row's tone-to-symbol mapping to `StatusChecks.ToolRow.Tone`,
   beside `StatusSurface.LaneState.pill`, which is the same shape of decision. Suite.
4. Switches → `Copy`, including `sourceLine` and `consentText` as functions. Suite.
5. Activity, Connect, Agent, Footer and the pill → `Copy`. Suite.
6. The identifiers the classifier cannot see as identifiers because they are returned from a
   computed property rather than passed to a call: the Settings pane anchors to
   `StatusChecks.settingsPane(for:)`, the shim path to `Wire.shimPath(inBundle:)`, the launchd
   domain to `Wire.launchdDomain(uid:)`, and the agent label to the `Wire.agentLabel` that
   already existed and was duplicated. Suite.

### Test strategy

| Level | What it holds |
|---|---|
| `status_literals.py` | the clause itself: `display` 0, with the total examined printed |
| `status_literals.py --baseline` | the identifier set, committed, so the count is a set comparison rather than a number |
| `StatusSurfaceTests` | `Copy.all` non-empty and free of accidental duplicates; the list is as long as the file's declarations; `MainWindow.swift` quotes nothing it renders |
| `StatusChecksTests` | the three surviving Re-check buttons, each in its own block |

Arming: a string is put back into a `Text(` and into a `Button(`, and the checker names the line.
A fourth arming run guts the file of `enum Actions` and shows `display` still 0 while the baseline
gate fails — the evasion an out-of-family review named.

### What will break, and what to do about it

`StatusChecksTests.theRightRecheckWasDeleted` matches `Button("Re-check")` in the source. The
conversion is exactly what that literal cannot survive. Its assertions are re-expressed against
the converted form with the label pinned, not deleted — and the count it carried was wrong before
the change, because the agent-down block has read that label from a constant since PRO-0066 and
was invisible to the scan. Three, named individually.

## Track B — PRO-0067's A3

### What the investigation has to settle first

Whether the clause has a population. It does not: no control in `Walkthrough.swift` carries a
`.disabled(` modifier. The design of record draws the primary disabled on the `permissions` pane
and captions the rule. So the behaviour is built to the design, the divergence is recorded as a
defect, and only then is the clause asked.

### The measurement

1. `WalkthroughFlow.primaryEnabled(on:accessibility:screenRecording:)` in Core, all sixteen
   combinations written out, the disabled set asserted by name rather than by count.
2. `.build/Proctor.app` built and Developer ID signed. `/Applications/Proctor.app` untouched.
3. The build launched with `PROCTOR_SOCKET` naming nothing, so its report is nil and every grant
   reads false — which is what puts the flow in the state the design draws disabled, on a machine
   that holds the real grants.
4. The installed agent, a different process, resolves
   `proctor.walkthrough.action.primary` by identifier and reads `enabled`.
5. **Two-way, on the same build.** The same read on `intro` returns `enabled true`. A field pinned
   to false could not have produced it.
6. **The negative arm.** The same measurement against a build with the `.disabled` modifier
   removed — the behaviour as it stood before this item. If that build reads `enabled true` in the
   same state, the instrument is reading the control rather than the change.
7. The capture is taken through `capture_with_manifest.py` and its pixels are read rather than its
   filename, because a dimmed control is a visual claim that `AXEnabled` does not carry.

### If the tree cannot resolve it

`FidelityChannel.settling(.enabled)` returns `.tree`, so the channel is declared able. If the read
comes back absent or ambiguous, the case is `inconclusive:` naming the instrument and the clause
stays open. It is not marked `n/a` and the requirement is not reclassed.

## Registry

Cases CASE-0100..0109, defects DEF-035..039, requirements REQ-048..049. Appended only.
`docs/feature-specs/LEDGER.md` is not touched.

## Out of scope, and named so it is not mistaken for missed

The sibling files in `Sources/ProctorUI` still hold user-facing literals — `HistoryWindow.swift`,
`ProctorUIApp.swift`, `Walkthrough.swift`, `AgentModel.swift`, `HistoryModel.swift`. A2 names one
file. Their counts are measured and published rather than silently left, so the scope of the
clause is legible.
