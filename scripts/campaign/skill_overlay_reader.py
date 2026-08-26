#!/usr/bin/env python3
"""Which skills carry a family overlay, and whether the running family owes it.

A skill directory may hold a file addressed to one model family beside its
SKILL.md — `gemini.md` is the shape in use here — and SKILL.md itself says to
read it first. An audit found one present and unread, and nothing in the run
said so, which is the same failure as an absent instrument nobody mentioned: the
operator cannot tell "did not apply" from "was not opened".

So the overlay is enumerated rather than remembered, and three states are kept
apart because they carry different remedies:

  absent        no overlay for this family — nothing is owed, and that is
                a finding only if the skill's own text claims one
  not-mine      an overlay exists for a family this run is not — correctly
                skipped, and worth printing so a reader can see it was seen
  owed          an overlay for the running family, which the run must read

The distinction that matters is the last two. Reporting `not-mine` as clean
hides the case where the family changed and nobody re-checked; reporting it as
`owed` cries wolf on a correct run, which is how a check gets switched off.

  skill_overlay_reader.py [--family NAME] [--cache DIR] [--json PATH] [--gate]
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CACHE = Path.home() / ".claude" / "plugins" / "cache"

# The overlay filenames in use, mapped to the family each addresses. A file this
# does not know about is reported as an unrecognised overlay rather than ignored
# — an overlay nobody classified is exactly the one that goes unread.
KNOWN = {"gemini.md": "google", "gpt.md": "openai", "codex.md": "openai",
         "grok.md": "xai", "claude.md": "anthropic"}

# A skill claiming an overlay in its own prose. When the claim is there and the
# file is not, the skill is the thing that is wrong.
#
# The claim must name a file that would sit BESIDE the SKILL.md. `tailings`
# addresses a Gemini run and points it at `references/probes.md`, which is a
# reference page it already ships — reporting that as a missing overlay is the
# cry-wolf case, and a check that cries wolf on correct guidance is one nobody
# leaves switched on.
CLAIMS = re.compile(
    r"Running as a (\w+) model\?[^\n]{0,120}?`([a-z0-9-]+\.md)`[^\n]{0,40}?in this directory",
    re.I)

# The idiom an overlay itself opens with. A file is only overlay-shaped if it
# reads like one: `prompts.md` in a benchmark skill carries the comment
# `<!-- model: gemini -->` and matched a looser test for the word "model",
# which is a false positive on a file that is not addressed to anybody.
OVERLAY_IDIOM = re.compile(r"Running as a \w+ model|overrides it names|"
                           r"Other models skip it", re.I)


def version_key(name: str) -> tuple:
    return tuple(int(x) if x.isdigit() else -1 for x in name.split("."))


# The plugin cache is not a static tree. `plugin install` and the marketplace
# refresh create `temp_git_<epoch>_<rand>` directories and remove them again, so
# a walk of the cache races whoever is installing.
#
# Measured 2026-08-26: `Path.rglob("SKILL.md")` raised
# `FileNotFoundError: .../cache/temp_git_1787749743021_1vk8u4` inside
# `_iterate_directories` and took the whole standing-gate set red — a crash
# about somebody else's install, in a check about overlay provenance.
#
# Two answers, and both are needed. Prune `temp_git_*` by name, because a
# SKILL.md inside one is a half-cloned copy that will not exist in a minute and
# a finding from it is noise. And tolerate any directory vanishing anyway, since
# pruning the known shape does not make the tree static — counting what was
# skipped so a walk that missed half the cache is visible rather than quiet.
TRANSIENT = re.compile(r"^temp_git_\d+_\w+$")


def walk_skills(cache: Path) -> list[Path]:
    """Every SKILL.md under the cache, tolerating a tree being mutated under it."""
    found: list[Path] = []
    vanished: list[str] = []
    pruned = 0
    for root, dirs, files in os.walk(cache, onerror=lambda e: vanished.append(str(e))):
        keep = []
        for d in dirs:
            if TRANSIENT.match(d):
                pruned += 1
            else:
                keep.append(d)
        dirs[:] = keep
        if "SKILL.md" in files:
            found.append(Path(root) / "SKILL.md")
    if pruned or vanished:
        print(f"walk: {len(found)} SKILL.md found · {pruned} transient temp_git_* "
              f"director(ies) pruned · {len(vanished)} vanished mid-walk")
        for v in vanished[:3]:
            print(f"      {v}")
    return found


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--family", default="anthropic",
                    help="the family this run belongs to (default: anthropic)")
    ap.add_argument("--cache", type=Path, default=DEFAULT_CACHE)
    ap.add_argument("--json", type=Path, default=None)
    ap.add_argument("--gate", action="store_true")
    a = ap.parse_args()

    if not a.cache.is_dir():
        print(f"no plugin cache at {a.cache}. An absent cache is not an empty one: nothing "
              f"here can say whether an overlay went unread.", file=sys.stderr)
        return 2

    # Newest copy of each SKILL only, across every marketplace. Three mistakes
    # are avoidable here and each was made on the way to this version.
    #
    # Keying on the plugin alone loses the other skills in a multi-skill plugin.
    # Keying on (marketplace, plugin) keeps a superseded copy from a second
    # marketplace alive: `diolog-plugins/mac-design-digest/1.2.0` has no overlay
    # and `fledgeling-plugins/mac-design-digest/1.3.0` has one, and reporting the
    # first as "claims an overlay, has none" describes a copy nobody resolves.
    # And counting every version multiplies each finding by the number on disk —
    # reckon alone has four.
    #
    # So the key is the skill name, the newest version across marketplaces wins,
    # and a skill carried by more than one marketplace is reported: a stale copy
    # a resolver could pick is a fact worth naming even when it is not read.
    newest: dict[str, Path] = {}
    carriers: dict[str, set[str]] = {}
    for skill in sorted(walk_skills(a.cache)):
        parts = skill.relative_to(a.cache).parts
        if len(parts) < 4:
            continue
        marketplace, plugin, version, name = parts[0], parts[1], parts[2], parts[-2]
        carriers.setdefault(name, set()).add(f"{marketplace}/{plugin}")
        prev = newest.get(name)
        if prev is None or version_key(version) > version_key(
                prev.relative_to(a.cache).parts[2]):
            newest[name] = skill

    rows, owed, unrecognised = [], [], []
    for name, skill in sorted(newest.items()):
        parts = skill.relative_to(a.cache).parts
        marketplace, plugin = parts[0], parts[1]
        d = skill.parent
        overlays = []
        for f in sorted(d.iterdir()):
            if not f.is_file() or f.suffix != ".md" or f.name == "SKILL.md":
                continue
            fam = KNOWN.get(f.name.lower())
            if fam is None:
                # Only files that look addressed to a family. A references/ page
                # is documentation, not an overlay, and treating every .md as one
                # would report the whole cache as unread.
                if OVERLAY_IDIOM.search(f.read_text(errors="replace")[:1200]):
                    unrecognised.append(str(f.relative_to(a.cache)))
                continue
            overlays.append({"file": str(f.relative_to(a.cache)), "family": fam,
                             "state": "owed" if fam == a.family else "not-mine"})
        cm = CLAIMS.search(skill.read_text(errors="replace")[:6000])
        claim = bool(cm)
        claimed_file = cm.group(2) if cm else None
        row = {"plugin": plugin, "skill": d.name, "marketplace": marketplace,
               "version": parts[2], "overlays": overlays,
               "alsoCarriedBy": sorted(carriers.get(name, set()) - {f"{marketplace}/{plugin}"}),
               "skillClaimsAnOverlay": claim, "claimedFile": claimed_file}
        if claim and claimed_file and not (d / claimed_file).is_file():
            row["finding"] = (f"the skill's own text says to read `{claimed_file}` in this "
                              f"directory, and no such file sits beside it")
        rows.append(row)
        owed.extend(o for o in overlays if o["state"] == "owed")

    with_overlay = [r for r in rows if r["overlays"]]
    claiming_none = [r for r in rows if r.get("finding")]
    duplicated = [r for r in rows if r["alsoCarriedBy"]]

    print(f"family: {a.family} · {len(rows)} skill(s) at their newest version · "
          f"{len(with_overlay)} carry an overlay")
    print(f"  owed by this family   {len(owed):>4}")
    print(f"  for another family    {sum(1 for r in rows for o in r['overlays'] if o['state'] == 'not-mine'):>4}"
          f"   (seen and correctly skipped — printed so a family change cannot pass unnoticed)")
    print(f"  unrecognised overlay  {len(unrecognised):>4}")
    print(f"  claims one, has none  {len(claiming_none):>4}")
    print(f"  carried twice         {len(duplicated):>4}"
          f"   (a second marketplace holds an older copy a resolver could pick)")

    if owed:
        print(f"\nOWED — this run belongs to {a.family} and these address it:")
        for o in owed:
            print(f"  {o['file']}")
    if claiming_none:
        print("\nA skill whose text promises an overlay that is not beside it:")
        for r in claiming_none[:8]:
            print(f"  {r['plugin']}/{r['skill']}  — {r['finding']}")
    if duplicated:
        print("\nSkills a second marketplace also carries — the newest was read, and the "
              "other copy is named so a resolver picking it is not a silent change:")
        for r in duplicated[:8]:
            print(f"  {r['skill']:<28} read {r['marketplace']}/{r['plugin']}@{r['version']}"
                  f"   also in {', '.join(r['alsoCarriedBy'])}")
    if unrecognised:
        print(f"\n{len(unrecognised)} file(s) look addressed to a model and this tool has no "
              f"family for them. An overlay nobody classified is the one that goes unread:")
        for u in unrecognised[:8]:
            print(f"  {u}")

    if a.json:
        a.json.write_text(json.dumps(
            {"family": a.family, "skills": len(rows), "owed": owed,
             "unrecognised": unrecognised,
             "claimingWithNoOverlay": [r["plugin"] + "/" + r["skill"] for r in claiming_none],
             "rows": with_overlay}, indent=2) + "\n")
        print(f"\nwrote {a.json}")

    if a.gate:
        # The gate fires on what this run owes and on a promise the cache cannot
        # keep. It does not fire on another family's overlay, which is the false
        # positive that would make it worth switching off.
        if owed:
            print(f"\nFAIL  {len(owed)} overlay(s) address this run's family and must be read "
                  f"before the skill is followed.")
            return 1
        if unrecognised:
            print(f"\nFAIL  {len(unrecognised)} overlay-shaped file(s) have no family here, so "
                  f"nothing can say whether this run owes them.")
            return 1
        print(f"\ngate: no overlay addresses {a.family}, and every overlay-shaped file on disk "
              f"has a family this tool can place.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
