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

import hashlib
import importlib.util
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
               test_operator_path_gate_on_this_repository):
        try:
            fn()
        except Exception as exc:                                    # noqa: BLE001
            check(False, f"{fn.__name__} raised", f"{type(exc).__name__}: {exc}")
    failed = [label for ok, label in RESULTS if not ok]
    print(f"campaign instruments: {len(RESULTS) - len(failed)} passed, {len(failed)} failed")
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
