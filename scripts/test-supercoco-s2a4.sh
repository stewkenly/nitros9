#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

EXPECTED='ff30390eb0971bdff29f11e4ef0bd68c5e0208f6'
ACTUAL="$(git rev-parse HEAD)"
[[ "$ACTUAL" == "$EXPECTED" ]] || {
    echo "FAIL: expected S2A-4 base $EXPECTED, found $ACTUAL" >&2
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
    echo "FAIL: expected XRoar R1L baseline $EXPECTED_XROAR, found $XROAR_HEAD" >&2
    exit 1
}

bash -n scripts/prepare-supercoco-s2a4.sh
grep -Fq 'scinfo scdemo scanim scgfxanim scavdemo wbreset' recipes/wildbits/wildbits.mak
grep -Fq 'Anim.Frames         equ       120' level1/wildbits/cmds/scavdemo.asm
grep -Fq 'Audio.Blocks        equ       16' level1/wildbits/cmds/scavdemo.asm
grep -Fq 'Slot.Audio          equ       4' level1/wildbits/cmds/scavdemo.asm
grep -Fq 'SC.AudioCtlProdCommit' level1/wildbits/cmds/scavdemo.asm
grep -Fq 'serviceAudio' level1/wildbits/cmds/scavdemo.asm
grep -Fq 'verifyAudioConcurrent' level1/wildbits/cmds/scavdemo.asm
grep -Fq 'SC.MBOConsumerAudio' level1/wildbits/cmds/scavdemo.asm
grep -Fq 'SC.GraphicsOpFill' level1/wildbits/cmds/scavdemo.asm
grep -Fq 'SC.GraphicsOpBlit' level1/wildbits/cmds/scavdemo.asm
grep -Fq 'SC.GraphicsOpMasked' level1/wildbits/cmds/scavdemo.asm
[[ "$(grep -Fc 'os9       F$AllRAM' level1/wildbits/cmds/scavdemo.asm)" -eq 5 ]]
[[ "$(grep -Fc 'os9       F$MapBlk' level1/wildbits/cmds/scavdemo.asm)" -eq 3 ]]
! grep -Fq 'clearFramebuffer' level1/wildbits/cmds/scavdemo.asm
! grep -Fq 'drawRect' level1/wildbits/cmds/scavdemo.asm
! grep -Eq 'rmb[[:space:]]+153600|rmb[[:space:]]+\$25800' level1/wildbits/cmds/scavdemo.asm

git diff --check

WORK="$(mktemp -d /tmp/supercoco-s2a4.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
MODULE="$WORK/scavdemo"
VHD="$WORK/63SDC-S2A4.VHD"
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
  "$ROOT/level1/wildbits/cmds/scavdemo.asm"

[[ -s "$MODULE" ]] || { echo 'FAIL: scavdemo assembly produced no module' >&2; exit 1; }
os9 ident "$MODULE" | grep -Fqi 'scavdemo' || { echo 'FAIL: module identity is not scavdemo' >&2; exit 1; }

cp "$BASE_VHD" "$VHD"
CMD_DIR='CMDS'
os9 dir "$VHD,$CMD_DIR" >/dev/null 2>&1 || CMD_DIR='cmds'
os9 dir "$VHD,$CMD_DIR" >/dev/null 2>&1 || { echo 'FAIL: no CMDS directory in base VHD' >&2; exit 1; }
os9 copy "$MODULE" "$VHD,$CMD_DIR/scavdemo"
os9 attr "$VHD,$CMD_DIR/scavdemo" -e -pe -r -pr
os9 copy -l "$VHD,startup" "$STARTUP"
printf '\nscavdemo\n' >> "$STARTUP"
os9 copy -l -r "$STARTUP" "$VHD,startup"

set +e
"$XROAR" -ui null -ao null -machine coco3 -machine-cpu 6309 -ram 16384 \
  -rompath "$ROMDIR" -romlist sdcdos=SDC-DOS.raw -cart supercocosdc \
  -cart-type cocosdc -no-cart-autorun -machine-cart supercocosdc \
  -load-hd0 "$VHD" -no-disk-write-back \
  -console-capture "$CONSOLE" -screen-capture "$SCREEN" \
  -trap pc=0x006b -trap-range 1 -trap-state "$CRASH" -trap-timeout 0.5 \
  -type $'DOS\r' -timeout "${S2A4_TIMEOUT:-300}" >"$LOG" 2>&1
RC=$?
set -e
printf 'XRoar exit status: %d\n' "$RC"

[[ ! -s "$CRASH" ]] || { echo 'FAIL: D.Crash trap fired during scavdemo' >&2; cat "$CRASH" >&2; exit 1; }
[[ -s "$SCREEN" ]] || { echo 'FAIL: no NitrOS-9 screen capture' >&2; tail -n 200 "$LOG" >&2 || true; exit 1; }
grep -Fq 'SuperCoCo S2A VIDEO+MEDIA+AUDIO PASS' "$SCREEN" || {
    echo 'FAIL: scavdemo did not complete concurrent graphics+audio workload' >&2
    cat "$SCREEN" >&2
    tail -n 200 "$LOG" >&2 || true
    exit 1
}
if grep -Fq 'scavdemo: concurrent graphics+audio failed' "$SCREEN"; then
    echo 'FAIL: scavdemo reported failure' >&2
    cat "$SCREEN" >&2
    exit 1
fi

echo 'PASS: S2A-4 concurrent R1K graphics + R1L 48 kHz stereo PCM proof'
