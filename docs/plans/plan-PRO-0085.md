# Plan — PRO-0085: the skill and the guest lane

**Spec:** `docs/specs/spec-PRO-0085.md` · **Tier:** Small · **Branch:** `ai/pro-0085` off `ai/wave-9`
**Requirements:** REQ-091, REQ-092, REQ-093 · **Cases:** CASE-0370..CASE-0374 · **Defects:** DEF-190..DEF-192

Two repositories, and the split is the whole plan. The documentation lands in
`~/Dev/fledgeling-plugins/plugins/proctor/skills/proctor/`; one test lands here. Nothing else in
either tree is touched.

`~/Dev/fledgeling-plugins` is being worked by another session, which holds uncommitted changes to
`plugins/shipyard/skills/plan/SKILL.md`, `plugins/shipyard/skills/plan/references/plan-tiers.md`,
`plugins/shipyard/skills/triage/references/sentinel-review.md` and `site/lib/catalogue.json`. This
item writes only under `plugins/proctor/` and commits only those paths. If `git status` there shows
the two sets entangled, the work stops and reports rather than committing.

## Slice 1 — `references/tools.md` back in line with the catalogue

Three edits to the existing file, and one new section.

1. **The count and its provenance.** Line 11's "20 tools" becomes 21, stated with
   `Sources/ProctorCore/ToolCatalogue.swift` as where it is read from, so the next reader
   re-measures instead of trusting the number. This is the third time the number has drifted.
2. **The profile table.** The `full` row goes 20 → 21 and gains `guest` in its adds column,
   matching `ToolProfiles.swift:33-38` where `full` is `all.map(\.name)`.
3. **The named-not-specified paragraph.** "Five more exist" against six names becomes the correct
   count, and the paragraph gains the internal-verb boundary: `proctor_queue`, `proctor_hud`,
   `proctor_recent_activity` and `proctor_resource` are Proctor's own window talking to Proctor's
   own agent, the shim gates `tools/call` on the catalogue, and calling one returns `no such tool`.
   The reason is attached so a reader generalises rather than memorising four names.
4. **A `## \`proctor_guest\`` section**, written at the depth the 14 specified tools get: the eight
   actions, the argument table with types and defaults transcribed from the catalogue's
   `inputSchema`, and the `provider` enum carrying `lume`, `prlctl` and `tart`.

Source of every value: `ToolCatalogue.swift`'s `proctor_guest` spec. No argument is written that is
absent from the schema, because the server rejects unknown keys rather than ignoring them.

## Slice 2 — `SKILL.md`: the description, and where the cap lives

1. **The `description` frontmatter** gains the guest lane: macOS guests at the native tier with
   their own Proctor, their own grants and a real accessibility tree; Linux and Windows guests
   delegated, coordinates and screenshots only. The description is routing text, so a lane it omits
   is a lane an agent does not consider.
2. **A `## Host or guest` section** placed where an agent choosing a target will read it, not
   under `## Scale`. It carries the decision in the spec's REQ-092 terms, the native/delegated tier
   split, the sentence that nothing provisions a guest with its reason, and the note that
   provisioning took most of a session and four closed routes.
3. **`## Scale` keeps the cap**, wording and citation intact, reframed as the answer to "how many
   at once" rather than as the file's only word on virtual machines.

Written to `/opus-5-guide`: the reason travels with each rule, triggers stay calm, no verification
scaffolding is added, and counts are written as numbers. Prose through `/agent-voice` at `skill`.

Target: the new section under 40 lines, so `SKILL.md` grows by less than 5% of its 887 lines. Depth
belongs in `tools.md`, which loads conditionally.

## Slice 3 — the test the documentation stands on

One new file, `Tests/ProctorCoreTests/AgentVerbBoundaryTests.swift`, asserting REQ-093.

**Seam:** `ToolCatalogue.spec(named:)` and the `AgentVerbs` constants. Both are pure and public;
the test needs no agent, no socket and no machine state, so it runs in the headless lane.

**Cases.**

| Case | Asserts | Arming |
|---|---|---|
| CASE-0372 | `ToolCatalogue.spec(named:)` is nil for `AgentVerbs.hud`, `.queue` and `.recentActivity` | add `proctor_hud` to `ToolCatalogue.all`; the case must red |
| CASE-0373 | `ToolCatalogue.spec(named: AgentVerbs.doctor)` is non-nil | rename the constant; the case must red |
| CASE-0374 | `ToolCatalogue.all` holds 21 specs and their names are unique | change the count; the case must red |

Each is armed by breaking the thing it claims to watch and observing the red, because a predicate
that cannot fail is the failure this campaign has found eight times. Arming output goes to
`docs/test-campaign/evidence/PRO-0085/`.

The count assertion is written against `ToolCatalogue.all.count` rather than a literal repeated
from the document, so the test moves when the catalogue does and tells the next reader that
`tools.md` needs the same edit.

**What this test does not cover**, recorded rather than implied: nothing here reads the skill file
in the other repository, so `tools.md` drifting again is caught by a person re-running the count,
not by this suite. That limit is stated in the spec and repeated in the test's own header.

## Slice 4 — registries and gates

Rows appended to `docs/test-campaign/inventory.json` (REQ-091..093 under SURF-002 and SURF-013,
DEF-190..192) and `docs/test-campaign/cases.json` (CASE-0370..0374), appended only, never re-sorted.
DEF-190..192 are recorded `open` and then closed by this item's own change, since they are what it
fixes.

Gates, in order: `./scripts/test.sh` with its exit read off the script into a file rather than
through a pipe, then `scripts/campaign/defect_gate.py` in both modes. An absent verdict line is
reported as a failure rather than re-run until it appears — this suite has produced two
unreproduced SIGTRAPs, and DEF-165 records `BrowserLaneWiringTests` reading two live machine probes
into an invariant, which reds the suite on an unchanged tree.

## Ordering

Slice 3 first, so the invariant is proved before the skill asserts it. Then slices 1 and 2 in the
other repository. Then slice 4. The two repositories are committed separately.
