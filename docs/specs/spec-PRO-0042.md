# PRO-0042: Backfill — `horizontalAlignment` on `proctor_assert`

**ID:** PRO-0042
**Status:** Triaged
**Created:** 2026-08-15
**Last updated:** 2026-08-15
**Brief:** `docs/features-to-triage/43-backfill-horizontal-alignment-assertion.md`
**Backfills:** commit `2b917ed` (shipped to main with no spec, plan, test or changelog entry)
**Builds on:** PRO-0001 (the assertion surface, `Outcome`, the skipped-is-not-a-pass rule)

## Feature description

`proctor_assert` should be able to answer a question a person asks about a
layout constantly and cannot ask it today: **is this element placed left, centre
or right inside the thing that contains it?**

The existing geometry kinds do not answer it. `frameEquals` needs the exact
rectangle, which nobody knows in advance. `containedIn` answers a yes/no about
being inside at all. `alignedWith` measures the distance between one element's
edge and another's, which is a measurement rather than a classification — with
no `edge` it passes when *any* of six deltas is small, and with an `edge` the
caller has to know which edge encodes the intent they are testing. None of them
lets a test say "this button should be right-aligned in its row" and get back
either a pass or the word for what it actually is.

That is the feature. The subject's frame is classified against a reference
rectangle — an explicit container, or the window when none is given — as one of
`left`, `center` or `right`, and compared against the placement the caller
expected.

## What actually shipped, and why most of it does not survive this spec

Commit `2b917ed` added the kind, the catalogue enum entry, and this classifier:

```swift
let wanted = expected.stringValue?.lowercased() ?? "leading"
let isCentered = abs(frame.centerX - refRect.centerX) <= tolerance
let isLeading  = abs(frame.x    - refRect.x)    <= (tolerance * 3.0) && !isCentered
let isTrailing = abs(frame.maxX - refRect.maxX) <= (tolerance * 3.0) && !isCentered
let observedAlignment = isCentered ? "center" : (isLeading ? "leading" : (isTrailing ? "trailing" : "custom"))
let ok = (wanted == observedAlignment) || (wanted == "left" && isLeading)
```

The feature is worth having. This classifier is not the one the feature wants,
and the six decisions below are decided on their merits rather than on what is
already in the file. Five of the six change the code.

### 1. One tolerance, not one and a triple

**Decided: `tolerance` means one distance, applied identically to both edges and
to the centre. The `* 3.0` goes.**

A caller who writes `tolerance: 8` has said what "aligned" means to them. Silently
tripling it on two of the three branches makes the parameter mean 8 or 24
depending on which branch the answer lands in, and a `leading` pass three times
weaker than the number the caller wrote. An element whose left edge sits 20pt
inside its container is not left-aligned; it is inset, and reporting `leading`
hides exactly the drift the assertion exists to catch.

The multiplier is compensating for something real — containers have padding, so
an element aligned inside a 16pt inset is 16pt off the container's own edge — but
it compensates by loosening the check for everyone rather than by telling the one
caller who hit it what happened. Padding is handled where it belongs instead: by
passing the content view as `container`, or by passing a tolerance that covers the
inset, and by a `custom` reason that reports the measured insets so the caller can
see which they need (decision 6).

### 2. The vocabulary is physical: left, center, right

**Decided: the classifications are `left`, `center` and `right`. `leading`,
`trailing` and `centre` are accepted as input aliases; the reported observation
is always the physical word.**

The code measures `frame.x` against `container.x` — a screen coordinate, in a
tree where nothing reads layout direction. In a right-to-left app the element a
developer calls *leading* sits at the larger x, so the shipped classifier would
report it `trailing`. Naming a physical measurement with the semantic word claims
a direction-awareness that is not there, and the failure it produces is one a
person would chase in the wrong place.

So the observation is named for what was measured. The alias table keeps every
existing caller working — `expected: "leading"` passes against an element on the
left, which is what it already did — and it closes the `"left"`-but-no-`"right"`
asymmetry, which was an oversight rather than a decision. The tool description
states that the terms are physical, so an RTL caller is told rather than misled.

Accepted inputs, case-insensitive: `left`, `leading`, `center`, `centre`,
`right`, `trailing`. Anything else is `skipped` with the list — the house
response to an unusable input, the one `frameEquals` gives an unparseable
rectangle and `alignedWith` gives an unknown edge — not a fail, which would
report a typo as a layout defect.

