Here is the detailed review of item **PRO-0106** across the five instruments and their test suites.

---

### 1. Is any repair WRONG — does any new check pass where it should fail, or fail where it should pass?

Yes. Several repaired checks contain logic errors where they misclassify outcomes or mangle inputs:

#### A. `mutate_swift.py` line 182: `run_suite()` intercepts crashes/runtime errors before checking `VERDICT_LINE` (DEF-240 repair is broken)
* **The Code ([`mutate_swift.py:L182-188`](file:///tmp/pro0106-review-input.md#L182-L188)):**
  ```python
  if p.returncode != 0 and ("cannot find" in out or "error:" in out or "Build failed" in out):
      return False, "build-failed"
  if p.returncode == 0:
      return True, "passed"
  if not VERDICT_LINE.search(out):
      return False, "no-verdict-line"
  return False, "failed"
  ```
* **The Error:** Line 182 checks `if p.returncode != 0 and ("error:" in out ...)` *before* checking whether a verdict line exists.
* **The Input:** 
  1. Any test run that linked successfully but died at runtime where `test.sh` or Swift prints an error line (for example, the exact DEF-240 fixture: `"error: Process '…' exited with unexpected signal code 5\nFAIL: no swift-testing verdict line"`). Because `"error:"` is present in `out`, line 182 returns `(False, "build-failed")` instead of `(False, "no-verdict-line")`. `score()` then marks it as `"unbuildable"` rather than `"inconclusive"`.
  2. Any test that fails legitimately and prints a verdict line (`Test run with 10 tests failed...`), but whose application output or diagnostics contain `"error:"`. Line 182 classifies it as `"build-failed"` (`unbuildable`) rather than `"failed"` (`killed`).

#### B. `reckoning.py` lines 935–937: `porcelain_paths()` unconditionally splits on `" -> "`
* **The Code ([`reckoning.py:L934-938`](file:///tmp/pro0106-review-input.md#L934-L938)):**
  ```python
  entry = line[3:]
  if " -> " in entry:
      entry = entry.split(" -> ", 1)[1]
  entry = unquote_path(entry)
  ```
* **The Error:** It checks `if " -> " in entry:` on *every* porcelain line without checking if the status code `line[:2]` indicates a rename (`R`) or copy (`C`).
* **The Input:**
  1. A modified tracked file named `docs/from -> to.md` (status: ` M docs/from -> to.md`). `porcelain_paths()` splits on `" -> "` and returns `to.md`. The refusal names `to.md` (which does not exist at root), and `--allow-dirty` writes that phantom into `run.json.dirty_inputs` — recreating DEF-206 on any file whose name contains `" -> "`.
  2. A rename where the original path contains `" -> "` and is quoted by git (e.g. `R  "a -> b.txt" -> c.txt`). Splitting on `" -> "` produces `b.txt" -> c.txt`, which `unquote_path()` fails to parse, returning a corrupted string.

#### C. `shot_disposition.py` lines 733–734: `adoptable()` ignores new files that have a static disposition rule
* **The Code ([`shot_disposition.py:L733-734`](file:///tmp/pro0106-review-input.md#L733-L734)):**
  ```python
  elif old_row is None and not r["disposed"]:
      out.append((r["file"], ...))
  ```
* **The Error:** If `old_row is None` (a file added since the audit was written), it only blocks `--write` if `not r["disposed"]`.
* **The Input:** A new screenshot added to `evidence/shots/` whose filename matches a disposition pattern in `shot_disposition.py` (so `r["disposed"] == True`). `adoptable()` returns `[]` for it. Running `--write` writes the new file into `shot-audit.json` as baseline without requiring `--adopt <file>`, bypassing DEF-226.

#### D. `mutation_seam_arm.py` lines 453–455: `score_arming()` credits runs unconditionally on non-zero exit with a verdict line
* **The Code ([`mutation_seam_arm.py:L453-455`](file:///tmp/pro0106-review-input.md#L453-L455)):**
  ```python
  if r["verdict"]:
      if r["exit"] != 0:
          return "ARMED", True, "the suite reported a verdict line and exited %d" % r["exit"]
  ```
* **The Error:** If `r["verdict"]` exists and `r["exit"] != 0`, it returns `ARMED` without checking whether the targeted test (`display`) actually ran or was what failed.
* **The Input:** Running `--filter functionA` where `functionA` passed or was skipped, but an unrelated test or suite-level failure produced a non-zero exit and a verdict line. The arming is scored `ARMED` for `functionA`.

---

### 2. Is scoring a trapping mutant `ARMED` via `started` and no completion sound? What could produce `started` without the check firing?

**It is NOT fundamentally sound.** While it distinguishes an in-test trap from an early setup failure before the runner started, it assumes that anything happening after `Test "<display>" started.` is the mutated assertion firing.

#### What can produce a `started` line without the check firing?
1. **Traps in test fixture setup / `init`:** In Swift Testing, `@Suite` initialization, test struct `init()`, async traits, and fixture setup run *after* the runner prints `Test "<display>" started.`. A crash (e.g. force-unwrap `!`, out-of-bounds array access, or `fatalError`) in mock setup or dependency construction will log `started`, crash with signal 5/11, and be scored `ARMED` despite never reaching the mutated code.
2. **Concurrent test execution (Default in Swift Testing):** Swift Testing runs tests in parallel across worker tasks unless `@Suite(.serialized)` is specified. If Test A (`display`) starts, and concurrently running Test B crashes, the process terminates with signal 5/11. Both Test A and Test B are in `r["started"]` and neither is in `r["finished"]`. Scoring Test A as `ARMED` credits a test that was simply running in the background when something else crashed.
3. **Precondition / requirement failures before the mutated call:** If the test has `try #require(...)` or `guard ... else { fatalError() }` verifying inputs before invoking the subject, an environment failure will trigger a trap that is falsely credited as the mutant check firing.
4. **Teardown / `deinit` traps:** A crash in `deinit` or post-test cleanup occurring after the test body finished executing but before the runner printed `Test "<display>" passed.` will be counted as a trap catch.

---

### 3. In `mutate_swift.py` `apply()`, is there a case that slips through the offset check and read-back?

Yes. Two significant cases slip through:

1. **Drift to an identical token at another site (Wrong-site mutation):**
   * Suppose a Swift file has `==` on line 2 (offset 15) and another `==` on line 10 (offset 80).
   * A mutant is generated for line 10 (`start: 80, end: 82, before: "=="`).
   * If an edit elsewhere in the file shifts text such that a *third* `==` token (or line 2's token) moves to offset 80:
     * `text[80:82] == "=="` evaluates to `True`.
     * `path.write_text(expected)` splices at offset 80.
     * `path.read_text() == expected` evaluates to `True`.
   * **Result:** The mutator spliced the wrong site in the file, but `apply()` returned `(True, ...)`. The test runner grades line 2 or 12 while the harness attributes the kill/survival to line 10.
2. **Character index vs. UTF-8 byte offset mismatch on non-ASCII text:**
   * [`mutate_swift.py:L125`](file:///tmp/pro0106-review-input.md#L125) uses `text = path.read_text()` and slices `text[start:end]`. In Python, string slicing operates on **Unicode character codepoints**, not bytes.
   * If mutant generation (e.g. Swift AST, SourceKit, or libSyntax) emits **UTF-8 byte offsets**, any file containing multi-byte characters (such as `café`, em-dashes `—`, emojis, or non-ASCII quotes) will have diverging byte offsets and character offsets. Slicing with character indices will either slice the wrong characters (and fail if mismatched) or, if coincidentally matching `before`, mutate the wrong location.
3. **No-op / Inert mutations (`before == after`):**
   * If `mutant["before"] == mutant["after"]`, `expected == text`. `apply()` returns `True`, claiming the mutation landed when the file was left unchanged.

---

### 4. In `shot_disposition.py --write`, is there another route by which new content becomes the baseline unnoticed?

Yes. Several routes allow unreviewed content to become baseline:

1. **Missing `AUDIT` file:**
   * Line 719: `if not AUDIT.exists(): return []`.
   * If `shot-audit.json` does not exist (fresh clone, new campaign directory, or deleted file), `adoptable(a)` returns `[]`. Running `--write` adopts all images and hashes on disk with no `--adopt` requirement.
2. **New images matching static disposition rules:**
   * Lines 733–734 only flag an unrecorded file if `old_row is None and not r["disposed"]`.
   * If a new file is added that `shot_disposition.py` marks `disposed: True` via its internal tables, `adoptable()` ignores it and `--write` commits it without `--adopt`.
3. **Deleted or renamed baseline files:**
   * `adoptable()` iterates over `for r in a["shots"]:` (current disk files) and never compares `set(prior) - set(now)`. If baseline images are deleted or renamed, running `--write` silently deletes them from the audit baseline without notice or flag.
4. **Metadata / Disposition changes with identical image bytes:**
   * Line 725 only checks `old_row.get("sha256") != r["sha256"]`. If someone alters `publishedAs`, `depicts`, or classification tags in code, `--write` updates the baseline audit without `--adopt`.
5. **`byteIdenticalGroups` changes:**
   * `verify()` checks `byteIdenticalGroups`, but `adoptable()` does not. New duplicate groups or broken groupings are written directly into `shot-audit.json` by `--write` without `--adopt`.
6. **`--manifest` bypass:**
   * Running `shot_disposition.py --manifest` prints capture entries derived directly from the unadopted disk state to stdout, bypassing `--adopt` checks for downstream manifest consumers.
7. **Mock files bypass:**
   * `is_mock(path)` (`"mock" in Path(path).parts`) exempts any image under a `mock/` directory from disposition checks entirely.

---

### 5. In `reckoning.py` `porcelain_paths`: does it mishandle any git status porcelain output shape?

Yes:

1. **Non-rename files with `" -> "` in the filename:**
   * Format: ` M path/to/step-1 -> step-2.json` or `?? assets/arrow -> target.png`.
   * [`reckoning.py:L935`](file:///tmp/pro0106-review-input.md#L935) executes `entry = entry.split(" -> ", 1)[1]`, truncating the path to `step-2.json` or `target.png`.
2. **Rename entries where the source path contains `" -> "`:**
   * Format: `R  "old -> name.txt" -> new.txt`.
   * It splits on the first `" -> "`, yielding `name.txt" -> new.txt`, which `unquote_path()` fails to unquote.
3. **Type changes (`T `) and Merge Conflicts (`UU`, `AA`, `DD`, `AU`, `UD`, `UA`, `DU`):**
   * Although `line[3:]` extracts the path for conflict lines, `porcelain_paths` treats conflict states identically to ordinary dirty working tree files and does not report whether the repository is in an unresolved merge state.
4. **Submodules (` M path/to/submodule` or `?? path/to/submodule/`):**
   * Trailing slashes emitted by git for dirty or untracked submodules are not normalized.

---

### 6. THE MOST IMPORTANT QUESTION: What register, path, or input kind does any of these repaired instruments still NOT read or drive?

PRO-0106's thesis is that an instrument must prove its own steps across all paths, not just the path exercised by happy-path tests. The following registers, paths, and inputs remain **unread and undriven**:

#### 1. `mutate_swift.py`: `revert()` is unwitnessed and unproved
* **Line citation:** [`mutate_swift.py:L145, L232`](file:///tmp/pro0106-review-input.md#L145) (`revert(m)`).
* **The Undriven Step:** While `apply()` was repaired with offset checks and a read-back assertion (DEF-207), `revert(m)` remains a fire-and-forget operation. It never re-reads the file to prove the original source was restored. If a revert fails or partially writes, all subsequent mutants in the loop run against corrupted source code.
* **The Undriven Target:** `run_suite()` runs `./scripts/test.sh` globally; it never reads test coverage registers or verifies that the test suite actually exercised the file named in `mutant["file"]`.

#### 2. `mutation_seam_arm.py`: Suite namespaces, parameterized tests, and trait variants are unread
* **Line citations:** [`mutation_seam_arm.py:L363`](file:///tmp/pro0106-review-input.md#L363) (`TEST_ATTR_RE`), [`L361`](file:///tmp/pro0106-review-input.md#L361) (`STARTED_RE`), [`L380-398`](file:///tmp/pro0106-review-input.md#L380-L398) (`display_name()`).
* **The Undriven Inputs:**
  * **Nested Suite namespaces:** Swift Testing prepends suite names to test outputs (e.g. `Test "MySuite/testFunction()" started.`). `display_name()` extracts only the bare display name or function name without the enclosing `@Suite` / `struct` / `class` namespace. For any nested test, `display in started` will evaluate to `False`, causing a valid trap to be marked `INCONCLUSIVE`.
  * **Trait ordering in `@Test`:** `TEST_ATTR_RE = re.compile(r'@Test\(\s*"((?:[^"\\]|\\.)*)"')` assumes the display string is the first and only argument. It fails on `@Test(.tags(...), "Display Name")`, `@Test(.disabled(), "Display Name")`, or `@Test(arguments: ...)`.
  * **Parameterized tests:** Parameterized tests log argument values in their started lines (e.g. `Test "test(arg: 1)" started.`). `display_name()` generates `test()`, which never matches.

#### 3. `shot_disposition.py`: Non-PNG media, non-case citations, and non-shots directories are unread
* **Line citations:** [`shot_disposition.py:L750`](file:///tmp/pro0106-review-input.md#L750) (`cite_paths`), [`L822-841`](file:///tmp/pro0106-review-input.md#L822-L841) (`citations`).
* **The Undriven Inputs:**
  * **Non-PNG media formats:** `cite_paths()` hardcodes `s.endswith(".png")`. Citations of `.jpg`, `.jpeg`, `.webp`, `.pdf`, `.svg`, `.mov`, or `.mp4` files are completely ignored.
  * **Non-case citation sources:** `citations()` reads *only* `cases.json`. Image citations in `run.json`, `ledger.json`, `docs/plans/*.md`, `docs/specs/*.md`, and test reports are unread and unverified.
  * **Non-`evidence/shots/` paths:** `citations()` line 841 filters on `path.startswith("evidence/shots/")`. Images located in `evidence/captures/` or other directories are not checked against the disposition audit.

#### 4. `reckoning.py`: File metadata, permission bits, and external side-effects are unread
* **Line citations:** [`reckoning.py:L919-941`](file:///tmp/pro0106-review-input.md#L919-L941) (`porcelain_paths`), [`L958-994`](file:///tmp/pro0106-review-input.md#L958-L994) (`cmd_take`).
* **The Undriven Registers:**
  * **File permissions and mode changes:** `sweep()` computes byte counts and SHA-256 hashes. It does not witness `chmod +x` executable bit changes, file permission changes, or timestamp/xattr changes.
  * **Writes outside `out`:** `cmd_take` only sweeps the designated `out` directory; any filesystem writes by `reckon` to `/tmp`, the repository root, or configuration files remain completely unwitnessed.
  * **Git porcelain states:** `porcelain_paths` was only tested for 6 specific status shapes in `reckoning_selftest.py:L580-608`. Type conversions (`T`), submodule pointer shifts (` m `), and merge conflicts (`UU`) remain undriven.

#### 5. `mutation_timeout_arm.py`: Shallow-clone git history is unresolvable
* **Line citation:** [`mutation_timeout_arm.py:L580`](file:///tmp/pro0106-review-input.md#L580) (`BASELINE_REF = "fc1b9a4~1"`).
* **The Undriven Path:** `BASELINE_REF` is pinned to a commit object `fc1b9a4~1`. In shallow git clones (such as standard CI checkouts), this ref does not exist, causing the arming instrument to fail before reading or driving any test.
