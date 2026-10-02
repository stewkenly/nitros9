#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

REQUIRED_BASE="1b0ccec88b2076f818f3fd59b8c2f5a88b245561"
if ! git merge-base --is-ancestor "$REQUIRED_BASE" HEAD; then
    echo "FAIL: candidate is not descended from Community Alpha base $REQUIRED_BASE" >&2
    exit 1
fi

command -v lwasm >/dev/null 2>&1 || { echo 'FAIL: lwasm not found' >&2; exit 1; }

grep -Fq 'SC.SysRegmapCurrent' defs/supercoco.d
grep -Fq 'SC.SysRegmapSupported' defs/supercoco.d
grep -Fq 'SC.SysRegmapSelect' defs/supercoco.d
grep -Fq 'SC.RegmapNG' defs/supercoco.d
grep -Fq 'SC_REGMAP_ENTER_NG' level1/wildbits/libs/scsys/scsys.inc
grep -Fq 'SC_REGMAP_RESTORE' level1/wildbits/libs/scsys/scsys.inc

for client in scdemo scanim scgfxanim scavdemo; do
    src="level1/wildbits/cmds/$client.asm"
    grep -Fq 'lbsr      SC_REGMAP_ENTER_NG' "$src"
    grep -Fq 'lbsr      restoreSCMode' "$src"
done

# Discovery is deliberately observational: asking what the machine supports
# must not silently change the machine execution personality.
! grep -Fq 'SC_REGMAP_ENTER_NG' level1/wildbits/cmds/scinfo.asm
! grep -Fq 'SC_REGMAP_RESTORE' level1/wildbits/cmds/scinfo.asm

# Production GrfDrv owns SC mode across the live style-9 VIDEO/MEDIA lifetime.
# Keep that ownership inside the already-frozen one-page GrfDrv DP: the high
# two bits of grSCScreenTbl carry lifetime state while bits 13:0 remain pointer.
# The probe itself must not select SC mode, otherwise it could hide a driver bug.
! grep -Fq 'grSCSavedRegmap' defs/cocovtio.d
! grep -Fq 'grSCModeOwned' defs/cocovtio.d
grep -Fq 'SCG.ModeOwnedHi     equ       $80' level2/cmds/scgrf.inc
grep -Fq 'SCG.ModeSavedNGHi   equ       $40' level2/cmds/scgrf.inc
grep -Fq 'SCG.ModePtrHiMask   equ       $3F' level2/cmds/scgrf.inc
grep -Fq 'lbsr      SC_REGMAP_ENTER_NG' level2/cmds/scgrf.inc
grep -Fq 'anda      #SCG.ModePtrHiMask' level2/cmds/scgrf.inc
grep -Fq 'lbsr      SCG_RESTORE_MODE' level2/cmds/scgrf.inc
grep -Fq 'lbsr      SC_REGMAP_RESTORE' level2/cmds/scgrf.inc
! grep -Fq 'SC_REGMAP_ENTER_NG' level1/wildbits/cmds/scgrfmaskprobe.asm

WORK="$(mktemp -d /tmp/supercoco-sc-mode-source.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

AS=(
    lwasm
    --no-warn=ifp1
    --6309
    --format=os9
    --pragma=pcaspcr,nosymbolcase,condundefzero,undefextern,dollarnotlocal,noforwardrefmax
    --includedir="$ROOT/recipes/wildbits/l2"
    --includedir="$ROOT/defs"
)

for client in scdemo scanim scgfxanim scavdemo scs1probe; do
    "${AS[@]}" \
        -o "$WORK/$client" \
        "$ROOT/level1/wildbits/cmds/$client.asm"
    [[ -s "$WORK/$client" ]] || {
        echo "FAIL: $client assembly produced no module" >&2
        exit 1
    }
done

git diff --check

echo 'PASS: Community Alpha clients and production GrfDrv own SC mode without extending the fixed GrfDrv direct page'
