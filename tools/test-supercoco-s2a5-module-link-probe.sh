#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

EXPECTED_HEAD="00be5567b7747c3824b2e810aac8aa3b8f889a69"
ACTUAL_HEAD="$(git rev-parse HEAD)"
[[ "$ACTUAL_HEAD" == "$EXPECTED_HEAD" ]] || {
    echo "FAIL: expected FIX13 base $EXPECTED_HEAD, found $ACTUAL_HEAD" >&2
    exit 1
}

SUPERCOCO_EMULATOR_ROOT="${SUPERCOCO_EMULATOR_ROOT:-/Volumes/design/supercoco-emulator}"
XROAR="${XROAR:-$SUPERCOCO_EMULATOR_ROOT/upstream/src/xroar}"
XROAR_CWD="${XROAR_CWD:-$SUPERCOCO_EMULATOR_ROOT/upstream}"
ROMDIR="${ROMDIR:-$SUPERCOCO_EMULATOR_ROOT/roms}"
BASE_VHD="${BASE_VHD:-$SUPERCOCO_EMULATOR_ROOT/images/63SDC.VHD}"
SCNGON_SOURCE="${SCNGON_SOURCE:-$SUPERCOCO_EMULATOR_ROOT/nitros9/scngon.asm}"
CONTROL_TIMEOUT="${S2A5_LINK_CONTROL_TIMEOUT:-90}"
TEST_TIMEOUT="${S2A5_LINK_TIMEOUT:-180}"
EXPECTED_BASE_SHA="5619e77b2b227d2cc4bffe8184634e4ff3f4e4a073b13d8e03cac23505235ab9"
EXPECTED_STARTUP_SHA="67a2435223c04ac231b5e664f991a3277c65faee1b2aa56a79dc8aa6a3f1c1ff"
EXPECTED_STARTUP_SIZE=497

for cmd in lwasm os9 python3 shasum cmp grep; do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo "FAIL: required command not found: $cmd" >&2
        exit 1
    }
done
[[ -x "$XROAR" ]] || { echo "FAIL: missing architecture XRoar binary: $XROAR" >&2; exit 1; }
[[ -d "$XROAR_CWD" ]] || { echo "FAIL: missing architecture XRoar cwd: $XROAR_CWD" >&2; exit 1; }
[[ -f "$ROMDIR/coco3.rom" ]] || { echo "FAIL: missing coco3.rom" >&2; exit 1; }
[[ -f "$ROMDIR/SDC-DOS.raw" ]] || { echo "FAIL: missing SDC-DOS.raw" >&2; exit 1; }
[[ -f "$BASE_VHD" ]] || { echo "FAIL: missing canonical VHD: $BASE_VHD" >&2; exit 1; }
[[ -f "$SCNGON_SOURCE" ]] || { echo "FAIL: missing architecture scngon source: $SCNGON_SOURCE" >&2; exit 1; }

BASE_SHA="$(shasum -a 256 "$BASE_VHD" | awk '{print $1}')"
[[ "$BASE_SHA" == "$EXPECTED_BASE_SHA" ]] || {
    echo "FAIL: canonical VHD SHA-256 mismatch: $BASE_SHA" >&2
    exit 1
}

WORK="$(mktemp -d /tmp/supercoco-s2a5-link.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT
PROBE="$WORK/scnetlink"
SCNET="$WORK/scnet"
NET0="$WORK/net0"
SCNGON="$WORK/scngon"
PAIR="$WORK/n3realpair-current"
ORIGINAL_BOOT="$WORK/OS9Boot.original"
HYBRID_BOOT="$WORK/OS9Boot.hybrid"
VHD="$WORK/63SDC-S2A5-LINK.VHD"
CONTROL_VHD="$WORK/63SDC-CONTROL.VHD"
CANONICAL_STARTUP="$WORK/startup.canonical"
STARTUP="$WORK/startup"
STARTUP_VERIFY="$WORK/startup.verify"
SCREEN="$WORK/screen.txt"
CONSOLE="$WORK/console.txt"
LOG="$WORK/xroar.log"
CRASH="$WORK/crash.txt"
CONTROL_SCREEN="$WORK/control-screen.txt"
CONTROL_CONSOLE="$WORK/control-console.txt"
CONTROL_LOG="$WORK/control-xroar.log"
CONTROL_CRASH="$WORK/control-crash.txt"

