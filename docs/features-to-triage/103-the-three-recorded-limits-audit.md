# Audit of the three recorded limits: filesystem certification, hardware keyboard yield, and dynamic TCC grant re-probe

**Wave 19, brief 1.** DEF-141, DEF-151, DEF-180.

## The three recorded limits

1. **DEF-141 (Filesystem Certification Scope):** REQ-055 originally certified reads, the whole run, and every operator path. The current witness watches writes across two calls and one root. Evaluate whether extending the witness to cover read-isolation (or formally classing read-isolation as a distinct policy contract) is feasible and valuable.
2. **DEF-151 (Real Hardware Keyboard Input Yield):** Whether the `userInput` yield fires for a real human hand on a real keyboard (`sourcePid == 0` / `IOHIDEvent`) is unproved by current synthetic CGEvent tests. Investigate an external USB controller probe or explicit fallback characterization.
3. **DEF-180 (Dynamic TCC Screen Recording Grant Re-probe):** Screen Recording status is cached for the process lifetime by macOS. Evaluate dynamic daemon restart or explicit API re-probing (`CGDisplayStreamCreate` / `SCShareableContent`) on doctor requests so permission revocation is recognized without full reboot.
