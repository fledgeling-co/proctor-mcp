#!/usr/bin/env python3
"""Gate tests for the campaign instruments this repo owns.

The instruments that measure this project are measured here, because each of the
defects below was found by somebody checking a tool rather than reading its
output. All 15 checks here are watched in both directions — the fixture that
trips it and the fixture that clears it, in one session, recorded in
`docs/test-campaign/evidence/PRO-0091/instrument-arming.txt` with the mutation
that armed each one — so a check that cannot fire is distinguishable from a check
that found nothing. Arming the last seven caught one of them asserting over a
population of zero, which is the same finding the file was written to close.

`Tests/ProctorCoreTests/CampaignInstrumentTests.swift` runs this file, so
`./scripts/test.sh` owns the verdict and a red here is a red suite.

    python3 scripts/campaign/test_instruments.py        # quiet unless something fails
    python3 scripts/campaign/test_instruments.py -v
"""
from __future__ import annotations

import hashlib
import importlib.util
import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
VERBOSE = "-v" in sys.argv
RESULTS: list[tuple[bool, str]] = []


def check(ok: bool, label: str, detail: str = "") -> None:
    RESULTS.append((ok, label))
    if ok:
        if VERBOSE:
            print(f"ok    {label}")
    else:
        print(f"FAIL  {label}")
        if detail:
            print("\n".join(f"      {ln}" for ln in detail.splitlines()))


