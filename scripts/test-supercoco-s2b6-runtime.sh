#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"
REQUIRED_NITROS_BASE="21745dea6911daed1220c88a17199e81fb129e20"
REQUIRED_XROAR_BASE="f011126cdf4012902885b133ea23fc539223773d"

if ! git merge-base --is-ancestor "$REQUIRED_NITROS_BASE" HEAD; then
    echo "FAIL: candidate is not descended from accepted S2B-5 base $REQUIRED_NITROS_BASE" >&2
    exit 1
fi

if [[ -n "${SUPERCOCO_XROAR_ROOT:-}" ]]; then
    XROAR_ROOT="$SUPERCOCO_XROAR_ROOT"
elif [[ -d /Volumes/design/supercoco-xroar/.git ]]; then
    XROAR_ROOT=/Volumes/design/supercoco-xroar
elif [[ -d /Volumes/design/supercoco-emulator/upstream/.git ]]; then
    XROAR_ROOT=/Volumes/design/supercoco-emulator/upstream
else
    echo "FAIL: no SuperCoCo XRoar worktree found" >&2
    exit 1
fi

[[ -d "$XROAR_ROOT/.git" ]] || { echo "FAIL: missing XRoar repository: $XROAR_ROOT" >&2; exit 1; }
if ! git -C "$XROAR_ROOT" merge-base --is-ancestor "$REQUIRED_XROAR_BASE" HEAD; then
    echo "FAIL: XRoar is not descended from S2B6 native-video ownership publication $REQUIRED_XROAR_BASE" >&2
    exit 1
fi

"$ROOT/scripts/test-supercoco-s2b6-build.sh"
SUPERCOCO_XROAR_ROOT="$XROAR_ROOT" "$ROOT/scripts/test-supercoco-s2b5-runtime.sh"

printf 'PASS: SuperCoCo S2B-6 style-9 glyph scratch + 8x8 alpha replay runtime closure\n'
printf 'NitrOS-9: %s\n' "$(git rev-parse HEAD)"
printf 'XRoar:    %s\n' "$(git -C "$XROAR_ROOT" rev-parse HEAD)"
