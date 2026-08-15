# Does Proctor need to exist? A review against Cua Driver

**Date:** 2026-08-15 · **Verdict:** Partly. The driver half should be replaced by
`cua-driver`. The testing half is real, is not what Cua is building, and is worth
keeping — but only if it is rebuilt on top of Cua rather than beside it.

Sources read in full: `cua.ai/llms.txt`, `/cua-driver`, the driver install guide,
`concepts/the-no-foreground-contract`, `docs/llms.txt`, `reference/cua-driver/mcp-tools`,
`reference/cua-driver/limits`.

---

## 1. The overlap is not partial, and it is not accidental

Cua Driver is MIT-licensed, open source, YC-backed, on version 0.13 with a nightly
channel, and is in production behind Hermes, Clicky, H Company and Factory Droid.
Its macOS design is the design this repo arrived at independently, decision for
decision:

| Proctor | Cua Driver |
|---|---|
| Two planes: accessibility first, synthetic events as the exception | "Best-effort background": AX actions first, routed CoreGraphics/SkyLight input, explicit `delivery_mode: "foreground"` escalation |
| Window-scoped ScreenCaptureKit capture without raising | Same, named as such |
| Drawn pointer overlay; the real cursor never moves | "The agent cursor" — an overlay, with `set_agent_cursor_theme` and dotLottie themes |
| `proctor_doctor` | `cua-driver doctor`, `health_report`, `check_permissions` |
| Developer ID signing so TCC grants survive upgrades | `com.trycua.driver` signing identity, documented with the same reasoning |
| Installer to `/Applications` + a CLI symlink | Same, plus PATH repair and no sudo |
| Agent daemon + MCP shim from one bundle | One binary as `mcp`, `serve`, or `call` |
| `proctor_menu`, `proctor_zoom`, `proctor_kill`, `proctor_snapshot`/`find` | `invoke_menu`, `zoom`, `kill_app`, `get_accessibility_tree`/`get_window_state` |
| Attribute writes that avoid opening a popup menu | `set_value`, with the identical AXPopUpButton trick spelled out |
| Policy gate over what a caller may do | Permission modes, plus YAML **and Rego** policy files and capability manifests |

Their documented limits are our limits, found the same way: off-Space SwiftUI
windows strip their AX tree, canvas apps need brief frontmost activation,
minimized windows silently drop keyboard commits.

**Nineteen Proctor tools against roughly fifty Cua tools.** Cua additionally has
Windows and Linux, Lume (local Apple Silicon macOS VMs), cloud sandboxes,
Cua-Bench, trajectory recording to MP4, autostart, update channels, telemetry
controls, and an app-hosted daemon mode for reusing a host app's permission
identity.

Where Cua is not merely equal but ahead of a decision this repo made
deliberately: **browser work.** PRO-0020 and PRO-0024 concluded Proctor should
*recommend* a browser tool and never proxy, because Obscura and browser-use drive
their own engine rather than the window Proctor is attached to. Cua solved the
problem instead of routing around it: it binds an exact native window to its tab
and adds a **CDP full-background rung**, so `browser_click`, `browser_type` and
`browser_navigate` drive the real window the user is looking at. That is the
thing PRO-0020 said was impossible for us, and it is shipped.

## 2. What genuinely is not there

I looked for this specifically, and it is narrower than the backlog assumes, but
it is real.

**Determinism scoring has no counterpart.** `proctor_stability` runs a flow N
times and returns `firstDivergence` plus per-step instability. Cua has
`replay_trajectory`, and its own docs describe the intended use as "recording a
replay against a new build and diffing the two trajectories". That is a diff, not
a score, and it carries an admission that matters: **element-indexed actions fail
on replay, because element indices are per-snapshot and do not survive a
session.** Proctor's flows record the selector each step resolved through, which
is exactly the fix for that. Cua's replay is a demo-and-regression tool; Proctor's
is a measurement.

**The accessibility audit has no counterpart.** `verify_state` evaluates one to
eight bounded predicates about window and AX state, conservatively, with
`unknown` never implying success. It is a good primitive and it is deliberately
minimal. It does not do contrast ratios, minimum hit-target sizes, focus order
against reading order, or the tri-observer `agree` check where the AX tree, the
geometry and the pixels are compared *against each other* and the disagreement is
the finding. That last one is Proctor's best original idea and I found nothing
like it anywhere in Cua's surface.

