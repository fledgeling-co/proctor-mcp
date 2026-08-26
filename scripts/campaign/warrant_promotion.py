#!/usr/bin/env python3
"""Warrant tier promotion: what qualifies, what blocks it, and what to sign.

A warrant class at tier 0 is advisory — a machine may close nothing in it
without a person looking. Raising a class is an evidenced act, and the evidence
is already on disk in three places that do not know about each other: the
charter says what each class covers and what threshold it must clear,
`oracle-coverage.json` says how many of each surface's cases stand on an effect
rung, and `suite-health.json` says whether the campaign gate was clear when
those numbers were taken.

This joins them, and it answers two different questions rather than one:

  qualifies    every threshold met — here is the ratification block to sign
  blocked      here are the surfaces, the counts and the case ids to fix

The second is the one that matters, because a rollup saying `84.0% (100 of 119)`
tells nobody what to do next. A class blocked by nineteen cases sitting below
the effect rung is nineteen pieces of work with ids, and until they are named
the number is a mood.

**A proposal is not a promotion.** The charter says the signature is the commit,
and that an agent committing it is not a signature. So nothing here edits
`warrant.toml`; it writes a proposal a named person applies. Producing the
document and signing it are deliberately two acts, and this tool only does the
first.

  warrant_promotion.py [--root DIR] [--json PATH] [--html PATH]
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from collections import defaultdict
from html import escape
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

# Rungs that can catch a wrong answer. Below these a case proves something
# rendered, or that the source says what it says, which is a different claim.
EFFECT_RUNGS = {"outcome", "metamorphic", "effect-witness",
                "raster-visual", "interactive-glass"}


def parse_charter(path: Path) -> dict:
    """The classes, tiers, thresholds and surface globs, read out of the TOML.

    Hand-parsed rather than via `tomllib` so the reason for every field read is
    visible here; the file is a flat list of `[[classes]]` tables and nothing in
    it needs a full parser.

    It is also the only reader of this file that runs everywhere. `tomllib`
    arrived in Python 3.11, and a Stop hook on this machine resolves `python3`
    to /usr/bin/python3, which is 3.9.6 — so two checks in test_instruments that
    imported it passed in a developer's shell and failed under the hook with
    `ModuleNotFoundError`, taking the whole suite red at 407 of 412. They read
    this instead, and `test_parse_charter_agrees_with_tomllib` compares the two
    field by field wherever tomllib is available, so the hand parser cannot
    drift from the format it is standing in for.
    """
    try:
        text = path.read_text()
    except OSError:
        return {}
    out = {"owner": {}, "classes": [], "signed": None, "renewal": None,
           "version": None, "lot": {}}
    for key in ("signed", "renewal", "version"):
        m = re.search(rf'^{key}\s*=\s*"([^"]+)"', text, re.M)
        if m:
            out[key] = m.group(1)
    # [lot].census_classes — the only field outside [[classes]] a gate reads.
    lot = re.search(r"^\[lot\]\s*\n(.*?)(?=^\[|\Z)", text, re.M | re.S)
    if lot:
        cc = re.search(r"census_classes\s*=\s*\[(.*?)\]", lot.group(1), re.S)
        if cc:
            out["lot"]["census_classes"] = re.findall(r'"([^"]+)"', cc.group(1))
        for k, v in re.findall(r"^(\w+)\s*=\s*([\d.]+)\s*$", lot.group(1), re.M):
            out["lot"][k] = float(v)
    owner = re.search(r"\[owner\]\s*\n((?:\s*\w+\s*=\s*\"[^\"]*\"\s*\n)+)", text)
    if owner:
        for k, v in re.findall(r'(\w+)\s*=\s*"([^"]*)"', owner.group(1)):
            out["owner"][k] = v
    for block in text.split("[[classes]]")[1:]:
        block = block.split("[[")[0]
        name = re.search(r'name\s*=\s*"([^"]+)"', block)
        tier = re.search(r"tier\s*=\s*(\d+)", block)
        esc = re.search(r'escalation\s*=\s*"([^"]+)"', block)
        surf = re.search(r"surfaces\s*=\s*\[(.*?)\]", block, re.S)
        census = re.search(r"census\s*=\s*(true|false)", block)
        plane = re.search(r'plane\s*=\s*"([^"]+)"', block)
        if not name:
            continue
        out["classes"].append({
            "name": name.group(1),
            "tier": int(tier.group(1)) if tier else 0,
            "escalation": esc.group(1) if esc else "owner",
            "surfaces": re.findall(r'"([^"]+)"', surf.group(1)) if surf else [],
            "census": (census.group(1) == "true") if census else None,
            "plane": plane.group(1) if plane else None,
        })
    return out


def glob_match(pattern: str, value: str) -> bool:
    return re.fullmatch(re.escape(pattern).replace(r"\*", ".*"), value) is not None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", type=Path, default=ROOT)
    ap.add_argument("--json", type=Path, default=None)
    ap.add_argument("--html", type=Path, default=None)
    a = ap.parse_args()

    warrant_dir = a.root / ".warrant"
    charter = parse_charter(warrant_dir / "warrant.toml")
    if not charter.get("classes"):
        print(f"no charter under {warrant_dir}. An absent charter is not an empty one, so "
              f"nothing is proposed.", file=sys.stderr)
        return 2

    coverage = json.loads((warrant_dir / "oracle-coverage.json").read_text())
    health = json.loads((warrant_dir / "suite-health.json").read_text())
    campaign = Path(health.get("campaign_dir") or (a.root / "docs" / "test-campaign"))
    raw = json.loads((campaign / "cases.json").read_text())
    cases = raw if isinstance(raw, list) else (raw.get("case") or raw.get("cases") or [])
    inv = json.loads((campaign / "inventory.json").read_text())
    route_of = {s["id"]: (s.get("route") or s["id"]) for s in inv.get("surface", [])}

    # Cases below the effect rung, keyed by the surface ROUTE the charter globs
    # against — the coverage file keys by route and the campaign keys by id, and
    # joining them on the wrong key is how a class reads as having no evidence.
    below: dict[str, list[dict]] = defaultdict(list)
    for c in cases:
        if not str(c.get("status", "")).startswith("pass"):
            continue
        if c.get("oracle") in EFFECT_RUNGS:
            continue
        below[route_of.get(c.get("surface"), c.get("surface") or "?")].append(c)

    by_route = {s["file"]: s for s in coverage.get("surfaces", [])}
    gate_clear = bool(health.get("campaign_gate_clear"))
    proposals, blocked = [], []

    for cls in charter["classes"]:
        routes = [r for r in by_route
                  if any(glob_match(p, r) for p in cls["surfaces"])]
        figures = sum(by_route[r]["figures"] for r in routes)
        sourced = sum(by_route[r]["sourced"] for r in routes)
        pct = (sourced / figures) if figures else 0.0
        short = sorted(
            ({"surface": r, "sourced": by_route[r]["sourced"],
              "figures": by_route[r]["figures"],
              "unsourced": by_route[r]["unsourced"],
              "cases": [{"id": c["id"], "oracle": c.get("oracle")} for c in below.get(r, [])]}
             for r in routes if by_route[r]["unsourced"]),
            key=lambda x: -x["unsourced"])
        row = {"class": cls["name"], "tier": cls["tier"], "escalation": cls["escalation"],
               "surfaces": len(routes), "figures": figures, "sourced": sourced,
               "pct": round(pct, 4), "gateClear": gate_clear, "shortfall": short}

        reasons = []
        if figures == 0:
            reasons.append("no surface in this class carries a case, so the threshold is "
                           "met over an empty population — a class with nothing in it is "
                           "not a class that passed")
        if pct < 1.0:
            reasons.append(f"{figures - sourced} of {figures} case(s) stand below the effect "
                           f"rung, across {len(short)} surface(s)")
        if not gate_clear:
            reasons.append("the campaign gate was not clear when these figures were taken, "
                           "so every number here describes a run that had not finished")
        if reasons:
            row["blockedBy"] = reasons
            blocked.append(row)
        else:
            row["proposedTier"] = cls["tier"] + 1
            proposals.append(row)

    print(f"warrant · owner {charter['owner'].get('name','?')} "
          f"<{charter['owner'].get('email','?')}> · signed {charter.get('signed')} · "
          f"renewal {charter.get('renewal')}")
    print(f"campaign gate clear: {gate_clear} · {len(cases)} case(s) · "
          f"{len(charter['classes'])} class(es)\n")

    if proposals:
        print(f"{len(proposals)} class(es) qualify for promotion:\n")
        for p in proposals:
            print(f"  {p['class']}  tier {p['tier']} -> {p['proposedTier']}  "
                  f"({p['sourced']}/{p['figures']} figures on an effect rung, "
                  f"{p['surfaces']} surface(s))")
        print("\nRatification block — apply to .warrant/warrant.toml and commit it under the")
        print("owner's own name. The charter says the signature is the commit, and that an")
        print("agent committing it is not a signature, so this tool writes it and stops.\n")
        for p in proposals:
            print(f'  # {p["class"]}: {p["sourced"]}/{p["figures"]} figures sourced on an '
                  f'effect rung across')
            print(f'  # {p["surfaces"]} surface(s), campaign gate clear. Proposed by '
                  f'warrant_promotion.py.')
            print(f'  [[classes]]')
            print(f'  name = "{p["class"]}"')
            print(f'  tier = {p["proposedTier"]}          # was {p["tier"]}')
            print(f'  escalation = "{p["escalation"]}"')
            print()
    else:
        print("No class qualifies for promotion.\n")

    print(f"{len(blocked)} class(es) blocked:\n")
    for b in blocked:
        print(f"  {b['class']}  tier {b['tier']}  "
              f"{100 * b['pct']:.1f}% ({b['sourced']} of {b['figures']})")
        for r in b["blockedBy"]:
            print(f"      · {r}")
        for s in b["shortfall"][:4]:
            ids = ", ".join(f"{c['id']}({c['oracle']})" for c in s["cases"][:5])
            print(f"      {s['surface']:<32} {s['unsourced']:>3} short"
                  + (f"   {ids}" if ids else "   (no passing sub-rung case found — the "
                                             "shortfall is in cases this join did not reach)"))
        if len(b["shortfall"]) > 4:
            print(f"      … and {len(b['shortfall']) - 4} more surface(s)")
        print()

    if a.json:
        a.json.write_text(json.dumps(
            {"owner": charter["owner"], "signed": charter.get("signed"),
             "renewal": charter.get("renewal"), "gateClear": gate_clear,
             "proposals": proposals, "blocked": blocked}, indent=2) + "\n")
        print(f"wrote {a.json}")

    if a.html:
        a.html.write_text(render_html(charter, proposals, blocked, gate_clear, len(cases)))
        print(f"wrote {a.html}")
    return 0


def render_html(charter, proposals, blocked, gate_clear, case_count) -> str:
    """One self-contained file. No network, no CDN, no font host — a dashboard
    that needs the internet is a dashboard that renders blank on the machine
    somebody actually opens it on."""
    def card(row, ok):
        pct = 100 * row["pct"]
        bars = "".join(
            f'<li><code>{escape(s["surface"])}</code>'
            f'<span class="n">{s["sourced"]}/{s["figures"]}</span>'
            f'<span class="short">{s["unsourced"]} short</span>'
            + ('<div class="ids">' + ", ".join(
                escape(f'{c["id"]} ({c["oracle"]})') for c in s["cases"][:8]) + "</div>"
               if s["cases"] else "")
            + "</li>"
            for s in row.get("shortfall", [])[:6])
        why = "".join(f"<li>{escape(r)}</li>" for r in row.get("blockedBy", []))
        head = (f'tier {row["tier"]} → <strong>{row["proposedTier"]}</strong>' if ok
                else f'tier {row["tier"]}')
        return f"""
    <article class="card {'ok' if ok else 'blocked'}">
      <header><h2>{escape(row['class'])}</h2><span class="tier">{head}</span></header>
      <div class="meter" role="img" aria-label="{pct:.1f} percent of figures on an effect rung">
        <div class="fill" style="width:{min(pct,100):.1f}%"></div>
      </div>
      <p class="figure"><strong>{pct:.1f}%</strong>
         <span>{row['sourced']} of {row['figures']} figures on an effect rung,
         across {row['surfaces']} surface(s)</span></p>
      {'<h3>What blocks it</h3><ul class="why">' + why + '</ul>' if why else ''}
      {'<h3>Where the shortfall is</h3><ul class="surfaces">' + bars + '</ul>' if bars else ''}
    </article>"""

    cards = "".join(card(p, True) for p in proposals) + \
            "".join(card(b, False) for b in blocked)
    return f"""<!doctype html>
