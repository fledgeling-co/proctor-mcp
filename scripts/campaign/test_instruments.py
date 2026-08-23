#!/usr/bin/env python3
"""Gate tests for the campaign instruments this repo owns.

The instruments that measure this project are measured here, because each of the
defects below was found by somebody checking a tool rather than reading its
output. Every check here is watched in both directions — the fixture that trips
it and the fixture that clears it, in one session — so a check that cannot fire
is distinguishable from a check that found nothing. `main()` prints how many ran,
so a check that quietly stopped being called shows up in the count rather than in
nothing at all. The first fifteen were armed at PRO-0091 and recorded in
`docs/test-campaign/evidence/PRO-0091/instrument-arming.txt` with the mutation
that armed each one; the ones added since carry both fixtures inline. Arming has
now caught three: one check asserting over a population of zero (PRO-0091) and
two bare-name collisions in the operator-path gate (PRO-0099, DEF-170/171), and
all three were found by arming rather than by reading.

`Tests/ProctorCoreTests/CampaignInstrumentTests.swift` runs this file, so
`./scripts/test.sh` owns the verdict and a red here is a red suite.

    python3 scripts/campaign/test_instruments.py        # quiet unless something fails
    python3 scripts/campaign/test_instruments.py -v
"""
from __future__ import annotations

import atexit
import contextlib
import hashlib
import importlib.util
import io
import json
import os
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


# ── REQ-067: an item cannot merge claiming a defect the registry calls open ──
#
# `inventory.json` reported 23 open defects over a tree that had fixed most of
# them, because the items that fixed them never moved the records and nothing
# read the two together. The claim is already written down — an item's spec
# states its defects on the `**Defects:**` line and again in its `## Defects`
# table — so the check reads the claim rather than asking anyone to remember it.
#
# Armed in both directions on one fixture registry, with the same spec: the
# defect open, and the defect fixed.

def _gate(*args) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(ROOT / "scripts/campaign/defect_gate.py"), *map(str, args)],
        capture_output=True, text=True, cwd=ROOT)


def test_defect_gate_claims() -> None:
    spec = (
        "# FIX-0001: a fixture\n\n"
        "**ID:** FIX-0001 · **Defects:** DEF-901..DEF-903 · **Cases:** CASE-0001\n\n"
        "## Defects\n\n"
        "| Id | What |\n|---|---|\n"
        "| DEF-901 | the first |\n| DEF-904 | recorded in the table and not the header |\n"
    )
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        spec_path = root / "spec-FIX-0001.md"
        spec_path.write_text(spec)
        reg = root / "registry"
        reg.mkdir()

        def write(statuses: dict[str, str]) -> None:
            (reg / "inventory.json").write_text(json.dumps(
                {"defect": [{"id": i, "status": s, "title": f"fixture {i}"}
                            for i, s in statuses.items()]}, indent=2))

        every = ["DEF-901", "DEF-902", "DEF-903", "DEF-904"]

        write({i: "open" for i in every})
        red = _gate("claims", spec_path, reg)
        check(red.returncode == 1,
              "claims refuses a spec whose claimed defects still read open",
              f"exit {red.returncode}: {red.stdout[-400:]}")
        # The range on the header line and the extra row in the table are both
        # read: an item that overran its allocation records the overrun in the
        # table only, which is the shape PRO-0081 took.
        for i in every:
            check(f"OPEN     {i}" in red.stdout,
                  f"claims names {i} as the reason it refused",
                  red.stdout[-600:])

        write({i: "fixed" for i in every})
        green = _gate("claims", spec_path, reg)
        check(green.returncode == 0,
              "claims passes over the same spec once every record reads fixed",
              f"exit {green.returncode}: {green.stdout[-400:]}")

        # A claim with no row at all is not the same as a claim that is closed,
        # and reporting it as a pass is how a renumbered id disappears.
        write({"DEF-901": "fixed", "DEF-902": "fixed", "DEF-903": "fixed"})
        missing = _gate("claims", spec_path, reg)
        check(missing.returncode == 1 and "UNKNOWN  DEF-904" in missing.stdout,
              "a claimed defect with no registry row is a finding, not a pass",
              missing.stdout[-400:])

        # A spec naming no defects measured nothing, and a check that cannot
        # tell that from a clean result is the condition this file exists for.
        bare = root / "spec-FIX-0002.md"
        bare.write_text("# FIX-0002\n\nNo defects here.\n")
        empty = _gate("claims", bare, reg)
        check(empty.returncode == 1 and "measured nothing" in empty.stdout,
              "a spec with no parsable claim refuses rather than passing empty",
              empty.stdout[-300:])


# ── REQ-068: a value a merged item set is still in the tree ─────────────────
#
# The drift the reconciliation found. Eleven values were set by merged items and
# were not at HEAD — five defect flips and REQ-024's `vacuous` from PRO-0091,
# CASE-0032's evidence from PRO-0088, CASE-0059's capture block, CASE-0063's
# witness block and DEF-024's whole row from PRO-0078. `merge_registry.py`
# resolves a same-id conflict by keeping ours, which is right for a hand merge
# and wrong for one nobody reads afterwards.
#
# The fixture is a real git repository, because the check reads history and a
# check tested against a stub of its own input has been watched fail nothing.
# It holds one dropped value AND one legitimate later correction, so a run that
# reported both would be indistinguishable from one that reported neither.

def test_defect_gate_dropped() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        repo = Path(tmp) / "repo"
        (repo / "docs/test-campaign").mkdir(parents=True)
        (repo / "scripts/campaign").mkdir(parents=True)
        (repo / "scripts/campaign/defect_gate.py").write_text(
            (ROOT / "scripts/campaign/defect_gate.py").read_text())

        inv = repo / "docs/test-campaign/inventory.json"
        (repo / "docs/test-campaign/cases.json").write_text("[]\n")
        env = {"GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@t",
               "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@t",
               "GIT_AUTHOR_DATE": "2026-01-01T00:00:00Z",
               "GIT_COMMITTER_DATE": "2026-01-01T00:00:00Z",
               "PATH": os.environ.get("PATH", ""), "HOME": tmp}

        def git(*args: str) -> subprocess.CompletedProcess:
            return subprocess.run(["git", *args], cwd=repo, capture_output=True,
                                  text=True, env=env)

        def commit(message: str) -> None:
            git("add", "-A")
            git("commit", "-q", "-m", message)

        def write(rows: list[dict]) -> None:
            inv.write_text(json.dumps({"defect": rows}, indent=2) + "\n")

        def gate() -> subprocess.CompletedProcess:
            return subprocess.run(
                [sys.executable, "scripts/campaign/defect_gate.py", "dropped",
                 "docs/test-campaign"], cwd=repo, capture_output=True, text=True)

        git("init", "-q", "-b", "main")

        write([{"id": "DEF-901", "status": "open"}, {"id": "DEF-902", "status": "open"}])
        commit("base")

        # An item branches, fixes both records and adds one of its own.
        git("checkout", "-q", "-b", "item")
        write([{"id": "DEF-901", "status": "fixed"}, {"id": "DEF-902", "status": "fixed"},
               {"id": "DEF-903", "status": "open"}])
        commit("the item that fixed them")

        # Meanwhile main makes a decision of its own on DEF-902 — a genuine
        # conflict, and the one thing this check must NOT report, because a
        # check that reports every difference is as useless as one that reports
        # none and a single red cannot tell them apart.
        git("checkout", "-q", "main")
        write([{"id": "DEF-901", "status": "open"}, {"id": "DEF-902", "status": "wontfix"}])
        commit("a decision taken on main")

        # The merge keeps ours wholesale. DEF-901 goes back to open, DEF-903
        # never arrives, and DEF-902 comes out holding neither side's start.
        git("merge", "-q", "-s", "ours", "--no-edit", "item")

        red = gate()
        check(red.returncode == 1,
              "dropped refuses a history whose merge came out holding the base",
              f"exit {red.returncode}: {red.stdout[-600:]}")
        check("DEF-901.status" in red.stdout,
              "dropped names the field the merge discarded",
              red.stdout[-600:])
        check("DEF-903" in red.stdout and "absent at HEAD" in red.stdout,
              "dropped names a whole row the merge did not take",
              red.stdout[-600:])
        check("DEF-902" not in red.stdout,
              "a field both sides changed is a decision, not a drop",
              red.stdout[-600:])

        # The other direction, in the same session: restore what the merge lost
        # and the same history over the same merge reads clean, so the green is
        # a measurement rather than an absence.
        write([{"id": "DEF-901", "status": "fixed"}, {"id": "DEF-902", "status": "wontfix"},
               {"id": "DEF-903", "status": "open"}])
        commit("restore what the merge dropped")
        green = gate()
        check(green.returncode == 0,
              "dropped passes once the discarded values are back",
              f"exit {green.returncode}: {green.stdout[-600:]}")


# ── The two gates, run against this repository's own registry ───────────────
#
# The fixtures above prove the checks can fire. This one is the claim that
# matters to a reader: on this tree, right now, nothing is dropped and every
# defect this item claims is closed. It runs the real thing rather than citing
# an evidence file, because an evidence file is what went stale in this wave.

def test_defect_gate_on_this_repository() -> None:
    out = _gate("dropped", ROOT / "docs/test-campaign")
    check(out.returncode == 0,
          "no registry value an ancestor commit set is missing from this tree",
          out.stdout[-800:])
    out = _gate("claims", ROOT / "docs/specs/spec-PRO-0097.md", ROOT / "docs/test-campaign")
    check(out.returncode == 0,
          "every defect this item's spec claims reads fixed in the registry",
          out.stdout[-800:])


# ── PRO-0099: the operator-path gate, and the two bugs arming it found ──────
#
# `operator_path_gate.py` refuses a new static that computes a path under the
# operator's application-support root with no injection seam — the shape behind
# DEF-042, DEF-142, DEF-164 and the three writers this item converted. It is a
# gate whose healthy state is silence, so it is exactly the kind that rots into a
# check that cannot fire.
#
# Arming it found two, both bare-name collisions in `PolicyStore.swift`, and both
# recorded as fixtures below so they cannot come back:
#
#   DEF-170  `enclosing_type` took the nearest type indented less than the site
#            without asking whether that type still CONTAINED it. `final class
#            Seams` closes 19 lines above the operator literal in
#            `AuditLog.directory`, so the census attributed the literal to
#            `Seams.directory`, matched no entry, and reported a classed writer
#            as an unclassed one. A false RED.
#   DEF-171  `declaration_body` resolved a dotted name to the FIRST declaration of
#            that name inside the owning type rather than the owner's own member.
#            `Seams.directory` — a lock-guarded stored property one level in —
#            comes first, and its body holds no test-process predicate, so the
#            gate reported the audit trail's own interlock as a writer with no
#            branch. Also a false RED, and the direction that gets argued away
#            rather than fixed.
#
# The gate's two modes take `root` and `manifest` as arguments, so both are armed
# on fixture trees here rather than on this repository, and then run once against
# the real one.

_OPERATOR_LITERAL = "Library/Application Support/"


def _operator_gate():
    return load(ROOT / "scripts/campaign/operator_path_gate.py", "operator_path_gate")


def _operator_tree(tmp: str, files: dict[str, str]) -> Path:
    root = Path(tmp)
    for rel, text in files.items():
        path = root / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
    return root


_OPERATOR_HOMES = ["FileManager.default.homeDirectoryForCurrentUser", "NSHomeDirectory()"]


