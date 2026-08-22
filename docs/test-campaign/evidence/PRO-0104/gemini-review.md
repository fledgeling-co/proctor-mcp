This review evaluates **PRO-0104** ("An input the check cannot classify"), covering defects DEF-201, DEF-202, and DEF-203 across [`reckon.py`](file:///plugins/reckon/skills/reckon/scripts/reckon.py), [`selftest.py`](file:///plugins/reckon/skills/reckon/scripts/selftest.py), [`spec_citation_measure.py`](file:///scripts/campaign/spec_citation_measure.py), and [`spec_citation_arm.py`](file:///scripts/campaign/spec_citation_arm.py).

---

### Q1. Does the repair actually satisfy demand (2), or is there a place where an input is still resolved by a silent default in either direction?

**Verdict:** **Yes**, the repair satisfies demand (2).

**Reason:**
1. **Explicit closed partitioning:** All three registry vocabularies (`CASE_VOCABULARY`, `DEFECT_VOCABULARY`, and `EVIDENCE_VOCABULARY`) and brief ID scanner outputs are fully closed sets.
2. **Fail-closed placement with explicit finding emission:** If an unrecognised value is encountered (e.g., an unlisted defect status, case status, requirement evidence string, or an in-prose placeholder ID), the row is given a fail-closed class (`broken` for defects, `unmeasured` for cases/requirements, `unjoined` for briefs) to preserve partition totality. However, this is not resolved silently: `unclassified_inputs()` collects each instance, [`gate()`](file:///plugins/reckon/skills/reckon/scripts/reckon.py#L1084-L1094) raises a blocking `vocabulary` violation exiting `4`, and [`render()`](file:///plugins/reckon/skills/reckon/scripts/reckon.py#L1260-L1277) outputs an explicit Markdown table naming the field, value, row count, placed class, and row IDs.
3. **Empty inputs are handled intentionally:** Missing fields (such as a defect row with no status) are explicitly defined and classified as unrecorded repairs (`broken`), distinguished from unknown strings.
4. **Citation measurement enforcement:** In [`spec_citation_measure.py`](file:///scripts/campaign/spec_citation_measure.py#L328-L478), unrecognised header relations (`odd_relation`), shown-only brief paths (`shown_only_claim`), incidental prose mentions (`mention_only_claim`), and unresolvable `none.` references (`unresolved_reasons`) are surfaced in dedicated assertion checks.

---

### Q2. Is `waived` the right class for the seven not-owing defect words, given the available classes?

**Verdict:** **Yes**, `waived` is the correct class.

**Reason:**
1. **Epistemic truthfulness (Not `verified-done`):** A defect marked `invalid`, `cannot reproduce`, `by design`, `obsolete`, `superseded`, `not-a-defect`, or `vacuous` was not repaired or verified by a test campaign. Classing it as `verified-done` would make a false claim of repair.
2. **Queue accuracy (Not `broken` / work item):** None of these seven statuses represent outstanding work (`is_work_item = False`). Retaining them in `broken` would inflate the active backlog with items that require no engineering action.
3. **Auditability and conditionality:** `waived` accurately conveys an administrative ruling or exception ("somebody decided not to"). It keeps the items visible on the ledger without counting them as active work, preserving the record if the underlying reason changes (e.g., a `cannot reproduce` that receives a new reproduction).

---

### Q3. Is the exclusion set and the placeholder rule the right partition, or is there a fourth shown-not-used region or wrong classification?

**Verdict:** **Yes**, the partition and placeholder rule are correct.

**Reason:**
1. **Exclusion set precision:** Fenced code blocks (` ``` `, ` ~~~ `), HTML comments (`<!-- ... -->`), and strikethroughs (`~~...~~`) are the exact syntactical markdown constructs that explicitly denote display-only or non-normative text.
2. **Non-collapsing blanking:** Replacing non-newline characters with whitespace via `_blank()` preserves exact byte offsets and line numbering, preventing line-start anchors from accidentally merging across deleted boundaries. Inline backticks (`` `ID` ``) are rightly not stripped wholesale because valid citations in prose frequently use inline code formatting.
3. **Placeholder classification:** Treating all-9s and all-0s IDs (e.g., `CASE-9999`, `REQ-0000`) in prose as `unclassifiable` findings rather than silently ignoring them obeys demand (2): silently dropping them would guess authorial intent, while creating an edge would generate false `unbuilt` tasks. Raising a vocabulary finding forces explicit author resolution.

---

### Q4. Exit code 4 for a vocabulary finding is ordered below conservation/placement (1) and above disclosure (2). Is that ordering defensible?

**Verdict:** **Yes**, this ordering is defensible and logically sound.

**Reason:**
1. **Subordinate to Conservation / Placement (`1`):** Conservation and placement violations represent fatal structural corruption (e.g., duplicate IDs, violated entity conservation, illegal class placements). Structural corruption invalidates the integrity of the data structure itself and must take highest precedence.
2. **Superordinate to Disclosure (`2`):** A vocabulary violation (`4`) means the tool was forced to apply a fail-closed fallback rather than reading registry intent. Because all aggregate counts and metrics are derived over these fallback placements, the ledger is epistemically uncertain—a more critical condition than presentation/disclosure omissions (e.g., missing denominator metadata).

```
Precedence: [1] Conservation / Placement (Structural corruption)
              ↓
            [4] Vocabulary violation (Classification uncertainty)
              ↓
            [2] Disclosure violation (Presentation / metadata omissions)
              ↓
            [0] Clean pass
```

---

### Q5. In `spec_citation_measure.py`, does the `none.` resolution rule leave an evasion open?

**Verdict:** **No**, it does not leave an evasion open within structural verification.

**Reason:**
1. **Bare names cannot satisfy the gate:** A `none.` reason containing only bare names/tools without an addressable artifact yields `any(ok) == False` and fails under `unresolved_reasons` ("resolves nothing").
2. **Strict resolution of addressable references:** If an author supplies a path (holding `/`), a git commit SHA (7–40 hex), or a PRD section (`§N`), each token must resolve against the tree, git database, or [`docs/PRD.md`](file:///docs/PRD.md). Any dangling reference in `refs` populates `dangling` and immediately fails the gate, even if another valid reference is present.
3. **Safe allowance of descriptive names:** Unresolvable "names" (e.g., citing a tool like `proctor_act`) are permitted *only* alongside an independently valid, resolvable reference (and their count is surfaced in the summary). This allows human-readable context without permitting names to substitute for verified artifacts.

---

### Q6. Anything in the diffs that is wrong, unproven, or that will misfire on a repository other than this one?

**Verdict:** The repair is solid for its target environment, but contains **three specific edge cases / portability assumptions** that will misfire on other repositories:

1. **Single-digit ID misfire in `PLACEHOLDER_ID_RE` ([`reckon.py:350`](file:///plugins/reckon/skills/reckon/scripts/reckon.py#L350)):**
   ```python
   PLACEHOLDER_ID_RE = re.compile(r"\A(?:REQ|CASE|DEF|SURF|FLOW|COMP)-(?:9+|0+)\Z")
   ```
   Because `9+` matches a single `"9"`, any repository using unpadded sequential IDs (e.g., `REQ-1`, ..., `REQ-9`) will classify item 9 (`REQ-9`, `DEF-9`, `CASE-9`) as an unclassifiable placeholder rather than a valid citation.
2. **Absolute path escape in `pathlib.Path` ([`spec_citation_measure.py:302`](file:///scripts/campaign/spec_citation_measure.py#L302)):**
   ```python
   elif first and (REPO / first).exists():
   ```
   In Python `pathlib`, `REPO / "/bin/sh"` resolves to root `/bin/sh`. If a spec author writes `` `none. Ran /bin/sh` ``, it evaluates to `True` on macOS/Linux and passes as a repository path rather than being flagged.
3. **Hardcoded repository conventions ([`spec_citation_measure.py:135, 275`](file:///scripts/campaign/spec_citation_measure.py#L135-L275)):**
   - `ACCOUNT_RELATIONS = ("Brief", "Supersedes", "Direction")` and `PRD = REPO / "docs/PRD.md"` are tailored specifically to `proctor-mcp`. Repositories using alternative header verbs (`**Origin:**`, `**Parent:**`) or alternative PRD paths (e.g., `PRD.md`) will trigger check failures.
   - `tok.split()[0]` takes the first word of a backticked token, so repository paths containing spaces (e.g., `` `docs/my feature/spec.md` ``) will extract `docs/my` and fail as dangling paths.
