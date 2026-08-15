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
ICON_SRC_PNG="$REPO_ROOT/Apps/Proctor/icon-1024.png"

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
  say "    icon: Proctor.icns (committed)"
elif [ -f "$ICON_SRC_PNG" ]; then
  say "    icon: generating Proctor.icns from icon-1024.png"
  ICONSET="$BUILD_DIR/Proctor.iconset"
  rm -rf "$ICONSET"; mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z "$s" "$s" "$ICON_SRC_PNG" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z "$((s * 2))" "$((s * 2))" "$ICON_SRC_PNG" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$RESOURCES_DIR/Proctor.icns"
else
  say "    notice: no icon at Apps/Proctor/Proctor.icns or icon-1024.png — building without one."
  say "            The consent dialog will show a generic icon. CFBundleIconFile"
  say "            already points at Proctor.icns, so dropping one in is enough."
fi

# SwiftPM puts a target's resources in its own bundle beside the binary, and
# `Bundle.module` looks for that bundle in the main bundle's Resources. Copying
# it here — before signing, so the signature seals it — is what puts the run
# HUD's character in a build that anyone else runs. Without it the bay is empty
# and the run carries on, which is deliberate but is not what shipped art is for.
for resource_bundle in "$BIN_DIR"/*.bundle; do
  [ -e "$resource_bundle" ] || continue
  cp -R "$resource_bundle" "$RESOURCES_DIR/"
  say "    resources: $(basename "$resource_bundle")"
done

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

# PRO-0040. Two properties of the agent binary that nothing else would catch, and
# whose failures are both silent — one costs a person the ability to open the app,
# the other costs them their grants. Checked here because this is the one step the
# local installer and .github/workflows/release.yml both go through.
say "==> checking the agent's identity"

AGENT_PLIST_ID="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" \
  "$REPO_ROOT/Apps/Proctor/AgentInfo.plist" 2>/dev/null || true)"
AGENT_SIGINFO="$(codesign -dv "$MACOS_DIR/proctor-agent" 2>&1 || true)"

# 1. The agent presents an identity of its own. Without it, LaunchServices records
#    the agent as a running instance of Proctor.app, `open -a Proctor` activates a
#    process that has no window and exits 0, and the app cannot be opened at all
#    while its own agent is running.
if [ -z "$AGENT_PLIST_ID" ] || [ "$AGENT_PLIST_ID" = "$BUNDLE_ID" ]; then
  say "error: Apps/Proctor/AgentInfo.plist must declare a CFBundleIdentifier of its" >&2
  say "       own, distinct from $BUNDLE_ID. Sharing the app's identifier is what" >&2
  say "       stops 'open -a Proctor' from ever launching Proctor." >&2
  exit 1
fi

if ! printf '%s' "$AGENT_SIGINFO" | grep -q 'Info.plist entries='; then
  say "error: proctor-agent has no embedded __TEXT,__info_plist section." >&2
  say "       The linker flags on the ProctorAgent target in Package.swift are what" >&2
  say "       put it there. Without it the agent registers as an instance of the app" >&2
  say "       and 'open -a Proctor' silently opens nothing." >&2
  exit 1
fi

# 2. The agent is still signed under the APP's identifier. This is the expensive one.
#    TCC matches a process against the recorded designated requirement, which names
#    the signing identifier and the team. A codesign run that dropped `-i` would take
#    the embedded CFBundleIdentifier above as the signing identifier, rewrite the
#    requirement, and throw away Accessibility and Screen Recording — one release
#    later, with nothing failing in between. Screen Recording cannot be granted
#    silently on any macOS version, so that lands on a person as a manual re-grant.
if ! printf '%s' "$AGENT_SIGINFO" | grep -qx "Identifier=$BUNDLE_ID"; then
  say "error: proctor-agent's signing identifier is not $BUNDLE_ID." >&2
  say "       Found: $(printf '%s' "$AGENT_SIGINFO" | grep '^Identifier=' || echo '(none)')" >&2
  say "       The TCC grants key on this. Re-sign with -i \"$BUNDLE_ID\" — the agent's" >&2
  say "       own identity belongs in AgentInfo.plist, never in the signature." >&2
  exit 1
fi

say "    agent: LaunchServices identity $AGENT_PLIST_ID, signed as $BUNDLE_ID"

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
