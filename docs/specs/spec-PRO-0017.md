# PRO-0017: HUD character sprite assets

**ID:** PRO-0017
**Status:** Ready for Plan
**Created:** 2026-08-14
**Last updated:** 2026-08-14

## Feature description

# HUD character — sprite assets and state binding

**Status:** untriaged · **Value:** med · **Effort:** med · **Source:** design session 2026-08-14 · **Spec:** `docs/design/run-hud-character.md`

## What it is
The run HUD's companion character: a compact-Mac pixel sprite that changes with run state, sitting in a 38pt inset bay at the left of the live line.

Chosen after four concepts were generated and looked at (`design/character/concept-*.jpg`). A glass-gel orb, a Luxo-style desk lamp and an illustrated owl were rejected — the orb had no personality, the lamp's arms and joints vanished below about 60pt, and the owl read as sticker art on a native panel. The sprite won on the test the others failed: pixel art is the only one of the four that gains legibility as it shrinks, and all seven states were verified distinguishable at 38px.

## The rule that governs it
The **screen is the expression**. Arms and lean are secondary and are expected to disappear at small sizes — that is by design, and it means any new state must be readable from its screen glyph alone.

Seven states: idle (dot eyes), travelling (leaning, speed lines), acting (filled vermilion screen, arm pressing), blocked (bold `!`), paused (grey pause bars — the only grey screen, so it is distinguishable without colour), finished (checkmark, sparkles), error (`X`, tilted, smoke).

## What exists and what is owed
Existing: `design/character/sprite-states-sheet-42b853.png` (all seven in one render) and `design/character/states/*.png` (sliced, wired into the mock).

Owed before shipping:

1. **Real alpha.** Every render carries a charcoal background. The mock seats the character in a dark inset bay, which hides this *and* keeps the white body legible on the light panel — so the bay stays regardless — but the shipping assets need cutting out.
2. **Even footprints.** The slices are hand-estimated and the character drifts slightly between cells. Re-crop to a common baseline so it does not jump as state changes.
3. **Animation frames.** Idle, travelling and acting want 4–6 frame loops rather than the CSS transform stand-ins in the mock.
4. **@2x and @3x.**

## Success looks like
The character changes with run state in the built HUD, holds a stable footprint across all seven states, is legible in both appearances, and animates without the agent process drawing frames — commit the loop to the render server, as the cursor overlay's own commentary argues.

## Scope
- In: asset production, the state→asset binding, the frame loops, the bay.
- Out: the character's design. It is settled; re-opening it is a separate decision.

## Dependencies / notes
- Depends on the run HUD panel.
- Regeneration guidance is in `docs/design/run-hud-character.md`. Two facts worth keeping: `style: "openai"` is the model that honours exclusions, and asking for a **transparent** background is what summons a painted checkerboard — ask for flat charcoal instead. Regenerate the whole sheet, never one cell, or the character drifts.

---

<!-- Triage, plan link, and progress sections are appended below. -->

## Triage — 2026-08-14

**Ready for Implementation Plan**

**Sentinel review:** S1 — Approve with assumptions. The character carries tone, never anything the words on the panel do not already say, so nothing here can mislead a person about what Proctor is doing. The one thing worth holding it to is that a picture moving continuously must not cost Proctor its ability to notice an app has settled, and must never turn up in a capture.

**UI & logic preview** *(rough sanity check — is this the surface area you expected?)*
- **Where it shows up:** the run panel's left bay *(customer-facing — an existing surface that gains its picture)*. Nothing else in Proctor changes, and nothing new can be done from it.
- **What users will see — the run panel:** the bay that ships empty now holds a small compact-Mac character whose screen changes with the run — calm while idle, leaning while getting ready, pressing while acting, a warning while blocked, grey while paused, a tick when it finishes, a cross when it fails — and it moves gently in the first three of those.
- **Behaviour changes:** the panel's state becomes readable at a glance as well as in words. No new control, no new decision.
- **Design reference:** the run panel mock and `docs/design/run-hud-character.md` are settled and binding — the seven states, the bay, the palette and the rule that each state must be readable from its screen alone. `design/character/sprite-states-sheet-42b853.png` is the source art. Do not re-open the character's design.

