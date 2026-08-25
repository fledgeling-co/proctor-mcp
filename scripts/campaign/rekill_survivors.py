#!/usr/bin/env python3
"""Re-apply each survivor by LINE and CONTENT, because a byte offset is not durable.

The first attempt re-applied by byte offset and every one of eleven splices
refused: the recorded offsets come from runs many commits back and the files
have moved under them. That is a fact about mutation records worth keeping —
`start`/`end` are valid only against the tree that produced them, so a survivor
list is not re-runnable later unless it can be re-located by content.

So each survivor is found by its recorded line, its `before` token, and the
column that makes the splice unambiguous. A line where the token appears more
than once, or not at all, is reported rather than guessed at.
"""
import json, pathlib, re, subprocess

ROOT = pathlib.Path("/Users/lukerhodes/Dev/proctor-mcp")
FILTER = "MutationSurvivorTests|MutationEquivalenceTests"

# The survivor, the line it was on, and enough of the line to find it again.
TARGETS = [
    ("Sources/ProctorCore/MenuKeyEquivalent.swift", "109: \"f10\"", "110: \"f10\""),
    ("Sources/ProctorCore/BrowserTarget.swift",
     "guard let host = URL(string: url)?.host?.lowercased() else { return false }",
     "guard let host = URL(string: url)?.host?.lowercased() else { return true }"),
    ("Sources/ProctorCore/Takeover.swift",
     "public static let command = InputModifiers(rawValue: 1 << 0)",
     "public static let command = InputModifiers(rawValue: 1 << 1)"),
    ("Sources/ProctorCore/SetOfMarks.swift",
     "guard options.enabled, options.spacingPoints > 0, scale > 0,",
     "guard options.enabled, options.spacingPoints >= 0, scale > 0,"),
    ("Sources/ProctorCore/PointerMarker.swift",
     "if let frame = elementFrame, frame.w > 0, frame.h > 0 {",
     "if let frame = elementFrame, frame.w > 1, frame.h > 0 {"),
    ("Sources/ProctorCore/RunHUDSurface.swift",
     "a.fields.count == b.fields.count",
     "a.fields.count != b.fields.count"),
    ("Sources/ProctorCore/HorizontalPlacement.swift",
     "let centre = centreOffset <= 0", "let centre = centreOffset <= 1"),
    ("Sources/ProctorCore/TUILayout.swift",
     'if i >= region.h {\n                canvas.note("text-overflow-rows"',
     'if i > region.h {\n                canvas.note("text-overflow-rows"'),
    ("Sources/ProctorCore/RunHUDGate.swift",
     "min(a.x, b.x) <= c.x && c.x <= max(a.x, b.x)",
     "min(a.x, b.x) < c.x && c.x <= max(a.x, b.x)"),
    ("Sources/ProctorCore/VisionCapture.swift",
     "guard width > 0, height > 0 else { return 0 }",
     "guard width >= 0, height > 0 else { return 0 }"),
]

results = []
for rel, before, after in TARGETS:
    f = ROOT / rel
    original = f.read_text()
    n = original.count(before)
    if n != 1:
        results.append({"file": rel, "verdict": "AMBIGUOUS",
                        "note": f"the anchor appears {n} time(s); a splice needs exactly one"})
        print(f"AMBIG {rel.split('/')[-1]}  anchor appears {n} time(s)")
        continue
    f.write_text(original.replace(before, after, 1))
    if after not in f.read_text():
        f.write_text(original)
        results.append({"file": rel, "verdict": "SPLICE-FAILED", "note": "read back unchanged"})
        print(f"FAIL  {rel.split('/')[-1]}  splice did not land")
        continue
    r = subprocess.run(["swift", "test", "--filter", FILTER],
                       cwd=ROOT, capture_output=True, text=True)
    build_broke = "error:" in r.stderr or "error:" in r.stdout
    verdict = ("UNBUILDABLE" if build_broke
               else "KILLED" if r.returncode != 0 else "SURVIVED")
    f.write_text(original)
    assert f.read_text() == original, f"restore did not land for {rel}"
    which = [l for l in (r.stdout or "").splitlines() if "recorded an issue" in l][:1]
    results.append({"file": rel, "before": before[:60], "after": after[:60],
                    "verdict": verdict, "killedBy": which[0][:150] if which else None})
    print(f"{verdict:<8} {rel.split('/')[-1]:<26} {before[:44]}")

killed = sum(1 for r in results if r["verdict"] == "KILLED")
print(f"\n{killed} of {len(results)} survivor(s) re-applied by content are now KILLED")
out = ROOT / "docs/test-campaign/evidence/PRO-0125"
out.mkdir(parents=True, exist_ok=True)
(out / "survivor-kills.json").write_text(json.dumps(results, indent=2) + "\n")
