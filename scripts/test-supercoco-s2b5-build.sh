#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"
REQUIRED_BASE="8d3f9b42d0d087e6d6f5eaaaa89a372e46cc0811"

if ! git merge-base --is-ancestor "$REQUIRED_BASE" HEAD; then
    echo "FAIL: candidate is not descended from accepted S2B-4 base $REQUIRED_BASE" >&2
    exit 1
fi

for cmd in git make lwasm os9 python3; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "FAIL: $cmd not found" >&2; exit 1; }
done

# SWAI 0.1.10 is the locally validated lifecycle tool for this candidate.  If
# the project carries an assurance-toolchain pin, do not publish through a
# stale pin silently.
PIN="$ROOT/ASSURANCE_TOOLCHAIN_PIN.md"
if [[ -f "$PIN" ]] && ! grep -Fq '0.1.10' "$PIN"; then
    echo 'FAIL: ASSURANCE_TOOLCHAIN_PIN.md exists but does not pin SWAI 0.1.10' >&2
    exit 1
fi

git diff --check

python3 - <<'PY'
from pathlib import Path

def need(path, text):
    data=Path(path).read_text()
    if text not in data:
        raise SystemExit(f"FAIL: {path}: missing retained S2B-5 source guard: {text}")

def forbid(path, text):
    data=Path(path).read_text()
    if text in data:
        raise SystemExit(f"FAIL: {path}: rejected V1 integration seam still present: {text}")

need('defs/cocovtio.d', 'grSCGlyphRows       EQU       grRsrved+$2E')
need('defs/cocovtio.d', 'grSCMaskKey         EQU       grRsrved+$36')
need('defs/cocovtio.d', 'grRsrved            RMB       256-.')
need('level2/cmds/grfdrv.asm', 'ldx       Wt.STbl,y           inspect the target window before consuming char 0')
need('level2/cmds/grfdrv.asm', 'SCG_FC_NEXT         lda       ,x+')
need('level2/cmds/grfdrv.asm', 'SCG_FC_BAD          puls      x                   unwind caller-owned buffer pointer')
need('level2/cmds/grfdrv.asm', 'lbsr      SCG_ALPHA_ENTRY     R1K-backed fixed 8x8 style-9 alpha output')
need('level2/cmds/grfdrv.asm', 'L0F4DLegacy         tstb                          restore sign test clobbered by CMPB')
forbid('level2/cmds/grfdrv.asm', 'L0F4DLegacy         equ       *')
need('level2/cmds/grfdrv.asm', 'rts                           preserve backend Carry/B for the caller')
need('level2/cmds/grfdrv.asm', 'pshs      cc                  preserve backend Carry while classifying target')
forbid('level2/cmds/grfdrv.asm', 'lbeq      f1.do               first char already rendered; continue via Not8Wd')
forbid('level2/cmds/grfdrv.asm', 'lbcc      L0F4DSCDone')
need('level2/cmds/scgrf.inc', 'SCG.GlyphOffset     equ       128')
need('level2/cmds/scgrf.inc', 'SCG_BUILD_MASKED_GLYPH')
need('level2/cmds/scgrf.inc', 'lda       #SC.GraphicsOpMasked')
need('level2/cmds/scgrf.inc', 'SCG_BUILD_MIRROR_BLIT_R1')
need('level2/cmds/scgrf.inc', 'SCG_SUBMIT_RECORD1')
need('level2/cmds/scgrf.inc', 'ldd       #Grp.Fnt*256+Fnt.S8x8')
need('level1/wildbits/cmds/scgrfmaskprobe.asm', "alphaA              fcb       'A'")
need('level1/wildbits/cmds/scgrfmaskprobe.asm', 'alphaBC             fcc       /BC/')
need('level1/wildbits/cmds/scgrfmaskprobe.asm', 'verifyBufferedFB')
need('level1/wildbits/cmds/scgrfmaskprobe.asm', 'S2B5 R1K SINGLE CHAR0 PASS')
need('level1/wildbits/cmds/scgrfmaskprobe.asm', 'S2B5 R1K BUFFERED BC PASS')
need('level1/wildbits/cmds/scgrfmaskprobe.asm', 'tcharOn             fcb       $1B,$3C,$01')
need('level1/wildbits/cmds/scgrfmaskprobe.asm', 'stu       cmdMap,y            preserve F$MapBlk U for F$ClrBlk')
need('level1/wildbits/cmds/scgrfmaskprobe.asm', 'ldu       cmdMap,y            F$ClrBlk requires mapped address in U')
need('level1/wildbits/cmds/scgrfmaskprobe.asm', 'vofMappedBad        ldu       cmdMap,y            restore mapped address before unmap')
need('level1/wildbits/cmds/scgrfmaskprobe.asm', '                    ldu       cmdMap,y            restore verifyCommands map for F$ClrBlk')
need('level1/wildbits/cmds/scgrfmaskprobe.asm', 'vcMappedBad         ldu       cmdMap,y            restore verifyCommands map before unmap')
need('scripts/test-supercoco-s2b5-runtime.sh', 'REQUIRED_XROAR_BASE="23d6f425d805de419f0297a62cbe60b6450e92e2"')
forbid('scripts/test-supercoco-s2b5-runtime.sh', '3429056f410ea3d9713ccddc96c492f159bd9a8a')

# The two new aliases deliberately consume the final nine bytes of the
# historical reserved tail and may not grow beyond +$36 without a new review.
d=Path('defs/cocovtio.d').read_text()
for off in range(0x37, 0x40):
    token=f'grRsrved+${off:02X}'
    if token in d or token.lower() in d.lower():
        raise SystemExit(f'FAIL: SuperCoCo private state escaped reserved DP tail at {token}')

print('PASS: S2B-5 source guards')
PY

RECIPE="$ROOT/recipes/coco3_6309/40d"
make -C "$RECIPE" --no-print-directory .mods/cowin.io .mods/grfdrv

test -s "$RECIPE/.mods/cowin.io"
test -s "$RECIPE/.mods/grfdrv"

WORK="$(mktemp -d /tmp/supercoco-s2b5-build.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
PROBE="$WORK/scgrfmaskprobe"

lwasm \
  --no-warn=ifp1 \
  --6309 \
  --format=os9 \
  --pragma=pcaspcr,nosymbolcase,condundefzero,undefextern,dollarnotlocal,noforwardrefmax \
  --includedir="$ROOT/recipes/wildbits/l2" \
  --includedir="$ROOT/defs" \
  -o "$PROBE" \
  "$ROOT/level1/wildbits/cmds/scgrfmaskprobe.asm"

test -s "$PROBE"
os9 ident "$PROBE" | grep -Fqi 'scgrfmaskprobe' || {
    echo 'FAIL: probe module identity is not scgrfmaskprobe' >&2
    exit 1
}

printf 'PASS: SuperCoCo S2B-5 R1K MASKED_BLIT alpha candidate builds\n'
printf 'NitrOS-9: %s\n' "$(git rev-parse HEAD)"
printf 'GrfDrv:   %s\n' "$RECIPE/.mods/grfdrv"
printf 'Probe:    %s\n' "$PROBE"