**Assumptions**
- `[Layout]` The dark inset bay stays in both appearances. *(keeps the white body legible; already settled.)*
- `[Layout]` One set of pictures serves light and dark, not two. *(the bay is dark either way.)*
- `[Layout]` Every state is drawn to one common footprint inside the bay. *(so it never jumps as the state changes.)*
- `[Layout]` Exactly the seven states already drawn; none added, none dropped. *(the design is closed.)*
- `[Experience]` Idle, travelling and acting move; blocked, paused, finished and error hold still. *(the brief names those three.)*
- `[Experience]` Movement is drawn frames — four to six per moving state — not the still picture being slid about. *(the brief asks for frames precisely to replace the sliding the mock stands in with.)*
- `[Experience]` Idle's movement is the slow one-pixel bob the design record sets, carried as frames like the rest. *(the record decides the motion; frames are only how it is drawn.)*
- `[Experience]` One regenerated sheet holds every frame of every state, including a single frame for the four that hold still. *(piecemeal generation drifts the character, and pairing today's stills with new frames is piecemeal.)*
- `[Experience]` If one sheet cannot hold the character steady across every frame, the moving states fall back to sliding the still picture a whole pixel at a time, and that is written down. *(a drifting character is worse than a simpler loop; the fallback should be visible, not silent.)*
- `[Experience]` A state change cuts straight to the new picture, with no fade between. *(hard-edged pixel art; a blend goes soft.)*
- `[Experience]` With motion reduced, the movement stops and each state stays readable from its screen alone. *(the design rule already demands that.)*
- `[Data & scope]` The pictures ship inside Proctor; nothing is fetched while a run is going. *(an agent holding these permissions should not reach the network to draw itself.)*
- `[Data & scope]` Standard and double density ship; the triple density the brief asks for is produced but not expected to be used. *(macOS never asks for more than double.)*
- `[Operations]` Transparency is cut from that one sheet by removing its flat charcoal, and is never asked for while drawing it. *(hard edges cut cleanly, and naming transparency to the model is what painted a fake checkerboard last time.)*
- `[Operations]` The movement is handed over once when the state changes and plays without Proctor drawing frames. *(the drawn pointer already works this way, for the same reason.)*
- `[Operations]` A picture that is missing or will not open leaves the bay empty and the run carries on. *(matches the panel's own rule that a drawing failure never stops a run.)*
- `[Operations]` The character never appears in a capture and never moves a comparison or a settle decision. *(same property the drawn pointer already holds.)*

*If any of these are wrong, edit it inline (or correct an assumption) in this file and re-run `/triage PRO-0017` before the planner picks this up.*

**Grounding note:** this is Swift/macOS work; the gate is `swift build` + `swift test` (no web or end-to-end stage applies). The panel that owns the bay is PRO-0015, which is triaged, scheduled ahead of this item in the same backlog, and explicitly ships the bay empty for this item to fill — an internal dependency, not an open question. The mechanism this needs already exists in the drawn pointer: that overlay hands every animation to the system in one pass and states in its own commentary that this is what lets it play at full rate while the agent is busy settling and walking trees, because the agent runs no application event loop of its own. The same commentary carries the one-panel-per-screen measurement the panel must honour. The app bundle already has a place for shipped artwork — the icon is copied there at build time — so adding pictures is an extension of an existing build step rather than a new mechanism, and both the build script and the shim's own installer need to stay in step, as this project's conventions require. Capture is scoped to the window under test and the panel belongs to Proctor's own process, so a continuously moving character cannot dirty the frames the settle logic reads; that is a property to preserve rather than one to build.

**Out-of-family spec review:** grok `grok-4.6` (xhigh, read-only) ran and returned 2 findings, **both accepted**. Its High was a real contradiction: the block said transparency would be cut from today's renders *and* that every frame would come from one regenerated sheet, which cannot both hold — today's renders are seven stills and contain no loops, and pairing them with a new frame sheet is exactly the piecemeal generation this project measured as drifting the character. The assumptions now name one regenerated sheet carrying every frame of every state, including a single frame for the four that hold still, with transparency cut from that one sheet. Its smaller clash — that forbidding any sliding of the picture contradicted the design record's own one-pixel idle bob — is fixed by naming the bob as the record's motion and frames as merely how it is drawn. Its second finding agreed there is no external dependency here. The first invocation hit the 240-second deadline mid-reasoning and returned narration only, which is a lane failure, not a pass; the retry, scoped to two files and a word limit, completed. Lane ran, no downgrade.

**Assumptions review:** an independent pass over the block (would this default surprise the owner, reverse a locked decision, or hide an external question) failed one and passed the rest. The failure was the animation default, which had picked the whole-picture sliding that the brief and the design record both name as the stand-in to be replaced; it now defaults to drawn frames, with sliding demoted to a written-down fallback for the case where one sheet cannot hold the character steady.


