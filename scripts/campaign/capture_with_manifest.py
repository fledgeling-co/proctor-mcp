#!/usr/bin/env python3
"""Photograph named surfaces through proctor_capture, recording what the channel
was pointed at while the shutter was open.

The manifest is the whole point. A capture claims a subject; the claim is
checkable only against the target the channel actually addressed, and only if
that was written down at capture time. Afterwards, the filename is the only thing
binding a picture to a surface, and a filename is not evidence.

This machine currently runs two Proctor instances from one bundle id, whose
windows carry identical titles at identical bounds. Every entry therefore records
the CG window id the agent resolved, not the title, because the title cannot tell
the two apart.

Usage:
    capture_with_manifest.py <out-dir> <handle> plan.json
"""

from __future__ import annotations

import hashlib
import json
import subprocess
import sys
import time
from pathlib import Path

SHIM = Path(".build/debug/proctor-shim")


def call(proc, ident, tool, args):
    req = {"jsonrpc": "2.0", "id": ident, "method": "tools/call",
           "params": {"name": tool, "arguments": args}}
    proc.stdin.write(json.dumps(req) + "\n")
    proc.stdin.flush()
    while True:
        line = proc.stdout.readline()
        if not line:
            raise SystemExit("the shim closed while waiting for a reply")
        msg = json.loads(line)
        if msg.get("id") == ident:
            return msg


def main() -> int:
    out_dir, handle, plan_path = Path(sys.argv[1]), sys.argv[2], Path(sys.argv[3])
    plan = json.loads(plan_path.read_text())
    shots = out_dir / "shots"
    shots.mkdir(parents=True, exist_ok=True)
    manifest_path = shots / "captures.json"
    manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() else []

    proc = subprocess.Popen([str(SHIM), "serve", "--profile", "full"],
                            stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True, bufsize=1)
    ident = 0
    call(proc, (ident := ident + 1), "initialize", {}) if False else None
    proc.stdin.write(json.dumps({"jsonrpc": "2.0", "id": 1, "method": "initialize",
                                 "params": {"protocolVersion": "2024-11-05",
                                            "capabilities": {},
                                            "clientInfo": {"name": "campaign",
                                                           "version": "1"}}}) + "\n")
    proc.stdin.flush()
    proc.stdout.readline()
    proc.stdin.write(json.dumps({"jsonrpc": "2.0",
                                 "method": "notifications/initialized"}) + "\n")
    proc.stdin.flush()
    ident = 1

    written = []
    for item in plan:
        args = dict(item["args"])
        ident += 1
        args.setdefault("app", handle)
        # CONFIRM THE STATE BEFORE THE SHUTTER, when the plan names one.
        #
        # A window handle proves which window was photographed and says nothing
        # about what that window was showing. Measured: a capture of the correct
        # window was very nearly filed as the status sections while the window was
        # showing the setup walkthrough, because a fresh launch opens there. The
        # target was right and the subject was wrong, which is the failure the
        # lineage plane exists to catch and which a handle alone cannot.
        # `proctor_find` rather than `proctor_snapshot`: a snapshot returns a
        # bounded tree, so a state confirmed deep in it reads as absent and the
        # check refuses a capture that was fine. Find searches the window.
        expected = item.get("expectIdentifier")
        confirmed = None
        if expected:
            ident += 1
            probe = call(proc, ident, "proctor_find",
                         {"window": args.get("window"), "identifier": expected})
            tree = ""
            for c in probe.get("result", {}).get("content", []):
                if c.get("type") == "text":
                    tree += c["text"]
            found = 0
            try:
                found = json.loads(tree).get("count", 0)
            except Exception:
                found = 0
            if found == 0:
                written.append({"subject": item["subject"], "status": "wrong-state",
                                "reason": f"expected an element identified {expected!r} in "
                                          f"this window before the shutter and found none"})
                continue
            confirmed = expected

        started = time.time()
        reply = call(proc, ident, item.get("tool", "proctor_capture"), args)
        elapsed = round(time.time() - started, 3)
        content = reply.get("result", {}).get("content", [])
        error = reply.get("error") or (reply.get("result", {}) or {}).get("isError")
        text = next((c for c in content if c.get("type") == "text"), None)
        payload = {}
        if text:
            try:
                payload = json.loads(text["text"])
            except Exception:
                payload = {"text": text["text"][:400]}

        # proctor_capture writes the PNG and returns where it landed, plus the
        # window it resolved, the frame status and whether the frame is
        # trustworthy. Every one of those goes in the manifest: the target is
        # what makes the picture checkable, and the frame status is what stops a
        # stale frame being filed as evidence of the current state.
        src = payload.get("path")
        if not src or not Path(src).exists():
            written.append({"subject": item["subject"], "status": "no-image",
                            "reason": json.dumps(error or payload)[:400]})
            continue

        raw = Path(src).read_bytes()
        path = shots / item["file"]
        path.write_bytes(raw)
        digest = hashlib.sha256(raw).hexdigest()

        entry = {
            "subject": item["subject"],
            "file": f"evidence/shots/{item['file']}",
            "sha256": digest,
            "bytes": len(raw),
            "channel": item.get("channel",
                                "proctor_capture → ScreenCaptureKit, window-scoped"),
            # WHAT THE CHANNEL WAS POINTED AT, as the product reported it rather
            # than as this script assumed. Two Proctor processes share one bundle
            # id on this machine and their windows carry identical titles at
            # identical bounds, so the window handle is the only thing that can
            # tell a picture of one from a picture of the other.
            "target": {
                "window": payload.get("window"),
                "app": handle,
                "contentRect": payload.get("contentRect"),
                "sourcePath": src,
            },
            "frameStatus": payload.get("status"),
            "trustworthy": payload.get("trustworthy"),
            "framesWaited": payload.get("framesWaited"),
            "normalization": payload.get("normalization"),
            "conditions": {**item.get("conditions", {}), "elapsedSeconds": elapsed,
                           **({"stateConfirmedBy": f"proctor_find matched {confirmed!r} in this "
                                                   f"window before the shutter"}
                              if confirmed else {})},
            "capturedAt": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        }
        manifest = [m for m in manifest if m.get("file") != entry["file"]]
        manifest.append(entry)
        written.append({"subject": item["subject"], "status": "ok",
                        "bytes": len(raw), "frame": payload.get("status"),
                        "target": payload.get("window"),
                        "sha256": digest[:12]})

    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    proc.stdin.close()
    proc.terminate()

    for row in written:
        print(json.dumps(row))
    print(f"manifest: {len(manifest)} entries → {manifest_path}")
    return 0 if all(r["status"] == "ok" for r in written) else 1


if __name__ == "__main__":
    raise SystemExit(main())
