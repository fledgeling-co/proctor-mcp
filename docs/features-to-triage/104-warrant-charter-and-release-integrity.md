---
sources: [REQ-165, REQ-166, REQ-167, DEF-290]
---
# Formalize warrant charter and release gate integration

**Wave 19, brief 2.**

## What and why

The `.warrant/warrant.toml` charter defines seven census classes for evidence integrity, operator state, capture trust, surface conformance, run lifecycle, registry drift, and release integrity.
Formalize the warrant charter so `campaign.py export-warrant` passes `charter absent` checks cleanly and earns verified tier ratings at release boundaries.
