#!/usr/bin/env bash
# Disarm Proctor's screen-unlock capability. Run with sudo.
#
#   sudo Unlock/scripts/disarm-unlock.sh
#
# Restores `system.login.screensaver` from the backup arm-unlock.sh took, removes
# the named Proctor rule, and removes the plugin. This is the reversal the
# equivalent OpenAI component never shipped — removing that app left a dangling
# mechanism in the unlock path. If no backup exists, it still surgically removes
# only the Proctor branch rather than guessing at the original.

set -euo pipefail

BACKUP_DIR="/Library/Application Support/app.fledgeling.procter/authdb-backup"
PLUGIN_DEST="/Library/Security/SecurityAgentPlugins/ProctorUnlock.bundle"
RIGHT="system.login.screensaver"
NAMED_RULE="app.fledgeling.procter.unlock.remote"

say() { printf '%s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" = "0" ] || die "run me with sudo."

LATEST="$BACKUP_DIR/$RIGHT.latest.plist"
if [ -f "$LATEST" ]; then
  say "==> restoring $RIGHT from backup"
  security authorizationdb write "$RIGHT" < "$LATEST" >/dev/null
else
  say "==> no backup found; removing only the Proctor branch from $RIGHT"
  security authorizationdb read "$RIGHT" | python3 -c '
import sys, plistlib
rule = plistlib.loads(sys.stdin.buffer.read())
proctor = sys.argv[1]
arr = rule.get("rule", [])
if isinstance(arr, str): arr = [arr]
rule["rule"] = [r for r in arr if r != proctor]
plistlib.dump(rule, sys.stdout.buffer)
' "$NAMED_RULE" | security authorizationdb write "$RIGHT" >/dev/null
fi

say "==> removing the named Proctor rule"
security authorizationdb remove "$NAMED_RULE" >/dev/null 2>&1 || true

say "==> removing the plugin"
rm -rf "$PLUGIN_DEST"

say ""
say "==> result"
security authorizationdb read "$RIGHT" 2>/dev/null | python3 -c 'import sys,plistlib; r=plistlib.loads(sys.stdin.buffer.read()); print("    rule:   ", r.get("rule"))'
say ""
say "Disarmed. Proctor is no longer in the unlock path."