run_xroar() {
    local image="$1" screen="$2" console="$3" log="$4" crash="$5" timeout="$6"
    rm -f "$screen" "$console" "$log" "$crash"
    pushd "$XROAR_CWD" >/dev/null
    SUPERCOCO_NET_BACKEND=host \
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
        -load-hd0 "$image" \
        -console-capture "$console" \
        -screen-capture "$screen" \
        -trap pc=0x006b \
        -trap-range 1 \
        -trap-state "$crash" \
        -trap-timeout 0.5 \
        -type $'DOS\r' \
        -timeout "$timeout" \
        >"$log" 2>&1
    local rc=$?
    popd >/dev/null
    return "$rc"
}

printf '%s\n' '=== S2A5 FIX13R4 CANONICAL BOOT CONTROL ==='
cp "$BASE_VHD" "$CONTROL_VHD"
set +e
run_xroar "$CONTROL_VHD" "$CONTROL_SCREEN" "$CONTROL_CONSOLE" "$CONTROL_LOG" "$CONTROL_CRASH" "$CONTROL_TIMEOUT"
CONTROL_RC=$?
set -e
printf 'Control XRoar exit status: %d\n' "$CONTROL_RC"
if [[ -s "$CONTROL_CRASH" ]]; then
    echo 'FAIL: canonical control hit D.Crash' >&2
    cat "$CONTROL_CRASH" >&2
    tail -n 160 "$CONTROL_LOG" >&2 || true
    exit 1
fi
if [[ ! -s "$CONTROL_SCREEN" ]]; then
    echo 'FAIL: canonical control produced no NitrOS-9 screen capture' >&2
    echo '--- control console ---' >&2
    cat "$CONTROL_CONSOLE" >&2 || true
    echo '--- control xroar log ---' >&2
    tail -n 200 "$CONTROL_LOG" >&2 || true
    exit 1
fi
if ! grep -Eq 'Shell\+|To run the GUI|NitrOS-9' "$CONTROL_SCREEN"; then
    echo 'FAIL: canonical control screen lacks expected NitrOS-9 witness' >&2
    cat "$CONTROL_SCREEN" >&2
    exit 1
fi
echo 'PASS: canonical VHD boots under architecture XRoar'

DEFDIR="$ROOT/level2/coco3_6309"
COMMON_DEFS="$ROOT/defs"
[[ -f "$DEFDIR/defsfile" ]] || { echo "FAIL: missing CoCo3/6309 defsfile: $DEFDIR/defsfile" >&2; exit 1; }

ASSEMBLER_FLAGS=(
    --no-warn=ifp1
    --6309
    --format=os9
    --pragma=pcaspcr,nosymbolcase,condundefzero,undefextern,dollarnotlocal,noforwardrefmax
    "--includedir=$DEFDIR"
    "--includedir=$COMMON_DEFS"
    -DH6309=1
    -DNOS9VER=0
    -DNOS9MAJ=0
    -DNOS9MIN=0
)

printf '%s\n' '=== S2A5 FIX13R4 BUILD TYPED-LINK PROBE ==='
lwasm "${ASSEMBLER_FLAGS[@]}" --output="$PROBE" "$ROOT/level1/wildbits/cmds/scnetlink.asm"
[[ -s "$PROBE" ]] || { echo 'FAIL: scnetlink assembly produced no module' >&2; exit 1; }
os9 ident "$PROBE" | grep -Fqi 'Header for : scnetlink' || { echo 'FAIL: scnetlink identity mismatch' >&2; exit 1; }

printf '%s\n' '=== S2A5 FIX13R4 BUILD CURRENT NATIVE-NET MODULES WITH PROVEN N3B DEFINITIONS ==='
lwasm "${ASSEMBLER_FLAGS[@]}" --output="$NET0" "$ROOT/level1/wildbits/modules/net0.asm"
lwasm "${ASSEMBLER_FLAGS[@]}" --output="$SCNET" "$ROOT/level1/wildbits/modules/scnet.asm"
lwasm "${ASSEMBLER_FLAGS[@]}" --output="$SCNGON" "$SCNGON_SOURCE"
for spec in "$NET0:net0" "$SCNET:scnet" "$SCNGON:scngon"; do
    module="${spec%%:*}"; name="${spec##*:}"
    [[ -s "$module" ]] || { echo "FAIL: assembled module missing: $name" >&2; exit 1; }
    os9 ident "$module" | grep -Fqi "Header for : $name" || { echo "FAIL: assembled module identity mismatch: $name" >&2; exit 1; }
    echo "PASS: freshly assembled module identified: $name"
