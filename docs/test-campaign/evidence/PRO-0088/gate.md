# PRO-0088 — what `./scripts/test.sh` reported, and what it was red against

The script owns the verdict. Its output went to a file and the exit code was read back off the
script; nothing here was read from the left of a pipe.

| Run | Result | Exit | Transcript |
|---|---|---|---|
| Before | `Test run with 1862 tests in 220 suites passed after 5.123 seconds.` | 0 | `gate-before.txt` |
| After | `Test run with 1874 tests in 222 suites passed after 8.841 seconds.` | 0 | `gate-after.txt` |
| Sabotage | `Test run with 1874 tests in 222 suites failed after 7.895 seconds with 2 issues.` | 1 | `gate-sabotage.txt` |
| Final | `Test run with 1875 tests in 222 suites passed after 18.709 seconds.` | 0 | `gate-final.txt` |

**+13 tests, +2 suites, 1862 to 1875.** `Frame content gate` (5) and `Capture content instrument`
(8) — the eighth is the pixel-format test the out-of-family review's Medium finding added after the
`gate-after` run, which is why that run reads 1874 and the final one reads 1875.

**What the before run was.** The tree at `4d76b3c` plus `Sources/ProctorCore/FrameContent.swift`,
which was already written when it started and which contributes no tests — SwiftPM had already
planned the build, so neither new test file was in it. Checked rather than assumed:
`grep -c 'Frame content gate\|Capture content instrument' gate-before.txt` returns 0.

## What the sabotage was

Two edits, both reverted, run through the same script:

1. `CaptureEngineImpl.swift` — the term `&& contentVerdict == .content` deleted from the
   `trustworthy` expression, leaving the pre-PRO-0088 verdict.
2. `CursorOverlay.swift` — one `Self.place(surface.panel, at: Self.inPlaneLevel)` put back as a
   direct `surface.panel.level = Self.inPlaneLevel`.

Exactly two tests went red, one per edit, and the run exited 1:

```
􀢄  Test "the capture verdict conjoins the content gate" failed after 1.830 seconds with 1 issue.
􀢄  Test "the drawn pointer assigns sharingType everywhere it assigns level" failed after 1.830 seconds with 1 issue.
􀢄  Test run with 1874 tests in 222 suites failed after 7.895 seconds with 2 issues.
```

Both are source analysis. They establish that the code the unit tests drive is the code that runs;
they buy no evidence about a real capture or a real window server. That is CASE-0128 and CASE-0129,
on glass.
