# PRO-0088 on glass — what window 121491 is, and what the capture path says now

Signed Developer ID build (`PROCTOR_SIGN_IDENTITY='Developer ID Application: Luke Rhodes
(H4HGFL52W7)' bash scripts/build-app.sh`), run from `.build/Proctor.app` on a private socket
(`PROCTOR_SOCKET=/tmp/pro0088/agent.sock`). `/Applications/Proctor.app` was never replaced, and its
own agent — pid 52976 — appears in every sample below as an untouched bystander.

## DEF-028: window 121491 identified by intervention, not by resemblance

DEF-028 recorded three windows on agent pid 86732: the HUD at layer 25 and the takeover statement
at layer 24 both at `sharingState 0`, and **window 121491 at layer 0, 1710x1073, at
`sharingState 1`**. What it was, was not established.

Two agent builds were run that differ in **one file** — `CursorOverlay.swift`, the drawn pointer.
Everything else, including the capture change, is identical. `CGWindowListCopyWindowInfo` was
sampled every ~330ms from a separate probe process (`witness_probe windows`), so the process being
measured is not the process measuring. Populations are `len()` over the rows filtered by owning
pid; `overlay-population.json` holds every row.

| Build | Agent pid | Windows owned | Not excluded | Layer 25 | Layer 24 | Layer 0 |
|---|---|---|---|---|---|---|
| `CursorOverlay.swift` at `4d76b3c` | 53748 | 3 | **1** | 0 | 0 | **1** |
| As delivered | 12838 | 3 | **0** | 0 | 0 | **0** |

60 samples before, 54 after. The one-file revert flips exactly the layer-0 window and nothing else,
so **window 121491 is the drawn-pointer overlay panel**, sitting in the normal band
(`CursorOverlay.inPlaneLevel`, `.normal`) after an in-plane placement. It is not a window the case
did not know about; it is the third overlay, and it had lost its exclusion. Assigning
`NSWindow.level` resets `sharingType`, and this is the only overlay that changes band at runtime.

`SCShareableContent` names the owner of all three as `app.fledgeling.procter.agent`
(`/tmp/pro0088/sck_owner` output, reproduced in `overlay-population.json` as `ownerName`), which is
also why the ownership test carries two identifiers rather than one.

## DEF-025: the capture verdict, both legs

Same agent, same session, one call apart. `capture-proctor-owned.json` and
`capture-calculator.json` are the raw MCP replies.

| Target | `status` | `trustworthy` | `contentVerdict` | `content` |
|---|---|---|---|---|
| `win:2:1` — CG 147541, the agent's own overlay | `complete` | **false** | `excludedTarget` | 7,720,704 sampled, `maxAlpha 0`, `allTransparent true`, 1 colour |
| Calculator's window | `complete` | **true** | `content` | 1,099,968 sampled, `maxAlpha 255`, 256 colours (capped) |

The caveat on the first reads: *"Window win:2:1 belongs to Proctor, and Proctor excludes its own
windows from its own captures so the run HUD and the takeover statement never appear in a shot. The
frame arrived, and it is empty because nothing was going to be in it."*

Before this change the first row read `status: complete, trustworthy: true` with nothing to
distinguish it from the second — that is DEF-025, and `dirtyRectCount 1` next to `dirtyArea 0` was
the only hint.

**The second row is the sabotage.** A real frame still passes, so the gate is not simply refusing
everything: the same code path, one call later, returns `trustworthy: true` over a window with
something in it.

## What this does not establish

The agent's overlays were measured; the Proctor UI's own windows were not captured, because AX
exposed no window for either UI process during the run and this harness has no route to click a
menu item on a window it cannot address. `excludedTarget` was therefore proved against an
agent-owned window rather than against the History window DEF-025 originally captured. The
mechanism is the same one — `sharingType = .none` — and the ownership test covers both identifiers,
but the History window itself is untested here.
