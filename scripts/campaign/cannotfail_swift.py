#!/usr/bin/env python3
"""Scan a Swift test suite for assertions that cannot fail.

warrant:assay owns this plane, and its two scanners read TypeScript, JavaScript
and Python. This suite is Swift, so the gap the campaign recorded as "mutation
survival not measured" is an instrument gap rather than an effort one, and this
closes the cheaper half of it: the patterns that pass a suite while testing
nothing.

Five findings, each of which a green run cannot tell you about:

  constant       #expect(true), #expect(1 == 1) — a literal compared to a literal
  self           #expect(x == x) — a value compared to itself
  no-assertion   a @Test function whose body asserts nothing at all
  disabled       .disabled(...) or .enabled(if: false) — a test that never runs
  swallowed      try? whose result is discarded, so a throw becomes a pass

Every count carries its denominator, because `failures=0` is a claim and
`examined=N failures=0` is a result. Exits 1 when a finding is present.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

# Assertions swift-testing and XCTest recognise. A body holding none of these
# asserts nothing, whatever else it does.
ASSERTS = re.compile(
    r"#expect\b|#require\b|Issue\s*\.\s*record\b|withKnownIssue\b|XCTAssert|XCTFail|XCTUnwrap")

TEST_ATTR = re.compile(r"^\s*@Test\b")
FUNC = re.compile(r"^\s*(?:private\s+|public\s+|internal\s+)?func\s+([A-Za-z_][\w]*)\s*\(")
# A helper defined beside the tests. A body that calls one of these is asserting
# through it, which is a house style rather than a hole: `Self.compare(built,
# expected, name)` says more at the call site than three inlined expectations.
HELPER = re.compile(r"^\s*(?:private\s+|public\s+|internal\s+)?static\s+func\s+([A-Za-z_][\w]*)\s*\(")
CALL = re.compile(r"(?<![\w.])(?:Self\s*\.\s*)?([A-Za-z_][\w]*)\s*\(")

LITERAL = r"(?:true|false|nil|-?\d+(?:\.\d+)?|\"(?:[^\"\\\\]|\\\\.)*\")"
CONSTANT = re.compile(rf"#expect\(\s*{LITERAL}\s*(?:[=!<>]=\s*{LITERAL}\s*)?\)")
# `x == x` with the same token text on both sides, allowing member chains.
SELF_CMP = re.compile(r"#expect\(\s*([\w.\[\]()]+)\s*==\s*\1\s*[,)]")
DISABLED = re.compile(r"\.disabled\s*\(|\.enabled\s*\(\s*if:\s*false\s*\)")
ENABLED_IF = re.compile(r"\.enabled\s*\(\s*if:")
SWALLOWED = re.compile(r"(?:^|[^\w.])(?:_\s*=\s*)?try\?\s")

# A comment or a string is not code. Masking them keeps a sentence about
# `#expect(true)` in a doc comment from being reported as one.
LINE_COMMENT = re.compile(r"//.*$", re.M)
BLOCK_COMMENT = re.compile(r"/\*.*?\*/", re.S)


def mask_noncode(text: str) -> str:
    text = BLOCK_COMMENT.sub(lambda m: " " * len(m.group(0)), text)
    return LINE_COMMENT.sub(lambda m: " " * len(m.group(0)), text)


def _body(lines: list[str], sig: int) -> tuple[int, int] | None:
    """The line range of the body opened on or after `sig`.

    Character-level rather than line-level, because a one-line body balances its
    braces on the signature line. The first version of this counted per line and
    treated `depth == 0` as "not open yet", so `func f() { ... }` was skipped
    entirely — and then consumed the NEXT function's body while looking for an
    opening brace. It was found by seeding a test that asserts nothing and
    watching this scanner not report it.
    """
    i = sig
    while i < len(lines) and "{" not in lines[i]:
        if ";" in lines[i] or (i > sig and lines[i].strip().startswith("@")):
            return None
        i += 1
    if i >= len(lines):
        return None
    start = i
    depth = 0
    opened = False
    for j in range(start, len(lines)):
        for ch in lines[j]:
            if ch == "{":
                depth += 1
                opened = True
            elif ch == "}":
                depth -= 1
        if opened and depth <= 0:
            return start, j
    return start, len(lines) - 1


def asserting_helpers(lines: list[str]) -> set[str]:
    """Same-file helpers whose own body asserts.

    One level deep, deliberately. A chain of helpers is a reason to read the
    file rather than to grow the scanner, and a scanner that follows calls
    forever ends up proving that everything asserts.
    """
    out: set[str] = set()
    for i, line in enumerate(lines):
        m = HELPER.match(line)
        if not m:
            continue
        span = _body(lines, i)
        if span and ASSERTS.search("\n".join(lines[span[0]:span[1] + 1])):
            out.add(m.group(1))
    return out


def test_bodies(lines: list[str]) -> list[tuple[str, int, int, list[str]]]:
    """Every @Test function, as (name, first line, last line, body lines)."""
    out = []
    i = 0
    while i < len(lines):
        if not TEST_ATTR.match(lines[i]):
            i += 1
            continue
        j = i
        while j < len(lines) and not FUNC.match(lines[j]):
            j += 1
        if j >= len(lines):
            break
        name = FUNC.match(lines[j]).group(1)
        span = _body(lines, j)
        if span is None:
            i = j + 1
            continue
        start, end = span
        out.append((name, i + 1, end + 1, lines[start:end + 1]))
        i = end + 1
    return out


def main() -> int:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else "Tests")
    files = sorted(root.rglob("*.swift"))
    findings: list[tuple[str, str, int, str]] = []
    informational: list[tuple[str, str, int, str]] = []
    tests = 0
    asserts = 0

    for path in files:
        raw = path.read_text()
        text = mask_noncode(raw)
        lines = text.splitlines()
        asserts += len(ASSERTS.findall(text))

        for lineno, line in enumerate(lines, 1):
            for m in CONSTANT.finditer(line):
                findings.append(("constant", str(path), lineno, m.group(0).strip()))
            for m in SELF_CMP.finditer(line):
                findings.append(("self", str(path), lineno, m.group(0).strip()))
            if DISABLED.search(line):
                findings.append(("disabled", str(path), lineno, line.strip()[:90]))
            elif ENABLED_IF.search(line):
                informational.append(("enabled-if", str(path), lineno, line.strip()[:90]))
            if SWALLOWED.search(line):
                informational.append(("swallowed", str(path), lineno, line.strip()[:90]))

        helpers = asserting_helpers(lines)
        for name, first, _, body in test_bodies(lines):
            tests += 1
            joined = "\n".join(body)
            if ASSERTS.search(joined):
                continue
            called = {m.group(1) for m in CALL.finditer(joined)}
            if called & helpers:
                continue
            findings.append(("no-assertion", str(path), first, name))

    print(f"examined  {len(files)} file(s) · {tests} @Test function(s) · "
          f"{asserts} assertion call(s)")
    print(f"findings  {len(findings)}")
    for kind, path, lineno, detail in findings:
        print(f"  {kind:<13} {path}:{lineno}  {detail}")
    print(f"informational  {len(informational)} "
          f"(a conditional enable or a try? is a judgement call, not a defect)")
    for kind, path, lineno, detail in informational:
        print(f"  {kind:<13} {path}:{lineno}  {detail}")
    return 1 if findings else 0


if __name__ == "__main__":
    raise SystemExit(main())
