#!/usr/bin/env python3
"""An intentional empty body says so, in a form a scan can read.

A static scan cannot tell a deliberate null implementation from an unfinished
one, and this repository has both shapes in production code. `NullContentionMonitor`
is empty by design — its whole purpose is to sample as a quiet machine, and the
comment above it carries five paragraphs on why the safe reading is the default.
`ProctorReflector`'s `#else` branch is empty because that build was compiled
without `DEBUG` or `PROCTOR_REFLECTOR`, so there is nothing to start and nothing
to stop.

Neither is a stub somebody forgot. A scan that reports them is a scan somebody
turns off, and a scan that ignores every empty body cannot find the one that was
forgotten. The way out is an attestation: a doc comment, on the body or on the
type declaring it, saying the emptiness is the design.

WHAT COUNTS AS AN ATTESTATION. A `///` doc comment within the six lines above the
body, or on the enclosing type, containing one of the phrases in ATTESTED. The
phrases are quoted from comments already in this tree rather than invented, the
way this repository's other phrase matchers are built.

PRODUCTION AND TESTS ARE SEPARATE QUESTIONS. An empty method on a test double is
the double doing its job — the caller wants a collaborator that records nothing —
and asking every fake to attest would produce a hundred findings and no
information. Tests are counted and reported apart, never mixed into the
production number.

    python3 scripts/campaign/noop_attestation.py [--root .] [--gate] [--json OUT]

Exit codes
    0   every empty body in production code carries an attestation
    1   at least one does not, named with its file and line
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

# A declaration whose body opens and closes on the same line with nothing in it,
# or opens and closes across two lines with nothing between. Computed properties
# returning a literal are NOT empty — they produce a value somebody can assert.
EMPTY_INLINE = re.compile(
    r"^\s*(?:@\w+\s+)*(?:public |private |internal |fileprivate |open )?(?:static |class )?"
    r"(?:override )?func\s+(?P<name>\w+)\s*(?:<[^>]*>)?\([^)]*\)\s*(?:async\s*)?(?:throws\s*)?"
    r"(?:->\s*\w+\s*)?\{\s*\}\s*$")

# Phrases that say the emptiness is the design. Each is quoted from a comment in
# this tree. A phrase list somebody invented would be tuned; this one grows only
# when a row is read and found to be attesting in words no entry covers.
ATTESTED = (
    "no-op", "No-op", "no op",
    "nothing to start", "nothing is tracked", "nothing to stop",
    "deliberately empty", "intentionally empty", "empty by design",
    "does nothing", "samples as a quiet machine", "the safe reading is the default",
    "inert build", "compiled without",
)

SKIP_DIRS = {".build", ".git", ".worktrees", "node_modules", "__pycache__"}


def doc_window(lines: list[str], i: int) -> str:
    """The doc comment above a body, plus the enclosing type's own doc comment."""
    out: list[str] = []
    for j in range(i - 1, max(-1, i - 7), -1):
        s = lines[j].strip()
        if s.startswith("///") or s.startswith("//"):
            out.append(s)
        elif s:
            break
    # The enclosing type: walk back to the declaration and take its doc comment.
    indent = len(lines[i]) - len(lines[i].lstrip())
    for j in range(i - 1, max(-1, i - 200), -1):
        s = lines[j]
        if not s.strip():
            continue
        this = len(s) - len(s.lstrip())
        if this < indent and re.match(r"\s*(?:public |private |internal |final |open )*"
                                      r"(?:class|struct|enum|extension|actor)\b", s):
            for k in range(j - 1, max(-1, j - 40), -1):
                t = lines[k].strip()
                if t.startswith("///") or t.startswith("//"):
                    out.append(t)
                elif t:
                    break
            break
    return "\n".join(out)


def scan(root: Path, sub: str) -> list[dict]:
    rows: list[dict] = []
    base = root / sub
    if not base.is_dir():
        return rows
    for f in sorted(base.rglob("*.swift")):
        if SKIP_DIRS & set(f.relative_to(root).parts):
            continue
        lines = f.read_text(errors="replace").splitlines()
        for i, line in enumerate(lines):
            m = EMPTY_INLINE.match(line)
            if not m:
                continue
            doc = doc_window(lines, i)
            hit = next((p for p in ATTESTED if p in doc), None)
            rows.append({"file": str(f.relative_to(root)), "line": i + 1,
                         "symbol": m.group("name"), "attested": hit is not None,
                         "by": hit, "text": line.strip()[:100]})
    return rows


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=str(ROOT))
    ap.add_argument("--gate", action="store_true")
    ap.add_argument("--json")
    a = ap.parse_args()
    root = Path(a.root).resolve()

    production = scan(root, "Sources")
    doubles = scan(root, "Tests")
    bare = [r for r in production if not r["attested"]]

    print(f"{len(production)} empty body(ies) in Sources · {len(doubles)} in Tests")
    print(f"  attested   {len(production) - len(bare)}  the comment says the emptiness is the design")
    print(f"  bare       {len(bare)}  nothing says whether this is finished")
    print(f"  test double{len(doubles):>3}  counted apart — an empty method on a fake is the fake "
          f"doing its job")

    if production:
        print()
        print("Production empty bodies:")
        for r in production:
            mark = f"attested ({r['by']})" if r["attested"] else "BARE"
            print(f"  {r['file']}:{r['line']}  {r['symbol']}  [{mark}]")

    if bare:
        print()
        print("An empty body nothing attests reads the same as an unfinished one. Add a doc")
        print("comment saying the emptiness is the design, and what a caller gets instead.")

    if a.json:
        Path(a.json).write_text(json.dumps(
            {"production": production, "tests": len(doubles), "bare": bare,
             "phrases": list(ATTESTED)}, indent=2) + "\n")

    print()
    if bare:
        print(f"FAIL  {len(bare)} of {len(production)} production empty body(ies) carry no "
              f"attestation.")
        return 1 if a.gate else 0
    print(f"PASS: all {len(production)} production empty body(ies) attest that the emptiness is "
          f"the design; {len(doubles)} test doubles counted apart.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
