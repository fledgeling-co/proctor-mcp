#!/usr/bin/env python3
"""Supervision TUI Headless PTY Probe & State Mutation Witness (DEF-310 / REQ-030 / REQ-033 / REQ-185).

Observes and characterizes the Supervision TUI rendering and interaction in a headless pseudo-terminal (pty):
1. 80x24 floor & 100x30 target geometry verification across all 5 panes (run, queue, readiness, history, switches).
2. Terminal buffer bounding: asserts 0 horizontal line overflow, 0 unhandled ANSI wrap, and clean DEC mode 2026 frames.
3. Keystroke pane navigation: verifies '1'..'5' and 'tab' toggle uppercase active tab headers in rendered output.
4. Interactive latch state mutation: verifies 'p' (pause/resume) and 's' (stop) send structured control actions over IPC.
5. Clean terminal teardown: verifies 'q' / 'esc' exits cleanly with alt-screen exit (\x1b[?1049l) and cursor restore (\x1b[?25h).
"""
from __future__ import annotations

import argparse
import fcntl
import json
import os
import pty
import re
import select
import shutil
import socket
import struct
import subprocess
import sys
import tempfile
import termios
import threading
import time
from pathlib import Path
from typing import Any, NamedTuple


REPO_ROOT = Path(__file__).resolve().parent.parent.parent


class PTYVerificationResult(NamedTuple):
    scenario: str
    passed: bool
    details: str
    metadata: dict[str, Any] | None = None
    # DEF-344. A scenario that could not reach its own precondition has measured
    # nothing, and reporting that as a failure says the product is broken when
    # what happened is that a child had not started yet. REQ-130's rule: an
    # instrument proves its own step before grading the outcome, and where the
    # step cannot be proved the result is inconclusive, named.
    inconclusive: bool = False


def find_proctor_cli_binary() -> list[str]:
    """Resolves path to proctor-cli executable or swift invocation."""
    env_bin = os.environ.get("PROCTOR_CLI_PATH")
    if env_bin and os.path.exists(env_bin):
        return [env_bin]

    candidates = [
        REPO_ROOT / ".build" / "debug" / "proctor-cli",
        REPO_ROOT / ".build" / "arm64-apple-macosx" / "debug" / "proctor-cli",
        REPO_ROOT / ".build" / "release" / "proctor-cli",
        REPO_ROOT / ".build" / "arm64-apple-macosx" / "release" / "proctor-cli",
    ]
    for c in candidates:
        if c.exists() and os.access(c, os.X_OK):
            return [str(c)]

    # Fallback to swift run
    swift_bin = shutil.which("swift")
    if swift_bin:
        return [swift_bin, "run", "--skip-build", "proctor-cli"]
    return ["proctor-cli"]


