# Plan — PRO-0095

**Spec:** `docs/specs/spec-PRO-0095.md` · **Tier:** Small · **Branch:** `ai/pro-0095` off `ai/wave-9`

Three independent defects. Nothing here depends on anything else here, so the order below is by
cost rather than by dependency: the check that might close a record for free comes first.

**Baseline, measured before any change:** `./scripts/test.sh` exit 0, `Test run with 1862 tests
in 220 suites passed after 16.096 seconds`, log at `/tmp/pro0095/baseline.log`.

## Step 1 — DEF-043: establish whether the record is already closed

Read `SessionDoctor.swift:237` through `SignatureVerdictCache.verdict(for:)` and sweep the rest
of `Session.doctor` for a second blocking call. Done during triage; the sweep found none, and
the reasoning is in the spec.

Add CASE-0197 to `Tests/ProctorAgentTests/ToolchainDoctorTests.swift`: eight sessions call
`session.doctor(verbose:)` concurrently against an injected `SignatureVerdictCache` whose
`identify` and `verify` closures each record `__dispatch_queue_get_label(nil)`. Assert the
caller's label contains `cooperative` first, because an assertion that the verification is not
on that pool means nothing unless the probe can see the pool when it is looking at it. Then
assert the verification's label contains neither `cooperative` nor bare
`com.apple.root.default-qos`.

The existing `concurrentSessionsVerifyOnce` is the nearest test and it counts verifications
rather than reading where they ran; CASE-0197 is a second `@Test` beside it rather than an edit
to it, so the count claim keeps its own case.

**Acceptance:** the new test passes; it is watched red by substituting a synchronous wrapper on
the call site, which is the substitution CASE-0116 was built after a reviewer made.

## Step 2 — DEF-068: the policy file's mode

Change `PolicyStore.save` in `Sources/ProctorAgent/Session/PolicyStore.swift`. Keep the atomic
replace and set the mode at creation:

1. Create the directory `0o700` as now.
2. Open a temporary in the same directory with `Darwin.open(path, O_WRONLY|O_CREAT|O_EXCL|O_TRUNC, 0o600)`.
3. Write the encoded bytes in a loop, `fsync`, close.
4. `FileManager.replaceItemAt(url, withItemAt: temp, options: [.usingNewMetadataOnly])`.
5. Remove the temporary on any throw, so a failed save leaves no partial file behind.

`.usingNewMetadataOnly` is load-bearing and is the easiest line to drop: without it
`replaceItemAt` carries the original item's metadata across, and an operator's existing `0644`
file would keep `0644` through every future save.

Four cases in a new `@Suite` in `Tests/ProctorAgentTests/PolicyStoreSeamTests.swift`, all
reading the mode off disk with `attributesOfItem` rather than trusting the call:

| Case | Claim |
|---|---|
| CASE-0190 | A fresh save leaves `policy.json` at exactly `0o600`, inside a `0o700` directory |
| CASE-0191 | A pre-existing `0644` file is `0600` after the next save |
| CASE-0192 | Under `umask(0)` the result is still `0600`, so the mode is set rather than inherited |
| CASE-0193 | The saved policy loads back equal, so the write path still works |

CASE-0192 is the one that discriminates. Restore the process umask in a `defer`, since `umask`
is process-wide and the suite runs in parallel — set it, save, read, restore, and do not assert
anything else while it is changed.

**Acceptance:** all four pass; the pre-fix `Data.write(to:options:.atomic)` is put back and
CASE-0190, CASE-0191 and CASE-0192 are watched red, recorded in
`docs/test-campaign/evidence/PRO-0095/def068-arming.txt`.

## Step 3 — DEF-075: the control's missing precondition

New `scripts/campaign/seed_strengthen.py`, modelled on `scripts/campaign/seed_unclass.py`:
resolve the plugin's `vacuity-check.py` by newest installed version, print the resolved path,
exit as a cannot-run when the plugin is absent, and refuse when the baseline is not clear.

The refusal reads the state and names it, following the sibling's wording:

    REFUSING: the census is already red before the mutation (N findings over M requirements).
    A red after the mutation would be red for a reason the mutation did not cause.

Exit 2 for a refusal, matching `seed_unclass.py`. Restore the registry in a `finally` and verify
the restoration by SHA-256 rather than asserting it.

Three checks appended to `scripts/campaign/test_instruments.py`, which
`Tests/ProctorCoreTests/CampaignInstrumentTests.swift` runs, so `./scripts/test.sh` owns the
verdict:

| Case | Claim |
|---|---|
| CASE-0194 | On a fixture whose census is already red, the control exits 2 and names the state |
| CASE-0195 | On a clear fixture the control runs and reports `before=clear after=red` |
| CASE-0196 | The fixture registry is byte-identical after both paths |

CASE-0195 is what keeps the refusal from being a way to pass by never running: a control that
refused everything would satisfy CASE-0194 alone.

**Acceptance:** three checks green; the refusal watched firing against
`docs/test-campaign` as it actually stands, recorded in
`docs/test-campaign/evidence/PRO-0095/def075-refusal.txt`.

## Step 4 — registry rows and the gate

Append to `docs/test-campaign/inventory.json` and `cases.json` only. Never reformat, re-sort, or
rewrite a row this item did not create. `docs/feature-specs/LEDGER.md` is not touched.

Rows: REQ-063, REQ-064, DEF-100, and CASE-0190..0197. DEF-068 and DEF-075 move to `fixed` with a
`fix` and `fixedBy` field, which is a change to rows this item is closing rather than to rows it
did not create.

Then `./scripts/test.sh` to a file, exit code read from the file rather than from a pipeline,
into `docs/test-campaign/evidence/PRO-0095/gate-after.txt` with the suite count beside the
baseline's 1862.

## What is deliberately not planned

No saturation test for the cooperative pool. CASE-0116's note records that one was drafted and
dropped because it holds the process-wide pool for seconds in a green run, and the suite runs in
parallel, so it would stall unrelated tests and feed DEF-051.

No change under `~/.claude/plugins`. The spec's open decision records the alternative and why an
unattended run is not the place to take it.

## Open question this plan cannot settle

Whether the plugin's own `--seed-strengthen` should be fixed at source in
`~/Dev/fledgeling-plugins`, which would fix it for every project on this machine. It is a second
repository and a published one. Carried to the report rather than decided here.