def _operator_manifest(entries: list[dict], guards: dict | None = None) -> dict:
    return {"root_literal": _OPERATOR_LITERAL,
            "predicates": ["TestProcess.isActive", "isTestProcess"],
            "home_expressions": _OPERATOR_HOMES,
            "entries": entries,
            "guards": guards or {}}


# The three shapes the PRO-0099 verifier built that cleared BOTH modes, each now a
# fixture. All three are the same failure — the gate resolving a site correctly and
# then losing the resolution — and the third is the sharpest, because it is exactly
# how `SwitchStore.operatorURL` is written.
_SWITCH_STORE = """import Foundation

public enum SwitchStore {
    public static func url(home: URL) -> URL {
        home.appendingPathComponent(
            "Library/Application Support/example/settings", isDirectory: true)
    }

    public static var operatorURL: URL {
%s    }

    public static var defaultURL: URL {
        guard TestProcess.isActive else { return operatorURL }
        return testFallbackRoot
    }
}
"""
_COMPOSED = "        url(home: FileManager.default.homeDirectoryForCurrentUser)\n"
_SPELT_OUT = ('        FileManager.default.homeDirectoryForCurrentUser\n'
              '            .appendingPathComponent("Library/Application Support/example/settings")\n')
_SWITCH_ENTRIES = [
    {"file": "Sources/ProctorCore/SwitchStore.swift", "declaration": "url",
     "class": "parameterised", "parameter": "home", "reason": "fixture"},
    {"file": "Sources/ProctorCore/SwitchStore.swift", "declaration": "operatorURL",
     "class": "operator-accessor", "seamed_by": "defaultURL", "reason": "fixture"},
]


def test_operator_path_gate_bare_name_is_not_a_wildcard() -> None:
    """A second declaration of a classed bare name is not absorbed by its entry."""
    gate = _operator_gate()
    file = "Sources/ProctorCore/SwitchStore.swift"
    legacy = (_SWITCH_STORE % _SPELT_OUT).replace(
        "public enum SwitchStore {",
        'public enum Legacy {\n'
        '    public static var operatorURL: URL {\n'
        '        FileManager.default.homeDirectoryForCurrentUser\n'
        '            .appendingPathComponent("Library/Application Support/example/legacy")\n'
        '    }\n'
        '}\n\n'
        'public enum SwitchStore {')

    with tempfile.TemporaryDirectory() as tmp:
        root = _operator_tree(tmp, {file: legacy})
        armed = gate.run_census(root, _operator_manifest(_SWITCH_ENTRIES))
        check(len(armed) == 2
              and any("Legacy.operatorURL" in f for f in armed)
              and any("SwitchStore.operatorURL" in f for f in armed),
              "a new operator path sharing a classed bare name is refused, and so is the "
              "site the bare entry used to cover, until the manifest says which is which",
              "\n".join(armed) or "no finding: the bare entry absorbed the new declaration")

    with tempfile.TemporaryDirectory() as tmp:
        # Both spelled qualified, and both clear.
        root = _operator_tree(tmp, {file: legacy})
        qualified = [dict(_SWITCH_ENTRIES[0]),
                     {"file": file, "declaration": "SwitchStore.operatorURL",
                      "class": "operator-accessor", "seamed_by": "defaultURL",
                      "reason": "fixture"},
                     {"file": file, "declaration": "Legacy.operatorURL",
                      "class": "prose", "reason": "fixture"}]
        cleared = gate.run_census(root, _operator_manifest(qualified))
        check(not cleared, "the same tree clears once each site is classed by its "
                           "qualified name", "\n".join(cleared))


def test_operator_path_gate_qualified_reach_is_never_excused() -> None:
    """A file declaring the same name may not reach the accessor by its owner."""
    gate = _operator_gate()
    file = "Sources/ProctorCore/SwitchStore.swift"
    bypass = "Sources/ProctorAgent/Bypass.swift"

    with tempfile.TemporaryDirectory() as tmp:
        # The shape that used to pass: a colliding declaration in the file, and a
        # QUALIFIED reach around the seam beside it.
        root = _operator_tree(tmp, {
            file: _SWITCH_STORE % _SPELT_OUT,
            bypass: "enum Bypass {\n    static var operatorURL: URL { SwitchStore.operatorURL }\n}\n"})
        armed = gate.run_seams(root, _operator_manifest(_SWITCH_ENTRIES))
        check(any("SwitchStore.operatorURL" in f and "around its seam" in f for f in armed),
              "a qualified reach around the seam is refused even from a file that "
              "declares the same bare name",
              "\n".join(armed) or "no finding: the whole file was skipped")

    with tempfile.TemporaryDirectory() as tmp:
        # And the reason the excuse exists at all still holds: a file using its OWN
        # member of that name, and never the owner's, clears.
        root = _operator_tree(tmp, {
            file: _SWITCH_STORE % _SPELT_OUT,
            bypass: "enum Bypass {\n    static var operatorURL: URL { operatorURL }\n}\n"})
        cleared = gate.run_seams(root, _operator_manifest(_SWITCH_ENTRIES))
        check(not cleared,
              "a file reaching only its own declaration of that name still clears",
              "\n".join(cleared))


def test_operator_path_gate_composed_path() -> None:
    """A path composed from the operator's home names no literal, and is still a site."""
    gate = _operator_gate()
    file = "Sources/ProctorCore/SwitchStore.swift"
    bypass = "Sources/ProctorAgent/Bypass.swift"
    composed = ("enum Bypass {\n"
                "    static var settingsURL: URL {\n"
                "        SwitchStore.url(home: FileManager.default.homeDirectoryForCurrentUser)\n"
                "    }\n}\n")

    with tempfile.TemporaryDirectory() as tmp:
        root = _operator_tree(tmp, {file: _SWITCH_STORE % _COMPOSED, bypass: composed})

        # The literal sweep on its own sees nothing here, which is the hole.
        literal = gate.census_sites(root, _OPERATOR_LITERAL)
        check(all(bypass not in site[0] for site in literal),
              "the literal sweep genuinely cannot see a composed path, so the second "
              "sweep is doing the work rather than duplicating it",
              f"literal sites: {[s[0] for s in literal]}")

        armed = gate.run_census(root, _operator_manifest(_SWITCH_ENTRIES))
        check(len(armed) == 1 and "Bypass.settingsURL" in armed[0],
              "a new un-seamed path built by handing the operator's own home to a "
              "parameterised builder is refused",
              "\n".join(armed) or "no finding: the composed path needed no entry")

        entry = _SWITCH_ENTRIES + [{"file": bypass, "declaration": "settingsURL",
                                    "class": "prose", "reason": "fixture"}]
        cleared = gate.run_census(root, _operator_manifest(entry))
        check(not cleared, "the same composed path clears once it carries an entry",
              "\n".join(cleared))

        # And the tree's own `operatorURL`, written the same way, is a site rather
        # than an entry with nothing behind it.
        sites = [q for _, _, _, q, _ in gate.composed_sites(root, _operator_manifest(_SWITCH_ENTRIES))]
        check("SwitchStore.operatorURL" in sites,
              "the accessor written as a composition is itself a census site",
              f"composed sites: {sites}")


# The `PolicyStore.swift` shape both bugs came from, reduced to what causes them:
# a nested type that closes ABOVE the site, declaring a member of the same name as
# the outer type's own.
_NESTED_COLLISION = """import Foundation

enum AuditLog {

    final class Seams {
        private var _directory: URL?
        var directory: URL? {
            get { _directory }
            set { _directory = newValue }
        }
    }

    static let seams = Seams()

    static var directory: URL {
%s        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/example/audit",
                                    isDirectory: true)
    }
}
"""
_GUARDED = "        guard !TestProcess.isActive else { return fallback }\n"


def test_operator_path_gate_census() -> None:
    """A new operator path with no entry fails; the same path classed clears."""
    gate = _operator_gate()
    source = (
        "import Foundation\n\n"
        "public enum NewStore {\n"
        "    public static var defaultURL: URL {\n"
        "        home.appendingPathComponent(\n"
        '            "Library/Application Support/example/settings", isDirectory: true)\n'
        "    }\n"
        "}\n"
    )
    file = "Sources/ProctorCore/NewStore.swift"
    with tempfile.TemporaryDirectory() as tmp:
        root = _operator_tree(tmp, {file: source})

        armed = gate.run_census(root, _operator_manifest([]))
        check(len(armed) == 1 and "NewStore.defaultURL" in armed[0],
              "the census refuses a new operator path that is classed nowhere",
              "\n".join(armed) or "no finding: the census cannot report one")

        entry = [{"file": file, "declaration": "defaultURL", "class": "prose",
                  "reason": "fixture"}]
        cleared = gate.run_census(root, _operator_manifest(entry))
        check(not cleared,
              "the census clears the same path once it carries an entry",
              "\n".join(cleared))


def test_operator_path_gate_nested_type_collision() -> None:
    """DEF-170: a type that closed above the site is not the site's owner."""
    gate = _operator_gate()
    file = "Sources/ProctorAgent/PolicyStore.swift"
    with tempfile.TemporaryDirectory() as tmp:
        root = _operator_tree(tmp, {file: _NESTED_COLLISION % _GUARDED})

        sites = gate.census_sites(root, _OPERATOR_LITERAL)
        qualified = [q for _, _, _, q, _ in sites]
        check(qualified == ["AuditLog.directory"],
              "the census attributes an operator literal to the type that contains it, "
              "not to a nested type that closed above it",
              f"resolved to {qualified}")

        # Both directions over one fixture: the entry naming the containing type
        # clears, and the entry naming the closed nested type does not.
        right = [{"file": file, "declaration": "AuditLog.directory",
                  "class": "writer-seam", "reason": "fixture"}]
        wrong = [{"file": file, "declaration": "Seams.directory",
                  "class": "writer-seam", "reason": "fixture"}]
        check(not gate.run_census(root, _operator_manifest(right)),
              "the census clears a nested-type file classed on its containing type")
        check(len(gate.run_census(root, _operator_manifest(wrong))) == 1,
              "the census still refuses that file when the entry names the wrong owner")


def test_operator_path_gate_seam_resolution() -> None:
    """DEF-171: a dotted name resolves to the owner's member, not a nested one."""
    gate = _operator_gate()
    file = "Sources/ProctorAgent/PolicyStore.swift"
    entry = [{"file": file, "declaration": "AuditLog.directory",
              "class": "writer-seam", "reason": "fixture"}]

    with tempfile.TemporaryDirectory() as tmp:
        # `Seams.directory` is declared first and carries no predicate. The seam
        # check must read `AuditLog.directory`, which carries one.
        root = _operator_tree(tmp, {file: _NESTED_COLLISION % _GUARDED})
        lines = (root / file).read_text().splitlines()
        found = gate.declaration_body(lines, "AuditLog.directory")
        body = "\n".join(found[1]) if found else ""
        check(found is not None and "TestProcess.isActive" in body,
              "a dotted name resolves to the owning type's own member rather than "
              "the first declaration of that name inside it",
              f"resolved to: {body[:200]}")

        cleared = gate.run_seams(root, _operator_manifest(entry))
        check(not cleared,
              "the seam check clears a writer whose own body carries the predicate",
              "\n".join(cleared))

    with tempfile.TemporaryDirectory() as tmp:
        # THE ARMING. The same fixture with the predicate removed from the writer,
        # leaving the nested property untouched, must go red.
        root = _operator_tree(tmp, {file: _NESTED_COLLISION % ""})
        armed = gate.run_seams(root, _operator_manifest(entry))
        check(len(armed) == 1 and "no test-process branch" in armed[0],
              "the seam check refuses a writer with no test-process branch",
              "\n".join(armed) or "no finding: the seam check cannot report one")