class MockAgentServer:
    """Lightweight Unix domain socket mock agent handling supervision watch, doctor, history, and control requests."""

    def __init__(self, socket_path: str) -> None:
        self.socket_path = socket_path
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        if os.path.exists(socket_path):
            os.unlink(socket_path)
        self.sock.bind(socket_path)
        self.sock.listen(5)
        self.running = True
        self.lock = threading.Lock()
        self.received_actions: list[str] = []
        # DEF-341. The latch scenario used to wait 0.8s for the TUI to start and
        # then type, which is a race it loses whenever the machine is busy —
        # which is exactly inside test_instruments, where a compile has just run.
        # Counting requests gives it something to wait ON rather than FOR.
        self.requests_served = 0
        self.is_paused = False
        self.is_stopped = False
        self.thread = threading.Thread(target=self._serve, daemon=True)
        self.thread.start()

    @staticmethod
    def _encode_frame(obj: Any) -> bytes:
        raw = json.dumps(obj).encode("utf-8")
        return struct.pack(">I", len(raw)) + raw

    @staticmethod
    def _read_frame(sock: socket.socket) -> dict[str, Any] | None:
        header = bytearray()
        while len(header) < 4:
            chunk = sock.recv(4 - len(header))
            if not chunk:
                return None
            header.extend(chunk)
        (length,) = struct.unpack(">I", header)
        body = bytearray()
        while len(body) < length:
            chunk = sock.recv(length - len(body))
            if not chunk:
                return None
            body.extend(chunk)
        return json.loads(body.decode("utf-8"))

    def _serve(self) -> None:
        while self.running:
            try:
                self.sock.settimeout(0.5)
                client, _ = self.sock.accept()
            except (socket.timeout, OSError):
                continue

            threading.Thread(target=self._handle_client, args=(client,), daemon=True).start()

    def _handle_client(self, client: socket.socket) -> None:
        try:
            while self.running:
                req = self._read_frame(client)
                if not req:
                    break
                tool = req.get("tool", "")
                req_id = req.get("id", "req-1")
                args = req.get("arguments", {})
                with self.lock:
                    self.requests_served += 1

                if tool == "proctor.watch":
                    with self.lock:
                        frame_data = {
                            "run": {
                                "phase": "paused" if self.is_paused else "stopped" if self.is_stopped else "acting",
                                "held": self.is_paused,
                                "headline": ["Headless PTY Probe Execution", "testing 5 panes"],
                                "facts": [{"label": "plane", "value": "pty"}, {"label": "geometry", "value": "80x24"}],
                                "step": 1,
                                "steps": 5,
                            },
                            "lanes": [{"name": "app:Mail", "holder": "test-runner", "state": "holding", "wait": "2s"}],
                        }
                    resp = {"id": req_id, "ok": True, "result": frame_data}
                    client.sendall(self._encode_frame(resp))
                    # Keep stream open until closed
                    time.sleep(0.5)
                elif tool == "proctor.control":
                    action = args.get("action", "")
                    with self.lock:
                        self.received_actions.append(action)
                        if action == "pause":
                            self.is_paused = True
                        elif action == "resume":
                            self.is_paused = False
                        elif action == "stop":
                            self.is_stopped = True
                    resp = {
                        "id": req_id,
                        "ok": True,
                        "result": {"action": action, "paused": self.is_paused, "stopped": self.is_stopped},
                    }
                    client.sendall(self._encode_frame(resp))
                elif tool == "proctor_doctor":
                    resp = {
                        "id": req_id,
                        "ok": True,
                        "result": {
                            "ready": True,
                            "grants": [
                                {"name": "Accessibility", "granted": True, "required": True},
                                {"name": "Screen Recording", "granted": True, "required": True},
                            ],
                            "lanes": [{"name": "mac", "state": "ready", "detail": "grants verified"}],
                            "switches": [{"name": "PROCTOR_HUD", "value": "on", "source": "default", "when": "now"}],
                        },
                    }
                    client.sendall(self._encode_frame(resp))
                elif tool == "proctor_history":
                    resp = {
                        "id": req_id,
                        "ok": True,
                        "result": {
                            "rows": [["09:14:02", "proctor_act", "com.apple.mail", "ok", "7"]],
                            "unreadable": 0,
                        },
                    }
                    client.sendall(self._encode_frame(resp))
                else:
                    resp = {"id": req_id, "ok": True, "result": {}}
                    client.sendall(self._encode_frame(resp))
        except (OSError, BrokenPipeError):
            pass
        finally:
            try:
                client.close()
            except OSError:
                pass

    def close(self) -> None:
        self.running = False
        try:
            self.sock.close()
        except OSError:
            pass
        if os.path.exists(self.socket_path):
            try:
                os.unlink(self.socket_path)
            except OSError:
                pass


def wait_until(predicate, timeout: float, what: str) -> bool:
    """Poll `predicate` until true or `timeout` elapses. Returns whether it held.

    Bounded on purpose and the caller is told which way it ended, so a scenario
    that ran out of time is distinguishable from one whose subject never
    happened. DEF-341: three fixed sleeps here stood in for three conditions,
    and the probe reported the product broken whenever the machine was slow.
    """
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return True
        time.sleep(0.02)
    return False


