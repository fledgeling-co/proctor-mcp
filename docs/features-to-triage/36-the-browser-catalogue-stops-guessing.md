---
sources: [REQ-024]
status: retired
validated-by: REQ-024 via CASE-0026, CASE-0087
validated-rungs: effect-witness, outcome
validated-provider: Process() in Sources/ProctorAgent/Actuation/CuaClients.swift — cua-driver and obscura
---
# The browser catalogue stops guessing, and the handoff is machine-readable

## The problem

PRO-0024 logged three related weaknesses in how Proctor decides what a browser is
and how it tells a model what it decided.

- **A PWA or "open as app" window is treated as Chrome.** A bundle id like
  `com.google.Chrome.app.<hash>` inherits Chrome's catalogue row through the
  prefix rule. Inherited from PRO-0020 rather than introduced by PRO-0024, and
  wrong in a way that matters: a PWA window is an application window whose whole
  content is one page, and handing it off as a browser tab is not obviously
  right or obviously wrong.
- **`chromiumFamily` is a second fact per browser that can drift.** A browser can
  change engine; Opera and Edge both have. A wrong answer costs one lane
  recommendation for an internal page, which at least fails visibly.
- **`why` names the rule, not the risk, and nothing on the handoff object is
  machine-readable.** A host that wanted to gate on "this lane is unaudited" or
  "this lane needs a live profile" has to read prose written for a person.

## What it should do

Decide what a PWA window is, stop carrying a fact that can drift where it can be
derived or checked, and give the handoff object a small machine-readable flag set
beside the prose.

## The hard parts, named

- **The PWA question is a product decision, not a lookup.** Three readings, and
  the spec should pick one: it is a browser window and routes like any page; it
  is an application window and Proctor drives it natively; or it is ambiguous and
  the handoff says so and lets the caller choose. Each has a cost, and the third
  is not automatically the honest one, because an object that refuses to decide
  moves the decision to a model that knows less.
- **The flag set is a wire contract** and every flag is something a host will
  gate on. Keep it small, name each flag for the risk rather than the rule, and
  say what a host may conclude from each. A flag that means several things is
  worse than prose.
- **Do not re-litigate the routing rule.** PRO-0024 settled that routing is on
  the URL's scheme alone, with a deny list, after rejecting AX shape and step
  kind with reasons that still hold. This item improves what is reported and how
  a browser is identified; it does not reopen how a lane is chosen.
