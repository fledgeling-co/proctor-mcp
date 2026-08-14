# PRO-0015: Run HUD panel

**ID:** PRO-0015
**Status:** Ready for Plan
**Created:** 2026-08-14
**Last updated:** 2026-08-14

## Feature description

# Run HUD — the overlay shown while Proctor drives an app

**Status:** untriaged · **Value:** high · **Effort:** high · **Source:** design session 2026-08-14

## What it is
A floating panel the agent shows while a run is in flight, so a person watching can see what Proctor is doing and stop it. Design is settled and rendered: **`mocks/run-hud.html`** is the reference (open it over HTTP, not `file://`).

## The design, in short
One direction survived review — the Ledger, a 352pt panel docked bottom-right:

- **A single live line at one type size.** The verb carries the state ("Pressing", "About to press", "Paused before", "never settled"), so there is no second line and no status label. Nothing truncates; copy is written short at the source.
- **A step counter** (`3/7`), tabular and fixed-width, so a value change never moves its neighbour. Every numeric slot in the panel follows this rule.
- **A progress rail** along the panel's own bottom edge, filled in the live colour.
- **A three-row trail** of recent steps with their settle times.
- **Run controls:** Pause and Stop.
- **One state variable** (`--live` in the mock) drives the character, the rail and the emphasised words together, so the panel changes colour as one object: vermilion running, amber blocked, red error, green finished, grey paused/idle.

Two rules that came out of review and are load-bearing:

- **Neutral ground, not the app palette.** The onboarding mock's warm porcelain reads as brown mud when it floats over someone else's app. The HUD is neutral graphite / neutral white with vermilion as the only colour on it.
- **Surface the exception, not the rule.** Accessibility is the normal plane and is never announced. A synthetic step says so in words, once: "Synthetic event — Acme Console must stay in front".

## Behaviour
- Click-through everywhere except its controls.
- Draggable by the grip.
- Honours `prefers-reduced-transparency` (solid background) and `prefers-reduced-motion`.
- Appears when a run starts, lingers briefly after it ends, and can be turned off entirely — the same off-switch shape as `PROCTOR_CURSOR`, because an unattended suite on a machine someone else is using should be able to leave the screen alone.

## Success looks like
A run driven from an MCP client shows the panel over the driven app; the live line and counter track the steps; Pause holds before the next step without killing the one in flight; Stop ends the run and the owning session's call returns a refusal naming that a person stopped it.

## Scope
- In: the panel, its states, the run controls, the off-switch.
- Out: the queue (separate brief), the character art (separate brief) — build the character's 38pt bay as an empty inset and leave it empty.

## Dependencies / notes
- **Blocked by the agent-panel-rendering fix.** This is the same shape of panel from the same process whose panel currently draws nothing.
- Needs the derived step descriptions to fill its live line.
- Light and dark are authored independently in the mock; both are in the reference.

---

<!-- Triage, plan link, and progress sections are appended below. -->

## Triage — 2026-08-14

**Ready for Implementation Plan**

**Sentinel review:** S2 — Approve with assumptions. This is the surface a person uses to watch and halt an agent driving their own Mac, so the risk it carries is a stop control that looks like it worked and did not. The scope answers that by making Stop end the run and the asking client's answer say a person stopped it, rather than letting the run finish quietly.

**UI & logic preview** *(rough sanity check — is this the surface area you expected?)*
- **Where it shows up:** a new floating panel over whatever app Proctor is driving *(customer-facing — new surface)*. Nothing in the Proctor window, the menu bar or the existing onboarding changes. The drawn pointer already on screen is untouched.
- **What users will see — the panel:** one live line naming what Proctor is doing right now, a step counter, a progress rail along the panel's bottom edge, a three-row trail of recent steps with how long each took, a run clock, Pause and Stop, a drag grip, a one-line warning on the steps that need the driven app in front, and an empty inset bay on the left where the character will later sit.
- **Behaviour changes:** a run that used to be invisible now announces itself and can be halted by hand. Pause holds before the next step and lets the one in flight finish; Stop ends the run and the client that asked for it gets a refusal saying a person stopped it. The whole panel can be switched off for an unattended machine.
- **Design reference:** `mocks/run-hud.html` is settled and binding — layout, states, colour, copy and both light and dark. Do not re-open it.

