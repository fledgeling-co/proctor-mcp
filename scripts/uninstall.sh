#!/usr/bin/env bash
# Remove Proctor: unload the launchd agent, delete its plist and the app.
#
#   scripts/uninstall.sh            leaves flows, logs and the socket directory
#   scripts/uninstall.sh --purge    removes those too
#
# Idempotent. Nothing here can revoke a TCC grant — see the closing note.

set -euo pipefail

BUNDLE_ID="app.fledgeling.procter"
LABEL="app.fledgeling.procter.agent"

APP_DEST="/Applications/Proctor.app"
OLD_USER_APP="$HOME/Applications/Proctor.app"
SUPPORT_DIR="$HOME/Library/Application Support/$BUNDLE_ID"
LOG_DIR="$HOME/Library/Logs/Proctor"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
TARGET="gui/$(id -u)"

PURGE=0
for arg in "$@"; do
  case "$arg" in
    --purge) PURGE=1 ;;
    -h|--help)
      printf 'usage: %s [--purge]\n' "$(basename "$0")"
      printf '  --purge  also remove %s and %s\n' "$SUPPORT_DIR" "$LOG_DIR"
      exit 0
      ;;
    *)
      printf 'unknown argument: %s\n' "$arg" >&2
      exit 2
      ;;
  esac
done

say() { printf '%s\n' "$*"; }

if launchctl bootout "$TARGET/$LABEL" >/dev/null 2>&1; then
  say "unloaded $LABEL"
else
  say "$LABEL was not loaded"
fi

if [ -f "$PLIST" ]; then
  rm -f "$PLIST"
  say "removed $PLIST"
else
  say "no plist at $PLIST"
fi

if [ -d "$APP_DEST" ]; then
  if [ -w "$(dirname "$APP_DEST")" ]; then
    rm -rf "$APP_DEST"
  else
    say "$(dirname "$APP_DEST") is not writable — using sudo (you may be prompted)"
    sudo rm -rf "$APP_DEST"
  fi
  say "removed $APP_DEST"
else
  say "no app at $APP_DEST"
fi

# Clean up an old per-user install if one is still around.
if [ -d "$OLD_USER_APP" ]; then
  rm -rf "$OLD_USER_APP"
  say "removed old per-user install $OLD_USER_APP"
fi

if [ "$PURGE" -eq 1 ]; then
  rm -rf "$SUPPORT_DIR" "$LOG_DIR"
  say "purged $SUPPORT_DIR"
  say "purged $LOG_DIR"
else
  say "kept $SUPPORT_DIR (flows, socket directory) — pass --purge to remove"
  say "kept $LOG_DIR — pass --purge to remove"
fi

say ""
say "The Accessibility and Screen Recording grants for Proctor are still in place."
say "No script can revoke a TCC grant; only you can, in"
say ""
say "  System Settings > Privacy & Security > Accessibility"
say "  System Settings > Privacy & Security > Screen Recording"
say ""
say "Select Proctor in each list and use the - button. Leaving the entries costs"
say "nothing but they will keep listing an app that is no longer on disk."
