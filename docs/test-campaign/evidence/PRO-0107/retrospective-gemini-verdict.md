### 1. Are the spec's acceptance clauses met on this evidence rather than on the narrative?

* **Clause 1: "Every one of the 35 files has a disposition: published into the manifest with the subject it shows, or an `unpublishedReason` on its `captures.json` entry."**
  * **Met.** All 35 unpublished files were individually inspected and assigned an `unpublishedReason` in [`captures.json`](file:///docs/test-campaign/evidence/captures.json). The unaccounted count dropped from 35 to 0, and [`scripts/campaign/shot_disposition.py`](file:///scripts/campaign/shot_disposition.py) verifies all 43 files (8 published + 35 accounted for with explicit reasons).
* **Clause 2: "`capture-lineage.py --gate` exits 0 because the population is accounted for, not because it shrank — the published count rises or each exclusion carries a reason."**
  * **Met.** [`capture-lineage.py docs/test-campaign --gate`](file:///scripts/campaign/capture-lineage.py) exits 0, reporting `43 files, 8 published, COUNTED APART (35), judged 6 of 8, ratchet 6 held`. Total files on disk remained exactly 43 (0 deleted).
* **Clause 3: "The ratchet is raised only by what the change actually earns."**
  * **Met.** The ratchet was held at 6 (6 of 8 judgeable captures). Because no new captures were made judgeable or judged, the ratchet was not raised.

---

### 2. Is publishing none of the 35 images sound, or is it a way of avoiding the work?

* **Strongest Counter-Argument:**
  Declaring 100% of the unaccounted files unpublished is an administrative shortcut that clears the gate while suppressing legitimate visual coverage. Crucially, several files (such as `surf-004-run-hud.png`, `surf-005-takeover-shield.png`, and `surf-008-tools.png`) actually depict their intended surfaces and are directly cited by passing test cases (`CASE-0008`, `CASE-0010`, `CASE-0011`) as `raster-visual` evidence with explicit `capture.method` declarations. By declaring them unpublished rather than reconstructing their lineage metadata or recapturing them, the item introduces a major contradiction between the lineage manifest and [`cases.json`](file:///docs/test-campaign/cases.json) (DEF-224).
* **Landing:**
  **The item's disposition is sound.** In an evidence-gated campaign, `target` is a specific coordinate/window binding recorded by the instrument at shutter actuation. Inspecting a bitmap after the fact can verify what subject it depicts, but it cannot establish the capture target without fabricating metadata. Faking shutter targets post-hoc to inflate published counts would subvert the exact provenance guarantees `capture-lineage.py` was built to enforce. Refusing to publish, preserving the files on disk, documenting the defect (DEF-224), and requiring proper recapture via `capture_with_manifest.py` maintains epistemic integrity.

---

### 3. Does the item's disposition of the app-icon renders and duplicate captures adequately protect a future reader, or is something still misleading?

* **It protects automated gates, but leaves the filesystem and test cases misleading:**
  * **Protected:** Automated lineage tools and manifest consumers are protected because the 35 files are flagged with `unpublishedReason` in [`captures.json`](file:///docs/test-campaign/evidence/captures.json) and tracked with cryptographic hashes in [`shot_disposition.py`](file:///scripts/campaign/shot_disposition.py).
  * **Misleading:** 
    1. **Deceptive filenames remain on disk:** Nine app-icon renders remain named `surf-001-mcp-stdio.png` through `surf-016-install-notarize.png`, and a Ready window remains named `sweepL-status-agent-down.png`. Anyone browsing `evidence/shots/` directly will be deceived.
    2. **Active case citations (DEF-224):** Passing cases in [`cases.json`](file:///docs/test-campaign/cases.json) still cite these misnamed and duplicate frames as evidence.
    3. **False docstrings:** The retirement docstring in [`scripts/build_test_campaign.py`](file:///scripts/build_test_campaign.py) falsely claims *"Every one of those files has been replaced by the output of a real tool call."*

---

### 4. Is there a defect in `scripts/campaign/shot_disposition.py` that the item did not record?

Yes:
1. **DEF-226 is omitted from the formal Defect table and Registry:** Although verification noted that `shot_disposition.py --write` blindly accepts mutated/degraded images (e.g. flat magenta frames) and re-baselines them to exit 0 without regression checks, **DEF-226 was never added to the item's Defects table or Registry list**.
2. **Uninspected Published Captures (`depicts: null`):** The instrument assigns `depicts: null` to all 8 published captures, enforcing semantic inspection only on the 35 unpublished captures while leaving the 6 ratchet-pinned published captures without semantic validation.
3. **No Cross-Registry Validation:** The script checks `captures.json` against the disk, but contains no checks against [`cases.json`](file:///docs/test-campaign/cases.json), allowing cases to cite unpublished images without the instrument flagging the inconsistency.

---

### 5. Is there anything materially wrong or missing that questions 1–4 do not reach?

1. **Unresolved Out-of-Family Review Contradiction:** The spec retains a section detailing an out-of-family review by `gemini-3.7-flash-high`, while the subsequent Verification section discloses that the out-of-family review actually failed completely (permission denials/refusals) and that the fallback read the wrong tree (the merge base). The spec text was never reconciled.
2. **Unarmed Cases Missing Declarations:** `CASE-0479` and `CASE-0480` have `armed: false` without the standard in-note declaration required for unarmed cases.
3. **Dangling Path in Sweep JSON:** `sweepL-halfopen.json` references a `statusShot` under `/tmp/campaign-run/` with no corresponding file in `evidence/`, which is unmonitored by any gate.

---

VERDICT: Needs More Work — The core lineage gate work is solid, but the spec must reconcile its contradictory out-of-family review narrative, add DEF-226 to the formal defect table and registry, and add required declarations for unarmed cases `CASE-0479` and `CASE-0480`.
