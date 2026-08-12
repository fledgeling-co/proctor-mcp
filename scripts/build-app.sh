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

for binary in "$AGENT_BIN" "$SHIM_BIN"; do
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

say "==> ad-hoc signing"
codesign --force --deep --sign - --options runtime "$APP"
codesign --verify --strict "$APP"

say ""
say "Built $APP"
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
