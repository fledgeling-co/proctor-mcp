#!/bin/bash
# Watch the window server while a synthetic batch holds the machine.
#
# The Run HUD and the takeover tint set sharingType = .none, so no capture
# channel can photograph them. That leaves two things that CAN be measured on
# glass, and this script measures both at once:
#
#   1. the overlay windows are drawn — the window server's own list reports
#      them onscreen with their alpha and bounds, while the batch runs;
#   2. they do not enter a capture — a window-scoped frame of the app under
#      test, taken mid-batch, shows the app and nothing of the overlay.
#
# The batch is hover steps only: synthetic mouse moves, which raise the
# overlays and mutate nothing in the target document.
set -u
OUT=/tmp/campaign-run
WIN="${1:-win:3:0}"
cd /Users/lukerhodes/Dev/proctor-mcp

cat > "$OUT/synthetic-batch.json" <<JSON
[
  {"tool": "proctor_act", "args": {"window": "$WIN", "foreground": true, "diffEach": false,
    "steps": [
      {"kind": "hover", "point": [120, 120], "label": "hover 1", "settle": {"timeoutMs": 1200}},
      {"kind": "hover", "point": [200, 160], "label": "hover 2", "settle": {"timeoutMs": 1200}},
      {"kind": "hover", "point": [280, 200], "label": "hover 3", "settle": {"timeoutMs": 1200}},
      {"kind": "hover", "point": [360, 240], "label": "hover 4", "settle": {"timeoutMs": 1200}},
      {"kind": "hover", "point": [440, 280], "label": "hover 5", "settle": {"timeoutMs": 1200}},
      {"kind": "hover", "point": [500, 320], "label": "hover 6", "settle": {"timeoutMs": 1200}}
    ]},
   "as": "act-synthetic-batch.json"}
]
JSON

# The batch runs detached so the window server can be read while it is up.
python3 scripts/campaign/mcp_drive.py "$OUT" "$OUT/synthetic-batch.json" \
    --profile full --transcript synthetic-transcript.json > "$OUT/synthetic-batch.log" 2>&1 &
BATCH=$!

rm -f "$OUT/overlay-poll.jsonl"
for i in $(seq 1 14); do
  "$OUT/glass_probe" Proctor >> "$OUT/overlay-poll.jsonl" 2>/dev/null
  echo "" >> "$OUT/overlay-poll.jsonl"
  perl -e 'select undef,undef,undef,0.5'
done

wait $BATCH
echo "batch exit=$?"
tail -4 "$OUT/synthetic-batch.log"
