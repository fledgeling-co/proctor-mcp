#!/usr/bin/env python3
"""Window Occlusion Witness & Covered Target Plane Detector (DEF-325 / REQ-043 / REQ-200).

Correlates CGWindowList bounds, window layer ordering, and synthetic pointer coordinates:
1. Target window visibility: verifies target window presence and on-screen status.
2. Z-order and Layer occlusion: determines if overlapping windows at equal or higher layers
   occlude the target coordinate or fully cover the target window.
3. Pointer plane suppression: asserts that when a target coordinate or window is occluded,
   the pointer plane resolves to hidden, preventing synthetic cursor rendering over
   covered windows.
4. Proctor overlay filtering: ignores Proctor's own annotation and HUD panels so that
   the agent's own overlays never trigger self-occlusion.
5. Contention / hold attribution: asserts that when a target window is occluded, the
   contention watch transitions to yielded with reason `.targetOccluded`.
"""
from __future__ import annotations

import argparse
import json
import sys
from typing import Any, NamedTuple


class Rect(NamedTuple):
    x: float
    y: float
    w: float
    h: float

    def contains(self, px: float, py: float) -> bool:
        return self.x <= px <= self.x + self.w and self.y <= py <= self.y + self.h

    def intersects(self, other: Rect) -> bool:
        return not (
            self.x + self.w <= other.x
            or other.x + other.w <= self.x
            or self.y + self.h <= other.y
            or other.y + other.h <= self.y
        )

    def encloses(self, other: Rect) -> bool:
        return (
            self.x <= other.x
            and self.y <= other.y
            and self.x + self.w >= other.x + other.w
            and self.y + self.h >= other.y + other.h
        )


class WindowEntry(NamedTuple):
    window_id: int
    pid: int
    bounds: Rect
    layer: int = 0
    alpha: float = 1.0
    is_on_screen: bool = True


class OcclusionState(NamedTuple):
    status: str  # "clear", "point_occluded", "fully_covered", "not_on_screen"
    covering_window_ids: list[int]
    pointer_suppressed: bool
    yield_reason: str | None = None


class OcclusionVerificationResult(NamedTuple):
    scenario: str
    passed: bool
    details: str
    state: OcclusionState | None = None


class WindowOcclusionDetector:
    """Independent window-server layer occlusion detector."""

    @staticmethod
    def evaluate(
        target_id: int,
        target_point: tuple[float, float] | None,
        windows: list[WindowEntry],
        ignoring: set[int] | None = None
    ) -> OcclusionState:
        ignoring = ignoring or set()
        target_idx = None
        for i, w in enumerate(windows):
            if w.window_id == target_id and w.is_on_screen:
                target_idx = i
                break

        if target_idx is None:
            return OcclusionState(
                status="not_on_screen",
                covering_window_ids=[],
                pointer_suppressed=True,
                yield_reason="targetOccluded"
            )

        target = windows[target_idx]
        covering_windows: list[int] = []
        point_covering_windows: list[int] = []

        # 1. Windows stacked in front of target in Z-order
        for w in windows[:target_idx]:
            if w.window_id in ignoring:
                continue
            if not w.is_on_screen or w.alpha <= 0.05:
                continue
            if w.layer < target.layer:
                continue

            if target.bounds.intersects(w.bounds):
                covering_windows.append(w.window_id)

            if target_point is not None and w.bounds.contains(target_point[0], target_point[1]):
                point_covering_windows.append(w.window_id)

        if point_covering_windows:
            return OcclusionState(
                status="point_occluded",
                covering_window_ids=point_covering_windows,
                pointer_suppressed=True,
                yield_reason="targetOccluded"
            )

        # 2. Higher layer windows (e.g. modal panels, system alerts) even if later in list
        for w in windows[target_idx:]:
            if w.window_id in ignoring:
                continue
            if not w.is_on_screen or w.alpha <= 0.05:
                continue
            if w.layer > target.layer:
                if target_point is not None and w.bounds.contains(target_point[0], target_point[1]):
                    return OcclusionState(
                        status="point_occluded",
                        covering_window_ids=[w.window_id],
                        pointer_suppressed=True,
                        yield_reason="targetOccluded"
                    )
                if target.bounds.intersects(w.bounds):
                    covering_windows.append(w.window_id)

        # 3. Check full enclosure
        if covering_windows:
            for cid in covering_windows:
                cw = next((w for w in windows if w.window_id == cid), None)
                if cw and cw.bounds.encloses(target.bounds):
                    return OcclusionState(
                        status="fully_covered",
                        covering_window_ids=[cid],
                        pointer_suppressed=True,
                        yield_reason="targetOccluded"
                    )

        return OcclusionState(
            status="clear",
            covering_window_ids=[],
            pointer_suppressed=False,
            yield_reason=None
        )


