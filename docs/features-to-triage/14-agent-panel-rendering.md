# Agent-drawn panels render nothing on screen

**Status:** untriaged · **Value:** high · **Effort:** unknown (root cause not yet found) · **Source:** measured 2026-08-14 in session

## What it is
`proctor-agent` can create a window in the window server but nothing it draws inside that window reaches the screen. The cursor overlay (`Sources/ProctorAgent/Overlay/CursorOverlay.swift`, uncommitted) is the first thing to hit this, and the run HUD will hit it identically because it is another borderless panel drawn by the same process.

## Evidence
Measured on macOS 26.6, agent pid running from `/Applications/Proctor.app`:

- `CGWindowListCopyWindowInfo` reports the agent owning a window at **layer 1000, `kCGWindowIsOnscreen: 1`, alpha 1**, bounds `(-716, -1440, 2560×2557)` — the correct union of both displays. So the panel exists, is ordered in, and is composited.
- 60 full-screen `screencapture` frames taken across a six-step run: the region the pointer was travelling through is **byte-identical in all 60**. A single shot inside the 2.5s linger window also shows nothing.
- Both measurements were repeated after adding `CATransaction.flush()` at all six layer-mutation sites, rebuilt and reinstalled. **No change.**

## Ruled out
Coordinate maths (`layerPoint` verified against `NSScreen.screens[0]` = the 1728×1117 primary; the target maps where it should), the glyph path (`arrowPath()` returns a valid non-degenerate path), the `PROCTOR_CURSOR` enable gate (unset = enabled), the call site (`SessionAct.swift:70`, reached for every non-refused step), target resolution (`PointerMarker.targetPoint` is kind-agnostic and resolves for a step with a framed node), and the missing explicit transaction commit.

## Still to check
- Whether the layer-hosted `NSView` survives assignment to `panel.contentView` — i.e. whether the layer tree is still attached at draw time.
- Whether `.accessory` activation policy without an `NSApplication` event loop (`main.swift` runs a bare `CFRunLoopRun()` at line 95) can back a window at all, or whether AppleWindow display/flush machinery is required for a layer-backed panel to present.
- Whether the panel needs a non-zero `contentView.layer.contentsScale` / an explicit `displayIfNeeded`.

## Success looks like
A step with a resolvable target draws the pointer at that target, and a full-screen capture taken during the step differs from one taken before it, in the region around the target. That difference is the test — not "the panel exists".

## Scope
- In: whatever makes agent-drawn panels present. If that means running an AppKit event loop instead of `CFRunLoopRun()`, the AX-observer behaviour documented at `main.swift:8-12` must be re-verified, not assumed.
- Out: redesigning the cursor overlay's appearance or motion; that part is written and reviewed.

## Dependencies / notes
- **Blocks the run HUD.** The HUD is the same shape of panel from the same process; there is no point building it until a panel from this process can draw.
- `Sources/ProctorAgent/Overlay/CursorOverlay.swift` and `Sources/ProctorAgent/Session/SessionCursor.swift` are currently uncommitted working-tree files.
