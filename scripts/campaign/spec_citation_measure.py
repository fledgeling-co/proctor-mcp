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

## A mention is not a citation, and a name is not a reference

Three of the checks below accepted inputs their names imply they reject, each
found by building the evasion against a scratch copy (DEF-203). `every spec
carries a parseable citation` passed when the only brief path sat in a fenced
block, an HTML comment or a struck-through line, because the legacy fallback was
a bare search over the whole text. `every `none` citation names its origin`
passed on `none. See docs/nowhere/imaginary-source.md` and on any backtick pair
padded to twenty characters. `every brief is claimed or registered` was satisfied
by an incidental mention in an unrelated spec, so a brief nobody built from read
as claimed.

The repair is not a longer floor. A longer floor extends the set of inputs this
check guesses correctly about and leaves it guessing, so the next evasion works
exactly as the last one did. Instead every input is placed:

  * **Shown, not used.** A fenced block, an HTML comment and a struck-through
    span are blanked before anything is matched, in `citable`. A brief path in
    one of them is a mention of a citation rather than a citation, and where it
    is a brief's only trace the check says so with its count rather than
    accepting it.
  * **An account, or a mention.** A brief is accounted for by a `**Brief:**`,
    `**Supersedes:**` or `**Direction:**` header segment, by being the citation
    of record of a spec that has no header, or by a register row. Brief 32 is
    real: `spec-PRO-0050.md` supersedes it, in a header, and that is a decision
    somebody wrote down — while the same path in body prose is a reference. A
    header relation outside those three that names a brief is an input this check
    cannot place, and is reported with its count rather than read either way.
  * **A reference, or a name.** In a `none.` reason, a token holding a `/` is a
    path and must resolve in the tree; a `§N` must resolve in the PRD; a sha must
    resolve in git. A bare filename is a *name* — this check does not pretend to
    resolve a basename against a tree, for the same reason the number is never a
    fallback below — so it names something without being a reference, and a
    reason offering nothing else fails.

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
# The three regions a markdown document shows a token in rather than uses it.
# Blanked rather than deleted, because deleting a fence joins the line above it
# to the line below and a check anchored to a line start would then match text
# that was never at one.
FENCE_RE = re.compile(r"^([ \t]*)(`{3,}|~{3,})[^\n]*\n.*?(?:^\1?\2[^\n]*\n|\Z)", re.M | re.S)
HTML_COMMENT_RE = re.compile(r"<!--.*?-->", re.S)
STRIKETHROUGH_RE = re.compile(r"~~[^\n]+?~~")
EXCLUSIONS = (("fenced", FENCE_RE), ("comment", HTML_COMMENT_RE), ("struck", STRIKETHROUGH_RE))

# A header line, and the relations that account for a brief rather than refer to
# one. Derived from the corpus rather than guessed: across 104 specs the only
# header segments naming a brief path are `Brief` (76), `Direction` (12) and
# `Supersedes` (1).
HEADER_SEGMENT_RE = re.compile(r"\*\*([^:*\n]{1,40}):\*\*")
ACCOUNT_RELATIONS = ("Brief", "Supersedes", "Direction")
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


def citable(text):
    """(text with the shown-not-used regions blanked, {kind: [brief paths in them]})."""
    shown, out = {}, text
    for kind, rx in EXCLUSIONS:
        found = []

        def take(m, _found=found):
            _found.extend(re.findall(BRIEF_PATH, m.group(0)))
            return re.sub(r"[^\n]", " ", m.group(0))

        out = rx.sub(take, out)
        if found:
            shown[kind] = found
    return out, shown


def header_segments(text):
    """[(relation, segment)] for every `**Name:**` on a header line.

    A header line is one whose first non-space characters are `**`, so a sentence
    in the body mentioning `**Brief:**` cannot make a claim. Several relations
    share a line — `**Status:** To Do → Ready for AI · **Brief:** `…`` is seven
    specs' shape — so a line is cut at each relation rather than read as one.
    """
    out = []
    for line in text.splitlines():
        if not line.lstrip().startswith("**"):
            continue
        hits = list(HEADER_SEGMENT_RE.finditer(line))
        for i, m in enumerate(hits):
            end = hits[i + 1].start() if i + 1 < len(hits) else len(line)
            out.append((m.group(1).strip(), line[m.end():end]))
    return out


