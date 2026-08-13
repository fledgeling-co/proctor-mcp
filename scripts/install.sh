#!/usr/bin/env bash
# Install Proctor: build the app, put it in ~/Applications, register it as a
# launchd user agent, and walk the two grants it needs.
#
# Idempotent. Running it twice reinstalls over the top and reloads the agent.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILT_APP="$REPO_ROOT/.build/Proctor.app"

BUNDLE_ID="app.fledgeling.procter"
LABEL="app.fledgeling.procter.agent"

APP_DEST="$HOME/Applications/Proctor.app"
SUPPORT_DIR="$HOME/Library/Application Support/$BUNDLE_ID"
SOCKET="$SUPPORT_DIR/agent.sock"
LOG_DIR="$HOME/Library/Logs/Proctor"
LOG="$LOG_DIR/agent.log"
# Sources/ProctorShim/Install.swift writes the same job when the shim installs
# a prebuilt bundle. Change one, change the other.
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
AGENT_BIN="$APP_DEST/Contents/MacOS/proctor-agent"
SHIM_BIN="$APP_DEST/Contents/MacOS/proctor-shim"
TARGET="gui/$(id -u)"

say() { printf '%s\n' "$*"; }

# Forward the signing identity. Without this the build falls back to ad-hoc and
# silently discards a Developer ID signature you just applied — and because TCC
# keys on the signature, that also throws away every grant the app had.
#
#   scripts/install.sh "Developer ID Application: Your Name (TEAMID)"
#   PROCTOR_SIGN_IDENTITY="..." scripts/install.sh
IDENTITY="${1:-${PROCTOR_SIGN_IDENTITY:-}}"

# Rebuilding re-signs, and re-signing throws away a stapled notarisation
# ticket. So a bundle that is already notarised is installed as it stands
# unless PROCTOR_FORCE_BUILD says otherwise.
STAPLED=no
if [ -d "$BUILT_APP" ] && xcrun stapler validate "$BUILT_APP" >/dev/null 2>&1; then
  STAPLED=yes
fi

if [ "$STAPLED" = yes ] && [ -z "${PROCTOR_FORCE_BUILD:-}" ]; then
  say "==> using the notarised bundle as built (PROCTOR_FORCE_BUILD=1 to rebuild)"
else
  say "==> building"
  if [ -n "$IDENTITY" ]; then
    "$REPO_ROOT/scripts/build-app.sh" "$IDENTITY"
  else
    "$REPO_ROOT/scripts/build-app.sh"
  fi
fi

if [ ! -d "$BUILT_APP" ]; then
  say "error: $BUILT_APP was not produced by the build" >&2
  exit 1
fi

say ""
say "==> installing to $APP_DEST"
mkdir -p "$HOME/Applications"
# Booting the agent out first means the running binary is not replaced underneath
# launchd, which is what leaves a zombie holding the socket.
launchctl bootout "$TARGET/$LABEL" >/dev/null 2>&1 || true
rm -rf "$APP_DEST"
# ditto preserves the signature's extended attributes; cp -R on some paths does
# not, and a broken signature reads as a revoked grant.
ditto "$BUILT_APP" "$APP_DEST"

if codesign -dv "$APP_DEST" 2>&1 | grep -q 'Signature=adhoc'; then
  say "    signature: ad-hoc — grants are tied to these exact bytes and will be"
  say "               revoked by the next rebuild. Pass a Developer ID identity"
  say "               to scripts/install.sh to make them stick."
else
  say "    signature: $(codesign -dv "$APP_DEST" 2>&1 | grep '^Authority' | head -1 | cut -d= -f2-)"
fi

mkdir -p "$SUPPORT_DIR" "$LOG_DIR" "$HOME/Library/LaunchAgents"
# A socket left behind by a killed agent stops the new one binding.
rm -f "$SOCKET"

say "==> writing $PLIST"
cat > "$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>$LABEL</string>
	<key>ProgramArguments</key>
	<array>
		<string>$AGENT_BIN</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<key>KeepAlive</key>
	<dict>
		<key>SuccessfulExit</key>
		<false/>
	</dict>
	<key>StandardErrorPath</key>
	<string>$LOG</string>
	<key>ProcessType</key>
	<string>Interactive</string>
</dict>
</plist>
PLIST_EOF

plutil -lint "$PLIST" >/dev/null

say "==> loading $LABEL"
launchctl bootstrap "$TARGET" "$PLIST"
launchctl kickstart -k "$TARGET/$LABEL" >/dev/null 2>&1 || true

say "==> waiting for the socket"
for _ in $(seq 1 40); do
  if [ -S "$SOCKET" ]; then break; fi
  sleep 0.25
done

if [ -S "$SOCKET" ]; then
  say "    up: $SOCKET"
else
  say "    the agent did not bind $SOCKET within 10 seconds."
  say "    Check $LOG, then run scripts/doctor.sh."
fi

say ""
say "==> grants"
say ""
say "Two grants are needed, and both attach to Proctor — not to this terminal,"
say "not to the shim, and not to your MCP host. Opening both panes now."
say ""
say "  Accessibility     turn on the switch next to Proctor."
say "  Screen Recording  turn on the switch next to Proctor."
say ""
say "If Proctor is not listed, use the + button and pick $APP_DEST."
say "Screen Recording cannot be granted silently on any macOS version, so this"
say "step is manual by design. After granting Screen Recording, macOS may ask"
say "you to quit and reopen Proctor: run"
say ""
say "  launchctl kickstart -k $TARGET/$LABEL"
say ""

open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" || true
sleep 1
open "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture" || true

say "==> register with an MCP host"
say ""
say "  claude mcp add proctor -- $SHIM_BIN serve"
say ""
say "Then check everything with scripts/doctor.sh, or the proctor_doctor tool."
