---
sources: [REQ-160, REQ-161, REQ-162, DEF-141, DEF-151, DEF-180]
status: retired
---
# Audit of the three recorded limits: filesystem certification, hardware keyboard yield, and dynamic TCC grant re-probe

**Wave 19, brief 1.** DEF-141, DEF-151, DEF-180.

## The three recorded limits

1. **DEF-141 (Filesystem Certification Scope):** REQ-055 originally certified reads, the whole run, and every operator path. The current witness watches writes across two calls and one root. Evaluate whether extending the witness to cover read-isolation (or formally classing read-isolation as a distinct policy contract) is feasible and valuable.
2. **DEF-151 (Real Hardware Keyboard Input Yield):** Whether the `userInput` yield fires for a real human hand on a real keyboard (`sourcePid == 0` / `IOHIDEvent`) is unproved by current synthetic CGEvent tests. Investigate an external USB controller probe or explicit fallback characterization.
3. **DEF-180 (Dynamic TCC Screen Recording Grant Re-probe):** Screen Recording status is cached for the process lifetime by macOS. Evaluate dynamic daemon restart or explicit API re-probing (`CGDisplayStreamCreate` / `SCShareableContent`) on doctor requests so permission revocation is recognized without full reboot.

## Validation record

Written by `scripts/campaign/brief_validation.py`, which reads the registry rather than this document. Every id below is re-checkable: the requirement is in `inventory.json`, the surface is the one that requirement itself names, and each case passed at a rung at or above reckon's retiring floor.

- requirement: REQ-055, REQ-160, REQ-161, REQ-162
- surface: SURF-005, SURF-008, SURF-012, SURF-022, SURF-031
- cases: CASE-0009, CASE-0010, CASE-0011, CASE-0017, CASE-0018, CASE-0027
- rungs reached: effect-witness, metamorphic, outcome, raster-visual
- provider: the test suite itself, observed through DirectoryWitness in Tests/ProctorAgentTests/Support/FileWitness.swift — a recursive sweep of ~/Library/Application Support/app.fledgeling.procter recording existence, byte count, mtime and sha256 per file either side of a Session.configurePolicy. The population is stated rather than implied: the sweep asserts the root exists and that len(files) >= 1 before the claim is read, and the claim is reported as changed / len(files) — 0 of the 3,290 regular files `find -type f` reports under that root on this machine — so a zero out of an absent or empty root fails instead of passing. The claim is a negative, so each case also carries a control arm: the same recorder, over the same call, reporting a non-zero count on a root that IS written.
