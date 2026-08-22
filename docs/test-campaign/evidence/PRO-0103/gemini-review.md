This material is **PRO-0103: "A reckoning worth comparing against"**.

---

### Evaluation of the 5 Questions

#### 1. Soundness of the tool-constant decomposition
**Verdict: Sound.**
- When comparing runs across different tool versions (e.g., `reckon` 1.0.0 → 1.1.0), `compare` extracts the earlier run's inputs at its recorded commit via `git archive` and runs the current tool version (`1.1.0`) on them in an isolated temporary tree.
- This creates an exact control baseline:
  $$\text{Tool Movement} = \text{Control} - \text{Previous (Published)}$$
  $$\text{Project Movement} = \text{Current} - \text{Control}$$
  $$\text{Net Movement} = \text{Current} - \text{Previous} = \text{Tool Movement} + \text{Project Movement}$$
- In `delta.md`, all row-level transitions (`moved`, `appeared`, `vanished`), axis calculations, and `unmeasured` dynamics are strictly computed between **Control** and **Current**, preventing tool fixes (like correcting status recognition on 108 defects or join classification on 75 briefs) from being falsely credited as project progress.

#### 2. Ratchet enforcement
**Verdict: Fully enforced.**
- In `compare()`, `ratchet_pair()` is executed prior to writing delta reports. For decomposed runs, both the published pair and the tool-constant control pair are checked against `reckon ratchet`.
- If either pair produces a non-zero exit code or silent transitions from `unmeasured`, the violation details are rendered directly into `delta.md` and printed to `stderr`, and `compare()` immediately returns `EXIT_RATCHET` (exit code `3`).
- In `cmd_take()`, the exit code of `compare()` is directly returned to `main()`. There is no path where a delta report is produced without running the ratchet or where a non-zero ratchet exit code is swallowed.

#### 3. Selftest validity & vacuity check
**Verdict: Non-vacuous.**
- All 28 checks in `scripts/reckoning/reckoning_selftest.py` are active and armed.
- Every gate check is validated via either:
  1. A two-way control (verifying that valid inputs pass and invalid inputs fail with expected error messages and exit codes).
  2. Removal mutations (e.g., Check 5, Check 7, Check 11, Check 14, Check 16) that assert substitution counts on a copy of `reckoning.py` to prove that disabling the specific check causes the failure to leak or alter the exit code.
- Check 28 binds `CADENCE.md`'s stated check count against runtime test count (`CHECKS + 1 == 28`), preventing documentation drift.

#### 4. Delta report structure and readability
**Verdict: Meets all acceptance criteria.**
- `delta.md` leads immediately with `# Reckoning delta` and `## What moved` (overall verdict, 5-axis delta table with point movement and directional indicators, and the `unmeasured` class focus block).
- Attribution and decomposition appear in `## Where the movement came from`, followed by `## The ratchet` and row-level changes.
- `## Totals, last` is placed at the end of the report.
- A reader can immediately determine whether coverage is improving from the headline summary and the per-axis direction badges (`better`, `flat`, `worse`) without manual recalculation.

#### 5. Portability and tree independence
**Verdict: Robust.**
- Worktree awareness is handled via `git rev-parse --git-common-dir` in `repo_name()`, preventing worktree path confusion.
- Git operations operate strictly on named commits and paths.
- Default path fallbacks to local paths are overridable via CLI flags (`--reckon`, `--repo`) and the `RECKON_SCRIPT` environment variable.

---

### Findings

#### [LOW] [scripts/reckoning/reckoning.py](file:///tmp/scripts/reckoning/reckoning.py#L48-L51) & [scripts/reckoning/reckoning_selftest.py](file:///tmp/scripts/reckoning/reckoning_selftest.py#L27-L30)
- **What is wrong:** `DEFAULT_RECKON` and `REAL_RECKON` fall back to a hardcoded user path (`/Users/lukerhodes/Dev/...`) if the `RECKON_SCRIPT` environment variable is unset. On another machine or in CI without this path or environment variable, execution will refuse with `no reckon script at ...`.
- **What would fix it:** While this is guarded by `resolve_tool` (which refuses cleanly with exit code 2) and documented in `CADENCE.md`, adding a standard discovery check (e.g., checking `Path.cwd() / "..."` or relative repository locations) before falling back to the hardcoded absolute path would improve out-of-the-box portability across disparate development environments.

---

OVERALL: ACCEPT