def classify(text):
    """(kind, path, sha, reason) for one spec.

    kind is `path`, `commit`, `none`, `legacy` or `uncited`. A malformed header
    is `malformed` rather than silently falling through to the body, because a
    citation nobody can parse is the failure this check exists to catch.
    """
    body_text, _ = citable(text)
    head = "".join(body_text.splitlines(keepends=True)[:HEADER_LINES])
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
    body = BODY_PATH.search(body_text)
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
    # The register holds two tables and they mean different things: a brief no spec
    # claims, and a brief several specs share. Reading past the second heading
    # counted four shared parents as unclaimed and moved the claimed total.
    body = read(REGISTER).split("## Briefs several specs share")[0]
    for line in body.splitlines():
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
        # Resolved against the brief directory in play rather than against REPO,
        # so a scratch queue is measured as the queue and the real one cannot
        # answer for it. The `docs/features-to-triage/` prefix is fixed by the
        # grammar, so the basename is the whole of the lookup.
        if not (BRIEFS / os.path.basename(path)).exists():
            unresolved.append(f"{name} -> {path} (not in the brief queue)")
    elif kind == "commit":
        # `cat-file -e` answers "git can resolve this", which a tree entry and a
        # zero-byte blob both satisfy. A citation is a promise that the brief is
        # readable there, so the type and the size are both asserted.
        kind_at = git("cat-file", "-t", f"{sha}:{path}")
        size_at = git("cat-file", "-s", f"{sha}:{path}")
        got = kind_at.stdout.strip()
        size = int(size_at.stdout.strip()) if size_at.returncode == 0 and size_at.stdout.strip() else 0
        if kind_at.returncode != 0:
            unresolved.append(f"{name} -> {path} @ {sha} (not at that commit)")
        elif got != "blob":
            unresolved.append(f"{name} -> {path} @ {sha} (a {got} there, not a file)")
        elif size == 0:
            unresolved.append(f"{name} -> {path} @ {sha} (an empty file there)")

PRD = REPO / "docs/PRD.md"
SHA_TOKEN = re.compile(r"\A[0-9a-f]{7,40}\Z")
REF_RE = re.compile(r"`([^`]+)`|§\s*(\d+[A-Za-z]?)")


def references(reason):
    """[(token, kind, resolves, why)] for one `none.` reason.

    Four kinds and no fifth. A token holding a `/` is a path and must exist in
    the tree; a `§N` must be a heading in the PRD; a 7-40 hex token must resolve
    in git. Anything else is a **name**: it names something without being a
    reference this check can resolve, because resolving a basename against a tree
    is the same guess as turning a listing position into a citation.
    """
    out = []
    for m in REF_RE.finditer(reason or ""):
        if m.group(2):
            n = m.group(2)
            ok = bool(re.search(r"^#{1,3} %s[.\s]" % re.escape(n), read(PRD), re.M)) if PRD.exists() else False
            out.append(("§" + n, "PRD section", ok, "no `## %s.` heading in docs/PRD.md" % n))
            continue
        tok = m.group(1).strip()
        first = (tok.split() or [""])[0].strip("`.,;:")
        if SHA_TOKEN.match(first):
            out.append((first, "commit",
                        git("cat-file", "-e", first + "^{commit}").returncode == 0,
                        "git cannot resolve it"))
        elif first and (REPO / first).exists():
            # Resolved against the repository root exactly, never searched for by
            # basename: an exact repo-relative path is unambiguous, and a
            # basename hunted through a tree is the same guess as reading a
            # listing position as a citation.
            out.append((first, "path", True, ""))
        elif "/" in first:
            out.append((first, "path", False, "nothing at that path in the tree"))
        else:
            out.append((first or tok, "name", False,
                        "a name rather than a path, a PRD section or a commit"))
    return out


