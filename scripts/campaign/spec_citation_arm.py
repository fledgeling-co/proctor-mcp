#!/usr/bin/env python3
"""PRO-0101 CASE-0440: prove every check in `spec_citation_measure.py` can report FAIL.

    python3 scripts/campaign/spec_citation_arm.py

Each check gets a mutation that breaks the one thing it claims to watch, applied
to a *scratch copy* of the specs, the brief queue, the register and the shared
triage skill. Nothing live is written. A predecessor on another item armed a doc
instrument by editing the live shared skill, was killed between the mutation and
the revert, and for about an hour every project on this machine read a skill with
an arming mutation in its heading.

A check that stays PASS under its own mutation is reported as NOT ARMED and this
script exits 1. Two of this campaign's instruments have reported a clean zero
they could not have earned: one detector's regex could not cross a parenthesis
and missed the line it was written for, and one census resolved its arming
reference with `git merge-base`, so once the fix merged it read the fixed tree
and reported "caught 0 of the 2 known offenders". Every reference below is a
pinned sha for that reason.

The commit-form pair is the one that matters most, because no spec on this tree
uses that form, so the code path it exercises would otherwise never run:

    3fb7681  holds docs/features-to-triage/92-….md      -> the check must PASS
    400808d  the commit that deleted it                 -> the check must FAIL

Both are immutable and both were read with `git cat-file -e` before being written
here. The `400808d` half is the arming the spec's added clause asks for: a
citation naming a path that does not resolve.
"""
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
MEASURE = HERE / "spec_citation_measure.py"
SPECS = REPO / "docs/specs"
BRIEFS = REPO / "docs/features-to-triage"
REGISTER = REPO / "docs/feature-specs/UNCLAIMED-BRIEFS.md"
TRIAGE = Path("/Users/lukerhodes/Dev/fledgeling-plugins/plugins/shipyard/skills/triage")
RECKON = Path("/Users/lukerhodes/Dev/fledgeling-plugins/plugins/reckon/skills/reckon/scripts/reckon.py")

BRIEF_92 = "docs/features-to-triage/92-a-spec-says-which-brief-it-came-from.md"
SHA_HOLDS, SHA_DELETED = "3fb7681", "400808d"

PASS, FAIL = "PASS", "FAIL"


def edit(rel, old, new):
    """Rewrite one file in the scratch tree, refusing a mutation that matched nothing."""
    def apply(root):
        p = root / rel
        text = p.read_text()
        assert old in text, f"{rel}: {old!r} not found, so nothing was mutated"
        p.write_text(text.replace(old, new, 1))
    return apply


def replace_line(rel, prefix, new):
    """Rewrite a whole line by its opening, so the tail cannot survive the mutation.

    A mutation that replaced only the opening of PRO-0075's citation left the rest
    of the sentence attached, and the reason it was shortening stayed long enough
    to pass. A partial mutation reports NOT ARMED against a check that works.
    """
    def apply(root):
        p = root / rel
        lines = p.read_text().splitlines(keepends=True)
        hit = 0
        for i, line in enumerate(lines):
            if line.startswith(prefix):
                lines[i], hit = new + "\n", hit + 1
        assert hit == 1, f"{rel}: {prefix!r} matched {hit} lines"
        p.write_text("".join(lines))
    return apply


def drop_line(rel, prefix):
    def apply(root):
        p = root / rel
        lines = p.read_text().splitlines(keepends=True)
        kept = [l for l in lines if not l.startswith(prefix)]
        assert len(kept) < len(lines), f"{rel}: no line starts {prefix!r}"
        p.write_text("".join(kept))
    return apply


def delete_brief(name):
    def apply(root):
        p = root / "briefs" / name
        assert p.exists(), f"{name} is not in the queue"
        p.unlink()
    return apply


def add_brief(name):
    def apply(root):
        (root / "briefs" / name).write_text("# Arming\n\nA brief nothing claims.\n")
    return apply


def append_to_spec(rel, text):
    """Add text to the end of a spec. Used to plant a mention of a brief.

    Appended rather than spliced because the position is the point: the mutations
    below plant the same path in a fence, in an HTML comment, struck through and
    in plain prose, and a splice into a specific paragraph would make the four
    differ in more than the one thing being measured.
    """
    def apply(root):
        p = root / rel
        p.write_text(p.read_text().rstrip("\n") + "\n\n" + text + "\n")
    return apply


