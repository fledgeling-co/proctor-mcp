#!/usr/bin/env python3
"""PRO-0101 CASE-0430..0439: every spec says which brief it came from, and the citation resolves.

    python3 scripts/campaign/spec_citation_measure.py
      [--specs DIR] [--briefs DIR] [--register FILE] [--triage DIR] [--reckon FILE] [--repo DIR]

The overrides exist so `spec_citation_arm.py` can mutate a *scratch copy* of the
specs, the brief queue, the register and the shared skill. Arming a check by
breaking the live shared skill leaves every project on this machine reading the
broken version if the run is interrupted, which is how a `## `proctor_guest``
heading once spent an hour reading `## `proctor_ARMING``.

`--repo` stays the real repository even when the documents are scratch copies,
because a commit-form citation is a claim about git history and a scratch
directory has none.

## The citation grammar

A spec's citation of record is a `**Brief:**` line in its first 20 lines, in one
of three forms:

    **Brief:** `docs/features-to-triage/92-a-spec-says-which-brief-it-came-from.md`
    **Brief:** `docs/features-to-triage/92-….md` @ `3fb7681`
    **Brief:** none. The three findings on `campaign.py check` are the specification.

The first must resolve in the working tree. The second is for a brief that was
deliberately consumed: the path need not exist now, and the named commit must
still hold it, so the reference is recoverable rather than dangling. The third
records an origin that was never a brief, and has to name what it was.

Specs written before the convention cite their brief in prose instead. That is
accepted as a legacy citation, and it is why `presence` and `resolution` are
separate checks rather than one: the four wave-16 specs cited paths that
`400808d` had deleted, so a presence-only check would have passed 75 citations
of which four resolved for nobody.

## Two things this deliberately does not require

**Uniqueness applies to the header form only.** `00-WAVE-7-DIRECTION.md` is
mentioned in the body of eleven specs because it is the direction document all
eleven were cut from. A body mention is prose; the header is the one-per-spec
citation, and only that is required to be unique.

**The number is never a fallback.** `35-scroll-moves-by-what-was-asked.md` is
PRO-0034's brief and its own retirement banner says so; the number would guess
PRO-0035, "The browser catalogue stops guessing", a different feature. The last
check executes the shared join's own filename reader to prove it still refuses
to turn a listing position into a citation.
"""
import importlib.util
import os
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SPECS = REPO / "docs/specs"
BRIEFS = REPO / "docs/features-to-triage"
REGISTER = REPO / "docs/feature-specs/UNCLAIMED-BRIEFS.md"
TRIAGE = Path("/Users/lukerhodes/Dev/fledgeling-plugins/plugins/shipyard/skills/triage")
RECKON = Path("/Users/lukerhodes/Dev/fledgeling-plugins/plugins/reckon/skills/reckon/scripts/reckon.py")

HEADER_LINES = 20
MIN_REASON = 20

argv = sys.argv[1:]
while argv:
    flag = argv.pop(0)
    if flag == "--specs":
        SPECS = Path(argv.pop(0))
    elif flag == "--briefs":
        BRIEFS = Path(argv.pop(0))
    elif flag == "--register":
        REGISTER = Path(argv.pop(0))
    elif flag == "--triage":
        TRIAGE = Path(argv.pop(0))
    elif flag == "--reckon":
        RECKON = Path(argv.pop(0))
    elif flag == "--repo":
        REPO = Path(argv.pop(0))
    else:
        sys.exit(f"unknown argument: {flag}")

BRIEF_PATH = r"docs/features-to-triage/[A-Za-z0-9._+-]+\.md"
# The header, anchored to the start of a line so a sentence mentioning `**Brief:**`
# in the body cannot satisfy a claim about the citation of record.
HEADER_RE = re.compile(r"^\*\*Brief:\*\*[ \t]*(.+?)[ \t]*$", re.M)
# The value must *open* with the backticked path, so a spec mentioning a brief in
# a sentence cannot pass as a citation; trailing annotation is allowed because
# ten of the citations that already join carry one (`· **PRD:** §15`,
# `(Wave 13, brief 6 of 6)`), and rewriting them would be a new form needing a
# new reader.
PATH_FORM = re.compile(rf"\A`({BRIEF_PATH})`(?:\s*@\s*`([0-9a-f]{{7,40}})`)?(?:\s|\Z)")
NONE_FORM = re.compile(r"\Anone[.:]\s*(.+)\Z", re.S | re.I)
BODY_PATH = re.compile(BRIEF_PATH)


def git(*args):
    return subprocess.run(("git", "-C", str(REPO)) + args,
                          capture_output=True, text=True)


def read(path):
    return path.read_text(encoding="utf-8")


def classify(text):
    """(kind, path, sha, reason) for one spec.

    kind is `path`, `commit`, `none`, `legacy` or `uncited`. A malformed header
    is `malformed` rather than silently falling through to the body, because a
    citation nobody can parse is the failure this check exists to catch.
    """
    head = "".join(text.splitlines(keepends=True)[:HEADER_LINES])
    m = HEADER_RE.search(head)
    if m:
        value = m.group(1).strip()
        p = PATH_FORM.match(value)
        if p:
            return ("commit" if p.group(2) else "path"), p.group(1), p.group(2), None
        n = NONE_FORM.match(value)
        if n:
            return "none", None, None, " ".join(n.group(1).split())
        return "malformed", None, None, value
    body = BODY_PATH.search(text)
    if body:
        return "legacy", body.group(0), None, None
    return "uncited", None, None, None


specs = {p.name: classify(read(p)) for p in sorted(SPECS.glob("spec-*.md"))}
briefs = sorted(p.name for p in BRIEFS.glob("*.md"))


