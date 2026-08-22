#!/usr/bin/env python3
"""Refuse a new operator-path writer that has no injection seam.

**The class this closes.** Four times now a `static` in this tree has computed a
path under the operator's own `~/Library/Application Support/app.fledgeling.procter`
with nothing to inject, so a test process resolved it to the operator's real
directory and wrote there. The policy store (DEF-042/110), the capture directory
(DEF-142), the flow store (DEF-164) and the settings file (PRO-0099) are one
shape, and not one of the first three was found by looking for it: one came from a
brief that happened to ask about test seams, and two came from a witness that had
just been narrowed enough to bite. A fifth would be found the same way, weeks
after it started writing. This check is the alternative to waiting for that.

**What it reads.** `operator_paths.json` beside this file classes every
declaration in `Sources/` that names a path under that root. The classes:

  operator-accessor  A deliberately truthful path — the operator's real
                     directory, kept honest so a test can name what it must not
                     touch. Requires `seamed_by`: the declaration that guards it.
                     The gate checks the seam exists, that it carries a
                     test-process predicate, that it names this accessor, and
                     that nothing else in Sources/ reaches the accessor directly.
  writer-seam        The path literal and the guard are the same declaration
                     (`AuditLog.directory`, `CaptureEngineImpl.defaultCaptureDirectory`).
                     The gate checks that declaration carries the predicate.
  parameterised      The root arrives as an argument, so the declaration cannot
                     reach the operator by itself. The gate checks the parameter
                     is really in the signature.
  socket             A rendezvous address rather than stored state. No seam
                     required; a reason is.
  prose              A string a person or a model reads. No seam required; a
                     reason is.

**The two checks.**

  `census`  Two sweeps, both of which must map every site to an entry.

            *The literal.* Every non-comment line in Sources/ naming the root
            literal. A NEW path with no entry fails here. Comment lines are
            skipped: a comment describing a path is prose about it, and the
            shipped-prose cases are string literals that carry their own entries.

            *The composition.* A `parameterised` declaration is safe BECAUSE the
            root arrives as an argument — so the caller that hands it the
            operator's real home is the operator path, and that caller names no
            literal at all. `SwitchStore.operatorURL` is written exactly that way
            (`url(home: FileManager.default.homeDirectoryForCurrentUser)`), so
            before this sweep existed a new un-seamed twin of it needed no entry
            and both modes stayed green. Every line calling a `parameterised`
            entry's declaration with one of `home_expressions` on it is a site.

            An entry spelled bare satisfies a site only where that bare name is
            UNAMBIGUOUS in its file — one distinct qualified name. A second
            `Legacy.operatorURL` beside `SwitchStore.operatorURL` used to be
            absorbed by the bare `operatorURL` entry, so the gate resolved the new
            site to its qualified name and then threw the qualification away. Both
            sites are now refused until the manifest says which is which.

  `seams`   Every entry's own requirement, per the classes above, plus the
            `guards` block — presently one, refusing a bare
            `ProctorReflector.start()` under Tests/.

            The leak half of `operator-accessor` reads two ways round. A
            QUALIFIED reach — `SwitchStore.operatorURL` — is refused from any
            other file, always. A bare reach is refused only from a file that does
            not declare that name itself, because `PolicyStore.operatorDirectory`
            and `FlowStore.operatorDirectory` are different paths spelled alike.
            The first version skipped the whole file on the second rule, so a
            `Bypass.swift` declaring any member named `operatorURL` could call
            `SwitchStore.operatorURL` around its seam and be waved through.

Both run by default. Exit 1 on a finding, 0 on none.

    python3 scripts/campaign/operator_path_gate.py
    python3 scripts/campaign/operator_path_gate.py census
    python3 scripts/campaign/operator_path_gate.py seams

`scripts/campaign/test_instruments.py` arms both directions, so a check that
cannot fire is distinguishable from a check that found nothing.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

DECL = re.compile(
    r"^(?P<indent>\s*)(?:@\w+\s+)*"
    r"(?:(?:public|internal|private|fileprivate|package|open|final|static|class|lazy|nonisolated)"
    r"(?:\([^)]*\))?\s+)*"
    r"(?:func|var|let)\s+(?P<name>[A-Za-z_]\w*)"
)


def repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def load_manifest(root: Path) -> dict:
    return json.loads((root / "scripts/campaign/operator_paths.json").read_text())


def swift_sources(root: Path) -> list[Path]:
    return sorted((root / "Sources").rglob("*.swift"))


def enclosing_declaration(lines: list[str], index: int) -> str | None:
    """The nearest declaration above `index` that opens a wider scope.

    Scans backwards for a `func`/`var`/`let` whose indentation is strictly less
    than the site's, which is what makes it the enclosing one rather than a local
    binding beside it. A site sitting on its own declaration line matches itself.
    """
    site = lines[index]
    own = DECL.match(site)
    if own:
        return own.group("name")
    site_indent = len(site) - len(site.lstrip())
    for j in range(index - 1, -1, -1):
        m = DECL.match(lines[j])
        if not m:
            continue
        if len(m.group("indent")) < site_indent:
            return m.group("name")
    return None


def scope_end(lines: list[str], start: int, indent: int) -> int:
    """One past the line closing the scope opened at `start` at `indent`.

    The first line at or below the opening indentation that begins with a closing
    brace, which is how every declaration in this tree is written.
    """
    for j in range(start + 1, len(lines)):
        nxt = lines[j]
        stripped = nxt.strip()
        if stripped and len(nxt) - len(nxt.lstrip()) <= indent and stripped.startswith("}"):
            return j + 1
    return len(lines)


def enclosing_type(lines: list[str], index: int) -> str | None:
    """The innermost type declaration whose scope actually contains `index`.

    Containment is measured rather than inferred from indentation alone. The
    first version scanned backwards for any type indented less than the site and
    took it, which reads a type that has already CLOSED above the site as if it
    enclosed it: `PolicyStore.swift` declares `final class Seams` at the same
    depth as `AuditLog`'s own members and closes it 19 lines before
    `AuditLog.directory` writes the operator literal, so the census reported that
    literal as `Seams.directory` and failed to match its `AuditLog.directory`
    entry. A nested type's declaration line always sits between the site and its
    enclosing type's line, so the nearest match is the wrong one exactly when a
    nested type is present.
    """
    site_indent = len(lines[index]) - len(lines[index].lstrip())
    for j in range(index - 1, -1, -1):
        m = TYPE_DECL.match(lines[j])
        if not m:
            continue
        indent = len(m.group("indent"))
        if indent >= site_indent:
            continue
        if scope_end(lines, j, indent) <= index:
            continue
        return m.group("name")
    return None


def qualified_declarations(lines: list[str]) -> dict[str, set[str]]:
    """Every declaration in a file, bare name to the qualified spellings it has.

    A bare manifest entry may only carry a site whose bare name maps to exactly
    one qualified spelling here. The local `let directory` inside
    `SwitchStore.save` and the `static func directory(home:)` beside it are both
    `SwitchStore.directory`, so they collapse to one and the bare entry still
    reads; `Seams.directory` and `AuditLog.directory` do not, and neither would a
    `Legacy.operatorURL` added beside `SwitchStore.operatorURL`.
    """
    names: dict[str, set[str]] = {}
    for i, line in enumerate(lines):
        m = DECL.match(line)
        if not m:
            continue
        bare = m.group("name")
        owner = enclosing_type(lines, i)
        names.setdefault(bare, set()).add(f"{owner}.{bare}" if owner else bare)
    return names


def accessor_owner(lines: list[str], decl: str) -> str | None:
    """The type a manifest declaration belongs to, however the entry spells it."""
    if "." in decl:
        return decl.split(".", 1)[0]
    found = declaration_body(lines, decl)
    if not found:
        return None
    return enclosing_type(lines, found[0] - 1)


def census_sites(root: Path, literal: str) -> list[tuple[str, int, str, str, str]]:
    """Every non-comment line in Sources/ naming the operator root literal."""
    found = []
    for path in swift_sources(root):
        lines = path.read_text().splitlines()
        for i, line in enumerate(lines):
            if literal not in line:
                continue
            if line.lstrip().startswith("//"):
                continue
            decl = enclosing_declaration(lines, i)
            owner = enclosing_type(lines, i)
            qualified = f"{owner}.{decl}" if owner and decl else decl
            found.append((str(path.relative_to(root)), i + 1, decl or "<none>",
                          qualified or "<none>", line.strip()))
    return found


def composed_sites(root: Path, manifest: dict) -> list[tuple[str, int, str, str, str]]:
    """Every line handing the operator's real home to a `parameterised` builder.

    A `parameterised` declaration is classed safe precisely because the root
    arrives as an argument. That makes its CALLER the operator path when the
    argument is the operator's own home — and that caller names no root literal,
    so the literal census cannot see it. `SwitchStore.operatorURL` is written that
    way, which is why a new un-seamed twin of it used to need no entry at all.
    """
    builders = {e["declaration"].split(".")[-1] for e in manifest["entries"]
                if e.get("class") == "parameterised"}
    homes = manifest.get("home_expressions", [])
    if not builders or not homes:
        return []
    call = re.compile("|".join(rf"\b{re.escape(b)}\s*\(" for b in sorted(builders)))
    found = []
    for path in swift_sources(root):
        lines = path.read_text().splitlines()
        for i, line in enumerate(lines):
            if line.lstrip().startswith("//"):
                continue
            if not any(h in line for h in homes) or not call.search(line):
                continue
            decl = enclosing_declaration(lines, i)
            owner = enclosing_type(lines, i)
            qualified = f"{owner}.{decl}" if owner and decl else decl
            found.append((str(path.relative_to(root)), i + 1, decl or "<none>",
                          qualified or "<none>", line.strip()))
    return found


TYPE_DECL = re.compile(
    r"^(?P<indent>\s*)(?:(?:public|internal|private|fileprivate|package|open|final)\s+)*"
    r"(?:enum|struct|class|actor|extension)\s+(?P<name>[A-Za-z_]\w*)"
)


def code_only(lines: list[str]) -> str:
    """The declaration's code, with comment lines dropped.

    A predicate named in a doc comment is a description of a seam rather than a
    seam, and the whole point of this gate is that it cannot be satisfied by
    prose. Every interlock in this tree writes its guard on one line of code.
    """
    return "\n".join(l for l in lines if not l.lstrip().startswith("//"))


def type_scope(lines: list[str], owner: str) -> tuple[int, int]:
    """The half-open line range of a named type, or the whole file when unnamed.

    Needed because a bare declaration name is ambiguous in this tree:
    `PolicyStore.swift` declares `directory` three times — the store's own stored
    property, a lock-guarded seam, and `AuditLog.directory`, which is the writer.
    A manifest entry says `AuditLog.directory` and is resolved here.
    """
    for i, line in enumerate(lines):
        m = TYPE_DECL.match(line)
        if not m or m.group("name") != owner:
            continue
        return i, scope_end(lines, i, len(m.group("indent")))
    return 0, len(lines)


def declaration_body(lines: list[str], name: str) -> tuple[int, list[str]] | None:
    """The lines of a named declaration, from its own line to the end of its scope.

    Ends at the first line at or below the declaration's indentation that closes
    a brace, which is how every declaration in this tree is written. A dotted
    name is resolved inside its owning type first. Returns None when the name is
    not declared in the file at all.
    """
    lo, hi = 0, len(lines)
    if "." in name:
        owner, name = name.split(".", 1)
        lo, hi = type_scope(lines, owner)

    # The SHALLOWEST declaration of the name in range, not the first. A type's own
    # member is the shallowest occurrence inside it; anything deeper is inside a
    # nested type and belongs to that one. `AuditLog` contains both
    # `Seams.directory` — a lock-guarded stored property at one more level in —
    # and `AuditLog.directory`, the writer that carries the interlock, and the
    # first version took whichever came first in the file. That is `Seams.directory`,
    # whose body holds no predicate, so the gate reported the audit trail's own
    # seam as a writer with no test-process branch. The bug is a false RED, which
    # is the direction that would have been argued away rather than fixed.
    best: tuple[int, int] | None = None
    for i in range(lo, hi):
        m = DECL.match(lines[i])
        if not m or m.group("name") != name:
            continue
        indent = len(m.group("indent"))
        if best is None or indent < best[1]:
            best = (i, indent)
    if best is None:
        return None

    i, indent = best
    body = [lines[i]]
    for j in range(i + 1, hi):
        nxt = lines[j]
        stripped = nxt.strip()
        if stripped and len(nxt) - len(nxt.lstrip()) <= indent and stripped.startswith("}"):
            body.append(nxt)
            break
        body.append(nxt)
    return i + 1, body


def run_census(root: Path, manifest: dict) -> list[str]:
    known = {(e["file"], e["declaration"]) for e in manifest["entries"]}
    spellings: dict[str, dict[str, set[str]]] = {}

    def unclassed(file: str, decl: str, qualified: str) -> bool:
        # Either spelling satisfies the entry, but a BARE entry only where the
        # bare name is unambiguous in its file. `PolicyStore.swift` declares
        # `directory` three times, so that one is classed as `AuditLog.directory`;
        # and a second declaration of a name a bare entry already covers refuses
        # both sites rather than being absorbed by the entry.
        if (file, qualified) in known:
            return False
        if (file, decl) not in known:
            return True
        if file not in spellings:
            spellings[file] = qualified_declarations((root / file).read_text().splitlines())
        return len(spellings[file].get(decl, {decl})) > 1

    findings = []
    for file, line, decl, qualified, text in census_sites(root, manifest["root_literal"]):
        if unclassed(file, decl, qualified):
            findings.append(
                f"{file}:{line}: `{qualified}` names a path under the operator's root and is not "
                f"classed in scripts/campaign/operator_paths.json — {text}"
            )
    for file, line, decl, qualified, text in composed_sites(root, manifest):
        if unclassed(file, decl, qualified):
            findings.append(
                f"{file}:{line}: `{qualified}` hands the operator's own home to a path builder "
                f"and is not classed in scripts/campaign/operator_paths.json — {text}"
            )
    return findings


def run_seams(root: Path, manifest: dict) -> list[str]:
    predicates = manifest["predicates"]
    findings = []
    source_text = {p: p.read_text() for p in swift_sources(root)}

    for entry in manifest["entries"]:
        file, decl, kind = entry["file"], entry["declaration"], entry["class"]
        if not entry.get("reason", "").strip():
            findings.append(f"{file}: `{decl}` carries no reason for its `{kind}` classification")
        path = root / file
        if not path.exists():
            findings.append(f"{file}: classed `{decl}` but the file is gone")
            continue
        lines = path.read_text().splitlines()

        if kind == "operator-accessor":
            seam = entry.get("seamed_by")
            if not seam:
                findings.append(f"{file}: `{decl}` is classed operator-accessor with no `seamed_by`")
                continue
            found = declaration_body(lines, seam)
            if not found:
                findings.append(f"{file}: `{decl}` names `{seam}` as its seam, which is not declared here")
                continue
            _, body = found
            body_text = code_only(body)
            if not any(p in body_text for p in predicates):
                findings.append(
                    f"{file}: `{seam}` is the seam over `{decl}` and carries none of "
                    f"{predicates} — an operator path with no test-process branch"
                )
            elif decl.split(".")[-1] not in body_text:
                findings.append(
                    f"{file}: `{seam}` guards a test process but never returns `{decl}`, "
                    f"so production no longer resolves the operator's own path"
                )
            # Nothing else in Sources/ may reach the truthful accessor directly,
            # and the rule reads two ways round.
            bare = decl.split(".")[-1]
            owner = accessor_owner(lines, decl)
            qualified_reach = (re.compile(rf"\b{re.escape(owner)}\s*\.\s*{re.escape(bare)}\b")
                               if owner else None)
            for other, text in source_text.items():
                rel = str(other.relative_to(root))
                if rel == file:
                    continue
                other_lines = text.splitlines()
                # A file that declares the same name may mean its OWN, and this
                # tree has two: `PolicyStore.operatorDirectory` and
                # `FlowStore.operatorDirectory` are different paths spelled alike.
                # So a bare reach is excused there — but only a bare one. Skipping
                # the whole file, which is what this did first, let a
                # `Bypass.swift` declaring any member named `operatorURL` call
                # `SwitchStore.operatorURL` around its seam and pass.
                declares_bare = declaration_body(other_lines, bare) is not None
                for i, line in enumerate(other_lines):
                    if line.lstrip().startswith("//"):
                        continue
                    if qualified_reach and qualified_reach.search(line):
                        findings.append(
                            f"{rel}:{i + 1}: reaches `{owner}.{bare}`, the truthful operator "
                            f"path declared in {file}, around its seam `{seam}`"
                        )
                    elif not declares_bare and re.search(rf"\b{re.escape(bare)}\b", line):
                        findings.append(
                            f"{rel}:{i + 1}: reaches `{bare}`, the truthful operator path "
                            f"declared in {file}, around its seam `{seam}`"
                        )

        elif kind == "writer-seam":
            found = declaration_body(lines, decl)
            if not found:
                findings.append(f"{file}: `{decl}` is classed writer-seam and is not declared here")
                continue
            _, body = found
            if not any(p in code_only(body) for p in predicates):
                findings.append(
                    f"{file}: `{decl}` is classed writer-seam and carries none of "
                    f"{predicates} — a writer with no test-process branch"
                )

        elif kind == "parameterised":
            parameter = entry.get("parameter")
            found = declaration_body(lines, decl)
            if not parameter:
                findings.append(f"{file}: `{decl}` is classed parameterised with no `parameter`")
            elif not found:
                findings.append(f"{file}: `{decl}` is classed parameterised and is not declared here")
            elif f"{parameter}:" not in found[1][0]:
                findings.append(
                    f"{file}: `{decl}` is classed parameterised on `{parameter}`, which is "
                    f"not in its signature: {found[1][0].strip()}"
                )

        elif kind not in ("socket", "prose"):
            findings.append(f"{file}: `{decl}` carries the unknown class `{kind}`")

    for name, guard in manifest.get("guards", {}).items():
        tree = root / guard["tree"]
        forbidden = guard["forbidden"]
        for path in sorted(tree.rglob("*.swift")):
            for i, line in enumerate(path.read_text().splitlines()):
                if line.lstrip().startswith("//"):
                    continue
                if forbidden in line:
                    findings.append(
                        f"{path.relative_to(root)}:{i + 1}: guard `{name}` — `{forbidden}` "
                        f"is refused under {guard['tree']}/: {guard['reason']}"
                    )
    return findings


def main(argv: list[str]) -> int:
    mode = argv[1] if len(argv) > 1 else "all"
    if mode not in ("all", "census", "seams"):
        print(f"unknown mode {mode!r}; expected `census`, `seams` or no argument")
        return 2
    root = repo_root()
    manifest = load_manifest(root)

    findings: list[str] = []
    if mode in ("all", "census"):
        findings += run_census(root, manifest)
    if mode in ("all", "seams"):
        findings += run_seams(root, manifest)

    if findings:
        print(f"operator_path_gate: {len(findings)} finding(s)")
        for f in findings:
            print(f"  {f}")
        return 1

    literal = len(census_sites(root, manifest["root_literal"]))
    composed = len(composed_sites(root, manifest))
    print(
        f"operator_path_gate: no findings "
        f"({literal} literal + {composed} composed = {literal + composed} operator-path "
        f"site(s) in Sources/, {len(manifest['entries'])} entries classed)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
