---
sources: [DEF-218, DEF-219, DEF-220, DEF-221, DEF-222, DEF-223, DEF-224, DEF-225]
status: retired
validated-by: REQ-111, REQ-112, REQ-113 via CASE-0472, CASE-0473, CASE-0474, CASE-0475, CASE-0476, CASE-0477
validated-rungs: outcome
validated-provider: none
validated-through-defect: REQ-112 via DEF-218; REQ-113 via DEF-221; REQ-111 via DEF-224
---
# Reconcile thirty-five captures with their cases and manifest

**Wave 18, brief 1.** DEF-218, DEF-219, DEF-220, DEF-221, DEF-222, DEF-223, DEF-224, DEF-225.
The follow-up work orders from PRO-0107.

## What needs doing

PRO-0107 established the dispositions and proved that `target` cannot be fabricated after the fact.
This brief executes the recapture and citation repair so the files on disk and the cases that cite them
agree with the manifest:

1. **DEF-218:** Nine app-icon renders (`surf-001` .. `surf-016`) renamed so filenames match what they depict, or duplicates deleted.
2. **DEF-219:** Three empty takeover-shield frames replaced with real captures or deleted.
3. **DEF-220:** `docs/test-campaign/evidence/sweepK-scaling.json` reconciled with disk.
4. **DEF-221:** One image carrying three captions across sweeps given a genuine re-take (1,046-pixel delta).
5. **DEF-222:** `docs/test-campaign/evidence/shots/sweepL-status-agent-down.png` replaced with a frame showing the Agent-down pill.
6. **DEF-223:** Surface prefixes corrected to match what pictures actually show.
7. **DEF-224:** Five unpublished-capture citations in `docs/test-campaign/cases.json` repointed or recaptured via `scripts/campaign/capture_with_manifest.py`.
8. **DEF-225:** CASE-0100 citation pointed at published `step-a3-walkthrough-primary-disabled.png`.
