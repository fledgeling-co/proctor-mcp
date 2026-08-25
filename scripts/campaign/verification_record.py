#!/usr/bin/env python3
"""What was asked for, what ran, and what stood in for it.

Two findings from the same audit, and they are one instrument because they are
one question asked about different things.

**T9.** Eighteen reviewer lanes were chosen by direct invocation rather than
through a selector, so which model family judged which work rests on prose. The
invariants a verification pipeline claims — reviewer at least as strong as
writer, verifier not in the writer's family — cannot be audited from prose, and
"we used a different family" is exactly the sentence nobody can check.

**T15.** Two named instruments were asked for, never used, and never mentioned.
A pass that cannot separate "the instrument was unavailable" from "the
instrument was ignored" manufactures findings, and manufactured findings are
what get a verification skill switched off. The remedy is not to guess which it
was: it is to record, at the moment of asking, whether the thing resolved.

So a record answers three things and refuses to be silent on any of them: what
was asked for, what actually ran, and — when those differ — what established the
difference.

  verification_record.py write  --task T --asked A --ran R [--writer W]
                                [--reason S] [--evidence P] [--effort E]
  verification_record.py sweep  [--instrument NAME ...]
  verification_record.py check  [--gate]
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
STORE = ROOT / "docs" / "test-campaign" / "verification-records"

# Which family a lane belongs to. The point of the record is the family, not the
# model string: two Anthropic models checking each other is one family however
# different the ids look, and that is the invariant a verifier claims to hold.
FAMILY = {
    "claude": "anthropic", "fable": "anthropic", "opus": "anthropic",
    "sonnet": "anthropic", "haiku": "anthropic",
    "codex": "openai", "gpt": "openai",
    "agy": "google", "gemini": "google",
    "grok": "xai",
    "cursor-agent": "harness",
}

# The CLI a lane runs through, for the availability sweep. A lane whose binary
# is absent is a lane failure to be reported once, never retried into the ground.
LANE_BINARY = {"anthropic": "claude", "openai": "codex", "google": "agy", "xai": "grok"}


def family_of(lane: str) -> str:
    low = lane.lower()
    for key, fam in FAMILY.items():
        if key in low:
            return fam
    return "unknown"


def egress_blocked() -> tuple[bool, str]:
    """Is an out-of-family call permitted in this repository right now?

    Re-read rather than remembered: the marker is the only kill-switch that
    reaches a run already in motion, so a record written from a cached answer
    describes a policy that may have changed since.
    """
    for marker in ("ANTHROPIC-ONLY", "NO EXTERNAL MODEL CLIS"):
        for name in (".egress", "EGRESS", "CLAUDE.md", "ORCHESTRATOR.md"):
            f = ROOT / name
            if f.is_file() and re.search(rf"^\s*{re.escape(marker)}\s*$",
                                         f.read_text(errors="replace"), re.M):
                return True, f"{marker} set in {name}"
    return False, "no egress marker is set for this repository"


def cmd_write(a) -> int:
    STORE.mkdir(parents=True, exist_ok=True)
    asked_fam, ran_fam = family_of(a.asked), family_of(a.ran)
    writer_fam = family_of(a.writer) if a.writer else None
    substituted = a.asked != a.ran
    if substituted and not a.reason:
        print("a record whose asked and ran lanes differ needs --reason: what established "
              "that the primary was unavailable. Without it the record cannot tell an "
              "environment failure from a routing decision, which is the whole point.",
              file=sys.stderr)
        return 2
    blocked, why = egress_blocked()
    rec = {
        "task": a.task,
        "asked": {"lane": a.asked, "family": asked_fam, "effort": a.effort},
        "ran": {"lane": a.ran, "family": ran_fam},
        "substituted": substituted,
        "substitutionReason": a.reason,
        "writerFamily": writer_fam,
        "inFamily": (writer_fam is not None and writer_fam == ran_fam),
        "egress": {"blocked": blocked, "basis": why},
        "evidence": a.evidence,
        "recordedAt": subprocess.run(["date", "-u", "+%Y-%m-%dT%H:%M:%SZ"],
                                     capture_output=True, text=True).stdout.strip(),
    }
    n = len(list(STORE.glob("*.json"))) + 1
    slug = re.sub(r"[^a-z0-9]+", "-", a.task.lower()).strip("-")[:48]
    path = STORE / f"{n:04d}-{slug}.json"
    path.write_text(json.dumps(rec, indent=2) + "\n")
    print(f"wrote {path}")
    if rec["inFamily"]:
        print(f"  FLAGGED in-family: the writer was {writer_fam} and so was the reviewer. "
              f"That may be correct — an egress marker makes it the right run rather than a "
              f"degraded one — but it is recorded rather than assumed.")
    return 0


def cmd_sweep(a) -> int:
    """Which named instruments resolve on this machine, right now.

    `usable` is not claimed. Locating a binary establishes that a name is at a
    path; whether it runs, and as what, is settled by running it. Reporting
    presence as usability is how a doctor call becomes a promise.
    """
    names = a.instrument or sorted(set(LANE_BINARY.values()))
    rows = []
    for name in names:
        p = shutil.which(name)
        rows.append({"instrument": name, "resolved": bool(p), "path": p,
                     "evidence": "presence at a path" if p else "not on PATH"})
    blocked, why = egress_blocked()
    print(f"{sum(1 for r in rows if r['resolved'])} of {len(rows)} instrument(s) resolve")
    for r in rows:
        print(f"  {r['instrument']:<16} {'FOUND' if r['resolved'] else 'ABSENT':<7} "
              f"{r['path'] or r['evidence']}")
    print(f"\negress: {'BLOCKED — ' if blocked else ''}{why}")
    print("Resolution is presence at a path. Whether an instrument runs, and as which model, "
          "is settled by running it and reading its header back — a clean header is necessary "
          "and not sufficient, and an empty output file is the real failure signal.")
    if a.json:
        a.json.write_text(json.dumps({"instruments": rows, "egress": {"blocked": blocked,
                                                                     "basis": why}},
                                     indent=2) + "\n")
        print(f"\nwrote {a.json}")
    return 0


def cmd_check(a) -> int:
    records = sorted(STORE.glob("*.json")) if STORE.is_dir() else []
    if not records:
        print(f"no verification records under {STORE}. An empty store is not a clean one: "
              f"it says no verification act has been recorded, which is the condition T9 "
              f"described rather than the absence of it.")
        return 1 if a.gate else 0

    bad, in_family, substituted = [], [], []
    for f in records:
        r = json.loads(f.read_text())
        for key in ("task", "asked", "ran"):
            if not r.get(key):
                bad.append(f"{f.name} names no {key}")
        if r.get("asked", {}).get("family") == "unknown":
            bad.append(f"{f.name} asked for a lane whose family this tool cannot place")
        if r.get("substituted") and not r.get("substitutionReason"):
            bad.append(f"{f.name} substituted a lane and records no reason")
        if r.get("inFamily"):
            in_family.append(f.name)
        if r.get("substituted"):
            substituted.append(f.name)

    print(f"{len(records)} verification record(s) · {len(in_family)} in-family · "
          f"{len(substituted)} with a substitution")
    for name in in_family:
        print(f"  in-family: {name}")
    for name in substituted:
        print(f"  substituted: {name}")
    if bad:
        for b in bad:
            print(f"FAIL  {b}")
        return 1
    if a.gate:
        print("\ngate: every record names its task, both lanes and their families, and every "
              "substitution names what established it.")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)

    w = sub.add_parser("write")
    w.add_argument("--task", required=True)
    w.add_argument("--asked", required=True)
    w.add_argument("--ran", required=True)
    w.add_argument("--writer", default=None)
    w.add_argument("--reason", default=None)
    w.add_argument("--effort", default=None)
    w.add_argument("--evidence", default=None)
    w.set_defaults(fn=cmd_write)

    s = sub.add_parser("sweep")
    s.add_argument("--instrument", action="append")
    s.add_argument("--json", type=Path, default=None)
    s.set_defaults(fn=cmd_sweep)

    c = sub.add_parser("check")
    c.add_argument("--gate", action="store_true")
    c.set_defaults(fn=cmd_check)

    a = ap.parse_args()
    return a.fn(a)


if __name__ == "__main__":
    sys.exit(main())
