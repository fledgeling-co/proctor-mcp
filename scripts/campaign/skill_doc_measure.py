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

PRO-0100 adds a sixth, and it is about the denominator rather than about a
predicate. DEF-193 was the FIFTH stale tool count in this skill, and it survived
every check above for one reason: this script opened `SKILL.md` and
`references/tools.md` and never opened `gemini.md` at all. Each of the five was
found by a person reading. So the file list stops being the two files somebody
thought of:

  * `md_files()` enumerates every `*.md` under the skill directory, and
    `COVERED` names the ones a check actually reads. A new file added to the
    skill reds until somebody decides what to check in it, rather than joining
    the set of places a count can go stale unwatched.
  * every number stated immediately before the word `tools`, in every one of
    those files, is read and compared. Subset counts are real — the `core`
    profile's ten, the fifteen this page specifies, "recording is two tools
    together" — so the rule is that each stated number is one the catalogue
    justifies, and the allowlist carries the reason rather than the number
    carrying nothing.
"""
import re
import sys
from pathlib import Path

SKILL = Path("/Users/lukerhodes/Dev/fledgeling-plugins/plugins/proctor/skills/proctor")
# Repo-relative. This defaulted to `.worktrees/PRO-0085/…` until PRO-0100:
# that worktree was removed when PRO-0085 merged, so the script could not run
# at all without `--catalogue`. `skill_doc_arm.py` already resolved it this
# way, which is why the arming kept working while the measurement did not.
CAT = Path(__file__).resolve().parents[2] / "Sources/ProctorCore/ToolCatalogue.swift"
INTERNAL = {"proctor_hud", "proctor_queue", "proctor_recent_activity", "proctor_resource"}
SPECIFIED_SECTIONS = 15
# The counts these two files spell out in words rather than digits.
NUM = {"one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
       "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13,
       "fourteen": 14, "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18,
       "nineteen": 19, "twenty": 20, "twenty-one": 21, "twenty-two": 22}

# Counts of tools that are NOT the catalogue count and are right anyway, each
# with the reason it is not drift. PRO-0100: the general scan below would
# otherwise fire on English, and a check that fires on English gets switched off.
SUBSET_COUNTS = {
    10: "the `core` profile's size, checked against the profile table by its own check",
    15: "the sections `references/tools.md` specifies, checked by its own two checks",
    2: '"Recording is two tools together" — a sentence about two named tools, not a catalogue count',
}

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
gemini_path = SKILL / "gemini.md"
gemini_raw = gemini_path.read_text() if gemini_path.exists() else ""

def md_files():
    return {str(p.relative_to(SKILL)) for p in SKILL.rglob("*.md")}


# A count word or digit sitting immediately before the word `tools`. The
# `(\*\*)?` lets the bolded `**21 tools**` in tools.md match the same way.
COUNT_BEFORE_TOOLS = re.compile(r"(?:\*\*)?(\d+|[a-z]+(?:-[a-z]+)?)(?:\*\*)?\s+tools\b", re.I)


def named_tools_everywhere():
    """Every (file, proctor_* identifier) named anywhere in the skill.

    The name half of the same denominator problem: `references/tools.md` is
    checked against the catalogue and the other four `*.md` files are not, so a
    renamed tool leaves a stale mention in `gemini.md` or `references/methodology.md`
    and every check here stays green. Measured at PRO-0100: those two files name
    ten identifiers between them and all ten are shipped, so this starts from a
    true statement rather than from a backlog.
    """
    found = []
    for rel in sorted(md_files()):
        for name in sorted(set(re.findall(r"proctor_[a-z_]+", (SKILL / rel).read_text()))):
            found.append((rel, name))
    return found


def stated_tool_counts():
    """Every (file, token, number) where a *.md states a count of tools.

    Tokens that name no number — "those tools", "the Mac tools" — are not counts
    and are dropped rather than reported, because a check that fires on English
    is one somebody switches off.
    """
    found = []
    for rel in sorted(md_files()):
        flat = flat_text((SKILL / rel).read_text())
        for m in COUNT_BEFORE_TOOLS.finditer(flat):
            token = m.group(1)
            value = int(token) if token.isdigit() else NUM.get(token.lower())
            if value is None:
                continue
            found.append((rel, token, value))
    return found
# Line wrapping is not content: normalise whitespace before matching prose, so a
# claim does not read as absent because the sentence broke across two lines.
flat = lambda s: " ".join(s.split())
flat_text = flat
tools, skill = flat(tools_raw), flat(skill_raw)
gemini = flat(gemini_raw)
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

# PRO-0100, DEF-193. Every count of tools any *.md in the skill states, and the
# ones the catalogue does not justify.
all_counts = stated_tool_counts()
stale_names = [f"{rel}: {name}" for rel, name in named_tools_everywhere()
               if name not in cat and name not in INTERNAL]
gemini_counts = [v for rel, _, v in all_counts if rel == "gemini.md"]
unjustified_counts = [f"{rel}: {token!r} -> {v}"
                      for rel, token, v in all_counts
                      if v != len(cat) and v not in SUBSET_COUNTS]

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
    # PRO-0100, DEF-193. The three checks that make the DENOMINATOR the skill
    # directory rather than the two files somebody thought of. DEF-193 was the
    # fifth stale count and it survived because nothing here opened its file.
    ("every *.md in the skill names only tools the server ships", not stale_names,
     stale_names),
    ("gemini.md states the catalogue count", gemini_counts == [len(cat)] if gemini_counts else False,
     gemini_counts or "gemini.md states no tool count at all"),
    ("every stated tool count is one the catalogue justifies", not unjustified_counts,
     unjustified_counts),
]
bad = 0
for name, ok, detail in checks:
    print(f"{'PASS' if ok else 'FAIL'}  {name}" + (f"   [{detail}]" if not ok and detail is not None else ""))
    bad += not ok
print(f"\n{len(checks) - bad}/{len(checks)} checks passed")
sys.exit(1 if bad else 0)
