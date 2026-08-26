#!/usr/bin/env bash
# Install Proctor: build the app, put it in /Applications, register it as a
# launchd user agent, and walk the two grants it needs.
#
# Idempotent. Running it twice reinstalls over the top and reloads the agent.
#
# The app bundle lives in /Applications (system-wide), while the launchd job
# stays a per-user agent in ~/Library/LaunchAgents — that per-user agent is what
# gives macOS a stable responsible-process identity for the TCC grants. Because
# the grants key on the Developer ID signature and not the path, moving the
# bundle between ~/Applications and /Applications does not disturb them.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILT_APP="$REPO_ROOT/.build/Proctor.app"

BUNDLE_ID="app.fledgeling.procter"
LABEL="app.fledgeling.procter.agent"

APP_DEST="/Applications/Proctor.app"
OLD_USER_APP="$HOME/Applications/Proctor.app"
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

# The notary keychain profile used to notarise a fresh build. Skipped cleanly
# when it does not exist (the install is then signed but not notarised, which is
# fine for this Mac; distribution to other Macs needs it). Override with
# PROCTOR_NOTARY_PROFILE, or set PROCTOR_SKIP_NOTARIZE=1 to never notarise.
NOTARY_PROFILE="${PROCTOR_NOTARY_PROFILE:-proctor}"

say() { printf '%s\n' "$*"; }

