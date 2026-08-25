---
sources: [REQ-024]
status: retired
validated-by: REQ-024 via CASE-0026, CASE-0087
validated-rungs: effect-witness, outcome
validated-provider: Process() in Sources/ProctorAgent/Actuation/CuaClients.swift — cua-driver and obscura
---
# Route browser work to Obscura instead of driving a browser by hand

## The problem

Proctor is being used to drive web pages: attaching to Chrome or Safari, walking an
accessibility tree that a browser exposes badly, and clicking through a page. It
works, and it is the wrong instrument. A page driven that way gives up everything
a browser tool gives you for free — the DOM, computed styles, the console, the
network log, `document.title`, a selector that survives a re-render — in exchange
for a flattened AX tree and coordinates.

It is also slow, it takes the foreground far more often than native work does, and
it is exactly the case where Proctor's own argument about provenance turns against
it: a click at a point in a browser window proves less than a DOM assertion does.

## What it should do

When the target is a browser, Proctor should reach the page through **Obscura**
(`obscura` on PATH, the operator's chosen browser tool) rather than through
AXUIElement and synthetic events.

The shape is a routing decision, not a new browser. Proctor keeps owning the
window, the app, and everything native around the page; the page itself is
Obscura's.

## What Obscura brings, and its known edges

Obscura is a Rust engine rather than packaged Chrome, and the operator's own notes
record where it diverges. A spec should carry these rather than rediscover them:

- Localhost is blocked unless `--allow-private-network` is passed. A local dev
  server fails as an SSRF block, which reads like a network error.
- CSS animations and transitions never execute, `Emulation.setEmulatedMedia` is
  accepted and inert, and web fonts never load. So no print pass, no
  reduced-motion pass, and font fidelity is unmeasurable rather than perfect.
- An empty computed value means "not implemented", not "not set", for
  `boxShadow`, `backgroundImage`, `textTransform`, `outline` and `flex`.
- Read computed styles through longhand properties. Shorthands such as `padding`
  and `margin` resolve to `0px` even when the layout is correct, which will pass a
  spacing assertion that should fail.
- `obscura fetch` renders at a fixed 1280x720 and does not await a promise; use
  `obscura serve` plus CDP when either matters.

## Worth deciding at triage

- **How much routing.** The honest minimum is that Proctor recognises a browser
  target and says so, naming the better tool, rather than silently driving it. The
  fuller version proxies page-level steps through Obscura and presents them as
  ordinary Proctor steps with a third plane alongside accessibility and synthetic.
- **Where the boundary sits.** A web view inside a native Mac app is still
  Proctor's, because reaching it means attaching to the host process. A page in a
  browser is not. The skill already draws this line for the model; the server does
  not draw it at all.
- **What a routed step's evidence looks like.** If a step travels through Obscura,
  its settle report, its state hash and its audit entry all need an answer, and
  they should not pretend to be an accessibility action.

## Not in scope

Replacing Obscura, embedding a browser, or adding a second browser backend. The
operator's browser tool is chosen and this brief routes to it.
