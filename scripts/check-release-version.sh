#!/usr/bin/env bash
# Check that a release's three names agree before anything is built.
#
#   the git tag             v0.1.1
#   the plist version       Apps/Proctor/Info.plist CFBundleShortVersionString
#   the CHANGELOG section   ## [0.1.1] - ...   with something written under it
#
# Why this exists at all: the plist version is now compiled into the running
# binaries, so a tag that disagrees with it ships an app that misreports which
# release it is. It runs before the build because failing in seconds beats failing
# after a notarisation round trip.
#
# Two things it gets right that the obvious spelling gets wrong, both measured:
#
#   THE `v`. Tags are `v0.1.0` and the plist holds `0.1.0`. A check comparing them
#   directly can never pass, so it would fail every release.
#
#   AN EMPTY SECTION IS NOT AN ABSENT ONE. A `## [0.1.1]` heading followed straight
#   away by the next heading extracts to a one-byte file containing a newline, and
#   `test -s` calls that non-empty — so a release whose notes are blank sails past a
#   check written that way and ships with no notes at all.
#
# Usage: check-release-version.sh <tag>          e.g. check-release-version.sh v0.1.1

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Overridable so the rules can be exercised against fixtures — a right tag, a
# missing `v`, an absent section and a blank one — without editing the real files.
PLIST="${PROCTOR_PLIST:-$REPO_ROOT/Apps/Proctor/Info.plist}"
CHANGELOG="${PROCTOR_CHANGELOG:-$REPO_ROOT/CHANGELOG.md}"

TAG="${1:-}"
[ -n "$TAG" ] || { printf 'error: no tag given\n  usage: %s <tag>\n' "$0" >&2; exit 2; }

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"

fail() { printf 'error: %s\n' "$*" >&2; exit 1; }

if [ "$TAG" != "v$VERSION" ]; then
  fail "the tag and the app disagree about this release.
  tag:              $TAG
  Info.plist:       $VERSION  (so the tag should be v$VERSION)
  Bump CFBundleShortVersionString in Apps/Proctor/Info.plist, or retag."
fi

# The same extraction release.yml uses for the notes, so this checks the thing that
# actually ships rather than something that resembles it.
#
# An exact prefix compare rather than a regex match: in a regex the dots in `1.2.3`
# match any character, so a heading like `## [1x2y3]` would win the slice for a
# release named 1.2.3. Comparing the literal `## [1.2.3]` cannot do that.
SECTION="$(awk -v target="## [$VERSION]" '
  substr($0, 1, length(target)) == target {grab=1; next}
  grab && /^## \[/ {exit}
  grab {print}
' "$CHANGELOG")"

# `case`, not `printf ... | grep -q`. Under `pipefail` a `grep -q` that exits at its
# first match can SIGPIPE the writer, and the pipeline then reports 141 for a section
# that is perfectly fine — the same trap scripts/notarize.sh already documents about
# piping codesign into grep. There is no pipe here to get it wrong.
case "$SECTION" in
  *[![:space:]]*) : ;;
  *) fail "CHANGELOG.md has no release notes for $VERSION.
  Expected a '## [$VERSION] - YYYY-MM-DD' heading with entries under it.
  On release, rename '## [Unreleased]' to that and open a fresh '## [Unreleased]'." ;;
esac

printf 'release names agree: tag %s · Info.plist %s · CHANGELOG section present\n' "$TAG" "$VERSION"
