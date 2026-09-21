#!/usr/bin/env bash
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"
SOURCE="$ROOT/tools/test-supercoco-s2a6-native-network.sh"
EXPECTED_SOURCE_BLOB="fc0c0d9ec0e21ce1ecd82acbb2bdf3a32701685f"
CURRENT_HEAD="$(git rev-parse HEAD)"
[[ -f "$SOURCE" ]] || { echo "FAIL: missing published S2A6 regression" >&2; exit 1; }
[[ "$(git hash-object "$SOURCE")" == "$EXPECTED_SOURCE_BLOB" ]] || { echo "FAIL: published S2A6 regression blob changed" >&2; exit 1; }
WORK="$(mktemp -d /tmp/supercoco-s2a6-retained.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
PATCHED="$WORK/test-supercoco-s2a6-native-network.sh"
python3 - "$SOURCE" "$PATCHED" "$CURRENT_HEAD" <<'__PATCH_HEAD__'
from pathlib import Path
import sys
src,dst=map(Path,sys.argv[1:3]); head=sys.argv[3]; text=src.read_text()
old='EXPECTED_HEAD="fb312c65c93213ef614b2e220fd8b7fe367f8b74"'
if text.count(old)!=1: raise SystemExit('FAIL: S2A6 HEAD guard shape changed')
dst.write_text(text.replace(old,f'EXPECTED_HEAD="{head}"',1))
__PATCH_HEAD__
chmod +x "$PATCHED"
bash -n "$PATCHED"
"$PATCHED"
