#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

REQUIRED_BASE="a35e56a4dcfaeb808a508cb3f7c2d7ac242f91ad"
if ! git merge-base --is-ancestor "$REQUIRED_BASE" HEAD; then
    echo "FAIL: candidate is not descended from accepted S2B-2 base $REQUIRED_BASE" >&2
    exit 1
fi

for cmd in git make lwasm os9; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "FAIL: $cmd not found" >&2; exit 1; }
done

# Retain the complete S2B-2 build gate first.
"$ROOT/scripts/test-supercoco-s2b2-build.sh"

grep -Fq 'SCG.FlagMirrorDirty EQU       $80' defs/cocovtio.d
grep -Fq 'lbsr      SCG_BAR_ENTRY' level2/cmds/grfdrv.asm
grep -Fq 'L0707Legacy' level2/cmds/grfdrv.asm
grep -Fq 'SCG_BAR_ENTRY' level2/cmds/scgrf.inc
grep -Fq 'SCG_RENDER_RECT' level2/cmds/scgrf.inc
grep -Fq 'SC.GfxCmdDstXO' level2/cmds/scgrf.inc
grep -Fq 'SC.GfxCmdDstYO' level2/cmds/scgrf.inc

git diff --check

RECIPE="$ROOT/recipes/coco3_6309/40d"
make -C "$RECIPE" --no-print-directory .mods/cowin.io .mods/grfdrv

test -s "$RECIPE/.mods/cowin.io"
test -s "$RECIPE/.mods/grfdrv"
os9 ident "$RECIPE/.mods/grfdrv" | grep -Fqi 'GrfDrv' || {
    echo 'FAIL: rebuilt module identity is not GrfDrv' >&2
    exit 1
}

WORK="$(mktemp -d /tmp/supercoco-s2b3-build.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
PROBE="$WORK/scgrfbarprobe"
lwasm \
  --no-warn=ifp1 \
  --6309 \
  --format=os9 \
  --pragma=pcaspcr,nosymbolcase,condundefzero,undefextern,dollarnotlocal,noforwardrefmax \
  --includedir="$ROOT/recipes/wildbits/l2" \
  --includedir="$ROOT/defs" \
  -o "$PROBE" \
  "$ROOT/level1/wildbits/cmds/scgrfbarprobe.asm"

test -s "$PROBE"
os9 ident "$PROBE" | grep -Fqi 'scgrfbarprobe' || {
    echo 'FAIL: probe module identity is not scgrfbarprobe' >&2
    exit 1
}

printf 'PASS: SuperCoCo S2B-3 R1K BAR fill candidate builds\n'
printf 'NitrOS-9: %s\n' "$(git rev-parse HEAD)"
printf 'GrfDrv:   %s\n' "$RECIPE/.mods/grfdrv"
printf 'Probe:    %s\n' "$PROBE"
