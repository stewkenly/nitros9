#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"
REQUIRED_BASE="1e99541240dc98baf8a814f8e6520876a4cbba3a"

if ! git merge-base --is-ancestor "$REQUIRED_BASE" HEAD; then
    echo "FAIL: candidate is not descended from published S2B6 alpha base $REQUIRED_BASE" >&2
    exit 1
fi

"$ROOT/scripts/test-supercoco-s2b6-build.sh"
git diff --check

python3 - <<'PY2'
from pathlib import Path


def need(path, text):
    data = Path(path).read_text()
    if text not in data:
        raise SystemExit(f"FAIL: {path}: missing buffered-batch guard: {text}")


def forbid(path, text):
    data = Path(path).read_text()
    if text in data:
        raise SystemExit(f"FAIL: {path}: superseded buffered-alpha path remains: {text}")

# The accepted H6309 fast buffer is at most 64 characters, so bit 7 of the
# existing count byte is available as a transaction marker without new DP.
need('level2/cmds/grfdrv.asm', '64 max/6309')
need('level2/cmds/grfdrv.asm', 'cmpa      #1')
need('level2/cmds/grfdrv.asm', 'lbsr      L0F4B.1             preserve accepted S2B6 single-buffered-character path')
need('level2/cmds/grfdrv.asm', 'ora       #$80')
need('level2/cmds/grfdrv.asm', 'lbsr      L0F4B.1             character 0 owns normal setup')
need('level2/cmds/grfdrv.asm', 'lbsr      Not8Wd               reuse mapped font/window setup')
need('level2/cmds/grfdrv.asm', 'lbsr      SCG_ALPHA_BATCH_COMMIT')
need('level2/cmds/grfdrv.asm', 'SCG_FC_NEXT         lda       ,x+')
need('level2/cmds/grfdrv.asm', 'SCG_FC_BAD          puls      x                   unwind caller-owned buffer pointer')
need('level2/cmds/grfdrv.asm', 'SCG_FC_ROLLBACK')
need('level2/cmds/grfdrv.asm', 'stq       <gr0047             keep GrfDrv working cursor coherent')
need('level2/cmds/grfdrv.asm', 'SCG_FC_SINGLE_BAD   clr       <gr0082+1')
need('level2/cmds/grfdrv.asm', 'SCG_FC_COMMIT_BAD   clr       <gr0082+1')
need('level2/cmds/grfdrv.asm', 'SCG_FC_DIRTY        ldb       #E$NotRdy')
need('level2/cmds/grfdrv.asm', 'lbmi      fast.set            yes, make it _really_ fast')
forbid('level2/cmds/grfdrv.asm', '                    bmi       fast.set            yes, make it _really_ fast')
grf = Path('level2/cmds/grfdrv.asm').read_text()
for start, end in (
    ('SCG_FC_SINGLE_BAD', 'SCG_FC_BATCH_BEGIN'),
    ('SCG_FC_ROLLBACK', 'SCG_FC_COMMIT_BAD'),
    ('SCG_FC_COMMIT_BAD', 'SCG_FC_DIRTY'),
    ('SCG_FC_DIRTY', 'SCG_FC_LEGACY'),
):
    block = grf[grf.index(start):grf.index(end, grf.index(start))]
    if 'orcc      #Carry' not in block:
        raise SystemExit(f'FAIL: {start} can return an error without Carry set')

src = Path('level2/cmds/scgrf.inc').read_text()
render_start = src.index('SCG_RENDER_GLYPH')
render_end = src.index('SCG_ALPHA_ADVANCE', render_start)
render = src[render_start:render_end]
for token in ('SCG_PRESENT_BACK', 'SCG_RETARGET_MASKED_BACK'):
    if token not in render:
        raise SystemExit(f'FAIL: retained single-character alpha path missing {token}')

strip_mode = 'SCG_STAGE_STRIP_GLYPH' in src
if strip_mode:
    alpha_start = src.index('SCG_ALPHA_ENTRY')
    alpha_end = src.index('SCG_ALPHA_BAD       ldb', alpha_start)
    alpha = src[alpha_start:alpha_end]
    for token in ('tst       <gr0082+1', 'lbmi      SCG_ALPHA_STRIP', 'SCG_STAGE_STRIP_GLYPH'):
        if token not in alpha:
            raise SystemExit(f'FAIL: strip descendant lost buffered staging route {token}')
    for token in ('lbmi      SCG_RG_BATCH', 'SCG_RG_BATCH'):
        if token in render:
            raise SystemExit(f'FAIL: strip descendant still submits glyphs through V3 deferred renderer: {token}')
else:
    for token in ('tst       <gr0082+1', 'lbmi      SCG_RG_BATCH'):
        if token not in render:
            raise SystemExit(f'FAIL: V3 single/deferred alpha split missing {token}')

batch_start = src.index('SCG_ALPHA_BATCH_COMMIT')
batch_end = src.index('SCG_RENDER_RECT', batch_start)
batch = src[batch_start:batch_end]
for token in (
    'SCG_PRESENT_BACK',
    'SCG_BUILD_MIRROR_BLIT_R1',
    'SCG_SUBMIT_RECORD1',
    'SCG_ABC_PRE_BAD',
    'SCG_ABC_POST_BAD',
):
    if token not in batch:
        raise SystemExit(f'FAIL: batch commit missing {token}')
if batch.count('SCG_PRESENT_BACK') != 1:
    raise SystemExit('FAIL: buffered batch commit must contain exactly one present call')
if strip_mode and 'SCG_ALPHA_STRIP_FLUSH' not in batch:
    raise SystemExit('FAIL: strip descendant does not flush its final row before present')

need('level2/cmds/scgrf.inc', 'negative count here can only belong to the current governed transaction')
need('level1/wildbits/cmds/scgrfmaskprobe.asm', 'verifyBatchCommands')
need('level1/wildbits/cmds/scgrfmaskprobe.asm', 'Batched presentation must toggle exactly once relative to single A.')
need('level1/wildbits/cmds/scgrfmaskprobe.asm', 'cmpd      #$8002              width 640 little endian')
if strip_mode:
    need('level1/wildbits/cmds/scgrfmaskprobe.asm', 'S2B6 BUFFERED STRIP COMMIT PASS')
    need('level1/wildbits/cmds/scgrfmaskprobe.asm', 'cmpd      #$1000              command width 16 little endian')
else:
    need('level1/wildbits/cmds/scgrfmaskprobe.asm', 'S2B6 BUFFERED BATCH COMMIT PASS')
    need('level1/wildbits/cmds/scgrfmaskprobe.asm', 'cmpd      #$1000              x=16 little endian')

print('PASS: S2B-6 buffered-alpha batch source guards')
PY2

RECIPE="$ROOT/recipes/coco3_6309/40d"
make -B -C "$RECIPE" --no-print-directory .mods/grfdrv

test -s "$RECIPE/.mods/grfdrv"
os9 ident "$RECIPE/.mods/grfdrv" | grep -Fqi 'grfdrv' || {
    echo 'FAIL: built module identity is not grfdrv' >&2
    exit 1
}

printf 'PASS: SuperCoCo S2B-6 buffered-alpha batch candidate builds\n'
printf 'NitrOS-9: %s\n' "$(git rev-parse HEAD)"
printf 'GrfDrv:   %s\n' "$RECIPE/.mods/grfdrv"