done
cat "$NET0" "$SCNET" > "$PAIR"
echo "net0 bytes:  $(wc -c < "$NET0" | tr -d ' ')"
echo "scnet bytes: $(wc -c < "$SCNET" | tr -d ' ')"
echo "pair bytes:  $(wc -c < "$PAIR" | tr -d ' ')"
echo "pair order:  net0 -> scnet"

printf '%s\n' '=== S2A5 FIX13R4 PRESERVE CANONICAL BOOT + APPEND N3B-ORDERED PAIR + SELECTOR ==='
os9 copy "$BASE_VHD,OS9Boot" "$ORIGINAL_BOOT"
[[ -s "$ORIGINAL_BOOT" ]] || { echo 'FAIL: canonical OS9Boot extraction produced no data' >&2; exit 1; }
cat "$ORIGINAL_BOOT" "$PAIR" "$SCNGON" > "$HYBRID_BOOT"
echo "canonical OS9Boot bytes: $(wc -c < "$ORIGINAL_BOOT" | tr -d ' ')"
echo "scngon bytes:            $(wc -c < "$SCNGON" | tr -d ' ')"
echo "hybrid OS9Boot bytes:    $(wc -c < "$HYBRID_BOOT" | tr -d ' ')"

printf '%s\n' '=== S2A5 FIX13R4 BUILD DISPOSABLE VHD USING PROVEN FIXED RELOCATION ==='
python3 - "$BASE_VHD" "$ORIGINAL_BOOT" "$HYBRID_BOOT" "$VHD" <<'PYBOOT'
from pathlib import Path
import sys

SECTOR=256
EXPECTED_OLD_START=0x00BCCF
EXPECTED_OLD_COUNT=136
EXPECTED_BOOT_FD=0x0091E4
NEW_START=0x00BE2C
source_path, original_path, hybrid_path, output_path = map(Path, sys.argv[1:5])
data=bytearray(source_path.read_bytes())
original=original_path.read_bytes(); hybrid=hybrid_path.read_bytes()

def u16(b): return int.from_bytes(b,'big')
def u24(b): return int.from_bytes(b,'big')
def parse_fd(image,lsn):
    off=lsn*SECTOR; fd=image[off:off+SECTOR]
    if len(fd)!=SECTOR: raise SystemExit('FAIL: file descriptor outside image')
    size=int.from_bytes(fd[9:13],'big'); segs=[]
    for p in range(16,SECTOR-4,5):
        start=u24(fd[p:p+3]); count=u16(fd[p+3:p+5])
        if start==0 or count==0: break
        segs.append((start,count))
    return size,segs

def decode_name(raw):
    out=[]
    for byte in raw:
        if byte in (0,0xff): break
        out.append(chr(byte & 0x7f))
        if byte & 0x80: break
    return ''.join(out)

total=u24(data[0:3]); bitmap_bytes=u16(data[4:6]); spc=u16(data[6:8]); root_fd=u24(data[8:11])
if total*SECTOR!=len(data): raise SystemExit('FAIL: filesystem size mismatch')
if spc!=1: raise SystemExit('FAIL: expected one sector per allocation cluster')
if u24(data[21:24])!=EXPECTED_OLD_START: raise SystemExit('FAIL: unexpected canonical DD.BT')
if u16(data[24:26])!=len(original): raise SystemExit('FAIL: canonical DD.BSZ mismatch')
root_size,root_segs=parse_fd(data,root_fd); root=bytearray()
for start,count in root_segs: root.extend(data[start*SECTOR:(start+count)*SECTOR])
root=root[:root_size]; boot_fd=None
for off in range(0,len(root),32):
    ent=root[off:off+32]
    if len(ent)<32: break
    if decode_name(ent[:29])=='OS9Boot': boot_fd=u24(ent[29:32]); break
if boot_fd!=EXPECTED_BOOT_FD: raise SystemExit(f'FAIL: unexpected OS9Boot FD: {boot_fd!r}')
old_size,old_segs=parse_fd(data,boot_fd)
if old_size!=len(original): raise SystemExit('FAIL: OS9Boot size mismatch')
if old_segs!=[(EXPECTED_OLD_START,EXPECTED_OLD_COUNT)]: raise SystemExit(f'FAIL: unexpected canonical extent: {old_segs}')
old_begin=EXPECTED_OLD_START*SECTOR
if bytes(data[old_begin:old_begin+old_size])!=original: raise SystemExit('FAIL: canonical OS9Boot extent mismatch')
need=(len(hybrid)+SECTOR-1)//SECTOR
if NEW_START+need>total: raise SystemExit('FAIL: new boot extent outside filesystem')