# A length floor is satisfiable with boilerplate — "none. not applicable here"
# clears twenty characters and names nothing — so the reason also has to point at
# something a reader can open: a backticked file or tool, a PRD section, or a sha.
NAMES_ARTIFACT = re.compile(r"`[^`]+`|§\s*\d+|\b[0-9a-f]{7,40}\b")
thin_reasons = sorted(
    f"{n} ({r!r})" for n, (k, _, _, r) in specs.items()
    if k == "none" and (r is None or len(r) < MIN_REASON or not NAMES_ARTIFACT.search(r)))

# Uniqueness over the header forms only.
claimed_by = {}
for name, (kind, path, _, _) in sorted(specs.items()):
    if kind in ("path", "commit"):
        claimed_by.setdefault(os.path.basename(path), []).append(name)
doubly_claimed = sorted(f"{b}: {', '.join(v)}" for b, v in claimed_by.items() if len(v) > 1)

# Reverse direction. Every brief-path token in every spec is placed in exactly
# one of four boxes, and only two of them account for a brief:
#
#   account   a `**Brief:**`, `**Supersedes:**` or `**Direction:**` header
#             segment, or the citation of record of a spec with no header form —
#             a decision somebody wrote down
#   mention   the same path in body prose: a reference, not a claim
#   shown     the path inside a fence, an HTML comment or a struck-through span
#   odd       a header relation this check has no rule for
#
# The old version unioned every body path into the claimed set, so a brief
# nobody built from read as claimed if any spec happened to mention it.
accounts, mentions, all_refs, shown_paths = {}, {}, {}, {}
odd_relation = []
for p in sorted(SPECS.glob("spec-*.md")):
    body_text, shown = citable(read(p))
    in_headers = set()
    for rel, seg in header_segments(body_text):
        for m in BODY_PATH.findall(seg):
            base = os.path.basename(m)
            in_headers.add(base)
            if rel in ACCOUNT_RELATIONS:
                accounts.setdefault(base, []).append("%s **%s:**" % (p.name, rel))
            else:
                odd_relation.append("%s: **%s:** names %s" % (p.name, rel, base))
    kind, path, _, _ = specs[p.name]
    if kind == "legacy" and path:
        accounts.setdefault(os.path.basename(path), []).append("%s citation of record" % p.name)
    for m in set(BODY_PATH.findall(body_text)):
        base = os.path.basename(m)
        all_refs.setdefault(base, []).append(p.name)
        if base not in in_headers:
            mentions.setdefault(base, []).append(p.name)
    for kindname, paths in shown.items():
        for m in paths:
            counts = shown_paths.setdefault(os.path.basename(m), {})
            counts[kindname] = counts.get(kindname, 0) + 1

# The shared-parent table accounts for a brief no single spec can own, so it is
# read here rather than only counted further down.
declared_shared = {}
if REGISTER.exists():
    for line in read(REGISTER).splitlines():
        m = re.match(r"^\|\s*`([A-Za-z0-9._+-]+\.md)`\s*\|\s*(\d+) specs?\s*\|", line)
        if m:
            declared_shared[m.group(1)] = int(m.group(2))

accounted = set(accounts) | registered | set(declared_shared)
unclaimed = sorted(b for b in briefs if b not in accounted)
stale_register = sorted(n for n in registered if n not in briefs)

# The two findings the old union hid, each naming the brief and its count. They
# are subsets of `unclaimed` and they are reported separately because "nothing
# claims this" and "the thing that looked like a claim was a fenced example"
# send a reader to different places.
shown_only_claim = sorted(
    "%s (%s)" % (b, ", ".join("%s %d" % (k, n) for k, n in sorted(shown_paths[b].items())))
    for b in unclaimed if b in shown_paths)
mention_only_claim = sorted(
    "%s (mentioned in %d spec(s): %s)" % (b, len(mentions[b]), ", ".join(sorted(mentions[b])[:4]))
    for b in unclaimed if b in mentions)