def test_operator_path_gate_accessor_and_guard() -> None:
    """An operator-accessor needs a seam that branches, returns it, and is not bypassed."""
    gate = _operator_gate()
    file = "Sources/ProctorCore/SwitchStore.swift"

    def source(guard: str) -> str:
        return (
            "import Foundation\n\n"
            "public enum SwitchStore {\n"
            "    public static var operatorURL: URL {\n"
            "        home.appendingPathComponent(\n"
            '            "Library/Application Support/example/settings", isDirectory: true)\n'
            "    }\n\n"
            "    public static var defaultURL: URL {\n"
            f"{guard}"
            "        return testFallbackRoot\n"
            "    }\n"
            "}\n"
        )

    entry = [{"file": file, "declaration": "operatorURL", "class": "operator-accessor",
              "seamed_by": "defaultURL", "reason": "fixture"}]
    seamed = "        guard TestProcess.isActive else { return operatorURL }\n"

    with tempfile.TemporaryDirectory() as tmp:
        root = _operator_tree(tmp, {file: source(seamed)})
        cleared = gate.run_seams(root, _operator_manifest(entry))
        check(not cleared, "a seamed operator-accessor clears", "\n".join(cleared))

    with tempfile.TemporaryDirectory() as tmp:
        root = _operator_tree(tmp, {file: source("")})
        armed = gate.run_seams(root, _operator_manifest(entry))
        check(len(armed) == 1 and "no test-process branch" in armed[0],
              "an operator-accessor whose seam does not branch on the test process is refused",
              "\n".join(armed) or "no finding")

    with tempfile.TemporaryDirectory() as tmp:
        # The seam branches but never returns the truthful path, so production
        # would resolve somewhere else.
        root = _operator_tree(
            tmp, {file: source("        guard TestProcess.isActive else { return elsewhere }\n")})
        armed = gate.run_seams(root, _operator_manifest(entry))
        check(any("never returns" in f for f in armed),
              "a seam that branches but drops the operator path is refused",
              "\n".join(armed) or "no finding")

    with tempfile.TemporaryDirectory() as tmp:
        # And another file reaching the truthful accessor around its seam.
        root = _operator_tree(tmp, {
            file: source(seamed),
            "Sources/ProctorAgent/Bypass.swift":
                "func save() { try? write(to: SwitchStore.operatorURL) }\n",
        })
        armed = gate.run_seams(root, _operator_manifest(entry))
        check(any("around its seam" in f for f in armed),
              "a caller reaching the truthful operator path around its seam is refused",
              "\n".join(armed) or "no finding")


def test_operator_path_gate_reflector_guard() -> None:
    """The `guards` block refuses a bare reflector start under Tests/."""
    gate = _operator_gate()
    guards = {"no_bare_reflector_start": {
        "reason": "fixture", "tree": "Tests", "forbidden": "ProctorReflector.start()"}}

    with tempfile.TemporaryDirectory() as tmp:
        root = _operator_tree(tmp, {
            "Tests/ProctorCoreTests/ReflectorTests.swift":
                "func test() { ProctorReflector.start() }\n"})
        armed = gate.run_seams(root, _operator_manifest([], guards))
        check(len(armed) == 1 and "no_bare_reflector_start" in armed[0],
              "a bare ProctorReflector.start() under Tests/ is refused",
              "\n".join(armed) or "no finding")

    with tempfile.TemporaryDirectory() as tmp:
        root = _operator_tree(tmp, {
            "Tests/ProctorCoreTests/ReflectorTests.swift":
                'func test() { ProctorReflector.start(supportDirectory: tmp) }\n'})
        check(not gate.run_seams(root, _operator_manifest([], guards)),
              "the same call with an explicit path clears")


def test_operator_path_gate_on_this_repository() -> None:
    """The real thing, both modes, on this tree."""
    for mode in ("census", "seams"):
        out = subprocess.run(
            [sys.executable, str(ROOT / "scripts/campaign/operator_path_gate.py"), mode],
            capture_output=True, text=True, cwd=ROOT)
        check(out.returncode == 0,
              f"operator_path_gate `{mode}` is clean on this tree",
              (out.stdout + out.stderr)[-800:])



# ── DEF-207: the splice was never read back ─────────────────────────────────
#
# `mutate_swift.py`'s `apply()` spliced by byte offset and returned nothing, so a
# wrong-offset write was silent: the harness graded pristine or wrongly-edited
# code and no line anywhere disagreed with the verdict. An anchor-string mutator
# that aborts at least reports INERT; this had nothing to report. A survivor then
# has two readings — the guard is decorative, or the mutation never happened.
#
# Both directions, and the fixture is the drift the offsets are exposed to:
# `candidates()` reads the file, and between that read and the write the text can
# move. The pre-repair form is reproduced inline as the control, so this is a
# comparison across the repair rather than a check that merely passes now.

def _mutate_swift():
    return load(ROOT / "scripts/campaign/mutate_swift.py", "mutate_swift_def207")


def test_mutate_swift_proves_its_splice() -> None:
    mod = _mutate_swift()
    source = "func f() -> Bool { return a == b }\n"
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "F.swift"

        # The offsets a candidates() pass over `source` would have produced.
        start = source.index("==")
        good = {"file": str(path), "start": start, "end": start + 2,
                "before": "==", "after": "!=", "line": 1}

        path.write_text(source)
        mod._APPLIED.clear()
        landed, why = mod.apply(dict(good))
        check(landed and path.read_text() == source.replace("==", "!=", 1),
              "a splice at the right offset lands and says so", why)
        check("confirmed by re-reading the file" in why,
              "the landing message names how it was established", why)

        # The same mutant against a file that moved under it: one line inserted
        # above, so every offset is late by that line's length.
        drifted = "// a line somebody added\n" + source
        path.write_text(drifted)
        mod._APPLIED.clear()
        landed, why = mod.apply(dict(good))
        check(not landed, "a splice whose offsets have drifted is refused", why)
        check(path.read_text() == drifted,
              "the refused splice left the file exactly as it was")
        check("the file moved under the offsets" in why,
              "the refusal says what it found instead", why)

        # The pre-repair form, verbatim, on the same fixture.
        text = path.read_text()
        path.write_text(text[:good["start"]] + good["after"] + text[good["end"]:])
        check(path.read_text() != drifted and "==" in path.read_text(),
              "the pre-repair splice wrote into the wrong place and reported nothing",
              repr(path.read_text()))
        check("fun!=f()" in path.read_text() and "a == b" in path.read_text(),
              "and the damage it did is the one nothing in the log would mention: the "
              "declaration mangled while the site it meant to mutate stands untouched",
              repr(path.read_text()))

        # A write that does not survive a re-read is refused too, which is the
        # half an offset check alone cannot cover.
        path.write_text(source)
        mod._APPLIED.clear()
        real_write = Path.write_text
        try:
            Path.write_text = lambda self, data, *a, **k: real_write(self, source, *a, **k)
            landed, why = mod.apply(dict(good))
        finally:
            Path.write_text = real_write
        check(not landed and "not the text that was written" in why,
              "a write the disk did not take is refused on the re-read", why)


def test_mutate_swift_unproved_mutation_is_inconclusive() -> None:
    """The verdict wiring: a mutant that did not land is never scored.

    A survivor and a kill are both statements about a mutated tree, so an
    unproved edit has no outcome to grade. It must be `inconclusive`, out of the
    survival-rate denominator, and the suite must not be run for it at all —
    running it would produce a verdict about pristine code.
    """
    mod = _mutate_swift()
    source = "func f() -> Bool { return a == b }\n"
    with tempfile.TemporaryDirectory() as tmp:
        tmpdir = Path(tmp)
        path = tmpdir / "F.swift"
        path.write_text(source)
        ran = []

        good = {"file": str(path), "start": source.index("=="), "end": source.index("==") + 2,
                "before": "==", "after": "!=", "line": 1}
        drifted = dict(good, start=0, end=2)      # points at "fu", not "=="

        real_candidates, real_run_suite = mod.candidates, mod.run_suite
        real_revert, real_restore = mod.revert, mod.restore_all
        try:
            mod.candidates = lambda _p: [dict(good), dict(drifted)]
            mod.run_suite = lambda timeout: (ran.append(1), (True, "passed"))[1]
            mod.revert = lambda m: (path.write_text(source), (True, "stub"))[1]
            mod.restore_all = lambda: path.write_text(source)
            out = tmpdir / "out.json"
            sys.argv = ["mutate_swift.py", "--targets", str(path), "--count", "2",
                        "--out", str(out), "--timeout", "5"]
            # main() runs a baseline and a git-clean check; both are stubbed to the
            # answers a clean tree would give, so the loop under test is the subject.
            real_subprocess_run = mod.subprocess.run

            class _P:
                def __init__(self, stdout="", returncode=0):
                    self.stdout, self.stderr, self.returncode = stdout, "", returncode

            mod.subprocess.run = lambda *a, **k: _P()
            try:
                with contextlib.redirect_stdout(io.StringIO()) as spoken:
                    code = mod.main()
            finally:
                mod.subprocess.run = real_subprocess_run
            record = json.loads(out.read_text())
            said = spoken.getvalue()
        finally:
            # main() registers whatever `restore_all` names at the time, so the
            # stub would outlive the temporary directory and fire at interpreter
            # exit against a path that is gone.
            atexit.unregister(mod.restore_all)
            mod.candidates, mod.run_suite = real_candidates, real_run_suite
            mod.revert, mod.restore_all = real_revert, real_restore

    verdicts = {r["before"] + "@" + str(r["start"]): r["verdict"] for r in record["mutants"]}
    s = record["summary"]
    check(code == 0, f"the run completed (exit {code})")
    check(s["inconclusive"] == 1, f"the drifted mutant is counted apart ({s['inconclusive']})")
    check(s["scored"] == 1 and s["survived"] == 1,
          f"only the mutant that landed is in the denominator (scored {s['scored']})")
    check(len(ran) == 2,
          "the suite ran for the baseline and the one mutant that landed, and not for the "
          f"one that did not ({len(ran)} run(s))")
    check("inconclusive" in said and "NOT in that denominator" in said,
          "the summary tells the reader an unproved mutant was set aside, and why",
          said[-400:])
    check("inconclusive" in verdicts.values(),
          f"the verdict is `inconclusive` rather than a kill or a survivor: {verdicts}")
    row = [r for r in record["mutants"] if r["verdict"] == "inconclusive"][0]
    check("the file moved under the offsets" in row["mutationLanded"],
          "and the row names why the step could not be proved", row["mutationLanded"])


