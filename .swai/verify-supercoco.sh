#!/bin/bash
set -euo pipefail

REPO="$(git rev-parse --show-toplevel)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

AS=(
    lwasm
    --no-warn=ifp1
    --6309
    --format=os9
    --pragma=pcaspcr,nosymbolcase,condundefzero,undefextern,dollarnotlocal,noforwardrefmax
    --includedir="$REPO/defs"
    --includedir="$REPO/recipes/wildbits/l2"
    -Djr2
)

"${AS[@]}" \
    -o "$TMP/scnet" \
    "$REPO/level1/wildbits/modules/scnet.asm"

"${AS[@]}" \
    -o "$TMP/net0" \
    "$REPO/level1/wildbits/modules/net0.asm"

test -s "$TMP/scnet"
test -s "$TMP/net0"

echo "PASS: SuperCoCo NitrOS-9 scnet/net0 retained build"
