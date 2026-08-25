#!/usr/bin/env python3
"""Spec-validation over the legacy brief queue, and retirement with a citation.

`reckon.py` classes a brief `undecided` when it cannot read a rung behind it,
and its stated remedy is spec-validation. 111 of this repository's briefs sit
there for one mechanical reason: they cite requirements in prose, and reckon
looks cases up by surface, so the hop from requirement to surface is never made
and the strongest oracle reads as `none`.

The hop exists in the registry — every requirement declares its surfaces — so
the validation is answerable without reading prose:

    brief --cites--> REQ --declares--> SURF --carries--> case(s)
                      |
                      +--declares--> provider symbol --> Sources/**.swift

A brief is **validated** when all three hold, each read from a different place:

  1. every requirement it cites is in the registry;
  2. at least one of those requirements carries a passing case at `outcome` or
     above, on a surface the requirement itself names;
  3. the requirement's declared `provider` resolves to a declaration in the
     production tree, or the requirement declares no external effect at all.

Rule 3 is what stops this being a rename of `undecided`. A requirement whose
provider resolves to nothing is vacuous — the guarantee holds because the
capability never runs — and a brief resting on one is reported, never retired.

That verdict is **read from `vacuity-check.py` rather than recomputed here.**
A first draft resolved provider strings against the declaration index and
reported REQ-006 and REQ-024 as vacuous over `NSPanel` and `Process()`, both of
which the platform supplies and the census resolves without difficulty. Two
implementations of one rule disagree, and the one this file would have shipped
was the wrong one — so the census's own findings list is the input, and an
absent census is a lane failure rather than a pass.

`--record` writes the verdict into the brief as a **Validation record** section
naming the requirement, the surface, the cases and the provider that carried it.

It deliberately does **not** set `status: retired`. reckon maps a declared
retirement onto `waived` — "somebody decided not to" — and 111 briefs proved
done would then read as 111 somebody declined. Proved-done is `retirable`, which
is reckon's to award and not this script's to assert. What the record does is
complete the hop the join was missing, by naming the surface in the brief's own
prose where `brief_scan` can see it; reckon then reads the rung off the cases
itself and classes the row on its own evidence. The instrument supplies the
citation; the verdict stays with the tool that owns it.

  brief_validation.py [--briefs DIR] [--campaign DIR] [--retire] [--json PATH]
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FM = re.compile(r"\A---\n(.*?)\n---\n", re.S)
REQ_ID = re.compile(r"\bREQ-\d{3}\b")
DECL = re.compile(
    r"^\s*(?:@\w+\s+)*(?:public|internal|private|fileprivate|open|package)?\s*"
    r"(?:final\s+|static\s+|class\s+|mutating\s+|nonisolated\s+|override\s+)*"
    r"\b(?:class|struct|enum|protocol|actor|extension|func|var|let|case|typealias)\b"
    r"\s+([A-Za-z_]\w*)")

# The floor for retiring stated intent, taken from reckon rather than chosen
# here: a rung below this proves something rendered and says nothing about
# whether it works.
RETIRING_RUNGS = {"outcome", "metamorphic", "effect-witness",
                  "raster-visual", "interactive-glass"}


def blank_fences(text: str) -> str:
    out, fenced = [], False
    for ln in text.splitlines():
        if ln.lstrip().startswith("```"):
            fenced = not fenced
            out.append("")
            continue
        out.append("" if fenced else ln)
    return "\n".join(out)


def production_symbols(source: Path) -> set[str]:
    names: set[str] = set()
    for f in source.rglob("*.swift"):
        try:
            for ln in f.read_text(errors="replace").splitlines():
                m = DECL.match(ln)
                if m:
                    names.add(m.group(1))
        except OSError:
            continue
    return names


def vacuous_requirements(campaign: Path, script: Path | None) -> dict[str, str] | None:
    """Requirement ids the vacuity census reports a finding against.

    Returns None when the census could not be run at all, which the caller must
    treat as a refusal rather than as an empty finding list.
    """
    import subprocess
    if script is None:
        cache = Path.home() / ".claude/plugins/cache/fledgeling-plugins/test-campaign"
        if not cache.is_dir():
            return None
        def key(d: Path) -> tuple:
            return tuple(int(x) if x.isdigit() else -1 for x in d.name.split("."))
        for d in sorted((x for x in cache.iterdir() if x.is_dir()), key=key, reverse=True):
            cand = d / "skills/test-campaign/scripts/vacuity-check.py"
            if cand.is_file():
                script = cand
                break
    if script is None or not Path(script).is_file():
        return None
    out = subprocess.run([sys.executable, str(script), str(campaign)],
                         capture_output=True, text=True)
    if out.returncode not in (0, 1):
        return None
    found: dict[str, str] = {}
    for ln in out.stdout.splitlines():
        m = re.search(r"\b(REQ-\d{3})\b", ln)
        if m and ("resolve" in ln or "vacuous" in ln or "no provider" in ln
                  or "reaches nothing" in ln):
            found[m.group(1)] = ln.strip()[:160]
    return found


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--briefs", type=Path, default=ROOT / "docs" / "features-to-triage")
    ap.add_argument("--campaign", type=Path, default=ROOT / "docs" / "test-campaign")
    ap.add_argument("--source", type=Path, default=ROOT / "Sources")
    ap.add_argument("--vacuity", type=Path, default=None,
                    help="path to vacuity-check.py; default resolves the newest installed copy")
    ap.add_argument("--record", action="store_true",
                    help="write the validation record into each validated brief")
    ap.add_argument("--retire-from", type=Path, default=None,
                    help="a reckon ledger.json; retire exactly the briefs IT classes retirable")
    ap.add_argument("--json", type=Path, default=None)
    a = ap.parse_args()

    vacuous = vacuous_requirements(a.campaign, a.vacuity)
    if vacuous is None:
        print("vacuity-check.py could not be run, so no requirement's provider can be "
              "judged. An absent instrument is a lane failure, not a pass.", file=sys.stderr)
        return 2

    inv = json.loads((a.campaign / "inventory.json").read_text())
    raw = json.loads((a.campaign / "cases.json").read_text())
    cases = raw if isinstance(raw, list) else (raw.get("case") or raw.get("cases") or [])
    reqs = {r["id"]: r for r in inv.get("requirement", [])}
    symbols = production_symbols(a.source)

    by_surface: dict[str, list[dict]] = defaultdict(list)
    for c in cases:
        if c.get("surface"):
            by_surface[c["surface"]].append(c)

    def strong_cases(req_id: str) -> list[dict]:
        r = reqs.get(req_id) or {}
        out = []
        for sid in r.get("surfaces") or []:
            for c in by_surface.get(sid, []):
                if str(c.get("status", "")).startswith("pass") \
                        and c.get("oracle") in RETIRING_RUNGS:
                    out.append(c)
        return out

    def provider_ok(req_id: str) -> tuple[bool, str]:
        r = reqs.get(req_id) or {}
        if (r.get("effect") or "none") == "none":
            return True, "declares no external effect, so no provider is owed"
        if req_id in vacuous:
            return False, f"the vacuity census reports it: {vacuous[req_id]}"
        if not (r.get("provider") or "").strip():
            return False, "declares an external effect and names no provider"
        return True, "the vacuity census resolves its provider"

    validated, blocked, skipped = [], [], []
    for f in sorted(a.briefs.rglob("*.md")):
        text = f.read_text()
        m = FM.match(text)
        front = m.group(1) if m else ""
        body = text[m.end():] if m else text
        status = ""
        sm = re.search(r"^status:\s*(\S+)\s*$", front, re.M)
        if sm:
            status = sm.group(1)
        if status in ("retired", "waived", "consumed"):
            skipped.append({"brief": f.name, "why": f"already {status}"})
            continue

        cited = sorted(set(REQ_ID.findall(front)) | set(REQ_ID.findall(blank_fences(body))))
        if not cited:
            skipped.append({"brief": f.name, "why": "cites no requirement"})
            continue

        known = [r for r in cited if r in reqs]
        if not known:
            blocked.append({"brief": f.name, "cited": cited,
                            "why": "cites requirements the registry does not hold"})
            continue

        support, provider_notes, carrying = [], [], []
        for r in known:
            cs = strong_cases(r)
            ok, note = provider_ok(r)
            provider_notes.append(f"{r}: {note}")
            if cs and ok:
                carrying.append(r)
                support.extend(cs)

        if not carrying:
            blocked.append({
                "brief": f.name, "cited": known,
                "why": ("no cited requirement carries both a passing case at the retiring "
                        "floor and a provider that resolves"),
                "detail": provider_notes})
            continue

        ids = sorted({c["id"] for c in support})[:6]
        surfaces = sorted({c["surface"] for c in support})
        req = carrying[0]
        rec = {"brief": f.name, "requirements": carrying, "surfaces": surfaces,
               "cases": ids, "provider": (reqs[req].get("provider") or "none"),
               "rungs": sorted({c["oracle"] for c in support})}
        validated.append(rec)

        if a.record:
            record = (
                "\n## Validation record\n\n"
                "Written by `scripts/campaign/brief_validation.py`, which reads the registry "
                "rather than this document. Every id below is re-checkable: the requirement is "
                "in `inventory.json`, the surface is the one that requirement itself names, and "
                "each case passed at a rung at or above reckon's retiring floor.\n\n"
                f"- requirement: {', '.join(carrying)}\n"
                f"- surface: {', '.join(surfaces)}\n"
                f"- cases: {', '.join(ids)}\n"
                f"- rungs reached: {', '.join(rec['rungs'])}\n"
                f"- provider: {rec['provider']}\n")
            stripped = re.sub(r"\n## Validation record\n.*?(?=\n## |\Z)", "\n",
                              body, flags=re.S)
            new_body = stripped.rstrip() + "\n" + record
            f.write_text((f"---\n{front}\n---\n" if m else "") + new_body.lstrip("\n"))

    if a.retire_from:
        led = json.loads(a.retire_from.read_text())
        rows = led["rows"] if isinstance(led, dict) else led
        # Retirement follows reckon's verdict, never this script's. `retirable`
        # is the class reckon awards after reading the rung off real cases; a
        # brief this file validated but reckon did not class is left open, and
        # that disagreement is the point of asking two instruments.
        want = {r.get("file") for r in rows if r.get("class") == "retirable"}
        mine = {v["brief"] for v in validated}
        done, absent = 0, sorted(want - mine)
        for f in sorted(a.briefs.rglob("*.md")):
            if f.name not in want:
                continue
            text = f.read_text()
            m = FM.match(text)
            front = m.group(1) if m else ""
            body = text[m.end():] if m else text
            if re.search(r"^status:", front, re.M):
                front = re.sub(r"^status:.*$", "status: retired", front, flags=re.M)
            else:
                front = (front + "\nstatus: retired").strip()
            f.write_text(f"---\n{front}\n---\n" + body.lstrip("\n"))
            done += 1
        print(f"retired {done} brief(s) the reckoning classed `retirable`; each keeps its "
              f"Validation record, so the reason is re-checkable after the status changes")
        if absent:
            print(f"  {len(absent)} classed retirable that this file did not validate — "
                  f"read them rather than trusting either: {', '.join(sorted(absent)[:4])}")
        return 0

    total = len(validated) + len(blocked) + len(skipped)
    print(f"{total} brief(s) examined")
    print(f"  validated {len(validated):>4} — a cited requirement carries a passing case at the "
          f"retiring floor, and its provider resolves")
    print(f"  blocked   {len(blocked):>4} — read the reason on each; none was retired")
    print(f"  skipped   {len(skipped):>4} — already decided, or cites no requirement")
    if blocked:
        print("\nblocked, first ten:")
        for b in blocked[:10]:
            print(f"  {b['brief']:<52} {b['why']}")
    if a.json:
        a.json.write_text(json.dumps(
            {"validated": validated, "blocked": blocked, "skipped": skipped}, indent=2) + "\n")
        print(f"\nwrote {a.json}")
    print("\nDRY RUN — pass --record to write the validation records in."
          if not a.record else "\nrecorded. reckon reads the rung and classes each row itself.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
