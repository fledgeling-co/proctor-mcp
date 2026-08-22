### 1. Decision A: Candidate 1 (`verified-done`)

* **Choice:** Candidate 1.
* **Why Candidate 2 breaks:** It violates your core acceptance criterion (*"A defect that has been fixed is not counted as remaining work"*). Marking 100 fixed defects as `unmeasured` swaps false "product-work" for false "evidence-work", reproducing the over-reporting fault. In this ontology, the campaign registry is an observation log, not self-reported documentation.
* **Fallback:** Any defect with `status: open`, unknown, or absent must remain `broken`.

---

### 2. Decision B: The `unbuilt` / `unjoined` Split

The split is coherent and cleanly separates epistemic uncertainty (`unjoined`) from measured negative findings (`unbuilt`).

**Sources of "positive evidence of absence" to keep `unbuilt` honest:**
1. **Dangling Explicit Citations (Your proposal):** Brief specifies explicit `REQ-`/`CASE-` IDs that are completely absent from the registry.
2. **Registry Surface Present, Cases Absent:** The brief resolves to a known, registered **Surface** or **Module** (via metadata or explicit tag), but that surface has zero registered requirements or test cases attached to it.
3. **Explicit Negative State in Registry:** The registry contains the matching requirement entity, but its recorded status is explicitly `not_implemented`, `unsupported`, or `backlog`.

**Adjustment to your rule:** Token-overlap matches must carry a strict confidence threshold. A weak token match should fall through to `unjoined` (decision-work), rather than forcing the brief into `broken`, `undecided`, or `unmeasured`.

---

### 3. Additional Design Flaws & Improvements

1. **Join Confidence as a First-Class Signal:** 
   Treat joining as a 3-tier resolution before classification:
   * `Explicit` (by ID) $\rightarrow$ Full classification (`verified-done`, `broken`, `unbuilt`).
   * `Inferred` (token match above threshold) $\rightarrow$ Classify, but flag with lower confidence.
   * `Unjoined` (below threshold or no edges) $\rightarrow$ `unjoined` (`decision-work`).

2. **Defect-to-Brief Transitivity:** 
   If a brief links *only* to a defect (no cases/reqs) and that defect is `status: fixed`, the brief should evaluate to `retirable` or `verified-done`, not `unmeasured`.

3. **Human Actionability for `unjoined`:**
   Because `unjoined` is `decision-work`, output candidate nearest-neighbor IDs or closest token matches alongside the entity. This prevents the human review loop from degenerating into manual grep runs across the registry.