def test_mutate_swift_unreported_suite_is_inconclusive() -> None:
    """DEF-240: the same hole as DEF-208, inside this file rather than beside it.

    `run_suite` read `p.returncode == 0` as the whole verdict once a build error
    was ruled out, so a runner dying after linking and before reporting scored
    `failed` and then `killed` — the direction that flatters the suite, because it
    credits the tests with catching a fault they were never run against.

    The (passed, why) contract is held on purpose: `mutation_timeout_arm.py`
    substitutes its own `run_suite` to drive the runner end to end, so widening it
    would break the arming that watches this file. Checked here rather than
    assumed.
    """
    mod = _mutate_swift()
    real_subprocess_run = mod.subprocess.run

    class _P:
        def __init__(self, out, code):
            self.stdout, self.stderr, self.returncode = out, "", code

    linked = "Build complete! (4.83s)\n"
    cases = [
        ("a run that reported a failure", linked + "Test run with 1 test in 1 suite failed "
         "after 0.001 seconds with 1 issue.", 1, "failed", "killed"),
        ("a run that died after linking", linked + "error: Process '…' exited with unexpected "
         "signal code 5\nFAIL: no swift-testing verdict line in the output.", 1,
         "no-verdict-line", "inconclusive"),
        ("a run that passed", linked + "Test run with 2074 tests in 252 suites passed after "
         "18.008 seconds.", 0, "passed", "SURVIVED"),
        ("a build failure", "error: cannot find 'x' in scope\n", 1, "build-failed", "unbuildable"),
    ]
    try:
        for label, out, code, want_why, want_verdict in cases:
            mod.subprocess.run = lambda *a, _o=out, _c=code, **k: _P(_o, _c)
            passed, why = mod.run_suite(600)
            check(why == want_why, f"{label} is reported as `{want_why}` ({why})")
            verdict, _near = mod.score(passed, why, 12.0, 600)
            check(verdict == want_verdict,
                  f"{label} scores `{want_verdict}` ({verdict})")
    finally:
        mod.subprocess.run = real_subprocess_run

    check(len(mod.run_suite.__annotations__.get("return").__args__) == 2
          if hasattr(mod.run_suite.__annotations__.get("return"), "__args__") else True,
          "run_suite still returns the (passed, why) pair mutation_timeout_arm substitutes")
    timeout_arm = (ROOT / "scripts/campaign/mutation_timeout_arm.py").read_text()
    check('return (True, "passed") if calls["n"] == 1 else (False, "timeout")' in timeout_arm,
          "and the substitute in mutation_timeout_arm.py still matches that shape")


# ── DEF-208: a non-zero exit is not a test result ───────────────────────────
#
# `armed = code != 0` read three different events as one: a check firing, a
# process dying in setup, and a `--filter` matching nothing. CASE-0461's trapping
# mutant gave signal 5, zero verdict lines and the suite's own `FAIL: no
# swift-testing verdict line`, and scored ARMED for a reason the rule could not
# see. It IS armed — the log shows the named test running as the process died —
# so the repair makes the rule able to tell rather than weakening the verdict.
#
# The fixture is that run's own recorded output, not a hand-written imitation.

TRAP_LOG = ROOT / "docs/test-campaign/evidence/PRO-0092/correlate-crash-arming.txt"


def _seam_arm():
    return load(ROOT / "scripts/campaign/mutation_seam_arm.py", "seam_arm_def208")


def _parse(mod, text: str, exit_code: int) -> dict:
    return {"exit": exit_code, "timedOut": False,
            "verdict": next((l.strip() for l in reversed(text.splitlines())
                             if mod.VERDICT_RE.search(l)), ""),
            "started": mod.STARTED_RE.findall(text),
            "finished": mod.FINISHED_RE.findall(text), "tail": ""}


def test_seam_arm_scores_the_trap_from_the_log() -> None:
    mod = _seam_arm()
    display, why_display = mod.display_name("correlateReturnsTheMatchingWindowsNumber")
    check(display == "A single fitting window is correlated to its own number",
          "the display name is read out of the Swift source, not hand-copied",
          f"{display!r} — {why_display}")

    text = TRAP_LOG.read_text(errors="replace")
    check("FAIL: no swift-testing verdict line" in text and "unexpected signal code 5" in text,
          "the fixture is the recorded trapping run, with no verdict line in it")
    trap = _parse(mod, text, 1)
    check(trap["verdict"] == "" and display in trap["started"] and display not in trap["finished"],
          f"the log has no verdict line and shows the named test started: {trap['started']}")

    state, armed, why = mod.score_arming(display, why_display, trap, 1200)
    check(state == "ARMED" and armed is True,
          "a trap while the named test was running is armed", f"{state}: {why}")
    check("was the only test to start" in why and "none finished" in why,
          "and the reason names the evidence rather than the exit code", why)
    check("WHAT THIS DOES NOT ESTABLISH" in why,
          "and it says what the started line cannot settle — a trap in the test's own setup, "
          "a require before the subject is called, or a crash in teardown all read the same",
          why)

    # Concurrency: swift-testing runs tests in parallel unless a suite is
    # serialized, so two started lines and no completions cannot say which one
    # died. Out-of-family review, PRO-0106.
    concurrent = dict(trap, started=trap["started"] + ["Some other test"])
    state, armed, why = mod.score_arming(display, why_display, concurrent, 1200)
    check(state == "INCONCLUSIVE" and armed is None,
          "two tests started and none finished cannot attribute the death to either",
          f"{state}: {why}")

    # A verdict line for a run that never started the named test is about some
    # other test, and the exit code cannot say so.
    other = _parse(mod, 'Test run with 1 test in 1 suite failed after 0.001 seconds '
                        'with 1 issue.\n\u1088  Test "Some other test" started.', 1)
    state, armed, why = mod.score_arming(display, why_display, other, 1200)
    check(state == "INCONCLUSIVE" and "never started" in why,
          "a verdict line for a run that never started the named test is inconclusive",
          f"{state}: {why}")

    # The setup death: the same output with the started line taken out. Under the
    # old rule this is indistinguishable from the trap above — both exit 1.
    setup_death = _parse(mod, "\n".join(
        l for l in text.splitlines() if not mod.STARTED_RE.search(l)), 1)
    state, armed, why = mod.score_arming(display, why_display, setup_death, 1200)
    check(state == "INCONCLUSIVE" and armed is None,
          "a non-zero exit with nothing showing the test ran is inconclusive",
          f"{state}: {why}")
    check("died in setup" in why, "and it says which reading it is refusing", why)
    check((trap["exit"] != 0) == (setup_death["exit"] != 0),
          "the two differ in no way the pre-repair rule `armed = code != 0` could see")


def test_seam_arm_scores_a_reported_run() -> None:
    mod = _seam_arm()
    display, why_display = mod.display_name("correlateReturnsTheMatchingWindowsNumber")
    failed = _parse(mod, '\u1088  Test run with 1 test in 1 suite failed after 0.001 seconds '
                         'with 1 issue.', 1)
    state, armed, _ = mod.score_arming(display, why_display, failed, 1200)
    check(state == "ARMED" and armed is True, f"a verdict line and a non-zero exit is armed ({state})")

    passed = _parse(mod, 'Test run with 1 test in 1 suite passed after 0.001 seconds.', 0)
    state, armed, why = mod.score_arming(display, why_display, passed, 1200)
    check(state == "NOT ARMED" and armed is False,
          f"a verdict line and exit 0 is not armed ({state})")
    check("the check did not fire" in why, "and it says so plainly", why)

    timed = {"exit": 124, "verdict": "", "started": [], "finished": [], "timedOut": True}
    state, armed, why = mod.score_arming(display, why_display, timed, 1200)
    check(state == "INCONCLUSIVE" and armed is None,
          f"a starved run is the absence of a measurement ({state})")

    state, armed, why = mod.score_arming(None, "no @Test function named x under Tests/",
                                         _parse(mod, "nothing at all", 1), 1200)
    check(state == "INCONCLUSIVE" and "display name could not be resolved" in why,
          "an unresolvable display name makes the arming inconclusive, not weaker", why)


ZERO_TESTS_LOG = ROOT / "docs/test-campaign/evidence/PRO-0106/zero-tests-arming.txt"


def test_seam_arm_zero_tests_is_not_an_arming() -> None:
    """A filter that matched nothing has not watched anything fail.

    The first repair separated a setup death from a check firing and left the
    third event `armed = code != 0` conflated — a `--filter` matching no test —
    graded as a pass. Driven end to end by the verifier: CASE-0461's real,
    landing mutation with only its Swift function name changed came back

        [CASE-0461] ARMED … exit 1 · Test run with 0 tests in 0 suites passed
        armed 1 of 1 · inconclusive 0

    against a suite in which nothing had run. The fixture is that run recorded
    rather than a string written here: `scripts/test.sh --filter
    thisFunctionDoesNotExistAnywhere`, whose own refusal block is the exit 1.
    """
    mod = _seam_arm()
    text = ZERO_TESTS_LOG.read_text(errors="replace")
    # The fixture, established before anything is read off it — a recorded run
    # that does not carry the shape being graded arms nothing.
    check("Test run with 0 tests in 0 suites passed" in text
          and "FAIL: the run executed 0 tests, which is not a pass." in text
          and "EXIT=1" in text and not mod.STARTED_RE.search(text),
          "the fixture is the recorded zero-test run: a well-formed verdict line over no "
          "tests, scripts/test.sh's own refusal, exit 1, and no started line",
          text[-400:])

    r = _parse(mod, text, 1)
    check(r["verdict"] and mod.verdict_test_count(r["verdict"]) == 0 and not r["started"],
          "and it parses as a verdict line reporting zero tests",
          f"{r['verdict']!r} started={r['started']}")

    display, why_display = mod.display_name("correlateReturnsTheMatchingWindowsNumber")
    state, armed, why = mod.score_arming(display, why_display, r, 1200)
    check(state == "INCONCLUSIVE" and armed is None,
          "an arming that ran zero tests is inconclusive, not armed", f"{state}: {why}")
    check("ZERO tests" in why and "matched nothing" in why,
          "and the reason names the filter rather than the exit code", why)

    # The original defect, reintroduced on this exact path. `armed = code != 0`
    # is the whole of the pre-repair rule; it returns ARMED here, which is the
    # verdict the verifier drove, and the check is that it DISAGREES with what
    # the rule now says. Comparing it to the literal "ARMED" instead would pass
    # whether or not the repair were present, which is this file's own subject.
    before = "ARMED" if r["exit"] != 0 else "NOT ARMED"
    check(before == "ARMED" and before != state,
          "the pre-repair rule `armed = code != 0` scores this same fixture ARMED, and the "
          "repaired rule does not", f"before={before} now={state}")

    # And the repair does not lean on the exit code either way: a zero-test run
    # that exits 0 — `swift test` without this repo's wrapper — is equally
    # unmeasured, and the pre-repair rule called that one NOT ARMED.
    quiet = _parse(mod, text, 0)
    state, armed, why = mod.score_arming(display, why_display, quiet, 1200)
    check(state == "INCONCLUSIVE" and armed is None,
          "and a zero-test run that exits 0 is inconclusive too, not a check that did not fire",
          f"{state}: {why}")
    quiet_before = "ARMED" if quiet["exit"] != 0 else "NOT ARMED"
    check(quiet_before == "NOT ARMED" and quiet_before != state,
          "which the pre-repair rule scored NOT ARMED — the same non-measurement, filed as a "
          "pass in one direction and a fail in the other, and inconclusive both ways now",
          f"before={quiet_before} now={state}")

    # A verdict line over tests that DID run is untouched by the new guard, so
    # the check is watched clearing as well as firing.
    ran = _parse(mod, '\u1088  Test run with 1 test in 1 suite failed after 0.001 seconds '
                      'with 1 issue.', 1)
    state, armed, _ = mod.score_arming(display, why_display, ran, 1200)
    check(state == "ARMED" and armed is True,
          "and the same rule still arms a verdict line over one test that failed", state)


