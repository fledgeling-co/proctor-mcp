#!/usr/bin/env python3
"""Screen Recording TCC Dynamic Grant Re-probe Characterization (DEF-180 / REQ-162).

Characterizes the lifecycle, caching invariants, and dynamic invalidation mechanics
of the macOS Screen Recording permission probe (`GrantProbeKeeper`).

Boundary Specification:
- macOS TCC grants for ScreenCaptureKit (`kTCCServiceScreenCapture`) are evaluated by
  `tccd`.
- `GrantProbeKeeper` caches definite results (`.granted` / `.denied`) for the process
  lifetime to prevent unbounded latency or deadlocks during recurring health checks.
- Dynamic grant status changes (e.g. user toggling System Settings) require either
  daemon process restart or explicit cache invalidation.
- When `invalidate_definite()` is triggered:
    1. The cached definite state is cleared (`definite = None`).
    2. Backoff retry schedules are reset (`attempts = 0`, `next_retry_at = 0`).
    3. The next query initiates a fresh bounded platform probe (`.start(token)`).
- Unconfirmed answers are never cached and follow exponential backoff: [2, 10, 60, 300] seconds.
"""
from __future__ import annotations

import enum
import sys
from typing import NamedTuple


class GrantState(enum.Enum):
    GRANTED = "granted"
    DENIED = "denied"
    UNCONFIRMED = "unconfirmed"


class DecisionKind(enum.Enum):
    CACHED = "cached"
    START = "start"
    JOIN = "join"
    UNCONFIRMED = "unconfirmed"


class Decision(NamedTuple):
    kind: DecisionKind
    state: GrantState | None = None
    token: int | None = None
    remaining: float | None = None


class GrantProbeKeeperSim:
    """Python simulation of ProctorCore.GrantProbeKeeper."""

    BACKOFF = [2.0, 10.0, 60.0, 300.0]

    def __init__(self, bound: float = 1.5):
        self.bound = bound
        self.definite: GrantState | None = None
        self.started_at: float | None = None
        self.attempts: int = 0
        self.next_retry_at: float = 0.0
        self.generation: int = 0

    @classmethod
    def retry_delay(cls, attempts: int) -> float:
        if attempts <= 0:
            return 0.0
        idx = min(attempts - 1, len(cls.BACKOFF) - 1)
        return cls.BACKOFF[idx]

    def claim(self, now: float) -> Decision:
        if self.definite is not None:
            return Decision(DecisionKind.CACHED, state=self.definite)
        if self.started_at is not None:
            elapsed = now - self.started_at
            if elapsed < self.bound:
                return Decision(DecisionKind.JOIN, remaining=self.bound - elapsed)
            self._reap_locked(now)
            return Decision(DecisionKind.UNCONFIRMED)
        if now < self.next_retry_at:
            return Decision(DecisionKind.UNCONFIRMED)
        self.generation += 1
        self.started_at = now
        return Decision(DecisionKind.START, token=self.generation)

    def record(self, state: GrantState, token: int | None = None, now: float = 0.0) -> None:
        if state == GrantState.UNCONFIRMED:
            return
        self.definite = state
        if token is None or token == self.generation:
            self.started_at = None
            self.attempts = 0
            self.next_retry_at = 0.0

    def abandon(self, token: int | None = None, now: float = 0.0) -> None:
        if self.started_at is None:
            return
        if token is not None and token != self.generation:
            return
        self._reap_locked(now)

    def invalidate_definite(self) -> None:
        self.definite = None
        self.started_at = None
        self.attempts = 0
        self.next_retry_at = 0.0

    def _reap_locked(self, now: float) -> None:
        self.started_at = None
        self.attempts += 1
        self.next_retry_at = now + self.retry_delay(self.attempts)


def verify_grant_lifecycle() -> list[tuple[str, bool, str]]:
    results = []

    keeper = GrantProbeKeeperSim(bound=1.5)

    # 1. Initial claim produces START with token 1
    d1 = keeper.claim(now=0.0)
    results.append(("Initial claim produces START(token=1)", d1.kind == DecisionKind.START and d1.token == 1, f"got {d1}"))

    # 2. Concurrent claim within bound produces JOIN
    d2 = keeper.claim(now=0.5)
    results.append(("Concurrent claim within bound produces JOIN", d2.kind == DecisionKind.JOIN and abs(d2.remaining - 1.0) < 1e-5, f"got {d2}"))

    # 3. Recording definite GRANTED caches result
    keeper.record(GrantState.GRANTED, token=1, now=0.6)
    d3 = keeper.claim(now=1.0)
    results.append(("Definite GRANTED is cached on next claim", d3.kind == DecisionKind.CACHED and d3.state == GrantState.GRANTED, f"got {d3}"))

    # 4. Consecutive claims continue returning cached state
    d4 = keeper.claim(now=100.0)
    results.append(("Cached state persists across time", d4.kind == DecisionKind.CACHED and d4.state == GrantState.GRANTED, f"got {d4}"))

    # 5. Invalidate definite clears cache and enables fresh START
    keeper.invalidate_definite()
    d5 = keeper.claim(now=101.0)
    results.append(("Invalidation clears cache and yields new START(token=2)", d5.kind == DecisionKind.START and d5.token == 2, f"got {d5}"))

    # 6. Recording DENIED after invalidation caches DENIED
    keeper.record(GrantState.DENIED, token=2, now=101.2)
    d6 = keeper.claim(now=102.0)
    results.append(("Updated DENIED state is now cached", d6.kind == DecisionKind.CACHED and d6.state == GrantState.DENIED, f"got {d6}"))

    # 7. Unconfirmed timeout schedules backoff
    keeper.invalidate_definite()
    d7 = keeper.claim(now=200.0)
    results.append(("START before timeout", d7.kind == DecisionKind.START and d7.token == 3, f"got {d7}"))

    keeper.abandon(token=3, now=201.5)
    # Immediately after abandon, next_retry_at is 201.5 + 2.0 = 203.5
    d8 = keeper.claim(now=202.0)
    results.append(("Claim during backoff returns UNCONFIRMED", d8.kind == DecisionKind.UNCONFIRMED, f"got {d8}"))

    d9 = keeper.claim(now=204.0)
    results.append(("Claim after backoff returns new START(token=4)", d9.kind == DecisionKind.START and d9.token == 4, f"got {d9}"))

    return results


def main() -> int:
    results = verify_grant_lifecycle()
    failed = [label for label, ok, detail in results if not ok]
    for label, ok, detail in results:
        status = "PASS" if ok else "FAIL"
        print(f"[{status}] {label}")
        if not ok:
            print(f"       {detail}")
    print(f"\nDynamic Grant Probe Characterization: {len(results) - len(failed)}/{len(results)} assertions passed.")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