# The signing identity. Distribution needs a Developer ID Application signature:
# it gives a team-scoped designated requirement, which is what makes the TCC
# grants survive rebuilds and upgrades. Ad-hoc ties them to the exact bytes and
# throws them away on every rebuild, so it is a last resort, not the default.
#
#   scripts/install.sh "Developer ID Application: Your Name (TEAMID)"
#   PROCTOR_SIGN_IDENTITY="..." scripts/install.sh
#
# With neither given, the one Developer ID Application identity in your keychain
# is detected and used, so a normal install is signed rather than ad-hoc.
IDENTITY="${1:-${PROCTOR_SIGN_IDENTITY:-}}"
if [ -z "$IDENTITY" ]; then
  DETECTED="$(security find-identity -v -p codesigning 2>/dev/null \
    | grep 'Developer ID Application' | head -1 | sed -E 's/.*"([^"]+)".*/\1/')"
  if [ -n "$DETECTED" ]; then
    IDENTITY="$DETECTED"
    say "==> using Developer ID identity: $IDENTITY"
  else
    say "==> no Developer ID Application identity found — falling back to ad-hoc."
    say "    Grants will be revoked on the next rebuild. Install a Developer ID"
    say "    certificate, or pass one to scripts/install.sh, to make them stick."
  fi
fi

# Rebuilding re-signs, and re-signing throws away a stapled notarisation
# ticket. So a bundle that is already notarised is installed as it stands
# unless PROCTOR_FORCE_BUILD says otherwise.
STAPLED=no
if [ -d "$BUILT_APP" ] && xcrun stapler validate "$BUILT_APP" >/dev/null 2>&1; then
  STAPLED=yes
fi

# ...but only while it still matches the source it was built from. Reusing a
# stapled bundle whose sources have moved installs the previous build and says
# "notarised: yes" while doing it, which is indistinguishable from success.
# Measured 2026-08-19: two consecutive installs shipped a binary predating the
# edit they were run to install, and the second was only caught by reading the
# file's timestamp. Newer source wins; the rebuild re-notarises below.
STALE=no
if [ "$STAPLED" = yes ]; then
  BUILT_BINARY="$BUILT_APP/Contents/MacOS/proctor-agent"
  if [ ! -f "$BUILT_BINARY" ]; then
    STALE=yes
  elif [ -n "$(find "$REPO_ROOT/Sources" "$REPO_ROOT/Apps" "$REPO_ROOT/Package.swift" \
                    -newer "$BUILT_BINARY" -print -quit 2>/dev/null)" ]; then
    STALE=yes
  fi
fi

# PROCTOR_PLAN_ONLY=1 — print what this run WOULD do and exit, before anything
# is built, signed, notarised or copied.
#
# It exists because the installer's controls could not otherwise be actuated by
# a test. PRO-0160 asks for every declared control to be driven by a case that
# reads an effect, and the installer's controls are the environment variables an
# operator sets; the only way to observe one taking effect used to be to run an
# install, which writes to /Applications and can submit a build to Apple. Now the
# decision each variable governs is readable without any of that happening.
#
# Every line below is the same expression the run itself uses, so a plan that
# disagrees with the install would be a bug in one of them rather than a
# separate model of the script.
if [ -n "${PROCTOR_PLAN_ONLY:-}" ]; then
  say "==> plan only, nothing will be built, signed, notarised or installed"
  IDENTITY_SHOWN="$IDENTITY"
  [ -z "$IDENTITY_SHOWN" ] && IDENTITY_SHOWN="<none — ad-hoc>"
  say "    identity:        $IDENTITY_SHOWN"
  say "    notary profile:  $NOTARY_PROFILE"
  say "    bundle stapled:  $STAPLED"
  say "    bundle stale:    $STALE"
  if [ "$STAPLED" = yes ] && { [ "$STALE" = no ] || [ -n "${PROCTOR_REUSE_BUNDLE:-}" ]; } \
     && [ -z "${PROCTOR_FORCE_BUILD:-}" ]; then
    say "    will build:      no — reusing the notarised bundle as built"
  else
    say "    will build:      yes"
  fi
  if [ -n "$IDENTITY" ] && [ -z "${PROCTOR_SKIP_NOTARIZE:-}" ]; then
    say "    will notarise:   yes (profile $NOTARY_PROFILE)"
  else
    say "    will notarise:   no"
    [ -n "${PROCTOR_SKIP_NOTARIZE:-}" ] && say "                     because PROCTOR_SKIP_NOTARIZE is set"
    [ -z "$IDENTITY" ] && say "                     because no Developer ID identity was found"
  fi
  say "    destination:     $APP_DEST"
  exit 0
fi

if [ "$STAPLED" = yes ] && [ "$STALE" = yes ] && [ -z "${PROCTOR_REUSE_BUNDLE:-}" ]; then
  say "==> the notarised bundle is older than the source it was built from — rebuilding"
  say "    (PROCTOR_REUSE_BUNDLE=1 installs it as it stands anyway)"
fi

if [ "$STAPLED" = yes ] && { [ "$STALE" = no ] || [ -n "${PROCTOR_REUSE_BUNDLE:-}" ]; } \
   && [ -z "${PROCTOR_FORCE_BUILD:-}" ]; then
  say "==> using the notarised bundle as built (PROCTOR_FORCE_BUILD=1 to rebuild)"
else
  say "==> building"
  if [ -n "$IDENTITY" ]; then
    "$REPO_ROOT/scripts/build-app.sh" "$IDENTITY"
  else
    "$REPO_ROOT/scripts/build-app.sh"
  fi

  # Notarise the fresh build when it is Developer ID signed and a notary profile
  # is available, so the default install is notarised rather than merely signed.
  if [ -n "$IDENTITY" ] && [ -z "${PROCTOR_SKIP_NOTARIZE:-}" ]; then
    if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
      say ""
      say "==> notarising the fresh build (profile: $NOTARY_PROFILE)"
      "$REPO_ROOT/scripts/notarize.sh" "$NOTARY_PROFILE"
    else
      say "    notary profile '$NOTARY_PROFILE' not found — installing signed but"
      say "    NOT notarised. Fine for this Mac; distribution to others needs it."
      say "    Create one: xcrun notarytool store-credentials $NOTARY_PROFILE ..."
    fi
  fi
fi

if [ ! -d "$BUILT_APP" ]; then
  say "error: $BUILT_APP was not produced by the build" >&2
  exit 1
fi

# Migrate away from the old per-user location if a previous install left one.
if [ -d "$OLD_USER_APP" ]; then
  say ""
  say "==> removing the old per-user install at $OLD_USER_APP"
  rm -rf "$OLD_USER_APP"
fi

say ""
say "==> installing to $APP_DEST"
# Booting the agent out first means the running binary is not replaced underneath
# launchd, which is what leaves a zombie holding the socket.
launchctl bootout "$TARGET/$LABEL" >/dev/null 2>&1 || true

# /Applications is group-writable by admin on a standard Mac, so no sudo is
# needed there; fall back to sudo only when the destination is not writable.
APP_PARENT="$(dirname "$APP_DEST")"
if [ -w "$APP_PARENT" ]; then
  rm -rf "$APP_DEST"
  # ditto preserves the signature's extended attributes; cp -R on some paths does
  # not, and a broken signature reads as a revoked grant.
  ditto "$BUILT_APP" "$APP_DEST"
else
  say "    $APP_PARENT is not writable by your user — using sudo (you may be prompted)"
  sudo rm -rf "$APP_DEST"
  sudo ditto "$BUILT_APP" "$APP_DEST"
fi

if codesign -dv "$APP_DEST" 2>&1 | grep -q 'Signature=adhoc'; then
  say "    signature: ad-hoc — grants are tied to these exact bytes and will be"
  say "               revoked by the next rebuild. Pass a Developer ID identity"
  say "               to scripts/install.sh to make them stick."
else
  say "    signature: $(codesign -dv "$APP_DEST" 2>&1 | grep '^Authority' | head -1 | cut -d= -f2-)"
  if xcrun stapler validate "$APP_DEST" >/dev/null 2>&1; then
    say "    notarised: yes (stapled ticket present)"
  else
    say "    notarised: no (signed only; fine locally, distribution needs it)"
  fi
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
say "==> opening Proctor"
say ""
say "Proctor's window walks the two grants (Accessibility and Screen Recording),"
say "and both attach to Proctor itself — not this terminal, not the shim, and not"
say "your MCP host. After that it stays in the menu bar and starts at login."
say ""
say "Screen Recording cannot be granted silently on any macOS version, so a person"
say "has to click it. After granting it, macOS may ask you to quit and reopen"
say "Proctor; the window does this for you, or run"
say ""
say "  launchctl kickstart -k $TARGET/$LABEL"
say ""

# Launch the app: it registers itself as a login item, shows the menu-bar icon,
# and on first run walks the grants. -F ignores any saved window state.
open -F "$APP_DEST" || true

say "==> register with an MCP host"
say ""
say "  claude mcp add proctor -- $SHIM_BIN serve --profile core"
say ""
say "The tool catalogue is re-sent every turn and survives context compaction,"
say "so the advertised surface is a standing cost. --profile core advertises the"
say "ten tools that drive a Mac (~6.8k tokens); --profile full advertises all"
say "nineteen (~11.3k). Widen to scripting or full for flows, policy, kill and"
say "the CUA adapters."
say ""
say "The shim now lives under /Applications, so if you registered a previous"
say "install from ~/Applications, re-run the line above to point your host at"
say "the new path. Then check everything with scripts/doctor.sh, or proctor_doctor."