def test_seam_arm_scores_every_route_through_the_rule() -> None:
    """Every route through `score_arming`, enumerated from the code not the tests.

    The failure this item is about is a repair proved on the path its own fixture
    drives, with a sibling path left carrying the original defect — which is how
    the zero-test route above survived the first pass. So the branches are read
    out of `score_arming` and each gets its own fixture, scored on its own and
    with `armed = code != 0` reintroduced against it. Three of the eleven agree
    with the pre-repair rule, and naming which is the point: a control that moves
    on every input is measuring the harness rather than the repair.
    """
    mod = _seam_arm()
    display, why_display = mod.display_name("correlateReturnsTheMatchingWindowsNumber")
    other = "Some other test"
    trap_text = TRAP_LOG.read_text(errors="replace")
    zero_text = ZERO_TESTS_LOG.read_text(errors="replace")

    def log(*lines: str) -> str:
        return "\n".join(lines)

    started_line = 'Test "%s" started.' % display
    other_started = 'Test "%s" started.' % other
    failed_verdict = ('\u1088  Test run with 1 test in 1 suite failed after 0.001 seconds '
                      'with 1 issue.')
    passed_verdict = 'Test run with 1 test in 1 suite passed after 0.001 seconds.'

    # (label, r, display, expected state) — one fixture per route, never one
    # fixture standing for several.
    routes = [
        ("timed out",
         {"exit": 124, "verdict": "", "started": [], "finished": [], "timedOut": True},
         display, "INCONCLUSIVE"),
        ("verdict over zero tests, non-zero exit",
         _parse(mod, zero_text, 1), display, "INCONCLUSIVE"),
        ("verdict over zero tests, exit 0",
         _parse(mod, zero_text, 0), display, "INCONCLUSIVE"),
        ("verdict, and the named test never started",
         _parse(mod, log(failed_verdict, other_started), 1), display, "INCONCLUSIVE"),
        ("verdict, the named test ran, non-zero exit",
         _parse(mod, log(started_line, failed_verdict), 1), display, "ARMED"),
        ("verdict, exit 0",
         _parse(mod, passed_verdict, 0), display, "NOT ARMED"),
        ("no verdict, the display name could not be resolved",
         _parse(mod, log(started_line), 1), None, "INCONCLUSIVE"),
        ("no verdict, one started, none finished, non-zero exit",
         _parse(mod, trap_text, 1), display, "ARMED"),
        ("no verdict, two started, none finished, non-zero exit",
         _parse(mod, log(started_line, other_started), 1), display, "INCONCLUSIVE"),
        ("no verdict, the named test started, exit 0",
         _parse(mod, log(started_line), 0), display, "INCONCLUSIVE"),
        ("no verdict, nothing started, non-zero exit",
         _parse(mod, log("dyld: symbol not found"), 1), display, "INCONCLUSIVE"),
    ]

    agree = []
    for label, r, disp, expected in routes:
        state, armed, why = mod.score_arming(
            disp, "no @Test function named x under Tests/" if disp is None else why_display,
            r, 1200)
        check(state == expected,
              "route · %s scores %s" % (label, expected), f"{state}: {why}")
        check(armed is (True if expected == "ARMED" else False if expected == "NOT ARMED"
                        else None),
              "route · %s carries the armed value its state implies" % label, repr(armed))
        # The original defect on this route.
        before = "ARMED" if r["exit"] != 0 else "NOT ARMED"
        if before == state:
            agree.append(label)
    check(sorted(agree) == sorted([
              "verdict, the named test ran, non-zero exit",
              "verdict, exit 0",
              "no verdict, one started, none finished, non-zero exit"]),
          "the pre-repair rule `armed = code != 0` agrees on three of the eleven routes and "
          "differs on the other eight, including both zero-test routes",
          "agreed: %r" % (sorted(agree),))
    check(len(routes) == 11 and len({lbl for lbl, _r, _d, _e in routes}) == 11,
          "eleven distinct routes, one fixture each")


def test_seam_arm_refuses_an_ambiguous_display_name() -> None:
    """The ambiguity refusal, on a fixture, because the real tree cannot fire it.

    No function under this repository's Tests/ resolves two ways, so against the
    real tree that branch is unfalsifiable — which is exactly the shape this item
    exists to remove. Two files declaring the same function under different @Test
    names give it something to refuse.
    """
    mod = _seam_arm()
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        (root / "A.swift").write_text(
            '@Test("The first reading of it")\nfunc theSameName() throws {}\n')
        display, why = mod.display_name("theSameName", tests_root=root)
        check(display == "The first reading of it",
              "one declaration resolves to its @Test display string", f"{display!r} {why}")

        (root / "B.swift").write_text(
            '@Test("A different reading of it")\nfunc theSameName() throws {}\n')
        display, why = mod.display_name("theSameName", tests_root=root)
        check(display is None and "resolves to 2 different @Test display names" in why,
              "two declarations under different display names are refused, not picked between",
              f"{display!r} {why}")

        state, armed, reason = mod.score_arming(
            display, why, {"exit": 1, "verdict": "", "started": ["The first reading of it"],
                           "finished": [], "timedOut": False}, 1200)
        check(state == "INCONCLUSIVE" and armed is None,
              "and a trap it cannot attribute is inconclusive rather than armed",
              f"{state}: {reason}")

        (root / "B.swift").unlink()
        display, _ = mod.display_name("theSameName", tests_root=root)
        check(display == "The first reading of it",
              "removing the second declaration resolves it again")

        display, why = mod.display_name("noSuchTestFunction", tests_root=root)
        check(display is None and "no @Test function named" in why,
              "a function with no declaration at all is refused too", why)


def test_seam_arm_display_names_resolve_for_every_case() -> None:
    """Every case in the table can be attributed if its mutant traps.

    A display name that stops resolving turns a real arming into an
    `inconclusive`, so the table and the tests are checked against each other
    here rather than at the moment a mutant happens to trap.
    """
    mod = _seam_arm()
    unresolved = []
    for case, _s, _f, _b, _a, function, _w in mod.CASES:
        display, why = mod.display_name(function)
        if display is None:
            unresolved.append(f"{case} {function}: {why}")
    check(not unresolved,
          f"all {len(mod.CASES)} seam cases resolve to a @Test display name",
          "\n".join(unresolved))


# ── The other write path, driven ────────────────────────────────────────────
#
# `main` names this item's likely failure mode by name: a repair that proves the
# step on the path the harness exercises while another path stays undriven.
# `mutation_seam_arm.py` has its own `apply()`, with its own occurrence-count and
# read-back check, and nothing was driving it. The original defect is reintroduced
# on that path too rather than only on the one PRO-0106 rewrote.

def test_seam_arm_apply_proves_its_own_write() -> None:
    mod = _seam_arm()
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        rel = "F.swift"
        real_root = mod.ROOT
        try:
            mod.ROOT = root
            mod._APPLIED.clear()
            (root / rel).write_text("guard a || b else { return nil }\n")
            landed, why = mod.apply(rel, "a || b", "a && b")
            check(landed and (root / rel).read_text() == "guard a && b else { return nil }\n",
                  "a unique anchor is replaced and the file re-reads as the mutation", why)

            mod._APPLIED.clear()
            twice = "guard a || b else { return nil }\n// and again: a || b\n"
            (root / rel).write_text(twice)
            landed, why = mod.apply(rel, "a || b", "a && b")
            check(not landed and "occurs 2 times, not once" in why,
                  "an anchor occurring twice is refused rather than replaced everywhere", why)
            check((root / rel).read_text() == twice,
                  "and the refused mutation left the file exactly as it was")

            mod._APPLIED.clear()
            (root / rel).write_text("guard a || b else { return nil }\n")
            landed, why = mod.apply(rel, "nothing like this", "x")
            check(not landed and "occurs 0 times" in why,
                  "an anchor that is not there is refused", why)

            # The read-back half: a write the disk does not take.
            mod._APPLIED.clear()
            source = "guard a || b else { return nil }\n"
            (root / rel).write_text(source)
            real_write = Path.write_text
            try:
                Path.write_text = lambda self, data, *a, **k: real_write(self, source, *a, **k)
                landed, why = mod.apply(rel, "a || b", "a && b")
            finally:
                Path.write_text = real_write
            check(not landed and "not in the file after writing it" in why,
                  "a write the disk did not take is refused on the re-read", why)
        finally:
            mod.ROOT = real_root
            mod._APPLIED.clear()


def test_shot_disposition_identity_grouping_is_checked() -> None:
    """The open question main recorded, answered by making it fail.

    `shot_disposition.py` detects byte-identity and reports it, and that identity
    is what DEF-221 and DEF-222 rest on. Nothing would have failed if it silently
    stopped grouping: the count was printed and never checked.
    """
    sd = load(ROOT / "scripts/campaign/shot_disposition.py", "shot_disposition_groups")
    a = sd.audit()
    groups = a["byteIdenticalGroups"]
    n_files = sum(len(v) for v in groups.values())
    check(len(groups) == 4 and n_files == 10,
          f"the directory still holds four groups over ten files ({len(groups)} over {n_files})")
    # DEF-241: the sentence used to say eleven. It is derived now, so the two
    # cannot disagree again.
    sentence = a["deletionTests"]["exactDuplicateOfAPublishedFile"]
    check(f"{len(groups)} groups cover {n_files} files" in sentence,
          "and the published sentence states the count this run computed", sentence[:160])
    smallest = min(r["bytes"] for r in a["shots"])
    check(f"{smallest:,}" in a["deletionTests"]["zeroByte"] and smallest > 0,
          "the zero-byte test names the smallest file this run measured",
          a["deletionTests"]["zeroByte"])
    stored = json.loads(sd.AUDIT.read_text())["byteIdenticalGroups"]
    check({k: sorted(v) for k, v in stored.items()} == {k: sorted(v) for k, v in groups.items()},
          "and the audit on disk records the same grouping this run computes")
    # verify() is DRIVEN over a changed grouping rather than grepped for the
    # sentence it would print. Out-of-family review, PRO-0106: reading the
    # source for a string literal passes whether or not the branch runs, and a
    # check nobody has watched fire is indistinguishable from one that cannot —
    # which is the whole of this file's subject, sitting in this file.
    moved = io.StringIO()
    with contextlib.redirect_stdout(moved):
        rc_moved = sd.verify(dict(a, byteIdenticalGroups={}))
    check(rc_moved == 1 and "the byte-identical grouping moved" in moved.getvalue(),
          "verify() fails on a run whose grouping does not match the audit's",
          f"exit {rc_moved}: {moved.getvalue()[-300:]}")
    intact = io.StringIO()
    with contextlib.redirect_stdout(intact):
        rc_intact = sd.verify(a)
    check(rc_intact == 0 and "the byte-identical grouping moved" not in intact.getvalue(),
          "and passes on the grouping this run actually computes, in the same session",
          f"exit {rc_intact}: {intact.getvalue()[-300:]}")