def load(path: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


# ── DEF-032: the integer operator matched closure shorthand ─────────────────
#
# `mutate_swift.py`'s integer-literal increment matched the `0` in `$0`. Mutant
# 24 of 24 rewrote `{ bind(fd, $0, size) }` to `bind(fd, $1, size)`, which cannot
# compile — a closure taking one parameter cannot name a second. The operator
# table's stated contract is that every operator keeps the file compiling, so an
# unbuildable mutant is a wasted sample, and with 24 slots against 3,189 sites
# the samples are the scarce thing. It did not even score as unbuildable: under
# load the build ran past the 600s timeout and the runner scores a timeout as a
# kill.

def test_mutate_swift_closure_shorthand() -> None:
    m = load(ROOT / "scripts/campaign/mutate_swift.py", "mutate_swift")
    fixture = (
        "func bindSocket(_ fd: Int32, _ addr: UnsafeRawPointer, _ size: socklen_t) {\n"
        "    withUnsafePointer(to: &sa) {\n"
        "        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, size) }\n"
        "    }\n"
        "    let attempts = 3\n"
        "    let projected = $pane2\n"
        "}\n"
    )
    with tempfile.TemporaryDirectory() as tmp:
        f = Path(tmp) / "UnlockBroker.swift"
        f.write_text(fixture)
        sites = m.candidates(f)

    def spans(site) -> tuple[str, int]:
        return site["before"], site["line"]

    befores = [spans(s)[0] for s in sites]
    ints = [b for b in befores if b.replace("_", "").isdigit()]

    # The fixture holds `$0` three times, `$1`-able capacity: 1, and a real
    # literal `3`. The digit in a shorthand parameter is not an integer literal.
    line3 = [s for s in sites if spans(s)[1] == 3]
    check(not any(spans(s)[0] == "0" for s in line3),
          "the integer operator does not fire on closure shorthand $0",
          f"line 3 sites: {[spans(s) for s in line3]}")
    check("3" in ints,
          "the same operator still fires on a real integer literal",
          f"integer sites found: {ints}")
    # A property wrapper's projected value carries the same risk one character
    # further in: the `2` of `$pane2` is a digit inside an identifier, held back
    # by `\w` in the lookbehind rather than by `$`. Written against `$state` this
    # check could not fire — no operator in the table matches a bare identifier,
    # so `before == "state"` was true of every operator table that could exist
    # and the check was watched green over a population of zero.
    line6 = [s for s in sites if spans(s)[1] == 6]
    check(not any(spans(s)[0] == "2" for s in line6),
          "a property wrapper's projected value is not a literal either",
          f"line 6 sites: {[spans(s) for s in line6]}")


# ── DEF-058: a registry merge that swept two keys of five ───────────────────
#
# Reconciling inventory.json at the PRO-0081 merge, only `defect` and
# `requirement` were merged and ours was taken as the base document, so
# PRO-0081's addition to `flow` was dropped with it. The capture stayed on disk
# and its verdict stayed in witness-verdicts.json; only the subject left the
# published set, and judged fell 6 to 5 against a ratchet of 6.

def _registry(**keys) -> dict:
    return {k: [{"id": i, "title": f"{k} {i}"} for i in v] for k, v in keys.items()}


def test_merge_registry() -> None:
    script = ROOT / "scripts/campaign/merge_registry.py"

    def run(*args) -> subprocess.CompletedProcess:
        return subprocess.run([sys.executable, str(script), *map(str, args)],
                              capture_output=True, text=True)

    with tempfile.TemporaryDirectory() as tmp:
        d = Path(tmp)
        ours = _registry(defect=["DEF-001"], requirement=["REQ-001"],
                         flow=["FLOW-001"], surface=["SURF-001"], component=["COMP-001"])
        theirs = _registry(defect=["DEF-001", "DEF-002"],
                           requirement=["REQ-001", "REQ-002"],
                           flow=["FLOW-001", "FLOW-010"],
                           surface=["SURF-001"], component=["COMP-001"])
        (d / "ours.json").write_text(json.dumps(ours, indent=2))
        (d / "theirs.json").write_text(json.dumps(theirs, indent=2))

        # The hand-merge that lost FLOW-010: two keys swept, ours taken as base.
        hand = json.loads(json.dumps(ours))
        hand["defect"] = theirs["defect"]
        hand["requirement"] = theirs["requirement"]
        (d / "hand.json").write_text(json.dumps(hand, indent=2))

        r = run("--base", d / "ours.json", "--theirs", d / "theirs.json",
                "--verify", d / "hand.json")
        check(r.returncode == 1 and "flow/FLOW-010" in r.stdout,
              "a key the merge did not sweep is caught and named",
              r.stdout + r.stderr)

        # The whole key absent, not merely a row: the other shape of the same loss.
        gutted = {k: v for k, v in hand.items() if k != "flow"}
        (d / "gutted.json").write_text(json.dumps(gutted, indent=2))
        r = run("--base", d / "ours.json", "--theirs", d / "theirs.json",
                "--verify", d / "gutted.json")
        check(r.returncode == 1 and "key 'flow' is absent" in r.stdout,
              "a key missing from the merge entirely is caught",
              r.stdout + r.stderr)

        # The script's own merge sweeps every key and then verifies clean, so the
        # gate is watched green as well as red.
        r = run("--base", d / "ours.json", "--theirs", d / "theirs.json",
                "--out", d / "merged.json")
        merged = json.loads((d / "merged.json").read_text()) if r.returncode == 0 else {}
        check(r.returncode == 0 and [x["id"] for x in merged.get("flow", [])] ==
              ["FLOW-001", "FLOW-010"],
              "the merge sweeps every key, including the one nobody was arguing about",
              r.stdout + r.stderr)
        r = run("--base", d / "ours.json", "--theirs", d / "theirs.json",
                "--verify", d / "merged.json")
        check(r.returncode == 0 and "every row under every one of 5 key(s)" in r.stdout,
              "the verifier passes the merge this script produced",
              r.stdout + r.stderr)

        # A row present on one side only is an addition, never a deletion, and a
        # real conflict stops rather than resolving itself to one side.
        conflict = json.loads(json.dumps(theirs))
        conflict["defect"][0]["title"] = "rewritten by them"
        (d / "conflict.json").write_text(json.dumps(conflict, indent=2))
        r = run("--base", d / "ours.json", "--theirs", d / "conflict.json",
                "--out", d / "no.json")
        check(r.returncode == 2 and "defect/DEF-001" in r.stdout,
              "two rows sharing an id with different content stop the merge",
              r.stdout + r.stderr)

        # A duplicate id inside one input is refused before anything is merged.
        dupe = json.loads(json.dumps(ours))
        dupe["defect"].append({"id": "DEF-001", "title": "again"})
        (d / "dupe.json").write_text(json.dumps(dupe, indent=2))
        r = run("--base", d / "dupe.json", "--theirs", d / "theirs.json",
                "--out", d / "no.json")
        check(r.returncode != 0 and "repeats DEF-001" in (r.stdout + r.stderr),
              "a registry that repeats an id is refused, not merged",
              r.stdout + r.stderr)


# ── DEF-058, against the real registry ──────────────────────────────────────
#
# The merge script is only worth having if it reads this project's own registry,
# so it is pointed at it: inventory.json merged against itself must be itself.

def test_merge_registry_on_this_registry() -> None:
    inv = ROOT / "docs/test-campaign/inventory.json"
    r = subprocess.run([sys.executable, str(ROOT / "scripts/campaign/merge_registry.py"),
                        "--base", str(inv), "--theirs", str(inv), "--verify", str(inv)],
                       capture_output=True, text=True)
    check(r.returncode == 0, "the real inventory.json merges against itself cleanly",
          r.stdout + r.stderr)
    keys = json.loads(inv.read_text()).keys()
    check(f"every one of {len(keys)} key(s)" in r.stdout,
          f"the verifier swept all {len(keys)} keys of the real registry",
          r.stdout)


# ── DEF-055: a note that contradicted its own evidence ──────────────────────

def test_case_0074_load_matches_its_evidence() -> None:
    cases = json.loads((ROOT / "docs/test-campaign/cases.json").read_text())
    case = next(c for c in cases if c["id"] == "CASE-0074")
    ev = (ROOT / "docs/test-campaign/evidence/mutation-agent.txt").read_text()
    start = next(ln for ln in ev.splitlines() if "Load average at start" in ln)
    figure = start.split(":")[1].split()[0]
    check(f"{figure} at start" in case["note"],
          f"CASE-0074's note carries the load its evidence file records ({figure})",
          f"note says: {case['note'][:400]}")


# ── DEF-057: the four cases stand on a rung the ladder recognises ───────────

def test_source_analysis_rung() -> None:
    cases = json.loads((ROOT / "docs/test-campaign/cases.json").read_text())
    four = [c for c in cases if c["id"] in ("CASE-0102", "CASE-0103", "CASE-0104", "CASE-0105")]
    check(len(four) == 4 and all(c["oracle"] == "source-analysis" for c in four),
          "CASE-0102..0105 stand on source-analysis rather than an unknown rung",
          str([(c["id"], c["oracle"]) for c in four]))
    check(all(isinstance(c.get("source", {}).get("examined"), int)
              and c["source"]["examined"] > 0 and c["source"].get("analyzer")
              for c in four),
          "each names its analyzer and the number of units it examined",
          str([(c["id"], c.get("source")) for c in four]))
    # The denominator is the classifier's own, not a number typed into the row.
    literals = load(ROOT / "scripts/campaign/status_literals.py", "status_literals")
    src = (ROOT / "Sources/ProctorUI/MainWindow.swift").read_text()
    examined = len(literals.literals(src))
    by_id = {c["id"]: c for c in four}
    check(by_id["CASE-0102"]["source"]["examined"] == examined,
          f"CASE-0102's denominator is what the classifier counts today ({examined})",
          f"row says {by_id['CASE-0102']['source']['examined']}")




def _fixture(tmp: Path, clear: bool) -> Path:
    """A copy of this project's registry, optionally with its standing census
    findings cleared.

    Copied rather than synthesised, so the control is exercised against the
    shapes it actually meets. `clear=False` is the registry as it stands, which
    is red on `uncensused` and is the state DEF-075 was found in.
    """
    d = tmp / ("clear" if clear else "red")
    d.mkdir(parents=True)
    for name in ("inventory.json", "cases.json"):
        src = ROOT / "docs/test-campaign" / name
        if src.exists():
            (d / name).write_bytes(src.read_bytes())
    if clear:
        inv = json.loads((d / "inventory.json").read_text())
        for r in inv.get("requirement", []):
            if r.get("effect") and r["effect"] != "none" and not r.get("provider"):
                r["provider"] = "fixture-only provider, so this copy starts clear"
        (d / "inventory.json").write_text(json.dumps(inv, indent=2) + "\n")
    return d


def _seed_strengthen(d: Path) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(ROOT / "scripts/campaign/seed_strengthen.py"), str(d), "REQ-017"],
        capture_output=True, text=True, cwd=str(ROOT))


