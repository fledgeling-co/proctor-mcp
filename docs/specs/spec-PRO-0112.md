# PRO-0112: Warrant charter and release integrity

**ID:** PRO-0112
**Status:** Ready for Plan
**Created:** 2026-08-23
**Last updated:** 2026-08-23
**Brief:** `docs/features-to-triage/104-warrant-charter-and-release-integrity.md`

## Feature description

Integrate `.warrant/warrant.toml` with campaign evidence to ensure warrant tier validation passes without charter-absent blocks.

## Acceptance sketch

- `.warrant/warrant.toml` validates against `campaign.py export-warrant`.
- All census classes match repository evidence rules.