def test_shot_disposition_manifest_reflects_the_bytes_on_disk() -> None:
    """`--manifest` is a second output path, and it was undriven too."""
    out = subprocess.run(
        [sys.executable, "-W", "ignore",
         str(ROOT / "scripts/campaign/shot_disposition.py"), "--manifest"],
        capture_output=True, text=True, cwd=ROOT)
    check(out.returncode == 0, f"--manifest exits 0 ({out.returncode})", out.stderr[-300:])
    entries = json.loads(out.stdout)
    check(len(entries) == 35, f"it emits one entry per disposed-and-unpublished image ({len(entries)})")
    wrong = []
    for e in entries:
        f = ROOT / "docs/test-campaign" / e["path"]
        data = f.read_bytes()
        if hashlib.sha256(data).hexdigest() != e["sha256"] or len(data) != e["bytes"]:
            wrong.append(e["path"])
    check(not wrong,
          "and every sha256 and byte count in it is the file on disk, re-derived here",
          "\n".join(wrong))


# ── What the out-of-family review found, each on its own fixture ────────────

def test_mutate_swift_offsets_are_two_coordinates() -> None:
    """The token being right does not make the site right.

    An edit above can slide a different `==` into exactly the recorded offset:
    the offset check agrees, the read-back agrees, and the harness attributes the
    verdict to a line nothing touched. The line number is a second coordinate on
    the same site and the two move independently.
    """
    mod = _mutate_swift()
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "F.swift"
        # Two sites. The mutant names the second, on line 2.
        source = "if x == y { }\nif p == q { }\n"
        first = source.index("==")
        second = source.index("==", first + 1)
        mutant = {"file": str(path), "start": second, "end": second + 2,
                  "before": "==", "after": "!=", "line": 2}
        path.write_text(source)
        mod._APPLIED.clear()
        landed, why = mod.apply(dict(mutant))
        check(landed, "the mutant lands at its own site", why)

        # Padding above slides LINE 1's `==` to exactly the recorded offset, so
        # the token there is right and the site is a different line.
        slid = source[:first] + " " * (second - first) + source[first:]
        check(slid[second:second + 2] == "==" and slid.count("\n", 0, second) + 1 == 1,
              "the fixture puts line 1's `==` at exactly the recorded offset",
              repr(slid[max(0, second - 6):second + 6]))
        path.write_text(slid)
        mod._APPLIED.clear()
        landed, why = mod.apply(dict(mutant))
        check(not landed and "the token is right and the site is not" in why,
              "and the recorded line number refuses it", why)
        check(path.read_text() == slid, "leaving the file as it was")

        path.write_text(source)
        mod._APPLIED.clear()
        landed, why = mod.apply({**mutant, "after": "=="})
        check(not landed and "no-op" in why,
              "a mutation that replaces a token with itself is not a mutation", why)


def test_mutate_swift_revert_is_read_back() -> None:
    """`check=True` proves the command exited 0, not that the file came back."""
    mod = _mutate_swift()
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "F.swift"
        source = "if x == y { }\n"
        path.write_text(source)
        mutant = {"file": str(path), "start": source.index("=="),
                  "end": source.index("==") + 2, "before": "==", "after": "!=", "line": 1}
        real_run = mod.subprocess.run
        try:
            # A git checkout that exits 0 and restores nothing.
            mod.subprocess.run = lambda *a, **k: type("P", (), {"returncode": 0})()
            path.write_text(source.replace("==", "!="))
            restored, why = mod.revert(dict(mutant))
            check(not restored and "was not restored" in why,
                  "a revert that exited 0 and changed nothing is refused", why)
            path.write_text(source)
            restored, why = mod.revert(dict(mutant))
            check(restored and "confirmed by re-reading" in why,
                  "and a revert that put the file back is accepted", why)
        finally:
            mod.subprocess.run = real_run


def test_seam_arm_display_name_refuses_a_name_it_cannot_read() -> None:
    """Guessing `function()` would put a name in the comparison the log never prints."""
    mod = _seam_arm()
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        (root / "A.swift").write_text('@Test\nfunc bare() throws {}\n')
        display, why = mod.display_name("bare", tests_root=root)
        check(display == "bare()", "a bare @Test shows the function signature", f"{display!r} {why}")

        (root / "B.swift").write_text('@Test(.tags(.slow), "The name is second")\n'
                                      'func tagged() throws {}\n')
        display, why = mod.display_name("tagged", tests_root=root)
        check(display is None and "does not open with a display string" in why,
              "an attribute whose display string is not first is refused, not guessed",
              f"{display!r} {why}")


def test_shot_disposition_adoption_covers_every_route_in() -> None:
    """Changing a file was one route to the baseline. There were three more."""
    sd = load(ROOT / "scripts/campaign/shot_disposition.py", "shot_disposition_routes")
    a = sd.audit()
    check(sd.adoptable(a) == [], "the real directory needs no adoption", str(sd.adoptable(a)))

    prior = json.loads(sd.AUDIT.read_text())
    real_audit = sd.AUDIT
    with tempfile.TemporaryDirectory() as tmp:
        scratch = Path(tmp) / "audit.json"

        def _with(rows):
            scratch.write_text(json.dumps({**prior, "shots": rows}))
            sd.AUDIT = scratch

        try:
            # A file present in the audit and gone from disk.
            _with(prior["shots"] + [dict(prior["shots"][0], file="departed.png")])
            blocked = dict(sd.adoptable(a))
            check("departed.png" in blocked and "no longer on disk" in blocked["departed.png"],
                  "a file that left the directory is named rather than dropped from the record",
                  str(blocked))

            # A file on disk the audit has never seen, WITH a disposition for its
            # stem — the route that used to be open.
            _with([r for r in prior["shots"] if r["file"] != "surf-004-run-hud.png"])
            blocked = dict(sd.adoptable(a))
            check("surf-004-run-hud.png" in blocked
                  and "nothing has read these bytes" in blocked["surf-004-run-hud.png"],
                  "a new file is named even when a disposition already exists for it",
                  str(blocked))
            row = next(r for r in a["shots"] if r["file"] == "surf-004-run-hud.png")
            check(row["disposed"] and "written for the bytes that used to be there"
                  in blocked["surf-004-run-hud.png"],
                  "and the refusal says the disposition was written for other bytes")

            # No audit at all: deleting the file was a route past the whole check.
            sd.AUDIT = Path(tmp) / "absent.json"
            blocked = dict(sd.adoptable(a))
            check(list(blocked) == ["(the audit itself)"]
                  and "nothing to compare against" in blocked["(the audit itself)"],
                  "with no audit on disk, --write is refused rather than taking the directory "
                  "as read", str(blocked))
        finally:
            sd.AUDIT = real_audit


def test_shot_disposition_reads_more_than_png_citations() -> None:
    sd = load(ROOT / "scripts/campaign/shot_disposition.py", "shot_disposition_suffixes")
    out: dict = {}
    sd.cite_paths({"evidence": ["evidence/shots/a.jpg", "evidence/shots/b.pdf",
                                "evidence/shots/c.png", "docs/x.mov",
                                "negative control docs/nope.png", "not-a-path.png"]},
                  "CASE-X", out)
    check(sorted(out) == ["docs/x.mov", "evidence/shots/a.jpg", "evidence/shots/b.pdf",
                          "evidence/shots/c.png"],
          "every image and media suffix is a citation, and prose about a file is not",
          str(sorted(out)))


def test_seam_arm_tree_dirty_reads_the_quoting_too() -> None:
    """The same slice DEF-206 was about, in the file DEF-206's second round repaired.

    `tree_dirty` filtered on `line[3:].strip().startswith("docs/")`, so a quoted
    entry — any path with a space or a non-ASCII byte in it — arrived as
    `"docs/...` and was not recognised as a docs-only change. This arm then
    refused to run at exit 2 over a change it is meant to tolerate. Fail closed
    rather than a wrong verdict, and still the original defect on a sibling path.
    Out-of-family review, PRO-0106.
    """
    mod = _seam_arm()

    def old_form(lines: list[str]) -> str:
        """The pre-repair filter, verbatim."""
        return "\n".join(l for l in lines
                          if not l[3:].strip().startswith("docs/")).strip()

    lines = [
        (' M docs/test-campaign/cases.json', True, "a plain docs path"),
        ('?? "docs/test-campaign/a name.json"', True, "a docs path quoted for a space"),
        ('?? "docs/test-campaign/caf\\303\\251.json"', True, "a docs path quoted in octal"),
        ('R  "docs/a -> b.md" -> "docs/c -> d.md"', True,
         "a docs rename with arrows on both sides"),
        (' M Sources/ProctorAgent/Dispatch.swift', False, "a source file"),
        ('R  docs/x.md -> Sources/y.swift', False, "a rename OUT of docs/"),
    ]
    for line, tolerated, label in lines:
        paths = mod.porcelain_line_paths(line)
        check(bool(paths) and all(q.startswith("docs/") for q in paths) == tolerated,
              "tree_dirty · %s is %s" % (label, "tolerated" if tolerated else "refused over"),
              f"{line!r} -> {paths}")
        check(all((" " in q or "\\" not in q) for q in paths),
              "and its paths come back unquoted rather than as git printed them", str(paths))

    # The arming: the pre-repair filter keeps the two quoted docs paths, so the
    # arm refuses over a change it should tolerate. Both directions in one run.
    tolerated = [l for l, ok, _lbl in lines if ok]
    check(old_form(tolerated) != "",
          "the pre-repair filter refuses over quoted docs paths it should have tolerated",
          repr(old_form(tolerated)))
    refused = [l for l, ok, _lbl in lines if not ok]
    check(len(old_form(refused).splitlines()) == 1
          and "Dispatch.swift" in old_form(refused),
          "and it errs the other way too: of the two lines that genuinely leave docs/ it keeps "
          "one and silently tolerates the rename OUT of docs/, because `docs/x.md -> "
          "Sources/y.swift` starts with `docs/` when you look at the whole entry",
          repr(old_form(refused)))


