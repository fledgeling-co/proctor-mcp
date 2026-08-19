#!/usr/bin/env python3
"""Compile every Proctor TUI screen state at both sizes.

Direction "Invigilator": cool ink ground, bronze accent reserved for the
provenance chip, focus, and one primary action; red held back for halt.

Every frame here is compiled, never drawn. The compiler owns the cell
arithmetic, so a column that does not fit is a fit finding rather than a
border that silently fails to close.
"""
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
COMPILER = ("/Users/lukerhodes/.claude/plugins/cache/fledgeling-plugins/"
            "tui-craft/0.4.0/skills/tui-design/scripts/tui_mock.py")

ROLES = {
    "surface":      {"bg": "#14161B"},
    "surface-lift": {"bg": "#1B1E25"},
    "text":         {"fg": "#E9EAED"},
    "text-strong":  {"fg": "#FFFFFF", "bold": True},
    "text-dim":     {"fg": "#9AA1AF"},
    "border":       {"fg": "#6E7686"},
    "border-focus": {"fg": "#D2A059"},
    "accent":       {"fg": "#D2A059"},
    "ok":           {"fg": "#74C79B"},
    "warn":         {"fg": "#E3B76A"},
    "danger":       {"fg": "#F1897F"},
    "selected":     {"reverse": True},
}

TAB_NAMES = [("1", "run"), ("2", "queue"), ("3", "readiness"),
             ("4", "history"), ("5", "switches")]

FOOTER_RUN = {"keybar": {"style": "bracket", "items": [
    ["p", "pause"], ["s", "stop"], ["d", "drop waiting"], ["?", "help"], ["q", "quit"]]}}
FOOTER_READ = {"keybar": {"style": "bracket", "items": [
    ["r", "re-check"], ["tab", "pane"], ["?", "help"], ["q", "quit"]]}}


def spec(title, root, cols, rows):
    return {"schema": "tui-design/spec/1", "title": title,
            "size": {"cols": cols, "rows": rows}, "theme": "dark",
            "roles": ROLES, "alt_screen": True, "root": root}


def tabs(active):
    """The five panes as a bracket bar; the active one shouts in caps."""
    return {"keybar": {"style": "bracket", "items": [
        [k, n.upper() if n == active else n] for k, n in TAB_NAMES]}}


def screen(body, active, footer=FOOTER_RUN):
    return {"dir": "col", "children": [
        dict({"h": 1}, **tabs(active)),
        dict({"flex": 1}, **body),
        dict({"h": 1}, **footer)]}


# ------------------------------------------------------------------ run pane

def queue_table(rows, shelf):
    # pad 2 rather than the default 1: a right-aligned figure flush against its
    # own border reads cramped, and the extra gutter also keeps a full-width row
    # from abutting the frame edge.
    return {"panel": {"title": "QUEUE", "border": "round", "shelf_right": shelf,
                      "pad": 2,
                      "child": {"table": {"columns": [
                          {"name": "LANE", "w": 13, "role": "accent"},
                          {"name": "HOLDER", "flex": 1},
                          {"name": "STATE", "w": 8},
                          {"name": "WAIT", "w": 5, "align": "right"}],
                          "rows": rows}}}}


def run_ideal(cols, rows):
    return screen({"dir": "col", "children": [
        {"h": 10, "panel": {
            "title": "RUN", "border": "round", "focus": True, "focus_marker": "▸",
            "shelf_centre": "acting", "shelf_right": "host · native",
            "shelf_bottom_right": "step 4 of 7",
            "child": {"dir": "col", "children": [
                {"h": 2, "text": {"role": "text", "lines": [
                    "Typing into Search in Mail",
                    "settled: allSignalsQuiet after 412ms"]}},
                {"flex": 1, "pairs": {"items": [
                    ["plane", "accessibility"],
                    ["route", "selectedText"],
                    ["backend", "native"],
                    ["elapsed", "00:12.4"]]}}]}}},
        dict({"flex": 1}, **queue_table(
            [["app:Mail", "mcp claude-code", "holding", "12s"],
             ["event-stream", "free", "free", "-"],
             ["app:Xcode", "cli lukerhodes", "waiting", "3s"]], "1 waiting"))]},
        "run")


def run_empty(cols, rows):
    return screen({"dir": "col", "children": [
        {"flex": 1, "panel": {
            "title": "RUN", "border": "round", "shelf_right": "host · native",
            "child": {"text": {"align": "centre", "role": "text-dim", "lines": [
                "",
                "Nothing running.",
                "",
                "Proctor is listening on the agent socket. A run",
                "appears here the moment a model calls a tool.",
                "",
                "Press <3> for readiness, <?> for keys."]}}}}]},
        "run")


