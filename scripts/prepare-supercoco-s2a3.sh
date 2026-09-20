#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

SUPERCOCO_EMULATOR_ROOT="${SUPERCOCO_EMULATOR_ROOT:-/Volumes/design/supercoco-emulator}"
BASE_VHD="${BASE_VHD:-$SUPERCOCO_EMULATOR_ROOT/images/63SDC.VHD}"
OUTPUT_VHD="${OUTPUT_VHD:-$(dirname "$SUPERCOCO_EMULATOR_ROOT")/_transfer/63SDC-S2A3.VHD}"

for cmd in lwasm os9; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: $cmd not found" >&2; exit 1; }
done
[[ -f "$BASE_VHD" ]] || { echo "ERROR: missing base VHD: $BASE_VHD" >&2; exit 1; }

WORK="$(mktemp -d /tmp/supercoco-s2a3-prep.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
MODULE="$WORK/scgfxanim"

lwasm \
  --no-warn=ifp1 \
  --6309 \
  --format=os9 \
  --pragma=pcaspcr,nosymbolcase,condundefzero,undefextern,dollarnotlocal,noforwardrefmax \
  --includedir="$ROOT/recipes/wildbits/l2" \
  --includedir="$ROOT/defs" \
  -o "$MODULE" \
  "$ROOT/level1/wildbits/cmds/scgfxanim.asm"

mkdir -p "$(dirname "$OUTPUT_VHD")"
cp "$BASE_VHD" "$OUTPUT_VHD"
CMD_DIR='CMDS'
os9 dir "$OUTPUT_VHD,$CMD_DIR" >/dev/null 2>&1 || CMD_DIR='cmds'
os9 dir "$OUTPUT_VHD,$CMD_DIR" >/dev/null 2>&1 || { echo 'ERROR: no CMDS directory in base VHD' >&2; exit 1; }
os9 copy "$MODULE" "$OUTPUT_VHD,$CMD_DIR/scgfxanim"
os9 attr "$OUTPUT_VHD,$CMD_DIR/scgfxanim" -e -pe -r -pr

echo "Prepared S2A-3 image: $OUTPUT_VHD"
echo "Boot it with SuperCoCo XRoar and run: scgfxanim"