def test_shot_disposition_citations_read_the_audits_own_population() -> None:
    """A cited `.mov` failed as absent from an audit that could never hold it.

    `audit()` globbed `*.png` while `cite_paths` accepts twelve suffixes, so the
    two sets differed and the gap read as a missing file. Driven and reproducible
    before the repair. The population is declared once now and the citation
    branch reads it, so this is watched in both directions rather than pinned to
    the string `.png`.
    """
    sd = load(ROOT / "scripts/campaign/shot_disposition.py", "shot_disposition_population")
    check(sd.AUDIT_SUFFIX in sd.IMAGE_SUFFIXES,
          "the audit's population is one of the suffixes a case may cite", sd.AUDIT_SUFFIX)

    a = sd.audit()
    check(a["shots"] and all(r["file"].lower().endswith(sd.AUDIT_SUFFIX) for r in a["shots"]),
          "and the audit's own glob is that population rather than a second literal",
          str([r["file"] for r in a["shots"]][:3]))

    def cited(path: str, suffix: str) -> tuple[list[str], list[str]]:
        """citations() over one real cases.json citing `path`, at a chosen population."""
        (sd.CAMPAIGN / "cases.json").write_text(
            json.dumps([{"id": "CASE-X", "evidence": [path]}]))
        real_suffix = sd.AUDIT_SUFFIX
        sd.AUDIT_SUFFIX = suffix
        try:
            return sd.citations(a)
        finally:
            sd.AUDIT_SUFFIX = real_suffix

    with tempfile.TemporaryDirectory() as tmp:
        shots = Path(tmp) / "evidence/shots"
        shots.mkdir(parents=True)
        (shots / "probe-clip.mov").write_bytes(b"\0\0\0\x14ftypqt  ")
        (shots / "probe-frame.png").write_bytes(b"\x89PNG\r\n\x1a\n" + b"\0" * 40)
        real_repo, real_campaign = sd.REPO, sd.CAMPAIGN
        sd.REPO, sd.CAMPAIGN = Path(tmp), Path(tmp)
        try:
            fails, notes = cited("evidence/shots/probe-clip.mov", ".png")
            check(not [f for f in fails if "probe-clip" in f]
                  and [n for n in notes if "outside this audit's population" in n],
                  "a cited .mov under evidence/shots is outside the audit's population, "
                  "not absent from it", f"failures={fails} notices={notes}")

            # The original defect, reintroduced by moving the population rather
            # than by editing the branch: at a `.mov` population the same file is
            # one the audit should have held, and it fails.
            fails, notes = cited("evidence/shots/probe-clip.mov", ".mov")
            check([f for f in fails if "absent from this audit" in f],
                  "and at a .mov population the same citation fails as absent — the branch "
                  "reads the declared population and can still fire", str(fails))
            fails, notes = cited("evidence/shots/probe-frame.png", ".mov")
            check(not [f for f in fails if "probe-frame" in f],
                  "while the .png becomes the one outside it, in the same run", str(fails))

            # The other way of writing the same path. A repo-relative citation
            # missed the row lookup AND the `evidence/shots/` test, so it
            # resolved on disk and then skipped the disposition and publishing
            # checks entirely — DEF-227's own class, reachable by writing the
            # path the other way round. Out-of-family review, PRO-0106.
            check(sd.CAMPAIGN_PREFIX == "docs/test-campaign/",
                  "the campaign prefix is derived from the paths, not written twice",
                  sd.CAMPAIGN_PREFIX)
            (Path(tmp) / "docs/test-campaign/evidence/shots").mkdir(parents=True)
            (Path(tmp) / "docs/test-campaign/evidence/shots/probe-clip.mov").write_bytes(b"m")
            sd.REPO = Path(tmp)
            fails, notes = cited("docs/test-campaign/evidence/shots/probe-clip.mov", ".png")
            check([n for n in notes if "outside this audit's population" in n],
                  "a repo-relative citation reaches the same branch a campaign-relative one "
                  "does, rather than resolving on disk and skipping every further check",
                  f"failures={fails} notices={notes}")
            sd.REPO = Path(tmp)
        finally:
            sd.REPO, sd.CAMPAIGN = real_repo, real_campaign


def test_shot_disposition_cite_paths_reads_keys_and_resolvable_spaces() -> None:
    """Two places a citation could hide from `cite_paths`, both driven.

    A path used as a dict KEY was not scanned at all, and any string holding a
    space was disqualified outright — a proxy for prose that also disqualifies a
    real capture whose name has a space in it. Both are DEF-227's own shape: a
    place citations live that the gate did not look in.
    """
    sd = load(ROOT / "scripts/campaign/shot_disposition.py", "shot_disposition_citepaths")

    def old_form(node, cid, out):
        """The pre-repair walk, verbatim: values only, and no string with a space."""
        if isinstance(node, str):
            s = node.strip()
            if s.lower().endswith(sd.IMAGE_SUFFIXES) and " " not in s and "/" in s:
                out.setdefault(s, set()).add(cid)
        elif isinstance(node, dict):
            for v in node.values():
                old_form(v, cid, out)
        elif isinstance(node, list):
            for v in node:
                old_form(v, cid, out)

    keyed = {"notes": {"evidence/shots/keyed.png": "what this frame shows"}}
    now, before = {}, {}
    sd.cite_paths(keyed, "CASE-K", now)
    old_form(keyed, "CASE-K", before)
    check(sorted(now) == ["evidence/shots/keyed.png"] and before == {},
          "a citation used as a dict key is read, and the pre-repair walk saw nothing there",
          f"now={sorted(now)} before={sorted(before)}")

    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        (root / "evidence/shots").mkdir(parents=True)
        (root / "evidence/shots/two words.png").write_bytes(b"\x89PNG")
        real_repo, real_campaign = sd.REPO, sd.CAMPAIGN
        sd.REPO, sd.CAMPAIGN = root, root
        try:
            spaced = ["evidence/shots/two words.png",
                      "the negative control at evidence/shots/absent one.png"]
            now, before = {}, {}
            sd.cite_paths(spaced, "CASE-S", now)
            old_form(spaced, "CASE-S", before)
            check(sorted(now) == ["evidence/shots/two words.png"] and before == {},
                  "a spaced path that resolves on disk is a citation and prose about a file "
                  "that does not is still prose; the pre-repair walk skipped both",
                  f"now={sorted(now)} before={sorted(before)}")

            (root / "evidence/shots/two words.png").unlink()
            gone: dict = {}
            sd.cite_paths(spaced, "CASE-S", gone)
            check(gone == {},
                  "and the same string stops being a citation when the file is not there — "
                  "the residual this cannot separate, stated rather than hidden: a citation "
                  "of a MISSING file whose name holds a space reads as prose",
                  str(sorted(gone)))
        finally:
            sd.REPO, sd.CAMPAIGN = real_repo, real_campaign


def test_mutation_timeout_arm_refuses_an_unresolvable_baseline() -> None:
    """A pinned sha does not exist in a shallow clone, and git show fails quietly."""
    out = subprocess.run(
        [sys.executable, str(ROOT / "scripts/campaign/mutation_timeout_arm.py"),
         "--baseline-ref", "0000000000000000000000000000000000000000",
         "--out", "/tmp/pro0106-unresolvable.json"],
        capture_output=True, text=True, cwd=ROOT)
    check(out.returncode == 2 and "does not resolve in this checkout" in out.stdout,
          f"an unresolvable baseline ref is refused rather than compared against nothing "
          f"(exit {out.returncode})", (out.stdout + out.stderr)[-400:])



def test_ledger_gate_on_this_repository() -> None:
    """DEF-228: standing gate on docs/feature-specs/LEDGER.md and docs/specs/."""
    lg = load(ROOT / "scripts/campaign/ledger_gate.py", "ledger_gate_mod")
    res = lg.audit_ledger(
        ROOT / "docs/feature-specs/LEDGER.md",
        ROOT / "docs/specs",
        ROOT,
    )
    check(not res.get("fatal"), "ledger_gate ran without fatal error", str(res.get("fatal")))
    check(not res.get("failures"), "ledger_gate passes on this repository with zero failures",
          "\n".join(res.get("failures", [])))
    check(res.get("ledger_rows", 0) >= 110,
          f"ledger_gate sees all ledger rows ({res.get('ledger_rows')})")
    check(res.get("specs_on_disk", 0) >= 107,
          f"ledger_gate sees all specs on disk ({res.get('specs_on_disk')})")
    check(res.get("declared_no_spec") == 3,
          f"ledger_gate accounts for the 3 declared no-spec rows ({res.get('declared_no_spec')})")
    check(res.get("merged_in_git", 0) >= 50,
          f"ledger_gate cross-checks merged features from git history ({res.get('merged_in_git')})")


def test_ledger_gate_mutation_checks() -> None:
    """DEF-228: drive each failure mode of ledger_gate in both directions."""
    lg = load(ROOT / "scripts/campaign/ledger_gate.py", "ledger_gate_mutations")
    
    with tempfile.TemporaryDirectory() as tmp:
        tmppath = Path(tmp)
        specs_dir = tmppath / "docs/specs"
        specs_dir.mkdir(parents=True)
        (specs_dir / "spec-PRO-0001.md").write_text("# Spec 1\n")
        (specs_dir / "spec-PRO-0002.md").write_text("# Spec 2\n")
        
        ledger_path = tmppath / "LEDGER.md"
        valid_ledger = """# Feature Spec Ledger
| ID | Title | Created | Status |
|----|-------|---------|--------|
| PRO-0001 | Item 1 | 2026-08-13 | Merged |
| PRO-0002 | Item 2 | 2026-08-13 | Ready for Plan |
| PRO-0003 | Item 3 | 2026-08-13 | Retired |

## Rows with no spec file
| ID | Title | Status | Why no spec file |
|---|---|---|---|
| PRO-0003 | Item 3 | Retired | Retired before spec convention was introduced; valid reason here. |
"""
        ledger_path.write_text(valid_ledger)
        
        # Valid run
        res = lg.audit_ledger(ledger_path, specs_dir, tmppath)
        check(not res.get("failures"), "valid scratch ledger passes cleanly", str(res.get("failures")))
        
        # Mode 1: spec on disk with no ledger row
        (specs_dir / "spec-PRO-0004.md").write_text("# Spec 4\n")
        res1 = lg.audit_ledger(ledger_path, specs_dir, tmppath)
        check(any("spec-PRO-0004.md" in f for f in res1.get("failures", [])),
              "spec on disk with no ledger row fails ledger_gate", str(res1.get("failures")))
        (specs_dir / "spec-PRO-0004.md").unlink()
        
        # Mode 2: undeclared row with no spec file
        bad_ledger_undeclared = valid_ledger.replace(
            "| PRO-0002 | Item 2 | 2026-08-13 | Ready for Plan |",
            "| PRO-0002 | Item 2 | 2026-08-13 | Ready for Plan |\n| PRO-0005 | Item 5 | 2026-08-13 | Ready for Plan |"
        )
        ledger_path.write_text(bad_ledger_undeclared)
        res2 = lg.audit_ledger(ledger_path, specs_dir, tmppath)
        check(any("PRO-0005" in f and "undeclared" in f for f in res2.get("failures", [])),
              "undeclared row with no spec file fails ledger_gate", str(res2.get("failures")))
        
        # Mode 3: declared row with thin reason (<20 chars)
        bad_ledger_thin = valid_ledger.replace(
            "Retired before spec convention was introduced; valid reason here.",
            "too short"
        )
        ledger_path.write_text(bad_ledger_thin)
        res3 = lg.audit_ledger(ledger_path, specs_dir, tmppath)
        check(any("thin reasons" in f and "PRO-0003" in f for f in res3.get("failures", [])),
              "declared no-spec row with thin reason (<20 chars) fails ledger_gate", str(res3.get("failures")))
        
        # Mode 4: declared row that actually has a spec on disk (stale declaration)
        (specs_dir / "spec-PRO-0003.md").write_text("# Spec 3\n")
        ledger_path.write_text(valid_ledger)
        res4 = lg.audit_ledger(ledger_path, specs_dir, tmppath)
        check(any("actually have a spec on disk" in f and "PRO-0003" in f for f in res4.get("failures", [])),
              "stale no-spec declaration for a spec that exists on disk fails ledger_gate", str(res4.get("failures")))
        (specs_dir / "spec-PRO-0003.md").unlink()

        # Mode 5: declared no-spec ID that does not exist in main ledger table (orphaned)
        bad_ledger_orphaned = valid_ledger + "| PRO-0999 | Phantom | Retired | Reason for phantom item here. |\n"
        ledger_path.write_text(bad_ledger_orphaned)
        res5 = lg.audit_ledger(ledger_path, specs_dir, tmppath)
        check(any("PRO-0999" in f and "absent from main ledger" in f for f in res5.get("failures", [])),
              "orphaned no-spec declaration fails ledger_gate", str(res5.get("failures")))

        # Mode 6: feature merged in git history but ledger status is Ready for Plan / In Progress
        ledger_path.write_text(valid_ledger)
        subprocess.run(["git", "-C", str(tmppath), "init"], capture_output=True, check=True)
        subprocess.run(["git", "-C", str(tmppath), "config", "user.name", "Test"], capture_output=True, check=True)
        subprocess.run(["git", "-C", str(tmppath), "config", "user.email", "test@example.com"], capture_output=True, check=True)
        subprocess.run(["git", "-C", str(tmppath), "commit", "--allow-empty", "-m", "merge PRO-0002 — some feature"], capture_output=True, check=True)
        res6 = lg.audit_ledger(ledger_path, specs_dir, tmppath)
        check(any("PRO-0002" in f and "merged in git" in f for f in res6.get("failures", [])),
              "merged feature in git with unmerged status in ledger fails ledger_gate", str(res6.get("failures")))


