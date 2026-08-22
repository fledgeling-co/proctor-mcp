#!/usr/bin/env python3
"""PRO-0103: prove every refusal in `reckoning.py` can fire, and is what fired.

A gate that has never been seen to refuse is indistinguishable from a gate that
cannot refuse, and a gate that refuses everything is worse than none. So every
check here is armed twice over:

  * a **two-way control** — the same command over a good input and a bad one,
    which separates "this check fires" from "this command always refuses"
  * where the check can be expressed as one line, a **removal mutation** on a
    scratch copy of `reckoning.py`, which separates "the bad input was refused"
    from "*this* check refused it". Each mutation asserts its own substitution
    count before the run, because a mutation that fails to apply looks exactly
    like a check that cannot fail.

Run: python3 scripts/reckoning/reckoning_selftest.py     (exit 0 = all armed)
"""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
SUBJECT = HERE / "reckoning.py"
REAL_RECKON = Path(os.environ.get(
    "RECKON_SCRIPT",
    "/Users/lukerhodes/Dev/fledgeling-plugins/plugins/reckon/skills/reckon/scripts/reckon.py"))

FAILURES = []
CHECKS = 0


def report(name, ok, detail=""):
    global CHECKS
    CHECKS += 1
    print("%-58s %s%s" % (name, "PASS" if ok else "FAIL", ("  " + detail) if detail and not ok else ""))
    if not ok:
        FAILURES.append("%s — %s" % (name, detail))
    return ok


def run(cmd, cwd=None):
    p = subprocess.run([str(c) for c in cmd], cwd=cwd, capture_output=True, text=True)
    return p.returncode, p.stdout + p.stderr


# ---------------------------------------------------------------------------
# fixtures
# ---------------------------------------------------------------------------

CASES = [
    {"id": "CASE-1", "req": "REQ-1", "surface": "SURF-1", "oracle": "outcome", "status": "pass",
     "evidence": ["fixture"], "armed": True, "note": "the passing one"},
    {"id": "CASE-2", "req": "REQ-2", "surface": "SURF-1", "oracle": "outcome",
     "status": "inconclusive: the instrument could not read the answer",
     "evidence": ["fixture"], "armed": True, "note": "the unmeasured one"},
]
INVENTORY = {
    "requirement": [
        {"id": "REQ-1", "text": "the fixture does the thing", "source": "fixture", "class": "behaviour",
         "evidence": "observed", "surfaces": ["SURF-1"], "effect": "none"},
        {"id": "REQ-2", "text": "the fixture says it does a second thing", "source": "fixture",
         "class": "behaviour", "evidence": "reported", "surfaces": ["SURF-1"], "effect": "none"},
    ],
    "surface": [{"id": "SURF-1", "name": "Fixture", "title": "fixture surface",
                 "route": "tool://fixture", "status": "reachable", "states": ["one"],
                 "description": "a fixture"}],
    "defect": [{"id": "DEF-1", "title": "an open one", "status": "open", "severity": "low"}],
}


def make_repo(root):
    """A git repository shaped like this one: a brief queue and a campaign."""
    root = Path(root)
    (root / "docs/features-to-triage").mkdir(parents=True)
    (root / "docs/test-campaign").mkdir(parents=True)
    (root / "docs/features-to-triage/01-a-thing.md").write_text(
        "# A thing\n\nThe fixture's only brief.\n", encoding="utf-8")
    (root / "docs/test-campaign/campaign.json").write_text(
        json.dumps({"project": "fixture", "lanes": ["headless"]}), encoding="utf-8")
    (root / "docs/test-campaign/cases.json").write_text(json.dumps(CASES), encoding="utf-8")
    (root / "docs/test-campaign/inventory.json").write_text(json.dumps(INVENTORY), encoding="utf-8")
    run(["git", "init", "-q", "."], cwd=root)
    run(["git", "config", "user.email", "fixture@example.com"], cwd=root)
    run(["git", "config", "user.name", "fixture"], cwd=root)
    run(["git", "add", "-A"], cwd=root)
    run(["git", "commit", "-q", "-m", "fixture"], cwd=root)
    return root


def make_tool(root, version="1.1.0", drop_class=None, drop_ratchet=False):
    """A scratch copy of reckon laid out the way a plugin is, at a chosen version."""
    root = Path(root)
    scripts = root / "skills/reckon/scripts"
    scripts.mkdir(parents=True)
    text = REAL_RECKON.read_text(encoding="utf-8")
    if drop_class:
        needle = '"%s", ' % drop_class
        if needle not in text:
            needle = '"%s",' % drop_class
        assert text.count(needle) >= 1, "cannot drop %s from CLASSES" % drop_class
        text = text.replace(needle, "", 1)
    if drop_ratchet:
        text = re.sub(r"\ndef ratchet\(prev, cur\):", "\ndef _ratchet_removed(prev, cur):", text, count=1)
        assert "def ratchet(prev, cur):" not in text
    (scripts / "reckon.py").write_text(text, encoding="utf-8")
    (root / ".claude-plugin").mkdir()
    (root / ".claude-plugin/plugin.json").write_text(
        json.dumps({"name": "reckon", "version": version}), encoding="utf-8")
    return scripts / "reckon.py"


