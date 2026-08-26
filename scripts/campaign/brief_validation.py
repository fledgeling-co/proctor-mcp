#!/usr/bin/env python3
"""Spec-validation over the legacy brief queue, and retirement with a citation.

`reckon.py` classes a brief `undecided` when it cannot read a rung behind it,
and its stated remedy is spec-validation. 111 of this repository's briefs sat
there for one mechanical reason: they cite requirements in prose, and reckon
looks cases up by SURFACE, so the hop from requirement to surface is never made
and the strongest oracle reads as `none`.

**The first version of this file closed that hop the wrong way**, and an
out-of-family review (grok-4.6 at xhigh, 25 Aug 2026, recorded in
`docs/test-campaign/evidence/PRO-0133/out-of-family-review-grok.md`) returned
UNSOUND on it. It wrote the surface ids into each brief's prose so reckon's
scanner would find them, then let reckon award `retirable`. Three things were
wrong with that and the review named all three: it is the tool feeding itself
the tokens it wants to read; a brief acquires prose its author never wrote,
which a later reader takes for original intent; and — the sharpest of them —
`case_by_surface[SURF-X]` returns *every* case on that surface, so the rung a
brief was retired on need not have come from a case that cites the brief's own
requirement at all.

So the join is the strong one, computed here rather than planted:

    brief --cites--> REQ <--cites-- passing case(s)          ← the cases that
                      |                                         name THIS req
                      +--declares--> provider --> vacuity census

A case on a surface a requirement happens to share is not evidence about that
requirement. `backed_by` is reckon's own name for the strong edge, and this
file computes the same thing rather than approximating it with a surface.

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

`--retire` writes the verdict into the brief's **frontmatter** — `validated-by`
naming the requirement and the exact case ids, and `validated-provider` — and
sets `status: retired`.

Frontmatter and not prose, deliberately. reckon scans a brief's body for
id-shaped tokens, so an id written into the body during a reckoning becomes an
edge in the next run's join; a frontmatter key other than `sources` is inert to
it. The record is there for a person to re-check and for nothing to re-read as
intent.

reckon then classes these `waived` — "a decision, not a measurement" — and that
is the honest reading. The retirement IS a decision, taken on a measurement, and
the measurement is named on the row. What it is not is reckon independently
awarding `retirable`, and the difference between those two matters enough that
the first version of this file was reverted for blurring it.

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
DEF_ID = re.compile(r"\bDEF-\d{3}\b")
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
                    help="write the verdict into each validated brief's FRONTMATTER and "
                         "retire it")
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
    # A brief may cite defects rather than requirements — the wave-18 capture
    # repairs cite eight, and nothing else. A defect names the requirements it
    # was raised against, so the hop from defect to requirement is a registry
    # fact in exactly the way requirement-to-surface is, and following it is
    # transcription rather than inference. A defect still open is not followed:
    # `broken` is the honest class for a brief resting on one, and reckon awards
    # it from the defect's own status.
    defects = {d["id"]: d for d in inv.get("defect", [])}
    symbols = production_symbols(a.source)

    by_req: dict[str, list[dict]] = defaultdict(list)
    for c in cases:
        if not str(c.get("status", "")).startswith("pass"):
            continue
        cited_req = c.get("req")
        for rid in ([cited_req] if isinstance(cited_req, str) else (cited_req or [])):
            if rid:
                by_req[rid].append(c)

    def strong_cases(req_id: str) -> list[dict]:
        """The passing cases that CITE this requirement, at or above the floor.

        Not the cases on a surface the requirement happens to sit on. Two
        requirements sharing SURF-001 do not share its evidence, and reading it
        that way retires a brief on a case about something else — which is what
        the out-of-family review refused.
        """
        return [c for c in by_req.get(req_id, [])
                if c.get("oracle") in RETIRING_RUNGS]

    def provider_ok(req_id: str) -> tuple[bool, str]:
        r = reqs.get(req_id) or {}
        if (r.get("effect") or "none") == "none":
            return True, "declares no external effect, so no provider is owed"
        if req_id in vacuous:
            return False, f"the vacuity census reports it: {vacuous[req_id]}"
        if not (r.get("provider") or "").strip():
            return False, "declares an external effect and names no provider"
        return True, "the vacuity census resolves its provider"

    # Which spec claims which brief, from the one place that says so: the
    # `**Brief:**` header. Built once.
    claiming_spec: dict[str, str] = {}
    for spec in sorted((ROOT / "docs" / "specs").glob("spec-PRO-*.md")):
        head = spec.read_text(errors="replace")[:1200]
        m = re.search(r"^\*\*Brief:\*\*\s*`([^`]+)`", head, re.M)
        if m:
            claiming_spec[Path(m.group(1)).name] = spec.stem.replace("spec-", "")

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

        # A brief an intake pass wrote and nobody has triaged yet is a REQUEST.
        # Its `reckon-sources` were written by that pass to route it, not by
        # somebody recording that the work is done — so evidence standing behind
        # those ids says nothing about this brief's own subject.
        #
        # Measured here, 2026-08-25: seven briefs were retired on exactly that
        # confusion. Brief 140 asks for a lane-selection record that does not
        # exist, cites REQ-130 and REQ-151 as a routing hint, and was retired
        # because those requirements carry six passing cases about instrument
        # identity. That is reckon's own warning — retiring stated intent on
        # evidence for a neighbour — arriving through the tool built to prevent
        # it. A hint is not a citation, and the difference is who wrote it.
        generated = re.search(r"^generated-by:\s*(\S+)\s*$", front, re.M)
        if generated and status == "to-triage":
            skipped.append({"brief": f.name,
                            "why": (f"written by {generated.group(1)} and still to-triage — its "
                                    f"sources route it, they do not record it as done")})
            continue

        text_all = front + "\n" + blank_fences(body)
        cited = sorted(set(REQ_ID.findall(text_all)))
        via_defect: list[str] = []
        for did in sorted(set(DEF_ID.findall(text_all))):
            d = defects.get(did)
            if not d or (d.get("status") or "").lower() not in ("fixed", "closed",
                                                                "resolved", "verified", "done"):
                continue
            # The registry spells this both ways — `requirements` on most rows
            # and `req` on DEF-215 among others. Reading one spelling silently
            # under-counts, and the row that gets missed is indistinguishable
            # from a row that had nothing to say.
            named = d.get("requirements") or ([d["req"]] if isinstance(d.get("req"), str)
                                              else (d.get("req") or []))
            for rid in named:
                if rid not in cited:
                    cited.append(rid)
                    via_defect.append(f"{rid} via {did}")
        cited = sorted(cited)
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

        # WHICH cases the record names, and why it is not simply the first six.
        #
        # `sorted(...)[:6]` takes whichever ids sort earliest, and on a
        # requirement carried by fifteen cases those are the oldest — cases about
        # something else that happen to cite the same requirement. Brief 163's
        # first record named CASE-0045, 0072, 0073, 0080, 0110 and 0111 while the
        # cases written FOR it, 0826 to 0828, appeared nowhere. The join was
        # sound and the witnesses were wrong, so a reader following the record
        # landed on unrelated work.
        #
        # Rank instead: a case whose note or evidence names this brief or its
        # spec first, then by rung with the strongest leading, then by id. And
        # print the total, so six is visibly a sample rather than the whole.
        stem = f.stem

        # A case names its work by SPEC id — "PRO-0168." opens most notes in this
        # registry — not by brief filename, so relevance has to go through the
        # spec whose `**Brief:**` header claims this brief. Without that hop,
        # brief 160's record led with the SIGPIPE case rather than either of the
        # two written for it.
        def names_this_brief(c: dict) -> int:
            blob = json.dumps(c)
            if stem in blob or f.name in blob:
                return 0
            if claiming_spec.get(f.name) and claiming_spec[f.name] in blob:
                return 0
            return 1

        # Strongest rung first, using the campaign's own ladder order.
        LADDER = ["outcome", "metamorphic", "effect-witness", "raster-visual",
                  "interactive-glass"]

        def rung_rank(c: dict) -> int:
            o = c.get("oracle")
            return -LADDER.index(o) if o in LADDER else 1

        ordered = sorted({c["id"]: c for c in support}.values(),
                         key=lambda c: (names_this_brief(c), rung_rank(c), c["id"]))
        ids = [c["id"] for c in ordered[:6]]
        support_total = len({c["id"] for c in support})
        surfaces = sorted({c["surface"] for c in support})
        req = carrying[0]
        rec = {"brief": f.name, "requirements": carrying, "surfaces": surfaces,
               "cases": ids, "provider": (reqs[req].get("provider") or "none"),
               "rungs": sorted({c["oracle"] for c in support}),
               "viaDefect": via_defect or None,
               "casesTotal": support_total,
               "casesShown": len(ids)}
        validated.append(rec)

        if a.record:
            # Frontmatter, never prose. reckon scans the body for id-shaped
            # tokens, so an id written into the body during a reckoning becomes
            # an edge in the next run's join — the tool feeding itself the
            # tokens it wants to read. A frontmatter key other than `sources` is
            # inert to that scan and legible to a person, which is the whole
            # requirement.
            lines = {
                "validated-by": (f"{', '.join(carrying)} via {', '.join(ids)}"
                                 + (f" ({len(ids)} of {support_total} citing case(s))"
                                    if support_total > len(ids) else "")),
                "validated-rungs": ", ".join(rec["rungs"]),
                "validated-provider": rec["provider"],
            }
            if via_defect:
                lines["validated-through-defect"] = "; ".join(via_defect)
            block = front
            if re.search(r"^status:", block, re.M):
                block = re.sub(r"^status:.*$", "status: retired", block, flags=re.M)
            else:
                block = (block + "\nstatus: retired").strip()
            for k, v in lines.items():
                line = f"{k}: {v}"
                if re.search(rf"^{k}:", block, re.M):
                    block = re.sub(rf"^{k}:.*$", line, block, flags=re.M)
                else:
                    block += "\n" + line
            f.write_text(f"---\n{block}\n---\n" + body.lstrip("\n"))

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
    # Grouped rather than listed: 144 skip lines is a wall nobody reads, and one
    # count per reason is the thing a reader is actually checking. A skip with no
    # reason printed is indistinguishable from a brief that was never examined.
    from collections import Counter
    for why, n in Counter(s["why"] for s in skipped).most_common():
        print(f"      {n:>4}  {why}")
    if blocked:
        print("\nblocked, first ten:")
        for b in blocked[:10]:
            print(f"  {b['brief']:<52} {b['why']}")
    if a.json:
        a.json.write_text(json.dumps(
            {"validated": validated, "blocked": blocked, "skipped": skipped}, indent=2) + "\n")
        print(f"\nwrote {a.json}")
    print("\nDRY RUN — pass --record to write the validation records in."
          if not a.record else "\nrecorded in frontmatter, and retired on that verdict.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
