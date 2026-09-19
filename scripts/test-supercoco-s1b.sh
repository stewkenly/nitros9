#!/usr/bin/env bash
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

expected='a8220376d7caf02af1c150766feff4ca77cca231'
actual="$(git rev-parse HEAD)"
[[ "$actual" == "$expected" ]] || {
    echo "FAIL: expected S1B base $expected, found $actual" >&2
    exit 1
}

for tool in lwasm lwlink; do
    command -v "$tool" >/dev/null 2>&1 || { echo "FAIL: $tool not found" >&2; exit 1; }
done

grep -Fq 'SC_READ8' level1/wildbits/libs/scsys/scsys.inc
grep -Fq 'SC_PROBE_R1L' level1/wildbits/libs/scsys/scsys.inc
grep -Fq 'SC_MBO_NEXTGEN' level1/wildbits/libs/scsys/scsys.inc
grep -Fq '../level1/wildbits/libs/scsys/scsys.inc' lib/wildbitsl2.as
grep -Fq 'lbsr      SC_PROBE_R1L' level1/wildbits/cmds/scinfo.asm
! grep -Fq 'portalRead' level1/wildbits/cmds/scinfo.asm

work="$(mktemp -d /tmp/supercoco-s1b.XXXXXX)"
trap 'rm -rf "$work"' EXIT

# Prove the first real client still assembles with the shared source layer.
lwasm \
  --no-warn=ifp1 \
  --6309 \
  --format=os9 \
  --pragma=pcaspcr,nosymbolcase,condundefzero,undefextern,dollarnotlocal,noforwardrefmax \
  --includedir="$ROOT/recipes/wildbits/l2" \
  --includedir="$ROOT/defs" \
  -o "$work/scinfo" \
  "$ROOT/level1/wildbits/cmds/scinfo.asm"
[[ -s "$work/scinfo" ]] || { echo 'FAIL: refactored scinfo produced no module' >&2; exit 1; }

# Prove scsys is also exported through the real Wildbits Level-2 object library.
lwasm \
  --no-warn=ifp1 \
  --6309 \
  --format=obj \
  --pragma=pcaspcr,condundefzero,undefextern,dollarnotlocal,noforwardrefmax,export \
  --includedir="$ROOT/lib" \
  --includedir="$ROOT/defs" \
  -o "$work/wildbitsl2.o" \
  "$ROOT/lib/wildbitsl2.as"
[[ -s "$work/wildbitsl2.o" ]] || { echo 'FAIL: wildbitsl2 object produced no output' >&2; exit 1; }

cat > "$work/scsysprobe.as" <<'PROBE'
                    section   _constant
Level               equ       2
                    use       os9.d
                    use       supercoco.d
                    endsect

                    section   bss
scratch             rmb       4
                    endsect

                    section   code
__start             ldx       #SC.SysMagic0
                    lbsr      SC_READ8
                    bcs       bad
                    lbsr      SC_PROBE_R1L
                    bcs       bad
                    lda       #SC.IRQImplemented
                    lbsr      SC_IRQ_MASK_SET
                    lbsr      SC_IRQ_GET
                    lbsr      SC_IRQ_ACK
                    ldb       #0
                    lbsr      SC_MBO_STATUS
                    leau      scratch,u
                    lbsr      SC_MBO_NEXTGEN
                    clrb
bad                 os9       F$Exit
                    endsect
PROBE

lwasm \
  --no-warn=ifp1 \
  --6309 \
  --format=obj \
  --pragma=pcaspcr,condundefzero,undefextern,dollarnotlocal,noforwardrefmax,export \
  --includedir="$ROOT/defs" \
  -o "$work/scsysprobe.o" \
  "$work/scsysprobe.as"

lwlink --format=os9 "$work/scsysprobe.o" "$work/wildbitsl2.o" -o"$work/scsysprobe"
[[ -s "$work/scsysprobe" ]] || { echo 'FAIL: scsys link probe produced no module' >&2; exit 1; }

if command -v os9 >/dev/null 2>&1; then
    os9 ident "$work/scinfo" | grep -Fqi 'scinfo' || {
        echo 'FAIL: assembled module identity is not scinfo' >&2
        exit 1
    }
fi

git diff --check

echo 'PASS: SuperCoCo NitrOS-9 S1B shared scsys layer'