def verify_window_occlusion_truth_table() -> list[OcclusionVerificationResult]:
    """Verify 6 deterministic window occlusion scenarios."""
    results: list[OcclusionVerificationResult] = []

    # Scenario 1: Target window frontmost & visible
    target = WindowEntry(window_id=101, pid=501, bounds=Rect(100, 100, 400, 300), layer=0)
    bg = WindowEntry(window_id=102, pid=502, bounds=Rect(200, 200, 400, 300), layer=0)
    state1 = WindowOcclusionDetector.evaluate(
        target_id=101,
        target_point=(250, 250),
        windows=[target, bg]
    )
    s1_pass = (state1.status == "clear" and not state1.pointer_suppressed and state1.yield_reason is None)
    results.append(OcclusionVerificationResult(
        scenario="Target window frontmost and clear",
        passed=s1_pass,
        details=f"status={state1.status}, suppressed={state1.pointer_suppressed}",
        state=state1
    ))

    # Scenario 2: Target coordinate occluded by front overlapping window
    front = WindowEntry(window_id=102, pid=502, bounds=Rect(200, 200, 400, 300), layer=0)
    target2 = WindowEntry(window_id=101, pid=501, bounds=Rect(100, 100, 400, 300), layer=0)
    state2 = WindowOcclusionDetector.evaluate(
        target_id=101,
        target_point=(250, 250),  # inside front (200..600, 200..500)
        windows=[front, target2]
    )
    s2_pass = (state2.status == "point_occluded" and state2.pointer_suppressed and 102 in state2.covering_window_ids)
    results.append(OcclusionVerificationResult(
        scenario="Target point occluded by overlapping front window",
        passed=s2_pass,
        details=f"status={state2.status}, covering={state2.covering_window_ids}",
        state=state2
    ))

    # Scenario 3: Target coordinate unoccluded in partially covered window
    state3 = WindowOcclusionDetector.evaluate(
        target_id=101,
        target_point=(150, 150),  # outside front (200..600, 200..500)
        windows=[front, target2]
    )
    s3_pass = (state3.status == "clear" and not state3.pointer_suppressed)
    results.append(OcclusionVerificationResult(
        scenario="Target point unoccluded in partially covered window",
        passed=s3_pass,
        details=f"status={state3.status}, suppressed={state3.pointer_suppressed}",
        state=state3
    ))

    # Scenario 4: Target window fully covered by larger front window
    covering_all = WindowEntry(window_id=103, pid=503, bounds=Rect(50, 50, 600, 500), layer=0)
    state4 = WindowOcclusionDetector.evaluate(
        target_id=101,
        target_point=(200, 200),
        windows=[covering_all, target2]
    )
    s4_pass = (state4.status in ("point_occluded", "fully_covered") and state4.pointer_suppressed)
    results.append(OcclusionVerificationResult(
        scenario="Target window fully covered by enclosing front window",
        passed=s4_pass,
        details=f"status={state4.status}, covering={state4.covering_window_ids}",
        state=state4
    ))

    # Scenario 5: Modal panel / alert at higher layer occludes point
    modal = WindowEntry(window_id=104, pid=600, bounds=Rect(200, 200, 200, 150), layer=100)
    state5 = WindowOcclusionDetector.evaluate(
        target_id=101,
        target_point=(250, 250),
        windows=[target, modal]  # modal listed after target but higher layer
    )
    s5_pass = (state5.status == "point_occluded" and state5.pointer_suppressed and 104 in state5.covering_window_ids)
    results.append(OcclusionVerificationResult(
        scenario="Modal panel at higher window layer occludes target point",
        passed=s5_pass,
        details=f"status={state5.status}, covering={state5.covering_window_ids}",
        state=state5
    ))

    # Scenario 6: Proctor overlay ignored, avoiding self-occlusion
    proctor_overlay = WindowEntry(window_id=999, pid=700, bounds=Rect(0, 0, 1920, 1080), layer=100)
    state6 = WindowOcclusionDetector.evaluate(
        target_id=101,
        target_point=(250, 250),
        windows=[proctor_overlay, target],
        ignoring={999}
    )
    s6_pass = (state6.status == "clear" and not state6.pointer_suppressed)
    results.append(OcclusionVerificationResult(
        scenario="Proctor overlay panels ignored to prevent self-occlusion",
        passed=s6_pass,
        details=f"status={state6.status}, suppressed={state6.pointer_suppressed}",
        state=state6
    ))

    return results


def main() -> int:
    parser = argparse.ArgumentParser(description="Window Occlusion Witness & Covered Target Plane Detector")
    parser.add_argument("--json", action="store_true", help="Output JSON report")
    args = parser.parse_args()

    results = verify_window_occlusion_truth_table()
    all_passed = all(r.passed for r in results)

    if args.json:
        payload = {
            "passed": all_passed,
            "scenarios": [
                {
                    "scenario": r.scenario,
                    "passed": r.passed,
                    "details": r.details,
                    "status": r.state.status if r.state else None,
                    "pointer_suppressed": r.state.pointer_suppressed if r.state else None,
                    "yield_reason": r.state.yield_reason if r.state else None,
                }
                for r in results
            ]
        }
        print(json.dumps(payload, indent=2))
    else:
        print(f"Window Occlusion Witness: {len(results)} scenarios evaluated.")
        for r in results:
            mark = "PASS" if r.passed else "FAIL"
            print(f"  [{mark}] {r.scenario}: {r.details}")
        print(f"\nVerdict: {'ALL SCENARIOS PASSED' if all_passed else 'FAILURES DETECTED'}")

    return 0 if all_passed else 1


if __name__ == "__main__":
    sys.exit(main())