def add_brief_shown_as(wrapper, name="97-arming.md", spec="specs/spec-PRO-0003.md"):
    """A new brief whose only trace anywhere is one shown-not-used mention.

    One wrapper per call, never several in one fixture: a spec carrying a fenced
    mention, a commented one and a struck-through one at once proves whichever
    exclusion runs first and nothing about the other two.
    """
    path = "docs/features-to-triage/" + name
    def apply(root):
        add_brief(name)(root)
        append_to_spec(spec, wrapper % path)(root)
    return apply


def add_register_row(row):
    """Append to the unclaimed table, which ends where the shared-parent one starts.

    Appending to the end of the file put the row in the second table, where the
    measurement does not look for it, and the mutation reported NOT ARMED against
    a check that works.
    """
    HEAD = "## Briefs several specs share"
    def apply(root):
        p = root / "register.md"
        text = p.read_text()
        assert HEAD in text, "the register has no shared-parent section to stop at"
        first, rest = text.split(HEAD, 1)
        p.write_text(first.rstrip("\n") + "\n" + row + "\n\n" + HEAD + rest)
    return apply


def reckon_regex(new):
    return edit("reckon.py", r'PROJECT_ID_RE = re.compile(r"\A([A-Za-z]{2,}-\d{2,})\b")',
                f'PROJECT_ID_RE = re.compile(r"{new}")')


CITE_0001 = "**Brief:** `docs/features-to-triage/01-cua-schema-facade.md`"

FENCED = "```text\n%s\n```"
COMMENTED = "<!-- %s -->"
STRUCK = "~~%s~~"
PROSE = "The origin of this item is %s, mentioned here and claimed nowhere."

