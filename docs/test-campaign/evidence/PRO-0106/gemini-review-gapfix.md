The test suite `scripts/campaign/test_instruments.py` has been launched in the background; awaiting completion.
Awaiting task-50 completion.
Waiting for `test_instruments.py` to finish.
Waiting for `reckoning_selftest.py` to finish.
### 1. `rename_destination()` and Git Quoting

[`rename_destination()`](file:///Users/lukerhodes/Dev/proctor-mcp/.worktrees/PRO-0106/scripts/reckoning/reckoning.py#L130-L166) in [scripts/reckoning/reckoning.py:L130-166](file:///Users/lukerhodes/Dev/proctor-mcp/.worktrees/PRO-0106/scripts/reckoning/reckoning.py#L130-L166) is structurally sound for all standard porcelain v1 renames:
- The `QUOTE_PATH_QUOTE_SP` claim **is true of git**: git's `quote_c_style` always quotes characters $\le \text{0x20}$ (space, tab, newline), double quotes, and backslashes.
- **`-c core.quotePath=false`:** Git **still quotes spaces**. `quotePath=false` only disables escaping of bytes $> \text{0x7E}$ (UTF-8), leaving space quoting active.
- **Defect under `core.quotePath=false`:** If a path contains *both* non-ASCII characters and a space (e.g. `R "café latte.txt" -> "théâtre royal.txt"`), git outputs literal UTF-8 inside C-quotes. [`rename_destination()`](file:///Users/lukerhodes/Dev/proctor-mcp/.worktrees/PRO-0106/scripts/reckoning/reckoning.py#L130-L166) returns `"théâtre royal.txt"`, but downstream [`unquote_path()`](file:///Users/lukerhodes/Dev/proctor-mcp/.worktrees/PRO-0106/scripts/reckoning/reckoning.py#L114-L128) fails to decode literal UTF-8 and leaves the surrounding quotes attached.

---

### 2. Zero-Test Guard in `score_arming()`

The zero-test guard in [scripts/campaign/mutation_seam_arm.py:L315-322](file:///Users/lukerhodes/Dev/proctor-mcp/.worktrees/PRO-0106/scripts/campaign/mutation_seam_arm.py#L315-L322):
```python
        if verdict_test_count(r["verdict"]) == 0:
            return ("INCONCLUSIVE", None,
                    "the suite reported a verdict line over ZERO tests (%s) and exited %d — "
                    ...
```
is placed correctly directly under `if r["verdict"]:`, before `if display is not None and started and display not in started:` ([line 327](file:///Users/lukerhodes/Dev/proctor-mcp/.worktrees/PRO-0106/scripts/campaign/mutation_seam_arm.py#L327)) and before `if r["exit"] != 0:` ([line 331](file:///Users/lukerhodes/Dev/proctor-mcp/.worktrees/PRO-0106/scripts/campaign/mutation_seam_arm.py#L331)). 

Every non-measurement branch (timeouts, zero-test counts, mismatches, missing/ambiguous display names, concurrent crashes) resolves strictly to `("INCONCLUSIVE", None, ...)`. There are no remaining paths filing non-measurements as `ARMED` or `NOT ARMED`.

---

### 3. `unquote_path()` C-Style Inversion

[`unquote_path()`](file:///Users/lukerhodes/Dev/proctor-mcp/.worktrees/PRO-0106/scripts/reckoning/reckoning.py#L114-L128) in [scripts/reckoning/reckoning.py:L114-128](file:///Users/lukerhodes/Dev/proctor-mcp/.worktrees/PRO-0106/scripts/reckoning/reckoning.py#L114-L128):
```python
        try:
            return (entry[1:-1].encode("ascii", "backslashreplace")
                    .decode("unicode_escape").encode("latin-1").decode("utf-8"))
        except (UnicodeDecodeError, UnicodeEncodeError):
            return entry
```
- **Correct for default git (`core.quotePath=true`):** Inverts all octal byte escapes (`\303\251`) and C-escapes (`\a`, `\b`, `\t`, `\n`, `\v`, `\f`, `\r`, `\"`, `\\`).
- **Incorrect for `-c core.quotePath=false`:** When unescaped UTF-8 sits inside quotes (e.g. `"café latte.txt"`), `backslashreplace` produces `\xe9`, which decodes to Latin-1 byte `0xe9`. `.decode("utf-8")` raises `UnicodeDecodeError`, hitting [line 125](file:///Users/lukerhodes/Dev/proctor-mcp/.worktrees/PRO-0106/scripts/reckoning/reckoning.py#L125) and returning the unstripped string `'"café latte.txt"'`.

---

### 4. Sibling Paths Carrying the Original Defect

1. **Naive porcelain slicing in [`tree_dirty()`](file:///Users/lukerhodes/Dev/proctor-mcp/.worktrees/PRO-0106/scripts/campaign/mutation_seam_arm.py#L156-L160) ([scripts/campaign/mutation_seam_arm.py:L156-159](file:///Users/lukerhodes/Dev/proctor-mcp/.worktrees/PRO-0106/scripts/campaign/mutation_seam_arm.py#L156-L159)):**
   ```python
   def tree_dirty() -> str:
       out = subprocess.run(["git", "status", "--porcelain"], cwd=ROOT,
                            capture_output=True, text=True).stdout
       return "\n".join(l for l in out.splitlines() if not l[3:].strip().startswith("docs/")).strip()
   ```
   While [scripts/reckoning/reckoning.py](file:///Users/lukerhodes/Dev/proctor-mcp/.worktrees/PRO-0106/scripts/reckoning/reckoning.py) repaired porcelain parsing, [`tree_dirty()`](file:///Users/lukerhodes/Dev/proctor-mcp/.worktrees/PRO-0106/scripts/campaign/mutation_seam_arm.py#L156-L160) still uses the unparsed `l[3:]` slice. Any uncommitted file under `docs/` containing spaces or non-ASCII characters (e.g., `?? "docs/test-campaign/new file.md"`) starts with `"`, fails `.startswith("docs/")`, and causes [`main()`](file:///Users/lukerhodes/Dev/proctor-mcp/.worktrees/PRO-0106/scripts/campaign/mutation_seam_arm.py#L369-L450) to refuse execution with exit 2.

2. **Prefix discrepancy in [`citations()`](file:///Users/lukerhodes/Dev/proctor-mcp/.worktrees/PRO-0106/scripts/campaign/shot_disposition.py#L759-L825) ([scripts/campaign/shot_disposition.py:L795, L802](file:///Users/lukerhodes/Dev/proctor-mcp/.worktrees/PRO-0106/scripts/campaign/shot_disposition.py#L795)):**
   ```python
           row = rows.get(path)
   ...
           elif on_disk and path.startswith("evidence/shots/") and not is_mock(path):
   ```
   `rows` keys start with `evidence/shots/`. If `cases.json` cites a shot using repo-relative `docs/test-campaign/evidence/shots/foo.png`, `row` is `None` and `path.startswith("evidence/shots/")` is `False`, allowing the citation to silently bypass audit disposition validation.

---

### 5. Fixtures That Cannot Fail

1. **Source-text check instead of functional gate assertion ([scripts/campaign/test_instruments.py:L1514-1516](file:///Users/lukerhodes/Dev/proctor-mcp/.worktrees/PRO-0106/scripts/campaign/test_instruments.py#L1514-L1516)):**
   ```python
       text = (ROOT / "scripts/campaign/shot_disposition.py").read_text()
       check("the byte-identical grouping moved" in text,
             "verify() fails on a change to the grouping rather than only printing the count")
   ```
   This asserts that a string literal exists in the `.py` source file. It never calls `verify()` with an altered grouping to verify that `verify()` actually detects changes and exits non-zero.

2. **Tautological assertions in test harness ([scripts/campaign/test_instruments.py:L1273, L1284](file:///Users/lukerhodes/Dev/proctor-mcp/.worktrees/PRO-0106/scripts/campaign/test_instruments.py#L1273)):**
   ```python
       check(("ARMED" if r["exit"] != 0 else "NOT ARMED") == "ARMED",
             "the pre-repair rule `armed = code != 0` scores this same fixture ARMED")
   ```
   and [line 1284](file:///Users/lukerhodes/Dev/proctor-mcp/.worktrees/PRO-0106/scripts/campaign/test_instruments.py#L1284):
   ```python
       check(("ARMED" if quiet["exit"] != 0 else "NOT ARMED") == "NOT ARMED",
   ```
   These test an inline Python expression on fixture dictionaries rather than invoking code under test.
