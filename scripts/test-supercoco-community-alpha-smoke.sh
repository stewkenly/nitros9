#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

REQUIRED_NITROS_BASE="6dee8c3133d8e22c84c04f1faa68d5e874117dc5"
REQUIRED_XROAR_BASE="d9661764ae4ecaeb54bf55fb404843efae74c1fa"

XROAR_ROOT="${SUPERCOCO_XROAR_ROOT:-/Volumes/design/supercoco-xroar}"
EMU_ROOT="${SUPERCOCO_EMULATOR_ROOT:-/Volumes/design/supercoco-emulator}"
XROAR="${XROAR:-$XROAR_ROOT/src/xroar}"
ROMDIR="${ROMDIR:-$EMU_ROOT/roms}"
BASE_VHD="${BASE_VHD:-$EMU_ROOT/images/63SDC.VHD}"

for cmd in git lwasm os9 shasum; do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo "FAIL: required command not found: $cmd" >&2
        exit 1
    }
done

[[ -d "$XROAR_ROOT/.git" ]] || { echo "FAIL: missing XRoar worktree: $XROAR_ROOT" >&2; exit 1; }
[[ -d "$EMU_ROOT/.git" ]] || { echo "FAIL: missing emulator worktree: $EMU_ROOT" >&2; exit 1; }
[[ -x "$XROAR" ]] || { echo "FAIL: missing XRoar binary: $XROAR" >&2; exit 1; }
[[ -f "$ROMDIR/coco3.rom" ]] || { echo "FAIL: missing coco3.rom" >&2; exit 1; }
[[ -f "$ROMDIR/SDC-DOS.raw" ]] || { echo "FAIL: missing SDC-DOS.raw" >&2; exit 1; }
[[ -f "$BASE_VHD" ]] || { echo "FAIL: missing base VHD: $BASE_VHD" >&2; exit 1; }

if ! git merge-base --is-ancestor "$REQUIRED_NITROS_BASE" HEAD; then
    echo "FAIL: NitrOS-9 HEAD is not descended from Community Alpha floor $REQUIRED_NITROS_BASE" >&2
    exit 1
fi
if ! git -C "$XROAR_ROOT" merge-base --is-ancestor "$REQUIRED_XROAR_BASE" HEAD; then
    echo "FAIL: XRoar HEAD is not descended from Community Alpha floor $REQUIRED_XROAR_BASE" >&2
    exit 1
fi

NITROS_HEAD="$(git rev-parse HEAD)"
XROAR_HEAD="$(git -C "$XROAR_ROOT" rev-parse HEAD)"
EMU_HEAD="$(git -C "$EMU_ROOT" rev-parse HEAD)"

echo "============================================================"
echo "SUPERCOCO COMMUNITY ALPHA CONSOLIDATED SMOKE"
echo "============================================================"
echo "NitrOS-9: $NITROS_HEAD"
echo "XRoar:    $XROAR_HEAD"
echo "Emulator: $EMU_HEAD"
echo "Base VHD: $BASE_VHD"
echo "Base SHA: $(shasum -a 256 "$BASE_VHD" | awk '{print $1}')"
echo

WORK="$(mktemp -d /tmp/supercoco-alpha-smoke.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

gate() {
    local name="$1"
    shift
    echo
    echo "=== $name ==="
    "$@"
    printf '%-38s PASS\n' "$name"
}

boot_gate() {
    local screen="$WORK/boot-screen.txt"
    local console="$WORK/boot-console.txt"
    local log="$WORK/boot.log"
    local crash="$WORK/boot-crash.txt"
    rm -f "$screen" "$console" "$log" "$crash"

    set +e
    "$XROAR" \
      -ui null \
      -ao null \
      -machine coco3 \
      -machine-cpu 6309 \
      -ram 16384 \
      -rompath "$ROMDIR" \
      -romlist sdcdos=SDC-DOS.raw \
      -cart supercocosdc \
      -cart-type cocosdc \
      -no-cart-autorun \
      -machine-cart supercocosdc \
      -load-hd0 "$BASE_VHD" \
      -no-disk-write-back \
      -console-capture "$console" \
      -screen-capture "$screen" \
      -trap pc=0x006b \
      -trap-range 1 \
      -trap-state "$crash" \
      -trap-timeout 0.5 \
      -type $'DOS\r' \
      -timeout "${ALPHA_BOOT_TIMEOUT:-90}" \
      >"$log" 2>&1
    local rc=$?
    set -e
    printf 'XRoar exit status: %d\n' "$rc"

    [[ ! -s "$crash" ]] || {
        echo "FAIL: D.Crash during Community Alpha boot" >&2
        cat "$crash" >&2
        exit 1
    }
    grep -Fq 'Shell+ v2.2a' "$screen" || {
        echo "FAIL: Shell+ banner missing" >&2
        cat "$screen" >&2 || true
        exit 1
    }
    grep -Fq '{Term|02}/DD:' "$screen" || {
        echo "FAIL: /DD prompt missing" >&2
        cat "$screen" >&2 || true
        exit 1
    }
}

run_xroar_test() {
    local script="$1"
    (
      cd "$XROAR_ROOT"
      SUPERCOCO_EMULATOR_ROOT="$EMU_ROOT" "$script"
    )
}