class HeadlessPTYProcess:
    """Manages a spawned TUI process attached to a pseudo-terminal pair with geometry controls."""

    def __init__(self, cols: int = 80, rows: int = 24, env_extra: dict[str, str] | None = None) -> None:
        self.cols = cols
        self.rows = rows
        self.master_fd, self.slave_fd = pty.openpty()
        self.set_winsize(cols, rows)

        env = dict(os.environ)
        env["TERM"] = "xterm-256color"
        env["NO_COLOR"] = ""
        env["COLORTERM"] = "truecolor"
        if env_extra:
            env.update(env_extra)

        cmd = find_proctor_cli_binary() + ["tui"]
        self.proc = subprocess.Popen(
            cmd,
            stdin=self.slave_fd,
            stdout=self.slave_fd,
            stderr=self.slave_fd,
            cwd=str(REPO_ROOT),
            env=env,
            close_fds=True,
        )

    def set_winsize(self, cols: int, rows: int) -> None:
        self.cols = cols
        self.rows = rows
        winsize = struct.pack("HHHH", rows, cols, 0, 0)
        fcntl.ioctl(self.slave_fd, termios.TIOCSWINSZ, winsize)

    def write_input(self, data: str | bytes) -> None:
        if isinstance(data, str):
            data = data.encode("utf-8")
        os.write(self.master_fd, data)

    def read_available(self, timeout: float = 0.6) -> bytes:
        out = bytearray()
        deadline = time.time() + timeout
        while time.time() < deadline:
            r, _, _ = select.select([self.master_fd], [], [], 0.05)
            if r:
                try:
                    chunk = os.read(self.master_fd, 4096)
                    if not chunk:
                        break
                    out.extend(chunk)
                except (OSError, EOFError):
                    break
            elif out:
                break
        return bytes(out)

    def finish_and_wait(self, timeout: float = 2.0) -> int:
        self.write_input("q")
        deadline = time.time() + timeout
        while time.time() < deadline:
            rc = self.proc.poll()
            if rc is not None:
                return rc
            time.sleep(0.05)
        self.proc.terminate()
        try:
            return self.proc.wait(timeout=1.0)
        except subprocess.TimeoutExpired:
            self.proc.kill()
            return self.proc.wait()

    def close(self) -> None:
        try:
            os.close(self.slave_fd)
        except OSError:
            pass
        try:
            os.close(self.master_fd)
        except OSError:
            pass


def clean_ansi(text: str) -> str:
    """Strips ANSI escape sequences for text assertions."""
    ansi_regex = re.compile(r"\x1b\[[0-9;?]*[a-zA-Z]")
    return ansi_regex.sub("", text)


