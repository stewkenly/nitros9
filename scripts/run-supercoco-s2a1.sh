#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[[ -n "$ROOT" && -f "$ROOT/rules.mak" ]] || {
    echo 'ERROR: run from the NitrOS-9 repository' >&2
    exit 2
}
cd "$ROOT"

XROAR_ROOT="${SUPERCOCO_XROAR_ROOT:-/Volumes/design/supercoco-xroar}"
EMULATOR_ROOT="${SUPERCOCO_EMULATOR_ROOT:-/Volumes/design/supercoco-emulator}"
XROAR="${XROAR:-$XROAR_ROOT/src/xroar}"
ROMDIR="${ROMDIR:-$EMULATOR_ROOT/roms}"
BASE_VHD="${BASE_VHD:-$EMULATOR_ROOT/images/63SDC.VHD}"

case "$(uname -s 2>/dev/null || true)" in
    Darwin)
        DEFAULT_RUNTIME="$HOME/Library/Application Support/SuperCoCo/S2A1"
        ;;
    *)
        DEFAULT_RUNTIME="$HOME/.local/share/supercoco/S2A1"
        ;;
esac
RUNTIME_DIR="${SUPERCOCO_RUNTIME_DIR:-$DEFAULT_RUNTIME}"
VHD="$RUNTIME_DIR/63SDC-S2A1.VHD"
MODULE="$RUNTIME_DIR/scdemo"
STARTUP="$RUNTIME_DIR/startup.txt"
RESET=0
PRINT_ONLY=0

usage() {
    cat <<'USAGE'
usage: scripts/run-supercoco-s2a1.sh [--reset-image] [--print-command] [--] [extra XRoar args]

Builds the current NitrOS-9 scdemo command, installs it into a private working
copy of 63SDC.VHD, arranges for scdemo to run during startup, and launches the
stable SuperCoCo R1L XRoar interactively.

Options:
  --reset-image     replace the private working VHD from BASE_VHD first
  --print-command   prepare everything, then print the XRoar command only

Environment overrides:
  SUPERCOCO_XROAR_ROOT    default /Volumes/design/supercoco-xroar
  SUPERCOCO_EMULATOR_ROOT default /Volumes/design/supercoco-emulator
  XROAR                    XRoar executable
  ROMDIR                   directory containing coco3.rom and SDC-DOS.raw
  BASE_VHD                 pristine 63SDC.VHD used to seed the working image
  SUPERCOCO_RUNTIME_DIR    private runtime directory

The base VHD is never modified. At the color bars, press any key to return to
NitrOS-9. The private VHD is retained so you can keep using the environment.
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --reset-image) RESET=1; shift ;;
        --print-command) PRINT_ONLY=1; shift ;;
        -h|--help) usage; exit 0 ;;
        --) shift; break ;;
        *) break ;;
    esac
done

for tool in lwasm os9; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "ERROR: required command not found: $tool" >&2
        exit 2
    }
done
[[ -x "$XROAR" ]] || { echo "ERROR: XRoar binary not found: $XROAR" >&2; exit 2; }
expected_xroar='cdebeb172b8147b615fc8e96c3f0b7b0fdcaaf06'
if [[ -d "$XROAR_ROOT/.git" ]]; then
    actual_xroar="$(git -C "$XROAR_ROOT" rev-parse HEAD)"
    [[ "$actual_xroar" == "$expected_xroar" ]] || {
        echo "ERROR: S2A-1 requires stable R1L XRoar commit $expected_xroar" >&2
        echo "       current $XROAR_ROOT HEAD is $actual_xroar" >&2
        echo '       switch to release/community-alpha-dev-r1l and rebuild XRoar.' >&2
        exit 2
    }
fi
[[ -f "$ROMDIR/coco3.rom" ]] || { echo "ERROR: missing $ROMDIR/coco3.rom" >&2; exit 2; }
[[ -f "$ROMDIR/SDC-DOS.raw" ]] || { echo "ERROR: missing $ROMDIR/SDC-DOS.raw" >&2; exit 2; }
[[ -f "$BASE_VHD" ]] || { echo "ERROR: base VHD not found: $BASE_VHD" >&2; exit 2; }

mkdir -p "$RUNTIME_DIR"

lwasm \
  --no-warn=ifp1 \
  --6309 \
  --format=os9 \
  --pragma=pcaspcr,nosymbolcase,condundefzero,undefextern,dollarnotlocal,noforwardrefmax \
  --includedir="$ROOT/recipes/wildbits/l2" \
  --includedir="$ROOT/defs" \
  -o "$MODULE" \
  "$ROOT/level1/wildbits/cmds/scdemo.asm"
[[ -s "$MODULE" ]] || { echo 'ERROR: scdemo assembly produced no module' >&2; exit 2; }

if [[ $RESET -eq 1 || ! -f "$VHD" ]]; then
    cp "$BASE_VHD" "$VHD"
    echo "Seeded private working image: $VHD"
fi

CMD_DIR='CMDS'
os9 dir "$VHD,$CMD_DIR" >/dev/null 2>&1 || CMD_DIR='cmds'
os9 dir "$VHD,$CMD_DIR" >/dev/null 2>&1 || {
    echo "ERROR: no CMDS directory found in $VHD" >&2
    exit 2
}

# Replace only the private working image's copy of scdemo. ToolShed's -r
# rewrite path is already used by the retained regression for startup updates.
os9 copy -r "$MODULE" "$VHD,$CMD_DIR/scdemo"
os9 attr "$VHD,$CMD_DIR/scdemo" -e -pe -r -pr

# Add the demo to startup once. ToolShed -l translates OS-9 CR text.
os9 copy -l "$VHD,startup" "$STARTUP"
if ! grep -Eq '^[[:space:]]*scdemo[[:space:]]*$' "$STARTUP"; then
    printf '\nscdemo\n' >> "$STARTUP"
    os9 copy -l -r "$STARTUP" "$VHD,startup"
fi

args=(
    -machine coco3
    -machine-cpu 6309
    -ram 16384
    -rompath "$ROMDIR"
    -romlist sdcdos=SDC-DOS.raw
    -cart supercocosdc
    -cart-type cocosdc
    -no-cart-autorun
    -machine-cart supercocosdc
    -load-hd0 "$VHD"
    -type $'DOS\r'
)

if [[ $PRINT_ONLY -eq 1 ]]; then
    printf '%q' "$XROAR"
    for a in "${args[@]}" "$@"; do printf ' %q' "$a"; done
    printf '\n'
    exit 0
fi

echo
printf 'Launching SuperCoCo R1L with S2A-1 NitrOS-9 image...\n'
printf '  XRoar: %s\n' "$XROAR"
printf '  VHD:   %s\n' "$VHD"
printf '  Demo:  %s/scdemo\n' "$CMD_DIR"
printf 'Press any key on the 16-color screen to return to NitrOS-9.\n\n'

exec "$XROAR" "${args[@]}" "$@"
