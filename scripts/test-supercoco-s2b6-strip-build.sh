#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"
REQUIRED_BASE="fbcb28aa3dda339c62e18a7dcf832753ef2fb83a"

if ! git merge-base --is-ancestor "$REQUIRED_BASE" HEAD; then
    echo "FAIL: candidate is not descended from published S2B6 batch V3 $REQUIRED_BASE" >&2
    exit 1
fi

"$ROOT/scripts/test-supercoco-s2b6-batch-build.sh"
git diff --check

python3 - <<'PY2'
from pathlib import Path


def need(path, text):
    data = Path(path).read_text()
    if text not in data:
        raise SystemExit(f"FAIL: {path}: missing buffered-strip guard: {text}")


def forbid(path, text):
    data = Path(path).read_text()
    if text in data:
        raise SystemExit(f"FAIL: {path}: superseded per-glyph batch path remains: {text}")

src = Path('level2/cmds/scgrf.inc').read_text()
need('level2/cmds/scgrf.inc', 'SCG.StripStride     equ       320')
need('level2/cmds/scgrf.inc', 'SCG.StripStartX     equ       grSCCurrentBlock')
need('level2/cmds/scgrf.inc', 'SCG.StripCount      equ       grSCBlocksLeft')
need('level2/cmds/scgrf.inc', 'SCG.StripStartY     equ       grSCMBOBase')
need('level2/cmds/scgrf.inc', 'lbmi      SCG_ALPHA_STRIP      buffered write stages into one row strip')

render_start = src.index('SCG_RENDER_GLYPH')
render_end = src.index('********************************************************************\n* Retarget the already-built', render_start)
render = src[render_start:render_end]
for token in ('SCG_SUBMIT_FILL', 'SCG_PRESENT_BACK', 'SCG_RETARGET_MASKED_BACK'):
    if token not in render:
        raise SystemExit(f'FAIL: single-character renderer lost {token}')
for token in ('SCG_RG_BATCH', 'lbmi      SCG_RG_BATCH'):
    if token in render:
        raise SystemExit(f'FAIL: per-glyph V3 batch submission still active: {token}')

stage_start = src.index('SCG_STAGE_STRIP_GLYPH\n                    pshs')
stage_end = src.index('SCG_ALPHA_STRIP_FLUSH\n                    pshs', stage_start)
stage = src[stage_start:stage_end]
for token in (
    'leax      SCG.GlyphOffset,x',
    'leax      316,x',
    'inc       <SCG.StripCount',
    'lbsr      SCG_ALPHA_ADVANCE',
):
    if token not in stage:
        raise SystemExit(f'FAIL: strip stage missing {token}')
if 'SCG_SUBMIT_FILL' in stage:
    raise SystemExit('FAIL: strip stage still submits one MEDIA job per glyph')

flush_start = src.index('SCG_ALPHA_STRIP_FLUSH\n                    pshs')
flush_end = src.index('SCG_ALPHA_BATCH_COMMIT', flush_start)
flush = src[flush_start:flush_end]
for token in (
    'SC.GraphicsOpMasked',
    'SCG_SUBMIT_FILL',
    'SCG.StripCount',
):
    if token not in flush:
        raise SystemExit(f'FAIL: strip flush missing {token}')
if flush.count('SCG_SUBMIT_FILL') != 1:
    raise SystemExit('FAIL: one strip flush must submit exactly one MEDIA graphics job')
for token in (
    'lda       #$40',
    'lda       #$01',
    'lda       #$80',
    'lda       #$02',
    'lsld',
):
    if token not in flush:
        raise SystemExit(f'FAIL: strip command geometry guard missing {token}')

batch_start = src.index('SCG_ALPHA_BATCH_COMMIT')
batch_end = src.index('SCG_RENDER_RECT', batch_start)
batch = src[batch_start:batch_end]
for token in ('SCG_ALPHA_STRIP_FLUSH', 'SCG_PRESENT_BACK', 'SCG_BUILD_MIRROR_BLIT_R1', 'SCG_SUBMIT_RECORD1'):
    if token not in batch:
        raise SystemExit(f'FAIL: final strip commit missing {token}')
if batch.index('SCG_ALPHA_STRIP_FLUSH') > batch.index('SCG_PRESENT_BACK'):
    raise SystemExit('FAIL: final strip must flush before the one visible present')
if batch.count('SCG_PRESENT_BACK') != 1:
    raise SystemExit('FAIL: strip batch must present exactly once')

# 4K command-MBO fit: record area through byte 127, then one fixed 640x8
# INDEX4 source surface at offset 128 and stride 320.
end = 128 + 7 * 320 + 320
if end > 4096:
    raise SystemExit(f'FAIL: strip source exceeds 4K command MBO: end={end}')

need('level1/wildbits/cmds/scgrfmaskprobe.asm', 'S2B6 BUFFERED STRIP COMMIT PASS')
need('level1/wildbits/cmds/scgrfmaskprobe.asm', 'source stride 320 little endian')
need('level1/wildbits/cmds/scgrfmaskprobe.asm', 'source width 640 little endian')
need('level1/wildbits/cmds/scgrfmaskprobe.asm', 'source x=8 little endian')
need('level1/wildbits/cmds/scgrfmaskprobe.asm', 'command width 16 little endian')

print('PASS: S2B-6 buffered-alpha row-strip source guards')
PY2

RECIPE="$ROOT/recipes/coco3_6309/40d"
make -B -C "$RECIPE" --no-print-directory .mods/grfdrv

test -s "$RECIPE/.mods/grfdrv"
os9 ident "$RECIPE/.mods/grfdrv" | grep -Fqi 'grfdrv' || {
    echo 'FAIL: built module identity is not grfdrv' >&2
    exit 1
}

printf 'PASS: SuperCoCo S2B-6 buffered-alpha row-strip candidate builds\n'
printf 'NitrOS-9: %s\n' "$(git rev-parse HEAD)"
printf 'GrfDrv:   %s\n' "$RECIPE/.mods/grfdrv"