MUTATIONS = [
    ("every spec carries a parseable citation", FAIL,
     drop_line("specs/spec-PRO-0001.md", "**Brief:**")),
    # The citation of record, one exclusion kind at a time. A `**Brief:**` line
    # inside a fence in the first 20 lines used to satisfy the check, because the
    # header was read out of the raw text and the legacy fallback searched the
    # whole document.
    ("every spec carries a parseable citation", FAIL,
     edit("specs/spec-PRO-0001.md", CITE_0001, FENCED % CITE_0001)),
    ("every spec carries a parseable citation", FAIL,
     edit("specs/spec-PRO-0001.md", CITE_0001, COMMENTED % CITE_0001)),
    ("every spec carries a parseable citation", FAIL,
     edit("specs/spec-PRO-0001.md", CITE_0001, STRUCK % CITE_0001)),
    ("every spec carries a parseable citation", FAIL,
     edit("specs/spec-PRO-0001.md", CITE_0001, "**Brief:** the cua brief")),
    ("every cited brief path resolves", FAIL,
     edit("specs/spec-PRO-0001.md", CITE_0001,
          "**Brief:** `docs/features-to-triage/99-no-such-brief.md`")),
    ("every cited brief path resolves", FAIL,
     delete_brief("01-cua-schema-facade.md")),
    ("every cited brief path resolves", FAIL,
     edit("specs/spec-PRO-0001.md", CITE_0001,
          f"**Brief:** `{BRIEF_92}` @ `{SHA_DELETED}`")),
    ("every cited brief path resolves", PASS,
     edit("specs/spec-PRO-0001.md", CITE_0001,
          f"**Brief:** `{BRIEF_92}` @ `{SHA_HOLDS}`")),
    ("every `none` citation names its origin", FAIL,
     replace_line("specs/spec-PRO-0075.md", "**Brief:** none.", "**Brief:** none. See above")),
    ("no brief is claimed by two specs", FAIL,
     edit("specs/spec-PRO-0002.md",
          "**Brief:** `docs/features-to-triage/02-set-of-marks-captures.md`", CITE_0001)),
    ("every brief is claimed or registered", FAIL, add_brief("97-arming.md")),
    # A mention is not a claim, proved separately for each of the three regions
    # that show a path rather than use one, and once for plain prose.
    ("no brief's only trace is a shown-not-used mention", FAIL, add_brief_shown_as(FENCED)),
    ("no brief's only trace is a shown-not-used mention", FAIL, add_brief_shown_as(COMMENTED)),
    ("no brief's only trace is a shown-not-used mention", FAIL, add_brief_shown_as(STRUCK)),
    ("no brief is claimed only by an incidental mention", FAIL, add_brief_shown_as(PROSE)),
    # A header relation this check has no rule for. It names a brief in the shape
    # an account takes, and the check refuses to read it either way.
    ("no brief is accounted for by an unrecognised relation", FAIL,
     append_to_spec("specs/spec-PRO-0003.md",
                    "**Cut from:** `docs/features-to-triage/01-cua-schema-facade.md`")),
    # DEF-203's second clause, three ways: a path that does not resolve, a PRD
    # section that does not exist, and a backtick pair padded past the length
    # floor. The last one is why a longer floor is not the repair.
    ("every `none` citation resolves to something here", FAIL,
     replace_line("specs/spec-PRO-0075.md", "**Brief:** none.",
                  "**Brief:** none. See `docs/nowhere/imaginary-source.md` for where this came from")),
    ("every `none` citation resolves to something here", FAIL,
     replace_line("specs/spec-PRO-0075.md", "**Brief:** none.",
                  "**Brief:** none. Cut directly from PRD §99, the section on all of this")),
    ("every `none` citation resolves to something here", FAIL,
     replace_line("specs/spec-PRO-0075.md", "**Brief:** none.",
                  "**Brief:** none. The specification is `whatever.md` and that is all there is")),
    # An absolute path resolves on the machine rather than in the repository, and
    # `REPO / "/bin/sh"` is `/bin/sh` in pathlib. Found by an out-of-family review
    # of this change; armed here so the next reader does not have to find it again.
    ("every `none` citation resolves to something here", FAIL,
     replace_line("specs/spec-PRO-0075.md", "**Brief:** none.",
                  "**Brief:** none. The origin is `/bin/sh` and there is nothing else to name")),
    ("every `none` citation resolves to something here", FAIL,
     replace_line("specs/spec-PRO-0075.md", "**Brief:** none.",
                  "**Brief:** none. Cut from `../../../etc/passwd`, which is quite a long way up")),
    ("the register names only briefs that exist", FAIL,
     add_register_row("| `98-not-a-brief.md` | nowhere | This row names a file the queue does not hold. |")),
    ("every register row carries a reason", FAIL,
     replace_line("register.md", "| `96-what-1-1-0-still-groups-and-still-grades.md`",
                  "| `96-what-1-1-0-still-groups-and-still-grades.md` | untriaged |  |")),
    ("every `none` citation names its origin", FAIL,
     replace_line("specs/spec-PRO-0075.md", "**Brief:** none.",
                  "**Brief:** none. This one came from somewhere else entirely, honestly")),
    ("every shared-parent brief is recorded with its count", FAIL,
     edit("register.md", "| `57-vm-targets.md` | 7 specs |", "| `57-vm-targets.md` | 6 specs |")),
    ("the shared join refuses a listing position", FAIL,
     reckon_regex("\\A([^-]+-[^-]+)\\b")),
    ("the shared join still reads a real id", FAIL,
     reckon_regex("\\A([A-Za-z]{4,}-\\d{2,})\\b")),
    ("the triage scaffold carries the citation line", FAIL,
     drop_line("triage/references/spec-format.md",
               "**Brief:** `docs/features-to-triage/<slug>.md`")),
    ("the scaffold's citation form is the path", FAIL,
     replace_line("triage/references/spec-format.md",
                  "**Brief:** `docs/features-to-triage/<slug>.md`", "**Brief:** <the brief>")),
    ("spec-format documents the consumed-brief form", FAIL,
     edit("triage/references/spec-format.md",
          "records the commit that still holds it", "keeps a note of the commit")),
    ("spec-format documents the no-brief form", FAIL,
     edit("triage/references/spec-format.md",
          "| The feature was never a brief |", "| There was no brief |")),
    ("triage is told to write the citation", FAIL,
     edit("triage/SKILL.md", "write the citation into the spec's", "put provenance in the spec's")),
]


def fixture_repo(root):
    """A throwaway repository whose history holds the three shapes a citation can name.

    `git cat-file -e` is satisfied by a tree entry and by a zero-byte blob, and
    an out-of-family review of this item said so. Nothing in the real history
    cites a brief path that is either, so the two failing shapes are built here
    rather than left as branches no mutation can reach.

    Returns (sha, path-that-is-a-file, path-that-is-empty, path-that-is-a-tree).
    """
    repo = root / "fixture"
    briefs = repo / "docs/features-to-triage"
    (briefs / "tree.md").mkdir(parents=True)
    (briefs / "full.md").write_text("# A brief with bytes in it\n")
    (briefs / "empty.md").write_text("")
    (briefs / "tree.md" / "inner.txt").write_text("this makes tree.md a directory\n")
    env = {"GIT_AUTHOR_NAME": "arm", "GIT_AUTHOR_EMAIL": "arm@example.invalid",
           "GIT_COMMITTER_NAME": "arm", "GIT_COMMITTER_EMAIL": "arm@example.invalid",
           "PATH": "/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin", "HOME": str(root)}
    run = lambda *a: subprocess.run(("git", "-C", str(repo)) + a, capture_output=True,
                                    text=True, env=env, check=True)
    subprocess.run(("git", "init", "-q", str(repo)), check=True, capture_output=True, env=env)
    run("add", "docs")
    run("commit", "-q", "-m", "fixture")
    sha = run("rev-parse", "--short", "HEAD").stdout.strip()
    return repo, sha


