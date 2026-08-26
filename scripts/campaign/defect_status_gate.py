#!/usr/bin/env python3
"""A defect's status word means one thing, and matches its own note.

`reckon` decides the owing set from these words: a `fixed` row leaves it, a
`partially-fixed` row stays in it. So a wrong word removes a piece of work from
the only report that counts it, and nothing here checked the words.

DEF-221 was the case. Its title names two arms — one image across two unrelated
sweeps, and two wedged timestamps sharing a frame — and its note closes the
second with "RECORDED rather than fixed", while its status read `fixed`. The
two captures that arm names are still one image. The registry already carried
`partially-fixed` and used it for DEF-339; the word existed and the row did not
use it.

TWO CHECKS, AND THE SECOND IS THE ONE THAT NEEDS CARE.

The vocabulary check is decidable: a word is in the list or it is not.

The remainder check matches phrases, and a phrase matcher tuned until it finds
nothing is the failure this repository refuses elsewhere. So the list is short,
every phrase in it is quoted from a row somebody read, and the run prints how
many notes it examined against how many matched. A denominator is what makes a
zero mean something.

    python3 scripts/campaign/defect_status_gate.py [--campaign DIR] [--gate] [--json OUT]

Exit codes
    0   every status word is known and no `fixed` row declares a remainder
    1   at least one of those, with the rows named
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

# What each word means for reckon's owing set. A word absent from here is
# placed by reckon's fail-closed default rather than by anything the registry
# said, which is why an unknown word is a gate failure and not a warning.
VOCABULARY = {
    "open": "measured and still failing — stays in the owing set",
    "fixed": "measured, repaired, and a case watches the repair — leaves the owing set",
    "partially-fixed": "one arm repaired and another recorded — stays in the owing set",
    "closed": "ended without a repair, because the subject went away — leaves the owing set",
}

# Phrases that say, inside a note, that part of the defect was not repaired.
# Every one is quoted from a row in this registry rather than imagined, because
# a list somebody invented would be tuned rather than measured.
REMAINDER = [
    ("RECORDED rather than fixed", "DEF-221 · DEF-222"),
    ("recorded rather than fixed", "lower-case form of the same"),
    ("the other half", "DEF-339"),
    ("the other still happens", "DEF-339"),
    ("still broken", "reckon's own wording for a partially-fixed row"),
    ("not this item's scope", "DEF-221"),
    ("stays unmeasured", "the shape a ceiling takes in a note"),
]
LEAVES_THE_SET = {"fixed", "closed"}

# A row may declare that a matched phrase is not about its own remainder, by
# carrying `statusRemainderWaiver`. Two rows needed it on this gate's first run
# and neither was a mis-status: DEF-202's note quotes reckon's reasoning about a
# word list ("a half still broken owes a reproduction for that half"), and
# DEF-219's says the underlying capture-channel fault belongs to another row.
#
# The waiver exists rather than the phrases being deleted. Dropping "still
# broken" would clear both runs and let the next row that genuinely is still
# broken through unflagged — which is tuning the matcher toward zero, and it is
# the failure this file's own docstring names. A waiver is visible, per-row, and
# carries its reason; a shorter phrase list is invisible and carries none.
WAIVER_FIELD = "statusRemainderWaiver"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--campaign", default=str(ROOT / "docs" / "test-campaign"))
    ap.add_argument("--gate", action="store_true")
    ap.add_argument("--json")
    a = ap.parse_args()

    inventory = Path(a.campaign) / "inventory.json"
    defects = json.loads(inventory.read_text()).get("defect", [])

    unknown, remainders, waived = [], [], []
    for d in defects:
        status = (d.get("status") or "").strip()
        if status not in VOCABULARY:
            unknown.append({"id": d.get("id"), "status": status})
            continue
        if status not in LEAVES_THE_SET:
            continue
        note = d.get("note") or ""
        hits = [phrase for phrase, _ in REMAINDER if phrase in note]
        if not hits:
            continue
        row = {"id": d.get("id"), "status": status, "phrases": hits, "title": d.get("title")}
        waiver = d.get(WAIVER_FIELD)
        if waiver:
            waived.append(dict(row, why=waiver))
        else:
            remainders.append(row)

    counts: dict[str, int] = {}
    for d in defects:
        counts[(d.get("status") or "").strip()] = counts.get((d.get("status") or "").strip(), 0) + 1

    print(f"{len(defects)} defect(s) examined · "
          + " · ".join(f"{w} {counts.get(w, 0)}" for w in VOCABULARY)
          + (f" · unknown {len(unknown)}" if unknown else ""))
    print(f"remainder phrases searched: {len(REMAINDER)}, over the "
          f"{sum(1 for d in defects if (d.get('status') or '') in LEAVES_THE_SET)} note(s) whose "
          f"status leaves the owing set · {len(remainders) + len(waived)} matched, "
          f"of which {len(waived)} carry a recorded waiver")
    print()
    print("The vocabulary, and what each word means to reckon:")
    for word, meaning in VOCABULARY.items():
        print(f"  {word:<16} {meaning}")

    if waived:
        print()
        print(f"{len(waived)} matched row(s) declare the phrase is not about their own "
              f"remainder, and stay visible rather than being matched away:")
        for r in waived:
            print(f"  {r['id']}  {r['status']}  matched \"{r['phrases'][0]}\"")
            print(f"      {r['why']}")
    if unknown:
        print()
        print(f"{len(unknown)} row(s) carry a status word this registry does not define:")
        for r in unknown:
            print(f"  {r['id']}  {r['status'] or '(empty)'}")
    if remainders:
        print()
        print(f"{len(remainders)} row(s) leave the owing set while their own note declares a "
              f"remainder:")
        for r in remainders:
            print(f"  {r['id']}  {r['status']}  — {r['title']}")
            for p in r["phrases"]:
                print(f"      note says: \"{p}\"")

    if a.json:
        Path(a.json).write_text(json.dumps(
            {"examined": len(defects), "counts": counts, "unknown": unknown,
             "remainders": remainders, "waived": waived,
             "phrasesSearched": len(REMAINDER), "vocabulary": VOCABULARY}, indent=2) + "\n")

    print()
    if unknown or remainders:
        print(f"FAIL  {len(unknown)} unknown word(s), {len(remainders)} row(s) whose word "
              f"disagrees with their note.")
        return 1 if a.gate else 0
    print(f"PASS: all {len(defects)} status words are defined, and no row that leaves the "
          f"owing set declares an unwaived remainder ({len(waived)} waived, named above).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
