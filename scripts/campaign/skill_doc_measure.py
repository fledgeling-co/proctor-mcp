#!/usr/bin/env python3
"""PRO-0085 CASE-0370/0371: measure the proctor skill against the shipped catalogue.

The skill lives in another repository, so this is a one-off measurement rather
than a suite predicate. Re-run it by hand when either tree moves.

    python3 scripts/campaign/skill_doc_measure.py [--skill DIR] [--catalogue FILE]

The two overrides exist so `skill_doc_arm.py` can mutate a scratch copy: arming
a check by breaking the live skill leaves every project on this machine reading
the broken version if the run is interrupted, which is how a `## `proctor_guest``
heading spent an hour reading `## `proctor_ARMING``.

Five checks have passed on text that could not have failed, and each is written
differently here:

  * `"tart" in tools` is satisfied by the word "s-tart". Providers are matched
    on a word boundary.
  * `"## The guest lane" in skill` was satisfied by a backticked cross-reference
    to that heading while the heading itself read something else. Headings are
    anchored to the start of a line.
  * nothing read the count the page states about itself, so "20 tools" survived
    a 17/17 run. Every count either file states is now read and compared to the
    catalogue: the headline, the profile table's four row totals, the
    specified/named split and its restatement, and SKILL.md's two.
  * the two description claims tested membership against the whole of SKILL.md,
    so a phrase anywhere in 900 lines of body satisfied a claim about the 300
    words a host reads to route. Both are anchored to the frontmatter
    `description:` value.
"""
import re
import sys
from pathlib import Path

SKILL = Path("/Users/lukerhodes/Dev/fledgeling-plugins/plugins/proctor/skills/proctor")
CAT = Path("/Users/lukerhodes/Dev/proctor-mcp/.worktrees/PRO-0085/Sources/ProctorCore/ToolCatalogue.swift")
INTERNAL = {"proctor_hud", "proctor_queue", "proctor_recent_activity", "proctor_resource"}
SPECIFIED_SECTIONS = 15
# The counts these two files spell out in words rather than digits.
NUM = {"six": 6, "eight": 8, "ten": 10, "thirteen": 13, "fifteen": 15,
       "twenty": 20, "twenty-one": 21, "twenty-two": 22}

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


def description(text):
    """The frontmatter `description:` value, flattened — not the whole file.

    A claim about the description is a claim about the few hundred words a host
    reads to decide whether to load this skill. Matching the whole of SKILL.md
    lets a phrase 800 lines into the body satisfy it, which is how both
    description checks passed without watching anything.
    """
    fm = re.match(r"---\n(.*?)\n---(?:\n|$)", text, re.S)
    if not fm:
        return ""
    lines = fm.group(1).splitlines()
    for i, line in enumerate(lines):
        if not line.startswith("description:"):
            continue
        rest = line[len("description:"):].strip()
        if rest and rest[0] not in "|>":
            return flat(rest)
        block = []
        for nxt in lines[i + 1:]:
            if nxt.strip() and not nxt[:1].isspace():
                break
            block.append(nxt)
        return flat("\n".join(block))
    return ""


desc = description(skill_raw)


def heading(text, title):
    """A `## ` heading on its own line, not a mention of one inside a sentence."""
    return re.search(rf"^## {re.escape(title)}\s*$", text, re.M) is not None


def word(text, token):
    return re.search(rf"\b{re.escape(token)}\b", text) is not None


def num(token):
    """The integer a count word names, or None when it names no number here."""
    return NUM.get((token or "").lower())


def group(match, n, cast=int):
    return cast(match.group(n)) if match else None


def profile_rows(text):
    """Each profile row as (name, tools named up to and including it, stated total).

    The profiles nest, so a row's total is the running count of the backticked
    names in every Adds cell down to it.
    """
    rows, running = [], 0
    for name, adds, total in re.findall(
            r"^\| `(ax|core|scripting|full)` \|(.*?)\|\s*(\d+)\s*\|", text, re.M):
        running += len(re.findall(r"`[a-z_]+`", adds))
        rows.append((name, running, int(total)))
    return rows


