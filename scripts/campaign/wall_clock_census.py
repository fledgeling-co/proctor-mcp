#!/usr/bin/env python3
"""Census of wall-clock assertions in the test suite.

An oracle that compares a *measured* elapsed time against a numeric literal is
measuring the machine, not the product. `ScreenRecordingProbeWiringTests:42`
did that and failed six times in one wave at 5.6s, 6.1s, 6.58s, 8.13s, 10.25s
and 14.73s while the product was correct every time.

Two rules this obeys, both learned the hard way in this repo:

* **A capped list is not a population.** Every row found is printed and every
  count is a `len()`.
* **Before believing a zero, confirm the instrument could report non-zero.**
  `--arm` runs the detector over the two files as they stood before PRO-0089
  and requires it to find exactly the two known offenders. A detector that
  cannot catch them has measured nothing, whatever it prints.

A clock a test *injects and drives* is not a wall clock and is not flagged:
the whole point of this item is to move assertions onto one.

Usage:
  scripts/campaign/wall_clock_census.py            census; exit 1 if any found
  scripts/campaign/wall_clock_census.py --arm      prove the detector fires
"""
import re
import subprocess
import sys
import pathlib

# Sources of real, machine-dependent time.
REAL_TIME = re.compile(
    r"Date\s*\(\s*\)"
    r"|DispatchTime\.now\s*\(\s*\)"
    r"|CFAbsoluteTimeGetCurrent\s*\(\s*\)"
    r"|ContinuousClock\s*\(\s*\)"
    r"|SuspendingClock\s*\(\s*\)"
    r"|systemUptime")
# Any clock at all, injected ones included — the denominator.
ANY_CLOCK = re.compile(REAL_TIME.pattern + r"|timeIntervalSince|uptimeNanoseconds|\belapsed\b")
# `let x = <something real-time>` — x now carries machine time.
DERIVED = re.compile(r"\b(?:let|var)\s+([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+)$")
# A comparison against a numeric literal, decimal or underscored.
LITERAL_COMPARE = re.compile(r"[<>]=?\s*-?[0-9][0-9_]*(?:\.[0-9]+)?")


def scan(name, text):
    """Return (clock_sites, offenders) for one file's text."""
    derived = set()
    clock_sites, offenders = [], []
    for n, line in enumerate(text.splitlines(), 1):
        stripped = line.strip()
        if stripped.startswith("//"):
            continue
        match = DERIVED.search(stripped)
        if match and REAL_TIME.search(match.group(2)):
            derived.add(match.group(1))
        if ANY_CLOCK.search(stripped):
            clock_sites.append((name, n, stripped))
        if "#expect" not in stripped and "#require" not in stripped:
            continue
        if not LITERAL_COMPARE.search(stripped):
            continue
        carries_time = bool(REAL_TIME.search(stripped)) or any(
            re.search(r"\b%s\b" % re.escape(v), stripped) for v in derived)
        if carries_time:
            offenders.append((name, n, stripped))
    return clock_sites, offenders


def census(paths):
    sites, offenders = [], []
    for path in paths:
        s, o = scan(str(path), path.read_text())
        sites += s
        offenders += o
    return sites, offenders


def arm():
    """The detector against the two offenders as they stood before PRO-0089."""
    known = {
        "Tests/ProctorAgentTests/ScreenRecordingProbeWiringTests.swift": 42,
        "Tests/ProctorAgentTests/CuaLineReaderTests.swift": 107,
    }
    base = subprocess.run(["git", "merge-base", "HEAD", "ai/wave-9"],
                          capture_output=True, text=True).stdout.strip() or "HEAD"
    found = {}
    for path, line in known.items():
        text = subprocess.run(["git", "show", f"{base}:{path}"],
                              capture_output=True, text=True).stdout
        if not text:
            print(f"ARMING FAILED: could not read {path} at {base}")
            return 1
        _, offenders = scan(path, text)
        found[path] = [n for _, n, _ in offenders]
        print(f"  {path} @ {base[:12]}: offenders at {found[path]} (expected {line})")
    ok = all(known[p] in found[p] for p in known)
    total = sum(len(v) for v in found.values())
    print(f"  detector caught {total} of the 2 known offenders")
    print("ARMED" if ok else "ARMING FAILED: the detector cannot catch a known offender")
    return 0 if ok else 1


def main():
    if "--arm" in sys.argv:
        print("--- arming: the detector over the pre-PRO-0089 files ---")
        return arm()
    files = sorted(pathlib.Path("Tests").rglob("*.swift"))
    sites, offenders = census(files)
    print(f"swift test files scanned: {len(files)}")
    print(f"lines mentioning a clock of any kind (the denominator): {len(sites)}")
    print(f"assertions comparing a measured wall-clock time to a literal: {len(offenders)}")
    print()
    print("--- every clock site, in full, not a sample ---")
    for name, n, text in sites:
        print(f"  {name}:{n}: {text}")
    print()
    print("--- wall-clock assertions ---")
    for name, n, text in offenders:
        print(f"  {name}:{n}: {text}")
    if not offenders:
        print("  (none)")
    return 1 if offenders else 0


if __name__ == "__main__":
    sys.exit(main())
