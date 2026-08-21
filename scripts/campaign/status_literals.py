#!/usr/bin/env python3
"""PRO-0066 A2, made runnable: no user-facing string literal in a status-window view file.

The clause reads *every user-facing string comes from `StatusSurface`; a grep for a
quoted string literal in `MainWindow.swift` outside an identifier returns nothing.*
"Outside an identifier" is the part a plain `grep` cannot decide, so this decides it
**by syntactic position and never by reading the string**, which is what keeps the
answer mechanical:

  symbol       an SF Symbol asset name  — `systemName:`, `systemImage:`, `icon:`
  system       a path, argv word, URL, sysctl name, window id, launchd label
  key          a `case "…":` label or a `== "…"` comparison against a wire value
  punctuation  a literal with no letter in it at all — "", ", ", "\n"
  display      everything else

`display` is the violation bucket and the classifier is **default-deny**: a literal
whose position matches none of the four identifier constructs is a violation. A
positive "does it look like prose" rule would silently pass every rendering
construct nobody thought to list; this one fails closed instead, so the way to
green is to move the string to `StatusSurface.Copy` rather than to widen a list.

All five counts are printed on every run, so the clause's denominator is visible
rather than implied.

    python3 scripts/campaign/status_literals.py Sources/ProctorUI/MainWindow.swift
    python3 scripts/campaign/status_literals.py --dump <file>     every literal + bucket
    python3 scripts/campaign/status_literals.py --json <file>

Exit 0 when `display` is 0.
"""

import json
import re
import sys

SYMBOL_LABELS = {"systemName", "systemImage", "icon"}

# Constructs whose string argument addresses the machine rather than the reader.
SYSTEM_LABELS = {"fileURLWithPath", "forAuxiliaryExecutable", "id"}
SYSTEM_CALLEES = {"URL", "sysctlbyname", "launchctl", "openWindow", "arguments",
                  "appendingPathComponent", "setenv", "removeItem"}
# An array literal's own governing prefix, for argv built inline.
SYSTEM_ARRAY_PREFIX = re.compile(r"(?:arguments|argv)\s*=\s*$")

# Separators and joiners. Anything not made of these is capable of being read.
PUNCTUATION_ONLY = re.compile(r"[\s,;:.·/\\|_()\[\]{}<>+*=&%#@!?'\"-]*")

BUCKETS = ("display", "symbol", "system", "key", "punctuation", "interpolated")

CASE_PREFIX = re.compile(r"\bcase\b(?:\s*\"(?:[^\"\\]|\\.)*\"\s*,)*\s*$")
COMPARE_PREFIX = re.compile(r"(?:==|!=)\s*$")
IDENT_TAIL = re.compile(r"[A-Za-z_][A-Za-z0-9_]*$")
LABEL_SCAN = re.compile(r"\b([A-Za-z_][A-Za-z0-9_]*)\s*:\s*$")


def literals(src):
    """Every Swift string literal in `src` as (start, end, text), comments skipped.

    Interpolation segments are stepped over rather than descended into, so a
    literal nested inside `\\(...)` is not reported twice.
    """
    out, i, n = [], 0, len(src)
    while i < n:
        c = src[i]
        if c == "/" and src[i + 1:i + 2] == "/":
            j = src.find("\n", i)
            i = n if j < 0 else j + 1
            continue
        if c == "/" and src[i + 1:i + 2] == "*":
            j = src.find("*/", i + 2)
            i = n if j < 0 else j + 2
            continue
        if src[i:i + 2] == '#"':
            j = src.find('"#', i + 2)
            end = (j + 2) if j >= 0 else n
            out.append((i, end, src[i:end]))
            i = end
            continue
        if src[i:i + 3] == '"""':
            j = src.find('"""', i + 3)
            end = (j + 3) if j >= 0 else n
            out.append((i, end, src[i:end]))
            i = end
            continue
        if c == '"':
            j = i + 1
            while j < n:
                if src[j] == "\\":
                    if src[j + 1:j + 2] == "(":
                        k, d = j + 2, 1
                        while k < n and d:
                            if src[k] == "(":
                                d += 1
                            elif src[k] == ")":
                                d -= 1
                            elif src[k] == '"':
                                m = k + 1
                                while m < n and src[m] != '"':
                                    m += 2 if src[m] == "\\" else 1
                                k = m
                            k += 1
                        j = k
                        continue
                    j += 2
                    continue
                if src[j] == '"' or src[j] == "\n":
                    break
                j += 1
            end = j + 1
            out.append((i, end, src[i:end]))
            i = end
            continue
        i += 1
    return out


