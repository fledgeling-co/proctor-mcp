#!/usr/bin/env bash
# Every repo-side standing gate, each exit code read from the gate itself.
#
# PRO-0166's lesson, applied to the thing that would suffer most from it: a gate
# piped to `tail` reports tail's status. Each command here runs unpiped, its
# status is captured immediately, and its output goes to a file that is printed
# only on failure.
#
#   scripts/campaign/standing_gates.sh [--verbose]
#
# Exit codes
#   0  every gate passed
#   1  at least one failed, named with its exit code and its last lines

set -uo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 2
VERBOSE=0
[ "${1:-}" = "--verbose" ] && VERBOSE=1

OUT="$(mktemp)"
trap 'rm -f "$OUT"' EXIT
FAILED=()
PASSED=0

gate() {
  local name="$1"; shift
  "$@" > "$OUT" 2>&1
  local code=$?
  if [ $code -eq 0 ]; then
    PASSED=$((PASSED + 1))
    [ $VERBOSE -eq 1 ] && printf '  ok    %-26s\n' "$name"
  else
    FAILED+=("$name")
    printf '  FAIL  %-26s exit %s\n' "$name" "$code"
    tail -n 12 "$OUT" | sed 's/^/          /'
  fi
  return 0
}

P=python3
gate ledger            $P scripts/campaign/ledger_gate.py
gate spec-citations    $P scripts/campaign/spec_citation_measure.py
gate spec-symbols      $P scripts/campaign/spec_symbol_linter.py --gate
gate figure-ledger     $P scripts/campaign/figure_ledger.py check --gate
gate claim-provenance  $P scripts/campaign/claim_provenance.py --gate
gate path-citations    $P scripts/campaign/path_citation_check.py --gate
gate partitions        $P scripts/campaign/partition_report.py --gate
gate defect-status     $P scripts/campaign/defect_status_gate.py --gate
gate noop-attestation  $P scripts/campaign/noop_attestation.py --gate
gate socket-signals    $P scripts/campaign/socket_signal_census.py --gate
gate pipe-exits        $P scripts/campaign/pipe_exit_sweep.py --gate
gate wait-sites        $P scripts/campaign/wait_site_sweep.py --gate
gate capture-manifest  $P scripts/campaign/capture_manifest.py --gate
gate overlay-reader    $P scripts/campaign/skill_overlay_reader.py --gate
gate verification-recs $P scripts/campaign/verification_record.py check
gate registry-drift    $P scripts/campaign/defect_gate.py dropped docs/test-campaign
gate plane-census      $P scripts/campaign/plane_census.py docs/test-campaign --gate
gate control-census    $P scripts/campaign/control_census.py --gate
gate lane-census       $P scripts/campaign/lane_census.py --gate
gate journey-census    $P scripts/campaign/journey_census.py --gate

TOTAL=$((PASSED + ${#FAILED[@]}))
if [ ${#FAILED[@]} -gt 0 ]; then
  echo "standing gates: ${#FAILED[@]} of $TOTAL failed — ${FAILED[*]}"
  exit 1
fi
echo "standing gates: $TOTAL of $TOTAL passed"
