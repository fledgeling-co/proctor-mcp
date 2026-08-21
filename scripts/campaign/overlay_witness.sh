#!/usr/bin/env bash
# REQ-028's witness: an overlay Proctor draws is excluded from screen capture,
# and the frame that proves it has CONTENT in it.
#
# WHY THE CONTENT HALF IS THE POINT. PRO-0078 published a capture reporting
# `status: complete, trustworthy: true` over 2,942,720 pixels of RGBA(0,0,0,0).
# The exclusion was working and the capture path did not notice that exclusion was
# all it got. So a blank frame proves nothing here, and this script refuses to let
# one stand: it captures a NON-Proctor window through the same channel in the same
# second, proves that window's subject from strings a third process reads out of
# the target's own accessibility server, and reads the delivered pixels with a
# fourth process before saying anything.
#
# Four recorders, none of which is Proctor's capture path:
#   1. CGWindowListCopyWindowInfo  — what the window server says is on screen
#   2. screencapture -l            — the system's own utility, run by the probe
#   3. AXUIElement                 — the target's accessibility server
#   4. CGImageSource               — the pixels, read by a program that took no capture
#
# Usage: overlay_witness.sh <subjectWindowNumber> <subjectPid> <outDir>
set -euo pipefail

subject_window="${1:?subject CG window number}"
subject_pid="${2:?subject pid}"
out="${3:?output directory}"
mkdir -p "$out"

probe=/tmp/witness_probe
content=/tmp/frame_content
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -x "$probe" ]   || swiftc -O "$here/witness_probe.swift"  -o "$probe"
[ -x "$content" ] || swiftc -O "$here/frame_content.swift"  -o "$content"

date -u +%Y-%m-%dT%H:%M:%SZ > "$out/started-at.txt"

# 1. What the window server says is on screen right now, Proctor's windows and
#    their sharingState among it. Taken FIRST so the overlays are known to have
#    been up before either capture was attempted.
"$probe" windows Proctor "$out/windows-proctor.json" > /dev/null

# 2. The subject: a window Proctor does not own, through the system utility.
"$probe" capture "$subject_window" "$out/subject.png" "$out/subject-capture.json" > /dev/null || true

# 3. Every Proctor-owned on-screen window, through the SAME utility in the same
#    second. An excluded window is refused or comes back empty; either way it is
#    read rather than assumed.
python3 - "$out" <<'PY'
import json, subprocess, sys, os
out = sys.argv[1]
rows = json.load(open(f"{out}/windows-proctor.json"))["rows"]
results = []
for row in rows:
    wid = row["windowNumber"]
    png = f"{out}/overlay-{wid}.png"
    js  = f"{out}/overlay-{wid}.json"
    subprocess.run(["/tmp/witness_probe", "capture", str(wid), png, js],
                   capture_output=True)
    reply = json.load(open(js)) if os.path.exists(js) else {"ok": False, "reason": "no reply"}
    results.append({"windowNumber": wid, "sharingState": row["sharingState"],
                    "onScreenAlpha": row["alpha"], "layer": row["layer"],
                    "ownerPID": row["ownerPID"],
                    "captureOk": reply.get("ok", False),
                    "reason": reply.get("reason", "")})
json.dump(results, open(f"{out}/overlay-captures.json", "w"), indent=2, sort_keys=True)
print(json.dumps(results, indent=2, sort_keys=True))
PY

# 4. The subject's own accessibility server, for what the frame is a picture OF.
#    A filename is not evidence of what a picture depicts.
"$probe" axtext "$subject_pid" "$out/subject-axtext.json" > /dev/null

# 5. The pixels. A frame with one distinct colour and every pixel transparent is
#    the condition under test, not the proof of it.
"$content" "$out/subject.png" "$out/subject-content.json"

date -u +%Y-%m-%dT%H:%M:%SZ > "$out/finished-at.txt"
echo "witness written to $out"