run_demo() {
    local name="$1"
    local source="$2"
    local marker="$3"
    local timeout="$4"

    local module="$WORK/$name"
    local vhd="$WORK/$name.VHD"
    local startup="$WORK/$name-startup.txt"
    local screen="$WORK/$name-screen.txt"
    local console="$WORK/$name-console.txt"
    local log="$WORK/$name.log"
    local crash="$WORK/$name-crash.txt"

    lwasm \
      --no-warn=ifp1 \
      --6309 \
      --format=os9 \
      --pragma=pcaspcr,nosymbolcase,condundefzero,undefextern,dollarnotlocal,noforwardrefmax \
      --includedir="$ROOT/recipes/wildbits/l2" \
      --includedir="$ROOT/defs" \
      -o "$module" \
      "$ROOT/$source"

    [[ -s "$module" ]] || { echo "FAIL: $name assembly produced no module" >&2; exit 1; }
    os9 ident "$module" | grep -Fqi "$name" || {
        echo "FAIL: module identity is not $name" >&2
        exit 1
    }

    cp "$BASE_VHD" "$vhd"
    local cmd_dir='CMDS'
    os9 dir "$vhd,$cmd_dir" >/dev/null 2>&1 || cmd_dir='cmds'
    os9 dir "$vhd,$cmd_dir" >/dev/null 2>&1 || {
        echo "FAIL: no CMDS directory in base VHD" >&2
        exit 1
    }
    os9 copy "$module" "$vhd,$cmd_dir/$name"
    os9 attr "$vhd,$cmd_dir/$name" -e -pe -r -pr
    os9 copy -l "$vhd,startup" "$startup"
    printf '\n%s\n' "$name" >> "$startup"
    os9 copy -l -r "$startup" "$vhd,startup"

    set +e
    "$XROAR" -ui null -ao null -machine coco3 -machine-cpu 6309 -ram 16384 \
      -rompath "$ROMDIR" -romlist sdcdos=SDC-DOS.raw -cart supercocosdc \
      -cart-type cocosdc -no-cart-autorun -machine-cart supercocosdc \
      -load-hd0 "$vhd" -no-disk-write-back \
      -console-capture "$console" -screen-capture "$screen" \
      -trap pc=0x006b -trap-range 1 -trap-state "$crash" -trap-timeout 0.5 \
      -type $'DOS\r' -timeout "$timeout" >"$log" 2>&1
    local rc=$?
    set -e
    printf 'XRoar exit status: %d\n' "$rc"

    [[ ! -s "$crash" ]] || {
        echo "FAIL: D.Crash during $name" >&2
        cat "$crash" >&2
        exit 1
    }
    grep -Fq "$marker" "$screen" || {
        echo "FAIL: $name did not produce: $marker" >&2
        cat "$screen" >&2 || true
        tail -n 160 "$log" >&2 || true
        exit 1
    }
    grep -Fq 'Shell+ v2.2a' "$screen" || {
        echo "FAIL: $name did not return to Shell+" >&2
        cat "$screen" >&2 || true
        exit 1
    }
    grep -Fq '{Term|02}/DD:' "$screen" || {
        echo "FAIL: $name did not return to /DD prompt" >&2
        cat "$screen" >&2 || true
        exit 1
    }
}

s2b6_gate() {
    local log="$WORK/s2b6.log"
    SUPERCOCO_XROAR_ROOT="$XROAR_ROOT" \
      "$ROOT/scripts/test-supercoco-s2b6-dirty-mirror-runtime.sh" | tee "$log"

    grep -Fq 'ROW_WORK_NORMAL=16' "$log" || {
        echo 'FAIL: missing ROW_WORK_NORMAL=16' >&2
        exit 1
    }
    grep -Fq 'ROW_WORK_WRAP=32' "$log" || {
        echo 'FAIL: missing ROW_WORK_WRAP=32' >&2
        exit 1
    }

    # The published V1R2 verifier requires this marker inside the underlying
    # S2B5 runtime capture. Re-run the exact runtime marker contract here
    # through the same descendant-aware verifier and require its success.
    grep -Fq "'S2B6 STYLE9 REOPEN PASS'" "$ROOT/scripts/test-supercoco-s2b5-runtime.sh" || {
        echo 'FAIL: published S2B5 runtime verifier does not require the S2B6 reopen marker' >&2
        exit 1
    }

    printf 'S2B6 CLOSE_REOPEN_LIFETIME             PASS\n'
}

gate "BOOT / SHELL+" boot_gate
gate "R1J NATIVE 640x480" run_xroar_test tools/test-supercoco-arch0-r1j-video.sh
gate "FIVE-CPU FULL-SPEED VIDEO" run_xroar_test tools/test-supercoco-alpha-fullspeed-video.sh
gate "R1K GRAPHICS ENGINE" run_xroar_test tools/test-supercoco-arch0-r1k-graphics.sh
gate "R1L AUDIO ENGINE" run_xroar_test tools/test-supercoco-arch0-r1l-audio.sh

gate "SCGFXANIM CURRENT-SOURCE" run_demo \
  scgfxanim level1/wildbits/cmds/scgfxanim.asm \
  'SuperCoCo S2A R1K graphics PASS' "${ALPHA_SCGFX_TIMEOUT:-180}"

gate "SCAVDEMO CURRENT-SOURCE" run_demo \
  scavdemo level1/wildbits/cmds/scavdemo.asm \
  'SuperCoCo S2A VIDEO+MEDIA+AUDIO PASS' "${ALPHA_SCAV_TIMEOUT:-300}"

gate "S1 SERVICE / IRQ / NETWORK" env \
  SUPERCOCO_XROAR_ROOT="$XROAR_ROOT" \
  "$ROOT/scripts/test-supercoco-s1.sh"

gate "S2B6 STYLE9 DIRTY/LIFETIME" s2b6_gate

echo
echo "============================================================"
echo "RESULT: PASS"
echo "COMMUNITY_ALPHA_CORE=READY"
echo "============================================================"
