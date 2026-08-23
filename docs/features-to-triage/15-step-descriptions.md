---
sources: [REQ-001]
---
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
