# Trawl — tailings pass over Wave 27, 2026-08-25

Source: `tailings/PASS-2026-08-25-wave-27.md`. Four contradicted rows, one
unbacked, one not-checked, plus one fault the pass found in a gate written the
same wave and one it committed itself.

## Kept

- **idea-01: an `armedBy` claim nobody checks** → brief 145, `proposed-by-ai: false`.
  From A100. `CASE-0808` named a test as its arm and that test passes with the
  fix removed. 495 cases carry an `armedBy` string and nothing reads one. The
  generalisation is the feature: an arming claim is checkable by construction —
  remove the thing, run the named test, expect red.
- **idea-02: a provenance gate that reads the number and not the word** → brief 146,
  `proposed-by-ai: false`. From the suite-verdict fault. `claim_provenance.py`
  matched `275 suites` in a line saying the run FAILED.
- **idea-03: a gate that loses which of its checks failed** → brief 147,
  `proposed-by-ai: false`. From the unbacked row. `test_instruments.py` reported
  361/1 once and 362/0 three times, and the failing check could not be named
  because the line had scrolled.
- **idea-04: nothing counts the ledger's status words** → brief 148,
  `proposed-by-ai: false`. From A278/A279. "152 of 152 Merged" over 150 Merged
  and 2 Retired, with `ledger_gate.py` green either way.
- **idea-05: an external probe cannot find the capture store** → brief 149,
  `proposed-by-ai: false`. From A277 and the standing R4. Declaring
  `captureRoots` served this repository's instruments and not anybody else's.
- **idea-06: an auditor clearing its own gate** → brief 150, `proposed-by-ai: true`.
  Second-order, and from this pass's own conduct rather than from a probe: it
  reclassified four contradicted rows to `substantiated` after correcting the
  record, which cleared the gate, and had to undo it. Where one actor both
  classifies and is judged, a reclassification needs a record.

## Dropped, with the reason

- **A settings surface for the gates.** Every instrument here is a script with
  flags. Adding configuration would be building for an audience that has not
  asked and cannot be observed.
- **An evidence-page freshness check.** Real, and it is idea-02 wearing a
  different hat: the suite-verdict page was stale *and* misread, and one gate
  reading verdict words closes both. Two briefs would compete over one fix.
- **Onboarding for the campaign scripts.** The standard companion feature, and
  the audience is one person who wrote them.
- **Notifications when a ratchet moves.** The ratchets already print their own
  movement and refuse to be raised silently. A notifier would restate that.
- **Re-running the whole prior-pass worklist.** 329 rows were waived by window.
  Re-mining them is what this skill exists not to do.
