#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"
REQUIRED_BASE="21745dea6911daed1220c88a17199e81fb129e20"

if ! git merge-base --is-ancestor "$REQUIRED_BASE" HEAD; then
    echo "FAIL: candidate is not descended from accepted S2B-5 base $REQUIRED_BASE" >&2
    exit 1
fi

"$ROOT/scripts/test-supercoco-s2b5-build.sh"
git diff --check

python3 - <<'PY2'
from pathlib import Path


def need(path, text):
    data = Path(path).read_text()
    if text not in data:
        raise SystemExit(f"FAIL: {path}: missing S2B-6 guard: {text}")


def forbid(path, text):
    data = Path(path).read_text()
    if text in data:
        raise SystemExit(f"FAIL: {path}: superseded S2B-5 alpha path remains: {text}")

need('defs/cocovtio.d', 'grSCMaskKey         EQU       grSCColor')
need('defs/cocovtio.d', 'grSCMapSave         EQU       grRsrved+$2D')
need('defs/cocovtio.d', 'grSCGlyphRows       EQU       grRsrved+$2F')
forbid('defs/cocovtio.d', 'grSCGlyphRows       EQU       grRsrved+$2E')

src = Path('level2/cmds/scgrf.inc').read_text()
start = src.index('SCG_RENDER_GLYPH')
end = src.index('SCG_ALPHA_ADVANCE', start)
render = src[start:end]
for token in (
    'SCG_BUILD_MASKED_GLYPH',
    'SCG_SUBMIT_FILL     MASKED_BLIT record 0 into hidden back',
    'SCG_PRESENT_BACK',
    'SCG_RETARGET_MASKED_BACK',
    'SCG_SUBMIT_FILL     replay same 8x8 MASKED_BLIT into new hidden back',
):
    if token not in render:
        raise SystemExit(f'FAIL: alpha render transaction missing {token}')
for token in ('SCG_BUILD_MIRROR_BLIT_R1', 'SCG_SUBMIT_RECORD1'):
    if token in render:
        raise SystemExit(f'FAIL: alpha render still uses full-frame record-1 mirror: {token}')

need('level2/cmds/scgrf.inc', 'SCG_RETARGET_MASKED_BACK')
need('level1/wildbits/cmds/scgrfmaskprobe.asm', 'Record 1 must remain untouched')
need('level1/wildbits/cmds/scgrfmaskprobe.asm', 'eora      #1')

# Historical GrfDrv DP allocation is fixed at one page.  S2B-6 consumes no
# offset above +$36 and the two-byte map save (+$2D,+$2E) cannot overlap the
# glyph rows (+$2F..+$36).
d = Path('defs/cocovtio.d').read_text()
for off in range(0x37, 0x40):
    token = f'grRsrved+${off:02X}'
    if token.lower() in d.lower():
        raise SystemExit(f'FAIL: SuperCoCo private state escaped reserved DP tail at {token}')

print('PASS: S2B-6 glyph scratch and bounded alpha replay source guards')
PY2

printf 'PASS: SuperCoCo S2B-6 style-9 alpha correctness/performance candidate builds\n'
printf 'NitrOS-9: %s\n' "$(git rev-parse HEAD)"
