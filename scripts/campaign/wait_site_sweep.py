#!/usr/bin/env python3
"""A wait states its bound and what happens when the bound is reached.

Two wait shapes cost something different. A fixed-interval poll with no exit
condition never ends and spends whatever budget it is given; a bounded wait that
does not say what happens at the bound leaves the caller unable to tell "the
thing happened" from "we gave up". The tailings probe T13 measured polling at 1%
of this session's Bash calls with a longest identical run of nine, which is the
first shape at small scale.

WHAT A WAIT SITE IS. A `sleep` in a shell script, and `time.sleep` in a Python
one. Each is classed:

    unbounded    a sleep inside a loop with no counter and no break — the shape
                 that never ends
    bounded      a loop with a counter or a deadline
    settle       a lone sleep, not in a loop: a fixed pause for something to land
    silent       bounded, and nothing says what happens when the bound is reached

`settle` is not a finding. A 100 ms pause so a FIN lands before the next write is
a measurement decision, not a poll, and reporting it as one is how a sweep gets
ignored. It is counted so the denominator is the real one.

    python3 scripts/campaign/wait_site_sweep.py [--root .] [--gate] [--json OUT]

Exit codes
    0   every waiting loop is bounded and says what the bound means
    1   at least one is unbounded, or bounded without saying
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

SWEPT_GLOBS = ["scripts/**/*.sh", "scripts/**/*.py", "*.sh"]
SKIP_DIRS = {".build", ".git", ".worktrees", "node_modules", "__pycache__"}

SLEEP = re.compile(r"(?:^|[\s;&(])(?:/bin/)?sleep\s+[\d.]|time\.sleep\s*\(")
LOOP = re.compile(r"^\s*(?:while|for|until)\b|^\s*(?:while|for)\s")
# A bound is a counter, a deadline, a range, or a retry limit in scope.
# Each alternative below came from a site that was read. `seq` is here because
# the first run reported `for _ in $(seq 1 40)` as unbounded, which is a loop
# that counts to forty and then prints "the agent did not bind … within 10
# seconds" — bounded, and saying so.
BOUND = re.compile(r"\brange\s*\(|\battempt\b|\btries\b|\bretries\b|\bdeadline\b|"
                   r"\btimeout\b|\bmax\w*\b|\belapsed\b|-lt\s|\-le\s|<\s*\d|<=\s*\d|"
                   r"\bseq\s+\d")

# A loop whose condition is a plain boolean flag another thread clears is a
# SERVICE loop, not a poll. `while self.running:` around a socket handler ends
# when the owner stops it, and the sleep inside is holding a stream open rather
# than asking a question repeatedly. The first run reported one of these as
# unbounded; a sweep that calls a server's accept loop a polling defect is a
# sweep nobody runs twice.
SERVICE_LOOP = re.compile(r"^\s*while\s+(?:self\.\w+|not\s+self\.\w+|\$\{?\w+\}?)\s*:?\s*(?:do)?\s*$")
# What happens at the bound: a raise, a return, a non-zero exit, or a message.
# Every alternative is quoted from a site somebody read, the way this
# repository's other phrase matchers are built. `did not` and `within N seconds`
# came from install.sh, which counts to forty and then says "the agent did not
# bind $SOCKET within 10 seconds" — a bound that says exactly what reaching it
# means, in words no earlier alternative covered.
AT_THE_BOUND = re.compile(r"\braise\b|\breturn\s+[1-9]|\bexit\s+[1-9]|\bsys\.exit\s*\(\s*[1-9]|"
                          r"\bgave up\b|\btimed out\b|\btimeout\b|\bfail\b|\bFAIL\b|"
                          r"nothing was measured|\bdid not\b|within\s+\d+\s+second|"
                          # `return False` is how a bounded poll helper says it
                          # ran out — the caller then reports which way it ended.
                          # Added from supervision_tui_pty_probe's wait_until,
                          # which this sweep classed `silent` on its first sight
                          # of it while the function's whole contract is that the
                          # boolean says whether the bound was reached.
                          r"return\s+False|\breturns? whether\b|\bran out\b")


def files(root: Path) -> list[Path]:
    out: list[Path] = []
    for g in SWEPT_GLOBS:
        for f in root.glob(g):
            if f.is_file() and not (SKIP_DIRS & set(f.relative_to(root).parts)):
                out.append(f)
    return sorted(set(out))


def enclosing_loop(lines: list[str], i: int) -> int | None:
    """The line number of the loop this sleep sits in, by indentation."""
    indent = len(lines[i]) - len(lines[i].lstrip())
    for j in range(i - 1, max(-1, i - 40), -1):
        ln = lines[j]
        if not ln.strip():
            continue
        this = len(ln) - len(ln.lstrip())
        if this < indent and LOOP.match(ln):
            return j
        if this < indent and ln.strip().startswith(("def ", "func ", "class ")):
            return None
    return None


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=str(ROOT))
    ap.add_argument("--gate", action="store_true")
    ap.add_argument("--json")
    a = ap.parse_args()
    root = Path(a.root).resolve()

    settle: list[dict] = []
    service: list[dict] = []
    bounded: list[dict] = []
    unbounded: list[dict] = []
    silent: list[dict] = []

    for f in files(root):
        lines = f.read_text(errors="replace").splitlines()
        rel = str(f.relative_to(root))
        for i, line in enumerate(lines):
            if not SLEEP.search(line):
                continue
            row = {"file": rel, "line": i + 1, "text": line.strip()[:120]}
            loop = enclosing_loop(lines, i)
            if loop is None:
                settle.append(row)
                continue
            if SERVICE_LOOP.match(lines[loop]):
                service.append(dict(row, loop=loop + 1))
                continue
            body = "\n".join(lines[loop:min(len(lines), loop + 25)])
            if not BOUND.search(body):
                unbounded.append(dict(row, loop=loop + 1))
            elif not AT_THE_BOUND.search(body):
                silent.append(dict(row, loop=loop + 1))
            else:
                bounded.append(dict(row, loop=loop + 1))

    total = len(settle) + len(service) + len(bounded) + len(unbounded) + len(silent)
    print(f"{total} wait site(s) examined across {len(files(root))} swept file(s)")
    print(f"  settle     {len(settle):>3}  a lone pause, not a loop — not a poll")
    print(f"  service    {len(service):>3}  a loop held open by a flag its owner clears — not a poll")
    print(f"  bounded    {len(bounded):>3}  a loop with a bound, and it says what the bound means")
    print(f"  silent     {len(silent):>3}  bounded, and nothing says what happens at the bound")
    print(f"  unbounded  {len(unbounded):>3}  a loop with neither counter nor deadline")

    for label, rows in (("unbounded — this loop has no way to stop", unbounded),
                        ("bounded, but nothing says what reaching the bound means", silent)):
        if rows:
            print()
            print(label + ":")
            for r in rows:
                print(f"  {r['file']}:{r['line']}  (loop opens at :{r['loop']})  {r['text']}")

    if a.json:
        Path(a.json).write_text(json.dumps(
            {"examined": total, "settle": settle, "service": service, "bounded": bounded,
             "silent": silent, "unbounded": unbounded}, indent=2) + "\n")

    print()
    if unbounded or silent:
        print(f"FAIL  {len(unbounded)} unbounded and {len(silent)} silent wait(s) of {total}.")
        return 1 if a.gate else 0
    print(f"PASS: all {len(bounded)} waiting loop(s) of {total} wait site(s) are bounded and say "
          f"what the bound means; {len(settle)} are settles and {len(service)} are service "
          f"loops rather than polls.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