def allocated(lsn):
    cluster=lsn; bi=cluster//8
    if bi>=bitmap_bytes: raise SystemExit('FAIL: allocation lookup overflow')
    return bool(data[SECTOR+bi] & (0x80>>(cluster&7)))
def set_alloc(lsn,state):
    cluster=lsn; bi=cluster//8; mask=0x80>>(cluster&7); pos=SECTOR+bi
    if state: data[pos]|=mask
    else: data[pos]&=(~mask)&0xff
old_range=range(EXPECTED_OLD_START,EXPECTED_OLD_START+EXPECTED_OLD_COUNT)
new_range=range(NEW_START,NEW_START+need)
if not all(allocated(lsn) for lsn in old_range): raise SystemExit('FAIL: canonical boot extent not fully allocated')
if any(allocated(lsn) for lsn in new_range): raise SystemExit('FAIL: fixed N3B boot target is not free')
for lsn in old_range: set_alloc(lsn,False)
for lsn in new_range: set_alloc(lsn,True)
cap=need*SECTOR; begin=NEW_START*SECTOR
data[begin:begin+cap]=hybrid+bytes(cap-len(hybrid))
fd_off=boot_fd*SECTOR
data[fd_off+9:fd_off+13]=len(hybrid).to_bytes(4,'big')
data[fd_off+16:fd_off+SECTOR]=bytes(SECTOR-16)
data[fd_off+16:fd_off+19]=NEW_START.to_bytes(3,'big')
data[fd_off+19:fd_off+21]=need.to_bytes(2,'big')
data[21:24]=NEW_START.to_bytes(3,'big')
data[24:26]=len(hybrid).to_bytes(2,'big')
size2,segs2=parse_fd(data,boot_fd)
if size2!=len(hybrid) or segs2!=[(NEW_START,need)]: raise SystemExit('FAIL: relocated OS9Boot postcheck failed')
if any(allocated(lsn) for lsn in old_range): raise SystemExit('FAIL: old boot allocation still committed')
if not all(allocated(lsn) for lsn in new_range): raise SystemExit('FAIL: new boot allocation not committed')
output_path.write_bytes(data)
print(f'OS9Boot old extent: ${EXPECTED_OLD_START:06X}+{EXPECTED_OLD_COUNT}')
print(f'OS9Boot new extent: ${NEW_START:06X}+{need}')
print(f'OS9Boot bytes:      {len(hybrid)}')
PYBOOT

CMD_DIR='CMDS'
os9 dir "$VHD,$CMD_DIR" >/dev/null 2>&1 || CMD_DIR='cmds'
os9 dir "$VHD,$CMD_DIR" >/dev/null 2>&1 || { echo 'FAIL: no CMDS directory in VHD' >&2; exit 1; }
os9 del "$VHD,$CMD_DIR/scnetlink" >/dev/null 2>&1 || true
os9 copy "$PROBE" "$VHD,$CMD_DIR/scnetlink"
os9 attr "$VHD,$CMD_DIR/scnetlink" -e -pe

printf '%s\n' '=== S2A5 FIX13R4 PRESERVE CANONICAL STARTUP PREFIX ==='
os9 copy "$BASE_VHD,startup" "$CANONICAL_STARTUP"
CANONICAL_SIZE="$(wc -c < "$CANONICAL_STARTUP" | tr -d ' ')"
CANONICAL_SHA="$(shasum -a 256 "$CANONICAL_STARTUP" | awk '{print $1}')"
[[ "$CANONICAL_SIZE" == "$EXPECTED_STARTUP_SIZE" ]] || { echo "FAIL: canonical startup size mismatch: $CANONICAL_SIZE" >&2; exit 1; }
[[ "$CANONICAL_SHA" == "$EXPECTED_STARTUP_SHA" ]] || { echo "FAIL: canonical startup SHA mismatch: $CANONICAL_SHA" >&2; exit 1; }
python3 - "$CANONICAL_STARTUP" "$STARTUP" <<'PYSTART'
from pathlib import Path
import sys
src,dst=map(Path,sys.argv[1:3]); raw=src.read_bytes()
if not raw.endswith(b'\r'): raise SystemExit('FAIL: canonical startup does not end in CR')
lines=[
    'echo *SUPERCOCO S2A5 LINK SESSION BEGIN*',
    'scngon',
    'echo *S2A5 SCNGON OK*',
    'scnetlink',
    'echo *S2A5-FIX13-PROBE-RETURNED*',
    'echo *S2A5-FIX13-SHELL-RETURN*',
]
dst.write_bytes(raw + ('\r'.join(lines)+'\r').encode('ascii'))
print(f'canonical startup bytes: {len(raw)}')
print(f'combined startup bytes:  {dst.stat().st_size}')
PYSTART
os9 del "$VHD,startup" >/dev/null 2>&1 || true
os9 copy "$STARTUP" "$VHD,startup"
os9 copy "$VHD,startup" "$STARTUP_VERIFY"
cmp "$STARTUP" "$STARTUP_VERIFY"
echo 'combined startup comparison: EXACT'

