#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"
REQUIRED_XROAR_BASE="d9661764ae4ecaeb54bf55fb404843efae74c1fa"
SUPERCOCO_EMULATOR_ROOT="${SUPERCOCO_EMULATOR_ROOT:-/Volumes/design/supercoco-emulator}"
BASE_VHD="${BASE_VHD:-$SUPERCOCO_EMULATOR_ROOT/images/63SDC-SUPERCOCO-S2B6-STRIP-V3.VHD}"

if [[ -n "${SUPERCOCO_XROAR_ROOT:-}" ]]; then
    XROAR_ROOT="$SUPERCOCO_XROAR_ROOT"
elif [[ -d /Volumes/design/supercoco-xroar/.git ]]; then
    XROAR_ROOT=/Volumes/design/supercoco-xroar
else
    echo 'FAIL: no SuperCoCo XRoar worktree found' >&2
    exit 1
fi

if ! git -C "$XROAR_ROOT" merge-base --is-ancestor "$REQUIRED_XROAR_BASE" HEAD; then
    echo "FAIL: XRoar is not descended from alpha full-speed native-video gate $REQUIRED_XROAR_BASE" >&2
    exit 1
fi
[[ -f "$BASE_VHD" ]] || { echo "FAIL: missing frozen V3 base VHD: $BASE_VHD" >&2; exit 1; }

"$ROOT/scripts/test-supercoco-s2b6-dirty-mirror-build.sh"
SUPERCOCO_XROAR_ROOT="$XROAR_ROOT" \
BASE_VHD="$BASE_VHD" \
S2B5_TIMEOUT="${S2B6_DIRTY_TIMEOUT:-180}" \
"$ROOT/scripts/test-supercoco-s2b5-runtime.sh"

printf 'PASS: SuperCoCo S2B6 style-9 buffered alpha mirrors only dirty rectangles after one present\n'
printf 'ROW_WORK_NORMAL=16\n'
printf 'ROW_WORK_WRAP=32\n'
printf 'NitrOS-9: %s\n' "$(git rev-parse HEAD)"
printf 'XRoar:    %s\n' "$(git -C "$XROAR_ROOT" rev-parse HEAD)"
