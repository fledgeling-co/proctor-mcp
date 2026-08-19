#!/usr/bin/env python3
"""Measure whether the overlays enter a window-scoped capture of the app under test.

The overlays cannot be photographed (sharingType = .none). The property the
product actually promises is the complement: a window-scoped frame of the app
under test is the same whether the overlays are up or down. That is measurable
with real frames, so it is measured here rather than argued.

Three captures of the same target window:

    baseA, baseB   overlays down — the noise floor of two frames of a still app
    armed          taken while a synthetic batch holds the machine

A tint that leaked into the capture would move `armed` away from the baseline by
much more than the baseline moves from itself. Reporting both numbers is the
whole point: `armed - baseA` alone has no scale.

Usage: overlay_exclusion.py <window-handle> <out-dir>
"""

from __future__ import annotations

import json
import subprocess
import sys
import time
from pathlib import Path

REPO = Path("/Users/lukerhodes/Dev/proctor-mcp")
DRIVER = REPO / "scripts/campaign/mcp_drive.py"


def drive(calls, out_dir, transcript):
    spec = out_dir / f"{transcript}-calls.json"
    spec.write_text(json.dumps(calls))
    proc = subprocess.run(
        [sys.executable, str(DRIVER), str(out_dir), str(spec),
         "--profile", "full", "--transcript", f"{transcript}.json"],
        cwd=REPO, capture_output=True, text=True, timeout=300)
    return proc


def capture_call(window, path, tag):
    return {"tool": "proctor_capture",
            "args": {"window": window, "purpose": "verify", "path": str(path),
                     "waitForComplete": True, "normalize": False},
            "as": f"{tag}.json"}


def mean_levels(png: Path):
    """Mean per-channel level, 0-255, over every pixel."""
    from PIL import Image
    with Image.open(png) as im:
        im = im.convert("RGBA")
        pixels = im.getdata()
        n = len(pixels)
        sums = [0, 0, 0, 0]
        for r, g, b, a in pixels:
            sums[0] += r; sums[1] += g; sums[2] += b; sums[3] += a
        return [s / n for s in sums], im.size


def main():
    window, out = sys.argv[1], Path(sys.argv[2])
    shots = out / "shots"
    shots.mkdir(parents=True, exist_ok=True)

    base_a = shots / "overlay-exclusion-baseA.png"
    base_b = shots / "overlay-exclusion-baseB.png"
    armed = shots / "overlay-exclusion-armed.png"

    print("1. two baseline frames, overlays down")
    drive([capture_call(window, base_a, "excl-baseA"),
           capture_call(window, base_b, "excl-baseB")], out, "excl-base")

    print("2. a synthetic batch, and a frame taken while it holds the machine")
    batch = [{"tool": "proctor_act",
              "args": {"window": window, "foreground": True, "diffEach": False,
                       "steps": [{"kind": "hover", "point": [120 + 40 * i, 120 + 30 * i],
                                  "label": f"hover {i}", "settle": {"timeoutMs": 1400}}
                                 for i in range(7)]},
              "as": "excl-act.json"}]
    spec = out / "excl-batch-calls.json"
    spec.write_text(json.dumps(batch))
    proc = subprocess.Popen(
        [sys.executable, str(DRIVER), str(out), str(spec), "--profile", "full",
         "--transcript", "excl-batch.json"],
        cwd=REPO, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

    time.sleep(3.5)
    probe = subprocess.run([str(out / "glass_probe"), "Proctor"],
                           capture_output=True, text=True, timeout=60)
    overlays = json.loads(probe.stdout)
    drive([capture_call(window, armed, "excl-armed")], out, "excl-armed-run")
    proc.wait(timeout=180)

    print("3. levels")
    report = {"window": window, "frames": {}, "overlayWindowsWhileArmed": []}
    for tag, png in (("baseA", base_a), ("baseB", base_b), ("armed", armed)):
        if not png.exists():
            report["frames"][tag] = {"error": "no frame written"}
            continue
        levels, size = mean_levels(png)
        report["frames"][tag] = {
            "path": str(png), "size": list(size),
            "meanRGBA": [round(v, 4) for v in levels],
            "bytes": png.stat().st_size}

    for w in overlays["matchedWindows"]:
        if w["sharingState"] == 0:
            report["overlayWindowsWhileArmed"].append({
                "pid": w["ownerPID"], "windowNumber": w["windowNumber"],
                "bounds": w["bounds"], "layer": w["layer"], "alpha": w["alpha"],
                "sharingState": w["sharingState"], "onscreen": w["isOnscreen"]})

    frames = report["frames"]
    if all("meanRGBA" in frames.get(t, {}) for t in ("baseA", "baseB", "armed")):
        a, b, c = (frames[t]["meanRGBA"] for t in ("baseA", "baseB", "armed"))
        report["noiseFloor"] = [round(abs(x - y), 4) for x, y in zip(a, b)]
        report["armedDelta"] = [round(abs(x - y), 4) for x, y in zip(a, c)]
        report["verdict"] = (
            "excluded" if max(report["armedDelta"]) <= max(report["noiseFloor"]) + 0.5
            else "LEAKED into the capture")

    (out / "overlay-exclusion.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({k: v for k, v in report.items() if k != "frames"}, indent=2))
    for tag, info in frames.items():
        print(f"  {tag}: {info}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
