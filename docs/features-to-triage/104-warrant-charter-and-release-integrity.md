---
sources: [REQ-165, REQ-166, REQ-167, DEF-290]
status: retired
---
# Formalize warrant charter and release gate integration

**Wave 19, brief 2.**

## What and why

The `.warrant/warrant.toml` charter defines seven census classes for evidence integrity, operator state, capture trust, surface conformance, run lifecycle, registry drift, and release integrity.
Formalize the warrant charter so `campaign.py export-warrant` passes `charter absent` checks cleanly and earns verified tier ratings at release boundaries.

## Validation record

Written by `scripts/campaign/brief_validation.py`, which reads the registry rather than this document. Every id below is re-checkable: the requirement is in `inventory.json`, the surface is the one that requirement itself names, and each case passed at a rung at or above reckon's retiring floor.

- requirement: REQ-165, REQ-166, REQ-167
- surface: SURF-032
- cases: CASE-0650, CASE-0651, CASE-0652, CASE-0653
- rungs reached: outcome
- provider: none
