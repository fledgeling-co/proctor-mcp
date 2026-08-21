# PRO-0091 — implementation plan

**Spec:** `docs/specs/spec-PRO-0091.md`. Written alongside the work rather than ahead of it;
the item was dispatched naming a plan that existed on no branch.

## Where each fix lands, and why there

Three of the seven findings are about a tool this repo does not own. `campaign.py` and
`vacuity-check.py` belong to the test-campaign plugin, and `seed_unclass.py`'s own header sets
this repo's standing rule: a patch to the plugin **cache** is reverted by the next plugin update
with nothing saying so. The rule argues against patching the cache, not against committing to
the plugin's source repository, which is where an update carries the change forward rather than
over it.

| Finding | File | Repo |
|---|---|---|
| DEF-041 | `skills/test-campaign/scripts/campaign.py`, `tests/run.sh` | `~/Dev/fledgeling-plugins` |
| DEF-057 | the same two files | `~/Dev/fledgeling-plugins` |
| DEF-030 | `scripts/campaign/seed_unclass.py` + an arming run | this repo |
| DEF-032 | `scripts/campaign/mutate_swift.py` | this repo |
| DEF-055 | `docs/test-campaign/cases.json` | this repo |
| DEF-040 | `docs/test-campaign/inventory.json` | this repo |
| DEF-058 | `scripts/campaign/merge_registry.py` (new) | this repo |

## The test seam

This repo's gate is `./scripts/test.sh`, and it runs swift-testing. The instruments are Python,
so the seam is `scripts/campaign/test_instruments.py` holding the checks and
`Tests/ProctorCoreTests/CampaignInstrumentTests.swift` running it, which puts the verdict where
the repo already keeps it. A Python file nobody runs is the same shape of finding as the ones it
was written to close.

The Swift wrapper asserts the **count** of checks made as well as the exit code, because
`0 passed, 0 failed` exits 0 and is exactly an instrument reporting a clean result over a
population it never examined. Two checks are additionally re-expressed in Swift, driving the two
scripts directly rather than through the Python runner.

The plugin's changes are gated by its own `tests/run.sh`, which already proves every blocker
fires on a fixture built to trip it and then clears when the fixture is repaired.

## Arming

`docs/test-campaign/evidence/PRO-0091/instrument-arming.txt` runs six one-line mutations, each
applied to a backed-up copy of the tree and restored before the next, so each red names one
cause. The first attempt at this used `git checkout` to revert and lost an uncommitted fix while
leaving an untracked script mutated for the rest of the run; the recorded version uses file
backups and re-runs green from the same session.

## Order

1. `campaign.py` denominator, its three gate tests, arming fixture at 18 requirements against a cap of 12.
2. `SOURCE_RUNGS`, its two guards, its five gate tests. Bump the plugin to 0.9.4, commit, mirror into the active cache.
3. `mutate_swift.py` lookbehind; `seed_unclass.py` version resolution.
4. `merge_registry.py` and the reproduction of the PRO-0081 loss as its fixture.
5. `cases.json`: CASE-0074's figure, CASE-0102..0105 onto `source-analysis` with analyzer and denominator.
6. `inventory.json`: REQ-024 to `vacuous`, REQ-057..058, DEF-075..076, and the five closures.
7. `test_instruments.py`, the Swift wrapper, the arming run, the four gates, the evidence page.

## Registry discipline

Ranges are allocated: CASE-0150..0159, DEF-075..079, REQ-057..058. Rows are appended in the
file's own format, checked by round-tripping each registry through `json.dumps(indent=2)` before
editing and asserting the result is byte-identical to what is on disk. No row this item did not
create is rewritten beyond a status flip and a closing note appended to a defect's own detail.
`docs/feature-specs/LEDGER.md` is not touched.
