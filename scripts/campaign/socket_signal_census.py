#!/usr/bin/env python3
"""Every socket this package opens or accepts, and whether SIGPIPE can kill it.

DEF-338 was a write to a peer that had gone, raising SIGPIPE, whose default
disposition is to terminate — measured at exit 141. It was fixed by setting
`SO_NOSIGPIPE`. DEF-342 is that the fix reached one of the four places this
package writes to a socket it accepted, and the tree passed every gate anyway.

The rule the fix rests on is written in the source, at `Server.swift`:

    An ACCEPTED descriptor does not inherit SO_NOSIGPIPE from its listener

`Tests/ProctorCoreTests/AcceptedSocketSignalTests.swift` measures that rather
than quoting it. This file is the other half: a census over every descriptor
`Sources/` produces, so a fix applied in one of four places is visible.

WHAT IT REQUIRES, AND WHY THE RULE IS "EVERY" RATHER THAN "EVERY WRITER".
Deciding statically whether a descriptor reaches a write is a dataflow problem
this tool would get wrong in both directions — a handle passed to another
function is written by that function, and a `defer { close(fd) }` looks the
same as a reply. Requiring the suppression on every descriptor is decidable,
costs one line at each site, is already what four of the five `socket()` calls
in this tree do, and cannot under-report. A listener that carries an option it
never needs is not a defect; a writer that lacks one is.

    python3 scripts/campaign/socket_signal_census.py [--root .] [--gate] [--json OUT]

Exit codes
    0   every descriptor is suppressed, or --gate was not asked for
    1   at least one descriptor has no suppression within its window
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

# `let fd = socket(AF_UNIX, ...)` / `let client = accept(fd, nil, nil)`.
# The binding name is what the suppression has to name, so it is captured.
PRODUCER = re.compile(
    r"^\s*(?:let|var)\s+(?P<name>\w+)\s*(?::\s*Int32\s*)?=\s*"
    r"(?:Darwin\.)?(?P<call>socket|accept)\s*\(")

# Two spellings, because ProctorReflector has no dependency on ProctorCore and
# inlines what `proctorSuppressSIGPIPE` does. Both are the same syscall.
def suppressors(name: str) -> list[re.Pattern[str]]:
    n = re.escape(name)
    return [
        re.compile(rf"proctorSuppressSIGPIPE\s*\(\s*{n}\s*\)"),
        re.compile(rf"setsockopt\s*\(\s*{n}\s*,\s*SOL_SOCKET\s*,\s*SO_NOSIGPIPE"),
    ]

# How far after the producer a suppression may sit, counted in CODE lines —
# comment-only and blank lines are skipped. Measuring prose distance made the
# check brittle in a way that mattered: writing a thirteen-line comment above
# `Server.swift`'s suppression pushed it out of the window and reported a bare
# descriptor, which is a finding about the comment rather than about the socket.
# Six code lines leaves room for a `guard` and an error path without letting an
# unrelated later call satisfy an earlier producer.
WINDOW = 6
COMMENT = re.compile(r"^\s*(//|/\*|\*)")


def code_window(lines: list[str], start: int, span: int) -> str:
    """The next `span` lines that carry code, from `start`, comments dropped."""
    out: list[str] = []
    for line in lines[start:]:
        if not line.strip() or COMMENT.match(line):
            continue
        out.append(line)
        if len(out) > span:
            break
    return "\n".join(out)


def scan(root: Path) -> list[dict]:
    rows: list[dict] = []
    for path in sorted((root / "Sources").rglob("*.swift")):
        lines = path.read_text().splitlines()
        for i, line in enumerate(lines):
            m = PRODUCER.match(line)
            if not m:
                continue
            name = m.group("name")
            window = code_window(lines, i, WINDOW)
            found = next((p.pattern for p in suppressors(name) if p.search(window)), None)
            rows.append({
                "file": str(path.relative_to(root)),
                "line": i + 1,
                "call": m.group("call"),
                "descriptor": name,
                "suppressed": found is not None,
                "by": "proctorSuppressSIGPIPE" if found and "proctorSuppress" in found
                      else ("setsockopt SO_NOSIGPIPE" if found else None),
            })
    return rows


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=".")
    ap.add_argument("--gate", action="store_true")
    ap.add_argument("--json")
    a = ap.parse_args()
    root = Path(a.root).resolve()

    rows = scan(root)
    bare = [r for r in rows if not r["suppressed"]]
    opened = [r for r in rows if r["call"] == "socket"]
    accepted = [r for r in rows if r["call"] == "accept"]

    print(f"{len(rows)} descriptor(s) produced under Sources/ — "
          f"{len(opened)} by socket(), {len(accepted)} by accept()")
    for r in rows:
        mark = "ok " if r["suppressed"] else "BARE"
        by = r["by"] or "nothing within %d code lines" % WINDOW
        print(f"  {mark}  {r['file']}:{r['line']}  {r['call']}() -> {r['descriptor']}   {by}")

    if a.json:
        Path(a.json).write_text(json.dumps(
            {"window": WINDOW, "rows": rows, "bare": len(bare)}, indent=2) + "\n")

    print()
    if bare:
        print(f"FAIL  {len(bare)} of {len(rows)} descriptor(s) can be killed by SIGPIPE.")
        print("      An accepted descriptor does not inherit SO_NOSIGPIPE from its listener,")
        print("      so a suppression on the listener does not answer for the client.")
        return 1 if a.gate else 0
    print(f"PASS: all {len(rows)} descriptor(s) suppress SIGPIPE within {WINDOW} code lines "
          f"of the call that produced them.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
