#!/usr/bin/env python3
"""PRO-0085 CASE-0370/0371: measure the proctor skill against the shipped catalogue.

The skill lives in another repository, so this is a one-off measurement rather
than a suite predicate. Re-run it by hand when either tree moves.

    python3 scripts/campaign/skill_doc_measure.py [--skill DIR] [--catalogue FILE]

The two overrides exist so `skill_doc_arm.py` can mutate a scratch copy: arming
a check by breaking the live skill leaves every project on this machine reading
the broken version if the run is interrupted, which is how a `## `proctor_guest``
heading spent an hour reading `## `proctor_ARMING``.

Three earlier checks passed on text that could not have failed, and each is
written differently here:

  * `"tart" in tools` is satisfied by the word "s-tart". Providers are matched
    on a word boundary.
  * `"## The guest lane" in skill` was satisfied by a backticked cross-reference
    to that heading while the heading itself read something else. Headings are
    anchored to the start of a line.
  * nothing read the count the page states about itself, so "20 tools" survived
    a 17/17 run. The stated count is now read and compared to the catalogue.
"""
import re
import sys
from pathlib import Path

SKILL = Path("/Users/lukerhodes/Dev/fledgeling-plugins/plugins/proctor/skills/proctor")
CAT = Path("/Users/lukerhodes/Dev/proctor-mcp/.worktrees/PRO-0085/Sources/ProctorCore/ToolCatalogue.swift")
INTERNAL = {"proctor_hud", "proctor_queue", "proctor_recent_activity", "proctor_resource"}
SPECIFIED_SECTIONS = 15

argv = sys.argv[1:]
while argv:
    flag = argv.pop(0)
    if flag == "--skill":
        SKILL = Path(argv.pop(0))
    elif flag == "--catalogue":
        CAT = Path(argv.pop(0))
    else:
        sys.exit(f"unknown argument: {flag}")

cat = set(re.findall(r'name: "(proctor_[a-z_]+)"', CAT.read_text()))
tools_raw = (SKILL / "references" / "tools.md").read_text()
skill_raw = (SKILL / "SKILL.md").read_text()
# Line wrapping is not content: normalise whitespace before matching prose, so a
# claim does not read as absent because the sentence broke across two lines.
flat = lambda s: " ".join(s.split())
tools, skill = flat(tools_raw), flat(skill_raw)
doc = set(re.findall(r"proctor_[a-z_]+", tools_raw))

def heading(text, title):
    """A `## ` heading on its own line, not a mention of one inside a sentence."""
    return re.search(rf"^## {re.escape(title)}\s*$", text, re.M) is not None

def word(text, token):
    return re.search(rf"\b{re.escape(token)}\b", text) is not None

sections = len(re.findall(r"^## `proctor_", tools_raw, re.M))
stated = re.search(r"The server ships \*\*(\d+) tools\*\*", tools_raw)
stated_count = int(stated.group(1)) if stated else None
full_row = re.search(r"^\| `full` \|(.*?)\|\s*(\d+)\s*\|", tools_raw, re.M)
full_adds, full_total = (full_row.group(1), int(full_row.group(2))) if full_row else ("", None)

checks = [
    ("tools.md names every shipped tool", not (cat - doc), sorted(cat - doc)),
    ("tools.md names no tool the server lacks", (doc - cat) == INTERNAL, sorted(doc - cat)),
    ("catalogue ships 21", len(cat) == 21, len(cat)),
    (f"tools.md specifies {SPECIFIED_SECTIONS} sections", sections == SPECIFIED_SECTIONS, sections),
    ("proctor_guest has a specified section", heading(tools_raw, "`proctor_guest`"), None),
    ("tools.md states the count the catalogue ships", stated_count == len(cat), stated_count),
    ("full profile row totals 21", full_total == 21, full_total),
    ("guest listed in full profile adds", word(full_adds, "guest"), full_adds.strip()),
    ("all three providers named", all(word(tools, p) for p in ("lume", "prlctl", "tart")),
     [p for p in ("lume", "prlctl", "tart") if not word(tools, p)]),
    ("SKILL.md has a guest lane section", heading(skill_raw, "The guest lane"), None),
    ("description names the guest lane", "virtual-machine guests" in skill, None),
    ("description distinguishes delegated", "delegated to coordinates" in skill, None),
    ("nothing provisions, stated in both", "Nothing here provisions a guest" in tools
     and "Nothing here provisions a guest" in skill, None),
    ("no provision action documented", "provision`" not in tools and '"provision"' not in tools, None),
    ("two-guest cap survives in SKILL.md", "caps concurrent macOS guests at two" in skill, None),
    ("cap sits under a scale question", "How many guests at once? Two." in skill, None),
    ("tahoe stated as measurement", "both still open" in tools and "rendered normally" in tools, None),
    ("status osVersion honesty stated", "`unknown` with the reason where it cannot" in tools, None),
]
bad = 0
for name, ok, detail in checks:
    print(f"{'PASS' if ok else 'FAIL'}  {name}" + (f"   [{detail}]" if not ok and detail is not None else ""))
    bad += not ok
print(f"\n{len(checks) - bad}/{len(checks)} checks passed")
sys.exit(1 if bad else 0)