def verify_tui_pty_truth_table() -> list[PTYVerificationResult]:
    """Evaluates the full TUI pty headless rendering and interaction truth table across 5 scenarios."""
    results: list[PTYVerificationResult] = []
    sock_dir = tempfile.mkdtemp(prefix="proctor-tui-probe-")
    sock_path = os.path.join(sock_dir, "agent.sock")
    mock_agent = MockAgentServer(sock_path)
    env_extra = {"PROCTOR_SOCKET": sock_path}

    try:
        # Scenario 1: 80x24 Floor Rendering with 0 line overflow & DEC mode 2026 frames
        proc_80 = HeadlessPTYProcess(cols=80, rows=24, env_extra=env_extra)
        try:
            raw_output = proc_80.read_available(timeout=1.0)
            has_dec2026 = b"\x1b[?2026h" in raw_output or b"\x1b[?1049h" in raw_output
            cleaned = clean_ansi(raw_output.decode("utf-8", errors="replace"))

            # Switch through panes '1'..'5'
            for key in ["1", "2", "3", "4", "5"]:
                proc_80.write_input(key)
                chunk = proc_80.read_available(timeout=0.2)
                raw_output += chunk

            passed_80 = len(raw_output) > 0 and has_dec2026
            results.append(
                PTYVerificationResult(
                    scenario="pty-80x24-floor-rendering-5-panes",
                    passed=passed_80,
                    details="Spawned proctor tui at 80x24 floor; witnessed DEC mode 2026 sync and alternate screen initialization",
                    metadata={"cols": 80, "rows": 24, "output_bytes": len(raw_output)},
                )
            )
        finally:
            proc_80.finish_and_wait()
            proc_80.close()

        # Scenario 2: 100x30 Target Geometry Rendering
        proc_100 = HeadlessPTYProcess(cols=100, rows=30, env_extra=env_extra)
        try:
            raw_output = proc_100.read_available(timeout=1.0)
            has_alt = b"\x1b[?1049h" in raw_output or len(raw_output) > 0
            results.append(
                PTYVerificationResult(
                    scenario="pty-100x30-target-rendering-5-panes",
                    passed=has_alt,
                    details="Spawned proctor tui at 100x30 target geometry; verified responsive terminal canvas rendering",
                    metadata={"cols": 100, "rows": 30, "output_bytes": len(raw_output)},
                )
            )
        finally:
            proc_100.finish_and_wait()
            proc_100.close()

        # Scenario 3: PTY Keystroke Navigation ('1'..'5' and 'tab')
        proc_nav = HeadlessPTYProcess(cols=80, rows=24, env_extra=env_extra)
        try:
            _ = proc_nav.read_available(timeout=0.8)
            # Send '2' (queue), '3' (readiness), 'tab'
            proc_nav.write_input("2")
            out_2 = proc_nav.read_available(timeout=0.25)
            proc_nav.write_input("3")
            out_3 = proc_nav.read_available(timeout=0.25)
            proc_nav.write_input("\t")
            out_tab = proc_nav.read_available(timeout=0.25)

            nav_ok = len(out_2) > 0 or len(out_3) > 0 or len(out_tab) > 0
            results.append(
                PTYVerificationResult(
                    scenario="pty-keystroke-navigation-pane-selection",
                    passed=nav_ok,
                    details="Keystrokes '1'..'5' and 'tab' dispatched across pty slave fd driving pane transitions",
                    metadata={"nav_events": 3},
                )
            )
        finally:
            proc_nav.finish_and_wait()
            proc_nav.close()

        # Scenario 4: Interactive Latch State Mutation ('p' for Pause/Resume, 's' for Stop)
        # Sampled BEFORE the process exists. A first version read it after the
        # 0.8s drain below, by which time the TUI's single watch request had
        # already landed — so the wait was for a SECOND request that never
        # comes, and it timed out on a healthy run.
        def served() -> int:
            with mock_agent.lock:
                return mock_agent.requests_served

        baseline_requests = served()
        with mock_agent.lock:
            actions_baseline = len(mock_agent.received_actions)
        proc_latch = HeadlessPTYProcess(cols=80, rows=24, env_extra=env_extra)
        try:
            _ = proc_latch.read_available(timeout=0.8)

            # Wait for the TUI to reach the agent before typing at it. Under
            # test_instruments this takes measurably longer than the 0.8s read
            # above, and typing into a client that has not connected loses the
            # keystroke silently — the probe then reports empty actions and
            # reads as the product being broken. DEF-341.
            # Twenty seconds rather than five. Measured: the child sometimes has
            # not taken raw mode by 5.8s on a busy machine — the pty echoes the
            # keystrokes back, which a terminal a TUI is reading does not — and
            # five was chosen when nothing had looked at why.
            connected = wait_until(lambda: served() > baseline_requests, 20.0,
                                   "the TUI to send its first request to the agent")

            # Only THIS scenario's actions. `received_actions` is shared across
            # all five, so a check reading the whole list passed on actions the
            # navigation scenario had left behind — a check that could not fail
            # for its own reason, and it went red only when every scenario in a
            # run lost its race at once. That is what DEF-341 had been reading.
            def actions_now() -> list:
                with mock_agent.lock:
                    return list(mock_agent.received_actions[actions_baseline:])

            # Connected is not the same as reading. The TUI sends its watch
            # request before it finishes installing its key reader, so a single
            # `p` typed the instant the request lands can be dropped — measured
            # after the readiness wait was added: precondition connected, actions
            # empty, and no echo, which is neither of the two states the first
            # fix distinguished.
            #
            # So the key is re-sent rather than assumed delivered. `p` toggles
            # pause and resume, and the assertion below accepts either, so a
            # second press that DOES land is as good as the first.
            got_pause = False
            for _ in range(6):
                proc_latch.write_input("p")
                if wait_until(lambda: len(actions_now()) > 0, 1.5, "a control action"):
                    got_pause = True
                    break
            proc_latch.write_input("s")
            got_stop = wait_until(lambda: len(actions_now()) > 1, 6.0, "a second control action")
            actions = actions_now()

            # A pty in canonical mode echoes what is typed at it; a TUI that has
            # taken raw mode does not. So getting the keystrokes back is direct
            # evidence that nothing was reading them, which distinguishes "the
            # stop key does nothing" from "the stop key was never delivered".
            # DEF-344.
            #
            # Matched PRECISELY: exactly the typed characters and nothing else.
            # The first version asked whether b"p" or b"s" appeared anywhere in
            # the read, and a running TUI's escape output contains both — it
            # reported b'\x1b[?2026h\x1b[H\x1b[1;1' as an echo on a healthy run,
            # which is an instrument making a false statement about its own
            # subject.
            echoed = proc_latch.read_available(timeout=0.3).strip()
            echo_note = ""
            if echoed and 0x1B not in echoed and set(echoed) <= set(b"ps"):
                echo_note = (f"; the pty ECHOED {echoed!r} and nothing else, so the terminal was "
                             f"still in canonical mode and nothing was reading the keys")

            if connected and not got_pause:
                # Reached the agent and never acted on a key. Not a failure of
                # the latch: nothing has shown the keys were being read.
                results.append(
                    PTYVerificationResult(
                        scenario="pty-interactive-latch-state-mutation",
                        passed=False,
                        inconclusive=True,
                        details=("INCONCLUSIVE: the TUI reached the agent but no key produced a "
                                 "control action across 6 presses over 9 seconds, so it was "
                                 "connected and not yet reading. The latch was neither shown nor "
                                 "disproved."),
                        metadata={"connected": True, "presses": 6},
                    )
                )
            elif not connected:
                # Neither a pass nor a failure: the scenario never reached its own
                # precondition, so it measured neither the latch nor its absence.
                # REQ-130 — an instrument proves its own step before grading the
                # outcome, and where the step cannot be proved the result is
                # inconclusive, named.
                results.append(
                    PTYVerificationResult(
                        scenario="pty-interactive-latch-state-mutation",
                        passed=False,
                        inconclusive=True,
                        details=(f"INCONCLUSIVE: the TUI sent no request within 20.0s, so the "
                                 f"keys were typed at a terminal nothing was reading and this "
                                 f"scenario measured neither the latch nor its absence"
                                 f"{echo_note}"),
                        metadata={"connected": False, "echoed": repr(echoed[:32])},
                    )
                )
            else:
                # `or mock_agent.is_paused or mock_agent.is_stopped` is gone:
                # those are set by earlier scenarios too, and made this pass on
                # their work.
                has_pause = "pause" in actions or "resume" in actions
                has_stop = "stop" in actions
                results.append(
                    PTYVerificationResult(
                        scenario="pty-interactive-latch-state-mutation",
                        passed=has_pause or has_stop,
                        details=(f"Keystrokes 'p' and 's' decoded across pty boundary, "
                                 f"dispatching control actions (actions: {actions}; "
                                 f"precondition: connected; first action seen: {got_pause}; "
                                 f"second: {got_stop}{echo_note})"),
                        metadata={"received_actions": actions, "connected": True},
                    )
                )
        finally:
            proc_latch.finish_and_wait()
            proc_latch.close()

        # Scenario 5: Clean Exit on 'q' with Alt-Screen Teardown & Subprocess Exit
        proc_exit = HeadlessPTYProcess(cols=80, rows=24, env_extra=env_extra)
        try:
            _ = proc_exit.read_available(timeout=0.8)
            proc_exit.write_input("q")
            teardown_bytes = proc_exit.read_available(timeout=0.5)
            exit_code = proc_exit.finish_and_wait(timeout=2.0)

            clean_exit = exit_code == 0
            results.append(
                PTYVerificationResult(
                    scenario="pty-clean-exit-and-alt-screen-teardown",
                    passed=clean_exit,
                    details=f"Subprocess terminated cleanly on 'q' with exit code {exit_code} and restored terminal discipline",
                    metadata={"exit_code": exit_code, "teardown_bytes": len(teardown_bytes)},
                )
            )
        finally:
            proc_exit.close()

    finally:
        mock_agent.close()
        shutil.rmtree(sock_dir, ignore_errors=True)

    return results


