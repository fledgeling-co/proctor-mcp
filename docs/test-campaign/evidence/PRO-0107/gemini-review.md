This review evaluates **PRO-0107: Thirty-five pictures the gate cannot see** (DEF-209, DEF-218..DEF-223) in [`proctor-mcp`](file:///Users/lukerhodes/Dev/proctor-mcp). The delivered work aligns with the PRO-0107 specification.

---

### 1. Is declaring all 35 unpublished an honest disposition, or is it clearing a gate by declaration?

* **The strongest case that this is the wrong call:** 
  `unpublishedReason` is intended as an exception mechanism for auxiliary or non-surface frames (such as the TextEdit scratchpad baseline in `overlay-exclusion.json`). Applying it to 100% of the 35 unaccounted images looks like papering over a failing gate to turn exit 2 into exit 0 without publishing a single capture or deleting dead files. Furthermore, several of these files (`surf-004-run-hud.png`, `surf-005-takeover-shield.png`, `surf-008-tools.png`) depict real product surfaces and are actively cited as evidence for passing test cases ([CASE-0008](file:///Users/lukerhodes/Dev/proctor-mcp/.worktrees/PRO-0107/docs/test-campaign/evidence.html#CASE-0008), [CASE-0010](file:///Users/lukerhodes/Dev/proctor-mcp/.worktrees/PRO-0107/docs/test-campaign/evidence.html#CASE-0010), [CASE-0011](file:///Users/lukerhodes/Dev/proctor-mcp/.worktrees/PRO-0107/docs/test-campaign/evidence.html#CASE-0011)) in [`evidence.html`](file:///Users/lukerhodes/Dev/proctor-mcp/.worktrees/PRO-0107/docs/test-campaign/evidence.html). Declaring them "unpublished" in [`captures.json`](file:///Users/lukerhodes/Dev/proctor-mcp/.worktrees/PRO-0107/docs/test-campaign/evidence/shots/captures.json) while they serve as evidence elsewhere appears contradictory.

* **Why the case does not hold:**
  Under the gate's strict epistemic contract, **a capture can only be published if its target was recorded at shutter time**.
  1. None of the 35 images carried a shutter-recorded target. Backfilling target strings post-hoc based on visual inspection or filenames would commit the exact violation the gate was built to stop: recording *"what somebody believed after the fact, not what the channel did."*
  2. Deleting them was impermissible: no file was 0 bytes, no file duplicated an already published shot, and the duplicate groups constitute the physical proof of DEF-218, DEF-221, and DEF-222.
  3. The runner did not issue empty declarations. Every image was inspected and re-measured (dimensions, opaque pixels, distinct RGBA, SHA-256) via [`scripts/campaign/shot_disposition.py`](file:///Users/lukerhodes/Dev/proctor-mcp/.worktrees/PRO-0107/scripts/campaign/shot_disposition.py). Running `--verify` enforces that if bytes drift or files disappear, the gate fails immediately. 

Declaring them unpublished with explicit reasons is the only disposition consistent with the instrument's rules.

---

### 2. Was refusing to publish right?

**Yes.** Refusing to publish was correct.

Even where filenames are honest and sibling JSON files exist (`surf-004-run-hud.png`, `surf-005-takeover-shield.png`, `sweepK-extras-open.png`):
* The sibling records (`overlay-capture-lifted.json`, `sweepK-popover.json`) record bounds, layers, and item strings, but **no window ID or target binding**.
* While adding `"target": "SURF-004"` into `captures.json` today would satisfy the script syntax, it would turn the lineage record into an unverified assertion.
* Additionally, `sweepK-extras-open.png` is a full display capture containing third-party desktop windows behind the menu, failing the standard for a window-scoped surface capture.

The only legitimate path to publishing these surfaces is re-executing the capture harness with [`capture_with_manifest.py`](file:///Users/lukerhodes/Dev/proctor-mcp/.worktrees/PRO-0107/scripts/campaign/capture_with_manifest.py) so provenance is captured at the shutter.

---

### 3. Was leaving the ratchet at 6 right?

**Yes.** 

The ratchet in [`capture-ratchet.json`](file:///Users/lukerhodes/Dev/proctor-mcp/.worktrees/PRO-0107/docs/test-campaign/capture-ratchet.json) tracks the number of **judged, published captures** (holding at 6 of 8, with SURF-006 and SURF-007 structurally unjudgeable). 
* PRO-0107 published 0 new captures and judged 0 new captures.
* Triage cleanup and cataloging unpublished files accounts for un-gated artifacts, but does not advance visual oracle coverage.
* Raising the ratchet would have recorded a higher bar without any new capture actually passing under it.

---

### 4. Is any of the six findings overclaimed?

**No.** All six findings (**Finding 1** through **Finding 6**, DEF-218..DEF-223) are exact and grounded in re-derivable data:

* **Finding 3 (Fairness of the recovery frame reading):** **Fair.** 
  While a window recovered after `SIGCONT` is expected to return to the "Ready" state, `sweepL-wedged-recovered.png` is byte-identical (`670a93988315…`) to both `sweepL-wedged-t1.png` and `sweepK-theme-before.png` (from an entirely separate sweep). Sharing exact byte hashes across distinct sweeps and timepoints proves the recovery frame was a reused static file rather than an independent capture of the recovery transition. Calling out DEF-221 is accurate.
* **Finding 5 (Real defect vs. shots array artifact):** **Real defect (DEF-220).** 
  `sweepK-scaling.json` records mode measurements for four specific display geometries (including a 781x961 baseline). The 781x961 capture is missing from disk, and two 900x833 images from an older build (with letter-spaced capital headers) were placed in the sweep's `shots` array. The JSON claims a set of shots that do not match the measurements performed.

---

### 5. What did this item miss that a reader of the evidence page would notice?

**The dangling and contradictory evidence links in [`docs/test-campaign/evidence.html`](file:///Users/lukerhodes/Dev/proctor-mcp/.worktrees/PRO-0107/docs/test-campaign/evidence.html).**

The lineage gate (`capture-lineage.py`) only scans captures published via [`inventory.json`](file:///Users/lukerhodes/Dev/proctor-mcp/.worktrees/PRO-0107/docs/test-campaign/inventory.json) (`surface` and `flow.steps`), completely ignoring the `Evidence` column links in [`cases.json`](file:///Users/lukerhodes/Dev/proctor-mcp/.worktrees/PRO-0107/docs/test-campaign/cases.json) and `evidence.html`. Consequently:
1. **Direct Contradictions:** A reader viewing [CASE-0028](file:///Users/lukerhodes/Dev/proctor-mcp/.worktrees/PRO-0107/docs/test-campaign/evidence.html#CASE-0028) (which claims DEF-002 was retracted because the window showed "Agent down") who clicks the linked evidence file [`sweepL-status-agent-down.png`](file:///Users/lukerhodes/Dev/proctor-mcp/.worktrees/PRO-0107/docs/test-campaign/evidence/shots/sweepL-status-agent-down.png) will see a green **Ready** window (**Finding 2**).
2. **Reused Evidence:** A reader clicking [CASE-0029](file:///Users/lukerhodes/Dev/proctor-mcp/.worktrees/PRO-0107/docs/test-campaign/evidence.html#CASE-0029)'s evidence link [`sweepL-wedged-recovered.png`](file:///Users/lukerhodes/Dev/proctor-mcp/.worktrees/PRO-0107/docs/test-campaign/evidence/shots/sweepL-wedged-recovered.png) will see the exact same file as the wedged frame (**Finding 3**).
3. **Unpublished Evidence on "Passing" Cases:** Cases [CASE-0008](file:///Users/lukerhodes/Dev/proctor-mcp/.worktrees/PRO-0107/docs/test-campaign/evidence.html#CASE-0008), [CASE-0010](file:///Users/lukerhodes/Dev/proctor-mcp/.worktrees/PRO-0107/docs/test-campaign/evidence.html#CASE-0010), and [CASE-0011](file:///Users/lukerhodes/Dev/proctor-mcp/.worktrees/PRO-0107/docs/test-campaign/evidence.html#CASE-0011) are displayed as `pass raster-visual` with links to `surf-004-run-hud.png`, `surf-005-takeover-shield.png`, and `surf-008-tools.png`—files that the lineage tool now treats as unpublished and lacking capture-time targets.

PRO-0107 turned the lineage gate green, but left the user-facing HTML dashboard linking to discredited and unpublished evidence files.
