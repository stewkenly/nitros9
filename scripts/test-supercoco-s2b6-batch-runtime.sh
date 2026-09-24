#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"
REQUIRED_NITROS_BASE="1e99541240dc98baf8a814f8e6520876a4cbba3a"
REQUIRED_XROAR_BASE="f011126cdf4012902885b133ea23fc539223773d"

if ! git merge-base --is-ancestor "$REQUIRED_NITROS_BASE" HEAD; then
    echo "FAIL: candidate is not descended from published S2B6 alpha base $REQUIRED_NITROS_BASE" >&2
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
    echo "FAIL: XRoar is not descended from native-video ownership publication $REQUIRED_XROAR_BASE" >&2
    exit 1
fi

"$ROOT/scripts/test-supercoco-s2b6-batch-build.sh"
SUPERCOCO_XROAR_ROOT="$XROAR_ROOT" "$ROOT/scripts/test-supercoco-s2b6-runtime.sh"

printf 'PASS: SuperCoCo S2B-6 buffered alpha uses one deferred present plus one final mirror per I$Write\n'
printf 'NitrOS-9: %s\n' "$(git rev-parse HEAD)"
printf 'XRoar:    %s\n' "$(git -C "$XROAR_ROOT" rev-parse HEAD)"
