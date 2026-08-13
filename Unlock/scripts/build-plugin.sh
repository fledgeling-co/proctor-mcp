#!/usr/bin/env bash
# Build ProctorUnlock.bundle — the SecurityAgent authorization mechanism.
#
# A SecurityAgent plugin has to be a Developer ID-signed, hardened-runtime,
# notarised bundle to load into the authorization host on macOS 26 — the same
# recipe as the app. An ad-hoc build will not load, and finding that out from
# a silent no-op in the login path is the worst place to learn it. So this
# refuses to produce anything the loader will reject: give it an identity.
#
#   Unlock/scripts/build-plugin.sh "Developer ID Application: Your Name (TEAMID)"
#
# then notarise it with Unlock/scripts/notarize-plugin.sh before installing.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$HERE/../plugin"
OUT_DIR="$HERE/../.build"
BUNDLE="$OUT_DIR/ProctorUnlock.bundle"
IDENTITY="${1:-${PROCTOR_SIGN_IDENTITY:-}}"

say() { printf '%s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

[ -n "$IDENTITY" ] || die "a signing identity is required — a SecurityAgent plugin will not load ad-hoc.
  Unlock/scripts/build-plugin.sh \"Developer ID Application: Your Name (TEAMID)\""

SDK="$(xcrun --show-sdk-path)"

rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
cp "$SRC_DIR/Info.plist" "$BUNDLE/Contents/Info.plist"

say "==> compiling"
clang -arch arm64 -bundle -isysroot "$SDK" \
  -mmacosx-version-min=14.4 \
  -framework Security -framework CoreFoundation \
  -o "$BUNDLE/Contents/MacOS/ProctorUnlock" \
  "$SRC_DIR/ProctorUnlock.c"

say "==> signing (hardened runtime, pinned identifier)"
codesign --force --sign "$IDENTITY" \
  -i app.fledgeling.procter.unlock \
  --options runtime --timestamp \
  "$BUNDLE"

codesign --verify --strict --verbose=2 "$BUNDLE" 2>&1 | sed 's/^/    /'
say ""
say "    designated requirement:"
codesign -d -r- "$BUNDLE" 2>&1 | sed 's/^/      /'

say ""
say "Built $BUNDLE"
say "Next: Unlock/scripts/notarize-plugin.sh <keychain-profile>, then install.sh."
