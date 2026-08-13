#!/usr/bin/env bash
# Shell-level preflight. Runs before anything is installed and without talking
# to the agent, so it can answer "why is nothing working" when the agent itself
# is the thing that is missing.
#
# Exits 0 when everything required is present, 1 otherwise. Warnings alone do
# not fail the run.
#
# The richer check is the proctor_doctor tool, which reports the actual TCC
# grants, live observers and attached apps. This one only knows what the
# filesystem and launchd know.

set -u

BUNDLE_ID="app.fledgeling.procter"
LABEL="app.fledgeling.procter.agent"
MIN_MACOS_MAJOR=14

SUPPORT_DIR="$HOME/Library/Application Support/$BUNDLE_ID"
SOCKET="$SUPPORT_DIR/agent.sock"
LOG="$HOME/Library/Logs/Proctor/agent.log"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
TARGET="gui/$(id -u)"

FAILURES=0
WARNINGS=0

ok()   { printf '  ok    %-22s %s\n' "$1" "$2"; }
warn() { printf '  warn  %-22s %s\n' "$1" "$2"; WARNINGS=$((WARNINGS + 1)); }
bad()  { printf '  FAIL  %-22s %s\n' "$1" "$2"; FAILURES=$((FAILURES + 1)); }
note() { printf '        %s\n' "$1"; }

printf 'Proctor preflight\n\n'

# --- system -----------------------------------------------------------------

MACOS_VERSION="$(sw_vers -productVersion 2>/dev/null || echo unknown)"
MACOS_MAJOR="${MACOS_VERSION%%.*}"
if [ "$MACOS_VERSION" = "unknown" ]; then
  bad "macOS" "could not read the version — is this macOS?"
elif [ "$MACOS_MAJOR" -ge "$MIN_MACOS_MAJOR" ] 2>/dev/null; then
  ok "macOS" "$MACOS_VERSION (build $(sw_vers -buildVersion 2>/dev/null))"
else
  bad "macOS" "$MACOS_VERSION — Proctor needs $MIN_MACOS_MAJOR or later"
fi

if [ "${MACOS_MAJOR:-0}" -ge 27 ] 2>/dev/null; then
  note "macOS 27+: Accessibility is configured through declarative App Settings;"
  note "the legacy PPPC profile path for Accessibility no longer applies."
fi

if command -v swift >/dev/null 2>&1; then
  SWIFT_VERSION="$(swift --version 2>&1 | head -1)"
  ok "swift" "$SWIFT_VERSION"
else
  bad "swift" "not on PATH — install Xcode or the Swift toolchain to build"
fi

if xcode-select -p >/dev/null 2>&1; then
  ok "developer tools" "$(xcode-select -p)"
else
  bad "developer tools" "xcode-select -p failed — run xcode-select --install"
fi

printf '\n'

# --- installation -----------------------------------------------------------

APP=""
for candidate in "$HOME/Applications/Proctor.app" "/Applications/Proctor.app"; do
  if [ -d "$candidate" ]; then APP="$candidate"; break; fi
done

if [ -n "$APP" ]; then
  ok "app bundle" "$APP"
  AGENT_BIN="$APP/Contents/MacOS/proctor-agent"
  if [ -x "$AGENT_BIN" ]; then
    ok "agent binary" "$AGENT_BIN"
  else
    bad "agent binary" "missing or not executable at $AGENT_BIN"
  fi
  if [ -x "$APP/Contents/MacOS/proctor-shim" ]; then
    ok "shim binary" "$APP/Contents/MacOS/proctor-shim"
  else
    warn "shim binary" "not in the bundle — register whichever shim you built"
  fi
  SIGNING="$(codesign -dv "$APP" 2>&1 | awk -F= '/^Signature|^TeamIdentifier/ {print $2}' | paste -sd' ' -)"
  if codesign -dv "$APP" 2>&1 | grep -q 'Signature=adhoc'; then
    warn "code signature" "ad-hoc — TCC grants are tied to these exact bytes"
    note "Every rebuild revokes the grants. Expected in development."
  elif [ -n "$SIGNING" ]; then
    ok "code signature" "$SIGNING"
  else
    warn "code signature" "unsigned or unreadable"
  fi
