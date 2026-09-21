#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

SOURCE="$ROOT/tools/test-supercoco-s2a5-native-network.sh"
EXPECTED_SOURCE_BLOB="b94c1f57e59e6ab26ec7a3f6c7d6e7770c0b2c05"
CURRENT_HEAD="$(git rev-parse HEAD)"

[[ -f "$SOURCE" ]] || { echo "FAIL: missing published S2A5 regression: $SOURCE" >&2; exit 1; }
ACTUAL_SOURCE_BLOB="$(git hash-object "$SOURCE")"
[[ "$ACTUAL_SOURCE_BLOB" == "$EXPECTED_SOURCE_BLOB" ]] || {
    echo "FAIL: published S2A5 regression blob changed" >&2
    echo "expected: $EXPECTED_SOURCE_BLOB" >&2
    echo "actual:   $ACTUAL_SOURCE_BLOB" >&2
    exit 1
}

WORK="$(mktemp -d /tmp/supercoco-s2a5-retained.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
PATCHED="$WORK/test-supercoco-s2a5-native-network.sh"

python3 - "$SOURCE" "$PATCHED" "$CURRENT_HEAD" <<'PY_RETAINED'
from pathlib import Path
import sys
src, dst = map(Path, sys.argv[1:3])
head = sys.argv[3]
text = src.read_text()
old = 'EXPECTED_HEAD="2564d6caee6b1bb8fb34279523665505c485e4c8"'
if text.count(old) != 1:
    raise SystemExit('FAIL: published S2A5 HEAD guard shape changed')
text = text.replace(old, f'EXPECTED_HEAD="{head}"', 1)
dst.write_text(text)
PY_RETAINED

chmod +x "$PATCHED"
bash -n "$PATCHED"

echo "=== S2A5 RETAINED REGRESSION AT $CURRENT_HEAD ==="
"$PATCHED"
