#!/usr/bin/env bash
# Arm Proctor's screen-unlock capability. Run with sudo — it installs a root
# authorization plugin and edits the login authorization database.
#
#   sudo Unlock/scripts/arm-unlock.sh
#
# What it does, in order, backup FIRST:
#   1. Refuses unless the plugin is notarised — an un-notarised SecurityAgent
#      plugin will not load, and a rule pointing at one that cannot load is the
#      worst outcome: a dead branch in the unlock path.
#   2. Backs up the current `system.login.screensaver` rule verbatim, so the
#      exact prior state can be restored. Nothing in macOS restores it for you.
#   3. Installs the plugin to /Library/Security/SecurityAgentPlugins.
#   4. Adds a named Proctor rule and inserts it into `system.login.screensaver`
#      ALONGSIDE whatever is already there (so an existing Codex branch keeps
#      working), always keeping `use-login-window-ui` as the final branch with
#      k-of-n=1. That last property is the guarantee you cannot be locked out:
#      if every plugin branch declines, the normal password prompt still
#      satisfies the right.
#
# Undo with disarm-unlock.sh, which restores the backup and removes the plugin.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PLUGIN_SRC="$REPO_ROOT/Unlock/.build/ProctorUnlock.bundle"
PLUGIN_DEST="/Library/Security/SecurityAgentPlugins/ProctorUnlock.bundle"
BACKUP_DIR="/Library/Application Support/app.fledgeling.procter/authdb-backup"
RIGHT="system.login.screensaver"
NAMED_RULE="app.fledgeling.procter.unlock.remote"
MECHANISM="ProctorUnlock:allow"

say() { printf '%s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" = "0" ] || die "run me with sudo — I install a root plugin and edit the authorization database."
[ -d "$PLUGIN_SRC" ] || die "no plugin at $PLUGIN_SRC — build it first: Unlock/scripts/build-plugin.sh <identity>"

say "==> checking the plugin is notarised (it will not load otherwise)"
spctl -a -vv -t install "$PLUGIN_SRC" 2>&1 | grep -q 'source=Notarized' \
  || die "$PLUGIN_SRC is not notarised. Run Unlock/scripts/notarize-plugin.sh first."

say "==> backing up the current $RIGHT rule (before any change)"
mkdir -p "$BACKUP_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$BACKUP_DIR/$RIGHT.$STAMP.plist"
security authorizationdb read "$RIGHT" > "$BACKUP"
# A stable 'latest' symlink is what disarm restores from.
ln -sf "$RIGHT.$STAMP.plist" "$BACKUP_DIR/$RIGHT.latest.plist"
say "    saved $BACKUP"

say "==> installing the plugin to $PLUGIN_DEST"
rm -rf "$PLUGIN_DEST"
ditto "$PLUGIN_SRC" "$PLUGIN_DEST"
chown -R root:wheel "$PLUGIN_DEST"

say "==> writing the named Proctor rule ($NAMED_RULE)"
cat <<PLIST | security authorizationdb write "$NAMED_RULE" >/dev/null
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>class</key><string>evaluate-mechanisms</string>
  <key>comment</key><string>Screen-unlock branch that asks the Proctor agent whether an authorized unlock turn is pending.</string>
  <key>mechanisms</key><array><string>$MECHANISM</string></array>
  <key>tries</key><integer>1</integer>
  <key>shared</key><true/>
  <key>version</key><integer>1</integer>
</dict>
</plist>
PLIST

say "==> inserting the Proctor branch into $RIGHT (additive, fallback preserved)"
security authorizationdb read "$RIGHT" | python3 -c '
import sys, plistlib
rule = plistlib.loads(sys.stdin.buffer.read())
proctor = sys.argv[1]
fallback = "use-login-window-ui"
arr = rule.get("rule", [])
if isinstance(arr, str):
    arr = [arr]
# The fallback must be the last resort, always present. This is the anti-lockout
# invariant: with k-of-n=1, a human satisfying use-login-window-ui always works.
if fallback not in arr:
    arr.append(fallback)
if proctor not in arr:
    arr.insert(arr.index(fallback), proctor)
rule["rule"] = arr
rule["k-of-n"] = 1
plistlib.dump(rule, sys.stdout.buffer)
' "$NAMED_RULE" | security authorizationdb write "$RIGHT" >/dev/null

say ""
say "==> result"
security authorizationdb read "$RIGHT" 2>/dev/null | python3 -c 'import sys,plistlib; r=plistlib.loads(sys.stdin.buffer.read()); print("    rule:   ", r.get("rule")); print("    k-of-n: ", r.get("k-of-n"))'

say ""
say "Armed. The Proctor branch is in the unlock path alongside any existing branch,"
say "and $fallback remains the final fallback so you cannot be locked out."
say "Undo any time:  sudo Unlock/scripts/disarm-unlock.sh"