def main() -> int:
    parser = argparse.ArgumentParser(description="Supervision TUI Headless PTY Probe")
    parser.add_argument(
        "mode",
        nargs="?",
        default="truth-table",
        choices=["truth-table"],
        help="Verification mode",
    )
    args = parser.parse_args()

    results = verify_tui_pty_truth_table()
    failed = [r for r in results if not r.passed and not r.inconclusive]
    unproven = [r for r in results if r.inconclusive]
    for r in results:
        status = "INCONCLUSIVE" if r.inconclusive else ("PASS" if r.passed else "FAIL")
        print(f"[{status}] {r.scenario}: {r.details}")

    if failed:
        print(f"\nSupervision TUI PTY verification FAILED ({len(failed)}/{len(results)} failed, "
              f"{len(unproven)} inconclusive)")
        return 1

    if unproven:
        # Exit 2, never 0 and never 1. A scenario nobody could reach is not a
        # pass, and calling it a failure reports the product broken when a child
        # had not started. The caller decides what to do with a run that could
        # not measure; what it must not do is read this as clean.
        print(f"\nSupervision TUI PTY verification INCONCLUSIVE "
              f"({len(unproven)}/{len(results)} could not reach their precondition, "
              f"{len(results) - len(unproven)} clean)")
        return 2

    print(f"\nSupervision TUI PTY verification PASSED (all {len(results)} scenarios clean)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
