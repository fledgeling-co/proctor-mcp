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
import importlib.util
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


def _subject_module():
    """The subject imported, so its own sweep() is what gets measured.

    A reimplementation of sweep() here would arm a copy rather than the tool.
    """
    spec = importlib.util.spec_from_file_location("_reckoning_subject", SUBJECT)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


_SUBJECT_MOD = _subject_module()
_sweep = _SUBJECT_MOD.sweep
_sha256_of = _SUBJECT_MOD.sha256_of
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

        # --- 11. the refusal names the path git named (DEF-206) -------------
        # `git()` strips its output, so the first porcelain line lost its leading
        # status space and the [3:] slice ate the first character of the path.
        # The refusal named `ocs/test-campaign/cases.json`, and --allow-dirty
        # wrote that phantom permanently into run.json.dirty_inputs.
        (repo / "docs/test-campaign/cases.json").write_text(
            json.dumps(CASES + [{"id": "CASE-4", "req": "REQ-1", "surface": "SURF-1",
                                 "oracle": "outcome", "status": "pass", "evidence": ["f"],
                                 "armed": True, "note": "modified, tracked, unstaged"}]),
            encoding="utf-8")
        porcelain = run(["git", "status", "--porcelain", "--",
                         "docs/test-campaign/cases.json"], cwd=repo)[1]
        report("fixture · the status line is the one that fires it (leading space)",
               porcelain.startswith(" M "), repr(porcelain[:40]))
        code, out = take(repo, tmp / "out-def206", reckon=good_tool)
        report("gate · the refusal names a path that exists on disk",
               code == 2 and "docs/test-campaign/cases.json" in out
               and "ocs/test-campaign/cases.json" not in out.replace("docs/test-campaign", ""),
               "exit %d: %s" % (code, out[-240:]))
        code, out = take(repo, tmp / "out-def206-dirty", reckon=good_tool,
                         extra=["--allow-dirty"])
        d206 = sorted((tmp / "out-def206-dirty").iterdir()) if (tmp / "out-def206-dirty").exists() else []
        recorded = json.loads((d206[0] / "run.json").read_text())["tree"]["dirty_inputs"] if d206 else []
        report("gate · --allow-dirty records a path the reader can open",
               recorded == ["docs/test-campaign/cases.json"]
               and (repo / recorded[0]).is_file() if recorded else False,
               "dirty_inputs %r" % (recorded,))
        # The mutation restores the pre-repair line verbatim, so this is the two-way
        # control across the repair rather than a check that merely passes now.
        mutant = mutate_subject(tmp / "m11.py", [(
            "    _, dirty_paths = porcelain_paths(repo, inputs)",
            '    code, dirty, _ = git(repo, "status", "--porcelain", "--", *inputs)\n'
            "    dirty_paths = [line[3:] for line in dirty.splitlines() if line.strip()]", 1)])
        code, out = take(repo, tmp / "out-def206-armed", subject=mutant, reckon=good_tool)
        report("arming · the pre-repair slice puts the phantom back in the refusal",
               code == 2 and "ocs/test-campaign/cases.json" in out,
               "exit %d: %s" % (code, out[-240:]))
        run(["git", "checkout", "--", "docs/test-campaign/cases.json"], cwd=repo)

        # --- 11b. every kind of status line, not the one the fixture ran -----
        # A repair proved on the path the harness happens to exercise, with
        # another path left undriven, is the failure mode this item was warned
        # about by name. `porcelain_paths` accepts six kinds of entry and the
        # check above drove one, so each is driven here and the pre-repair slice
        # is reintroduced against each.
        def _old_form(inputs):
            """The pre-repair parse, verbatim, for the same inputs."""
            code, dirty, _ = _SUBJECT_MOD.git(repo, "status", "--porcelain", "--", *inputs)
            return [line[3:] for line in dirty.splitlines() if line.strip()]

        run(["git", "checkout", "--", "."], cwd=repo)
        kinds = []
        # modified, tracked, unstaged — ` M path`
        (repo / "docs/test-campaign/cases.json").write_text(
            json.dumps(CASES + [{"id": "CASE-M", "req": "REQ-1", "surface": "SURF-1",
                                 "oracle": "outcome", "status": "pass", "evidence": ["f"],
                                 "armed": True, "note": "modified"}]), encoding="utf-8")
        kinds.append(("modified unstaged", ["docs/test-campaign/cases.json"],
                      ["docs/test-campaign/cases.json"]))
        # untracked — `?? path`
        (repo / "docs/test-campaign/new-file.json").write_text("{}", encoding="utf-8")
        kinds.append(("untracked", ["docs/test-campaign/new-file.json"],
                      ["docs/test-campaign/new-file.json"]))
        # staged addition — `A  path`
        (repo / "docs/test-campaign/added.json").write_text("{}", encoding="utf-8")
        run(["git", "add", "docs/test-campaign/added.json"], cwd=repo)
        kinds.append(("staged addition", ["docs/test-campaign/added.json"],
                      ["docs/test-campaign/added.json"]))
        # deleted — ` D path`
        (repo / "docs/test-campaign/campaign.json").unlink()
        kinds.append(("deleted", ["docs/test-campaign/campaign.json"],
                      ["docs/test-campaign/campaign.json"]))
        # renamed — `R  old -> new`, which names both sides on one line
        run(["git", "mv", "docs/features-to-triage/01-a-thing.md",
             "docs/features-to-triage/02-renamed.md"], cwd=repo)
        kinds.append(("renamed", ["docs/features-to-triage"],
                      ["docs/features-to-triage/02-renamed.md"]))
        # a non-ASCII path, which git prints C-quoted with octal escapes
        (repo / "docs/test-campaign/café.json").write_text("{}", encoding="utf-8")
        kinds.append(("quoted non-ASCII", ["docs/test-campaign/café.json"],
                      ["docs/test-campaign/café.json"]))

        wrong_before = []
        for label, inputs, expected in kinds:
            _, got = _SUBJECT_MOD.porcelain_paths(repo, inputs)
            report("gate · %s resolves to the path on disk" % label,
                   got == expected and all((repo / g).exists() or label == "deleted"
                                           for g in got),
                   "got %r, wanted %r" % (got, expected))
            if _old_form(inputs) != expected:
                wrong_before.append(label)
        # Four of the six moved and two did not, and naming which is the point: a
        # control that changes on every input is measuring the harness rather than
        # the repair. `??` and `A ` survive a strip intact, so an untracked file
        # and a staged addition were always parsed correctly — which is why the
        # defect went unnoticed and why the fixture had to be a modified tracked
        # file. The rename and the quoted path were wrong for their own reasons
        # rather than the strip's.
        report("arming · the pre-repair slice is wrong on four kinds and right on two",
               sorted(wrong_before) == ["deleted", "modified unstaged",
                                        "quoted non-ASCII", "renamed"],
               "wrong before the repair: %r" % (sorted(wrong_before),))
        run(["git", "reset", "-q", "--hard"], cwd=repo)
        for stray in ("docs/test-campaign/new-file.json", "docs/test-campaign/café.json"):
            (repo / stray).unlink(missing_ok=True)

        # --- 11c. every kind ISOLATED, and the rename forms 11b could not see -
        # 11b drove six kinds with the tree carrying all six at once, and its
        # arrow only ever sat inside a ` M` path. A rename DESTINATION holding
        # one was undriven — and the repair 11b was checking, split from the
        # RIGHT, is wrong on exactly that. `git mv src.md "stage-1 -> stage-2.md"`
        # gives `R  src.md -> "stage-1 -> stage-2.md"`, whose last ` -> ` is
        # inside the quoted destination, so the rsplit returned `stage-2.md"` and
        # `--allow-dirty` wrote that phantom permanently into
        # `run.json.dirty_inputs`, which is DEF-206's original harm re-created by
        # DEF-206's own repair. So the kinds are enumerated from
        # `porcelain_paths`' branches rather than from this file, each is driven
        # ALONE in a reset tree, and all three parses are computed against every
        # one: the pre-repair slice, the rsplit repair, and the code as it stands.
        def _rsplit_form(inputs):
            """The shipped repair this one replaces, verbatim."""
            _c, out, _e = _SUBJECT_MOD.git_raw(repo, "status", "--porcelain", "--", *inputs)
            got = []
            for line in out.splitlines():
                if len(line) < 4:
                    continue
                status, entry = line[:2], line[3:]
                if status[0] in "RC" and " -> " in entry:
                    entry = entry.rsplit(" -> ", 1)[1]
                entry = _SUBJECT_MOD.unquote_path(entry)
                if entry:
                    got.append(entry)
            return got

        run(["git", "reset", "-q", "--hard"], cwd=repo)
        run(["git", "clean", "-qfd"], cwd=repo)
        D, F = "docs/test-campaign", "docs/features-to-triage"
        for stem in ("src.md", "c-src.md", "sp.md"):
            (repo / F / stem).write_text("a rename source\n", encoding="utf-8")
        (repo / F / "a -> b.md").write_text("a source whose own name holds the arrow\n",
                                            encoding="utf-8")
        run(["git", "add", "-A"], cwd=repo)
        run(["git", "commit", "-q", "-m", "rename sources"], cwd=repo)

        def _mv(src, dst):
            return lambda: run(["git", "mv", "%s/%s" % (F, src), "%s/%s" % (F, dst)], cwd=repo)

        def _write(rel, body="{}"):
            return lambda: (repo / rel).write_text(body, encoding="utf-8")

        def _write_add(rel, body="{}"):
            def go():
                (repo / rel).write_text(body, encoding="utf-8")
                run(["git", "add", rel], cwd=repo)
            return go

        isolated = [
            # (label, setup, inputs, expected)
            ("modified unstaged", _write("%s/cases.json" % D, "[]"),
             ["%s/cases.json" % D], ["%s/cases.json" % D]),
            ("modified staged", _write_add("%s/cases.json" % D, "[]"),
             ["%s/cases.json" % D], ["%s/cases.json" % D]),
            ("untracked", _write("%s/new-file.json" % D),
             ["%s/new-file.json" % D], ["%s/new-file.json" % D]),
            ("staged addition", _write_add("%s/added.json" % D),
             ["%s/added.json" % D], ["%s/added.json" % D]),
            ("deleted unstaged", lambda: (repo / D / "campaign.json").unlink(),
             ["%s/campaign.json" % D], ["%s/campaign.json" % D]),
            ("deleted staged",
             lambda: run(["git", "rm", "-q", "%s/campaign.json" % D], cwd=repo),
             ["%s/campaign.json" % D], ["%s/campaign.json" % D]),
            ("untracked, quoted for a non-ASCII byte", _write("%s/café.json" % D),
             ["%s/café.json" % D], ["%s/café.json" % D]),
            ("untracked, quoted for a space", _write("%s/a name.json" % D),
             ["%s/a name.json" % D], ["%s/a name.json" % D]),
            ("rename, neither side quoted", _mv("01-a-thing.md", "02-renamed.md"),
             [F], ["%s/02-renamed.md" % F]),
            ("rename, destination quoted for an arrow in it",
             _mv("src.md", "stage-1 -> stage-2.md"),
             [F], ["%s/stage-1 -> stage-2.md" % F]),
            ("rename, source quoted for an arrow in it", _mv("a -> b.md", "plain.md"),
             [F], ["%s/plain.md" % F]),
            ("rename, both sides quoted for an arrow", _mv("a -> b.md", "c -> d.md"),
             [F], ["%s/c -> d.md" % F]),
            ("rename, destination quoted for a space only", _mv("sp.md", "two words.md"),
             [F], ["%s/two words.md" % F]),
        ]

        wrong_slice, wrong_rsplit, seen_raw = [], [], {}
        for label, setup, inputs, expected in isolated:
            run(["git", "reset", "-q", "--hard"], cwd=repo)
            run(["git", "clean", "-qfd"], cwd=repo)
            setup()
            seen_raw[label] = _SUBJECT_MOD.git_raw(
                repo, "status", "--porcelain", "--", *inputs)[1].rstrip("\n")
            _, got = _SUBJECT_MOD.porcelain_paths(repo, inputs)
            report("gate · isolated %s resolves to the path on disk" % label,
                   got == expected
                   and all((repo / g).exists() for g in got if "deleted" not in label),
                   "raw %r gave %r, wanted %r" % (seen_raw[label], got, expected))
            if _old_form(inputs) != expected:
                wrong_slice.append(label)
            if _rsplit_form(inputs) != expected:
                wrong_rsplit.append(label)

        # The record 11b wrote says the pre-repair slice is wrong on four kinds.
        # That is a statement about the six kinds 11b drove, not about the
        # population: enumerated from the code and isolated, thirteen kinds reach
        # `porcelain_paths` and the slice is wrong on NINE of them, from three
        # separate causes — two the strip (a leading-space status column), two
        # the quoting, and five the rename naming both sides on one line. The
        # four kinds it gets right are the four with neither a leading space, a
        # quote, nor an arrow.
        report("arming · the pre-repair slice is wrong on nine of the thirteen isolated kinds",
               sorted(wrong_slice) == sorted([
                   "modified unstaged", "deleted unstaged",
                   "untracked, quoted for a non-ASCII byte", "untracked, quoted for a space",
                   "rename, neither side quoted",
                   "rename, destination quoted for an arrow in it",
                   "rename, source quoted for an arrow in it",
                   "rename, both sides quoted for an arrow",
                   "rename, destination quoted for a space only"]),
               "wrong before the repair: %r" % (sorted(wrong_slice),))
        # And the shipped repair is wrong on exactly the two kinds whose LAST
        # ` -> ` is inside a quoted destination, which is the failure this block
        # exists for. Splitting from the right is not a repair, it is the same
        # defect aimed at a different input: `git()`'s strip and the rsplit both
        # publish a name nobody can open.
        report("arming · the rsplit repair is wrong on both arrow-in-destination renames",
               sorted(wrong_rsplit) == sorted([
                   "rename, destination quoted for an arrow in it",
                   "rename, both sides quoted for an arrow"]),
               "wrong under the rsplit: %r" % (sorted(wrong_rsplit),))
        report("fixture · the arrow-in-destination line is the one git actually writes",
               seen_raw["rename, destination quoted for an arrow in it"].endswith(
                   'src.md -> "docs/features-to-triage/stage-1 -> stage-2.md"'),
               repr(seen_raw.get("rename, destination quoted for an arrow in it")))

        # The out-of-family review claimed an UNSTAGED rename arrives as ` R`,
        # which would put a rename entry in the second status column. It does not
        # reproduce: git 2.50.1 has no rename to report until one side is staged,
        # so a plain `mv` is a deletion and an untracked file. Driven rather than
        # argued, because the guard above reads both columns on the strength of
        # it and a guard resting on an unchecked claim is the shape of this item.
        run(["git", "reset", "-q", "--hard"], cwd=repo)
        run(["git", "clean", "-qfd"], cwd=repo)
        (repo / F / "01-a-thing.md").rename(repo / F / "03-moved-on-disk.md")
        raw_unstaged = _SUBJECT_MOD.git_raw(
            repo, "status", "--porcelain", "--", F)[1].rstrip("\n")
        _, got_unstaged = _SUBJECT_MOD.porcelain_paths(repo, [F])
        report("gate · an unstaged rename is a deletion and an untracked file, not ` R`",
               sorted(l[:2] for l in raw_unstaged.splitlines()) == [" D", "??"],
               "raw %r" % (raw_unstaged,))
        report("gate · and both halves of it resolve to names on disk or off it",
               sorted(got_unstaged) == ["%s/01-a-thing.md" % F, "%s/03-moved-on-disk.md" % F]
               and (repo / F / "03-moved-on-disk.md").is_file()
               and not (repo / F / "01-a-thing.md").exists(),
               "got %r" % (sorted(got_unstaged),))

        # --- 11d. the other quoting mode, which is a git config not a filename -
        # Out-of-family review, PRO-0106. `core.quotePath` decides whether git
        # escapes non-ASCII bytes in octal or writes the UTF-8 through literally,
        # and it is a setting a user commonly has in their own gitconfig. The old
        # `unicode_escape` round trip decoded the octal form and raised
        # UnicodeDecodeError on the literal one, whose except branch returned the
        # entry WITH ITS QUOTES ON \u2014 an unopenable name, which is DEF-206's harm
        # reached by a config rather than by a path. Both modes are driven here,
        # and the pre-repair round trip is reintroduced against each.
        def _old_unquote(entry):
            """The pre-repair unquote, verbatim."""
            if len(entry) >= 2 and entry[0] == '"' and entry[-1] == '"':
                try:
                    return (entry[1:-1].encode("ascii", "backslashreplace")
                            .decode("unicode_escape").encode("latin-1").decode("utf-8"))
                except (UnicodeDecodeError, UnicodeEncodeError):
                    return entry
            return entry

        octal_form = '"docs/test-campaign/caf\\303\\251 latte.json"'
        literal_form = '"docs/test-campaign/café latte.json"'
        want = "docs/test-campaign/café latte.json"
        report("gate · the octal-escaped form unquotes to the path on disk",
               _SUBJECT_MOD.unquote_path(octal_form) == want,
               repr(_SUBJECT_MOD.unquote_path(octal_form)))
        report("gate · and so does the literal-UTF-8 form the other config writes",
               _SUBJECT_MOD.unquote_path(literal_form) == want,
               repr(_SUBJECT_MOD.unquote_path(literal_form)))
        report("arming · the pre-repair round trip returns the literal form still quoted",
               _old_unquote(octal_form) == want and _old_unquote(literal_form) == literal_form,
               "octal %r, literal %r" % (_old_unquote(octal_form), _old_unquote(literal_form)))
        for label, escape in (('a quote', 'a\\"b.json'), ('a backslash', 'a\\\\b.json'),
                              ('a tab', 'a\\tb.json')):
            got = _SUBJECT_MOD.unquote_path('"%s"' % escape)
            report("gate · %s survives the unquote as one character" % label,
                   len(got) == len("ab.json") + 1 and got.endswith("b.json"), repr(got))

        # End to end under the other config, because a unit check on the helper
        # is not the thing that publishes the name.
        run(["git", "reset", "-q", "--hard"], cwd=repo)
        run(["git", "clean", "-qfd"], cwd=repo)
        run(["git", "config", "core.quotePath", "false"], cwd=repo)
        (repo / "docs/test-campaign/café latte.json").write_text("{}", encoding="utf-8")
        raw_literal = _SUBJECT_MOD.git_raw(
            repo, "status", "--porcelain", "--", "docs/test-campaign")[1].rstrip("\n")
        _, got_literal = _SUBJECT_MOD.porcelain_paths(repo, ["docs/test-campaign"])
        report("fixture · quotePath=false writes the UTF-8 through and quotes for the space",
               raw_literal.endswith('"docs/test-campaign/café latte.json"'), repr(raw_literal))
        report("gate · and porcelain_paths resolves it to a file that opens",
               got_literal == [want] and (repo / want).is_file(),
               "got %r" % (got_literal,))
        run(["git", "config", "--unset", "core.quotePath"], cwd=repo)
        (repo / "docs/test-campaign/café latte.json").unlink()
        run(["git", "reset", "-q", "--hard"], cwd=repo)
        run(["git", "clean", "-qfd"], cwd=repo)

        # End to end, because the harm is what --allow-dirty writes down. The
        # phantom is permanent in run.json, so a parse that is only right in a
        # unit check is not the thing that was broken.
        run(["git", "reset", "-q", "--hard"], cwd=repo)
        run(["git", "clean", "-qfd"], cwd=repo)
        run(["git", "mv", "%s/src.md" % F, "%s/stage-1 -> stage-2.md" % F], cwd=repo)
        code, out = take(repo, tmp / "out-arrow", reckon=good_tool, extra=["--allow-dirty"])
        runs = sorted((tmp / "out-arrow").iterdir()) if (tmp / "out-arrow").exists() else []
        recorded = (json.loads((runs[0] / "run.json").read_text())["tree"]["dirty_inputs"]
                    if runs else [])
        report("gate · --allow-dirty records the renamed path a reader can open",
               recorded == ["%s/stage-1 -> stage-2.md" % F] and (repo / recorded[0]).is_file()
               if recorded else False,
               "exit %d, dirty_inputs %r" % (code, recorded))
        rsplit_mutant = mutate_subject(tmp / "m11c.py", [(
            '        if "R" in status or "C" in status:\n'
            "            entry = rename_destination(entry)",
            '        if status[0] in "RC" and " -> " in entry:\n'
            '            entry = entry.rsplit(" -> ", 1)[1]', 1)])
        code, out = take(repo, tmp / "out-arrow-armed", subject=rsplit_mutant,
                         reckon=good_tool, extra=["--allow-dirty"])
        runs = sorted((tmp / "out-arrow-armed").iterdir()) if (tmp / "out-arrow-armed").exists() else []
        armed_recorded = (json.loads((runs[0] / "run.json").read_text())["tree"]["dirty_inputs"]
                          if runs else [])
        report("arming · the rsplit repair writes the phantom permanently into run.json",
               armed_recorded == ['stage-2.md"'] and not (repo / 'stage-2.md"').exists(),
               "exit %d, dirty_inputs %r" % (code, armed_recorded))
        run(["git", "reset", "-q", "--hard"], cwd=repo)
        run(["git", "clean", "-qfd"], cwd=repo)

        # --- 12. the witness records what sweep() measured (DEF-205) ---------
        # sweep() computes a byte count and sha256 per file and cmd_take kept only
        # the names, so the witness could say two files appeared and not what was
        # in them.
        latest = sorted((tmp / "out-control").iterdir())[-1]
        effect = json.loads((latest / "run.json").read_text())["effect"]
        written = effect.get("written") or {}
        digests_hold = bool(written) and all(
            isinstance(v, dict) and v.get("sha256") == _sha256_of(latest / n)
            and v.get("bytes") == (latest / n).stat().st_size
            for n, v in written.items())
        report("gate · the effect records a byte count and digest for every file written",
               digests_hold and sorted(written) == effect["files_written"],
               "written %r" % (list(written)[:3],))
        mutant = mutate_subject(tmp / "m12.py", [(
            '                   "written": {n: after[n] for n in written},',
            '                   "written": {},', 1)])
        run(["git", "commit", "-q", "--allow-empty", "-m", "third"], cwd=repo)
        code, out = take(repo, tmp / "out-def205-armed", subject=mutant, reckon=good_tool)
        armed_dir = sorted((tmp / "out-def205-armed").iterdir()) if (tmp / "out-def205-armed").exists() else []
        blind = json.loads((armed_dir[0] / "run.json").read_text())["effect"]["written"] if armed_dir else None
        report("arming · dropping the digests leaves the witness naming files only",
               code == 0 and blind == {}, "exit %d, written %r" % (code, blind))

        # --- 13. a file rewritten between sweeps is not invisible (DEF-205) --
        # The half a name-only witness could not see at all: same name, different
        # content, absent from set(after) - set(before) entirely.
        scratch = tmp / "sweep-scratch"
        scratch.mkdir()
        (scratch / "ledger.json").write_text("one", encoding="utf-8")
        before_sweep = _sweep(scratch)
        (scratch / "ledger.json").write_text("two", encoding="utf-8")   # same length
        after_sweep = _sweep(scratch)
        appeared = sorted(set(after_sweep) - set(before_sweep))
        moved = sorted(n for n in set(after_sweep) & set(before_sweep)
                       if after_sweep[n] != before_sweep[n])
        report("gate · a rewrite of equal length is invisible to a name-only diff",
               appeared == [], "appeared %r" % (appeared,))
        report("gate · the digest diff names the file the name diff missed",
               moved == ["ledger.json"]
               and before_sweep["ledger.json"]["sha256"] != after_sweep["ledger.json"]["sha256"],
               "moved %r" % (moved,))
        # The third kind the record now carries: a file the build stopped writing.
        # Driven here rather than left to the one path the fixture happened to run.
        (scratch / "gone.json").write_text("here", encoding="utf-8")
        with_gone = _sweep(scratch)
        (scratch / "gone.json").unlink()
        without = _sweep(scratch)
        report("gate · a file that stopped being written is named by the digest diff",
               sorted(set(with_gone) - set(without)) == ["gone.json"]
               and with_gone["gone.json"]["sha256"],
               "removed %r" % (sorted(set(with_gone) - set(without)),))
        latest_effect = json.loads((latest / "run.json").read_text())["effect"]
        report("gate · the record carries all three kinds, not only the one it ran",
               {"written", "rewritten", "removed"} <= set(latest_effect),
               "effect keys %r" % (sorted(latest_effect),))

        # --- 14. the cadence note's count of this file ----------------------
        # DEF-193 was the fifth stale count in a document nothing read. A number
        # a document states about an instrument is a number the instrument can
        # read back.
        cadence = HERE.parents[1] / "docs/reckoning/CADENCE.md"
        stated = re.search(r"(\d+) checks", cadence.read_text(encoding="utf-8")) if cadence.is_file() else None
        expected = CHECKS + 1
        report("gate · the cadence note states this file's own check count",
               bool(stated) and int(stated.group(1)) == expected,
               "CADENCE.md says %s, this run has %d" % (stated.group(1) if stated else "nothing", expected))

    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    print("")
    print("reckoning selftest: %d checks, %d failed" % (CHECKS, len(FAILURES)))
    for f in FAILURES:
        print("  · %s" % f)
    return 1 if FAILURES else 0


if __name__ == "__main__":
    sys.exit(main())