**Assumptions**
- `[Layout]` One panel, docked bottom-right of the screen holding the driven window. *(the mock's Ledger direction, at its 352pt width.)*
- `[Layout]` The queue bar in the mock is not built here; it arrives with the queue feature. *(brief scopes the queue out.)*
- `[Layout]` The character bay is an empty inset at the mock's size. *(brief: art is a separate item.)*
- `[Layout]` The panel follows the system's light or dark setting, and re-reads it when it changes. *(both appearances are authored in the mock.)*
- `[Experience]` The seven states are the mock's: idle, travelling, acting, blocked, paused, finished, error. *(no state exists that the reference does not draw.)*
- `[Experience]` Every word on the live line and in the trail comes from the derived step wording already specified. *(one description shared by the panel, the trail and the records.)*
- `[Experience]` The counter and the rail count the steps of the batch in flight, whose total is known before it starts. A repeated sweep shows each of its passes in turn rather than one total across all of them. *(a batch is handed over whole; a sweep is several batches.)*
- `[Experience]` State follows the run: getting ready to act reads as travelling, acting as acting, a refused step as blocked, a step that errors or never settles as error, the end of the run as finished. *(the mock's own colours, one per outcome.)*
- `[Experience]` A person's own stop is not drawn as a fault — the panel ends in the quiet grey with a line saying a person stopped it. *(red is for something going wrong; this went right.)*
- `[Experience]` The panel does not show the mock's idle state in this build. It appears when a run starts and goes after one ends, so there is no between-runs moment to show. *(idle becomes real when the panel stays up between runs, with the queue.)*
- `[Experience]` The trail holds the three most recent finished steps, newest at the bottom, with the time each took to settle. *(three rows in the reference.)*
- `[Experience]` Pause takes effect before the next step; the step in flight runs to completion. Resume continues from there. *(brief; killing a step mid-flight leaves the app in an unknown state.)*
- `[Experience]` A pause holds until somebody resumes it, with a long backstop — fifteen minutes, adjustable by the same kind of setting as the off-switch — after which it gives up the same way a stop does. *(a paused run is still holding Proctor's attention, so an unbounded hold leaves every other request queued behind it; the backstop is long enough that a person who walked off to check something comes back to a live pause.)*
- `[Experience]` Stop ends the run after the step in flight; the steps already done are still reported, alongside the refusal. *(the caller needs to know how far it got.)*
- `[Experience]` A stopped or given-up run is reported the way a step refused mid-run already is: the finished steps, plus the refusal attached to the first step that never ran. If no step remains, the run simply completes and Stop does nothing. *(reusing the existing shape keeps the partial results; a wholesale rejection would throw them away.)*
- `[Experience]` Pause and Stop act on the run the panel is showing. *(one run at a time until the queue feature lands.)*
- `[Experience]` The panel appears when a run starts and fades about three seconds after a run that finished or was stopped. A run that ended blocked or in error holds for fifteen seconds instead. *(the endings a person actually needs to read are the ones a three-second fade would take away from an unattended machine.)*
- `[Experience]` Dragging by the grip moves it; the position is remembered until Proctor restarts and is not saved. *(a panel that stays where it was moved for the session, without leaving a settings file behind.)*
- `[Experience]` Everything but the grip, Pause and Stop passes clicks through to the app underneath. *(brief.)*
- `[Experience]` Reduced transparency gives it a solid background; reduced motion removes the animation and leaves every state readable from text and colour alone. *(brief; both settings are honoured elsewhere in Proctor.)*
- `[Data & scope]` The off-switch is `PROCTOR_HUD`, the pointer's shape exactly — off on `0`, `off`, `false`, `no` — and separate from `PROCTOR_CURSOR`, so either can be left on alone. *(brief names the shape; someone may want one and not the other.)*
- `[Data & scope]` The panel shows what a step acts on, never text typed into the app or the body of a script. *(the shared wording already withholds those.)*
- `[Operations]` Every kind of run shows it — a single batch, a replayed flow, a repeated stability sweep. *(all three already run steps the same way; showing the panel for one and not the others would make a stop control that is sometimes absent.)*
- `[Operations]` A person stopping or pausing a run is recorded alongside the step it interrupted, the same as any other refusal. *(a halt is an event worth accounting for, and this is a security-relevant control.)*
- `[Operations]` The panel is never in a capture and never moves a state hash or a pixel comparison, the same property the drawn pointer already has. *(evidence must not change because somebody was watching.)*
- `[Operations]` If the panel cannot be drawn, the run still proceeds, and Proctor's own health report says the panel is unavailable. *(refusing to drive because an annotation failed would be worse; a silent absence would leave a person believing they have a stop button they do not have.)*
- `[Operations]` The controls have to actually take a click. Proctor's background process draws today but has never received one, so this needs a way in for mouse input that reaches only the grip, Pause and Stop — and it must not cost Proctor its ability to notice an app settling, which is where a regression would show. *(the drawing process deliberately runs no application event loop; the settling behaviour depends on that.)*

*If any of these are wrong, edit it inline (or correct an assumption) in this file and re-run `/triage PRO-0015` before the planner picks this up.*

**Assumptions review:** an independent in-family pass over the Assumptions block (would this default surprise the owner, reverse a locked decision, or hide an external question) failed two of them and passed the rest. Both were fixed rather than escalated: the pause give-up became a long adjustable backstop instead of a five-minute one, with the reason a cap exists at all written down; and the linger split, so a run that ended blocked or in error holds long enough to be read on an unattended machine.

**Grounding note:** the panel's blocker is cleared — the one-panel-per-screen finding that fixed the agent's existing overlay is recorded in that overlay's own header, with the measurement, and this panel must follow it. Proctor already draws from this process, already switches that drawing off through one setting, and already runs every kind of run — a batch, the simplified façade, a replayed flow and a stability sweep — through one shared step loop, which is where the panel's state, the pause check and the stop check belong so all of them behave the same. The one new thing is input: the panel's buttons are the first thing this process has ever had to receive a click on, and it deliberately runs no application event loop. The refusal a stop produces has no existing code that fits — the nearest is the policy gate's, which would misreport a person's decision as a configured rule — so this adds one. This spec is Swift/macOS work; the gate is `swift build` + `swift test` (web design and end-to-end stages are not applicable here), and the panel's own behaviour is testable without a window wherever the state, the wording and the pause/stop decisions are kept separate from the drawing, matching how the existing pointer and marker logic is kept testable.

**Out-of-family spec review:** grok `grok-4.6` (xhigh, read-only) ran and returned 9 findings — **7 accepted** (the reported shape of a stop, so the finished steps survive and the refusal lands on the first step that never ran; a named five-minute give-up for a pause nobody resumes; an event-to-state mapping including where a person's own stop lands; the counter tracking one batch rather than a whole sweep; a named linger; the off-switch named; the panel's absence surfaced in the health report), **1 sharpened rather than added** (its Critical — that a click has no way in on a process with no application event loop — was already the last assumption and is now stated as a requirement with the settling behaviour named as the regression to watch), and **1 rejected** (it read the derived step wording as an external dependency; it is PRO-0014, triaged and scheduled ahead of this item in the same backlog). It verified three grounding claims as true and could not confirm a fourth from its read set — that replay and stability share the step loop — which was checked here directly and holds. The first invocation hit the 240-second deadline mid-reasoning; the retry, scoped to four files, completed. Lane ran, no downgrade.
