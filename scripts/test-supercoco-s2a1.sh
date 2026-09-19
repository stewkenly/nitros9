#!/usr/bin/env bash
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

expected='a434445d2b5182683ec2d164febc0a030b0d36cb'
actual="$(git rev-parse HEAD)"
[[ "$actual" == "$expected" ]] || {
    echo "FAIL: expected S2A-1 base $expected, found $actual" >&2
    exit 1
}

command -v lwasm >/dev/null 2>&1 || { echo 'FAIL: lwasm not found' >&2; exit 1; }

bash -n scripts/run-supercoco-s2a1.sh
grep -Fq '63SDC-S2A1.VHD' scripts/run-supercoco-s2a1.sh
grep -Fq "-type \$'DOS\\r'" scripts/run-supercoco-s2a1.sh || true

grep -Fq 'SC.VideoSurfMBOSlotO' defs/supercoco.d
grep -Fq 'SC.VideoSurfStrideO' defs/supercoco.d
grep -Fq 'scinfo scdemo wbreset' recipes/wildbits/wildbits.mak
grep -Fq 'os9       F$AllRAM' level1/wildbits/cmds/scdemo.asm
grep -Fq 'os9       F$MapBlk' level1/wildbits/cmds/scdemo.asm
grep -Fq 'os9       F$ClrBlk' level1/wildbits/cmds/scdemo.asm
grep -Fq 'os9       F$DelRAM' level1/wildbits/cmds/scdemo.asm
grep -Fq 'FB.Blocks           equ       19' level1/wildbits/cmds/scdemo.asm
grep -Fq 'FB.Pages            equ       38' level1/wildbits/cmds/scdemo.asm
! grep -Eq 'rmb[[:space:]]+153600|rmb[[:space:]]+\$25800' level1/wildbits/cmds/scdemo.asm

work="$(mktemp -d /tmp/supercoco-s2a1.XXXXXX)"
trap 'rm -rf "$work"' EXIT

lwasm \
  --no-warn=ifp1 \
  --6309 \
  --format=os9 \
  --pragma=pcaspcr,nosymbolcase,condundefzero,undefextern,dollarnotlocal,noforwardrefmax \
  --includedir="$ROOT/recipes/wildbits/l2" \
  --includedir="$ROOT/defs" \
  -o "$work/scdemo" \
  "$ROOT/level1/wildbits/cmds/scdemo.asm"

[[ -s "$work/scdemo" ]] || { echo 'FAIL: scdemo assembly produced no module' >&2; exit 1; }

if command -v os9 >/dev/null 2>&1; then
    os9 ident "$work/scdemo" | grep -Fqi 'scdemo' || {
        echo 'FAIL: assembled module identity is not scdemo' >&2
        exit 1
    }
fi

git diff --check

echo 'PASS: SuperCoCo NitrOS-9 S2A-1 first-pixels command builds'
