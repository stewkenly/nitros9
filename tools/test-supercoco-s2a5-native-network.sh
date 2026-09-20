#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

EXPECTED_HEAD="2564d6caee6b1bb8fb34279523665505c485e4c8"
ACTUAL_HEAD="$(git rev-parse HEAD)"
[[ "$ACTUAL_HEAD" == "$EXPECTED_HEAD" ]] || {
    echo "FAIL: expected S2A5 FIX14 base $EXPECTED_HEAD, found $ACTUAL_HEAD" >&2
    exit 1
}

# The current production native-network sources are intentionally byte-identical
# to the canonical N3B-5 implementation.  Prove that before delegating to the
# mature full-session traffic/remote-close harness.
expect_blob() {
    local rel="$1" expected="$2" actual
    actual="$(git hash-object "$rel")"
    [[ "$actual" == "$expected" ]] || {
        echo "FAIL: source blob mismatch for $rel" >&2
        echo "expected: $expected" >&2
        echo "actual:   $actual" >&2
        exit 1
    }
}

expect_blob level1/wildbits/modules/net0.asm 77b5680a1fc34872422ab99e50104cdd560da725
expect_blob level1/wildbits/modules/scnet.asm a230a5cff112b4974c5e6afebef1882086da0907

echo 'PASS: current net0/scnet sources match the canonical N3B-5 implementation'

SUPERCOCO_EMULATOR_ROOT="${SUPERCOCO_EMULATOR_ROOT:-/Volumes/design/supercoco-emulator}"
BUILD_SCRIPT="$SUPERCOCO_EMULATOR_ROOT/nitros9/build-native-net.sh"
HARNESS_SCRIPT="$SUPERCOCO_EMULATOR_ROOT/tools/test-supercoco-native-net-nitros9-n3b5.sh"
N3B5_SOURCE="$SUPERCOCO_EMULATOR_ROOT/nitros9/n3b5.asm"
SCNGON_SOURCE="$SUPERCOCO_EMULATOR_ROOT/nitros9/scngon.asm"

for path in "$BUILD_SCRIPT" "$HARNESS_SCRIPT" "$N3B5_SOURCE" "$SCNGON_SOURCE"; do
    [[ -f "$path" ]] || { echo "FAIL: missing architecture regression dependency: $path" >&2; exit 1; }
done

# Pin the exact architecture-harness files.  This lets the emulator remain the
# executable architecture source of truth while ensuring this NitrOS-9 witness
# cannot silently drift onto a different test implementation.
expect_external_blob() {
    local path="$1" expected="$2" actual
    actual="$(git -C "$SUPERCOCO_EMULATOR_ROOT" hash-object "$path")"
    [[ "$actual" == "$expected" ]] || {
        echo "FAIL: architecture harness blob mismatch for $path" >&2
        echo "expected: $expected" >&2
        echo "actual:   $actual" >&2
        exit 1
    }
}

expect_external_blob nitros9/build-native-net.sh 503a65166829e0d5ac7893ef81e57dd6c974eb71
expect_external_blob tools/test-supercoco-native-net-nitros9-n3b5.sh a93bfe68377bd39e000519e28c4a28ed7eb27e71
expect_external_blob nitros9/n3b5.asm fb783832ee2a23d422c6f2309617af773c7f13e5
expect_external_blob nitros9/scngon.asm 3799665d66ae3d6f90d93801521608555559c2f5

echo 'PASS: architecture N3B-5 harness dependencies are pinned'

WORK="$(mktemp -d /tmp/supercoco-s2a5-fix14.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
PATCHED_BUILD="$WORK/build-native-net-current.sh"
PATCHED_HARNESS="$WORK/test-n3b5-current.sh"

# The canonical emulator scripts deliberately pin the historical NitrOS-9
# commit that originally proved N3B-5.  FIX14 has already proven that today's
# net0/scnet source blobs are identical, so make temporary copies that accept
# today's published NitrOS-9 HEAD without modifying the architecture repo.
python3 - "$BUILD_SCRIPT" "$PATCHED_BUILD" "$SUPERCOCO_EMULATOR_ROOT" "$EXPECTED_HEAD" <<'PYBUILD'
from pathlib import Path
import sys

src, dst = map(Path, sys.argv[1:3])
emulator_root = Path(sys.argv[3])
head = sys.argv[4]
text = src.read_text()
old_script_dir = 'SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"'
old_commit = 'EXPECTED_NITROS9_COMMIT="17e504f2f398fa41cea423c07b6678f60be8f49f"'
if old_script_dir not in text or old_commit not in text:
    raise SystemExit('FAIL: canonical build-native-net.sh shape changed')
text = text.replace(old_script_dir, f'SCRIPT_DIR="{emulator_root / "nitros9"}"', 1)
text = text.replace(old_commit, f'EXPECTED_NITROS9_COMMIT="{head}"', 1)
dst.write_text(text)
PYBUILD

python3 - "$HARNESS_SCRIPT" "$PATCHED_HARNESS" "$SUPERCOCO_EMULATOR_ROOT" "$PATCHED_BUILD" <<'PYHARNESS'
from pathlib import Path
import sys

src, dst = map(Path, sys.argv[1:3])
emulator_root = Path(sys.argv[3])
patched_build = Path(sys.argv[4])
text = src.read_text()
old_script_dir = 'SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"'
old_builder = 'MODULE_BUILD="$ROOT/nitros9/build-native-net.sh"'
if old_script_dir not in text or old_builder not in text:
    raise SystemExit('FAIL: canonical N3B-5 harness shape changed')
text = text.replace(old_script_dir, f'SCRIPT_DIR="{emulator_root / "tools"}"', 1)
text = text.replace(old_builder, f'MODULE_BUILD="{patched_build}"', 1)
dst.write_text(text)
PYHARNESS

chmod +x "$PATCHED_BUILD" "$PATCHED_HARNESS"
bash -n "$PATCHED_BUILD"
bash -n "$PATCHED_HARNESS"

echo '=== S2A5 FIX14 FULL NATIVE-NETWORK SESSION ==='
echo "NitrOS-9 HEAD: $EXPECTED_HEAD"
echo 'Harness: canonical N3B-5 exact TX/RX + blocked-read IRQ + orderly remote close + Shell+ return'

NITROS9_ROOT="$ROOT" "$PATCHED_HARNESS"

echo
echo 'PASS: S2A5 full native-network regression via canonical N3B-5 harness'