def _walk_back(src, start, ends):
    """The nearest enclosing unbalanced opener before `start`, skipping literals."""
    i, depth = start - 1, 0
    while i >= 0:
        c = src[i]
        if i + 1 in ends:
            i = ends[i + 1] - 1
            continue
        if c in ")]}":
            depth += 1
        elif c in "([{":
            if depth == 0:
                return i, c
            depth -= 1
        i -= 1
    return -1, None


def governing(src, start, ends):
    """(callee, label, opener, prefix) for the construct the literal sits inside."""
    i, opener = _walk_back(src, start, ends)
    while True:
        if i < 0:
            return "", "", None, src[max(0, start - 40):start]
        prefix = src[max(0, i - 60):i].rstrip()
        if opener == "(":
            m = IDENT_TAIL.search(prefix)
            callee = m.group(0) if m else ""
            if not callee:
                # A grouping paren — the governing construct is further out.
                i, opener = _walk_back(src, i, ends)
                continue
            # The argument label immediately preceding this literal, at depth 0.
            # Literal bodies are blanked first: a colon inside prose ("Mac app:
            # read what…") is not an argument label, and reading one out of a
            # string is how a classifier starts describing the copy it is
            # supposed to be positioned against.
            inner = list(src[i + 1:start])
            for le, ls in ends.items():
                if ls > i and le <= start:
                    for k in range(ls - i - 1, min(le - i - 1, len(inner))):
                        inner[k] = " "
            inner, label, d = "".join(inner), "", 0
            for tok in re.finditer(r"[()\[\]{}]|\b[A-Za-z_][A-Za-z0-9_]*\s*:", inner):
                t = tok.group(0)
                if t in "([{":
                    d += 1
                elif t in ")]}":
                    d -= 1
                elif d == 0:
                    label = t.rstrip().rstrip(":").strip()
            return callee, label, "(", prefix
        if opener == "[":
            outer_callee, outer_label, _, outer_prefix = governing(src, i, ends)
            if SYSTEM_ARRAY_PREFIX.search(prefix):
                return "arguments", "", "[", prefix
            return outer_callee, outer_label, "[", outer_prefix
        return "", "", opener, prefix


def classify(src, s, e, text, ends):
    prefix = src[max(0, s - 60):s].rstrip()
    # An interpolation segment is code and an escape is a control character, so
    # neither is copy: `"\n"` is a newline and `"\(count)"` is a number. Testing
    # the raw source text instead reads the `n` of `\n` as a word.
    stripped = re.sub(r"\\\((?:[^()]|\([^()]*\))*\)", "", text)
    interpolated = stripped != text
    body = re.sub(r"\\.", "", stripped).strip('"#')
    # An out-of-family review of this classifier named the hole: "no ASCII
    # letter" would pass a literal that is entirely glyphs — an arrow, a bullet,
    # a chevron — and those are read. So the rule is an allowlist of separator
    # characters rather than a denylist of letters, and anything outside it
    # falls through to the buckets below.
    if PUNCTUATION_ONLY.fullmatch(body):
        # Named separately from punctuation because the two hide different
        # things. A literal that is nothing but an interpolation renders whatever
        # the expression evaluates to, and this classifier cannot see that value;
        # it is reported as its own bucket rather than folded into "no words",
        # so the count of strings nobody has read stays visible.
        return ("interpolated" if interpolated and not body else "punctuation"), "no words"
    if CASE_PREFIX.search(prefix):
        return "key", "switch case label"
    if COMPARE_PREFIX.search(prefix):
        return "key", "equality comparison"
    callee, label, opener, _ = governing(src, s, ends)
    if label in SYMBOL_LABELS:
        return "symbol", f"{label}:"
    if label in SYSTEM_LABELS or callee in SYSTEM_CALLEES:
        return "system", f"{callee}({label + ':' if label else ''})"
    return "display", f"{callee or '<none>'}({label + ':' if label else ''})"


