#!/usr/bin/env python3
"""A path citation in a durable artifact resolves from the repository root.

An out-of-family audit reported thirty citations as "a cited path exists
nowhere in the repo or its history", over files that all exist:
`spec-PRO-0073.md`, `capture-lineage.py`, `campaign.json`, `OverlayCapture.swift`.
Every one was a bare filename. The reader was right and the tool was right; what
failed was the citation, which resolves for somebody who already knows the tree
and for nobody else.

That is worse than a broken link, because it fails silently in one direction: an
insider reads it and it works, an outsider reads it and reports a defect that is
not there. The thirty findings cost a diagnosis each.

WHAT COUNTS AS A CITATION. A backticked token with a path-shaped extension, in a
durable artifact — the files another session plans from. Prose that merely names
a tool ("run capture-lineage") is not a citation and is not read here; the
backticks are the author saying "this is a thing on disk".

THREE OUTCOMES, AND THE THIRD IS THE ONE A NAIVE FIXER GETS WRONG. A citation
that resolves from the root passes. A bare filename matching exactly one file is
reported with the repository-relative path that would fix it, because that fix
is mechanical. A bare filename matching several is reported AMBIGUOUS and no
path is offered: resolving it to the first match is how a citation comes to point
at the wrong file while looking repaired.

    python3 scripts/campaign/path_citation_check.py [--root .] [--gate] [--json OUT]

Exit codes
    0   every citation resolves from the root
    1   at least one does not, listed with what would fix it
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

# The artifacts another session plans from. A chat reply is band 3 and scrolls
# away; these do not.
DURABLE = ["ORCHESTRATOR.md", "README.md", "CLAUDE.md",
           "docs/feature-specs/LEDGER.md", "docs/feature-specs/UNCLAIMED-BRIEFS.md",
           "docs/PRD.md", "docs/architecture.md"]
DURABLE_GLOBS = ["docs/specs/*.md", "docs/features-to-triage/*.md", "tailings/*.md"]

# A backticked token carrying an extension this repository actually keeps.
EXTENSIONS = ("md", "py", "swift", "json", "sh", "html", "yml", "yaml", "txt",
              "jsonl", "png", "toml", "mjs")
CITATION = re.compile(r"`([A-Za-z0-9_./\-]+\.(?:%s))`" % "|".join(EXTENSIONS))

# Directories whose contents are not the repository's own files.
SKIP_DIRS = {".build", ".git", ".worktrees", "node_modules", "__pycache__"}

# A citation may legitimately name a file that is not in this repository:
# `campaign.py`, `reckon.py` and `capture-lineage.py` all live in the installed
# plugin cache, and a repository-relative path for them would be a lie. Those
# are classed EXTERNAL rather than absent, because "cite it from the root" has
# no root to cite from. Distinguishing them is what keeps the absent list small
# enough that somebody reads it.
PLUGIN_CACHE = Path.home() / ".claude" / "plugins" / "cache"

# Artifacts where the FORM of a citation is load-bearing for another tool, so
# expanding a bare name changes what that tool reads.
#
# Measured, by breaking it: `--fix` rewrote 742 citations including these, and
# `spec_citation_measure.py` went from 19/19 to 16/19. Two things happened.
# `docs/feature-specs/UNCLAIMED-BRIEFS.md` keys its shared-parent table on bare
# brief names, so expanding them orphaned every row. And `spec-PRO-0053.md`
# carried the prose "Read `00-WAVE-7-DIRECTION.md` first"; expanding it made a
# second path citation in a spec that already had one, raising that brief's spec
# count from 13 to 16 and leaving brief 54 claimed only by an incidental mention.
#
# UNCLAIMED-BRIEFS.md records the same result from an out-of-family review that
# proposed normalising all 24 prose citations to the header form: "Measured
# against this tree that would break the invariant it was meant to strengthen".
# The document said so and the first run of this fixer did it anyway.
FIXED_FORM = ("docs/specs/", "docs/feature-specs/")


def external_names() -> set[str]:
    if not PLUGIN_CACHE.is_dir():
        return set()
    return {f.name for f in PLUGIN_CACHE.rglob("*")
            if f.is_file() and f.suffix.lstrip(".") in EXTENSIONS}


def index(root: Path) -> dict[str, list[str]]:
    """Every file in the repository, grouped by basename."""
    out: dict[str, list[str]] = {}
    for f in root.rglob("*"):
        if not f.is_file():
            continue
        if SKIP_DIRS & set(f.relative_to(root).parts):
            continue
        out.setdefault(f.name, []).append(str(f.relative_to(root)))
    return out


def artifacts(root: Path) -> list[Path]:
    seen: list[Path] = []
    for rel in DURABLE:
        p = root / rel
        if p.is_file():
            seen.append(p)
    for pattern in DURABLE_GLOBS:
        seen.extend(sorted(p for p in root.glob(pattern) if p.is_file()))
    return seen


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=str(ROOT))
    ap.add_argument("--gate", action="store_true")
    ap.add_argument("--json")
    ap.add_argument("--ratchet")
    ap.add_argument("--set-ratchet", action="store_true", dest="set_ratchet")
    ap.add_argument("--fix", action="store_true",
                    help="rewrite the single-match citations to their repository-relative path. "
                         "Never touches an ambiguous or absent one: those need a person, and a "
                         "fixer that guesses is how a citation comes to point at the wrong file "
                         "while looking repaired. Never touches FIXED_FORM either — see below.")
    a = ap.parse_args()
    root = Path(a.root).resolve()

    by_name = index(root)
    outside = external_names()
    resolved = unresolvable = 0
    fixable: list[dict] = []
    ambiguous: list[dict] = []
    absent: list[dict] = []
    external: list[dict] = []
    form_locked: list[dict] = []

    for art in artifacts(root):
        rel = str(art.relative_to(root))
        for n, line in enumerate(art.read_text(errors="replace").splitlines(), 1):
            for token in CITATION.findall(line):
                if (root / token).exists():
                    resolved += 1
                    continue
                # Not a path from the root. Is it a bare name of something here?
                name = token.rsplit("/", 1)[-1]
                # A partial path is the same failure wearing more of the answer:
                # `ProctorShim/RemoteServer.swift` names one file and still does
                # not resolve. Match on the suffix so those are offered a fix
                # rather than reported as naming nothing — the first run of this
                # check classed seven of them absent, and they were this repo's
                # own source files cited from the middle.
                matches = ([m for m in by_name.get(name, []) if m.endswith("/" + token)]
                           if "/" in token else by_name.get(name, []))
                if len(matches) == 1:
                    (form_locked if rel.startswith(FIXED_FORM) else fixable).append(
                        {"artifact": rel, "line": n, "cited": token, "fix": matches[0]})
                elif len(matches) > 1:
                    ambiguous.append({"artifact": rel, "line": n, "cited": token,
                                      "candidates": sorted(matches)[:6],
                                      "matchCount": len(matches)})
                elif name in outside:
                    external.append({"artifact": rel, "line": n, "cited": token})
                    resolved += 1        # it resolves, just not from this root
                    continue
                else:
                    absent.append({"artifact": rel, "line": n, "cited": token})
                unresolvable += 1

    total = resolved + unresolvable
    print(f"{total} path citation(s) examined across {len(artifacts(root))} durable artifact(s)")
    print(f"  resolved                 {resolved}"
          f"  ({resolved - len(external)} from this root, {len(external)} naming a file the "
          f"installed plugins own)")
    print(f"  bare, one match          {len(fixable)}  (mechanically fixable)")
    print(f"  form is another tool's input  {len(form_locked)}"
          f"  (resolvable, deliberately left — see FIXED_FORM)")
    print(f"  bare, several matches    {len(ambiguous)}")
    print(f"  no file of that name     {len(absent)}")

    if fixable:
        print()
        print("Bare filenames that resolve to exactly one file — the fix is mechanical:")
        for r in fixable[:40]:
            print(f"  {r['artifact']}:{r['line']}  `{r['cited']}`  ->  `{r['fix']}`")
        if len(fixable) > 40:
            print(f"  … and {len(fixable) - 40} more")
    if ambiguous:
        print()
        print("Bare filenames matching several files — reported, never resolved to the first,")
        print("because that is how a citation comes to point at the wrong file while looking fixed:")
        for r in ambiguous[:20]:
            print(f"  {r['artifact']}:{r['line']}  `{r['cited']}`  {r['matchCount']} candidates: "
                  f"{', '.join(r['candidates'])}")
    if absent:
        print()
        print("Cited, and no file of that name exists anywhere in the tree:")
        for r in absent[:20]:
            print(f"  {r['artifact']}:{r['line']}  `{r['cited']}`")

    if a.json:
        Path(a.json).write_text(json.dumps(
            {"examined": total, "resolved": resolved, "fixable": fixable,
             "ambiguous": ambiguous, "absent": absent, "external": external,
             "formLocked": form_locked}, indent=2) + "\n")

    if a.fix and fixable:
        by_artifact: dict[str, list[dict]] = {}
        for r in fixable:
            by_artifact.setdefault(r["artifact"], []).append(r)
        written = 0
        skipped = len(form_locked)
        for rel, rows in sorted(by_artifact.items()):
            path = root / rel
            text = path.read_text()
            # Longest cited token first, so `Session/SessionGuest.swift` is not
            # half-rewritten by a rule for `SessionGuest.swift`.
            for token, fix in sorted({(r["cited"], r["fix"]) for r in rows},
                                     key=lambda t: -len(t[0])):
                text = text.replace(f"`{token}`", f"`{fix}`")
            path.write_text(text)
            written += 1
        print()
        print(f"rewrote {len(fixable)} citation(s) across {written} artifact(s). "
              f"{len(ambiguous)} ambiguous and {len(absent)} absent were left alone, and "
              f"{skipped} sit in artifacts where the citation form is another tool's input.")
        return 0

    # The residue is ratcheted rather than gated at zero, because neither
    # remaining class can be closed mechanically. `main.swift` names three real
    # files and picking one is a guess; `docs/specs/spec-PRO-NNNN.md` is a
    # template placeholder and correctly names nothing. Both need a person, and
    # a gate that demands zero of them would be switched off. What the ratchet
    # buys is that a NEW unresolvable citation shows on the run that adds it.
    ratchet_file = Path(a.ratchet) if a.ratchet else (
        ROOT / "docs" / "test-campaign" / "path-citation-ratchet.json")
    allowed = None
    if ratchet_file.is_file():
        allowed = json.loads(ratchet_file.read_text()).get("unresolvable")
    if a.set_ratchet:
        ratchet_file.write_text(json.dumps(
            {"unresolvable": unresolvable,
             "note": ("Citations that cannot be resolved mechanically: a bare name matching "
                      "several real files, and a name matching none. Both need a person. "
                      "Lower this only by resolving one, never to make a run green.")},
            indent=2) + "\n")
        print()
        print(f"ratchet set to {unresolvable}" + (f" (was {allowed})" if allowed is not None else ""))
        return 0

    print()
    if allowed is None:
        if unresolvable:
            print(f"FAIL  {unresolvable} of {total} citation(s) do not resolve, and no ratchet "
                  f"is recorded.")
            return 1 if a.gate else 0
        print(f"PASS: all {total} citation(s) resolve from the repository root.")
        return 0
    print(f"ratchet: {allowed} unresolvable allowed, {unresolvable} measured "
          f"({total - unresolvable} of {total} resolve). Of the {unresolvable}: "
          f"{len(form_locked)} are resolvable and deliberately left because another tool reads "
          f"their form, {len(ambiguous)} name several real files, {len(absent)} name none, and "
          f"{len(fixable)} are mechanically fixable and should be zero after --fix.")
    if unresolvable > allowed:
        print(f"FAIL  the unresolvable count ROSE from {allowed} to {unresolvable}. A new "
              f"citation was written that an outside reader cannot follow.")
        return 1 if a.gate else 0
    if unresolvable < allowed:
        print(f"checked ROSE: {allowed - unresolvable} citation(s) resolved since the ratchet "
              f"was set — lower it with --set-ratchet in the same commit.")
        return 1 if a.gate else 0
    print("held.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