printf '%s\n' '=== S2A5 FIX13R4 RUN DIAGNOSTIC IMAGE UNDER ARCHITECTURE XROAR ==='
set +e
run_xroar "$VHD" "$SCREEN" "$CONSOLE" "$LOG" "$CRASH" "$TEST_TIMEOUT"
RC=$?
set -e
printf 'Diagnostic XRoar exit status: %d\n' "$RC"
if [[ -s "$CRASH" ]]; then
    echo 'FAIL: D.Crash trap fired during FIX13R4 diagnostic' >&2
    cat "$CRASH" >&2
    tail -n 160 "$LOG" >&2 || true
    exit 1
fi
if [[ ! -s "$SCREEN" ]]; then
    echo 'FAIL: diagnostic image produced no NitrOS-9 screen capture' >&2
    echo '--- diagnostic console ---' >&2
    cat "$CONSOLE" >&2 || true
    echo '--- diagnostic xroar log ---' >&2
    tail -n 220 "$LOG" >&2 || true
    exit 1
fi

printf '%s\n' '=== S2A5 FIX13R4 GUEST SCREEN ==='
cat "$SCREEN"
printf '%s\n' '=== S2A5 FIX13R4 END SCREEN ==='

if ! grep -Fq 'S2A5 SCNGON OK' "$SCREEN"; then
    echo 'FAIL: architecture scngon did not return successfully' >&2
    exit 1
fi
if ! grep -Fq 'S2A5-NG PASS' "$SCREEN"; then
    echo 'FAIL: S2A5 NG personality selection failed before typed-link probe' >&2
    exit 1
fi
if grep -Fq 'S2A5-LINK-DESC FAIL' "$SCREEN"; then
    echo 'FAIL: typed Devic link failed for net0' >&2
    exit 1
fi
if ! grep -Fq 'S2A5-LINK-DESC PASS' "$SCREEN"; then
    echo 'FAIL: typed Devic link result missing for net0' >&2
    exit 1
fi
if grep -Fq 'S2A5-LINK-DRIVER FAIL' "$SCREEN"; then
    echo 'FAIL: typed Drivr link failed for scnet' >&2
    exit 1
fi
if ! grep -Fq 'S2A5-LINK-DRIVER PASS' "$SCREEN"; then
    echo 'FAIL: typed Drivr link result missing for scnet' >&2
    exit 1
fi
if grep -Fq 'S2A5-LINK-FMGR FAIL' "$SCREEN"; then
    echo 'FAIL: typed FlMgr link failed for SCF' >&2
    exit 1
fi
if ! grep -Fq 'S2A5-LINK-FMGR PASS' "$SCREEN"; then
    echo 'FAIL: typed FlMgr link result missing for SCF' >&2
    exit 1
fi
if grep -Fq 'S2A5-IATTACH FAIL' "$SCREEN"; then
    echo 'FAIL: all three typed links passed; failure is later inside I$Attach/init' >&2
    exit 1
fi
if ! grep -Fq 'S2A5-IATTACH PASS' "$SCREEN"; then
    echo 'FAIL: I$Attach result missing after all typed links' >&2
    exit 1
fi
if grep -Fq 'S2A5-IDETACH FAIL' "$SCREEN"; then
    echo 'FAIL: I$Attach passed but I$Detach failed' >&2
    exit 1
fi

echo 'PASS: S2A5 typed module links and I$Attach all succeeded'
