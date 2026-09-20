#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

EXPECTED='50535d0a422df7e7031497035021169baf3f6110'
ACTUAL="$(git rev-parse HEAD)"
[[ "$ACTUAL" == "$EXPECTED" ]] || {
    echo "FAIL: expected S2A-2 base $EXPECTED, found $ACTUAL" >&2
    exit 1
}

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

bash -n scripts/prepare-supercoco-s2a2.sh
grep -Fq 'scinfo scdemo scanim wbreset' recipes/wildbits/wildbits.mak
grep -Fq 'Anim.Frames         equ       120' level1/wildbits/cmds/scanim.asm
grep -Fq 'FB.FlagsMBO0' level1/wildbits/cmds/scanim.asm
grep -Fq 'FB.FlagsMBO1' level1/wildbits/cmds/scanim.asm
grep -Fq 'flipDisplay' level1/wildbits/cmds/scanim.asm
grep -Fq 'SC.VideoStageSurface' level1/wildbits/cmds/scanim.asm
grep -Fq 'SC.MBOStatusBusy' level1/wildbits/cmds/scanim.asm
[[ "$(grep -Fc 'os9       F$AllRAM' level1/wildbits/cmds/scanim.asm)" -ge 2 ]]
! grep -Eq 'rmb[[:space:]]+153600|rmb[[:space:]]+\$25800' level1/wildbits/cmds/scanim.asm

git diff --check

WORK="$(mktemp -d /tmp/supercoco-s2a2.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
MODULE="$WORK/scanim"
VHD="$WORK/63SDC-S2A2.VHD"
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
  "$ROOT/level1/wildbits/cmds/scanim.asm"

[[ -s "$MODULE" ]] || { echo 'FAIL: scanim assembly produced no module' >&2; exit 1; }
os9 ident "$MODULE" | grep -Fqi 'scanim' || { echo 'FAIL: module identity is not scanim' >&2; exit 1; }

cp "$BASE_VHD" "$VHD"
CMD_DIR='CMDS'
os9 dir "$VHD,$CMD_DIR" >/dev/null 2>&1 || CMD_DIR='cmds'
os9 dir "$VHD,$CMD_DIR" >/dev/null 2>&1 || { echo 'FAIL: no CMDS directory in base VHD' >&2; exit 1; }
os9 copy "$MODULE" "$VHD,$CMD_DIR/scanim"
os9 attr "$VHD,$CMD_DIR/scanim" -e -pe -r -pr
os9 copy -l "$VHD,startup" "$STARTUP"
printf '\nscanim\n' >> "$STARTUP"
os9 copy -l -r "$STARTUP" "$VHD,startup"

set +e
"$XROAR" -ui null -ao null -machine coco3 -machine-cpu 6309 -ram 16384 \
  -rompath "$ROMDIR" -romlist sdcdos=SDC-DOS.raw -cart supercocosdc \
  -cart-type cocosdc -no-cart-autorun -machine-cart supercocosdc \
  -load-hd0 "$VHD" -no-disk-write-back \
  -console-capture "$CONSOLE" -screen-capture "$SCREEN" \
  -trap pc=0x006b -trap-range 1 -trap-state "$CRASH" -trap-timeout 0.5 \
  -type $'DOS\r' -timeout "${S2A2_TIMEOUT:-90}" >"$LOG" 2>&1
RC=$?
set -e
printf 'XRoar exit status: %d\n' "$RC"

[[ ! -s "$CRASH" ]] || { echo 'FAIL: D.Crash trap fired during scanim' >&2; cat "$CRASH" >&2; exit 1; }
[[ -s "$SCREEN" ]] || { echo 'FAIL: no NitrOS-9 screen capture' >&2; tail -n 160 "$LOG" >&2 || true; exit 1; }
grep -Fq 'SuperCoCo S2A double-buffer PASS' "$SCREEN" || {
    echo 'FAIL: scanim did not return PASS after 120 VBLANK flips' >&2
    cat "$SCREEN" >&2
    tail -n 160 "$LOG" >&2 || true
    exit 1
}
if grep -Fq 'scanim: double-buffer demo failed' "$SCREEN"; then
    echo 'FAIL: scanim reported failure' >&2
    cat "$SCREEN" >&2
    exit 1
fi

echo 'PASS: S2A-2 two independent framebuffers completed 120 VBLANK-safe swaps'
