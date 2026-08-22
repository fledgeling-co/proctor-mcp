# Item 6 — the revocation, attempted on this machine

The brief's contract was to grant Screen Recording, confirm `doctor` reports it granted, revoke it
in System Settings without restarting anything, and read `doctor` again. Steps 1, 2 and 4 ran.
Step 3 **could not be completed by an agent**, and the reason is itself a measurement.

## What ran

**Subject.** The installed agent, pid 52976, started `Fri 21 Aug 17:37:20 2026` and never
restarted across any of this — `agent-identity.txt` holds the stamp, and `ps` reported the same
pid and the same start time after the attempt as before it.

**Before.** `revocation-before/doctor.json`, written by `scripts/campaign/mcp_drive.py` driving
`.build/debug/proctor-shim` over real MCP stdio to that agent. Not transcribed:

    {"granted":true,"name":"Screen Recording","required":true,"state":"granted", …}

**The revocation attempt.** System Settings ▸ Privacy & Security ▸ Screen & System Audio
Recording, driven over the accessibility plane by Proctor itself. The row's switch resolved as
`Proctor_Toggle`, node `nd:427831a66ed52dee`, `AXCheckBox`/`AXSwitch`, value `1`. One `AXPress`
took its value to `0` — and macOS raised an `AXSheet` at the same moment carrying, verbatim:

    Privacy & Security is trying to modify your system settings.
    Touch ID or enter your password to allow this.

with `Use Password…` and `Cancel` as its only buttons. **The toggle's `0` was a proposal, not a
change.** Pressing `Cancel` returned node `nd:427831a66ed52dee` to value `1` in the same tree diff.

**After.** `revocation-after-attempt/doctor.json`, same instrument: `Screen Recording` reads
`granted`, Accessibility reads `granted`, and pid 52976 is unchanged.

## What this settles, and what it does not

**Settled: on macOS 26.6 a Screen Recording grant cannot be revoked without a person.** The pane
gates the write behind Touch ID or a password, so no background runner can perform this
revocation, and none should try — the two buttons offered are the password prompt and cancel.
That is the cost the spec predicted from the code; it is now measured, with the sheet's own words.

**Not settled: whether the agent reports a revoked grant as granted end-to-end.** The doctor
reading after the attempt says `granted`, and the permission was never actually taken away, so it
is a reading of an intact grant and proves nothing about a stale one. It is recorded here so
nobody later mistakes it for the after-shot the brief asked for.

**Where the claim does stand.** `StatusWindowDebtWiringTests` drives `ScreenRecordingProbe` with a
platform that answers `granted` and then `denied` and reads `granted` back, with the platform
asked exactly once — and its two-way control is the same probe answering `unconfirmed`, which is
never cached and does re-probe. So the freeze is established at the layer that owns it, armed in
both directions, rather than asserted from a code read. What is missing is the glass rung, and it
is missing for a reason a runner cannot remove.

**One human action would close it:** with the pane open, press the toggle and authenticate, then
call `doctor` again before touching anything else. DEF-180 records the claim and stays open.