def mutate_subject(dest, replacements):
    """A scratch copy of reckoning.py with one check removed.

    Each replacement asserts its own count, because PRO-0101 lost three armings
    to mutations that silently did not apply — a partial line replacement and
    two regexes that emitted a doubled backslash — and a mutation that does not
    land is reported as a check that cannot fail.
    """
    text = SUBJECT.read_text(encoding="utf-8")
    for old, new, count in replacements:
        found = text.count(old)
        assert found == count, "mutation did not land: %d occurrences of %r, wanted %d" % (found, old[:60], count)
        text = text.replace(old, new)
    dest = Path(dest)
    dest.write_text(text, encoding="utf-8")
    assert dest.read_text(encoding="utf-8") != SUBJECT.read_text(encoding="utf-8"), "scratch copy is identical"
    code, out = run([sys.executable, dest, "--help"])
    assert code == 0, "mutated copy does not run: %s" % out[-300:]
    return dest


def take(repo, out_root, subject=SUBJECT, reckon=None, extra=()):
    cmd = [sys.executable, subject, "take", "--out-root", out_root,
           "--reckon", str(reckon or REAL_RECKON)] + list(extra)
    return run(cmd, cwd=repo)


# ---------------------------------------------------------------------------
# the checks
# ---------------------------------------------------------------------------

