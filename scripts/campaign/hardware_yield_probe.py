#!/usr/bin/env python3
"""Hardware Input Event Source Characterization Probe (DEF-151 / REQ-161).

Characterizes and asserts the boundary between synthetic CGEvent injection and
real hardware IOHIDEvent event sources in macOS window server dispatch.

Boundary Specification:
- Real hardware keyboard/mouse input from kernel/IOHIDEvent subsystem enters
  WindowServer with `eventSourceUnixProcessID == 0` (kernel / WindowServer source).
- Synthetic event injection via `CGEventPost` or `CGEventCreateKeyboardEvent` from
  user-space application processes carries the non-zero PID of the posting process.
- Proctor tags its own posted events with `eventSourceUserData == ProctorEventTag.value`
  (0x50524F43544F52).
- `PersonInput.isAPerson(sourcePid:userData:sinceSyntheticPost:grace:)` enforces:
    1. `sourcePid == 0` (must be kernel/hardware source, rejecting synthetic user-space posts)
    2. `userData != ProctorEventTag.value` (rejects Proctor's own tagged events)
    3. `sinceSyntheticPost == nil || sinceSyntheticPost >= grace` (suppresses echo/bounce during grace window)
"""
from __future__ import annotations

import sys
from typing import NamedTuple

PROCTOR_EVENT_TAG = 0x50524F43544F52  # "PROCTOR"
DEFAULT_GRACE_SECONDS = 0.25


class EventSample(NamedTuple):
    source_pid: int | None
    user_data: int | None
    since_synthetic_post: float | None
    grace: float = DEFAULT_GRACE_SECONDS


def is_a_person(sample: EventSample) -> bool:
    """Python mirror of ProctorCore.PersonInput.isAPerson."""
    if sample.source_pid is None or sample.source_pid != 0:
        return False
    if sample.user_data == PROCTOR_EVENT_TAG:
        return False
    if sample.since_synthetic_post is not None and sample.since_synthetic_post < sample.grace:
        return False
    return True


def is_ours(source_pid: int | None, user_data: int | None, our_pid: int,
            delegated: set[int] | None = None) -> bool:
    """Python mirror of ProctorCore.InputBlock.isOurs."""
    delegated = delegated or set()
    if source_pid is not None and source_pid == our_pid:
        return True
    if source_pid is not None and source_pid != 0 and source_pid in delegated:
        return True
    if user_data == PROCTOR_EVENT_TAG:
        return True
    return False


def verify_truth_table() -> list[tuple[str, bool, str]]:
    """Evaluates the full combinatorial boundary matrix."""
    results = []

    # 1. Hardware input (PID 0, untagged, outside grace)
    hw = EventSample(source_pid=0, user_data=0, since_synthetic_post=None)
    results.append(("Hardware input (PID 0, untagged) is person", is_a_person(hw) is True, "expected True"))

    # 2. Tagged automation event (PID 0, tagged)
    tagged = EventSample(source_pid=0, user_data=PROCTOR_EVENT_TAG, since_synthetic_post=None)
    results.append(("Tagged automation event is not person", is_a_person(tagged) is False, "expected False"))

    # 3. Synthetic userspace event (PID > 0)
    synthetic = EventSample(source_pid=1234, user_data=0, since_synthetic_post=None)
    results.append(("Synthetic userspace post (PID > 0) is not person", is_a_person(synthetic) is False, "expected False"))

    # 4. Nil source PID
    nil_pid = EventSample(source_pid=None, user_data=None, since_synthetic_post=None)
    results.append(("Nil source PID is not person", is_a_person(nil_pid) is False, "expected False"))

    # 5. Hardware input within grace period
    in_grace = EventSample(source_pid=0, user_data=0, since_synthetic_post=0.1, grace=0.25)
    results.append(("Hardware input within grace period is suppressed", is_a_person(in_grace) is False, "expected False"))

    # 6. Hardware input after grace period
    after_grace = EventSample(source_pid=0, user_data=0, since_synthetic_post=0.3, grace=0.25)
    results.append(("Hardware input after grace period is person", is_a_person(after_grace) is True, "expected True"))

    # 7. isOurs evaluation
    our_pid = 42
    delegated_pid = 99
    other_pid = 100

    results.append(("Our own PID is ours", is_ours(our_pid, 0, our_pid) is True, "expected True"))
    results.append(("Delegated PID is ours", is_ours(delegated_pid, 0, our_pid, {delegated_pid}) is True, "expected True"))
    results.append(("Non-delegated PID is not ours", is_ours(other_pid, 0, our_pid, {delegated_pid}) is False, "expected False"))
    results.append(("Hardware PID 0 untagged is not ours", is_ours(0, 0, our_pid, {delegated_pid}) is False, "expected False"))
    results.append(("Tagged PID 0 is ours", is_ours(0, PROCTOR_EVENT_TAG, our_pid) is True, "expected True"))

    return results


def main() -> int:
    results = verify_truth_table()
    failed = [label for label, ok, detail in results if not ok]
    for label, ok, detail in results:
        status = "PASS" if ok else "FAIL"
        print(f"[{status}] {label}")
        if not ok:
            print(f"       {detail}")
    print(f"\nHardware Yield Characterization: {len(results) - len(failed)}/{len(results)} assertions passed.")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