def run_loading(cols, rows):
    return screen({"dir": "col", "children": [
        {"flex": 1, "panel": {
            "title": "RUN", "border": "round",
            "shelf_centre": "connecting", "shelf_right": "-",
            "child": {"dir": "col", "children": [
                {"h": 3, "text": {"role": "text-dim", "lines": [
                    "Reaching the agent.",
                    "~/Library/Application Support/",
                    "  app.fledgeling.procter/agent.sock"]}},
                {"h": 1, "gauge": {"label": "handshake", "value": 60,
                                   "readout": "waiting", "role": "accent"}},
                {"flex": 1, "blank": {}}]}}}]},
        "run")


def run_partial(cols, rows):
    return screen({"dir": "col", "children": [
        {"h": 10, "panel": {
            "title": "RUN", "border": "round", "focus": True, "focus_marker": "▸",
            "shelf_centre": "paused", "shelf_right": "host · native",
            "shelf_bottom_right": "step 4 of 7",
            "child": {"dir": "col", "children": [
                {"h": 2, "text": {"role": "warn", "lines": [
                    "Paused. Somebody started using this Mac and",
                    "the run yielded at the first keystroke."]}},
                {"flex": 1, "pairs": {"items": [
                    ["held by", "contention yield"],
                    ["resumes", "on <p>"],
                    ["pause cap", "15:00"],
                    ["elapsed", "00:12.4"]]}}]}}},
        dict({"flex": 1}, **queue_table(
            [["app:Mail", "mcp claude-code", "paused", "12s"],
             ["app:Xcode", "cli lukerhodes", "waiting", "31s"],
             ["event-stream", "mcp cursor", "waiting", "8s"]], "2 waiting"))]},
        "run")


def run_error(cols, rows):
    return screen({"dir": "col", "children": [
        {"flex": 1, "panel": {
            "title": "RUN", "border": "round", "border_role": "danger",
            "shelf_centre": "agent unreachable",
            "child": {"dir": "col", "children": [
                {"h": 3, "text": {"role": "danger", "lines": [
                    "The background agent is not answering.",
                    "Connection refused on the agent socket.",
                    "Until it runs, nothing on this screen is live."]}},
                {"h": 3, "text": {"role": "text-dim", "lines": [
                    "",
                    "The last good frame was 4s ago and is not shown,",
                    "because a stale frame reads as a running one."]}},
                {"flex": 1, "blank": {}},
                {"h": 1, "keybar": {"style": "bracket", "items": [
                    ["r", "retry now"], ["a", "start the agent"]]}}]}}}]},
        "run")


def run_done(cols, rows):
    return screen({"dir": "col", "children": [
        {"h": 10, "panel": {
            "title": "RUN", "border": "round",
            "shelf_centre": "finished", "shelf_right": "host · native",
            "shelf_bottom_right": "7 of 7",
            "child": {"dir": "col", "children": [
                {"h": 2, "text": {"role": "ok", "lines": [
                    "Finished. 7 steps, no refusals.",
                    "2 took the foreground and said so."]}},
                {"flex": 1, "pairs": {"items": [
                    ["planes", "accessibility x5, syntheticEvent x2"],
                    ["backend", "native"],
                    ["recorded", "run-4f2c, sealed and signed"],
                    ["elapsed", "00:41.8"]]}}]}}},
        {"flex": 1, "panel": {
            "title": "QUEUE", "border": "round", "shelf_right": "0 waiting",
            "child": {"text": {"role": "text-dim", "align": "centre",
                               "lines": ["", "Every lane is free."]}}}}]},
        "run")


# ------------------------------------------------------------- other panes

def readiness(cols, rows):
    return screen({"dir": "col", "children": [
        {"h": 9, "panel": {
            "title": "PERMISSIONS", "border": "round", "shelf_right": "read-only",
            "child": {"table": {"columns": [
                {"name": "GRANT", "w": 17},
                {"name": "STATE", "w": 9, "role": "accent"},
                {"name": "WHAT IT GATES", "flex": 1}],
                "rows": [["Accessibility", "granted", "the tree, and writes to it"],
                         ["Screen Recording", "granted", "pixels, and frame status"],
                         ["Input Monitoring", "off", "noticing a person sooner"]]}}}},
        {"flex": 1, "panel": {
            "title": "LANES", "border": "round", "shelf_right": "derived",
            "child": {"table": {"columns": [
                {"name": "LANE", "w": 8, "role": "accent"},
                {"name": "STATE", "w": 12},
                {"name": "NEEDS", "flex": 1}],
                "rows": [["mac", "ready", "the two grants above"],
                         ["browser", "ready", "obscura"],
                         ["ios", "unconfirmed", "simctl, maestro"],
                         ["cua", "unavailable", "cua-driver, not on this Mac"],
                         ["guest", "ready", "lume, prlctl"]]}}}}]},
        "readiness", FOOTER_READ)