def main():
    if not REAL_RECKON.is_file():
        print("no reckon at %s — cannot arm anything" % REAL_RECKON)
        return 1
    tmp = Path(tempfile.mkdtemp(prefix="reckoning-selftest-"))
    try:
        repo = make_repo(tmp / "repo")
        good_tool = make_tool(tmp / "tool-good")

        # --- the control: the whole command must succeed on good input -------
        code, out = take(repo, tmp / "out-control", reckon=good_tool)
        report("control · a clean tree and a current tool take a reading", code == 0, out[-300:])
        taken = sorted((tmp / "out-control").iterdir())
        first = taken[0] if taken else None
        report("control · the reading names its own commit",
               bool(first) and json.loads((first / "run.json").read_text())["tree"]["commit"],
               "no run.json")
        report("control · the first reading has nothing to compare against",
               "no earlier reading" in out, out[-200:])

        # --- 1. the tool's declared version ---------------------------------
        old_tool = make_tool(tmp / "tool-old", version="1.0.0")
        code, out = take(repo, tmp / "out-old", reckon=old_tool)
        armed_1 = report("gate · a tool below the version floor is refused",
                         code == 2 and "below the floor" in out, "exit %d: %s" % (code, out[-200:]))
        mutant = mutate_subject(tmp / "m1.py",
                                [("    if version < MIN_TOOL_VERSION:", "    if False:", 1)])
        code, _ = take(repo, tmp / "out-old-armed", subject=mutant, reckon=old_tool)
        report("arming · removing the floor lets the old tool through", code == 0, "exit %d" % code)

        # --- 2. the tool's actual class vocabulary --------------------------
        liar = make_tool(tmp / "tool-liar", version="1.1.0", drop_class="unjoined")
        code, out = take(repo, tmp / "out-liar", reckon=liar)
        report("gate · a tool whose partition lacks a class is refused",
               code == 2 and "does not carry the current partition" in out,
               "exit %d: %s" % (code, out[-200:]))
        mutant = mutate_subject(tmp / "m2.py",
                                [("    missing = REQUIRED_CLASSES - classes", "    missing = set()", 1)])
        code, _ = take(repo, tmp / "out-liar-armed", subject=mutant, reckon=liar)
        report("arming · removing the vocabulary check lets the liar through", code == 0, "exit %d" % code)

        # --- 3. the tool must carry a ratchet -------------------------------
        noratchet = make_tool(tmp / "tool-noratchet", drop_ratchet=True)
        code, out = take(repo, tmp / "out-noratchet", reckon=noratchet)
        report("gate · a tool with no ratchet is refused",
               code == 2 and "no ratchet" in out, "exit %d: %s" % (code, out[-200:]))

        # --- 4. a reading over an uncommitted tree cannot name itself -------
        (repo / "docs/test-campaign/cases.json").write_text(
            json.dumps(CASES + [{"id": "CASE-3", "req": "REQ-1", "surface": "SURF-1",
                                 "oracle": "outcome", "status": "pass", "evidence": ["f"],
                                 "armed": True, "note": "uncommitted"}]), encoding="utf-8")
        code, out = take(repo, tmp / "out-dirty", reckon=good_tool)
        report("gate · uncommitted inputs refuse to be named by a commit",
               code == 2 and "cannot be named by a commit" in out, "exit %d: %s" % (code, out[-200:]))
        code, out = take(repo, tmp / "out-dirty-allowed", reckon=good_tool, extra=["--allow-dirty"])
        dirty_dir = sorted((tmp / "out-dirty-allowed").iterdir()) if (tmp / "out-dirty-allowed").exists() else []
        named = json.loads((dirty_dir[0] / "run.json").read_text())["tree"]["tree_named"] if dirty_dir else True
        report("gate · --allow-dirty takes the reading and marks it unnamed",
               code == 0 and named is False, "exit %d, tree_named %r" % (code, named))
        mutant = mutate_subject(tmp / "m4.py", [("    if dirty_paths:", "    if False:", 1)])
        code, _ = take(repo, tmp / "out-dirty-armed", subject=mutant, reckon=good_tool)
        report("arming · removing the dirty check publishes the unnamed reading",
               code == 0, "exit %d" % code)
        run(["git", "checkout", "--", "docs/test-campaign/cases.json"], cwd=repo)

        # --- 5. compare declines a run with no provenance -------------------
        a = sorted((tmp / "out-control").iterdir())[0]
        run(["git", "commit", "-q", "--allow-empty", "-m", "second"], cwd=repo)
        code, out = take(repo, tmp / "out-control", reckon=good_tool)
        report("control · a second reading compares against the first",
               code == 0 and "wrote" in out and "delta.md" in out, "exit %d: %s" % (code, out[-300:]))
        b = [d for d in sorted((tmp / "out-control").iterdir()) if d != a][0]

        stripped = tmp / "no-provenance"
        shutil.copytree(a, stripped)
        (stripped / "run.json").unlink()
        code, out = run([sys.executable, SUBJECT, "compare", stripped, b, "--repo", repo,
                         "--reckon", good_tool], cwd=repo)
        report("gate · a reading with no provenance is not differenced",
               code == 2 and "carries no run.json" in out, "exit %d: %s" % (code, out[-200:]))
        mutant = mutate_subject(tmp / "m5.py",
                                [('        if not (d / "run.json").is_file():', "        if False:", 1)])
        code, out = run([sys.executable, mutant, "compare", stripped, b, "--repo", repo,
                         "--reckon", good_tool], cwd=repo)
        report("arming · with the provenance check gone the refusal is replaced by a crash",
               code == 1 and "FileNotFoundError" in out and "run.json" in out,
               "exit %d: %s" % (code, out[-160:]))

        # --- 6. compare declines an unnamed reading -------------------------
        unnamed = tmp / "unnamed"
        shutil.copytree(a, unnamed)
        rec = json.loads((unnamed / "run.json").read_text())
        rec["tree"]["tree_named"] = False
        (unnamed / "run.json").write_text(json.dumps(rec), encoding="utf-8")
        code, out = run([sys.executable, SUBJECT, "compare", unnamed, b, "--repo", repo,
                         "--reckon", good_tool], cwd=repo)
        report("gate · an unnamed reading is a reading, not a baseline",
               code == 2 and "unnamed tree" in out, "exit %d: %s" % (code, out[-200:]))
        mutant = mutate_subject(tmp / "m6.py",
                                [('        if not (rec.get("tree") or {}).get("tree_named"):',
                                  "        if False:", 1)])
        code, out = run([sys.executable, mutant, "compare", unnamed, b, "--repo", repo,
                         "--reckon", good_tool], cwd=repo)
        report("arming · removing the unnamed check differences it anyway",
               code == 0, "exit %d: %s" % (code, out[-160:]))

        # --- 7. the tool cannot be held constant ----------------------------
        stale = tmp / "stale-commit"
        shutil.copytree(a, stale)
        rec = json.loads((stale / "run.json").read_text())
        rec["tool"]["version"] = "1.1.1"          # different tool ⇒ a control is required
        rec["tree"]["commit"] = "0" * 40           # and its tree is not in this repository
        (stale / "run.json").write_text(json.dumps(rec), encoding="utf-8")
        code, out = run([sys.executable, SUBJECT, "compare", stale, b, "--repo", repo,
                         "--reckon", good_tool], cwd=repo)
        report("gate · an unresolvable earlier commit refuses the delta",
               code == 2 and "cannot resolve" in out, "exit %d: %s" % (code, out[-200:]))
        rec["tree"]["commit"] = json.loads((a / "run.json").read_text())["tree"]["commit"]
        (stale / "run.json").write_text(json.dumps(rec), encoding="utf-8")
        code, out = run([sys.executable, SUBJECT, "compare", stale, b, "--repo", repo,
                         "--reckon", good_tool], cwd=repo)
        report("two-way · a resolvable earlier commit is decomposed instead",
               code == 0 and json.loads((b / "delta.json").read_text())["attribution"] == "decomposed",
               "exit %d: %s" % (code, out[-200:]))

        # --- 7b. the control must be built by the current reading's own tool ---
        third = tmp / "third-tool"
        shutil.copytree(a, third)
        rec = json.loads((third / "run.json").read_text())
        rec["tool"]["version"] = "1.1.0"
        (third / "run.json").write_text(json.dumps(rec), encoding="utf-8")
        futures = json.loads((b / "run.json").read_text())
        futures["tool"]["version"] = "1.2.0"
        (b / "run.json").write_text(json.dumps(futures), encoding="utf-8")
        code, out = run([sys.executable, SUBJECT, "compare", third, b, "--repo", repo,
                         "--reckon", good_tool], cwd=repo)
        report("gate · a control built by a third tool is refused",
               code == 2 and "belongs to" in out, "exit %d: %s" % (code, out[-200:]))
        futures["tool"]["version"] = "1.1.0"
        (b / "run.json").write_text(json.dumps(futures), encoding="utf-8")
        code, out = run([sys.executable, SUBJECT, "compare", third, b, "--repo", repo,
                         "--reckon", good_tool], cwd=repo)
        report("two-way · with the versions agreeing the same pair compares",
               code == 0, "exit %d: %s" % (code, out[-200:]))

        # --- 8. the ratchet ------------------------------------------------
        violating = tmp / "violating"
        shutil.copytree(b, violating)
        led = json.loads((violating / "ledger.json").read_text())
        moved = 0
        for row in led["rows"]:
            if row["id"] == "REQ-2":
                row["class"], row["is_work_item"] = "verified-done", False
                moved += 1
        assert moved == 1, "the ratchet fixture did not move a row (moved %d)" % moved
        (violating / "ledger.json").write_text(json.dumps(led), encoding="utf-8")
        code, out = run([sys.executable, SUBJECT, "compare", a, violating, "--repo", repo,
                         "--reckon", good_tool], cwd=repo)
        report("gate · a row leaving unmeasured with no evidence exits 3",
               code == 3 and "RATCHET" in out and "REQ-2" in out, "exit %d: %s" % (code, out[-240:]))
        report("gate · the violation is written into the report, not only printed",
               (violating / "delta.md").is_file()
               and "silent transition" in (violating / "delta.md").read_text(),
               "no violation in delta.md")
        code, out = run([sys.executable, SUBJECT, "compare", a, b, "--repo", repo,
                         "--reckon", good_tool], cwd=repo)
        report("two-way · the same pair unedited ratchets clean",
               code == 0 and "clean" in out, "exit %d: %s" % (code, out[-200:]))

        # --- 9. the report leads with movement ------------------------------
        headings = re.findall(r"^## (.+)$", (b / "delta.md").read_text(encoding="utf-8"), re.M)
        report("gate · the report's first section is what moved",
               bool(headings) and headings[0] == "What moved", str(headings[:2]))
        report("gate · totals come last",
               bool(headings) and headings[-1] == "Totals, last", str(headings[-2:]))
        report("two-way · the ordering check fails on a report that leads with totals",
               re.findall(r"^## (.+)$", "## Totals, last\n\n## What moved\n", re.M)[0] != "What moved")

        # --- 10. reckon's own gate is not swallowed -------------------------
        broken = make_tool(tmp / "tool-badgate")
        text = broken.read_text(encoding="utf-8")
        needle = "def gate(ledger, weak_join_ratio=0.5):"
        assert text.count(needle) == 1
        text = text.replace(needle, needle + '\n    return [("conservation", "fixture forced")], []', 1)
        broken.write_text(text, encoding="utf-8")
        code, out = run([sys.executable, broken, "check",
                         str(a / "ledger.json")], cwd=repo)
        assert code == 1, "the forced-violation tool did not fail its own check (exit %d)" % code
        code, out = take(repo, tmp / "out-badgate", reckon=broken)
        report("gate · a ledger failing reckon's own gate is not reported clean",
               code != 0 and "did not come back clean" in out, "exit %d: %s" % (code, out[-200:]))

    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    print("")
    print("reckoning selftest: %d checks, %d failed" % (CHECKS, len(FAILURES)))
    for f in FAILURES:
        print("  · %s" % f)
    return 1 if FAILURES else 0


if __name__ == "__main__":
    sys.exit(main())
