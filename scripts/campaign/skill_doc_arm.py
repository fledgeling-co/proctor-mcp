#!/usr/bin/env python3
"""PRO-0085 CASE-0371: prove every check in `skill_doc_measure.py` can report FAIL.

Each check gets a mutation that breaks the one thing it claims to watch, applied
to a *scratch copy* of the skill and the catalogue. The live skill is never
written, because the previous attempt at this armed three checks by editing the
real files and was killed between the mutation and the revert, leaving every
project on this machine reading a skill whose guest section was headed
`## `proctor_ARMING`` and whose two-guest cap had been replaced by a placeholder.

A check that stays PASS under its own mutation is reported as NOT ARMED and the
script exits 1: three checks in the first version of this instrument were
satisfied by text that could not go away.

    python3 scripts/campaign/skill_doc_arm.py
"""
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
MEASURE = HERE / "skill_doc_measure.py"
SKILL = Path("/Users/lukerhodes/Dev/fledgeling-plugins/plugins/proctor/skills/proctor")
CAT = Path(__file__).resolve().parents[2] / "Sources/ProctorCore/ToolCatalogue.swift"

TOOLS, SKILLMD, CATALOGUE = "tools", "skill", "catalogue"


def sub(old, new, count=1):
    """Replace `old`, tolerating the line wrapping the source files are written at.

    The measurement flattens whitespace before matching prose, so a claim it
    reads as one sentence may sit across two lines in the file. A mutation that
    matched only the unwrapped form silently failed to arm the three checks
    whose sentences happen to wrap.
    """
    pattern = re.compile(r"\s+".join(re.escape(w) for w in old.split()))
    def apply(text):
        text, n = pattern.subn(new.replace("\\", "\\\\"), text)
        if n < count:
            raise AssertionError(f"expected >={count} match of {old!r}, found {n}")
        return text
    return apply


def full_row(replacement):
    """Rewrite only the `| \\`full\\` |` row of the profile table."""
    def apply(text):
        out, hit = [], 0
        for line in text.splitlines(keepends=True):
            if line.startswith("| `full` |"):
                line, hit = replacement(line), hit + 1
            out.append(line)
        assert hit == 1, f"full row matched {hit} times"
        return "".join(out)
    return apply


MUTATIONS = [
    ("tools.md names every shipped tool", TOOLS, sub("proctor_policy", "policyTool", 1)),
    ("tools.md names no tool the server lacks", TOOLS, sub("## Reading results honestly", "`proctor_bogus`\n\n## Reading results honestly")),
    ("catalogue ships 21", CATALOGUE, sub('name: "proctor_zoom"', 'name: "proctorZoom"')),
    ("tools.md specifies 15 sections", TOOLS, sub("\n## `proctor_wait`", "\n### `proctor_wait`")),
    ("proctor_guest has a specified section", TOOLS, sub("\n## `proctor_guest`", "\n## The guest tool")),
    ("tools.md states the count the catalogue ships", TOOLS, sub("ships **21 tools**", "ships **20 tools**")),
    ("full profile row totals 21", TOOLS, full_row(lambda l: l.replace("| 21 |", "| 20 |"))),
    ("guest listed in full profile adds", TOOLS, full_row(lambda l: l.replace(" `guest`", ""))),
    ("all three providers named", TOOLS, sub("prlctl", "parallels-cli", 1)),
    ("SKILL.md has a guest lane section", SKILLMD, sub("\n## The guest lane", "\n## The VM lane")),
    ("description names the guest lane", SKILLMD, sub("virtual-machine guests", "VM guests", 1)),
    ("description distinguishes delegated", SKILLMD, sub("delegated to coordinates", "limited to coordinates", 1)),
    ("nothing provisions, stated in both", TOOLS, sub("Nothing here provisions a guest", "Nothing provisions a guest", 1)),
    ("no provision action documented", TOOLS, sub("## Reading results honestly", "`provision`\n\n## Reading results honestly")),
    ("two-guest cap survives in SKILL.md", SKILLMD, sub("caps concurrent macOS guests at two", "limits macOS guests to two")),
    ("cap sits under a scale question", SKILLMD, sub("How many guests at once? Two.", "How many at once? Two.")),
    ("tahoe stated as measurement", TOOLS, sub("both still open", "both open", 1)),
    ("status osVersion honesty stated", TOOLS, sub("`unknown` with the reason where it cannot", "`unknown` otherwise", 1)),
]


def measure(skill_dir, cat_file):
    r = subprocess.run([sys.executable, str(MEASURE), "--skill", str(skill_dir),
                        "--catalogue", str(cat_file)], capture_output=True, text=True)
    pairs = re.findall(r"^(PASS|FAIL)  (.+?)(?:   \[.*\])?$", r.stdout, re.M)
    return {name: verdict for verdict, name in pairs}, r.stdout


def main():
    baseline, out = measure(SKILL, CAT)
    unarmed = [n for n, ok in baseline.items() if ok != "PASS"]
    if unarmed:
        print("baseline is not green; arming is meaningless against it:")
        print(out)
        return 1
    print(f"baseline: {len(baseline)}/{len(baseline)} PASS\n")

    failures = []
    for name, target, mutate in MUTATIONS:
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp) / "skill"
            (root / "references").mkdir(parents=True)
            shutil.copy(SKILL / "SKILL.md", root / "SKILL.md")
            shutil.copy(SKILL / "references" / "tools.md", root / "references" / "tools.md")
            cat = Path(tmp) / "ToolCatalogue.swift"
            shutil.copy(CAT, cat)
            path = {TOOLS: root / "references" / "tools.md",
                    SKILLMD: root / "SKILL.md", CATALOGUE: cat}[target]
            path.write_text(mutate(path.read_text()))
            after, _ = measure(root, cat)
            moved = sorted(n for n, ok in after.items() if ok == "FAIL")
            armed = after.get(name) == "FAIL"
            print(f"{'ARMED   ' if armed else 'NOT ARMED'} {name}")
            print(f"          mutation reds: {', '.join(moved) or 'nothing'}")
            if not armed:
                failures.append(name)

    print(f"\n{len(MUTATIONS) - len(failures)}/{len(MUTATIONS)} checks armed")
    if failures:
        print("could not be made to fail: " + "; ".join(failures))
    return 1 if failures else 0


sys.exit(main())
