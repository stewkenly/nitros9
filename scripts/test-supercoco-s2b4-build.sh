#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

REQUIRED_BASE="400c0247644bf1468ba1776d2fc1c9134b449dd0"
if ! git merge-base --is-ancestor "$REQUIRED_BASE" HEAD; then
    echo "FAIL: candidate is not descended from accepted S2B-3 base $REQUIRED_BASE" >&2
    exit 1
fi

for cmd in git make lwasm os9; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "FAIL: $cmd not found" >&2; exit 1; }
done

"$ROOT/scripts/test-supercoco-s2b3-build.sh"

grep -Fq 'SCG_BUILD_MIRROR_BLIT' level2/cmds/scgrf.inc
grep -Fq 'SC.GraphicsOpBlit' level2/cmds/scgrf.inc
grep -Fq 'SCG_RR_MIRROR_BLIT' level2/cmds/scgrf.inc
grep -Fq 'Full-screen overwrite remains the recovery primitive from S2B-3' level2/cmds/scgrf.inc

git diff --check

RECIPE="$ROOT/recipes/coco3_6309/40d"
make -C "$RECIPE" --no-print-directory .mods/cowin.io .mods/grfdrv

test -s "$RECIPE/.mods/cowin.io"
test -s "$RECIPE/.mods/grfdrv"
os9 ident "$RECIPE/.mods/grfdrv" | grep -Fqi 'GrfDrv' || {
    echo 'FAIL: rebuilt module identity is not GrfDrv' >&2
    exit 1
}

WORK="$(mktemp -d /tmp/supercoco-s2b4-build.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
PROBE="$WORK/scgrfblitprobe"
lwasm \
  --no-warn=ifp1 \
  --6309 \
  --format=os9 \
  --pragma=pcaspcr,nosymbolcase,condundefzero,undefextern,dollarnotlocal,noforwardrefmax \
  --includedir="$ROOT/recipes/wildbits/l2" \
  --includedir="$ROOT/defs" \
  -o "$PROBE" \
  "$ROOT/level1/wildbits/cmds/scgrfblitprobe.asm"

test -s "$PROBE"
os9 ident "$PROBE" | grep -Fqi 'scgrfblitprobe' || {
    echo 'FAIL: probe module identity is not scgrfblitprobe' >&2
    exit 1
}

printf 'PASS: SuperCoCo S2B-4 R1K BLIT mirror candidate builds\n'
printf 'NitrOS-9: %s\n' "$(git rev-parse HEAD)"
printf 'GrfDrv:   %s\n' "$RECIPE/.mods/grfdrv"
printf 'Probe:    %s\n' "$PROBE"
