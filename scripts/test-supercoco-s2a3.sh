#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

EXPECTED='4ef59a59170b12f53ef517f19ed859992cabe626'
ACTUAL="$(git rev-parse HEAD)"
[[ "$ACTUAL" == "$EXPECTED" ]] || {
    echo "FAIL: expected S2A-3 base $EXPECTED, found $ACTUAL" >&2
    exit 1
}

EXPECTED_XROAR='3429056f410ea3d9713ccddc96c492f159bd9a8a'
SUPERCOCO_XROAR_ROOT="${SUPERCOCO_XROAR_ROOT:-/Volumes/design/supercoco-xroar}"
SUPERCOCO_EMULATOR_ROOT="${SUPERCOCO_EMULATOR_ROOT:-/Volumes/design/supercoco-emulator}"
XROAR="${XROAR:-$SUPERCOCO_XROAR_ROOT/src/xroar}"
ROMDIR="${ROMDIR:-$SUPERCOCO_EMULATOR_ROOT/roms}"
BASE_VHD="${BASE_VHD:-$SUPERCOCO_EMULATOR_ROOT/images/63SDC.VHD}"

for cmd in lwasm os9; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "FAIL: $cmd not found" >&2; exit 1; }
done
[[ -x "$XROAR" ]] || { echo "FAIL: missing XRoar binary: $XROAR" >&2; exit 1; }
[[ -f "$ROMDIR/coco3.rom" ]] || { echo 'FAIL: missing coco3.rom' >&2; exit 1; }
[[ -f "$ROMDIR/SDC-DOS.raw" ]] || { echo 'FAIL: missing SDC-DOS.raw' >&2; exit 1; }
[[ -f "$BASE_VHD" ]] || { echo "FAIL: missing base VHD: $BASE_VHD" >&2; exit 1; }

XROAR_HEAD="$(git -C "$SUPERCOCO_XROAR_ROOT" rev-parse HEAD)"
[[ "$XROAR_HEAD" == "$EXPECTED_XROAR" ]] || {
    echo "FAIL: expected XRoar host-video baseline $EXPECTED_XROAR, found $XROAR_HEAD" >&2
    exit 1
}

bash -n scripts/prepare-supercoco-s2a3.sh
grep -Fq 'scinfo scdemo scanim scgfxanim wbreset' recipes/wildbits/wildbits.mak
grep -Fq 'Anim.Frames         equ       120' level1/wildbits/cmds/scgfxanim.asm
grep -Fq 'SC.GraphicsOpFill' level1/wildbits/cmds/scgfxanim.asm
grep -Fq 'SC.GraphicsOpBlit' level1/wildbits/cmds/scgfxanim.asm
grep -Fq 'SC.GraphicsOpMasked' level1/wildbits/cmds/scgfxanim.asm
grep -Fq 'SC.MBOConsumerVideo!SC.MBOConsumerMedia' level1/wildbits/cmds/scgfxanim.asm
grep -Fq 'Slot.Cmd            equ       2' level1/wildbits/cmds/scgfxanim.asm
grep -Fq 'Slot.Src            equ       3' level1/wildbits/cmds/scgfxanim.asm
grep -Fq 'MEDIA is the sole framebuffer writer' level1/wildbits/cmds/scgfxanim.asm
[[ "$(grep -Fc 'os9       F$AllRAM' level1/wildbits/cmds/scgfxanim.asm)" -eq 4 ]]
[[ "$(grep -Fc 'os9       F$MapBlk' level1/wildbits/cmds/scgfxanim.asm)" -eq 2 ]]
! grep -Fq 'clearFramebuffer' level1/wildbits/cmds/scgfxanim.asm
! grep -Fq 'drawRect' level1/wildbits/cmds/scgfxanim.asm
! grep -Eq 'rmb[[:space:]]+153600|rmb[[:space:]]+\$25800' level1/wildbits/cmds/scgfxanim.asm

git diff --check

WORK="$(mktemp -d /tmp/supercoco-s2a3.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
MODULE="$WORK/scgfxanim"
VHD="$WORK/63SDC-S2A3.VHD"
STARTUP="$WORK/startup.txt"
SCREEN="$WORK/screen.txt"
CONSOLE="$WORK/console.txt"
LOG="$WORK/xroar.log"
CRASH="$WORK/crash.txt"

lwasm \
  --no-warn=ifp1 \
  --6309 \
  --format=os9 \
  --pragma=pcaspcr,nosymbolcase,condundefzero,undefextern,dollarnotlocal,noforwardrefmax \
  --includedir="$ROOT/recipes/wildbits/l2" \
  --includedir="$ROOT/defs" \
  -o "$MODULE" \
  "$ROOT/level1/wildbits/cmds/scgfxanim.asm"

[[ -s "$MODULE" ]] || { echo 'FAIL: scgfxanim assembly produced no module' >&2; exit 1; }
os9 ident "$MODULE" | grep -Fqi 'scgfxanim' || { echo 'FAIL: module identity is not scgfxanim' >&2; exit 1; }

cp "$BASE_VHD" "$VHD"
CMD_DIR='CMDS'
os9 dir "$VHD,$CMD_DIR" >/dev/null 2>&1 || CMD_DIR='cmds'
os9 dir "$VHD,$CMD_DIR" >/dev/null 2>&1 || { echo 'FAIL: no CMDS directory in base VHD' >&2; exit 1; }
os9 copy "$MODULE" "$VHD,$CMD_DIR/scgfxanim"
os9 attr "$VHD,$CMD_DIR/scgfxanim" -e -pe -r -pr
os9 copy -l "$VHD,startup" "$STARTUP"
printf '\nscgfxanim\n' >> "$STARTUP"
os9 copy -l -r "$STARTUP" "$VHD,startup"

set +e
"$XROAR" -ui null -ao null -machine coco3 -machine-cpu 6309 -ram 16384 \
  -rompath "$ROMDIR" -romlist sdcdos=SDC-DOS.raw -cart supercocosdc \
  -cart-type cocosdc -no-cart-autorun -machine-cart supercocosdc \
  -load-hd0 "$VHD" -no-disk-write-back \
  -console-capture "$CONSOLE" -screen-capture "$SCREEN" \
  -trap pc=0x006b -trap-range 1 -trap-state "$CRASH" -trap-timeout 0.5 \
  -type $'DOS\r' -timeout "${S2A3_TIMEOUT:-180}" >"$LOG" 2>&1
RC=$?
set -e
printf 'XRoar exit status: %d\n' "$RC"

[[ ! -s "$CRASH" ]] || { echo 'FAIL: D.Crash trap fired during scgfxanim' >&2; cat "$CRASH" >&2; exit 1; }
[[ -s "$SCREEN" ]] || { echo 'FAIL: no NitrOS-9 screen capture' >&2; tail -n 200 "$LOG" >&2 || true; exit 1; }
grep -Fq 'SuperCoCo S2A R1K graphics PASS' "$SCREEN" || {
    echo 'FAIL: scgfxanim did not complete accelerated animation' >&2
    cat "$SCREEN" >&2
    tail -n 200 "$LOG" >&2 || true
    exit 1
}
if grep -Fq 'scgfxanim: R1K animation failed' "$SCREEN"; then
    echo 'FAIL: scgfxanim reported failure' >&2
    cat "$SCREEN" >&2
    exit 1
fi

echo 'PASS: S2A-3 R1K FILL/BLIT/MASKED rendered through double-buffered GIME-NG output'
