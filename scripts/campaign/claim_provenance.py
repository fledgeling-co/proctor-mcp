#!/usr/bin/env python3
"""Every figure in a durable artifact, and whether anything on disk backs it.

The audit that produced this repository's `tailings/` ran once, by hand, over a
session transcript. What it found is not confined to a transcript: the most
damaging failure in its corpus is a number written into an artifact another
session plans from, and this repository has several — `ORCHESTRATOR.md`, the
ledger, the reckoning reports, the spec Verify blocks.

So the same partition runs standing, over those artifacts, with a narrower
subject: a **figure** — a count, a fraction or a percentage stated about this
project — and whether a file on disk carries it.

Four classes, and every figure lands in exactly one:

  substantiated   a registry, a gate's recorded output or a file on disk holds
                  this exact number
  unbacked        nothing on disk holds it, and nothing contradicts it either
  contradicted    a file on disk holds a DIFFERENT number for the same subject
  waived          declared stale on purpose, with a reason on the row

`unbacked` is the largest class and the least alarming, and folding it into
`contradicted` is how a pass over-reports and loses its reader. A figure in a
wave entry written three waves ago is unbacked because the run it described is
over — that is a fact about time, not a false claim.

  claim_provenance.py [--artifact PATH ...] [--json PATH] [--gate]
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

DEFAULT_ARTIFACTS = ["ORCHESTRATOR.md", "docs/feature-specs/LEDGER.md"]

# A figure this tool can check: a count of a thing the registries also count.
# Narrow on purpose. A scanner that reads every number in a markdown file finds
# version strings, dates and line numbers, and drowns the one figure that moved.
FIGURE = re.compile(
    r"(?<![\d.])\*?\*?(\d[\d,]*)\*?\*?\s+(tests?|suites?|cases?|rows?|specs?|briefs?|"
    r"requirements?|surfaces?|defects?)\b(?!\s*[a-z])", re.I)

# A version string is not a figure. `0.9.2 test-campaign` matched "2 test" until
# the lookbehind above refused a digit preceded by a dot or another digit.
#
# Two subjects are overloaded in this repository's prose and a scanner that does
# not know it manufactures contradictions.
#
# "6,182 spec citations" is not 6,182 specs, and the trailing `(?!\s*[a-z])`
# above is what stops that: a subject word followed by another lowercase word is
# qualified by it and names something else.
#
# "969 rows" on a line about reckon is reckon's ledger, a different population
# from the feature ledger — and a figure whose subject this tool cannot pin down
# is `unbacked`, never `contradicted`. Asserting a contradiction needs certainty
# about WHICH population, and a false contradiction is the finding that gets a
# gate switched off.
OTHER_POPULATION = re.compile(
    r"\breckon|\breckoning|citation|ledger\.json|mutation|survivor|figures? sourced", re.I)

# A figure a writer has already marked as history. `waived` is the class for
# "accepted unverified, with a named reason", and this is the only way into it:
# the line must SAY it is superseded or dated, in its own words, on the same
# line as the figure. A waiver a tool grants itself is not a waiver.
DECLARED_HISTORY = re.compile(
    r"\bsuperseded\b|\bas at \d{4}-\d{2}-\d{2}\b|\bhistory rather than a claim\b|"
    r"\bno longer\b|\bat the time\b", re.I)

# Subjects whose true value this tool can read off the registries. Anything else
# is reported unbacked rather than guessed at.
def truths(campaign: Path, repo: Path) -> dict[str, set[int]]:
    out: dict[str, set[int]] = {}

    def add(k: str, v: int) -> None:
        out.setdefault(k, set()).add(v)

    raw = json.loads((campaign / "cases.json").read_text())
    cases = raw if isinstance(raw, list) else (raw.get("case") or raw.get("cases") or [])
    add("case", len(cases))
    inv = json.loads((campaign / "inventory.json").read_text())
    for key, word in (("requirement", "requirement"), ("surface", "surface"),
                      ("defect", "defect")):
        add(word, len(inv.get(key, [])))

    ledger = (repo / "docs" / "feature-specs" / "LEDGER.md")
    if ledger.is_file():
        add("row", len(re.findall(r"^\| PRO-\d{4} \|", ledger.read_text(), re.M)))
    specs = list((repo / "docs" / "specs").glob("spec-PRO-*.md"))
    add("spec", len(specs))
    briefs = [f for f in (repo / "docs" / "features-to-triage").rglob("*.md")]
    add("brief", len(briefs))

    # Test and suite counts come from the recorded run rather than from a fresh
    # one: this tool reads, it does not execute, and a figure checked against a
    # run it started itself would be checking its own work.
    for log in sorted((campaign / "evidence").rglob("*.txt")) + \
            sorted((campaign / "evidence").rglob("*.log")):
        try:
            head = log.read_text(errors="replace")
        except OSError:
            continue
        for m in re.finditer(r"Test run with ([\d,]+) tests in ([\d,]+) suites", head):
            add("test", int(m.group(1).replace(",", "")))
            add("suite", int(m.group(2).replace(",", "")))
    return out


SINGULAR = {"tests": "test", "test": "test", "suites": "suite", "suite": "suite",
            "cases": "case", "case": "case", "rows": "row", "row": "row",
            "specs": "spec", "spec": "spec", "briefs": "brief", "brief": "brief",
            "requirements": "requirement", "requirement": "requirement",
            "surfaces": "surface", "surface": "surface",
            "defects": "defect", "defect": "defect"}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--artifact", action="append")
    ap.add_argument("--campaign", type=Path, default=ROOT / "docs" / "test-campaign")
    ap.add_argument("--json", type=Path, default=None)
    ap.add_argument("--gate", action="store_true")
    a = ap.parse_args()

    known = truths(a.campaign, ROOT)
    artifacts = [ROOT / p for p in (a.artifact or DEFAULT_ARTIFACTS)]
    rows = []

    for art in artifacts:
        if not art.is_file():
            print(f"{art} does not exist — not checked, rather than clean.", file=sys.stderr)
            return 2
        lines = art.read_text(errors="replace").splitlines()
        # A wave entry describes a run that is over, so its figures are history.
        # Only the newest wave's block, and anything outside a wave block, is
        # held to the present — the rest is waived with that reason on the row.
        wave_starts = [i for i, ln in enumerate(lines) if re.match(r"^## Wave \d+", ln)]
        newest = wave_starts[-1] if wave_starts else None
        for i, ln in enumerate(lines, 1):
            for m in FIGURE.finditer(ln):
                n = int(m.group(1).replace(",", ""))
                subject = SINGULAR.get(m.group(2).lower())
                if subject is None or subject not in known:
                    continue
                historical = (newest is not None and wave_starts
                              and i - 1 < newest
                              and any(i - 1 > s for s in wave_starts))
                row = {"artifact": str(art.relative_to(ROOT)), "line": i,
                       "figure": n, "subject": subject, "text": ln.strip()[:120]}
                if historical:
                    row["class"] = "waived"
                    row["why"] = ("stated inside a closed wave entry, which describes a run "
                                  "that is over — history rather than a claim about now")
                elif DECLARED_HISTORY.search(ln):
                    row["class"] = "waived"
                    row["why"] = ("the line marks itself superseded or dated, in its own "
                                  "words — a reason a reader can see beside the figure, "
                                  "which is what separates a waiver from an omission")
                elif OTHER_POPULATION.search(ln):
                    row["class"] = "unbacked"
                    row["why"] = ("the line names a different population — this tool counts "
                                  "the feature ledger and the campaign registries, and will "
                                  "not assert a contradiction about a register it does not "
                                  "hold")
                elif n in known[subject]:
                    row["class"] = "substantiated"
                    row["why"] = f"a registry or a recorded run holds {n} {subject}(s)"
                else:
                    row["class"] = "contradicted"
                    row["why"] = (f"the registries hold "
                                  f"{', '.join(str(x) for x in sorted(known[subject]))} "
                                  f"{subject}(s), not {n}")
                rows.append(row)

    counts = {c: sum(1 for r in rows if r["class"] == c)
              for c in ("substantiated", "unbacked", "contradicted", "waived")}
    print(f"{len(rows)} checkable figure(s) across {len(artifacts)} artifact(s)")
    for c, n in counts.items():
        print(f"  {c:<15} {n:>4}")

    bad = [r for r in rows if r["class"] == "contradicted"]
    if bad:
        print(f"\n{len(bad)} contradicted — a durable artifact states a number the registries "
              f"do not hold, and another session plans from this file:")
        for r in bad[:12]:
            print(f"  {r['artifact']}:{r['line']}  {r['figure']} {r['subject']}(s)")
            print(f"      {r['why']}")
            print(f"      {r['text']}")

    print("\nNot checked (a figure this tool cannot place is not a figure that passed):")
    print(f"  every figure whose subject is not one of "
          f"{', '.join(sorted(known))} — the scanner is narrow on purpose, because one that "
          f"read every number would drown the figure that moved in version strings and dates")

    if a.json:
        a.json.write_text(json.dumps({"counts": counts, "rows": rows}, indent=2) + "\n")
        print(f"\nwrote {a.json}")

    if a.gate:
        if bad:
            print(f"\nFAIL  {len(bad)} contradicted figure(s) stand in artifacts another "
                  f"session plans from.")
            return 1
        print(f"\ngate: no durable artifact states a live figure the registries contradict.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
