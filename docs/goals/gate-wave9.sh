#!/usr/bin/env bash
# Wave 9 completion gate.
#
# Ids are allocated by /triage at run time, so this cannot hard-code them. It
# maps each brief to whichever spec cites it, then requires that spec's id to be
# terminal in LEDGER.md — which is the file /triage owns and the only place a
# status is authoritative. A brief with no spec is untriaged; a spec whose id is
# not Merged or Retired is unfinished. Either way the wave is not done.
#
# Exit 0 only when all 11 items are terminal. Prints the outstanding set.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 2

BRIEFS=(59 60 61 62 63 64 65 66 67 68 69)
LEDGER=docs/feature-specs/LEDGER.md
outstanding=()

for n in "${BRIEFS[@]}"; do
  brief=$(ls docs/features-to-triage/${n}-*.md 2>/dev/null | head -1)
  [ -z "$brief" ] && { outstanding+=("$n: brief missing"); continue; }
  base=$(basename "$brief")

  spec=$(grep -rl -- "$base" docs/specs/ 2>/dev/null | head -1)
  [ -z "$spec" ] && { outstanding+=("$n: untriaged (no spec cites $base)"); continue; }

  id=$(basename "$spec" .md | sed 's/^spec-//')
  row=$(grep -E "^\| $id \|" "$LEDGER" 2>/dev/null | head -1)
  [ -z "$row" ] && { outstanding+=("$n: $id has no LEDGER row"); continue; }

  if ! printf '%s' "$row" | grep -qE '\| *(Merged|Retired)'; then
    state=$(printf '%s' "$row" | awk -F'|' '{gsub(/^ +| +$/,"",$5); print $5}')
    outstanding+=("$n: $id is ${state:-not terminal}")
  fi
done

if [ ${#outstanding[@]} -eq 0 ]; then
  echo "wave 9: all ${#BRIEFS[@]} items terminal"
  exit 0
fi

echo "wave 9: ${#outstanding[@]} of ${#BRIEFS[@]} outstanding"
printf '  %s\n' "${outstanding[@]}"
exit 1
