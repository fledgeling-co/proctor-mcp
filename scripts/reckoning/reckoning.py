#!/usr/bin/env python3
"""PRO-0103: take a reckoning that can be compared against, and compare two.

`reckon` answers "how much is unmeasured now". It cannot answer "is that
falling", because a snapshot has nothing to difference against. This is the
machinery that makes the difference computable and readable, and it exists
because of one failure: a reckoning whose tree is not named cannot be compared
to anything. The first run of this repository's reckoning names its tree only
in a sentence of prose in the report; nothing machine-readable says which
commit produced those numbers, so a second run could difference against it only
by trusting a human to have read the sentence.

Three subcommands:

    take     build a reading, stamped with the commit it was taken on
    compare  difference two readings, holding the reckoning tool constant
    stamp    write provenance for a run that predates this script

The cadence is settled and lives in `docs/reckoning/CADENCE.md`: at wave close,
not on a clock.

## What "holding the tool constant" means, and why it is the centre of this

Between this repository's first and second reckonings the tool itself was
repaired (PRO-0102, `reckon` 1.0.0 -> 1.1.0), and the repair moved the numbers
much further than the project did. Differencing the two published ledgers
directly reports the tool's repair as project progress. So when the two runs
were taken with different tool versions, `compare` rebuilds the earlier run's
own inputs at the earlier run's own commit using the *current* tool, and reports
two movements rather than one:

    tool movement     previous ledger  ->  control ledger   (same tree, new tool)
    project movement  control ledger   ->  current ledger   (same tool, new tree)

That decomposition is only possible because the earlier run named its commit,
which is the whole argument for `run.json`. Where the earlier commit cannot be
resolved in this repository, the delta is refused rather than attributed.

## Fail-closed, in five places

  * a tool below the version floor, or one whose class vocabulary is not the
    current partition, is refused — the installed plugin cache on this machine
    was still 1.0.0 while the shared source read 1.1.0, and 1.0.0 crashes on
    this registry rather than misreporting, which is luck rather than design
  * a reading taken over uncommitted inputs cannot name its tree; `--allow-dirty`
    still refuses to *publish* it as comparable, it marks the run unnamed and
    `compare` then declines it
  * a run with no provenance is not differenced
  * the ratchet must run, on both pairs, or there is no delta
  * a ratchet violation exits 3 after the report is written, so the violation is
    on the page rather than only in a terminal
"""
import argparse
import datetime as _dt
import hashlib
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from collections import Counter
from pathlib import Path

DEFAULT_RECKON = Path(os.environ.get(
    "RECKON_SCRIPT",
    "/Users/lukerhodes/Dev/fledgeling-plugins/plugins/reckon/skills/reckon/scripts/reckon.py"))

# The floor is the version that reads a defect's own status and stops calling an
# unjoined brief unbuilt. Below it the numbers are about the tool.
MIN_TOOL_VERSION = (1, 1, 0)

# The partition as it stands. A tool missing any of these is not the tool this
# repository's ledgers were built by, whatever its plugin manifest declares.
REQUIRED_CLASSES = {"unbuilt", "unjoined", "broken", "unmeasured",
                    "unnamed", "undecided", "retirable", "waived"}

SCHEMA = "reckoning-run/1"

# Down is better for these, up is better for the rest.
LOWER_IS_BETTER = {"unmeasured_rows", "evidence_work", "work_items"}

EXIT_OK, EXIT_USAGE, EXIT_REFUSED, EXIT_RATCHET = 0, 1, 2, 3


# ---------------------------------------------------------------------------
# small helpers
# ---------------------------------------------------------------------------

def run(cmd, cwd=None):
    p = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    return p.returncode, p.stdout, p.stderr


def git(repo, *args):
    code, out, err = run(["git", "-C", str(repo)] + list(args))
    return code, out.strip(), err.strip()


def git_raw(repo, *args):
    """git's output exactly as git wrote it.

    `git()` strips, which is right for a `rev-parse` and wrong for anything
    column-oriented. DEF-206: a porcelain status line's leading space is a status
    column, so ` M docs/x` arriving as `M docs/x` moves every column left by one
    and the slice that drops the two status characters and the space eats the
    first character of the path instead.
    """
    return run(["git", "-C", str(repo)] + list(args))


_C_ESCAPES = {ord("a"): 0x07, ord("b"): 0x08, ord("t"): 0x09, ord("n"): 0x0A,
              ord("v"): 0x0B, ord("f"): 0x0C, ord("r"): 0x0D,
              ord('"'): 0x22, ord("\\"): 0x5C}


