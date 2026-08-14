# PRO-0014: Human-readable step descriptions, derived not supplied

**ID:** PRO-0014
**Status:** Ready for Plan
**Created:** 2026-08-14
**Last updated:** 2026-08-14

## Feature description

# Human-readable step descriptions, derived not supplied

**Status:** untriaged · **Value:** high · **Effort:** low-med · **Source:** design session 2026-08-14

## What it is
A single place in the agent that turns an `ActionStep` into one short line of English — "Pressing **Send invoice**", "About to press **Send invoice**", "Hover refused" — for the run HUD, the audit trail and flow reports to share.

## Why it must be derived
The obvious shortcut is to render `ActionStep.label`, which the tool schema already documents as "Human name for this step, carried into reports". That is the wrong default for three reasons:

1. **It is optional and agents skip it.** In the session that produced this brief, the same agent passed `label` on some steps and omitted it on others within one run.
2. **It is model-authored text rendered in a kill switch.** The HUD is the surface a person uses to decide whether to stop a run. Text the running client controls does not belong there unqualified — the same argument that made session identity derived rather than client-supplied.
3. **Proctor already knows better.** The verb is in `step.kind`; the object is the target node's own `AXTitle`/`AXLabel`, which the agent resolves anyway. Derivation needs nothing from the caller and is correct more often.

## Scope
- In: a `StepDescription` type mapping `kind` → verb (present and prospective forms: "Pressing" / "About to press"), plus the resolved node label as the object, plus a refusal form. One line, no markup.
- In: `label` accepted as an **override**, sanitised — single line, no control characters or markup, truncated to ~48 characters. The HUD's live line is designed never to ellipse, so the cap belongs at the source, not in the UI.
- In: a fallback chain when the node has no label — subrole, then role, then the node id — so the line is never empty.
- Out: localisation. Out: multi-line or rich descriptions.

## Success looks like
Every `ActionStep` kind produces a sensible line with no caller input, verified by a test per kind. A `label` containing newlines, markup or 400 characters comes out as a safe single line within the cap. A step whose node has no accessibility label still produces something a person can act on.

## Dependencies / notes
- Feeds the run HUD, but is independently testable — it is pure logic in the agent with no window involved, so it does not depend on the panel-rendering fix.
- The prospective/present distinction matters: the HUD shows the step it is *about to* perform during travel and the step it *is* performing during actuation, from the same step object.

---

## Triage — 2026-08-14

**Ready for Implementation Plan**

**Sentinel review:** S1 — Approve with assumptions. No customer-facing UI is built here; the risk it carries is that untrusted, caller-supplied text reaches a surface a person uses to stop a run, and the scope already answers that by deriving the wording and sanitising the override.

**UI & logic preview** *(rough sanity check — is this the surface area you expected?)*
- **Where it shows up:** nothing visible on its own. It produces the one-line wording that the run overlay, the activity record and the flow reports will each show for a step, so all three say the same thing about the same action.
- **Behaviour changes:** every step gets a plain-English line whether or not the client named it — "About to press Send invoice" while Proctor is getting ready, "Pressing Send invoice" while it acts, and a refusal line when the action is turned down. A name supplied by the client is still honoured, but cleaned up first and cut to a fixed length so it cannot break the line it lands in.
- **Nothing the caller sends can change the verb**, so a person reading the line always sees what Proctor actually did, described by Proctor.

