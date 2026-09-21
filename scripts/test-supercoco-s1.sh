#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

REQUIRED_NITROS_BASE="12963de229600c098a7058f452eb7b72f38e0e6c"
REQUIRED_XROAR_BASE="23d6f425d805de419f0297a62cbe60b6450e92e2"

if ! git merge-base --is-ancestor "$REQUIRED_NITROS_BASE" HEAD; then
    echo "FAIL: candidate is not descended from accepted NitrOS-9 base $REQUIRED_NITROS_BASE" >&2
    exit 1
fi

if [[ -n "${SUPERCOCO_XROAR_ROOT:-}" ]]; then
    XROAR_ROOT="$SUPERCOCO_XROAR_ROOT"
elif [[ -d /Volumes/design/supercoco-emulator/upstream/.git ]]; then
    XROAR_ROOT=/Volumes/design/supercoco-emulator/upstream
else
    XROAR_ROOT=/Volumes/design/supercoco-xroar
fi
SUPERCOCO_EMULATOR_ROOT="${SUPERCOCO_EMULATOR_ROOT:-/Volumes/design/supercoco-emulator}"
XROAR="${XROAR:-$XROAR_ROOT/src/xroar}"
ROMDIR="${ROMDIR:-$SUPERCOCO_EMULATOR_ROOT/roms}"
BASE_VHD="${BASE_VHD:-$SUPERCOCO_EMULATOR_ROOT/images/63SDC.VHD}"

for cmd in git lwasm lwlink os9; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "FAIL: $cmd not found" >&2; exit 1; }
done
[[ -d "$XROAR_ROOT/.git" ]] || { echo "FAIL: missing XRoar repository: $XROAR_ROOT" >&2; exit 1; }
[[ -x "$XROAR" ]] || { echo "FAIL: missing XRoar binary: $XROAR" >&2; exit 1; }
[[ -f "$ROMDIR/coco3.rom" ]] || { echo "FAIL: missing coco3.rom in $ROMDIR" >&2; exit 1; }
[[ -f "$ROMDIR/SDC-DOS.raw" ]] || { echo "FAIL: missing SDC-DOS.raw in $ROMDIR" >&2; exit 1; }
[[ -f "$BASE_VHD" ]] || { echo "FAIL: missing NitrOS-9 base VHD: $BASE_VHD" >&2; exit 1; }

if ! git -C "$XROAR_ROOT" merge-base --is-ancestor "$REQUIRED_XROAR_BASE" HEAD; then
    echo "FAIL: XRoar candidate is not descended from accepted R1L+NativeNet base $REQUIRED_XROAR_BASE" >&2
    exit 1
fi

# Retain the original discovery and shared-library checkpoints on descendants.
"$ROOT/scripts/test-supercoco-s1a.sh"
"$ROOT/scripts/test-supercoco-s1b.sh"

# Ensure the real runtime client still consumes the shared layer rather than a
# private portal copy.
grep -Fq 'use       ../libs/scsys/scsys.inc' level1/wildbits/cmds/scanim.asm
grep -Fq 'lbsr      SC_PROBE_R1L' level1/wildbits/cmds/scanim.asm
grep -Fq 'lbsr      SC_IRQ_GET' level1/wildbits/cmds/scanim.asm
grep -Fq 'lbsr      SC_IRQ_ACK' level1/wildbits/cmds/scanim.asm

git diff --check

WORK="$(mktemp -d /tmp/supercoco-s1.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
PROBE="$WORK/scs1probe"
ANIM="$WORK/scanim"
VHD="$WORK/63SDC-S1.VHD"
STARTUP="$WORK/startup.txt"
SCREEN="$WORK/screen.txt"
CONSOLE="$WORK/console.txt"
LOG="$WORK/xroar.log"
CRASH="$WORK/crash.txt"

AS=(
    lwasm
    --no-warn=ifp1
    --6309
    --format=os9
    --pragma=pcaspcr,nosymbolcase,condundefzero,undefextern,dollarnotlocal,noforwardrefmax
    --includedir="$ROOT/recipes/wildbits/l2"
    --includedir="$ROOT/defs"
)

