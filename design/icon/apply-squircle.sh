#!/usr/bin/env bash
# Mask a full-bleed 1024x1024 raster into the macOS squircle (transparent
# corners), producing app-icon-shaped source art. This is how the shipped
# Proctor icon master is derived from the chosen raster take.
#
#   apply-squircle.sh proctor-raster-7c3d62-2.png icon-proctor-1024.png
#
# Needs rsvg-convert (librsvg) and squircle-path.txt beside this script.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${1:?usage: apply-squircle.sh <src-1024.png> <out.png>}"
OUT="${2:?usage: apply-squircle.sh <src-1024.png> <out.png>}"
SQ="$(cat "$DIR/squircle-path.txt")"
B64="$(base64 -i "$SRC")"
TMP="$(mktemp -t squircle-XXXX).svg"
cat > "$TMP" <<EOF
<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="1024" height="1024" viewBox="0 0 1024 1024">
<defs><clipPath id="sq"><path d="$SQ"/></clipPath></defs>
<image xlink:href="data:image/png;base64,$B64" width="1024" height="1024" clip-path="url(#sq)"/>
</svg>
EOF
rsvg-convert -w 1024 -h 1024 "$TMP" -o "$OUT"
rm -f "$TMP"
echo "wrote $OUT"
