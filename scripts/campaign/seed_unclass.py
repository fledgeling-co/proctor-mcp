#!/usr/bin/env python3
"""The half of the census control that `--seed-strengthen` does not reach.

`vacuity-check.py --seed-strengthen` is the skill's arming rule turned on its
own gate, and it works: it sets a requirement's `effect` to a class no case
witnesses, drops the `provider`, and requires the census to go red. Measured
here against REQ-017 and REQ-001, both `before=clear after=red`.

But that mutation is *exactly* the `uncensused` predicate — declares an external
effect class, records no provider. So it fires `uncensused` and only
`uncensused`, in both directions, whatever the requirement's starting class:

    REQ-017 -> packet-filter, provider dropped:  unclassed 0, uncensused 1
    REQ-001 -> packet-filter, provider dropped:  unclassed 0, uncensused 1

The census has two exact passes at requirement level. After the shipped control
runs green, `unclassed` is still a pass reporting `examined=45 findings=0` that
nobody has watched go red — the position the control exists to get a gate out
of, surviving the control. Recorded as DEF-030.

This is the missing direction. It strengthens the *specification* rather than
the census record: remove a requirement's `effect` field entirely and require
`unclassed` to flag it. A requirement whose text names an effect outside the
process and carries no `effect` field is what that pass is for, so a pass that
stays clear under this mutation is reading nothing.

Two refusals, because a control that cannot fail is the thing being guarded
against:

  - it refuses a requirement the vocabulary cannot hit, since removing `effect`
    from one whose text names no external effect *correctly* produces no
    finding, and scoring that as a red would be a control passing on a
    tautology;
  - it refuses when `unclassed` is already red before the mutation, since
    `after=red` would then be red for a reason the mutation did not cause.

It lives here rather than as a patch to `vacuity-check.py`, which sits in a
plugin cache this repo does not own — a fix there is reverted by the next plugin
update with nothing saying so.

The registry is restored byte-for-byte in a `finally`, and the restoration is
verified by SHA-256 rather than asserted.

    python3 scripts/campaign/seed_unclass.py docs/test-campaign REQ-017
"""
from __future__ import annotations

import hashlib
import importlib.util
import json
import sys
from pathlib import Path

SKILL = Path.home() / (".claude/plugins/cache/fledgeling-plugins/test-campaign/"
                       "0.9.2/skills/test-campaign/scripts/vacuity-check.py")


def _vacuity():
    if not SKILL.exists():
        sys.exit(f"vacuity-check.py not found at {SKILL}")
    spec = importlib.util.spec_from_file_location("vacuity", SKILL)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def main() -> int:
    if len(sys.argv) != 3:
        sys.exit(__doc__.strip().splitlines()[-1].strip())
    d, req_id = Path(sys.argv[1]), sys.argv[2]
    v = _vacuity()

    inv_path = d / "inventory.json"
    original = inv_path.read_bytes()
    digest_before = hashlib.sha256(original).hexdigest()
    inv = json.loads(original)

    hit = next((r for r in inv.get("requirement", []) if r["id"] == req_id), None)
    if hit is None:
        sys.exit(f"No requirement {req_id}.")

    # Refusal one: the pass is already red, so a red after proves nothing.
    examined, before = v.pass_unclassed(v.requirements(d))
    if before:
        print(f"REFUSING: unclassed is already red ({len(before)} findings over "
              f"{examined} requirements). A red after the mutation would be red "
              f"for a reason the mutation did not cause.")
        return 2

    # Refusal two: the vocabulary cannot hit this requirement's text, so an
    # absent finding is correct rather than a gate reading nothing.
    probe = json.loads(original)
    ph = next(r for r in probe["requirement"] if r["id"] == req_id)
    ph.pop("effect", None)
    ph.pop("provider", None)
    _, hits = v.pass_unclassed(probe["requirement"])
    if not any(f.startswith(req_id + " ") for f in hits):
        print(f"REFUSING: {req_id}'s text names no effect the vocabulary matches, "
              f"so removing its `effect` field correctly produces no finding. "
              f"Scoring that as a red would pass this control on a tautology. "
              f"Pick a requirement whose text names an external effect.")
        return 2

    try:
        hit.pop("effect", None)
        hit.pop("provider", None)
        inv_path.write_text(json.dumps(inv, indent=2) + "\n")
        after_examined, after = v.pass_unclassed(v.requirements(d))
    finally:
        inv_path.write_bytes(original)

    digest_after = hashlib.sha256(inv_path.read_bytes()).hexdigest()
    restored = digest_before == digest_after

    print(f"seed-unclass {req_id}: before=clear after="
          f"{'red' if after else 'clear'} "
          f"(unclassed examined={after_examined} findings={len(after)})")
    for f in after:
        if f.startswith(req_id + " "):
            print(f"  {f}")
    print(f"registry restored byte-for-byte: {restored} (sha256 {digest_before[:16]}…)")

    if not after:
        print("FAIL — the requirement lost its effect class and unclassed stayed "
              "clear, so that pass reads nothing and its findings=0 means nothing.")
        return 1
    if not restored:
        print("FAIL — the registry was not restored.")
        return 3
    print("The pass bites: removing the effect class turned unclassed red.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