def test_seed_strengthen_refuses_a_red_baseline() -> None:
    """DEF-075. The shipped control prints "The gate bites" from before=red.

    Three checks, and the second is the one that keeps the first honest: a
    control that refused every input would satisfy the refusal check alone and
    have stopped being a control.
    """
    with tempfile.TemporaryDirectory() as tmp:
        tmp = Path(tmp)

        red = _fixture(tmp, clear=False)
        before = hashlib.sha256((red / "inventory.json").read_bytes()).hexdigest()
        out = _seed_strengthen(red)
        check(out.returncode == 2,
              "seed_strengthen refuses a census that is already red (exit 2)",
              f"exit {out.returncode}: {out.stdout[-400:]}")
        check("REFUSING" in out.stdout and "already red" in out.stdout,
              "the refusal names the state it found",
              out.stdout[-400:])
        # Naming the state means the counts, not just the word. The registry as
        # it stands is red on uncensused, so that pass and its population appear.
        check("uncensused (" in out.stdout and "findings over" in out.stdout,
              "the refusal reports which pass was red and over what population",
              out.stdout[-400:])
        check(hashlib.sha256((red / "inventory.json").read_bytes()).hexdigest() == before,
              "a refused run leaves the registry untouched",
              "the refusal path mutated the registry")

        clear = _fixture(tmp, clear=True)
        before_clear = hashlib.sha256((clear / "inventory.json").read_bytes()).hexdigest()
        out = _seed_strengthen(clear)
        check(out.returncode == 0,
              "seed_strengthen still runs, and bites, on a clear baseline (exit 0)",
              f"exit {out.returncode}: {out.stdout[-400:]}")
        check("before=clear after=red" in out.stdout,
              "the run that is allowed through reports a bite from a clear baseline",
              out.stdout[-400:])
        check(hashlib.sha256((clear / "inventory.json").read_bytes()).hexdigest() == before_clear,
              "the registry is byte-identical after a completed run",
              "the mutation was not restored")
        check("registry restored byte-for-byte: True" in out.stdout,
              "the control verifies its own restoration rather than asserting it",
              out.stdout[-400:])


def main() -> int:
    for fn in (test_mutate_swift_closure_shorthand, test_merge_registry,
               test_merge_registry_on_this_registry,
               test_case_0074_load_matches_its_evidence, test_source_analysis_rung,
               test_seed_strengthen_refuses_a_red_baseline):
        try:
            fn()
        except Exception as exc:                                    # noqa: BLE001
            check(False, f"{fn.__name__} raised", f"{type(exc).__name__}: {exc}")
    failed = [label for ok, label in RESULTS if not ok]
    print(f"campaign instruments: {len(RESULTS) - len(failed)} passed, {len(failed)} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
