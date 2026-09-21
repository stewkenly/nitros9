#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

REQUIRED_BASE="dbaadc16a9aad81f6b226f0c9aca8f4ea974b606"
if ! git merge-base --is-ancestor "$REQUIRED_BASE" HEAD; then
    echo "FAIL: candidate is not descended from accepted S1 base $REQUIRED_BASE" >&2
    exit 1
fi

for cmd in git make lwasm os9; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "FAIL: $cmd not found" >&2; exit 1; }
done

# Structural invariants: legacy style mappings remain, style 9 is additive,
# and type 7 is intercepted before old MMU/GIME selection paths.
grep -Fq 'SCGrfStyle          EQU       $09' defs/cocovtio.d
grep -Fq 'SCGrfType           EQU       $07' defs/cocovtio.d
grep -Fq 'fcb       $04                 320 16 color, sty=$08' level2/coco3/modules/cowin.asm
grep -Fq 'fcb       SCGrfType           SuperCoCo 640x480 INDEX4, sty=$09' level2/coco3/modules/cowin.asm
grep -Fq 'beq       noneed              MBO-backed screen is not legacy MMU-mapped RAM' level2/cmds/grfdrv.asm
grep -Fq 'lbsr      SCG_DWSET' level2/cmds/grfdrv.asm
grep -Fq 'lbsr      L0129               go setup data & MMU for new window' level2/cmds/grfdrv.asm
grep -Fq 'lbeq      SCG_DWEND_ENTRY' level2/cmds/grfdrv.asm
grep -Fq 'lbeq      SCG_SELECT_WINDOW' level2/cmds/grfdrv.asm
grep -Fq 'use       scsys.inc' level2/cmds/grfdrv.asm
grep -Fq 'use       scgrf.inc' level2/cmds/grfdrv.asm

git diff --check

RECIPE="$ROOT/recipes/coco3_6309/40d"
make -C "$RECIPE" --no-print-directory clean >/dev/null
make -C "$RECIPE" --no-print-directory .mods/cowin.io .mods/grfdrv

test -s "$RECIPE/.mods/cowin.io"
test -s "$RECIPE/.mods/grfdrv"
os9 ident "$RECIPE/.mods/cowin.io" | grep -Fqi 'CoWin' || {
    echo 'FAIL: rebuilt module identity is not CoWin' >&2
    exit 1
}
os9 ident "$RECIPE/.mods/grfdrv" | grep -Fqi 'GrfDrv' || {
    echo 'FAIL: rebuilt module identity is not GrfDrv' >&2
    exit 1
}

WORK="$(mktemp -d /tmp/supercoco-s2b1-build.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
PROBE="$WORK/scgrfprobe"
lwasm \
  --no-warn=ifp1 \
  --6309 \
  --format=os9 \
  --pragma=pcaspcr,nosymbolcase,condundefzero,undefextern,dollarnotlocal,noforwardrefmax \
  --includedir="$ROOT/recipes/wildbits/l2" \
  --includedir="$ROOT/defs" \
  -o "$PROBE" \
  "$ROOT/level1/wildbits/cmds/scgrfprobe.asm"

test -s "$PROBE"
os9 ident "$PROBE" | grep -Fqi 'scgrfprobe' || {
    echo 'FAIL: probe module identity is not scgrfprobe' >&2
    exit 1
}

printf 'PASS: SuperCoCo S2B-1 CoWin/GrfDrv lifecycle candidate builds\n'
printf 'NitrOS-9: %s\n' "$(git rev-parse HEAD)"
printf 'CoWin:    %s\n' "$RECIPE/.mods/cowin.io"
printf 'GrfDrv:   %s\n' "$RECIPE/.mods/grfdrv"
printf 'Probe:    %s\n' "$PROBE"
