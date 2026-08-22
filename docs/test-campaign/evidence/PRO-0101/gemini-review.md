### Subject Verification
The submitted material matches **PRO-0101** (reconciling the brief queue against specification files in `proctor-mcp`).

---

### Answers

#### A. Resolution Clause Gaps
The resolution check has two real-world failure modes:
1. **Squash/Rebase Invalidation:** The `path @ sha` convention records `git rev-parse --short HEAD` during triage. If the resulting PR is squash-merged or rebased, that local commit SHA is orphaned or never pushed to the remote repository. Readers cloning downstream will fail `git cat-file -e sha:path`.
2. **Object Type & Empty Files:** `git cat-file -e` verifies only that git can resolve the tree object, not that it is a valid, non-empty markdown blob (e.g., a tree path pointing to a deleted empty blob or directory passes `-e`).

#### B. Uniqueness Check Scope
**Drawing the line at the header is conceptually correct for provenance** (1-to-1 origin vs. cross-referencing in body prose). However, it leaves a loophole: because legacy specs are allowed to claim briefs via prose, any brief claimed in prose is entirely exempt from the uniqueness check and can be claimed concurrently by another spec's header or prose.

#### C. Normalization of Legacy Specs
**They should have been normalized to the `**Brief:**` header.** 
Maintaining dual-mode parsing in [`spec_citation_measure.py`](file:///tmp/scripts/campaign/spec_citation_measure.py) (header vs. prose regex) adds ongoing parser fragility, perpetuates technical debt, and prevents the uniqueness check from enforcing strict 1-to-1 mapping across the entire repository.

#### D. Scratch-Copy Arming
**Yes, this is sufficient.** 
Applying 18 mutations against isolated scratch copies is standard mutation testing. It proves the instrument actively rejects each failure mode without mutating working tree state. Specifically, validating the `@ 3fb7681` (pass) vs. `@ 400808d` (fail) pair guarantees that resolution distinguishes valid historical states from deleting commits.

#### E. Specific Gaps to Address
1. **Triage Deletion Workflow:** The root cause of `path @ sha` complexity is the triage step that deletes brief files upon spec creation. Triage should move triaged briefs to `docs/features-to-triage/archive/` rather than deleting them from the filesystem.
2. **Object Validation:** Replace `git cat-file -e <sha>:<path>` with `test "$(git cat-file -t <sha>:<path> 2>/dev/null)" = "blob" && test $(git cat-file -s <sha>:<path>) -gt 0`.
3. **Meaningless "None" Justifications:** A 20-character floor for `none.` reasons can be satisfied by padding/boilerplate (e.g., `none. not applicable here`). Require structured category prefixes (e.g., `none. [PRD|RESEARCH|DEFECT]: <details>`).

---

### Verdict: Needs More Work

**Reasons:**
1. **Ephemeral SHAs:** Committing `path @ sha` citations derived from pre-merge `HEAD` creates dead links as soon as branches are squashed or rebased.
2. **Dual-Parser Debt:** Failing to normalize the 24 legacy specs weakens the uniqueness invariant and leaves heuristic prose parsing in the validation toolchain.
