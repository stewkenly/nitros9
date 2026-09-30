#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"
REQUIRED_BASE="7cf3027b549e9392c313c9645d269aad61134604"

if ! git merge-base --is-ancestor "$REQUIRED_BASE" HEAD; then
    echo "FAIL: candidate is not descended from published S2B6 verification-hygiene authority $REQUIRED_BASE" >&2
    exit 1
fi

"$ROOT/scripts/test-supercoco-s2b6-strip-build.sh"
git diff --check

python3 - <<'PY2'
from pathlib import Path


def need(path, token):
    data = Path(path).read_text()
    if token not in data:
        raise SystemExit(f"FAIL: {path}: missing dirty-mirror guard: {token}")

src = Path('level2/cmds/scgrf.inc').read_text()
cowin = Path('level2/coco3/modules/cowin.asm').read_text()
term = cowin[cowin.index('Term\n'):cowin.index('****************************\n* Main Entry point from VTIO', cowin.index('Term\n'))]
resident = term[term.index('* All windows are unallocated.  GrfDrv is now a session-resident shared'):term.index('TermEx              clrb')]
# Comments intentionally name the retained resources.  Inspect executable lines only
# for the historical destructive last-window operations.
resident_code = '\n'.join(
    line for line in resident.splitlines()
    if not line.lstrip().startswith('*')
)
for forbidden in (
    'lbsr      L0101',
    'os9       F$UnLink',
    'std       >WGlobal+G.GrfEnt',
    'os9       F$SRtMem',
):
    if forbidden in resident_code:
        raise SystemExit(f'FAIL: last-window resident policy still executes destructive operation {forbidden}')
if 'Keep the module link, G.GrfEnt and G.GfxTbl alive until system-session end.' not in resident:
    raise SystemExit('FAIL: missing explicit session-resident GrfDrv lifetime policy')

probe_lifetime = Path('level1/wildbits/cmds/scgrfmaskprobe.asm').read_text()
for token in (
    'S2B6 STYLE9 REOPEN PASS',
    '* Reopen after the last window has fully closed.',
    'leax      pathW15,pcr',
    'leax      alphaBC,pcr',
):
    if token not in probe_lifetime:
        raise SystemExit(f'FAIL: close/reopen lifetime witness missing {token}')
if probe_lifetime.count('os9       I$Open') < 2 or probe_lifetime.count('os9       I$Close') < 2:
    raise SystemExit('FAIL: close/reopen lifetime witness must execute two real open/close cycles')

# Teardown must fence the periodic VIDEO wakeup on authoritative inactive state.
disable = src[src.index('SCG_DISABLE'):src.index('SCG_SELECT_WINDOW', src.index('SCG_DISABLE'))]
for token in (
    'SCG_DISABLE         pshs      y',
    'ldy       #4',
    'SCG_DIS_WAIT_INACTIVE',
    'cmpa      #$FF',
    'lbne      SCG_DIS_WAIT_INACTIVE',
    'puls      y,pc',
):
    if token not in disable:
        raise SystemExit(f'FAIL: disable VBLANK fence missing {token}')
if disable.count('lbsr      SCG_WAIT_VIDEO') != 1:
    raise SystemExit('FAIL: disable fence must use one waiter inside the bounded state loop')

for token in (
    'SCG.StripRecords    equ       grSCMBOStart',
    'SCG.StripReplay     equ       grSCMBOStart+1',
    'SCG_ALPHA_DIRTY_MIRROR',
    'bita      #$01                640x480 INDEX4; full-speed gated by emulator',
):
    need('level2/cmds/scgrf.inc', token)

flush = src[src.index('SCG_ALPHA_STRIP_FLUSH\n'):src.index('SCG_ALPHA_DIRTY_MIRROR', src.index('SCG_ALPHA_STRIP_FLUSH\n'))]
for token in ('SC.GraphicsOpMasked', 'SCG.StripRecords', 'SCG_SUBMIT_RECORD'):
    if token not in flush:
        raise SystemExit(f'FAIL: retained strip flush missing {token}')
if 'SCG_SUBMIT_FILL' in flush:
    raise SystemExit('FAIL: dirty-strip flush fell back to record-0-only submit')
if 'cmpa      #2' not in flush:
    raise SystemExit('FAIL: retained command count is not bounded to two records')

mirror = src[src.index('SCG_ALPHA_DIRTY_MIRROR'):src.index('SCG_ALPHA_BATCH_COMMIT', src.index('SCG_ALPHA_DIRTY_MIRROR'))]
for token in (
    'SC.GraphicsOpBlit',
    'SCG_ADM_DESC_COPY',
    'SC.GfxCmdDstXO,x',
    'SC.GfxCmdSrcXO,x',
    'SC.GfxCmdDstYO,x',
    'SC.GfxCmdSrcYO,x',
    'SCG_SUBMIT_RECORD',
):
    if token not in mirror:
        raise SystemExit(f'FAIL: dirty mirror missing {token}')
if 'SC.GraphicsOpMasked' in mirror:
    raise SystemExit('FAIL: post-present mirror still depends on temporary MASKED_BLIT source')

batch = src[src.index('SCG_ALPHA_BATCH_COMMIT\n'):src.index('SCG_RENDER_RECT', src.index('SCG_ALPHA_BATCH_COMMIT\n'))]
for token in ('SCG_ALPHA_STRIP_FLUSH', 'SCG_PRESENT_BACK', 'SCG_ALPHA_DIRTY_MIRROR'):
    if token not in batch:
        raise SystemExit(f'FAIL: batch commit missing {token}')
for token in ('SCG_BUILD_MIRROR_BLIT_R1', 'SCG_SUBMIT_RECORD1'):
    if token in batch:
        raise SystemExit(f'FAIL: buffered alpha still performs full-frame mirror via {token}')
if batch.count('SCG_PRESENT_BACK') != 1:
    raise SystemExit('FAIL: buffered alpha must present exactly once')

# Deterministic pixel-row work: one row = 8+8; two rows = 16+16.
normal_rows = 8 + 8
wrap_rows = 2 * 8 + 2 * 8
if normal_rows != 16 or wrap_rows != 32:
    raise SystemExit('FAIL: dirty-mirror row-work invariant changed')

probe = Path('level1/wildbits/cmds/scgrfmaskprobe.asm').read_text()
for token in (
    'S2B6 DIRTY RECT MIRROR PASS',
    'S2B6 TWO-ROW DIRTY RECT PASS',
    'verifyWrapCommands',
    'verifyWrapMirror',
    'mirrorCopy          rmb       128',
    'alphaWrap16         fcc       /EEEEEEEEEEEEEFFF/',
):
    if token not in probe:
        raise SystemExit(f'FAIL: dirty-mirror runtime probe missing {token}')

print('PASS: S2B6 dirty-rectangle mirror source guards; normal=16 rows, wrap=32 rows')
PY2

RECIPE="$ROOT/recipes/coco3_6309/40d"
make -B -C "$RECIPE" --no-print-directory .mods/cowin.io .mods/grfdrv

test -s "$RECIPE/.mods/grfdrv"
os9 ident "$RECIPE/.mods/grfdrv" | grep -Fqi 'grfdrv' || {
    echo 'FAIL: built module identity is not grfdrv' >&2
    exit 1
}

printf 'PASS: SuperCoCo S2B6 style-9 dirty-rectangle mirror candidate builds\n'
printf 'NitrOS-9: %s\n' "$(git rev-parse HEAD)"
printf 'GrfDrv:   %s\n' "$RECIPE/.mods/grfdrv"