### 3. The nearest fit wins; only a genuine tie is `skipped`

**Decided: among the placements within tolerance, the one whose offset is smallest
is the observation. `skipped` is reserved for a tie — two or more smallest offsets
within half a point of each other.**

In a container barely wider than the element, more than one placement is within
tolerance at once. The shipped code resolves that by precedence — `isCentered`
pre-empts both edges — and returns `center` with no sign that anything was close,
so an element that fills its row fails a `right` assertion it does not actually
violate.

Precedence is a lie and passing whenever the wanted placement is among the
candidates is a vacuous green, but the first draft of this spec over-corrected to
skipping on any overlap, and the out-of-family gate killed it with a case that is
not exotic: a 28pt control in a 36pt cell has offsets of 0, 4 and 8, so at a
tolerance of 8 all three fit. That is an ordinary compact layout, `ok` requires
`skipped == 0`, and the kind would therefore be unable to assert the case it
exists for. Skip is the house answer to *no measurement* — no frame, an
unreadable container, an unusable word. Here the measurement exists and is
ranked; refusing to rank it is a different thing wearing the same word.

So the nearest offset wins. The 28-in-36 cell reads `left`, because 0 beats 4 and
8. What survives as `skipped` is the case where the ranking genuinely does not
exist: an element that fills its container has offsets of 0, 0 and 0, and left,
centre and right are indistinguishable — reported with that reason rather than as
a confident third of an answer.

The tie window is **half a point**, one device pixel at 2x, which is the finest
difference a layout can express. It must not be the tolerance, and the first
attempt at this spec made it 1.0 to match `alignedWith`'s rounding allowance,
which is the same number as the default tolerance and therefore switches the
ranking off wherever the default is in use: the candidate band is one tolerance
wide, so no two candidates can be further apart than that, and every
multi-candidate reading at the default would tie. A 16pt element flush against an
18pt cell has offsets of 0, 1 and 2 — plainly left-aligned, and unassertable
under that rule. The second out-of-family gate found it; the two constants are now
independent and the smaller one is justified by the display rather than by the
other kind's default.

### 4. One tolerance across the tool: the default becomes 1.0

**Decided: `horizontalAlignment` defaults to 1.0, the same as `alignedWith` and
`frameEquals`. The 8.0 goes.**

The first draft kept 8.0 and reconciled by documentation — `alignedWith` tests
coordinate equality, this classifies design intent against containers that carry
insets, 8 is one macOS layout-grid unit. The gate took that apart, and the
argument holds: decision 1 had just made padding the caller's problem, and 8.0
puts the slop straight back into the default. It also lands in the worst place
available. It is too loose to be strict — `|inset| <= 8` calls a deliberate 8pt
grid indent `left`, the exact thing the justification claimed it would not
swallow — and far too tight to rescue the window fallback it was aimed at, since
window content margins run 16 to 28pt. And after decisions 6 and 7, the correct
response to a padded container is to name the content view, at which point the
test genuinely is coordinate equality.

Unifying also disposes of the trap properly rather than labelling it. A human
reading two documented defaults may infer the right one; a model copying a
`tolerance` value from one assertion in a list to the next will not, and it no
longer has to. `tolerance` now means one thing everywhere on `proctor_assert`:
the distance at which two coordinates count as the same. A caller who wants slack
for a padded container passes it, and the `custom` reason tells them how much they
need.

### 5. It does not overlap `alignedWith` enough to remove either

**Decided: both stay; the boundary is stated in the spec and in the tool
description.**

`alignedWith` is a measurement between two things the caller names: it returns six
deltas and, given an `edge`, tests one of them. `horizontalAlignment` is a
classification of one element inside its container: it names which of three
placements describes it, rejects the other two, and defaults the container to the
window.

There is one genuinely shared case — `horizontalAlignment: "center"` against an
explicit container is the same test as `alignedWith: {node: container, edge:
"centerX"}` at the same tolerance. It stays shared because the classification form
does something the delta form cannot: it reports what the placement *is* when the
expectation fails, and it rejects the other two placements, where `alignedWith`
with no `edge` passes if any single one of six deltas is small. That is a much
weaker check wearing a similar name, which is itself a reason for the description
to distinguish them.