def unquote_path(entry):
    """A path as git printed it, back to the path on disk.

    git quotes a path containing a control character, a space, a quote, a
    backslash or a non-ASCII byte. Left quoted, such a path is as unfindable as
    the one DEF-206 chopped a character off.

    UNQUOTED BYTE BY BYTE RATHER THAN THROUGH `unicode_escape`, because the two
    quoting modes need the same answer and the round trip only handled one.
    Under the default `core.quotePath=true` git escapes every non-ASCII byte in
    octal (`"d/caf\\303\\251 latte.txt"`); under `core.quotePath=false`, which
    is a common setting in a user's own gitconfig, it writes the UTF-8 through
    literally (`"d/caf\u00e9 latte.txt"`) and quotes only for the space. The old
    round trip decoded the first and raised `UnicodeDecodeError` on the second,
    whose except branch returned the entry WITH ITS QUOTES ON \u2014 DEF-206's harm
    again, reached by a git config rather than by a filename. Measured against
    git 2.50.1 in both modes. Out-of-family review, PRO-0106.

    A byte sequence that is not UTF-8 is decoded with `surrogateescape`, which is
    what the filesystem calls accept, so an undecodable name is still openable
    rather than mangled into one that is not.
    """
    if not (len(entry) >= 2 and entry[0] == '"' and entry[-1] == '"'):
        return entry
    raw = entry[1:-1].encode("utf-8", "surrogateescape")
    out = bytearray()
    i = 0
    while i < len(raw):
        if raw[i] != 0x5C:
            out.append(raw[i])
            i += 1
            continue
        i += 1
        if i >= len(raw):
            out.append(0x5C)
            break
        if 0x30 <= raw[i] <= 0x37:
            digits = ""
            while i < len(raw) and len(digits) < 3 and 0x30 <= raw[i] <= 0x37:
                digits += chr(raw[i])
                i += 1
            out.append(int(digits, 8) & 0xFF)
            continue
        out.append(_C_ESCAPES.get(raw[i], raw[i]))
        i += 1
    return out.decode("utf-8", "surrogateescape")


def rename_destination(entry):
    """The destination half of a porcelain `R`/`C` entry, read by its quoting.

    DEF-206 again, one level in. A rename entry names both sides on one line
    separated by ` -> `, and NEITHER naive split survives contact with git:

        R  src.png -> "stage-1 -> stage-2.png"      split last  -> `stage-2.png"`
        R  "a -> b.png" -> renamed.png              split first -> `b.png" -> renamed.png`

    Both of those are names nobody can open, and `--allow-dirty` writes whichever
    one it got permanently into `run.json.dirty_inputs`, which is the original
    harm. The separator is findable only by reading the quoting, so that is what
    this does: porcelain v1 quotes a path C-style whenever it holds a space, a
    quote, a backslash or a non-ASCII byte (git's own QUOTE_PATH_QUOTE_SP, driven
    against git 2.50.1 and recorded in the selftest), so an UNQUOTED side cannot
    contain a space and therefore cannot contain the separator. Quoted side: scan
    to the closing quote, honouring backslash escapes, and the separator is what
    follows. Unquoted side: the first ` -> ` is the separator, and there is no
    second candidate for it to be confused with.

    Returns the entry unchanged when it carries no separator, so a status code
    this misreads as a rename cannot silently truncate a plain path.
    """
    if entry.startswith('"'):
        i = 1
        while i < len(entry):
            if entry[i] == "\\":
                i += 2
                continue
            if entry[i] == '"':
                rest = entry[i + 1:]
                return rest[4:] if rest.startswith(" -> ") else entry
            i += 1
        return entry
    head, sep, tail = entry.partition(" -> ")
    return tail if sep else entry


def porcelain_paths(repo, inputs):
    """(exit, paths) — the paths `git status --porcelain` names, parsed not sliced.

    DEF-206. The refusal built on this names files a reader has to be able to
    find, and `--allow-dirty` writes them permanently into `run.json.dirty_inputs`,
    so a mangled name here becomes a permanent record of a path that never
    existed. Three things the old slice got wrong: the leading status space that
    `git()` stripped off the first line, a rename entry that names both sides,
    and a quoted non-ASCII path.
    """
    code, out, _ = git_raw(repo, "status", "--porcelain", "--", *inputs)
    paths = []
    for line in out.splitlines():
        if len(line) < 4:
            continue
        status, entry = line[:2], line[3:]
        # `R  old -> new` / `C  old -> new`. The working tree carries the
        # destination. Gated on the status code, and either column is read: git
        # 2.50.1 reports an unstaged rename as ` D` plus `??` rather than ` R`,
        # so column two is not observed to carry one here, and the guard is wide
        # on purpose rather than on evidence. `rename_destination` returns the
        # entry untouched when there is no separator, so a status code read
        # wrongly costs nothing.
        if "R" in status or "C" in status:
            entry = rename_destination(entry)
        entry = unquote_path(entry)
        if entry:
            paths.append(entry)
    return code, paths


def repo_name(repo):
    """The repository's name, not the worktree's.

    A reading taken in `.worktrees/PRO-0103` is a reading about proctor-mcp, and
    a provenance record that says otherwise sends the next comparison looking
    for a repository that does not exist.
    """
    code, common, _ = git(repo, "rev-parse", "--git-common-dir")
    if code == 0 and common:
        path = Path(common)
        if not path.is_absolute():
            path = Path(repo) / path
        return path.resolve().parent.name
    return Path(repo).resolve().name


def load_json(path):
    with open(path, encoding="utf-8") as fh:
        return json.load(fh)


def refuse(msg):
    print("REFUSED: %s" % msg, file=sys.stderr)
    return EXIT_REFUSED


def parse_version(text):
    m = re.match(r"(\d+)\.(\d+)\.(\d+)", str(text or ""))
    return tuple(int(g) for g in m.groups()) if m else None


