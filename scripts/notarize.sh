#!/usr/bin/env bash
# Notarise a Developer ID signed Proctor.app and staple the ticket to it.
#
# Notarisation matters for *distribution*: without a stapled ticket, Gatekeeper
# on another Mac refuses the app or makes the user fight a dialog to open it.
# It is not what makes the TCC grants stable — that is the Developer ID
# signature's team-scoped designated requirement, which scripts/build-app.sh
# applies when you give it an identity. So a build you only ever run on this
# machine does not need this script; one you send anywhere does.
#
# Credentials are yours and are never stored here. Create a keychain profile
# once, with an app-specific password from appleid.apple.com:
#
#   xcrun notarytool store-credentials proctor \
#       --apple-id you@example.com --team-id TEAMID --password abcd-efgh-ijkl-mnop
#
# then:  scripts/notarize.sh proctor

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$REPO_ROOT/.build"
APP="$BUILD_DIR/Proctor.app"
ZIP="$BUILD_DIR/Proctor.zip"
PROFILE="${1:-}"

say() { printf '%s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

[ -n "$PROFILE" ] || die "usage: scripts/notarize.sh <keychain-profile>

Create one first:
  xcrun notarytool store-credentials <profile> \\
      --apple-id <you@example.com> --team-id <TEAMID> --password <app-specific-password>"

[ -d "$APP" ] || die "no app at $APP — run scripts/build-app.sh first"

# An ad-hoc signature cannot be notarised, and finding that out from Apple's
# rejection email is a slow way to learn it.
if codesign -dv "$APP" 2>&1 | grep -q 'Signature=adhoc'; then
  die "$APP is ad-hoc signed. Rebuild with a Developer ID identity first:
  scripts/build-app.sh \"Developer ID Application: Your Name (TEAMID)\""
fi

say "==> signature"
codesign -dv "$APP" 2>&1 | grep -E 'Authority|TeamIdentifier|Signature' | sed 's/^/    /'

say "==> hardened runtime check"
codesign -d --entitlements - "$APP" 2>/dev/null | sed 's/^/    /' || true
codesign -dv "$APP" 2>&1 | grep -q 'flags=.*runtime' \
  || die "the hardened runtime is not enabled; notarisation will be rejected"

say "==> zipping"
rm -f "$ZIP"
# ditto, not zip: the bundle's symlinks and extended attributes have to survive.
ditto -c -k --keepParent "$APP" "$ZIP"

say "==> submitting (this waits; a first submission often takes a few minutes)"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait

say "==> stapling"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

say "==> verifying as Gatekeeper sees it"
spctl --assess --type execute --verbose=2 "$APP"

say ""
say "Notarised and stapled: $APP"
say "Next: scripts/install.sh"
