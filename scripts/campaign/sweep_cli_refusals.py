#!/usr/bin/env python3
"""Refusal honesty across every CLI verb, against a real refusal.

The first version of this sweep invoked each verb with no arguments and reported
0 failures over 21 verbs. That number was worthless: 16 verbs returned a usage
error, which the remedy predicate exempted, and the other 5 succeeded. The
predicate examined 21 rows and could not have failed on any of them.

This version points every verb at a socket nothing is listening on. That is a
refusal every verb must produce, it is the one CI is most likely to hit, and a
remedy is genuinely owed on all of them.

WRITE POSTURE: the socket does not exist, so no call can reach an agent and
nothing can be actuated. The five service verbs are still never invoked.
"""
import json, os, subprocess, sys

CLI = ".build/debug/proctor-cli"
SERVICE = {"install", "uninstall", "serve", "tui", "status"}
DEAD = "/tmp/proctor-sweep-no-such.sock"

def verbs():
    out = subprocess.run([CLI], capture_output=True, text=True)
    txt = out.stdout + out.stderr
    found, grab = set(), False
    for line in txt.splitlines():
        if line.startswith(("Observation", "Actuation", "Service")):
            grab = True; continue
        if grab and line.startswith("  ") and line.strip() and not line.strip().startswith("proctor"):
            found |= set(line.split())
        elif grab and not line.strip():
            grab = False
    return sorted(found - SERVICE)

def main():
    env = dict(os.environ, PROCTOR_SOCKET=DEAD)
    vs = verbs()
    a_ok = b_ok = c_ok = 0
    rows = []
    for v in vs:
        p = subprocess.run([CLI, v], capture_output=True, text=True, timeout=90, env=env)
        code, err = p.returncode, (p.stderr or "")
        # A: an unreachable agent is exit 3, never 0 and never 1
        a = code == 3
        # B: the refusal says what to do next
        b = "install" in err.lower() or "load the agent" in err.lower()
        # C: it names the socket it tried, so the operator can see WHICH agent
        c = DEAD in err
        a_ok += a; b_ok += b; c_ok += c
        rows.append((v, code, a, b, c))
    print(f"{'verb':<18}{'exit':>5}  {'is-3':>5}{'remedy':>8}{'names-socket':>14}")
    for v, code, a, b, c in rows:
        flag = "" if (a and b and c) else "   <-- FINDING"
        print(f"{v:<18}{code:>5}  {'Y' if a else 'n':>5}{'Y' if b else 'n':>8}{'Y' if c else 'n':>14}{flag}")
    print()
    n = len(vs)
    print(f"A · agent-unreachable did not exit 3:  examined={n} failures={n-a_ok}")
    print(f"B · refusal carried no remedy:         examined={n} failures={n-b_ok}")
    print(f"C · refusal did not name the socket:   examined={n} failures={n-c_ok}")
    return 0 if a_ok == b_ok == c_ok == n else 1

sys.exit(main())