def sha256_of(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def sweep(root):
    """A directory witness: every file under root with its size and digest.

    The same shape `DirectoryWitness` uses in the Swift suite, for the same
    reason — a claim that a command wrote something has to name what appeared.
    """
    root = Path(root)
    seen = {}
    if not root.exists():
        return seen
    for p in sorted(root.rglob("*")):
        if p.is_file():
            seen[str(p.relative_to(root))] = {"bytes": p.stat().st_size, "sha256": sha256_of(p)}
    return seen


# ---------------------------------------------------------------------------
# gate 1 + 2: the tool
# ---------------------------------------------------------------------------

def resolve_tool(script):
    """Return the tool's identity, or a reason it cannot be used.

    Two checks, because they fail in different directions. The declared version
    catches an old copy that is honest about being old. The class vocabulary
    catches a copy whose manifest says one thing and whose behaviour is another,
    which is the failure REQ-099 exists over, arriving from the other side.
    """
    script = Path(script)
    if not script.is_file():
        return None, ("no reckon script at %s. Point at one with --reckon, or set RECKON_SCRIPT; "
                      "the default is this machine's checkout of the shared plugin and it is not "
                      "portable." % script)

    manifest = None
    for parent in script.parents:
        cand = parent / ".claude-plugin" / "plugin.json"
        if cand.is_file():
            manifest = cand
            break
    if manifest is None:
        return None, "no .claude-plugin/plugin.json above %s — the tool cannot state its version" % script

    declared = (load_json(manifest) or {}).get("version")
    version = parse_version(declared)
    if version is None:
        return None, "plugin manifest at %s declares no parseable version (%r)" % (manifest, declared)
    if version < MIN_TOOL_VERSION:
        return None, ("reckon %s is below the floor %s — below that the tool misreads this registry, "
                      "and a delta against it measures the tool"
                      % (declared, ".".join(str(n) for n in MIN_TOOL_VERSION)))

    spec = importlib.util.spec_from_file_location("_reckon_probe", script)
    module = importlib.util.module_from_spec(spec)
    try:
        spec.loader.exec_module(module)
    except Exception as exc:                                   # pragma: no cover - defensive
        return None, "reckon at %s does not import: %s" % (script, exc)
    classes = set(getattr(module, "CLASSES", ()) or ())
    missing = REQUIRED_CLASSES - classes
    if missing:
        return None, ("reckon %s at %s does not carry the current partition — missing %s. "
                      "A manifest version is a claim; the class list is the behaviour."
                      % (declared, script, ", ".join(sorted(missing))))
    if not hasattr(module, "ratchet"):
        return None, "reckon %s exposes no ratchet — there is no delta without it" % declared

    code, commit, _ = git(script.parent, "rev-parse", "HEAD")
    return {
        "name": "reckon",
        "version": declared,
        "script": str(script),
        "manifest": str(manifest),
        "source_commit": commit if code == 0 else None,
        "classes": sorted(classes),
    }, None


# ---------------------------------------------------------------------------
# gate 3: the tree
# ---------------------------------------------------------------------------

def resolve_tree(repo, inputs, allow_dirty=False):
    """Name the commit the reading is taken on, or say it cannot be named."""
    code, head, err = git(repo, "rev-parse", "HEAD")
    if code != 0:
        return None, "not a git repository at %s (%s)" % (repo, err)
    _, branch, _ = git(repo, "rev-parse", "--abbrev-ref", "HEAD")
    _, dirty_paths = porcelain_paths(repo, inputs)

    tree = {"repo": repo_name(repo), "commit": head, "short": head[:7],
            "branch": branch, "tree_named": True, "dirty_inputs": dirty_paths}
    if dirty_paths:
        if not allow_dirty:
            return None, ("%d uncommitted change(s) under the reckoning's own inputs (%s). A reading "
                          "taken over an uncommitted tree cannot be named by a commit, and a reading "
                          "that cannot be named cannot be compared to anything. Commit them, or pass "
                          "--allow-dirty to take an unpublishable reading."
                          % (len(dirty_paths), ", ".join(dirty_paths[:4])))
        tree["tree_named"] = False
        tree["commit"] = None
        tree["short"] = "dirty"
    for path in inputs:
        code, last, _ = git(repo, "log", "-1", "--format=%H", "--", path)
        tree.setdefault("inputs", {})[path] = {"last_commit": last if code == 0 else None}
    return tree, None


# ---------------------------------------------------------------------------
# take
# ---------------------------------------------------------------------------

def cmd_take(args):
    repo = Path(args.repo).resolve()
    tool, why = resolve_tool(args.reckon)
    if why:
        return refuse(why)
    tree, why = resolve_tree(repo, [args.briefs, args.campaign], allow_dirty=args.allow_dirty)
    if why:
        return refuse(why)

    stamp = _dt.datetime.now(_dt.timezone.utc)
    name = args.name or "%s-%s" % (stamp.strftime("%Y-%m-%d"),
                                   tree["short"] if tree["tree_named"]
                                   else "dirty-" + stamp.strftime("%H%M%S"))
    out = Path(args.out_root) / name
    if out.exists() and not args.force:
        return refuse("%s already exists — a reading is named by its tree, so re-taking it over the "
                      "same commit would overwrite the record rather than add one. Pass --force to "
                      "replace it." % out)

    before = sweep(out)
    code, stdout, stderr = run([sys.executable, tool["script"], "build",
                                "--briefs", args.briefs, "--campaign", args.campaign,
                                "--out", str(out)], cwd=repo)
    sys.stdout.write(stdout)
    sys.stderr.write(stderr)
    build_exit = code
    after = sweep(out)
    written = sorted(set(after) - set(before))
    # DEF-205. `sweep()` measures bytes and a digest per file and the record used
    # to keep only the names, so the witness could say two files appeared and not
    # what was in them — and a file rewritten between the two sweeps appeared in
    # neither set, which is the case a name-only witness cannot see at all.
    rewritten = sorted(n for n in set(after) & set(before) if after[n] != before[n])
    unchanged = sorted(n for n in set(after) & set(before) if after[n] == before[n])
    # The third kind, and it is the same blindness in the other direction: under
    # --force a re-take runs over a directory that already holds a reading, and a
    # file the build stopped writing leaves no trace in either name set.
    removed = sorted(set(before) - set(after))

    if not (out / "ledger.json").is_file():
        return refuse("reckon wrote no ledger (build exit %d)" % build_exit)
    ledger = load_json(out / "ledger.json")

    check_code, check_out, check_err = run([sys.executable, tool["script"], "check",
                                            str(out / "ledger.json")], cwd=repo)
    sys.stdout.write(check_out)
    sys.stderr.write(check_err)

    counts = Counter(r["class"] for r in ledger["rows"])
    record = {
        "schema": SCHEMA,
        "taken_at": stamp.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "project": ledger.get("project"),
        "tree": tree,
        "tool": tool,
        "inputs": {"briefs": args.briefs, "campaign": args.campaign},
        "gate": {"build_exit": build_exit, "check_exit": check_code},
        "headline": ledger.get("headline"),
        "summary": ledger.get("summary"),
        "denominators": {k: v for k, v in ledger.get("denominators", {}).items()
                         if isinstance(v, dict)},
        "class_counts": dict(counts),
        "effect": {"kind": "filesystem-write", "root": str(out),
                   "files_written": written, "count": len(written),
                   "written": {n: after[n] for n in written},
                   "rewritten": {n: {"before": before[n], "after": after[n]}
                                 for n in rewritten},
                   "rewritten_count": len(rewritten),
                   "removed": {n: before[n] for n in removed},
                   "removed_count": len(removed),
                   "unchanged_count": len(unchanged),
                   "witness": ("every file under the root with its byte count and sha256, "
                               "before and after the build, so the claim that a command wrote "
                               "something names what appeared and what it held")},
        "provenance": "measured",
        "notes": list(args.note or []),
    }
    with open(out / "run.json", "w", encoding="utf-8") as fh:
        json.dump(record, fh, indent=1, ensure_ascii=False)
    print("took %s · commit %s · reckon %s" % (out, tree["short"], tool["version"]))

    if build_exit or check_code:
        print("reckon's own gate did not come back clean (build %d, check %d)"
              % (build_exit, check_code), file=sys.stderr)
        return build_exit or check_code

    if args.no_compare:
        return EXIT_OK
    prev = newest_prior(Path(args.out_root), out)
    if prev is None:
        print("no earlier reading to compare against — this one is the baseline")
        return EXIT_OK
    return compare(prev, out, reckon=tool["script"], repo=repo)


def newest_prior(root, current):
    """The most recent published run before `current`, by its own stamp."""
    runs = []
    for d in sorted(Path(root).iterdir()):
        if not d.is_dir() or d.resolve() == Path(current).resolve():
            continue
        rec = d / "run.json"
        if rec.is_file() and (d / "ledger.json").is_file():
            try:
                runs.append((load_json(rec).get("taken_at") or "", d))
            except ValueError:
                continue
    cur_at = ""
    if (Path(current) / "run.json").is_file():
        cur_at = load_json(Path(current) / "run.json").get("taken_at") or ""
    earlier = [d for at, d in sorted(runs) if not cur_at or at < cur_at]
    return earlier[-1] if earlier else None


# ---------------------------------------------------------------------------
# compare
# ---------------------------------------------------------------------------

def axis_rows(prev_den, ctrl_den, cur_den):
    """Per-axis movement, each with its own denominator. Never blended."""
    labels = [("cases_adjudicated", "Cases adjudicated"),
              ("decisions_taken", "Cases ruled out by decision"),
              ("requirements_observed", "Requirements observed"),
              ("surfaces_spoken_for", "Surfaces spoken for"),
              ("briefs_joined", "Briefs joined to evidence")]
    rows = []
    for key, label in labels:
        p, c, n = prev_den.get(key, {}), ctrl_den.get(key, {}), cur_den.get(key, {})
        if not n:
            continue
        moved_of = c.get("of") != n.get("of")
        direction = classify_move((c.get("n"), c.get("of"), c.get("pct")),
                                  (n.get("n"), n.get("of"), n.get("pct")))
        rows.append({"key": key, "label": label,
                     "prev": p, "control": c, "current": n,
                     "denominator_moved": moved_of, "direction": direction})
    return rows


def classify_move(control, current, lower_is_better=False):
    """Direction on one axis, decided by the share where there is one.

    Where both sides carry a percentage, the share decides and the raw count
    does not: 22/22 becoming 23/23 is a wider denominator fully covered, not
    coverage improving, and calling it `better` would let the campaign grow its
    way to an improvement it never measured. The count decides only where the
    axis has no denominator at all, which is where `unmeasured` rows live.
    """
    (cn, cof, cpct), (nn, nof, npct) = control, current
    if cn is None or nn is None:
        return "unknown"
    if cpct is not None and npct is not None:
        if abs(npct - cpct) < 0.05:
            return "flat"
        better = npct < cpct if lower_is_better else npct > cpct
        return "improved" if better else "worsened"
    if nn != cn:
        better = nn < cn if lower_is_better else nn > cn
        return "improved" if better else "worsened"
    return "flat"


def build_control(repo, prev_run, reckon, workdir):
    """The previous run's own inputs, at its own commit, through today's tool.

    This is the reading the previous run *would* have published if it had been
    taken with the tool in use now. Differencing against it is the only way to
    say what the project did rather than what the tool learned.
    """
    commit = (prev_run.get("tree") or {}).get("commit")
    if not commit:
        return None, "the earlier run does not name a commit, so its tree cannot be rebuilt"
    code, _, err = git(repo, "cat-file", "-e", commit + "^{commit}")
    if code != 0:
        return None, ("the earlier run names commit %s, which this repository cannot resolve (%s) — "
                      "the tool cannot be held constant, and a delta across two tool versions would "
                      "report the tool's repair as the project's progress" % (commit[:7], err))
    inputs = prev_run.get("inputs") or {}
    paths = [inputs.get("briefs", "docs/features-to-triage"),
             inputs.get("campaign", "docs/test-campaign")]
    tree_dir = Path(workdir) / "tree"
    tree_dir.mkdir(parents=True, exist_ok=True)
    archive = subprocess.run(["git", "-C", str(repo), "archive", commit] + paths,
                             capture_output=True)
    if archive.returncode != 0:
        return None, "git archive of %s failed: %s" % (commit[:7], archive.stderr.decode()[:200])
    untar = subprocess.run(["tar", "-x", "-C", str(tree_dir)], input=archive.stdout,
                           capture_output=True)
    if untar.returncode != 0:
        return None, "could not unpack %s: %s" % (commit[:7], untar.stderr.decode()[:200])
    out = Path(workdir) / "control"
    code, _, err = run([sys.executable, reckon, "build", "--briefs", paths[0],
                        "--campaign", paths[1], "--out", str(out)], cwd=tree_dir)
    if not (out / "ledger.json").is_file():
        return None, "the control build produced no ledger (exit %d): %s" % (code, err[-200:])
    return load_json(out / "ledger.json"), None


def ratchet_pair(reckon, previous, current, repo):
    code, out, err = run([sys.executable, reckon, "ratchet", str(previous), str(current)], cwd=repo)
    lines = [l for l in err.splitlines() if l.startswith("RATCHET")]
    return code, lines


def compare(prev_dir, cur_dir, reckon=None, repo=None, out_name="delta"):
    prev_dir, cur_dir = Path(prev_dir), Path(cur_dir)
    repo = Path(repo or ".").resolve()

    for d in (prev_dir, cur_dir):
        if not (d / "run.json").is_file():
            return refuse("%s carries no run.json. A reading with no provenance names neither its "
                          "tree nor its tool, and differencing it would attribute movement to "
                          "whichever of the two happens to be the reader's assumption." % d)
    prev_run, cur_run = load_json(prev_dir / "run.json"), load_json(cur_dir / "run.json")
    for d, rec in ((prev_dir, prev_run), (cur_dir, cur_run)):
        if not (rec.get("tree") or {}).get("tree_named"):
            return refuse("%s was taken over an unnamed tree — it is a reading, not a baseline" % d)

    tool, why = resolve_tool(reckon or DEFAULT_RECKON)
    if why:
        return refuse(why)
    reckon = tool["script"]

    prev_ledger = load_json(prev_dir / "ledger.json")
    cur_ledger = load_json(cur_dir / "ledger.json")

    prev_ver = (prev_run.get("tool") or {}).get("version")
    cur_ver = (cur_run.get("tool") or {}).get("version")
    if cur_ver != tool["version"]:
        return refuse("the current reading was taken with reckon %s and this comparison would build "
                      "its control with reckon %s. A control built by a third tool belongs to "
                      "neither side, and the delta would carry the difference between those two as "
                      "project movement. Re-take the reading, or compare with the tool that took it."
                      % (cur_ver, tool["version"]))
    same_tool = parse_version(prev_ver) == parse_version(cur_ver) and prev_ver == cur_ver

    workdir = tempfile.mkdtemp(prefix="reckoning-control-")
    try:
        if same_tool:
            control, attribution, why = prev_ledger, "direct", None
        else:
            control, why = build_control(repo, prev_run, reckon, workdir)
            attribution = "decomposed"
        if why:
            return refuse(why)

        ratchets = []
        code_a, lines_a = ratchet_pair(reckon, prev_dir / "ledger.json", cur_dir / "ledger.json", repo)
        ratchets.append({"pair": "published", "from": prev_run["tree"]["short"],
                         "to": cur_run["tree"]["short"], "exit": code_a, "violations": lines_a})
        if attribution == "decomposed":
            ctrl_path = Path(workdir) / "control" / "ledger.json"
            code_b, lines_b = ratchet_pair(reckon, ctrl_path, cur_dir / "ledger.json", repo)
            ratchets.append({"pair": "tool-constant", "from": prev_run["tree"]["short"] + " (rebuilt)",
                             "to": cur_run["tree"]["short"], "exit": code_b, "violations": lines_b})

        delta = assemble(prev_run, cur_run, prev_ledger, control, cur_ledger,
                         attribution, ratchets)
        with open(cur_dir / (out_name + ".json"), "w", encoding="utf-8") as fh:
            json.dump(delta, fh, indent=1, ensure_ascii=False)
        with open(cur_dir / (out_name + ".md"), "w", encoding="utf-8") as fh:
            fh.write(render_delta(delta))
        print("wrote %s" % (cur_dir / (out_name + ".md")))
        print(delta["verdict"])
        for r in ratchets:
            print("ratchet %s: %s" % (r["pair"], "clean" if r["exit"] == 0
                                      else "%d silent transition(s)" % len(r["violations"])))
        if any(r["exit"] != 0 for r in ratchets):
            for r in ratchets:
                for line in r["violations"]:
                    print(line, file=sys.stderr)
            return EXIT_RATCHET
        return EXIT_OK
    finally:
        shutil.rmtree(workdir, ignore_errors=True)


def work_split(ledger):
    s = ledger.get("summary") or {}
    kinds = s.get("work_by_kind") or {}
    return {"work_items": s.get("work_items"),
            "product": kinds.get("product-work", 0),
            "evidence": kinds.get("evidence-work", 0),
            "decision": kinds.get("decision-work", 0),
            "rows": s.get("rows")}


def assemble(prev_run, cur_run, prev_ledger, control, cur_ledger, attribution, ratchets):
    prev_w, ctrl_w, cur_w = (work_split(x) for x in (prev_ledger, control, cur_ledger))
    prev_c = Counter(r["class"] for r in prev_ledger["rows"])
    ctrl_c = Counter(r["class"] for r in control["rows"])
    cur_c = Counter(r["class"] for r in cur_ledger["rows"])

    ctrl_rows = {r["id"]: r for r in control["rows"]}
    cur_rows = {r["id"]: r for r in cur_ledger["rows"]}
    moved = [{"id": rid, "entity": cur_rows[rid]["entity"], "from": ctrl_rows[rid]["class"],
              "to": cur_rows[rid]["class"], "title": (cur_rows[rid].get("title") or "")[:110],
              "why": (cur_rows[rid].get("why") or "")[:160]}
             for rid in sorted(set(ctrl_rows) & set(cur_rows))
             if ctrl_rows[rid]["class"] != cur_rows[rid]["class"]]
    appeared = [{"id": rid, "entity": cur_rows[rid]["entity"], "class": cur_rows[rid]["class"],
                 "title": (cur_rows[rid].get("title") or "")[:110]}
                for rid in sorted(set(cur_rows) - set(ctrl_rows))]
    vanished = [{"id": rid, "entity": ctrl_rows[rid]["entity"], "class": ctrl_rows[rid]["class"],
                 "title": (ctrl_rows[rid].get("title") or "")[:110]}
                for rid in sorted(set(ctrl_rows) - set(cur_rows))]

    axes = axis_rows(prev_ledger.get("denominators", {}), control.get("denominators", {}),
                     cur_ledger.get("denominators", {}))
    unmeasured = {
        "control_rows": ctrl_c.get("unmeasured", 0),
        "current_rows": cur_c.get("unmeasured", 0),
        "left": [m for m in moved if m["from"] == "unmeasured"],
        "entered": [m for m in moved if m["to"] == "unmeasured"],
        "direction": classify_move((ctrl_c.get("unmeasured", 0), None, None),
                                   (cur_c.get("unmeasured", 0), None, None),
                                   lower_is_better=True),
    }
    evidence_dir = classify_move((ctrl_w["evidence"], None, None), (cur_w["evidence"], None, None),
                                 lower_is_better=True)

    improved = [a["label"] for a in axes if a["direction"] == "improved"]
    worsened = [a["label"] for a in axes if a["direction"] == "worsened"]
    flat = [a["label"] for a in axes if a["direction"] == "flat"]
    verdict = ("%d of %d axes improved, %d flat, %d worsened; evidence work %s at %s and the "
               "unmeasured class %s at %d rows."
               % (len(improved), len(axes), len(flat), len(worsened),
                  {"flat": "flat", "improved": "down", "worsened": "up", "unknown": "unknown"}[evidence_dir],
                  cur_w["evidence"],
                  {"flat": "flat", "improved": "smaller", "worsened": "larger", "unknown": "unknown"}[unmeasured["direction"]],
                  unmeasured["current_rows"]))

    return {
        "schema": "reckoning-delta/1",
        "project": cur_run.get("project"),
        "attribution": attribution,
        "previous": {"dir_stamp": prev_run.get("taken_at"), "commit": prev_run["tree"]["commit"],
                     "short": prev_run["tree"]["short"], "tool": (prev_run.get("tool") or {}).get("version"),
                     "provenance": prev_run.get("provenance"), "notes": prev_run.get("notes") or []},
        "current": {"dir_stamp": cur_run.get("taken_at"), "commit": cur_run["tree"]["commit"],
                    "short": cur_run["tree"]["short"], "tool": (cur_run.get("tool") or {}).get("version"),
                    "provenance": cur_run.get("provenance"), "notes": cur_run.get("notes") or []},
        "verdict": verdict,
        "movement": {
            "tool": {k: (None if prev_w[k] is None or ctrl_w[k] is None else ctrl_w[k] - prev_w[k])
                     for k in prev_w},
            "project": {k: (None if ctrl_w[k] is None or cur_w[k] is None else cur_w[k] - ctrl_w[k])
                        for k in cur_w},
            "net": {k: (None if prev_w[k] is None or cur_w[k] is None else cur_w[k] - prev_w[k])
                    for k in cur_w},
            "previous": prev_w, "control": ctrl_w, "current": cur_w,
        },
        "classes": {"previous": dict(prev_c), "control": dict(ctrl_c), "current": dict(cur_c)},
        "axes": axes,
        "unmeasured": unmeasured,
        "rows": {"moved": moved, "appeared": appeared, "vanished": vanished},
        "ratchets": ratchets,
    }


ARROW = {"improved": "better", "worsened": "worse", "flat": "flat", "unknown": "?"}


def render_delta(d):
    """Movement first, totals last — the report answers "what changed" before
    it answers "how much is there", because the second question is the one the
    single-run report already answers."""
    p, c = d["previous"], d["current"]
    L = []
    A = L.append
    A("# Reckoning delta — %s" % (d.get("project") or "project"))
    A("")
    A("`%s` (reckon %s) → `%s` (reckon %s), attribution **%s**."
      % (p["short"], p["tool"], c["short"], c["tool"], d["attribution"]))
    A("")
    A("## What moved")
    A("")
    A("**%s**" % d["verdict"])
    A("")
    A("| Axis | Was (same tool) | Now | Move | Reading |")
    A("|---|---|---|---|---|")
    for a in d["axes"]:
        ctrl, cur = a["control"], a["current"]
        def cell(v):
            return "%s/%s (%s)" % (v.get("n"), v.get("of"),
                                   "—" if v.get("pct") is None else "%.1f%%" % v["pct"])
        move = "—"
        if ctrl.get("pct") is not None and cur.get("pct") is not None:
            move = "%+.1f pts" % (cur["pct"] - ctrl["pct"])
        note = ARROW[a["direction"]]
        if a["denominator_moved"]:
            note += "; denominator moved %s → %s" % (ctrl.get("of"), cur.get("of"))
        A("| %s | %s | %s | %s | %s |" % (a["label"], cell(ctrl), cell(cur), move, note))
    A("")
    u = d["unmeasured"]
    published_um = d["classes"]["previous"].get("unmeasured", 0)
    A("**The class this exists for.** `unmeasured` went %d → %d rows under a constant tool (%s). "
      "%d row(s) left it, %d entered. The published baseline recorded %d; the difference between "
      "that and the control column is the tool, not the project. The ratchet below is what says the "
      "rows that left were measured rather than reclassified."
      % (u["control_rows"], u["current_rows"], ARROW[u["direction"]], len(u["left"]),
         len(u["entered"]), published_um))
    A("")

    A("## Where the movement came from")
    A("")
    if d["attribution"] == "decomposed":
        A("The two readings were taken with different versions of the reckoning tool, so the "
          "published ledgers are not directly comparable: part of any difference is the tool "
          "learning to read this registry. The earlier run's own inputs were rebuilt at its own "
          "commit (`%s`) with the current tool, and that control is what the current reading is "
          "differenced against. **Only the project column is progress.**" % p["short"])
    else:
        A("Both readings were taken with reckon %s, so the difference is the project's alone and "
          "no control was needed." % c["tool"])
    A("")
    m = d["movement"]
    A("| Count | Previous (as published) | Control (same tree, current tool) | Current | Tool moved | Project moved |")
    A("|---|---:|---:|---:|---:|---:|")
    for key, label in (("work_items", "Work items"), ("product", "· product"),
                       ("evidence", "· evidence"), ("decision", "· decision"),
                       ("rows", "Ledger rows")):
        A("| %s | %s | %s | %s | %s | %s |"
          % (label, m["previous"][key], m["control"][key], m["current"][key],
             signed(m["tool"][key]), signed(m["project"][key])))
    A("")

    A("## The ratchet")
    A("")
    A("An item may leave `unmeasured` only by being measured. This is the check the second run "
      "exists to turn on: a snapshot gate catches a bad run, and this catches the slow version, "
      "where a row is quietly reclassified across runs until nothing remembers it was never checked.")
    A("")
    A("| Pair | From | To | Exit | Verdict |")
    A("|---|---|---|---:|---|")
    for r in d["ratchets"]:
        A("| %s | %s | %s | %d | %s |"
          % (r["pair"], r["from"], r["to"], r["exit"],
             "clean" if r["exit"] == 0 else "%d silent transition(s)" % len(r["violations"])))
    for r in d["ratchets"]:
        for line in r["violations"]:
            A("")
            A("> %s" % line)
    A("")

    rows = d["rows"]
    A("## Rows that changed class (%d), appeared (%d), vanished (%d)"
      % (len(rows["moved"]), len(rows["appeared"]), len(rows["vanished"])))
    A("")
    A("Tool held constant, so each of these is the project moving.")
    A("")
    if rows["moved"]:
        A("| Row | Was | Now | What |")
        A("|---|---|---|---|")
        for r in rows["moved"][:40]:
            A("| `%s` | `%s` | `%s` | %s |" % (r["id"], r["from"], r["to"], r["title"].replace("|", "／")))
        if len(rows["moved"]) > 40:
            A("")
            A("_…and %d more in delta.json_" % (len(rows["moved"]) - 40))
        A("")
    if rows["appeared"]:
        by_class = Counter(r["class"] for r in rows["appeared"])
        A("**New rows (%d):** %s." % (len(rows["appeared"]),
                                      ", ".join("%d `%s`" % (n, cls)
                                                for cls, n in sorted(by_class.items()))))
        work = [r for r in rows["appeared"] if r["class"] != "verified-done"]
        if work:
            A("")
            A("New rows that are not already done — the ones a reader schedules: %s%s"
              % (", ".join("`%s` (`%s`)" % (r["id"], r["class"]) for r in work[:30]),
                 "" if len(work) <= 30 else ", …and %d more in delta.json" % (len(work) - 30)))
        A("")
    if rows["vanished"]:
        A("**Rows no longer present (%d):** %s — every one of these is an id the registry stopped "
          "carrying, which the ratchet reads as a disappearance rather than a completion."
          % (len(rows["vanished"]), ", ".join("`%s`" % r["id"] for r in rows["vanished"][:60])))
        A("")

    notes = [("previous", n) for n in p.get("notes") or []]
    notes += [("current", n) for n in c.get("notes") or []]
    if notes:
        A("## What each side of this comparison carries")
        A("")
        for side, n in notes:
            A("- *%s* — %s" % (side, n))
        A("")

    A("## Totals, last")
    A("")
    A("Read these second. A total says how much there is; the tables above say whether it is "
      "moving, and only the second question needs two runs.")
    A("")
    A("| Class | Previous | Control | Current |")
    A("|---|---:|---:|---:|")
    for cls in sorted(set(d["classes"]["previous"]) | set(d["classes"]["control"])
                      | set(d["classes"]["current"])):
        A("| `%s` | %s | %s | %s |" % (cls, d["classes"]["previous"].get(cls, 0),
                                       d["classes"]["control"].get(cls, 0),
                                       d["classes"]["current"].get(cls, 0)))
    A("")
    return "\n".join(L) + "\n"


def signed(v):
    if v is None:
        return "—"
    return "%+d" % v if v else "0"


# ---------------------------------------------------------------------------
# stamp
# ---------------------------------------------------------------------------

def cmd_stamp(args):
    """Write provenance for a run taken before this script existed.

    Transcribed rather than measured, and it says so in the record: the first
    reckoning is not re-run to make a tidier baseline, because a baseline edited
    to suit is not a baseline.
    """
    d = Path(args.dir)
    if not (d / "ledger.json").is_file():
        return refuse("no ledger at %s" % d)
    if (d / "run.json").is_file() and not args.force:
        return refuse("%s already carries provenance" % d)
    repo = Path(args.repo).resolve()
    code, full, _ = git(repo, "rev-parse", args.commit + "^{commit}")
    if code != 0:
        return refuse("this repository cannot resolve %s, so the reading cannot be tied to a tree"
                      % args.commit)
    ledger = load_json(d / "ledger.json")
    counts = Counter(r["class"] for r in ledger["rows"])
    record = {
        "schema": SCHEMA,
        "taken_at": args.taken_at,
        "project": ledger.get("project"),
        "tree": {"repo": repo_name(repo), "commit": full, "short": full[:7], "branch": args.branch,
                 "tree_named": True, "dirty_inputs": []},
        "tool": {"name": "reckon", "version": args.tool_version, "script": args.tool_script,
                 "manifest": None, "source_commit": args.tool_commit, "classes": None},
        "inputs": {"briefs": args.briefs, "campaign": args.campaign},
        "gate": {"build_exit": None, "check_exit": None},
        "headline": ledger.get("headline"),
        "summary": ledger.get("summary"),
        "denominators": {k: v for k, v in ledger.get("denominators", {}).items()
                         if isinstance(v, dict)},
        "class_counts": dict(counts),
        "provenance": "transcribed",
        "notes": list(args.note or []),
    }
    with open(d / "run.json", "w", encoding="utf-8") as fh:
        json.dump(record, fh, indent=1, ensure_ascii=False)
    print("stamped %s · commit %s · reckon %s (transcribed)" % (d, full[:7], args.tool_version))
    return EXIT_OK


def cmd_compare(args):
    return compare(args.previous, args.current, reckon=args.reckon, repo=args.repo,
                   out_name=args.out_name)


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)

    t = sub.add_parser("take", help="build a reading stamped with the commit it was taken on")
    t.add_argument("--repo", default=".")
    t.add_argument("--briefs", default="docs/features-to-triage")
    t.add_argument("--campaign", default="docs/test-campaign")
    t.add_argument("--out-root", default="docs/reckoning")
    t.add_argument("--reckon", default=str(DEFAULT_RECKON))
    t.add_argument("--name", help="override the run directory name")
    t.add_argument("--note", action="append", help="a caveat this reading carries into every delta")
    t.add_argument("--allow-dirty", action="store_true",
                   help="take a reading over uncommitted inputs; it is marked unnamed and compare will decline it")
    t.add_argument("--force", action="store_true")
    t.add_argument("--no-compare", action="store_true")
    t.set_defaults(fn=cmd_take)

    c = sub.add_parser("compare", help="difference two readings, holding the tool constant")
    c.add_argument("previous")
    c.add_argument("current")
    c.add_argument("--repo", default=".")
    c.add_argument("--reckon", default=str(DEFAULT_RECKON))
    c.add_argument("--out-name", default="delta")
    c.set_defaults(fn=cmd_compare)

    s = sub.add_parser("stamp", help="write provenance for a run taken before this script existed")
    s.add_argument("dir")
    s.add_argument("--repo", default=".")
    s.add_argument("--commit", required=True)
    s.add_argument("--taken-at", required=True)
    s.add_argument("--tool-version", required=True)
    s.add_argument("--tool-script", default=None)
    s.add_argument("--tool-commit", default=None)
    s.add_argument("--branch", default=None)
    s.add_argument("--briefs", default="docs/features-to-triage")
    s.add_argument("--campaign", default="docs/test-campaign")
    s.add_argument("--note", action="append")
    s.add_argument("--force", action="store_true")
    s.set_defaults(fn=cmd_stamp)

    args = p.parse_args(argv)
    return args.fn(args)


if __name__ == "__main__":
    sys.exit(main())