def history(cols, rows):
    return screen({"dir": "col", "children": [
        {"flex": 1, "panel": {
            "title": "HISTORY", "border": "round",
            "shelf_centre": "14 days, 10,000 entries",
            "shelf_bottom_right": "page 1 of 6",
            "child": {"table": {"selected": 1, "selected_marker": "▸", "columns": [
                {"name": "WHEN", "w": 8},
                {"name": "TOOL", "w": 15, "role": "accent"},
                {"name": "APP", "flex": 1},
                {"name": "OUTCOME", "w": 8},
                {"name": "STEPS", "w": 5, "align": "right"}],
                "rows": [["09:14:02", "proctor_act", "com.apple.mail", "ok", "7"],
                         ["09:13:41", "proctor_assert", "com.apple.mail", "ok", "4"],
                         ["09:13:20", "proctor_act", "com.apple.dt.Xcode", "refused", "0"],
                         ["09:12:55", "proctor_apps", "com.apple.mail", "ok", "1"],
                         ["09:11:03", "proctor_flow", "com.apple.mail", "ok", "12"],
                         ["09:08:17", "proctor_guest", "-", "refused", "0"]]}}}}]},
        "history", FOOTER_READ)


def history_empty(cols, rows):
    return screen({"dir": "col", "children": [
        {"flex": 1, "panel": {
            "title": "HISTORY", "border": "round",
            "shelf_centre": "nothing recorded yet",
            "child": {"text": {"align": "centre", "role": "text-dim", "lines": [
                "",
                "No runs recorded on this machine.",
                "",
                "The trail starts at the first tool call and keeps",
                "14 days or 10,000 entries, whichever comes first.",
                "",
                "Press <3> to check the agent is ready to record."]}}}}]},
        "history", FOOTER_READ)


def switches(cols, rows):
    return screen({"dir": "col", "children": [
        {"flex": 1, "panel": {
            "title": "SWITCHES", "border": "round", "shelf_centre": "read-only here",
            "shelf_bottom_left": "set in the app or the launchd environment",
            "child": {"table": {"columns": [
                {"name": "SWITCH", "w": 22, "role": "accent"},
                {"name": "VALUE", "w": 5},
                {"name": "FROM", "w": 11},
                {"name": "EFFECT", "flex": 1}],
                "rows": [["PROCTOR_HUD", "on", "default", "now"],
                         ["PROCTOR_CURSOR", "on", "default", "next start"],
                         ["PROCTOR_TAKEOVER", "on", "default", "next start"],
                         ["PROCTOR_YIELD", "on", "saved", "next start"],
                         ["PROCTOR_YIELD_INPUT", "on", "saved", "next start"],
                         ["PROCTOR_TAKEOVER_INPUT", "off", "default", "next start"],
                         ["PROCTOR_SECOND_LANE", "off", "default", "next start"],
                         ["PROCTOR_ACTUATION", "off", "environment", "next start"]]}}}}]},
        "switches", FOOTER_READ)


def queue_pane(cols, rows):
    return screen({"dir": "col", "children": [
        {"h": 8, "panel": {
            "title": "LANE MODEL", "border": "round", "shelf_right": "3 lanes",
            "child": {"text": {"role": "text-dim", "lines": [
                "Reads never join the line.",
                "Process-directed actuation contends per app.",
                "Synthetic events contend globally, one at a time,",
                "and raising an app holds that app's lane too."]}}}},
        dict({"flex": 1}, **queue_table(
            [["app:Mail", "mcp claude-code", "holding", "12s"],
             ["app:Xcode", "cli lukerhodes", "waiting", "31s"],
             ["event-stream", "mcp cursor", "waiting", "8s"],
             ["app:Safari", "free", "free", "-"]], "2 waiting, cap 45s"))]},
        "queue", FOOTER_RUN)


SCREENS = {
    "run-ideal": run_ideal,
    "run-empty": run_empty,
    "run-loading": run_loading,
    "run-partial": run_partial,
    "run-error": run_error,
    "run-done": run_done,
    "queue-ideal": queue_pane,
    "readiness-ideal": readiness,
    "history-ideal": history,
    "history-empty": history_empty,
    "switches-ideal": switches,
}
SIZES = [(100, 30), (80, 24)]


def main():
    failures, made = [], []
    for name, fn in SCREENS.items():
        for cols, rows in SIZES:
            body = fn(cols, rows)
            payload = spec("proctor - " + name, body, cols, rows)
            stem = "%s-%dx%d" % (name, cols, rows)
            sp = os.path.join(HERE, stem + ".spec.json")
            fp = os.path.join(HERE, stem + ".json")
            with open(sp, "w") as fh:
                json.dump(payload, fh, indent=1)
            r = subprocess.run([sys.executable, COMPILER, sp, "-o", fp],
                               capture_output=True, text=True)
            made.append(stem)
            if r.returncode != 0:
                failures.append((stem, r.stderr.strip()))
    print("compiled %d frames" % len(made))
    for name, err in failures:
        print("FIT %s:" % name)
        for line in err.splitlines():
            print("   ", line)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