**Assumptions**
- `[Behaviour]` A supplied name replaces only the *thing being acted on*, never the verb or the timing word — that keeps the "about to" / "doing it now" distinction working and keeps the verb Proctor's own. (Reversing this is a one-line change; flag it now if you meant it to replace the whole line.)
- `[Behaviour]` Every one of the twenty-two action kinds gets its own hand-written wording, in both timings — none of them is rendered by printing the kind's internal name, which would read as "About to setValue" or "Menuing File".
- `[Behaviour]` Cleaning a name means: collapse it to a single line, drop control characters and markup, trim, and hard-cut at 48 characters with no trailing ellipsis — the overlay is designed never to ellipse. A name that cleans down to nothing falls back to the derived wording.
- `[Behaviour]` **That same cleaning runs on every name, not just the caller's** — an app's own accessibility names, menu item names and keystroke text can each be long, multi-line, or carry markup, so the cap and the strip are applied wherever the object comes from.
- `[Behaviour]` The object comes from the element's own readable name first (its title, then its description, then its identifier), then its human-readable kind description, then its sub-kind, then its kind, then its internal identifier. The line is never empty and always points at something.
- `[Data & scope]` The wording is produced from the step **plus the element it resolved to**, not from the step alone — the step carries only an identifier, and the readable name lives on the element.
- `[Data & scope]` Text the caller typed, script bodies, and typed-in values never appear in the line. The activity record deliberately reduces those to a length and a fingerprint, and a description that repeated them would defeat that.
- `[Data & scope]` **Stated boundary, worth a glance:** a name the caller supplies is *not* itself reduced that way — it is display text the caller chose to have shown, and it lands in the activity record as written (cleaned and capped). The guarantee is that the wording never re-derives the fields that get reduced, not that every character on the line has been vetted. If you would rather the supplied name never reach the activity record at all — overlay only — say so and it becomes a one-line rule.
- `[Data & scope]` Steps with no nameable target are described from whatever they do carry: a menu item by its last path component, a keystroke by the key and its modifiers, a run-a-shortcut step by the shortcut's name. Where a step carries nothing nameable — waiting, running a script, a freehand drag — the line is the action alone, with no object, rather than a dangling phrase.
- `[Behaviour]` Waiting reads as waiting *for* the thing, not acting on it.
- `[Behaviour]` The outcome wording is the action named as a thing plus what happened — "Hover refused", and the same shape for a failure, since the activity record already distinguishes the two. It keeps the object where there is one, so a turned-down confirmation does not read as the person's own confirmation being denied. The reason is left to whatever surface shows it.
- `[Experience]` British English, sentence case, no bold or other markup in the produced string — the surfaces decide their own emphasis.
- `[Data & scope]` The wording logic sits with the other pure, independently testable pieces rather than beside the window code, matching how the existing marker and mark-placement logic is kept testable without a window or a grant.

*If any of these are wrong, edit it inline (or correct an assumption) in this file and re-run `/triage PRO-0014` before the planner picks this up.*

**Grounding note:** the step shape (its kind list, its optional caller-supplied name) and the element fields the wording draws on (name, sub-kind, kind, identifier) both exist today, as does the activity record this feeds and its redaction of typed text. The existing element-naming order used elsewhere in the agent is name, then description, then identifier, and this reuses it. This spec is Swift/macOS backend work; the pipeline is running Swift-adapted (gate = `swift build` + `swift test`; web design/e2e stages N/A). Independent of the overlay-panel work, per the brief.

**Out-of-family spec review:** grok `grok-4.6` (xhigh, read-only) ran and returned 16 findings — **10 accepted** (every kind needs hand-written wording; the cleaning must run on derived names too, not only the caller's; the element must be handed in alongside the step; menu object = last path component; a failure form as well as a refusal; the object kept in the outcome line; waiting reads as waiting *for*; the primary name order stated explicitly ahead of the fallbacks; nameless steps degrade to the action alone), **4 rejected** (it read the wording as printing the kind's internal name, which the spec never said; it thought a run-a-shortcut step carries no name, but the actuator already reads one; two findings were about the existing activity record's redaction rules rather than this feature, so they stay out of scope), and **2 recorded as stated boundaries** rather than changes — the caller-supplied name is display text and is not itself reduced, and the 48-character cut is the brief's own decision. Its one Critical was that boundary; it is internal and documented above rather than escalated, since the brief chose the shared line deliberately.