def baseline_check(path, rows, baseline_path):
    """Every non-display literal the snapshot names is still in the file.

    An out-of-family review of this instrument found the hole this closes: a
    printed count is not a threshold. `display 0` stays green if the file is
    emptied into a second file, and it stays green if one identifier is deleted
    while another is added, because a count collides where a set does not. So
    the identifier set is committed and compared as a set, and a literal that
    left the file has to be accounted for in the diff rather than absorbed.
    """
    with open(baseline_path) as fh:
        recorded = json.load(fh)
    have = {}
    for r in rows:
        if r["bucket"] != "display":
            have.setdefault((r["bucket"], r["text"]), 0)
            have[(r["bucket"], r["text"])] += 1
    want = {}
    for r in recorded["identifiers"]:
        want.setdefault((r["bucket"], r["text"]), 0)
        want[(r["bucket"], r["text"])] += r.get("count", 1)
    missing = [f"{b}: {t}  (x{n - have.get((b, t), 0)})"
               for (b, t), n in sorted(want.items()) if have.get((b, t), 0) < n]
    added = [f"{b}: {t}" for (b, t), n in sorted(have.items()) if want.get((b, t), 0) < n]
    return missing, added


def run(path, dump=False, as_json=False, baseline=None, write_baseline=None):
    src = open(path).read()
    lits = literals(src)
    ends = {e: s for s, e, _ in lits}
    rows = []
    for s, e, text in lits:
        bucket, why = classify(src, s, e, text, ends)
        rows.append({"line": src.count("\n", 0, s) + 1, "bucket": bucket,
                     "why": why, "text": text[:90]})
    counts = {b: sum(1 for r in rows if r["bucket"] == b) for b in BUCKETS}
    total = len(rows)
    if write_baseline:
        seen = {}
        for r in rows:
            if r["bucket"] != "display":
                seen.setdefault((r["bucket"], r["text"]), 0)
                seen[(r["bucket"], r["text"])] += 1
        with open(write_baseline, "w") as fh:
            json.dump({"file": path, "total": total, "counts": counts,
                       "identifiers": [{"bucket": b, "text": t, "count": n}
                                       for (b, t), n in sorted(seen.items())]},
                      fh, indent=2)
        print(f"wrote {write_baseline}: {sum(seen.values())} identifier literals")
        return 0
    if as_json:
        print(json.dumps({"file": path, "total": total, "counts": counts,
                          "violations": [r for r in rows if r["bucket"] == "display"]},
                         indent=2))
    else:
        print(f"{path}: {total} string literals examined")
        for b in BUCKETS:
            print(f"  {b:12s} {counts[b]:4d}")
        if dump:
            for r in rows:
                print(f"  {r['line']:5d} {r['bucket']:12s} {r['why']:34s} {r['text']}")
        else:
            for r in rows:
                if r["bucket"] == "display":
                    print(f"  VIOLATION {r['line']:5d} {r['why']:34s} {r['text']}")
        print()
        if baseline:
            missing, added = baseline_check(path, rows, baseline)
            print(f"  baseline {baseline}: "
                  f"{len(missing)} identifier(s) gone, {len(added)} new")
            for m in missing:
                print(f"  GONE      {m}")
            for a in added:
                print(f"  NEW       {a}")
            if missing:
                print()
                print(f"FAIL: {len(missing)} identifier literal(s) left "
                      f"{path} without being accounted for. The clause is about "
                      "moving the copy out, not the machinery.")
                return 1
        if counts["display"]:
            print(f"FAIL: {counts['display']} user-facing literal(s) of {total} examined. "
                  "Move them to StatusSurface.Copy.")
        else:
            print(f"PASS: 0 user-facing literals of {total} examined; "
                  f"{total - counts['display']} are identifiers, symbols, "
                  "system strings or punctuation.")
    return 1 if counts["display"] else 0


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    flags = {a for a in sys.argv[1:] if a.startswith("--")}
    if not args:
        print(__doc__)
        sys.exit(2)
    baseline = next((a.split("=", 1)[1] for a in flags if a.startswith("--baseline=")), None)
    write = next((a.split("=", 1)[1] for a in flags if a.startswith("--write-baseline=")), None)
    rc = 0
    for p in args:
        rc |= run(p, dump="--dump" in flags, as_json="--json" in flags,
                  baseline=baseline, write_baseline=write)
    sys.exit(rc)
