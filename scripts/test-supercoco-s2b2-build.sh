#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

REQUIRED_BASE="0216744e95d2196813a0187d345f560818156783"
if ! git merge-base --is-ancestor "$REQUIRED_BASE" HEAD; then
    echo "FAIL: candidate is not descended from accepted S2B-1 base $REQUIRED_BASE" >&2
    exit 1
fi

for cmd in git make lwasm os9; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "FAIL: $cmd not found" >&2; exit 1; }
done

# Retain the complete S2B-1 build gate first.
"$ROOT/scripts/test-supercoco-s2b1-build.sh"

# S2B-2 is deliberately additive: style 9 gains BColor/CLS interception,
# a dedicated command MBO, R1K Job V1 submission and VBLANK back-buffer flip.
grep -Fq 'SCG.FlagRAMCmd      EQU       $20' defs/cocovtio.d
grep -Fq 'SCG.FlagMBOCmd      EQU       $40' defs/cocovtio.d
grep -Fq 'cmpb      #SCGrfType' level2/cmds/grfdrv.asm
grep -Fq 'lbsr      SCG_CLS_ENTRY' level2/cmds/grfdrv.asm
grep -Fq 'lbsr      SCG_PROBE_GRAPHICS' level2/cmds/scgrf.inc
grep -Fq 'SCG_PROGRAM_CMD_MBO' level2/cmds/scgrf.inc
grep -Fq 'SCG_SUBMIT_FILL' level2/cmds/scgrf.inc
grep -Fq 'SCG_PRESENT_BACK' level2/cmds/scgrf.inc
grep -Fq 'SC.GraphicsOpFill' level2/cmds/scgrf.inc

git diff --check

RECIPE="$ROOT/recipes/coco3_6309/40d"
make -C "$RECIPE" --no-print-directory .mods/cowin.io .mods/grfdrv

test -s "$RECIPE/.mods/cowin.io"
test -s "$RECIPE/.mods/grfdrv"
os9 ident "$RECIPE/.mods/grfdrv" | grep -Fqi 'GrfDrv' || {
    echo 'FAIL: rebuilt module identity is not GrfDrv' >&2
    exit 1
}

WORK="$(mktemp -d /tmp/supercoco-s2b2-build.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
PROBE="$WORK/scgrffillprobe"
lwasm \
  --no-warn=ifp1 \
  --6309 \
  --format=os9 \
  --pragma=pcaspcr,nosymbolcase,condundefzero,undefextern,dollarnotlocal,noforwardrefmax \
  --includedir="$ROOT/recipes/wildbits/l2" \
  --includedir="$ROOT/defs" \
  -o "$PROBE" \
  "$ROOT/level1/wildbits/cmds/scgrffillprobe.asm"

test -s "$PROBE"
os9 ident "$PROBE" | grep -Fqi 'scgrffillprobe' || {
    echo 'FAIL: probe module identity is not scgrffillprobe' >&2
    exit 1
}

printf 'PASS: SuperCoCo S2B-2 R1K CLS fill candidate builds\n'
printf 'NitrOS-9: %s\n' "$(git rev-parse HEAD)"
printf 'GrfDrv:   %s\n' "$RECIPE/.mods/grfdrv"
printf 'Probe:    %s\n' "$PROBE"