<html lang="en-GB"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Warrant tiers — Proctor</title>
<style>
:root {{ --bg:#fbfaf8; --ink:#1a1a1a; --dim:#6b6b6b; --line:#e2ddd5;
        --ok:#2f6f4f; --blocked:#8a5a2b; --card:#fff; }}
@media (prefers-color-scheme: dark) {{
  :root {{ --bg:#16161a; --ink:#eceae6; --dim:#9a968f; --line:#2e2e34;
          --ok:#6cc79a; --blocked:#c99a5e; --card:#1e1e24; }} }}
* {{ box-sizing:border-box; }}
body {{ margin:0; padding:2.5rem 1.5rem 4rem; background:var(--bg); color:var(--ink);
       font:16px/1.55 -apple-system,BlinkMacSystemFont,"Segoe UI",Helvetica,Arial,sans-serif; }}
.wrap {{ max-width:56rem; margin:0 auto; }}
h1 {{ font-size:1.6rem; margin:0 0 .3rem; letter-spacing:-.01em; }}
.sub {{ color:var(--dim); margin:0 0 2rem; font-size:.92rem; }}
.card {{ background:var(--card); border:1px solid var(--line); border-radius:12px;
        padding:1.15rem 1.3rem 1.3rem; margin:0 0 1rem; }}
.card header {{ display:flex; align-items:baseline; justify-content:space-between; gap:1rem; }}
h2 {{ font-size:1.05rem; margin:0; font-family:ui-monospace,SFMono-Regular,Menlo,monospace; }}
.tier {{ color:var(--dim); font-size:.85rem; white-space:nowrap; }}
.meter {{ height:6px; background:var(--line); border-radius:3px; overflow:hidden; margin:.8rem 0 .55rem; }}
.fill {{ height:100%; background:var(--blocked); }}
.card.ok .fill {{ background:var(--ok); }}
.figure {{ margin:0; font-size:.9rem; }}
.figure span {{ color:var(--dim); margin-left:.4rem; }}
h3 {{ font-size:.78rem; text-transform:uppercase; letter-spacing:.06em; color:var(--dim);
     margin:1.1rem 0 .4rem; font-weight:600; }}
ul {{ margin:0; padding:0; list-style:none; font-size:.88rem; }}
.why li {{ padding:.25rem 0 .25rem .9rem; position:relative; }}
.why li::before {{ content:"·"; position:absolute; left:.15rem; color:var(--dim); }}
.surfaces li {{ padding:.35rem 0; border-top:1px solid var(--line); }}
.surfaces li:first-child {{ border-top:0; }}
.surfaces code {{ font-size:.84rem; }}
.n {{ color:var(--dim); margin-left:.6rem; }}
.short {{ float:right; color:var(--blocked); font-size:.82rem; }}
.ids {{ color:var(--dim); font-size:.78rem; margin-top:.15rem;
       font-family:ui-monospace,SFMono-Regular,Menlo,monospace; overflow-x:auto; }}
footer {{ color:var(--dim); font-size:.82rem; margin-top:2rem; border-top:1px solid var(--line);
         padding-top:1rem; }}
</style></head><body><div class="wrap">
<h1>Warrant tiers</h1>
<p class="sub">Owner {escape(charter['owner'].get('name','?'))} ·
signed {escape(str(charter.get('signed')))} · renewal {escape(str(charter.get('renewal')))} ·
campaign gate {'clear' if gate_clear else 'NOT clear'} · {case_count} cases</p>
{cards}
<footer>A tier above 0 means a machine may close items in that class and no person will
look at the item. A proposal is not a promotion: the charter says the signature is the
commit, and that an agent committing it is not a signature. Generated by
<code>scripts/campaign/warrant_promotion.py</code>; no network resource is referenced.</footer>
</div></body></html>
"""


if __name__ == "__main__":
    sys.exit(main())
