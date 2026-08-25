#!/usr/bin/env python3
"""Execute an arming claim, instead of reading it.

Every case carries an `armedBy` string saying what was done to make it fail, and
until now nothing read one. Measured 2026-08-25: a case named a test as its arm
and that test passes with the fix removed — the defect was real, the fix was
real, the suite as a whole did bite, and the named test did not. An arming claim
is the sentence a reader trusts when deciding whether a green case means
anything, and 468 of them are prose.

So the claim becomes executable. A case may carry an `arm` object beside its
prose:

    "arm": {"file": "Sources/ProctorCore/Transport.swift",
            "remove": "        if s >= 0 { proctorSuppressSIGPIPE(s) }",
            "expectRed": ["swift", "test", "--filter", "SocketBoundaryChaos"]}

and this applies it, runs the command, requires a non-zero exit, restores the
file and requires the restore to land. Red with the change and green without it
is the whole claim; anything else is reported.

**The denominator is the point.** Structuring 468 prose arms would be authoring
claims nobody has established, so this reports what it can check and what it
cannot, and a prose-only arm is `unverifiable` — never `armed`. A verified-arm
count with no denominator beside it would be the failure this campaign is built
against, one layer in.

Three refusals, each from something that went wrong while this was written:

  * A change that does not land is reported, never run. A splice that failed and
    a check that cannot fail are indistinguishable from the exit code alone.
  * A restore that does not land aborts the whole run. The next arm would
    otherwise be applied on top of the last one.
  * An `expectRed` command that is already red on the unmodified tree proves
    nothing, so the baseline is taken first and a case whose command is red
    before the change is reported rather than counted.

  arming_verify.py <campaign-dir> [--case CASE-0808] [--json PATH] [--gate]
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def load_cases(campaign: Path) -> list[dict]:
    raw = json.loads((campaign / "cases.json").read_text())
    return raw if isinstance(raw, list) else (raw.get("case") or raw.get("cases") or [])


def run(cmd: list[str]) -> int:
    return subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True).returncode


def tree_is_clean(paths: list[str]) -> list[str]:
    """Which of these files git sees as modified right now.

    Checked before every arm rather than once at the start. A previous arm that
    failed to restore would otherwise make the next one's baseline red, and the
    run would report `unverifiable` about a tree the run itself dirtied — which
    happened once while this was being written, and cost a wrong conclusion
    about a case whose arm was fine.
    """
    out = subprocess.run(["git", "-C", str(ROOT), "status", "--porcelain", "--"] + paths,
                         capture_output=True, text=True).stdout
    return [ln[3:] for ln in out.splitlines() if ln.strip()]


def verify(case: dict) -> dict:
    arm = case["arm"]
    f = ROOT / arm["file"]
    target = arm.get("remove") or arm.get("before")
    if not f.is_file():
        return {"case": case["id"], "verdict": "unverifiable",
                "why": f"{arm['file']} is not on disk"}
    dirty = tree_is_clean([arm["file"]])
    if dirty:
        return {"case": case["id"], "verdict": "unverifiable",
                "why": (f"{arm['file']} is already modified in the working tree, so a baseline "
                        f"taken now measures somebody else's edit")}
    original = f.read_text()
    if original.count(target) != 1:
        return {"case": case["id"], "verdict": "unverifiable",
                "why": (f"the anchor appears {original.count(target)} time(s) in "
                        f"{arm['file']}; a change needs exactly one site")}

    # Baseline first. A command already red on the unmodified tree proves nothing
    # about the change, and counting it would be the cheapest possible way to
    # manufacture a verified arm.
    base = run(arm["expectRed"])
    if base != 0:
        return {"case": case["id"], "verdict": "unverifiable",
                "why": f"the expectRed command is already red on the unmodified tree (exit {base})"}

    replacement = arm.get("after", "")
    try:
        f.write_text(original.replace(target, replacement, 1))
        if target in f.read_text():
            f.write_text(original)
            return {"case": case["id"], "verdict": "unverifiable",
                    "why": "the change did not land; a splice that failed and a check that "
                           "cannot fail look the same from the exit code"}
        code = run(arm["expectRed"])
    finally:
        f.write_text(original)
        if f.read_text() != original:
            raise SystemExit(f"RESTORE FAILED for {arm['file']} — stopping rather than "
                             f"applying the next arm on top of this one")

    if code != 0:
        return {"case": case["id"], "verdict": "verified",
                "why": f"green at baseline, exit {code} with the change applied"}
    return {"case": case["id"], "verdict": "does-not-arm",
            "why": ("the named command stays green with the change applied, so this case's arm "
                    "does not discriminate — the claim names something that does not bite")}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("campaign", type=Path)
    ap.add_argument("--case", action="append")
    ap.add_argument("--json", type=Path, default=None)
    ap.add_argument("--gate", action="store_true")
    a = ap.parse_args()

    cases = load_cases(a.campaign)
    armed = [c for c in cases if c.get("armed")]
    structured = [c for c in armed if isinstance(c.get("arm"), dict)]
    prose_only = [c for c in armed if not isinstance(c.get("arm"), dict)]
    if a.case:
        structured = [c for c in structured if c["id"] in set(a.case)]

    results = [verify(c) for c in structured]
    verified = [r for r in results if r["verdict"] == "verified"]
    broken = [r for r in results if r["verdict"] == "does-not-arm"]
    unver = [r for r in results if r["verdict"] == "unverifiable"]

    print(f"{len(cases)} case(s) · {len(armed)} armed · "
          f"{len(structured)} carrying a machine-readable arm")
    print(f"  verified      {len(verified):>4}  green at baseline, red with the change applied")
    print(f"  does-not-arm  {len(broken):>4}  the named command stays green — the claim names "
          f"something that does not bite")
    print(f"  unverifiable  {len(unver):>4}  the arm could not be applied; reported, never counted "
          f"as armed")
    print(f"\n{len(prose_only)} armed case(s) carry prose only, out of {len(armed)}. "
          f"{100.0 * len(structured) / len(armed):.1f}% of arming claims on this campaign are "
          f"machine-checkable, and the rest are a sentence somebody wrote. That denominator is "
          f"the finding; structuring them by hand would author claims nobody has established.")

    for r in broken:
        print(f"\nFAIL  {r['case']}: {r['why']}")
    for r in unver:
        print(f"      {r['case']} unverifiable: {r['why']}")
    for r in verified:
        print(f"      {r['case']} verified: {r['why']}")

    if a.json:
        a.json.write_text(json.dumps(
            {"cases": len(cases), "armed": len(armed), "structured": len(structured),
             "proseOnly": len(prose_only), "results": results}, indent=2) + "\n")
        print(f"\nwrote {a.json}")

    if a.gate:
        if broken:
            print(f"\nFAIL  {len(broken)} case(s) name an arm that does not discriminate.")
            return 1
        if unver:
            # An arm that could not be applied is not an arm that passed, and a
            # success line saying "every arm was applied" over one that was not
            # is the shape this whole file exists to catch.
            print(f"\nFAIL  {len(unver)} arm(s) could not be applied, so nothing here says "
                  f"whether they discriminate.")
            return 1
        print(f"\ngate: {len(verified)} of {len(structured)} machine-readable arm(s) applied and "
              f"took their named command red; {len(prose_only)} armed case(s) remain prose.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
