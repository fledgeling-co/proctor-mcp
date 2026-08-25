---
sources: [REQ-024]
status: retired
validated-by: REQ-024 via CASE-0026, CASE-0087
validated-rungs: effect-witness, outcome
validated-provider: Process() in Sources/ProctorAgent/Actuation/CuaClients.swift — cua-driver and obscura
---
# A second browser lane for what Obscura cannot do

## The problem

PRO-0020 routes a browser page to Obscura. Obscura is a Rust engine rather than
packaged Chrome, and its own limits are documented and measured. Some of them stop
a real task rather than merely degrading it:

- **CSS animations and transitions never execute** (`document.getAnimations()`
  returns 0), so anything gated on a transition completing cannot be driven.
- **`Emulation.setEmulatedMedia` is accepted and inert**, so no print pass and no
  reduced-motion pass; `matchMedia` stays false while reporting success.
- **Web fonts never load**, so font fidelity is unmeasurable rather than perfect.
- **An empty computed value means "not implemented"**, not "not set", for
  `boxShadow`, `backgroundImage`, `textTransform`, `outline` and `flex`.
- **Shorthand computed styles resolve to `0px`** while the layout is correct, so a
  spacing assertion passes when it should fail.
- `obscura fetch` renders at a fixed 1280x720 and awaits no promise; `serve` plus
  CDP is needed for either.
- Divergence is also expected in service workers, some Web APIs, native media,
  GPU and compositor effects, PDF structure, and font rasterisation.

A handoff that names one tool for every page is therefore sometimes handing over a
job that tool cannot finish, and the failure will look like the page's fault.

## What it should do

Keep Obscura as the default and add a second lane for what it cannot do, using the
latest **browser-use** CLI, so the recommendation names the tool that can actually
complete the task rather than the tool Proctor prefers.

The interesting half is **choosing**, not invoking. A recommendation that says "try
Obscura, and if that doesn't work try the other one" has moved the decision back to
the person. The spec should decide what Proctor can know about the job at hand,
which is roughly: the URL and its scheme, the page's accessibility shape, and the
kind of step being asked for. From that it can name a lane and, importantly, say
which limit drove the choice, so the advice is checkable rather than oracular.

## A conflict to settle before building this, not after

**The operator's own standing instructions currently forbid browser-use.**
`~/.claude/CLAUDE.md` names Playwright, Puppeteer, chrome-headless-shell,
chrome-devtools-mcp, Playwright MCP and browser-use, and says they are removed and
that every browser task goes through Obscura. This brief exists because the
operator asked for browser-use as a second lane, which is their call to make about
their own rule.

The two are not quite the same claim, and the difference is worth stating in the
spec: that instruction governs how an assistant does its own browser work, while
this is about what Proctor recommends to whoever is driving it. But a Proctor that
recommends browser-use to a machine where browser-use has been deliberately removed
is giving advice its own operator will not take. The spec should say which of these
it is:

- a lane Proctor recommends only when it detects browser-use installed, so a
  machine that removed it never sees the advice; or
- a lane Proctor recommends on capability grounds regardless, leaving the operator
  to decline it; or
- a configurable preference, defaulting to Obscura-only, which is the reading most
  consistent with the instruction as written.

## Scope

Recommendation and disclosure, as PRO-0020 established. Proctor does not proxy
steps through either tool: both drive their own engine rather than the window
Proctor is attached to, so a routed step would report success against a window it
never touched. That reasoning is in `docs/specs/spec-PRO-0020.md` and holds equally
for a second lane.

## Not in scope

Making Obscura do these things, or embedding a browser. And nothing here changes
what Proctor drives natively: a web view inside a Mac app is still Proctor's,
because reaching it means attaching to the host process.
