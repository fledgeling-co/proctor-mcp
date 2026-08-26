#!/usr/bin/env python3
"""An exit code read from a pipeline is the last stage's, not the gate's.

`python3 gate.py | tail -5; echo "exit=$?"` prints tail's status, which is 0
whatever the gate did. This session used that shape and reported a gate green
that had exited 1; the tailings probe T5 names the same pattern as "gate output
suppressed and never re-run unsuppressed" and it fired eleven times across this
transcript.

The shape is easy to get wrong twice, so the sweep knows both spellings. In zsh
the array is `$pipestatus`; in bash it is `$PIPESTATUS`. A script using the
wrong one for its shell reads an empty string and compares it to zero, which
passes.

WHAT IS SWEPT. Shell scripts and workflow files in this repository, plus any
`subprocess.run(..., shell=True)` string in `scripts/`. A pipeline is a finding
only when its head is a GATE — something whose exit code is a verdict — because
`ls | head` has no verdict to lose.

    python3 scripts/campaign/pipe_exit_sweep.py [--root .] [--gate] [--json OUT]

Exit codes
    0   no invocation reads a pipeline's status in place of its gate's
    1   at least one does, named with its file and line
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

SWEPT_GLOBS = ["scripts/**/*.sh", "scripts/**/*.py", ".github/workflows/*.yml",
               ".github/workflows/*.yaml", "*.sh"]
SKIP_DIRS = {".build", ".git", ".worktrees", "node_modules", "__pycache__"}

# The head of a pipeline whose exit code is a verdict somebody acts on.
GATE_HEAD = re.compile(
    r"(?:^|[;&|]\s*|\$\(\s*)(?:python3?\s+\S+|swift\s+(?:test|build)|"
    r"\./scripts/\S+\.sh|xcodebuild|codesign|spctl|xcrun\s+stapler|npm\s+\w+|"
    r"cargo\s+\w+|make\b)")
# A pipe into something that discards the head's status.
SWALLOWER = re.compile(r"\|\s*(?:tail|head|grep|sed|awk|tee|jq|sort|uniq|wc|cut)\b")
# The reads that are correct, in either shell.
CORRECT = re.compile(r"\$\{?PIPESTATUS\[|\$\{?pipestatus\[|set\s+-o\s+pipefail|"
                     r"\bPIPESTATUS\b|\bpipestatus\b")
# `$?` immediately after a pipeline is the shape that lies.
READS_STATUS = re.compile(r"\$\?")

# Two shapes that pipe a gate binary and are not gates.
#
# A pipeline inside `$( )` is a VALUE EXTRACTION: `SIGNING="$(codesign -dv … |
# awk …)"` wants the text, and codesign's exit code is not a verdict anybody
# acts on there. The first run of this sweep reported all three of this
# repository's command substitutions as findings, which is a sweep that would be
# switched off within a week.
#
# `|| true` is a DECLARED discard. Somebody wrote down that the status does not
# matter, which is the opposite of losing it by accident.
VALUE_EXTRACTION = re.compile(r"\$\(")
DECLARED_DISCARD = re.compile(r"\|\|\s*(?:true|:)\s*$")


def files(root: Path) -> list[Path]:
    out: list[Path] = []
    for g in SWEPT_GLOBS:
        for f in root.glob(g):
            if f.is_file() and not (SKIP_DIRS & set(f.relative_to(root).parts)):
                out.append(f)
    return sorted(set(out))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=str(ROOT))
    ap.add_argument("--gate", action="store_true")
    ap.add_argument("--json")
    a = ap.parse_args()
    root = Path(a.root).resolve()

    examined = pipelines = extractions = declared = 0
    findings: list[dict] = []
    for f in files(root):
        lines = f.read_text(errors="replace").splitlines()
        rel = str(f.relative_to(root))
        guarded = any(CORRECT.search(ln) for ln in lines[:40])   # a file-level pipefail
        for i, line in enumerate(lines):
            if "|" not in line:
                continue
            examined += 1
            if not (GATE_HEAD.search(line) and SWALLOWER.search(line)):
                continue
            pipelines += 1
            if VALUE_EXTRACTION.search(line):
                extractions += 1
                continue
            if DECLARED_DISCARD.search(line):
                declared += 1
                continue
            # Correct if this line or the next two name the array, or the file
            # set pipefail near the top.
            window = "\n".join(lines[i:i + 3])
            if guarded or CORRECT.search(window):
                continue
            # A gate piped into a swallower has already lost its status; whether
            # anything then reads `$?` decides how loudly. Both are findings,
            # because a pipeline is the script's own exit status too — an
            # earlier version required the `$?` and reported 0 findings over
            # three real pipelines that had all discarded a verdict.
            findings.append({"file": rel, "line": i + 1, "text": line.strip()[:140],
                             "readsStatus": bool(READS_STATUS.search(window))})

    print(f"{examined} line(s) containing a pipe examined across {len(files(root))} swept file(s)")
    print(f"  {pipelines} pipe a gate into something that discards its status")
    reads = sum(1 for r in findings if r["readsStatus"])
    print(f"  {extractions} are a value extraction inside $( ), where no status is a verdict")
    print(f"  {declared} declare the discard with || true")
    print(f"  {len(findings)} of those are unguarded — no pipefail, no pipestatus")
    print(f"  {reads} of those then read $? and act on the answer")

    if findings:
        print()
        print("An exit code read here is the last stage's, not the gate's:")
        for r in findings:
            mark = "reads $?" if r["readsStatus"] else "status dropped"
            print(f"  {r['file']}:{r['line']}  [{mark}]  {r['text']}")
        print()
        print("The fix in zsh is $pipestatus[1]; in bash it is ${PIPESTATUS[0]}; in either,")
        print("`set -o pipefail` near the top makes the pipeline itself carry the failure.")

    if a.json:
        Path(a.json).write_text(json.dumps(
            {"examined": examined, "pipelines": pipelines, "findings": findings}, indent=2) + "\n")

    print()
    if findings:
        print(f"FAIL  {len(findings)} invocation(s) read a pipeline's status in place of a gate's.")
        return 1 if a.gate else 0
    print(f"PASS: of {pipelines} gate pipeline(s) in {examined} piped line(s), none reads $? "
          f"where the gate's own status was needed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
