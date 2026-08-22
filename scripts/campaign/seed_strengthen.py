#!/usr/bin/env python3
"""The census-strengthening control, with the precondition the shipped one lacks.

`vacuity-check.py --seed-strengthen` takes a requirement, replaces its declared
effect class with one no case witnesses, drops its `provider`, and requires the
census to go red. That is the right mutation. What it does not do is check where
it started, so it prints

    seed-strengthen REQ-017: before=red after=red
    The gate bites: strengthening the constraint turned it red

from a red the mutation did not cause. Measured against `docs/test-campaign` as
it stands: the registry has a standing census finding, so `uncensused` is red
before anything is mutated, and the control reports a bite having established
nothing. A control that cannot tell "the gate bit" from "the gate was already
red" is not a control. DEF-075.

The fix is one refusal, and it is the same refusal `seed_unclass.py` already
carries for the other pass: require a clear baseline, and name the state found
when refusing.

It lives here rather than as a patch to `vacuity-check.py` for the reason
`seed_unclass.py` records — that file sits in a plugin cache this repo does not
own, and a fix there is reverted by the next plugin update with nothing saying
so. Fixing it for every project on this machine means a commit to the plugin's
source repository, which is a second and published repository; spec-PRO-0095
records that as an open decision rather than taking it.

The mutation itself is the plugin's, read from the installed copy rather than
reimplemented, so this control and the one it replaces cannot drift about what
"strengthened" means.

    python3 scripts/campaign/seed_strengthen.py docs/test-campaign REQ-017
"""
from __future__ import annotations

import hashlib
import importlib.util
import json
import sys
from pathlib import Path

# The newest installed version rather than a pinned one — DEF-076, which found
# `seed_unclass.py` pinned to a 0.9.2 that one cache prune removes. Versions sort
# as tuples of integers so 0.9.10 lands after 0.9.9 rather than before it.
PLUGIN = Path.home() / ".claude/plugins/cache/fledgeling-plugins/test-campaign"


def _skill() -> Path:
    def key(p: Path) -> tuple:
        try:
            return tuple(int(part) for part in p.name.split("."))
        except ValueError:
            return ()
    found = sorted((v / "skills/test-campaign/scripts/vacuity-check.py"
                    for v in PLUGIN.glob("*") if v.is_dir()),
                   key=lambda p: key(p.parent.parent.parent.parent))
    return next((p for p in reversed(found) if p.exists()), PLUGIN / "vacuity-check.py")


def _vacuity():
    skill = _skill()
    if not skill.exists():
        sys.exit(f"vacuity-check.py not found under {PLUGIN} — the test-campaign "
                 f"plugin is not installed, so this control cannot run. That is a "
                 f"cannot-run, not a pass.")
    print(f"# vacuity-check.py: {skill}")
    spec = importlib.util.spec_from_file_location("vacuity", skill)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def census(v, d: Path) -> tuple[int, list[str], int, list[str]]:
    """Both requirement-level passes, with their populations beside them.

    The shipped control collapses this to one boolean, which is how it lost the
    ability to say what it found.
    """
    reqs = v.requirements(d)
    unclassed_examined, unclassed = v.pass_unclassed(reqs)[:2]
    # `[:2]` rather than a two-name unpack because the skill this borrows lives
    # outside the repo and its signature moves. test-campaign 0.9.6 widened
    # `pass_uncensused` to `(declared, findings, named, resolved)`, and the stale
    # two-value unpack raised `ValueError: too many values to unpack` — which
    # `seed_strengthen` reported as exit 1, which the suite reported as a red
    # tree, for a reason that had nothing to do with the tree. The population and
    # the findings are the first two in every version, so those are what is taken.
    uncensused_examined, uncensused = v.pass_uncensused(reqs)[:2]
    return unclassed_examined, unclassed, uncensused_examined, uncensused


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

    # The refusal DEF-075 is about. A census that is already red would be red
    # after the mutation for a reason the mutation did not cause, and the shipped
    # control scores exactly that as a bite.
    ux_examined, unclassed, uc_examined, uncensused = census(v, d)
    if unclassed or uncensused:
        red = []
        if unclassed:
            red.append(f"unclassed ({len(unclassed)} findings over {ux_examined} requirements)")
        if uncensused:
            red.append(f"uncensused ({len(uncensused)} findings over {uc_examined} requirements)")
        print(f"REFUSING: the census is already red before the mutation — "
              f"{'; '.join(red)}. A red after the mutation would be red for a "
              f"reason the mutation did not cause, which is what this control "
              f"exists to rule out.")
        for f in (unclassed + uncensused)[:5]:
            print(f"  standing finding: {f}")
        remaining = len(unclassed) + len(uncensused) - 5
        if remaining > 0:
            print(f"  ... and {remaining} more")
        print("Clear the standing findings, or run against a fixture copy in "
              "which they are cleared, and run this again.")
        return 2

    # The plugin's own mutation, so the two controls cannot disagree about what
    # a strengthened constraint is.
    try:
        hit["effect"] = "packet-filter" if hit.get("effect") != "packet-filter" else "subprocess"
        hit["evidence"] = "observed"
        hit.pop("provider", None)
        inv_path.write_text(json.dumps(inv, indent=2) + "\n")
        after_ux_examined, after_unclassed, after_uc_examined, after_uncensused = census(v, d)
    finally:
        inv_path.write_bytes(original)

    digest_after = hashlib.sha256(inv_path.read_bytes()).hexdigest()
    restored = digest_before == digest_after
    after_red = bool(after_unclassed or after_uncensused)

    print(f"seed-strengthen {req_id}: before=clear after={'red' if after_red else 'clear'} "
          f"(unclassed examined={after_ux_examined} findings={len(after_unclassed)}; "
          f"uncensused examined={after_uc_examined} findings={len(after_uncensused)})")
    for f in after_unclassed + after_uncensused:
        if f.startswith(req_id + " "):
            print(f"  {f}")
    print(f"registry restored byte-for-byte: {restored} (sha256 {digest_before[:16]}…)")

    if not after_red:
        print("FAIL — the strengthened requirement still clears the census, so the "
              "census reads nothing and every verdict it has issued is worthless.")
        return 1
    if not restored:
        print("FAIL — the registry was not restored.")
        return 3
    print("The gate bites: strengthening the constraint turned a clear census red, "
          "from a baseline this run established rather than assumed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
