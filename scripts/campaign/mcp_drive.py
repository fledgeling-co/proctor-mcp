#!/usr/bin/env python3
"""Drive proctor-shim over real MCP stdio and record raw responses as evidence.

Every artifact this writes is a response the product produced. Nothing here
authors a shape and calls it a measurement — that was the defect this replaces.

Usage:
    mcp_drive.py <out-dir> [--profile full] [--env KEY=VALUE ...] call.json ...

Each call file is {"tool": "proctor_doctor", "args": {...}, "as": "doctor.json"}.
Responses are written verbatim; the transcript records the request, the raw
response, the wall time and the shim's stderr.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from pathlib import Path

SHIM = Path(".build/debug/proctor-shim")


def drive(calls, profile, extra_env, out_dir, timeout=180):
    """One shim process, one session, every call in order."""
    env = dict(os.environ)
    env.update(extra_env)
    proc = subprocess.Popen(
        [str(SHIM), "serve", "--profile", profile],
        stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        env=env, text=True, bufsize=1,
    )

    transcript = []
    started = time.time()

    def send(obj):
        proc.stdin.write(json.dumps(obj) + "\n")
        proc.stdin.flush()

    def recv():
        line = proc.stdout.readline()
        if not line:
            return None
        return json.loads(line)

    send({"jsonrpc": "2.0", "id": 1, "method": "initialize",
          "params": {"protocolVersion": "2024-11-05", "capabilities": {},
                     "clientInfo": {"name": "test-campaign-driver", "version": "1"}}})
    init = recv()
    transcript.append({"request": "initialize", "response": init})

    send({"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}})

    send({"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}})
    listed = recv()
    transcript.append({"request": "tools/list", "response": listed})

    results = {}
    next_id = 3
    for spec in calls:
        req = {"jsonrpc": "2.0", "id": next_id, "method": "tools/call",
               "params": {"name": spec["tool"], "arguments": spec.get("args", {})}}
        next_id += 1
        t0 = time.time()
        send(req)
        resp = recv()
        elapsed = round(time.time() - t0, 3)
        transcript.append({"request": req, "response": resp, "elapsedSeconds": elapsed})
        results[spec["tool"]] = resp
        if spec.get("as"):
            (out_dir / spec["as"]).write_text(json.dumps(resp, indent=2) + "\n")

    proc.stdin.close()
    try:
        proc.wait(timeout=15)
    except subprocess.TimeoutExpired:
        proc.kill()
    stderr = proc.stderr.read()

    return {
        "shim": str(SHIM),
        "profile": profile,
        "env": extra_env,
        "toolsAdvertised": sorted(
            t["name"] for t in (listed or {}).get("result", {}).get("tools", [])),
        "transcript": transcript,
        "shimStderr": stderr,
        "wallSeconds": round(time.time() - started, 3),
        "exitCode": proc.returncode,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out_dir", type=Path)
    ap.add_argument("calls", type=Path, nargs="+")
    ap.add_argument("--profile", default="full")
    ap.add_argument("--env", action="append", default=[])
    ap.add_argument("--transcript", default="mcp-transcript.json")
    args = ap.parse_args()

    extra_env = dict(kv.split("=", 1) for kv in args.env)
    calls = []
    for p in args.calls:
        loaded = json.loads(p.read_text())
        calls.extend(loaded if isinstance(loaded, list) else [loaded])

    args.out_dir.mkdir(parents=True, exist_ok=True)
    session = drive(calls, args.profile, extra_env, args.out_dir)
    (args.out_dir / args.transcript).write_text(json.dumps(session, indent=2) + "\n")

    print(f"tools advertised: {len(session['toolsAdvertised'])}")
    print(f"calls driven:     {len(calls)}")
    for entry in session["transcript"]:
        req = entry["request"]
        if isinstance(req, dict) and req.get("method") == "tools/call":
            name = req["params"]["name"]
            resp = entry["response"] or {}
            err = "error" in resp
            content = resp.get("result", {}).get("content", [])
            head = ""
            if content and content[0].get("type") == "text":
                head = content[0]["text"][:120].replace("\n", " ")
            print(f"  {name:22s} {'ERROR' if err else 'ok':5s} {entry['elapsedSeconds']:>7}s  {head}")
    print(f"wrote {args.out_dir / args.transcript}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
