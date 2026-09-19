#!/usr/bin/env bash
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

expected='afc18e25c3b3691b0d2859a34a045eefddc2338f'
actual="$(git rev-parse HEAD)"
[[ "$actual" == "$expected" ]] || {
    echo "FAIL: expected S1A base $expected, found $actual" >&2
    exit 1
}

command -v lwasm >/dev/null 2>&1 || { echo 'FAIL: lwasm not found' >&2; exit 1; }

grep -Fq 'SuperCoCo Community Alpha NG service ABI definitions' defs/supercoco.d
grep -Fq 'SC.VideoBase' defs/supercoco.d
grep -Fq 'SC.GraphicsBase' defs/supercoco.d
grep -Fq 'SC.AudioBase' defs/supercoco.d
grep -Eq 'CMDS .*scinfo|scinfo' recipes/wildbits/wildbits.mak

work="$(mktemp -d /tmp/supercoco-s1a.XXXXXX)"
trap 'rm -rf "$work"' EXIT

lwasm \
  --no-warn=ifp1 \
  --6309 \
  --format=os9 \
  --pragma=pcaspcr,nosymbolcase,condundefzero,undefextern,dollarnotlocal,noforwardrefmax \
  --includedir="$ROOT/recipes/wildbits/l2" \
  --includedir="$ROOT/defs" \
  -o "$work/scinfo" \
  "$ROOT/level1/wildbits/cmds/scinfo.asm"

[[ -s "$work/scinfo" ]] || { echo 'FAIL: scinfo assembly produced no module' >&2; exit 1; }

if command -v os9 >/dev/null 2>&1; then
    os9 ident "$work/scinfo" | grep -Fqi 'scinfo' || {
        echo 'FAIL: assembled module identity is not scinfo' >&2
        exit 1
    }
fi

git diff --check

echo 'PASS: SuperCoCo NitrOS-9 S1A common discovery surface'