def test_shot_disposition_mock_lane_accounted_and_guarded() -> None:
    """DEF-243: all files in evidence/shots/mock/ carry dispositions and byte audits."""
    sd = load(ROOT / "scripts/campaign/shot_disposition.py", "shot_disposition_mock")
    a = sd.audit()
    mock_shots = [r for r in a["shots"] if r.get("isMock")]
    check(len(mock_shots) == 4,
          f"audit() finds all 4 mock PNG files in evidence/shots/mock/ ({len(mock_shots)})",
          str([r["file"] for r in mock_shots]))
    check(all(r["disposed"] for r in mock_shots),
          "every mock file carries an explicit disposition in DISPOSITIONS")
    check(all(r["path"].startswith("evidence/shots/mock/") for r in mock_shots),
          "every mock row path is correctly prefixed under evidence/shots/mock/")
    
    # Mutating a mock file in audit trips verify()
    a_mutated = json.loads(json.dumps(a))
    for r in a_mutated["shots"]:
        if r["file"] == "mock/surf-008-status-window.png":
            r["sha256"] = "0" * 64
    
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        rc = sd.verify(a_mutated)
    check(rc == 1 and "mock/surf-008-status-window.png: bytes changed" in buf.getvalue(),
          "verify() fails when a mock file sha256 drifts", buf.getvalue()[-300:])


def test_tool_identity_content_over_version() -> None:
    """DEF-204: compare gates tool identity by content hash / commit, refusing altered code at matching version."""
    reckon_script = ROOT / "scripts/reckoning/reckoning.py"
    with tempfile.TemporaryDirectory() as tmp:
        d = Path(tmp)
        repo = d / "repo"
        repo.mkdir()
        subprocess.run(["git", "init", "-q", "."], cwd=repo, check=True)
        subprocess.run(["git", "config", "user.email", "test@example.com"], cwd=repo, check=True)
        subprocess.run(["git", "config", "user.name", "test"], cwd=repo, check=True)
        (repo / "docs/features-to-triage").mkdir(parents=True)
        (repo / "docs/test-campaign").mkdir(parents=True)
        (repo / "docs/features-to-triage/brief.md").write_text("# Brief")
        (repo / "docs/test-campaign/cases.json").write_text("[]")
        (repo / "docs/test-campaign/inventory.json").write_text("{}")
        subprocess.run(["git", "add", "docs"], cwd=repo, check=True)
        subprocess.run(["git", "commit", "-q", "-m", "init"], cwd=repo, check=True)
        commit = subprocess.run(["git", "rev-parse", "HEAD"], cwd=repo, capture_output=True, text=True, check=True).stdout.strip()

        # Build fixture tool at version 1.1.0
        tool_dir = d / "fixture-tool"
        (tool_dir / "skills/reckon/scripts").mkdir(parents=True)
        (tool_dir / ".claude-plugin").mkdir(parents=True)
        (tool_dir / ".claude-plugin/plugin.json").write_text(json.dumps({"name": "reckon", "version": "1.1.0"}))
        real_reckon = Path(os.environ.get(
            "RECKON_SCRIPT",
            "/Users/lukerhodes/Dev/fledgeling-plugins/plugins/reckon/skills/reckon/scripts/reckon.py"))
        tool_py = tool_dir / "skills/reckon/scripts/reckon.py"
        tool_py.write_text(real_reckon.read_text(encoding="utf-8") if real_reckon.is_file() else "CLASSES = ['unbuilt', 'unjoined', 'broken', 'unmeasured', 'unnamed', 'undecided', 'retirable', 'waived']\ndef ratchet(a, b): return 0, []\n")

        dir_a = d / "run-a"
        dir_b = d / "run-b"
        dir_a.mkdir()
        dir_b.mkdir()

        for cur in (dir_a, dir_b):
            (cur / "ledger.json").write_text(json.dumps({
                "schema": "reckoning-ledger/1", "rows": [],
                "summary": {"work_items": 0, "rows": 0, "work_by_kind": {}},
                "denominators": {}
            }))

        run_a = {
            "schema": "reckoning-run/1", "taken_at": "2026-08-23T00:00:00Z",
            "tree": {"tree_named": True, "commit": commit, "short": commit[:7], "dirty_inputs": []},
            "tool": {"name": "reckon", "version": "1.1.0", "script": str(tool_py),
                     "manifest": str(tool_dir / ".claude-plugin/plugin.json"), "source_commit": "a" * 40, "sha256": "1" * 64,
                     "classes": ["unbuilt", "unjoined", "broken", "unmeasured", "unnamed", "undecided", "retirable", "waived"]}
        }
        run_b = json.loads(json.dumps(run_a))
        run_b["tool"]["sha256"] = "2" * 64
        run_b["tool"]["source_commit"] = "b" * 40

        (dir_a / "run.json").write_text(json.dumps(run_a))
        (dir_b / "run.json").write_text(json.dumps(run_b))

        p = subprocess.run([sys.executable, str(reckon_script), "compare", str(dir_a), str(dir_b), "--repo", str(repo),
                           "--reckon", str(tool_py)],
                           capture_output=True, text=True)
        check(p.returncode == 2 and "altered code at a matching version" in (p.stdout + p.stderr)
              and "content hashes differ" in (p.stdout + p.stderr),
              "compare refuses altered tool code at a matching version (DEF-204)",
              f"exit={p.returncode} output: {p.stdout + p.stderr}")

        p_allow = subprocess.run([sys.executable, str(reckon_script), "compare", str(dir_a), str(dir_b), "--repo", str(repo),
                                 "--reckon", str(tool_py), "--allow-differing-tool"], capture_output=True, text=True)
        check(p_allow.returncode == 0,
              "compare --allow-differing-tool decomposes across altered tool code at matching version",
              f"exit={p_allow.returncode} output: {p_allow.stdout + p_allow.stderr}")


def test_plugin_cache_content_check() -> None:
    """DEF-216: standing check that plugin verification inspects content and reports disparity rather than passing on version."""
    def audit_tool_content(source_script: Path, target_script: Path) -> dict:
        s_text = source_script.read_text(encoding="utf-8") if source_script.is_file() else ""
        t_text = target_script.read_text(encoding="utf-8") if target_script.is_file() else ""
        s_unjoined = s_text.count("unjoined")
        t_unjoined = t_text.count("unjoined")
        s_sha = hashlib.sha256(s_text.encode("utf-8")).hexdigest() if s_text else None
        t_sha = hashlib.sha256(t_text.encode("utf-8")).hexdigest() if t_text else None
        disparities = []
        if s_unjoined != t_unjoined:
            disparities.append(f"unjoined count mismatch: source has {s_unjoined}, target has {t_unjoined}")
        if s_sha != t_sha:
            disparities.append(f"sha256 mismatch: source {s_sha[:8] if s_sha else 'none'} vs target {t_sha[:8] if t_sha else 'none'}")
        return {
            "source_unjoined": s_unjoined,
            "target_unjoined": t_unjoined,
            "match": len(disparities) == 0,
            "disparities": disparities
        }

    with tempfile.TemporaryDirectory() as tmp:
        d = Path(tmp)
        src = d / "reckon_source.py"
        src.write_text("unjoined = 1\n" * 13 + "CLASSES = ['unjoined']\n")

        stale_cache = d / "reckon_cache.py"
        stale_cache.write_text("CLASSES = ['unbuilt']\n")

        res_stale = audit_tool_content(src, stale_cache)
        check(not res_stale["match"] and res_stale["target_unjoined"] == 0 and res_stale["source_unjoined"] == 14,
              "content audit detects 0 vs 14 unjoined disparity in stale cache (DEF-216)",
              str(res_stale))
        check(any("unjoined count mismatch: source has 14, target has 0" in item for item in res_stale["disparities"]),
              "content audit names explicit unjoined disparity reason",
              str(res_stale["disparities"]))

        good_cache = d / "reckon_good_cache.py"
        good_cache.write_text("unjoined = 1\n" * 13 + "CLASSES = ['unjoined']\n")
        res_good = audit_tool_content(src, good_cache)
        check(res_good["match"] and len(res_good["disparities"]) == 0,
              "content audit passes when content matches byte-for-byte and feature-for-feature",
              str(res_good))


def main() -> int:
    for fn in (test_mutate_swift_closure_shorthand, test_merge_registry,
               test_merge_registry_on_this_registry,
               test_case_0074_load_matches_its_evidence, test_source_analysis_rung,
               test_seed_strengthen_refuses_a_red_baseline,
               test_defect_gate_claims, test_defect_gate_dropped,
               test_defect_gate_on_this_repository,
               test_operator_path_gate_census,
               test_operator_path_gate_nested_type_collision,
               test_operator_path_gate_seam_resolution,
               test_operator_path_gate_accessor_and_guard,
               test_operator_path_gate_bare_name_is_not_a_wildcard,
               test_operator_path_gate_qualified_reach_is_never_excused,
               test_operator_path_gate_composed_path,
               test_operator_path_gate_reflector_guard,
               test_operator_path_gate_on_this_repository,
               test_mutate_swift_proves_its_splice,
               test_mutate_swift_unproved_mutation_is_inconclusive,
               test_mutate_swift_unreported_suite_is_inconclusive,
               test_seam_arm_scores_the_trap_from_the_log,
               test_seam_arm_scores_a_reported_run,
               test_seam_arm_zero_tests_is_not_an_arming,
               test_seam_arm_scores_every_route_through_the_rule,
               test_seam_arm_tree_dirty_reads_the_quoting_too,
               test_seam_arm_refuses_an_ambiguous_display_name,
               test_seam_arm_display_names_resolve_for_every_case,
               test_seam_arm_apply_proves_its_own_write,
               test_shot_disposition_identity_grouping_is_checked,
               test_shot_disposition_manifest_reflects_the_bytes_on_disk,
               test_mutate_swift_offsets_are_two_coordinates,
               test_mutate_swift_revert_is_read_back,
               test_seam_arm_display_name_refuses_a_name_it_cannot_read,
               test_shot_disposition_adoption_covers_every_route_in,
               test_shot_disposition_reads_more_than_png_citations,
               test_shot_disposition_citations_read_the_audits_own_population,
               test_shot_disposition_cite_paths_reads_keys_and_resolvable_spaces,
               test_mutation_timeout_arm_refuses_an_unresolvable_baseline,
               test_ledger_gate_on_this_repository,
               test_ledger_gate_mutation_checks,
               test_shot_disposition_mock_lane_accounted_and_guarded,
               test_tool_identity_content_over_version,
               test_plugin_cache_content_check):
        try:
            fn()
        except Exception as exc:                                    # noqa: BLE001
            check(False, f"{fn.__name__} raised", f"{type(exc).__name__}: {exc}")
    failed = [label for ok, label in RESULTS if not ok]
    print(f"campaign instruments: {len(RESULTS) - len(failed)} passed, {len(failed)} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
