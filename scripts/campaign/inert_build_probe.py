#!/usr/bin/env python3
"""Run the branch a DEBUG test build can never reach.

`ProctorReflector` is a live implementation under `#if DEBUG || PROCTOR_REFLECTOR`
and a set of empty bodies under `#else`. `swift test` is a debug build, so the
whole `#else` branch is dead code in every run of this repository's suite: its
safe defaults — `isRunning` false, `isIdle` true, no socket created — have never
been asserted by anything, only assumed.

Compiling the target in release proves it builds. It does not prove what it
does. So this compiles the same sources into a scratch executable twice, once
with `-DDEBUG` and once without, drives the same six calls through both, and
reads the observables back. Two runs rather than one is the point: a probe that
only ever sees the inert build cannot tell an inert implementation from a broken
compile flag.

    python3 scripts/campaign/inert_build_probe.py [--json OUT]

Exit codes
    0   the inert build's defaults hold, and the DEBUG build differs from them
    1   the inert build did something, or the two builds agree — which would mean
        the flag is not reaching the compiler and the measurement is vacuous
    2   a build failed, so nothing was measured
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

DRIVER = '''import Foundation

// NOT named `socket`: these sources compile as one flat module here, and a
// top-level `let socket` shadows the syscall SocketServer.swift calls, which
// fails as "cannot call value of non-function type 'String'" inside a file this
// driver never touched.
let probeSocketPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1] : "/tmp/probe.sock"
ProctorReflector.start(socketPath: probeSocketPath)
let running = ProctorReflector.isRunning
let token = ProctorReflector.beginActivity("probe")
ProctorReflector.endActivity(token)
let idle = ProctorReflector.isIdle
ProctorReflector.stop()
print("isRunning=\\(running) isIdle=\\(idle) serial=\\(token.serial) "
      + "socketCreated=\\(FileManager.default.fileExists(atPath: probeSocketPath))")
'''


def build_and_run(work: Path, debug: bool) -> dict:
    # The file has to be called main.swift: Swift allows top-level expressions
    # only there, and a driver named anything else fails to compile with
    # "expressions are not allowed at the top level", which reads like a probe
    # defect rather than a filename one.
    stage = work / ("debug" if debug else "inert")
    stage.mkdir(exist_ok=True)
    driver = stage / "main.swift"
    driver.write_text(DRIVER)
    binary = work / ("probe-debug" if debug else "probe-inert")
    sources = sorted(str(p) for p in (ROOT / "Sources" / "ProctorReflector").glob("*.swift"))
    cmd = ["swiftc", "-O"] + (["-DDEBUG"] if debug else []) + sources + [str(driver),
                                                                        "-o", str(binary)]
    built = subprocess.run(cmd, capture_output=True, text=True)
    if built.returncode != 0:
        return {"built": False, "error": built.stderr[-800:]}
    socket = work / ("debug.sock" if debug else "inert.sock")
    ran = subprocess.run([str(binary), str(socket)], capture_output=True, text=True)
    fields = dict(re.findall(r"(\w+)=(\S+)", ran.stdout))
    return {"built": True, "exit": ran.returncode, "output": ran.stdout.strip(),
            "fields": fields}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--json")
    a = ap.parse_args()

    if not shutil.which("swiftc"):
        print("swiftc is not on the path, so nothing was measured.")
        return 2

    with tempfile.TemporaryDirectory() as td:
        work = Path(td)
        inert = build_and_run(work, debug=False)
        live = build_and_run(work, debug=True)

    for name, r in (("inert", inert), ("DEBUG", live)):
        if not r["built"]:
            print(f"the {name} build failed, so nothing was measured:")
            print(r["error"])
            return 2
        print(f"  {name:<6} {r['output']}")

    problems = []
    i, l = inert["fields"], live["fields"]
    if i.get("isRunning") != "false":
        problems.append("the inert build reports isRunning true — it started something")
    if i.get("isIdle") != "true":
        problems.append("the inert build reports isIdle false — it is tracking something")
    if i.get("serial") != "0":
        problems.append(f"the inert build handed back serial {i.get('serial')}, not 0 — "
                        f"beginActivity registered an activity")
    if i.get("socketCreated") != "false":
        problems.append("the inert build created a socket")
    # The control. If both builds agree, the flag never reached the compiler and
    # the inert reading above is about whichever build ran twice.
    if i.get("isRunning") == l.get("isRunning") and i.get("serial") == l.get("serial"):
        problems.append("the two builds agree on isRunning and serial, so -DDEBUG did not reach "
                        "the compiler and this measurement is about one build read twice")

    if a.json:
        Path(a.json).write_text(json.dumps(
            {"inert": inert, "debug": live, "problems": problems}, indent=2) + "\n")

    print()
    if problems:
        for p in problems:
            print(f"  {p}")
        print()
        print(f"FAIL  {len(problems)} problem(s).")
        return 1
    print("PASS: the inert build starts nothing, tracks nothing and hands back serial 0, and the")
    print(f"      DEBUG build of the same sources differs on isRunning "
          f"({i['isRunning']} vs {l['isRunning']}) and serial ({i['serial']} vs {l['serial']}), "
          f"so the flag reached the compiler.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