### 6. `custom` keeps its name and gains a reason worth relaying

**Decided: `custom` remains the observed classification, and the failure reason
carries the three measured offsets, the container that was used, and — when the
container defaulted to the window — the most likely fix.**

`custom` is the honest word: none of the three describe the placement. The problem
is not the word, it is that `Element observed as 'custom' but expected 'leading'`
tells a model nothing to relay and a person nothing to act on. The reason now
reads, for example:

> not left, center or right aligned within 1.0pt of the container: the left edge
> is 32.0pt inside it, the right edge 96.0pt inside, and the centre 32.0pt to its
> left. The container defaulted to the window frame — pass `container` with the
> content view's node id if the element is aligned inside an inset area.

The last sentence appears only when the container did default, because that is
when it is the likely cause.

### 7. A container that was asked for and did not resolve is `skipped`

Not in the brief; found while reading. `referenceRect` returns nil both when no
container was given and when a given one has no readable frame, and the shipped
code treats both the same — it falls back to the window. A caller who names a
content view that does not resolve gets a confident answer about a different
rectangle, with nothing saying so. Since decision 6 makes the window-versus-container
distinction the main thing a `custom` failure hangs on, that silent substitution
is now load-bearing. A container that was requested must resolve or the assertion
is `skipped`, which is what `containedIn` already does. The window fallback stays,
for the case where no container was asked for.

### 8. An absent `expected` is `skipped`, not an assumed `leading`

Also found while reading. The shipped default, `expected.stringValue?.lowercased()
?? "leading"`, means `{kind: "horizontalAlignment"}` with no expectation quietly
asserts left-alignment and can fail a layout nobody made a claim about. An
assertion with no expectation is not an assertion. It is `skipped`, carrying the
observed classification — so it still answers "what is this?" for exploratory use,
while `ok` correctly refuses to call it verified.

## Where the classifier lives

The classification is pure arithmetic over two rectangles, and every wrong answer
it can give looks exactly like a right one. It goes in `ProctorCore` beside
`RegionCrop`, `RegionDirt` and `SetOfMarks.toPixels`, which are there for the same
reason: it is the part of the check that can be tested without a window, a display
or an Accessibility grant. `SessionAssert` keeps the resolution of the subject, the
container and the window, and the shaping of the `Outcome`.

## Acceptance clauses

Each is witnessed by a Swift test. Core clauses run against the pure classifier;
the Agent clauses run against the `Outcome` shaping through the existing session
test harness.

1. **One tolerance.** An element whose left edge is `2 * tolerance` inside its
   container's classifies as `custom`, not `left`. At exactly `tolerance` it is
   `left`; just beyond, `custom`. The same holds symmetrically on the right edge
   and for the centre — no branch is looser than another.
2. **Physical vocabulary with aliases.** `leading` parses to `left`, `trailing` to
   `right`, `centre` to `center`, case-insensitively; an element on the left of its
   container passes `expected: "leading"` and `expected: "left"` alike, and the
   reported observation is `left` in both.
3. **Unknown word.** `expected: "middle"` is `skipped`, and the reason lists the
   accepted words.
4. **The nearest fit wins.** An element whose offsets put more than one placement
   within tolerance is reported as the placement with the smallest offset — a
   28pt element at the left edge of a 36pt container reads `left`, not `center`.
5. **A tie is `skipped`.** An element that exactly fills its container is
   `skipped` for every expectation, its reason naming all three candidates; two
   offsets equal within half a point tie the same way, and a half-point gap
   between them does not — so the ranking still runs at the default tolerance.
6. **One default.** With no `tolerance`, the kind behaves as `tolerance: 1.0`,
   the same number `alignedWith` and `frameEquals` already default to.
7. **`custom` reason.** A `custom` failure's reason contains all three measured
   offsets and the tolerance, and contains the container hint when the container
   defaulted to the window and not when one was supplied. A failure against a
   placement that was measured cleanly carries no container hint at all, because
   an inset container is not why it failed.
8. **Unresolvable or unmeasurable reference.** A `container` naming a node with
   no readable frame is `skipped` and is not answered against the window. A
   subject or a container whose frame is non-finite or has a negative width is
   `skipped`, rather than classified from comparisons that a NaN silently makes
   false. A container given as `[x,y,w,h]` is measured against directly.
