#!/usr/bin/env python3
"""Spec-symbol citation linter — resolve what a spec names against the code.

A spec that cites `ContentionSample.automationMode` reads as grounded whether or
not the field exists. Nothing in the pipeline notices a rename: the spec keeps
its citation, the ledger keeps its row, and the first reader to open the file
finds a symbol the tree has not carried for months.

So every backticked identifier in `docs/specs/` is resolved against declarations
found in the production tree, and one that resolves to nothing is reported with
the file and line that wrote it.

Two things this deliberately does not do.

It does not read a citation out of prose. Only backticked spans count, because a
spec's prose says "the contention monitor" and means a concept, while
`ContentionMonitor` names a thing that either exists or does not. Blanking code
fences first is the same rule one layer down: a fenced block is a quotation,
and quoting a symbol is not citing it.

And it does not fail on the first unresolved citation. A tree this size carries
citations to Foundation, to AppKit, to another repository's script and to types
that were correct when written; failing on all of them at once produces a gate
somebody switches off. It carries a ratchet instead, the way `strict-check.py`
and `capture-lineage.py` do: the count may fall and may not rise.

  spec_symbol_linter.py [--specs DIR] [--source DIR] [--gate] [--set-ratchet N]
                        [--json PATH]
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RATCHET = ROOT / "docs" / "test-campaign" / "spec-symbol-ratchet.json"

# A declaration site in Swift. `case` is here for enum cases, which specs cite
# constantly and which no other pattern catches.
DECL = re.compile(
    r"^\s*(?:@\w+\s+)*(?:public|internal|private|fileprivate|open|package)?\s*"
    r"(?:final\s+|static\s+|class\s+|mutating\s+|nonisolated\s+|override\s+)*"
    r"\b(class|struct|enum|protocol|actor|extension|func|var|let|case|typealias|init)\b"
    r"\s+([A-Za-z_]\w*)")

# What counts as a citation: a backticked span that looks like a Swift name
# rather than a sentence, a path, or a shell command.
CITE = re.compile(r"`([^`\n]{2,80})`")
SYMBOLISH = re.compile(r"^[A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*(?:\([^)]*\))?$")

# Spans that are citations of something else and are resolved elsewhere: file
# paths have their own check in spec_citation_measure.py, and a shell word is
# not a symbol.
NOT_A_SYMBOL = re.compile(r"[/\\ ]|\.(?:md|py|swift|json|sh|txt|png|html|toml|yml|yaml)$")

# Two whole families are citations of something real that this index cannot
# answer for, and reporting them drowns the one finding that matters.
#
# snake_case is not Swift. `openai_computer`, `mouse_move` and `proctor_menu`
# are wire names — MCP tool ids and CUA action strings — and the count of
# proctor_* names against ToolCatalogue.all is already skill_doc_measure.py's
# job. Swift declares lowerCamelCase and UpperCamelCase and nothing else, so an
# underscore inside a span is positive evidence that it is not a Swift symbol.
WIRE_NAME = re.compile(r"\w_\w")

# And a platform constant is grounded by the framework rather than by this tree.
# `AXMenuBar`, `kAXFocusedAttribute`, `kCGWindowNumber` and the SC* family all
# exist; none is declared in Sources/, and a linter that calls them missing is
# a linter somebody adds to .gitignore.
PLATFORM = re.compile(r"^(?:k?AX|kCG|kCF|SC[A-Z]|CF[A-Z]|OS[A-Z]|VN[A-Z]|NS[A-Z])")

# Names the language and the platform supply. A spec citing `String` is grounded
# by Swift itself, and reporting it as unresolved is how a linter earns its way
# into a `.gitignore`.
BUILTIN = {
    "String", "Int", "Int32", "Int64", "UInt", "UInt8", "UInt32", "Double", "Float",
    "Bool", "Data", "Date", "URL", "UUID", "Array", "Dictionary", "Set", "Optional",
    "Result", "Error", "Task", "Codable", "Encodable", "Decodable", "Sendable",
    "Equatable", "Hashable", "Comparable", "CaseIterable", "Identifiable",
    "FileManager", "JSONEncoder", "JSONDecoder", "JSONSerialization", "Process",
    "Pipe", "Bundle", "Notification", "Timer", "DispatchQueue", "OSLog", "Logger",
    "NSObject", "NSApp", "NSMenu", "NSMenuItem", "NSWindow", "NSView", "NSImage",
    "NSColor", "NSScreen", "NSWorkspace", "NSException", "NSRunningApplication",
    "View", "Text", "Button", "Toggle", "Image", "VStack", "HStack", "ZStack",
    "State", "Binding", "ObservableObject", "Published", "EnvironmentObject",
    "CGRect", "CGSize", "CGPoint", "CGFloat", "CGImage", "CGEvent", "CGEventTap",
    "CGWindowListCopyWindowInfo", "CGEventPost", "AXUIElement", "AXError",
    "SCStream", "SCFrameStatus", "SCShareableContent", "SCWindow",
    "VNRecognizeTextRequest", "VNImageRequestHandler", "CryptoKit", "SHA256",
    "HMAC", "AES", "SymmetricKey", "true", "false", "nil", "self", "Self",
}


def source_symbols(source: Path) -> dict[str, set[str]]:
    """Every declared name in the production tree, mapped to the files declaring it."""
    index: dict[str, set[str]] = {}
    for f in sorted(source.rglob("*.swift")):
        try:
            lines = f.read_text(errors="replace").splitlines()
        except OSError:
            continue
        rel = str(f.relative_to(ROOT))
        for ln in lines:
            m = DECL.match(ln)
            if m:
                index.setdefault(m.group(2), set()).add(rel)
    return index


# A wire key is grounded by the code that writes it, not by a declaration.
# `idempotentHint` is a string the shim puts into an MCP annotations object and
# `fsRoots` names an environment variable; both exist, neither is declared, and
# a spec citing one is citing something real. So string literals in the
# production tree are a second index, reported apart from declarations because
# "the code writes this string" is a weaker claim than "the code declares this".
LITERAL = re.compile(r'"([A-Za-z_][\w.]{1,60})"')


def source_literals(source: Path) -> set[str]:
    out: set[str] = set()
    for f in source.rglob("*.swift"):
        try:
            out.update(LITERAL.findall(f.read_text(errors="replace")))
        except OSError:
            continue
    return out


def module_names(root: Path) -> set[str]:
    """Target names from Package.swift — a spec citing `ProctorCore` cites a module."""
    try:
        return set(re.findall(r'name:\s*"([A-Za-z][\w]*)"',
                              (root / "Package.swift").read_text()))
    except OSError:
        return set()


def blank_fences(text: str) -> str:
    """Blank fenced blocks so a quoted symbol is not read as a citation."""
    out, fenced = [], False
    for ln in text.splitlines():
        if ln.lstrip().startswith("```"):
            fenced = not fenced
            out.append("")
            continue
        out.append("" if fenced else ln)
    return "\n".join(out)


def citations(path: Path) -> list[tuple[int, str]]:
    found = []
    for i, ln in enumerate(blank_fences(path.read_text(errors="replace")).splitlines(), 1):
        for span in CITE.findall(ln):
            s = span.strip()
            if NOT_A_SYMBOL.search(s) or not SYMBOLISH.match(s):
                continue
            if WIRE_NAME.search(s):
                continue
            found.append((i, s))
    return found


def head(symbol: str) -> str:
    """The part a declaration index can answer for: `A.b(c:)` resolves on `A`."""
    return symbol.split("(")[0].split(".")[0]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--specs", type=Path, default=ROOT / "docs" / "specs")
    ap.add_argument("--source", type=Path, default=ROOT / "Sources")
    # A spec cites its own acceptance tests by name, and those are declared in
    # Tests/ rather than Sources/. Resolving them against the wrong root reports
    # a grounded citation as missing, so the two roots are counted apart: a
    # production symbol and a test symbol are different claims about a spec.
    ap.add_argument("--tests", type=Path, default=ROOT / "Tests")
    ap.add_argument("--gate", action="store_true")
    ap.add_argument("--set-ratchet", type=int, default=None)
    ap.add_argument("--json", type=Path, default=None)
    a = ap.parse_args()

    index = source_symbols(a.source)
    test_index = source_symbols(a.tests) if a.tests.is_dir() else {}
    literals = source_literals(a.source) | module_names(ROOT)
    specs = sorted(a.specs.glob("spec-*.md"))
    rows, unresolved = [], []
    cited_total = resolved_total = in_tests_total = 0

    for spec in specs:
        cites = citations(spec)
        res, in_tests, unres = 0, 0, []
        for line, sym in cites:
            h = head(sym)
            if h in BUILTIN or h in index or PLATFORM.match(h) or h in literals:
                res += 1
            elif h in test_index:
                in_tests += 1
            else:
                unres.append({"line": line, "symbol": sym,
                              "spec": str(spec.relative_to(ROOT))})
        cited_total += len(cites)
        resolved_total += res
        in_tests_total += in_tests
        unresolved.extend(unres)
        rows.append({"spec": spec.name, "cited": len(cites), "resolved": res,
                     "inTests": in_tests, "unresolved": len(unres)})

    pct = (100.0 * resolved_total / cited_total) if cited_total else 100.0
    print(f"{len(specs)} spec(s) · {cited_total} symbol citation(s) · "
          f"{resolved_total} in production ({pct:.1f}% of {cited_total}) · "
          f"{in_tests_total} in tests · {len(unresolved)} unresolved")
    print(f"index: {len(index)} production name(s) across "
          f"{len(list(a.source.rglob('*.swift')))} file(s) under {a.source.name}/ · "
          f"{len(test_index)} test name(s) under {a.tests.name}/ · "
          f"{len(literals)} string literal(s) and module name(s)")

    worst = sorted((r for r in rows if r["unresolved"]),
                   key=lambda r: -r["unresolved"])[:8]
    if worst:
        print("\nspecs carrying the most unresolved citations:")
        for r in worst:
            print(f"  {r['spec']:<24} {r['unresolved']:>3} of {r['cited']:>3}")
        print("\nfirst twelve, line-anchored:")
        for u in unresolved[:12]:
            print(f"  {u['spec']}:{u['line']}  `{u['symbol']}`")

    if a.json:
        a.json.write_text(json.dumps(
            {"specs": len(specs), "cited": cited_total, "resolved": resolved_total,
             "inTests": in_tests_total, "unresolved": unresolved, "rows": rows},
            indent=2) + "\n")
        print(f"\nwrote {a.json}")

    if a.set_ratchet is not None:
        RATCHET.write_text(json.dumps({"unresolved": a.set_ratchet}, indent=2) + "\n")
        print(f"\nratchet set to {a.set_ratchet}")
        return 0

    if a.gate:
        try:
            bar = json.loads(RATCHET.read_text())["unresolved"]
        except (OSError, json.JSONDecodeError, KeyError):
            print("\nno ratchet on disk. Set one with --set-ratchet <n>; a first run "
                  "with no bar cannot say whether the count rose.")
            return 1
        print(f"\nratchet: {bar} unresolved allowed")
        if len(unresolved) > bar:
            print(f"FAIL  unresolved rose from {bar} to {len(unresolved)} — a spec is "
                  f"naming a symbol the tree does not declare.")
            for u in unresolved[:6]:
                print(f"      {u['spec']}:{u['line']}  `{u['symbol']}`")
            return 1
        if len(unresolved) < bar:
            print(f"unresolved FELL from {bar} to {len(unresolved)} — lower the ratchet "
                  f"with --set-ratchet in the same commit, so it cannot climb back.")
            return 0
        print("held.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