# Every `none.` citation has to resolve to something in this repository, rather
# than merely name something. Two ways to fail and both are DEF-203's: a reason
# no reference in which resolves — `none. See docs/nowhere/imaginary-source.md`,
# and any backtick pair padded past the length floor — and a reason naming a
# path, a PRD section or a commit that does not exist.
#
# A **name** is neither of those and is not a failure on its own. Naming the tool
# a finding came off, beside an artifact a reader can open, is how somebody
# honestly describes an origin; what the check refuses is a name standing in for
# the artifact. So a name never satisfies the requirement and never breaks a
# reason that also carries something resolvable, and the count of them is
# disclosed in the summary rather than left invisible.
unresolved_reasons, named_not_referenced = [], []
for name, (k, _, _, r) in sorted(specs.items()):
    if k != "none":
        continue
    refs = references(r)
    dangling = "; ".join("`%s` (%s: %s)" % (tok, kind, why)
                         for tok, kind, ok, why in refs if not ok and kind != "name")
    named_not_referenced += ["%s `%s`" % (name, tok) for tok, kind, ok, _ in refs
                             if kind == "name" and not ok]
    if not any(ok for _, _, ok, _ in refs):
        unresolved_reasons.append(
            "%s resolves nothing: %s"
            % (name, "; ".join("`%s` (%s)" % (tok, kind) for tok, kind, _, _ in refs)
               or "names no reference at all"))
    elif dangling:
        unresolved_reasons.append("%s names a reference that does not resolve: %s" % (name, dangling))

# A brief several specs cite, with no spec owning it by header, is a shared parent:
# 57-vm-targets.md is the direction document PRO-0056 through PRO-0062 were all cut
# from. Uniqueness cannot apply to those, so they are enumerated in the register
# with their count instead of being quietly exempt. Where one spec does own the
# brief by header, further prose mentions are references rather than claims.
shared = {b: v for b, v in all_refs.items() if len(v) > 1 and b not in claimed_by}
unrecorded_shared = sorted(
    f"{b} ({len(v)} specs, register says {declared_shared.get(b, 'nothing')})"
    for b, v in shared.items() if declared_shared.get(b) != len(v))


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
    ("every `none` citation resolves to something here", not unresolved_reasons, unresolved_reasons),
    ("no brief is claimed by two specs", not doubly_claimed, doubly_claimed),
    ("every brief is claimed or registered", not unclaimed, unclaimed),
    ("no brief's only trace is a shown-not-used mention", not shown_only_claim, shown_only_claim),
    ("no brief is claimed only by an incidental mention", not mention_only_claim, mention_only_claim),
    ("no brief is accounted for by an unrecognised relation", not odd_relation, odd_relation),
    ("the register names only briefs that exist", not stale_register, stale_register),
    ("every register row carries a reason", not unreasoned, unreasoned),
    ("every shared-parent brief is recorded with its count",
     not unrecorded_shared, unrecorded_shared),
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
    # The detail is flattened because `spec_citation_arm.py` reads these lines one
    # per check: a scaffold quoted with its newlines intact turned an ARMED check
    # into a MISSING one, which reads as an unarmed check rather than a parse fault.
    shown = " ".join(str(detail).split()) if detail else ""
    print(f"{'PASS' if ok else 'FAIL'}  {name}" + (f"   [{shown}]" if not ok and shown else ""))
    bad += not ok

kinds = {}
for kind, *_ in specs.values():
    kinds[kind] = kinds.get(kind, 0) + 1
print(f"\nspecs {len(specs)}: " + " · ".join(f"{k} {v}" for k, v in sorted(kinds.items())))
print(f"none-citations {sum(1 for k, *_ in specs.values() if k == 'none')}: "
      f"{len(unresolved_reasons)} resolving nothing · "
      f"{len(named_not_referenced)} naming something this check cannot resolve"
      + (f" ({', '.join(named_not_referenced)})" if named_not_referenced else ""))
print(f"briefs {len(briefs)}: claimed {len(briefs) - len(unclaimed) - len(registered)} · "
      f"registered {len(registered)} · unclaimed {len(unclaimed)}")
print(f"{len(checks) - bad}/{len(checks)} checks passed")
sys.exit(1 if bad else 0)
