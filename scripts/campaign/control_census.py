#!/usr/bin/env python3
"""Every surface's controls, declared and checked against the source that draws them.

The control census read `4 of 34 declared control(s) actuated, across 2 surface(s)
that declare any` — and both numbers came from two surfaces out of forty. A
fraction over 5% of the surface list describes the list, not the product.

TWO KINDS OF SURFACE, AND ONLY ONE OF THEM HAS CONTROLS. `ui://status-window`
has buttons. `engine://screen-capture` and `tool://reckon/build` do not: they are
engines and instruments, reached by a call rather than a click. Asking those to
enumerate controls would produce forty empty lists and no information.

So each surface is classed by its route scheme, and the two classes owe different
things. A non-interactive surface owes an EXPLICIT empty list, because absent and
zero read identically in a census and only one of them is a decision. An
interactive surface owes a declaration checked against the file that draws it —
that is what "taken from its own source of truth" has to mean if it is to stay
true when the source changes.

WHAT COUNTS AS A CONTROL, PER KIND. A SwiftUI surface's `Button(...)` and
`Toggle(...)`. A TUI's key cases. A CLI's verbs. Each is extracted from the file
named in the surface's own `controlSource`, so a surface that grows a button and
does not declare it is a finding rather than a silence.

    python3 scripts/campaign/control_census.py [--write] [--gate] [--json OUT]

`--write` fills in the empty lists for non-interactive surfaces, which is
transcription. It never invents a control for an interactive one.

Exit codes
    0   every surface declares a control list, and every interactive one matches
        the source that draws it
    1   a surface is silent rather than empty, or its declaration and its source
        disagree
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CAMPAIGN = ROOT / "docs" / "test-campaign"

# A route scheme says whether a person can touch the surface at all.
INTERACTIVE_SCHEMES = ("ui://", "cli://", "proctor://panel/")
NON_INTERACTIVE_SCHEMES = ("engine://", "tool://", "core://", "stdio://", "mcp://",
                           "process://", "cgwindow://")

# Controls, per kind of source. Each pattern is here because it was read in this
# tree, not because it is what SwiftUI or a CLI might contain in general.
# `commandButton(CID.pause)` is this app's own button wrapper and is how the
# menu-bar and run-HUD commands are drawn, so a matcher that knew only `Button(`
# read the HUD as having none.
SWIFT_CONTROL = re.compile(
    r"\b(?:Button|Toggle|commandButton)\s*\(\s*"
    r"(?:\"([^\"]+)\"|([A-Za-z_][\w.]*(?:\([^)]*\))?))")
# The CLI's verbs are built from the tool specs rather than written out, so its
# source of truth is the table, not a switch.
CLI_SURFACE_VERB = re.compile(r'verbName\(for:\s*spec\.name\)|name:\s*"([a-z][\w-]*)"')
# A shell script's controls are what an OPERATOR sets, which is a `${VAR:-...}`
# read with a default — not `VAR=` assignments, which are the script's own
# working state. The first version matched assignments and reported APP_DEST and
# BUILT_APP as installer controls.
SHELL_INPUT = re.compile(r"\$\{([A-Z][A-Z0-9_]*):-")
# `CommandSurface.all` declares, per command, which surfaces draw it — so one
# file drawing both the menu-bar extra and the run HUD can still be split by the
# thing that decides it rather than by which file it lives in.
COMMAND_ENTRY = re.compile(
    r"\.init\(\s*id:\s*CommandID\.(\w+)\s*,\s*title:\s*\"([^\"]+)\""
    r"(?P<rest>(?:[^)]|\([^)]*\))*?)surfaces:\s*\[([^\]]*)\]", re.S)
TUI_KEY = re.compile(r'^\s*case\s+((?:"[a-z]+"\s*,?\s*)+):', re.M)
CLI_VERB = re.compile(r'^\s*case\s+"([a-z][\w-]*)"\s*:', re.M)


def classify(route: str) -> str:
    if route.startswith(INTERACTIVE_SCHEMES):
        return "interactive"
    if route.startswith(NON_INTERACTIVE_SCHEMES):
        return "non-interactive"
    return "unclassified"


def controls_in_source(path: Path, kind: str) -> list[str]:
    try:
        text = path.read_text(errors="replace")
    except OSError:
        return []
    if kind == "tui":
        keys: list[str] = []
        for group in TUI_KEY.findall(text):
            keys.extend(re.findall(r'"([a-z]+)"', group))
        return sorted(set(keys))
    if kind == "cli":
        return sorted(set(CLI_VERB.findall(text)))
    if kind == "cli-verbs":
        # Derived from the tool catalogue at runtime; the names live there.
        cat = ROOT / "Sources" / "ProctorCore" / "ToolCatalogue.swift"
        try:
            names = re.findall(r'ToolSpec\(\s*name:\s*"proctor_(\w+)"', cat.read_text())
        except OSError:
            names = []
        return sorted(set(n.replace("_", "-") for n in names) | {"tui", "completion"})
    if kind == "shell":
        # The installer's siblings are part of the same surface.
        inputs = set(SHELL_INPUT.findall(text))
        for sibling in ("notarize.sh", "uninstall.sh"):
            try:
                inputs |= set(SHELL_INPUT.findall(
                    (path.parent / sibling).read_text(errors="replace")))
            except OSError:
                pass
        return sorted(inputs)
    if kind.startswith("command-surface:"):
        want = kind.split(":", 1)[1]
        return sorted({title for _id, title, _rest, surfaces in
                       ((m.group(1), m.group(2), m.group("rest"), m.group(4))
                        for m in COMMAND_ENTRY.finditer(text))
                       if want in surfaces})
    found = []
    for literal, symbol in SWIFT_CONTROL.findall(text):
        found.append(literal or symbol)
    return sorted(set(found))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--campaign", default=str(CAMPAIGN))
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--gate", action="store_true")
    ap.add_argument("--json")
    a = ap.parse_args()

    inv_path = Path(a.campaign) / "inventory.json"
    inv = json.loads(inv_path.read_text())
    raw_cases = json.loads((Path(a.campaign) / "cases.json").read_text())
    cases = raw_cases if isinstance(raw_cases, list) else raw_cases.get("cases", [])

    # Only a PASSING case at or above the outcome rung moves the actuated count.
    # Driving a control and asserting the control is still there has measured the
    # click and not the effect.
    EFFECT = {"outcome", "metamorphic", "effect-witness", "raster-visual",
              "interactive-glass"}
    actuated: dict[str, set[str]] = {}
    for c in cases:
        if c.get("status") != "pass" or c.get("oracle") not in EFFECT:
            continue
        for name in c.get("actuates") or []:
            actuated.setdefault(c.get("surface", "?"), set()).add(name)

    rows, silent, mismatched, unclassified = [], [], [], []
    filled = 0
    for s in inv.get("surface", []):
        route = s.get("route") or ""
        kind = classify(route)
        declared = s.get("controls")
        row = {"id": s["id"], "route": route, "class": kind,
               "declared": declared, "source": s.get("controlSource")}

        if kind == "unclassified":
            unclassified.append(row)
        elif kind == "non-interactive":
            if declared is None:
                if a.write:
                    s["controls"] = []
                    s.setdefault("controlsNote",
                                 f"No controls: {route.split('://')[0]} surfaces are reached by a "
                                 f"call rather than a click. An explicit empty list, because "
                                 f"absent and zero read identically in a census.")
                    filled += 1
                    row["declared"] = []
                else:
                    silent.append(row)
        else:
            src = s.get("controlSource")
            if declared is None:
                silent.append(row)
            elif src:
                path = ROOT / src.split("#")[0]
                skind = src.split("#")[1] if "#" in src else "swift"
                found = controls_in_source(path, skind)
                missing = [c for c in found if c not in (declared or [])]
                row["inSource"] = found
                row["undeclared"] = missing
                if missing:
                    mismatched.append(row)

        got = actuated.get(s["id"], set())
        row["actuated"] = sorted(got & set(declared or []))
        row["unactuated"] = sorted(set(declared or []) - got)
        rows.append(row)

    interactive = [r for r in rows if r["class"] == "interactive"]
    declaring = [r for r in rows if r["declared"] is not None]
    total_controls = sum(len(r["declared"] or []) for r in rows)
    total_actuated = sum(len(r["actuated"]) for r in rows)

    print(f"{len(rows)} surface(s) — {len(interactive)} interactive, "
          f"{len(rows) - len(interactive) - len(unclassified)} non-interactive, "
          f"{len(unclassified)} unclassified")
    print(f"  declaring a control list   {len(declaring)} of {len(rows)}")
    print(f"  controls declared          {total_controls}")
    print(f"  actuated by a passing case at an effect rung   {total_actuated} of "
          f"{total_controls}")

    if unclassified:
        print()
        print("Route scheme this census cannot place — a surface it cannot class is not one "
              "it has counted:")
        for r in unclassified:
            print(f"  {r['id']}  {r['route']}")
    if silent:
        print()
        print("Silent rather than empty — a census cannot tell 'no controls' from 'nobody said':")
        for r in silent:
            print(f"  {r['id']}  {r['class']}  {r['route']}")
    if mismatched:
        print()
        print("The source draws a control the surface does not declare:")
        for r in mismatched:
            print(f"  {r['id']}  {r['source']}")
            for c in r["undeclared"][:8]:
                print(f"      undeclared: {c}")

    unact = [(r["id"], c) for r in rows for c in r["unactuated"]]
    if unact:
        print()
        print(f"Declared and not actuated by any passing effect-rung case ({len(unact)}), named "
              f"rather than counted in aggregate:")
        for sid, c in unact[:30]:
            print(f"  {sid}  {c}")
        if len(unact) > 30:
            print(f"  … and {len(unact) - 30} more")

    if a.write and filled:
        inv_path.write_text(json.dumps(inv, indent=2) + "\n")
        print()
        print(f"wrote {filled} explicit empty control list(s) — transcription, not invention")

    if a.json:
        Path(a.json).write_text(json.dumps(
            {"surfaces": rows, "declaredControls": total_controls,
             "actuated": total_actuated, "silent": [r["id"] for r in silent],
             "mismatched": [r["id"] for r in mismatched],
             "unclassified": [r["id"] for r in unclassified]}, indent=2) + "\n")

    print()
    problems = len(silent) + len(mismatched) + len(unclassified)
    if problems:
        print(f"FAIL  {len(silent)} silent, {len(mismatched)} contradicted by their source, "
              f"{len(unclassified)} unclassifiable.")
        return 1 if a.gate else 0
    print(f"PASS: all {len(rows)} surfaces declare a control list; every interactive one covers "
          f"what its source draws; {total_actuated} of {total_controls} controls are actuated.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