else
  bad "app bundle" "not installed in ~/Applications or /Applications"
  note "Run scripts/install.sh."
fi

if [ -f "$PLIST" ]; then
  if plutil -lint "$PLIST" >/dev/null 2>&1; then
    ok "launchd plist" "$PLIST"
  else
    bad "launchd plist" "$PLIST is malformed"
  fi
else
  bad "launchd plist" "not written — run scripts/install.sh"
fi

if launchctl print "$TARGET/$LABEL" >/dev/null 2>&1; then
  STATE="$(launchctl print "$TARGET/$LABEL" 2>/dev/null | awk -F'= ' '/^\tstate = /{print $2; exit}')"
  PID="$(launchctl print "$TARGET/$LABEL" 2>/dev/null | awk -F'= ' '/^\tpid = /{print $2; exit}')"
  ok "launchd label" "$LABEL loaded (state=${STATE:-unknown} pid=${PID:-none})"
  if [ -z "${PID:-}" ]; then
    warn "agent process" "loaded but not running — check $LOG"
  fi
else
  bad "launchd label" "$LABEL is not loaded in $TARGET"
fi

if [ -d "$SUPPORT_DIR" ]; then
  ok "support directory" "$SUPPORT_DIR"
else
  bad "support directory" "missing — run scripts/install.sh"
fi

if [ -S "$SOCKET" ]; then
  ok "socket" "$SOCKET"
elif [ -e "$SOCKET" ]; then
  bad "socket" "$SOCKET exists but is not a socket — delete it and reload"
else
  bad "socket" "the agent has not bound $SOCKET"
fi

printf '\n'

# --- logs -------------------------------------------------------------------

if [ -f "$LOG" ]; then
  LOG_LINES="$(wc -l < "$LOG" | tr -d ' ')"
  RECENT_ERRORS="$(tail -n 200 "$LOG" 2>/dev/null \
    | grep -ciE 'error|fatal|fault|crash|denied|refused|not permitted' 2>/dev/null || true)"
  RECENT_ERRORS="${RECENT_ERRORS:-0}"
  if [ "$RECENT_ERRORS" -gt 0 ]; then
    warn "agent log" "$RECENT_ERRORS error-ish lines in the last 200 of $LOG"
    tail -n 200 "$LOG" \
      | grep -iE 'error|fatal|fault|crash|denied|refused|not permitted' \
      | tail -n 3 | while IFS= read -r line; do note "$line"; done
  else
    ok "agent log" "$LOG ($LOG_LINES lines, no recent errors)"
  fi
else
  warn "agent log" "no log yet at $LOG — the agent has not run"
fi

# --- secure event input -----------------------------------------------------

SEI_PID="$(ioreg -l -d 1 -k IOConsoleUsers 2>/dev/null \
  | sed -n 's/.*"kCGSSessionSecureInputPID"=\([0-9-]*\).*/\1/p' | head -1)"
if [ -n "$SEI_PID" ] && [ "$SEI_PID" != "0" ]; then
  SEI_NAME="$(ps -p "$SEI_PID" -o comm= 2>/dev/null | sed 's|.*/||')"
  warn "secure event input" "active, held by pid $SEI_PID${SEI_NAME:+ ($SEI_NAME)}"
  note "Synthetic-event actions (click, hover, dragPath, and typing into a"
  note "secure field) are blocked while this is on. Process-directed actuation"
  note "through the accessibility plane is unaffected. Usually a password field"
  note "has focus somewhere, or a terminal is in secure keyboard entry mode."
else
  ok "secure event input" "not active"
fi

# --- verdict ----------------------------------------------------------------

printf '\n'
if [ "$FAILURES" -eq 0 ]; then
  printf 'Ready. %d warning(s).\n' "$WARNINGS"
  exit 0
fi

printf '%d check(s) failed, %d warning(s).\n' "$FAILURES" "$WARNINGS"
if [ -z "$APP" ]; then
  printf '\nProctor is not installed. Run:\n\n  scripts/install.sh\n'
fi
exit 1
