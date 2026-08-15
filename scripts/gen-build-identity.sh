#!/bin/sh
# Write the build identity that ProctorCore compiles in.
#
# Run as a SwiftPM prebuild command (Plugins/BuildIdentity), which means it runs
# before EVERY build — plain `swift build`, `swift test`, `swift build -c release`
# from scripts/build-app.sh, and the same call inside .github/workflows/release.yml.
# That is the point: those three paths have exactly one step in common, and this
# hangs off it, so none of them has to be taught anything.
#
# TWO RULES THIS FILE EXISTS TO KEEP.
#
#   IT NEVER FAILS. Every input has a sentinel, and a non-zero exit here is a
#   broken build for anyone who clones without git, packages a tarball, or runs
#   under a sandbox that denies something. An identity that says "unknown" is
#   worth having; a build that will not compile is not.
#
#   IT WRITES ONLY WHEN THE CONTENT CHANGES. A prebuild command runs every time,
#   with no up-to-date check. If it rewrote the file each run, every build would
#   recompile Core and everything downstream — measured at ~20s against 0.64s for
#   a no-change build. The cmp at the bottom is what makes freshness free.
#
# Usage: gen-build-identity.sh <output-dir> <package-dir>

# `set -u` but deliberately NOT `set -e`. Under `-e` any unexpected non-zero — a
# tool that is not there, a sandbox that denies something — aborts the script
# before it writes, and then Core compiles with no generated source at all and the
# build fails on an undefined symbol. That is the opposite of the rule above. So
# every step here is written to fall through to a sentinel, and the write at the
# bottom always happens.
set -u

OUT_DIR="$1"
PKG_DIR="$2"
PLIST="$PKG_DIR/Apps/Proctor/Info.plist"

mkdir -p "$OUT_DIR" 2>/dev/null || true

# Keep only characters that are safe inside a Swift string literal, so nothing read
# from a file or a tool can close the quote or escape into code. Everything this
# script emits goes through here.
safe() { printf '%s' "$1" | tr -cd 'A-Za-z0-9._+-'; }

# --- version: the release line, from the one file the release workflow trusts ---
#
# Apps/Proctor/Info.plist is already what release.yml reads for the asset name and
# for the CHANGELOG section match, so reading it here means the running binary and
# the release it came from cannot disagree — not because two places are kept in
# step, but because there is one place.
#
# PlistBuddy is the correct reader and is the normal path. The shell fallback is
# for the case where it is missing or the sandbox denies it: a build must not fail
# over the way a version is read.
#
# The `-f` gate is not belt and braces. Given a path that does not exist PlistBuddy
# prints "File Doesn't Exist, Will Create: /..." on STDOUT and exits 0, so without
# it that sentence becomes the version string.
VERSION=""
if [ -f "$PLIST" ]; then
  if [ -x /usr/libexec/PlistBuddy ]; then
    VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST" 2>/dev/null || true)"
  fi
  if [ -z "$VERSION" ]; then
    # The <string> element on the line after the CFBundleShortVersionString key.
    VERSION="$(sed -n '/<key>CFBundleShortVersionString<\/key>/{n;s/.*<string>\(.*\)<\/string>.*/\1/p;}' "$PLIST" 2>/dev/null || true)"
  fi
fi
VERSION="$(safe "$VERSION")"
[ -n "$VERSION" ] || VERSION="unknown"

# --- commit and dirty: which code, exactly ---
#
# Two sentinels rather than one, because they call for different responses:
#   unknown      this is not a git checkout — a tarball, an unpacked release.
#                Expected, nothing to do about it.
#   unavailable  git is here and could not answer — a broken checkout, an empty
#                repository, a denied read. Someone should look, and a single
#                "unknown" would have sent them hunting for a tarball that does
#                not exist.
#
# -e rather than -d on .git: inside a git worktree it is a pointer FILE to objects
# outside this directory, and a worktree is where this repo's work is done.
#
# --no-optional-locks so git cannot decide to refresh an index inside a sandbox
# that forbids the write.
COMMIT="unknown"
DIRTY=false
if [ -e "$PKG_DIR/.git" ] && command -v git >/dev/null 2>&1; then
  COMMIT="unavailable"
  if RESOLVED="$(git --no-optional-locks -C "$PKG_DIR" rev-parse --short=12 HEAD 2>/dev/null)" \
     && [ -n "$RESOLVED" ]; then
    COMMIT="$RESOLVED"
    # --porcelain rather than `diff`: an untracked source file changes the build
    # and belongs in the answer. It already excludes ignored paths, so .build and
    # .worktrees do not make every tree read as dirty.
    if [ -n "$(git --no-optional-locks -C "$PKG_DIR" status --porcelain 2>/dev/null)" ]; then
      DIRTY=true
    fi
  fi
fi
COMMIT="$(safe "$COMMIT")"
[ -n "$COMMIT" ] || COMMIT="unavailable"

OUT="$OUT_DIR/BuildIdentityGenerated.swift"
# Process-unique, and NOT ending in .swift: everything in this directory is handed
# to the compiler as a source file, so a leftover temporary that happened to end in
# .swift would be a second declaration of the same enum. The pid keeps two builds
# sharing one output directory from interleaving into one half-written file.
NEW="$OUT_DIR/.BuildIdentityGenerated.$$.tmp"

cat > "$NEW" <<SWIFT
// Generated by scripts/gen-build-identity.sh before every build. Do not edit, and
// do not commit: this file lives in the plugin's work directory, so a fresh clone
// generates its own rather than inheriting somebody else's.
enum BuildIdentityGenerated {
    static let version = "$VERSION"
    static let commit = "$COMMIT"
    static let dirty = $DIRTY
}
SWIFT

if cmp -s "$NEW" "$OUT" 2>/dev/null; then
  rm -f "$NEW"
else
  mv "$NEW" "$OUT"
fi
rm -f "$NEW" 2>/dev/null || true
exit 0
