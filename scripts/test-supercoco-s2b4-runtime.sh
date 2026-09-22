#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

REQUIRED_NITROS_BASE="400c0247644bf1468ba1776d2fc1c9134b449dd0"
REQUIRED_XROAR_BASE="23d6f425d805de419f0297a62cbe60b6450e92e2"

if ! git merge-base --is-ancestor "$REQUIRED_NITROS_BASE" HEAD; then
    echo "FAIL: candidate is not descended from accepted S2B-3 base $REQUIRED_NITROS_BASE" >&2
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

for cmd in git make lwasm os9 python3; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "FAIL: $cmd not found" >&2; exit 1; }
done
[[ -d "$XROAR_ROOT/.git" ]] || { echo "FAIL: missing XRoar repository: $XROAR_ROOT" >&2; exit 1; }
[[ -x "$XROAR" ]] || { echo "FAIL: missing XRoar binary: $XROAR" >&2; exit 1; }
[[ -f "$ROMDIR/coco3.rom" ]] || { echo "FAIL: missing coco3.rom in $ROMDIR" >&2; exit 1; }
[[ -f "$ROMDIR/SDC-DOS.raw" ]] || { echo "FAIL: missing SDC-DOS.raw in $ROMDIR" >&2; exit 1; }
[[ -f "$BASE_VHD" ]] || { echo "FAIL: missing NitrOS-9 base VHD: $BASE_VHD" >&2; exit 1; }

if ! git -C "$XROAR_ROOT" merge-base --is-ancestor "$REQUIRED_XROAR_BASE" HEAD; then
    echo "FAIL: XRoar candidate is not descended from accepted R1L+R1K base $REQUIRED_XROAR_BASE" >&2
    exit 1
fi

"$ROOT/scripts/test-supercoco-s2b4-build.sh"
git diff --check

RECIPE="$ROOT/recipes/coco3_6309/40d"
make -C "$RECIPE" --no-print-directory .mods/cowin.io .mods/grfdrv

WORK="$(mktemp -d /tmp/supercoco-s2b4-runtime.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
PROBE="$WORK/scgrfblitprobe"
VHD="$WORK/63SDC-S2B4.VHD"
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
  -o "$PROBE" \
  "$ROOT/level1/wildbits/cmds/scgrfblitprobe.asm"

test -s "$PROBE"
os9 ident "$PROBE" | grep -Fqi 'scgrfblitprobe' || {
    echo 'FAIL: runtime probe module identity is not scgrfblitprobe' >&2
    exit 1
}

cp "$BASE_VHD" "$VHD"
python3 "$ROOT/scripts/patch-supercoco-os9boot.py" \
    "$VHD" "$RECIPE/.mods/cowin.io"

CMD_DIR='CMDS'
os9 dir "$VHD,$CMD_DIR" >/dev/null 2>&1 || CMD_DIR='cmds'
os9 dir "$VHD,$CMD_DIR" >/dev/null 2>&1 || {
    echo 'FAIL: no CMDS directory in candidate VHD' >&2
    exit 1
}

os9 copy -r "$RECIPE/.mods/grfdrv" "$VHD,$CMD_DIR/grfdrv"
os9 attr "$VHD,$CMD_DIR/grfdrv" -e -pe -r -pr
os9 copy -r "$PROBE" "$VHD,$CMD_DIR/scgrfblitprobe"
os9 attr "$VHD,$CMD_DIR/scgrfblitprobe" -e -pe -r -pr

os9 copy -l "$VHD,startup" "$STARTUP"
printf '\nscgrfblitprobe\n' >> "$STARTUP"
os9 copy -l -r "$STARTUP" "$VHD,startup"

set +e
"$XROAR" -ui null -ao null -machine coco3 -machine-cpu 6309 -ram 16384 \
  -rompath "$ROMDIR" -romlist sdcdos=SDC-DOS.raw -cart supercocosdc \
  -cart-type cocosdc -no-cart-autorun -machine-cart supercocosdc \
  -load-hd0 "$VHD" -no-disk-write-back \
  -console-capture "$CONSOLE" -screen-capture "$SCREEN" \
  -trap pc=0x006b -trap-range 1 -trap-state "$CRASH" -trap-timeout 0.5 \
  -type $'DOS\r' -timeout "${S2B4_TIMEOUT:-150}" >"$LOG" 2>&1
RC=$?
set -e
printf 'XRoar exit status: %d\n' "$RC"

if [[ -s "$CRASH" ]]; then
    echo 'FAIL: D.Crash trap fired during S2B-4 R1K BLIT proof' >&2
    cat "$CRASH" >&2
    tail -n 200 "$LOG" >&2 || true
    exit 1
fi

FAIL_MARKER='scgrfblitprobe: S2B-4 R1K BLIT mirror FAIL'
required=(
  'S2B4 R1K BLIT0 PASS'
  'S2B4 R1K BLIT1 PASS'
  'S2B4 R1K MIRROR PASS'
  'SuperCoCo S2B-4 R1K BLIT mirror PASS'
)

if grep -Fq "$FAIL_MARKER" "$SCREEN" 2>/dev/null || grep -Fq "$FAIL_MARKER" "$CONSOLE" 2>/dev/null; then
    echo 'FAIL: native S2B-4 probe reported R1K BLIT mirror failure' >&2
    cat "$SCREEN" >&2 || true
    cat "$CONSOLE" >&2 || true
    tail -n 200 "$LOG" >&2 || true
    exit 1
fi

for marker in "${required[@]}"; do
    if ! grep -Fq "$marker" "$SCREEN" 2>/dev/null && ! grep -Fq "$marker" "$CONSOLE" 2>/dev/null; then
        echo "FAIL: missing runtime marker: $marker" >&2
        echo '--- screen ---' >&2
        cat "$SCREEN" >&2 || true
        echo '--- console ---' >&2
        cat "$CONSOLE" >&2 || true
        echo '--- xroar tail ---' >&2
        tail -n 200 "$LOG" >&2 || true
        exit 1
    fi
done

printf 'PASS: SuperCoCo S2B-4 normal BAR mirror -> R1K BLIT runtime proof\n'
printf 'NitrOS-9: %s\n' "$(git rev-parse HEAD)"
printf 'XRoar:    %s\n' "$(git -C "$XROAR_ROOT" rev-parse HEAD)"
printf 'GrfDrv:   %s\n' "$RECIPE/.mods/grfdrv"
printf 'Screen:   %s\n' "$SCREEN"
printf 'Console:  %s\n' "$CONSOLE"
printf 'Log:      %s\n' "$LOG"