"${AS[@]}" -o "$PROBE" "$ROOT/level1/wildbits/cmds/scs1probe.asm"
"${AS[@]}" -o "$ANIM" "$ROOT/level1/wildbits/cmds/scanim.asm"
[[ -s "$PROBE" ]] || { echo 'FAIL: scs1probe assembly produced no module' >&2; exit 1; }
[[ -s "$ANIM" ]] || { echo 'FAIL: scanim assembly produced no module' >&2; exit 1; }
os9 ident "$PROBE" | grep -Fqi 'scs1probe' || { echo 'FAIL: module identity is not scs1probe' >&2; exit 1; }
os9 ident "$ANIM" | grep -Fqi 'scanim' || { echo 'FAIL: module identity is not scanim' >&2; exit 1; }

cp "$BASE_VHD" "$VHD"
CMD_DIR='CMDS'
os9 dir "$VHD,$CMD_DIR" >/dev/null 2>&1 || CMD_DIR='cmds'
os9 dir "$VHD,$CMD_DIR" >/dev/null 2>&1 || { echo 'FAIL: no CMDS directory in base VHD' >&2; exit 1; }
os9 copy "$PROBE" "$VHD,$CMD_DIR/scs1probe"
os9 attr "$VHD,$CMD_DIR/scs1probe" -e -pe -r -pr
os9 copy "$ANIM" "$VHD,$CMD_DIR/scanim"
os9 attr "$VHD,$CMD_DIR/scanim" -e -pe -r -pr
os9 copy -l "$VHD,startup" "$STARTUP"
printf '\nscs1probe\nscanim\n' >> "$STARTUP"
os9 copy -l -r "$STARTUP" "$VHD,startup"

set +e
"$XROAR" -ui null -ao null -machine coco3 -machine-cpu 6309 -ram 16384 \
  -rompath "$ROMDIR" -romlist sdcdos=SDC-DOS.raw -cart supercocosdc \
  -cart-type cocosdc -no-cart-autorun -machine-cart supercocosdc \
  -load-hd0 "$VHD" -no-disk-write-back \
  -console-capture "$CONSOLE" -screen-capture "$SCREEN" \
  -trap pc=0x006b -trap-range 1 -trap-state "$CRASH" -trap-timeout 0.5 \
  -type $'DOS\r' -timeout "${S1_TIMEOUT:-120}" >"$LOG" 2>&1
RC=$?
set -e
printf 'XRoar exit status: %d\n' "$RC"

[[ ! -s "$CRASH" ]] || { echo 'FAIL: D.Crash trap fired during S1 closure proof' >&2; cat "$CRASH" >&2; exit 1; }
[[ -s "$SCREEN" ]] || { echo 'FAIL: no S1 NitrOS-9 screen capture' >&2; tail -n 180 "$LOG" >&2 || true; exit 1; }

required=(
  'S1 DISCOVERY PORTAL PASS'
  'S1 IRQ MASK STATUS W1C PASS'
  'S1 MBO HELPER PASS'
  'SUPERCOCO S1 PASS'
  'SuperCoCo S2A double-buffer PASS'
)
for line in "${required[@]}"; do
    grep -Fq "$line" "$SCREEN" || {
        echo "FAIL: missing S1 runtime marker: $line" >&2
        cat "$SCREEN" >&2
        tail -n 180 "$LOG" >&2 || true
        exit 1
    }
done
if grep -Fq 'SUPERCOCO S1 FAIL' "$SCREEN"; then
    echo 'FAIL: native S1 probe reported failure' >&2
    cat "$SCREEN" >&2
    exit 1
fi

printf 'PASS: SuperCoCo NitrOS-9 S1 common service/IRQ layer retained closure\n'
printf 'NitrOS-9: %s\n' "$(git rev-parse HEAD)"
printf 'XRoar:    %s\n' "$(git -C "$XROAR_ROOT" rev-parse HEAD)"
printf 'Screen:   %s\n' "$SCREEN"
printf 'Console:  %s\n' "$CONSOLE"
printf 'Log:      %s\n' "$LOG"
