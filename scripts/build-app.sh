#!/usr/bin/env bash
# Build Proctor.app into .build/Proctor.app.
#
# The app bundle is not cosmetic. macOS attributes a TCC grant to the
# responsible process, and a bundle at a stable path launched by launchd is its
# own responsible process. That is what makes the Accessibility grant stick to
# Proctor rather than to whichever MCP host happened to start it.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/.build"
APP="$BUILD_DIR/Proctor.app"
CONTENTS="$APP/Contents"
MACOS_DIR="$CONTENTS/MacOS"
# Read from the plist so the identifier has exactly one home.
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$REPO_ROOT/Apps/Proctor/Info.plist")"
RESOURCES_DIR="$CONTENTS/Resources"
PLIST_SRC="$REPO_ROOT/Apps/Proctor/Info.plist"
ICNS_SRC="$REPO_ROOT/Apps/Proctor/Proctor.icns"

say() { printf '%s\n' "$*"; }

cd "$REPO_ROOT"

say "==> swift build -c release"
swift build -c release

BIN_DIR="$(swift build -c release --show-bin-path)"
AGENT_BIN="$BIN_DIR/proctor-agent"
SHIM_BIN="$BIN_DIR/proctor-shim"
UI_BIN="$BIN_DIR/Proctor"

for binary in "$AGENT_BIN" "$SHIM_BIN" "$UI_BIN"; do
  if [ ! -x "$binary" ]; then
    say "error: expected a built binary at $binary" >&2
    exit 1
  fi
done

say "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$AGENT_BIN" "$MACOS_DIR/proctor-agent"
# The shim rides along so it has a stable, bundle-relative path to be
# registered with an MCP host from. It holds no permissions either way, and its
# own installer knows how to find the bundle it is sitting inside.
cp "$SHIM_BIN" "$MACOS_DIR/proctor-shim"
# The bundle's main executable: the setup walkthrough and status window. It
# holds no permissions of its own and only reads the agent's health, but it
# lives in this bundle so that opening Proctor shows something rather than
# silently doing nothing.
cp "$UI_BIN" "$MACOS_DIR/Proctor"
cp "$PLIST_SRC" "$CONTENTS/Info.plist"

if [ -f "$ICNS_SRC" ]; then
  cp "$ICNS_SRC" "$RESOURCES_DIR/Proctor.icns"
  say "    icon: Proctor.icns"
else
  say "    notice: no icon at Apps/Proctor/Proctor.icns — building without one."
  say "            The consent dialog will show a generic icon. CFBundleIconFile"
  say "            already points at Proctor.icns, so dropping one in is enough."
fi

# PkgInfo is legacy but costs nothing and keeps older tooling happy.
printf 'APPL????' > "$CONTENTS/PkgInfo"

# Signing. Pass a Developer ID identity to get a stable designated requirement;
# without one this falls back to ad-hoc, which is fine for development and
# costs you the grants on every rebuild.
#
#   scripts/build-app.sh "Developer ID Application: Your Name (TEAMID)"
#
# --deep is deprecated and signs inner code in the wrong order, so each nested
# binary is signed first and the bundle last.
IDENTITY="${1:-${PROCTOR_SIGN_IDENTITY:--}}"

if [ "$IDENTITY" = "-" ]; then
  say "==> ad-hoc signing (no identity given)"
  TIMESTAMP_FLAG=""
else
  say "==> signing as: $IDENTITY"
  TIMESTAMP_FLAG="--timestamp"
fi

# -i pins every nested binary to the bundle identifier. Without it each one is
# signed under its own filename, so the agent's identity is "proctor-agent"
# rather than the bundle's — and TCC then has three identities to reason about
# where the user granted permission to one app.
for binary in "$MACOS_DIR/proctor-agent" "$MACOS_DIR/proctor-shim" "$MACOS_DIR/Proctor"; do
  codesign --force --sign "$IDENTITY" -i "$BUNDLE_ID" --options runtime $TIMESTAMP_FLAG "$binary"
done
codesign --force --sign "$IDENTITY" --options runtime $TIMESTAMP_FLAG "$APP"
codesign --verify --strict --deep "$APP"

if [ "$IDENTITY" != "-" ]; then
  say ""
  say "    designated requirement:"
  codesign -d -r- "$APP" 2>&1 | sed 's/^/      /'
fi

say ""
say "Built $APP"
if [ "$IDENTITY" != "-" ]; then
  say ""
  say "Signed with a real identity. The designated requirement is team-scoped, so"
  say "Accessibility and Screen Recording survive rebuilds and upgrades."
  say ""
  say "To distribute this to another Mac it also has to be notarised:"
  say "  scripts/notarize.sh <keychain-profile>"
  say ""
  say "Next: scripts/install.sh"
  exit 0
fi

say ""
say "Signing caveat — read this before wondering where your grant went."
say ""
say "  This bundle is ad-hoc signed (--sign -). An ad-hoc signature has no"
say "  stable designated requirement, so TCC records the grant against the"
say "  exact bytes of this build. Rebuilding changes the bytes, the grant no"
say "  longer matches, and Accessibility and Screen Recording silently stop"
say "  applying — usually surfacing as 'elements not found' rather than as a"
say "  permission error. Re-granting after each rebuild is the cost of ad-hoc"
say "  signing. That is fine for development and wrong for distribution."
say ""
say "  For distribution, sign with a Developer ID identity and notarise. The"
say "  team-scoped designated requirement then survives rebuilds and upgrades:"
say ""
# codesign --sign "Developer ID Application: Your Name (TEAMID)" \
#          --timestamp --options runtime --force \
#          "$APP"
#
# ditto -c -k --keepParent "$APP" "$BUILD_DIR/Proctor.zip"
#
# xcrun notarytool submit "$BUILD_DIR/Proctor.zip" \
#          --keychain-profile "AC_PASSWORD" --wait
#
# xcrun stapler staple "$APP"
say '  codesign --sign "Developer ID Application: Your Name (TEAMID)" \'
say '           --timestamp --options runtime --force .build/Proctor.app'
say '  ditto -c -k --keepParent .build/Proctor.app .build/Proctor.zip'
say '  xcrun notarytool submit .build/Proctor.zip \'
say '           --keychain-profile "AC_PASSWORD" --wait'
say '  xcrun stapler staple .build/Proctor.app'
say ""
say "Next: scripts/install.sh"