**The Apple Events plane has no counterpart.** `proctor_dictionary` and the
scripting-dictionary route are a third actuation plane Cua does not have.

**ProctorReflector has a near-counterpart, but not the same one.** Cua's embedded
app-hosted daemon exists to reuse a host app's *permissions*. The reflector exists
to read resolved colours, fonts, corner radii, constraints, and both layer-model
and presentation values from inside an app you own — measurement rather than
access. For fidelity testing that difference is the whole point.

**Live human supervision is different in kind, not merely absent.** Cua's answer
to "what may the agent do" is pre-authorization: modes, YAML/Rego policy,
manifests. Proctor's answer is a run HUD with Pause and Stop on screen, a run that
yields when a person takes the machine back, a multi-session queue, and a sealed
audit trail. Cua's is stronger for unattended fleets; Proctor's is about the
person sitting at the machine while it happens. I would not claim this as a moat,
but it is not the same product.

## 3. Recommendation

**Adopt `cua-driver` for actuation, and stop building a second one.** Everything
in Proctor that clicks, types, scrolls, captures, targets a window, finds an
element, checks a grant, draws a cursor, or routes browser work is now a worse,
macOS-only, single-maintainer version of something MIT-licensed and better
resourced. Continuing to maintain that half is the expensive mistake, and the
overlap will only widen.

**Keep the testing harness, rebuilt as a layer on top of Cua.** The defensible
product is not "give a model hands on a Mac" — that question is answered. It is
**"prove this Mac app is correct"**: determinism scoring with selectors that
survive a replay, the accessibility audit rubric, the tri-observer disagreement
check, the fidelity ledger, and the reflector for apps you own. Cua-Bench scores
*agents*; nothing in their stack scores *an app under test*. That is a real gap
and it is where this repo's genuinely novel work sits.

**Expect to delete a lot.** On a first pass, the capture engine, the actuation
planes, window targeting, the cursor overlay, the browser lane, the doctor, the
installer and the permission plumbing are all replaceable. That is most of
PRO-0001 through PRO-0010 and most of wave 6.

**One thing to verify before committing**, because it decides whether the layer is
even buildable: whether Cua's MCP surface exposes enough raw AX geometry and
per-window pixels for the audit assertions and the tri-observer check to be
computed on top of it. `get_accessibility_tree` and window screenshots suggest
yes; it should be proven with a spike rather than assumed.

## 4. What this means for work in flight

Wave 6 is now mostly building on ground that is proposed for demolition.

- **Stop before starting:** PRO-0029 (settings for the `PROCTOR_*` switches),
  PRO-0031 (doctor completeness + `doctor.sh`), PRO-0034 (scroll delta units),
  PRO-0036 (status window checks), PRO-0040 (`open -a` cannot launch Proctor),
  PRO-0041 (doctor hangs on the Screen Recording probe). Every one of these is in
  the layer `cua-driver` replaces. PRO-0040 and PRO-0041 are live bugs, but they
  are bugs in code that should not survive the decision.
- **Already merged and still worth having:** PRO-0042 (the alignment assertion is
  audit-layer work), and the reasoning captured in PRO-0033 and PRO-0035's specs.
- **In flight, worth letting finish:** PRO-0032 (audit signing) and PRO-0037 (hold
  attribution) both sit in the supervision layer, which survives longest under any
  reading.
- **Re-scope rather than cancel:** PRO-0038 (stability disclosing page churn) and
  PRO-0039 (page-scoped refusal) are about the testing layer's honesty and keep
  their point on a Cua substrate.

## 5. The uncomfortable part

The deep research that scoped this project missed a funded, shipped, MIT-licensed
competitor whose macOS driver is a near-superset of the core. That is worth a
post-mortem of its own: the research surface was pointed at the *problem* rather
than at *who has already solved it*, and a single search for "computer use agent
macOS background input" would have found `trycua/cua`. Whatever the next project
is, a competitor sweep belongs before the first spec, not after twenty-eight
merged features.