sections = len(re.findall(r"^## `proctor_", tools_raw, re.M))
stated_count = group(re.search(r"The server ships \*\*(\d+) tools\*\*", tools_raw), 1)
rows = profile_rows(tools_raw)
stated_total = {name: total for name, _, total in rows}
full_row = re.search(r"^\| `full` \|(.*?)\|\s*(\d+)\s*\|", tools_raw, re.M)
full_adds = full_row.group(1) if full_row else ""

# The four remaining count sites: tools.md's specified/named split and its
# restatement, and the two SKILL.md states in prose.
split = re.search(r"This page specifies the (\d+) tools a campaign uses directly\. "
                  r"(\w+) more are named", tools)
restated = re.search(r"(\w+) plus (\w+) is the (\d+) above", tools)
skill_words = re.search(r"rather than all ([a-z]+(?:-[a-z]+)?)\b", skill)
skill_depth = re.search(r"the (\d+) tools the server ships", skill)
core_words_tools = re.search(r"`core` is the ([a-z]+(?:-[a-z]+)?) that", tools)
core_words_skill = re.search(r"advertises the ([a-z]+(?:-[a-z]+)?) tools that drive a Mac", skill)

split_pair = (group(split, 1), num(split.group(2)) if split else None)
restated_triple = (num(restated.group(1)) if restated else None,
                   num(restated.group(2)) if restated else None,
                   group(restated, 3))
bad_rows = [(n, named, total) for n, named, total in rows if named != total]

checks = [
    ("tools.md names every shipped tool", not (cat - doc), sorted(cat - doc)),
    ("tools.md names no tool the server lacks", (doc - cat) == INTERNAL, sorted(doc - cat)),
    ("catalogue ships 21", len(cat) == 21, len(cat)),
    (f"tools.md specifies {SPECIFIED_SECTIONS} sections", sections == SPECIFIED_SECTIONS, sections),
    ("proctor_guest has a specified section", heading(tools_raw, "`proctor_guest`"), None),
    ("tools.md states the count the catalogue ships", stated_count == len(cat), stated_count),
    ("full profile row totals the catalogue", stated_total.get("full") == len(cat),
     stated_total.get("full")),
    ("every profile row totals the tools it names", not bad_rows and len(rows) == 4,
     bad_rows or f"{len(rows)} rows"),
    ("tools.md's specified-plus-named split is the catalogue",
     split_pair == (SPECIFIED_SECTIONS, len(cat) - SPECIFIED_SECTIONS), split_pair),
    ("tools.md restates the split as the catalogue count",
     restated_triple == (SPECIFIED_SECTIONS, len(cat) - SPECIFIED_SECTIONS, len(cat)),
     restated_triple),
    ("SKILL.md states the catalogue count in words",
     num(skill_words.group(1)) == len(cat) if skill_words else False,
     skill_words.group(1) if skill_words else None),
    ("SKILL.md's depth line states the catalogue count", group(skill_depth, 1) == len(cat),
     group(skill_depth, 1)),
    ("both files state the core profile's size",
     num(core_words_tools.group(1) if core_words_tools else None) == stated_total.get("core")
     and num(core_words_skill.group(1) if core_words_skill else None) == stated_total.get("core"),
     [core_words_tools and core_words_tools.group(1),
      core_words_skill and core_words_skill.group(1), stated_total.get("core")]),
    ("guest listed in full profile adds", word(full_adds, "guest"), full_adds.strip()),
    ("all three providers named", all(word(tools, p) for p in ("lume", "prlctl", "tart")),
     [p for p in ("lume", "prlctl", "tart") if not word(tools, p)]),
    ("SKILL.md has a guest lane section", heading(skill_raw, "The guest lane"), None),
    ("description names the guest lane", "virtual-machine guests" in desc, None),
    ("description distinguishes delegated", "delegated to coordinates" in desc, None),
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