9. **Absent expectation.** `{kind: "horizontalAlignment"}` with no `expected` is
   `skipped`, and its entry still carries the observed classification.
10. **No frame, no reference.** A subject exposing no frame is `skipped`; a
    subject with a frame and no container given and no window frame is `skipped`.
11. **Tool surface.** `proctor_assert` still advertises the kind, the tool count
    stays 19, and the description states the boundary against `alignedWith` and
    both defaults.

## Out of scope

- **Vertical alignment.** The same argument applies to top/middle/bottom and the
  classifier generalises, but nothing asked for it and an unused kind is surface
  to maintain. Recorded as child work.
- **Real layout-direction awareness.** Resolving RTL properly means reading the
  target app's layout direction, which the AX tree does not expose consistently.
  Decision 2 makes the current behaviour honest rather than pretending otherwise.
- **Distribution and spacing checks** (equal gaps in a row, and so on).

## What a `swift test` cannot witness here

Nothing structural. The classification is pure and the `Outcome` shaping is
reachable through the existing harness. What tests do not witness is whether 1.0pt
is the right strictness against real macOS layouts — that is a judgement, argued in
decision 4, that only use will confirm. The failure mode if it is wrong is the
benign one: a `custom` result whose reason states the inset the caller needs to
allow.

## Child work found, not scheduled

- **`verticalAlignment`,** the same classifier on the y axis. The Core type is
  written so the axis is a parameter in all but name; adding it is a catalogue
  entry, a case, and a test sweep.
- **`alignedWith` with no `edge` passes on any one of six deltas.** That is a very
  weak check with a confident name, found while writing decision 5. Not touched
  here — it is a behaviour change to a shipped kind with its own callers.

## Gates

The out-of-family review ran on grok (`grok-4.6`, effort `xhigh`), with the six
decisions and the shipped classifier inlined per the fleet contract's measured
prompt-length limit. It rejected two of them and both rejections were taken:

- **Decision 3** was "skip whenever more than one placement fits". Grok's
  counter-example — a 28pt control in a 36pt cell, offsets 0/4/8, every placement
  inside a tolerance of 8 — showed that an ordinary compact layout would become
  unassertable, since `ok` requires `skipped == 0`. Its point that skip is the
  house answer to *no measurement* rather than to a measurement one refuses to
  rank is the right reading of the file's opening rule. Rewritten to nearest-fit
  with a 1.0pt tie window.
- **Decision 4** was "keep 8.0 and document why it differs from `alignedWith`'s
  1.0". Grok held that 8.0 reintroduces the slop decision 1 had just removed, is
  simultaneously too loose to be strict and too tight to save the window fallback
  whose margins run 16–28pt, and that documenting a split default still traps a
  model copying `tolerance` between assertions in one list. Unified at 1.0.

Both changes make the code strictly stricter than what shipped, which is the safe
direction for a kind one day old with no known callers.

A second grok pass ran as the completeness critic over the finished
implementation, with the classifier and the assertion's decision order inlined. It
found four defects, all fixed:

- **The tie window equalled the default tolerance,** so the nearest-fit rule from
  decision 3 never ran at the default and an ordinary 2pt-slack row was
  unassertable. Argued and fixed in decision 3; the constants are now
  independent.
- **A non-finite frame produced a confident verdict.** Every comparison against a
  NaN is false, so a NaN width came back as `custom` — a fail — and a finite
  origin beside a NaN width came back as a confident `left`. Both are now
  `skipped`, along with a negative width, which is not the rectangle that was
  drawn.
- **The container hint was appended to a clean wrong-placement failure,** where it
  is advice about a different problem. It belongs to `custom` alone.
- **Three implemented paths had no test:** the window-has-no-frame skip, a
  container given as a rectangle rather than a node id, and an unmeasurable
  container. All three now have one.

It also noted that `isCustom` and `isTied` are mutually exclusive, so their
ordering is defensive rather than load-bearing. Left as written.

Build and test gate, recorded here and in the progress note:
`swift test --skip ObscuraPresenceWiringTests --skip BrowserLaneWiringTests`
(PRO-0041 — `Session.doctor` awaits `SCShareableContent`, which neither answers
nor throws in the test host).
