---
sources: [REQ-018]
status: retired
---
# Decide what happens to the native planes

**Read `00-WAVE-7-DIRECTION.md` first.** Do not start this before brief 45 has merged.

## The problem

Once Cua performs actuation, Proctor still contains a complete, tested, working
implementation of the same thing: the accessibility plane, the synthetic-event plane,
the Apple Events route, the fallback rungs, and the tests that pin all of it. Leaving
it in place is not free and deleting it is not obviously right.

## The decision this item exists to make

Three readings, and the spec must choose one and defend it:

1. **Delete them.** One actuation path, one set of failure modes, a much smaller
   surface. Loses the ability to run at all on a machine without `cua-driver`, and
   throws away the Apple Events plane, which Cua has no equivalent of.
2. **Keep them as an automatic fallback.** Nothing breaks when Cua is missing or a
   call fails. Costs two paths with different behaviour, and a run that silently
   changes plane mid-flight makes a determinism score meaningless, which is the
   product this repo is pivoting towards.
3. **Keep them, explicitly selected, never automatic.** An operator or a caller
   chooses the lane and the run record says which one it was. Honest, and it means two
   paths stay maintained and tested forever.

**The Apple Events plane is the part that most argues against deletion.** It is a third
actuation route Cua does not have, it needs no foreground and no accessibility tree,
and for scriptable apps it is the most reliable thing in the box.

## The hard parts, named

- **Whatever is chosen, the run record must say which plane ran.** A determinism score
  computed across runs that used different actuation paths is measuring the paths.
- **The test suite is the asset here, not the code.** Several hundred tests pin the
  native planes' behaviour. If the planes go, decide what happens to the tests: some
  of them describe macOS rather than Proctor, and those are worth keeping as a
  characterisation of the platform whatever drives it.
- **Do not decide this by counting lines.** The question is which failure mode a person
  running an unattended campaign would rather have.

## Validation record

Written by `scripts/campaign/brief_validation.py`, which reads the registry rather than this document. Every id below is re-checkable: the requirement is in `inventory.json`, the surface is the one that requirement itself names, and each case passed at a rung at or above reckon's retiring floor.

- requirement: REQ-018
- surface: SURF-001, SURF-013
- cases: CASE-0001, CASE-0019, CASE-0020, CASE-0038, CASE-0059, CASE-0371
- rungs reached: effect-witness, metamorphic, outcome
- provider: none