def scratch(tmp):
    """A copy of every document the measurement reads, and nothing else."""
    root = Path(tmp)
    shutil.copytree(SPECS, root / "specs")
    shutil.copytree(BRIEFS, root / "briefs")
    shutil.copy(REGISTER, root / "register.md")
    (root / "triage" / "references").mkdir(parents=True)
    shutil.copy(TRIAGE / "SKILL.md", root / "triage" / "SKILL.md")
    shutil.copy(TRIAGE / "references/spec-format.md", root / "triage/references/spec-format.md")
    shutil.copy(RECKON, root / "reckon.py")
    return root


def measure(root, repo=REPO):
    r = subprocess.run(
        [sys.executable, str(MEASURE),
         "--specs", str(root / "specs"), "--briefs", str(root / "briefs"),
         "--register", str(root / "register.md"), "--triage", str(root / "triage"),
         "--reckon", str(root / "reckon.py"), "--repo", str(repo)],
        capture_output=True, text=True)
    pairs = re.findall(r"^(PASS|FAIL)  (.+?)(?:   \[.*\])?$", r.stdout, re.M)
    return {name: verdict for verdict, name in pairs}, r.stdout + r.stderr


def fixture_cases():
    """The three shapes a `path @ sha` citation can name, measured against a fixture.

    Each returns the verdict of `every cited brief path resolves` with PRO-0001's
    citation rewritten to that shape. A blob with bytes must PASS; an empty blob
    and a tree must both FAIL.
    """
    want = [("a blob with bytes", "full.md", PASS),
            ("an empty blob", "empty.md", FAIL),
            ("a tree, not a file", "tree.md", FAIL)]
    failures = []
    for label, name, expect in want:
        with tempfile.TemporaryDirectory() as tmp:
            root = scratch(tmp)
            repo, sha = fixture_repo(Path(tmp))
            edit("specs/spec-PRO-0001.md", CITE_0001,
                 f"**Brief:** `docs/features-to-triage/{name}` @ `{sha}`")(root)
            after, _ = measure(root, repo=repo)
        got = after.get("every cited brief path resolves", "MISSING")
        ok = got == expect
        print(f"{'ARMED    ' if ok else 'NOT ARMED'} commit form names {label}"
              f"  (wanted {expect}, got {got})")
        if not ok:
            failures.append(f"commit form names {label} (wanted {expect}, got {got})")
    return failures


def main():
    with tempfile.TemporaryDirectory() as tmp:
        baseline, out = measure(scratch(tmp))
    if not baseline or any(v != PASS for v in baseline.values()):
        print("baseline is not green on an unmutated copy; arming would mean nothing:")
        print(out)
        return 1
    print(f"baseline: {len(baseline)}/{len(baseline)} PASS on an unmutated scratch copy\n")

    covered, failures = set(), []
    for name, want, mutate in MUTATIONS:
        with tempfile.TemporaryDirectory() as tmp:
            root = scratch(tmp)
            mutate(root)
            after, out = measure(root)
        got = after.get(name, "MISSING")
        moved = sorted(n for n, v in after.items() if v == FAIL)
        ok = got == want
        print(f"{'ARMED    ' if ok else 'NOT ARMED'} {name}  (wanted {want}, got {got})")
        print(f"          reds under this mutation: {', '.join(moved) or 'nothing'}")
        if want == FAIL:
            covered.add(name)
        if not ok:
            failures.append(f"{name} (wanted {want}, got {got})")

    failures += fixture_cases()

    unarmed = sorted(set(baseline) - covered)
    total = len(MUTATIONS) + 3
    print(f"\n{total - len(failures)}/{total} mutations behaved as pinned; "
          f"{len(covered)}/{len(baseline)} checks watched to fail")
    if unarmed:
        print("no mutation makes these fail: " + "; ".join(unarmed))
    if failures:
        print("wrong verdict: " + "; ".join(failures))
    return 1 if failures or unarmed else 0


sys.exit(main())