def register_rows():
    """(brief filename, reason) for every row of the unclaimed-brief register.

    A row without a reason is not a row: the register exists so that a brief no
    spec claims is a recorded decision rather than an absence, and an empty
    reason is exactly the absence it replaces.
    """
    if not REGISTER.exists():
        return []
    rows = []
    for line in read(REGISTER).splitlines():
        m = re.match(r"^\|\s*`([A-Za-z0-9._+-]+\.md)`\s*\|([^|]*)\|(.*)\|\s*$", line)
        if m:
            rows.append((m.group(1), " ".join(m.group(3).split())))
    return rows


rows = register_rows()
registered = {name for name, _ in rows}
unreasoned = sorted(name for name, reason in rows if len(reason) < MIN_REASON)

uncited = sorted(n for n, (k, *_) in specs.items() if k in ("uncited", "malformed"))

# Resolution, in the same pass as presence. A path-form citation must exist in
# the working tree; a commit-form one must exist at the commit it names.
unresolved = []
for name, (kind, path, sha, _) in specs.items():
    if kind in ("path", "legacy"):
        if not (BRIEFS.parent.parent / path).exists() and not (REPO / path).exists():
            unresolved.append(f"{name} -> {path} (not in the working tree)")
    elif kind == "commit":
        if git("cat-file", "-e", f"{sha}:{path}").returncode != 0:
            unresolved.append(f"{name} -> {path} @ {sha} (not at that commit)")

thin_reasons = sorted(f"{n} ({r!r})" for n, (k, _, _, r) in specs.items()
                      if k == "none" and (r is None or len(r) < MIN_REASON))

# Uniqueness over the header forms only.
claimed_by = {}
for name, (kind, path, _, _) in sorted(specs.items()):
    if kind in ("path", "commit"):
        claimed_by.setdefault(os.path.basename(path), []).append(name)
doubly_claimed = sorted(f"{b}: {', '.join(v)}" for b, v in claimed_by.items() if len(v) > 1)

# Reverse direction: a brief in the queue is claimed by some spec, or registered.
all_claims = {os.path.basename(p) for k, p, _, _ in specs.values() if p}
for name, (kind, *_) in specs.items():
    if kind in ("legacy",):
        continue
for p in sorted(SPECS.glob("spec-*.md")):
    all_claims |= {os.path.basename(m) for m in BODY_PATH.findall(read(p))}
unclaimed = sorted(b for b in briefs if b not in all_claims and b not in registered)
stale_register = sorted(n for n in registered if n not in briefs)


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def number_fallback():
    """(refuses a listing position, accepts a real id, error) from the shared join.

    Executed rather than read. The shared tool's filename reader is the one
    place a brief's position in a directory listing could become a citation at
    confidence 1.0, and a regex match against its source would pass on a
    version that had been rewritten around it.
    """
    try:
        mod = load(RECKON, "reckon_under_test")
        refuses = mod.project_id_in("03-menu-bar-key-equivalents.md") is None
        accepts = mod.project_id_in("SCR-0075-dead-credential.md") == "SCR-0075"
        return refuses, accepts, None
    except Exception as exc:                                  # noqa: BLE001
        return False, False, f"{type(exc).__name__}: {exc}"


refuses_number, accepts_id, join_error = number_fallback()

scaffold = ""
fmt = read(TRIAGE / "references/spec-format.md") if (TRIAGE / "references/spec-format.md").exists() else ""
skill = read(TRIAGE / "SKILL.md") if (TRIAGE / "SKILL.md").exists() else ""
m = re.search(r"### Spec scaffold \(`docs/specs/spec-<ID>\.md`\)\s*\n+```markdown\n(.*?)\n```",
              fmt, re.S)
scaffold = m.group(1) if m else ""
flat = lambda s: " ".join(s.split())

checks = [
    ("every spec carries a parseable citation", not uncited, uncited),
    ("every cited brief path resolves", not unresolved, unresolved),
    ("every `none` citation names its origin", not thin_reasons, thin_reasons),
    ("no brief is claimed by two specs", not doubly_claimed, doubly_claimed),
    ("every brief is claimed or registered", not unclaimed, unclaimed),
    ("the register names only briefs that exist", not stale_register, stale_register),
    ("every register row carries a reason", not unreasoned, unreasoned),
    ("the shared join refuses a listing position", refuses_number, join_error or "03-menu… scored an id"),
    ("the shared join still reads a real id", accepts_id, join_error or "SCR-0075 was not read"),
    ("the triage scaffold carries the citation line",
     bool(re.search(r"^\*\*Brief:\*\*", scaffold, re.M)), scaffold[:80] or "no scaffold found"),
    ("the scaffold's citation form is the path", "docs/features-to-triage/" in scaffold, None),
    ("spec-format documents the consumed-brief form",
     "records the commit that still holds it" in flat(fmt), None),
    ("spec-format documents the no-brief form",
     "**Brief:** none." in fmt and "never a brief" in flat(fmt), None),
    ("triage is told to write the citation",
     "write the citation into the spec" in flat(skill), None),
]

bad = 0
for name, ok, detail in checks:
    print(f"{'PASS' if ok else 'FAIL'}  {name}" + (f"   [{detail}]" if not ok and detail else ""))
    bad += not ok

kinds = {}
for kind, *_ in specs.values():
    kinds[kind] = kinds.get(kind, 0) + 1
print(f"\nspecs {len(specs)}: " + " · ".join(f"{k} {v}" for k, v in sorted(kinds.items())))
print(f"briefs {len(briefs)}: claimed {len(briefs) - len(unclaimed) - len(registered)} · "
      f"registered {len(registered)} · unclaimed {len(unclaimed)}")
print(f"{len(checks) - bad}/{len(checks)} checks passed")
sys.exit(1 if bad else 0)
