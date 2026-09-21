#!/usr/bin/env bash
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"
EXPECTED_HEAD="d09f2dd5ebcde34e74869b766cecade990a2ae64"
[[ "$(git rev-parse HEAD)" == "$EXPECTED_HEAD" ]] || { echo "FAIL: expected S2A7 base $EXPECTED_HEAD" >&2; exit 1; }
EMU="${SUPERCOCO_EMULATOR_ROOT:-/Volumes/design/supercoco-emulator}"
XROOT="${SUPERCOCO_XROAR_ROOT:-$EMU/upstream}"
XROAR="$XROOT/src/xroar"
EXPECTED_XROAR_HEAD="1343483dfacdb787e5601e18593338bf4d95ac63"
ROMDIR="$EMU/roms"
BASE_VHD="$EMU/images/63SDC.VHD"
IMAGE_BUILD="$EMU/tools/build-supercoco-native-net-vhd.py"
SCNGON_SOURCE="$EMU/nitros9/scngon.asm"
[[ -x "$XROAR" ]] || { echo "FAIL: telemetry-enabled XRoar not built: $XROAR" >&2; exit 1; }
[[ -x "$XROOT/tools/test-supercoco-native-net-telemetry.sh" ]] || { echo "FAIL: XRoar S2A7 telemetry bootstrap not installed" >&2; exit 1; }
[[ "$(git -C "$XROOT" rev-parse HEAD)" == "$EXPECTED_XROAR_HEAD" ]] || {
    echo "FAIL: XRoar telemetry revision mismatch" >&2
    echo "expected: $EXPECTED_XROAR_HEAD" >&2
    echo "actual:   $(git -C "$XROOT" rev-parse HEAD)" >&2
    exit 1
}

echo "=== S2A7 VERIFY XROAR TELEMETRY CONTRACT ==="
(
    cd "$XROOT"
    XROAR="$XROAR" ROMDIR="$ROMDIR" ./tools/test-supercoco-native-net-telemetry.sh
)

WORK="$(mktemp -d /tmp/supercoco-s2a7-measure.XXXXXX)"
SERVER_PID=""
cleanup() {
    if [[ -n "$SERVER_PID" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
    rm -rf "$WORK"
}
trap cleanup EXIT
PORT_FILE="$WORK/port"
LAUNCH="$WORK/launch"
SERVER_LOG="$WORK/server.log"
TELEMETRY="$WORK/telemetry.txt"
SERVER_PY="$WORK/server.py"
cat >"$SERVER_PY" <<'__HOST_PY__'
import os, socket, sys, time, traceback
portfile, launch, logfile = sys.argv[1:4]
block = bytes(33 + (i % 94) for i in range(256))
payload = block * 256

def waitfile(path, timeout):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if os.path.exists(path):
            return
        time.sleep(0.01)
    raise RuntimeError("launch barrier timeout")

def recv_exact(conn, count):
    data = bytearray()
    while len(data) < count:
        chunk = conn.recv(min(8192, count - len(data)))
        if not chunk:
            raise RuntimeError(f"peer closed at {len(data)}/{count}")
        data.extend(chunk)
    return bytes(data)

with open(logfile, "w", encoding="ascii", buffering=1) as log:
    try:
        server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server.bind(("127.0.0.1", 0))
        server.listen(2)
        port = server.getsockname()[1]
        with open(portfile, "w", encoding="ascii") as f:
            f.write(str(port))
        log.write(f"LISTEN {port}\n")
        waitfile(launch, 90.0)
        server.settimeout(30.0)

        conn, peer = server.accept()
        conn.settimeout(30.0)
        log.write(f"TX_ACCEPT {peer!r}\n")
        data = recv_exact(conn, len(payload))
        if data != payload:
            raise RuntimeError("TX payload mismatch")
        log.write("TX_EXACT 65536\n")
        conn.close()

        conn, peer = server.accept()
        conn.settimeout(30.0)
        log.write(f"RX_ACCEPT {peer!r}\n")
        conn.sendall(payload)
        conn.shutdown(socket.SHUT_WR)
        log.write("RX_SENT 65536\n")
        try:
            while conn.recv(1024):
                pass
        except (socket.timeout, ConnectionResetError):
            pass
        conn.close()
        server.close()
        log.write("PASS: S2A7 host directional fixture\n")
    except Exception:
        traceback.print_exc(file=log)
        raise
__HOST_PY__
python3 -u "$SERVER_PY" "$PORT_FILE" "$LAUNCH" "$SERVER_LOG" &
SERVER_PID=$!
for _ in {1..200}; do
    [[ -s "$PORT_FILE" ]] && break
    if ! kill -0 "$SERVER_PID" 2>/dev/null; then
        cat "$SERVER_LOG" >&2 || true
        exit 1
    fi
    sleep 0.02
done
[[ -s "$PORT_FILE" ]] || { echo "FAIL: server port missing" >&2; exit 1; }
PORT="$(cat "$PORT_FILE")"

DEFDIR="$ROOT/level2/coco3_6309"
COMMON="$ROOT/defs"
AS=(lwasm --no-warn=ifp1 --6309 --format=os9 --pragma=pcaspcr,nosymbolcase,condundefzero,undefextern,dollarnotlocal,noforwardrefmax "--includedir=$DEFDIR" "--includedir=$COMMON" -DH6309=1 -DNOS9VER=0 -DNOS9MAJ=0 -DNOS9MIN=0)
NET0="$WORK/net0"; SCNET="$WORK/scnet"; SCNGON="$WORK/scngon"; TX="$WORK/scnettxm"; RX="$WORK/scnetrxm"; PAIR="$WORK/pair"; ORIG="$WORK/os9boot"; HYB="$WORK/hybrid"; VHD="$WORK/test.vhd"
"${AS[@]}" --output="$NET0" "$ROOT/level1/wildbits/modules/net0.asm"
"${AS[@]}" --output="$SCNET" "$ROOT/level1/wildbits/modules/scnet.asm"
"${AS[@]}" --output="$SCNGON" "$SCNGON_SOURCE"
"${AS[@]}" -DS2A7_PORT="$PORT" --output="$TX" "$ROOT/level1/wildbits/cmds/scnettxm.asm"
"${AS[@]}" -DS2A7_PORT="$PORT" --output="$RX" "$ROOT/level1/wildbits/cmds/scnetrxm.asm"
for spec in "$TX:scnettxm" "$RX:scnetrxm"; do
    f="${spec%%:*}"; n="${spec##*:}"
    os9 ident "$f" | grep -Fqi "Header for : $n" || { echo "FAIL: module identity $n" >&2; exit 1; }
done
cat "$NET0" "$SCNET" >"$PAIR"
[[ "$(shasum -a 256 "$PAIR" | awk '{print $1}')" == "83f3bd10084ba5826dabe4dbbf62e17aa638e8e4f887ad1aeb4d8a1b5e2fdc65" ]] || { echo "FAIL: pair hash" >&2; exit 1; }
os9 copy "$BASE_VHD,OS9Boot" "$ORIG"
python3 "$IMAGE_BUILD" --source "$BASE_VHD" --output "$VHD" --original-boot "$ORIG" --pair "$PAIR" --selector "$SCNGON" --hybrid-output "$HYB"
CMD=CMDS
os9 dir "$VHD,$CMD" >/dev/null 2>&1 || CMD=cmds
for spec in "$TX:scnettxm" "$RX:scnetrxm"; do
    f="${spec%%:*}"; n="${spec##*:}"
    os9 del "$VHD,$CMD/$n" >/dev/null 2>&1 || true
    os9 copy "$f" "$VHD,$CMD/$n"
    os9 attr "$VHD,$CMD/$n" -e -pe
done
CAN="$WORK/startup.can"; STARTUP="$WORK/startup"
os9 copy "$BASE_VHD,startup" "$CAN"
python3 - "$CAN" "$STARTUP" <<'__STARTUP_PY__'
from pathlib import Path
import sys
src, dst = map(Path, sys.argv[1:3])
raw = src.read_bytes()
if not raw.endswith(b"\r"):
    raise SystemExit("FAIL: canonical startup does not end in CR")
lines = [
    "echo *SUPERCOCO S2A7 SESSION BEGIN*",
    "scngon",
    "iniz /net0",
    "scnettxm",
    "scnetrxm",
    "deiniz /net0",
    "echo *SUPERCOCO S2A7 SHELL RETURN*",
]
dst.write_bytes(raw + ("\r".join(lines) + "\r").encode("ascii"))
__STARTUP_PY__
os9 del "$VHD,startup" >/dev/null 2>&1 || true
os9 copy "$STARTUP" "$VHD,startup"
printf 'launch\n' >"$LAUNCH"
SCREEN="$WORK/screen"; CONSOLE="$WORK/console"; LOG="$WORK/xroar.log"; CRASH="$WORK/crash"
pushd "$XROOT" >/dev/null
set +e
SUPERCOCO_NET_TELEMETRY="$TELEMETRY" SUPERCOCO_NET_BACKEND=host "$XROAR" \
    -ui null -ao null -machine coco3 -machine-cpu 6309 -ram 16384 \
    -rompath "$ROMDIR" -romlist sdcdos=SDC-DOS.raw -cart supercocosdc -cart-type cocosdc \
    -no-cart-autorun -machine-cart supercocosdc -load-hd0 "$VHD" \
    -console-capture "$CONSOLE" -screen-capture "$SCREEN" \
    -trap pc=0x006b -trap-range 1 -trap-state "$CRASH" -trap-timeout 0.5 \
    -type $'DOS\r' -timeout 120 >"$LOG" 2>&1
XROAR_STATUS=$?
set -e
popd >/dev/null
set +e
wait "$SERVER_PID"
SERVER_STATUS=$?
set -e
SERVER_PID=""
if [[ "$XROAR_STATUS" -ne 0 || "$SERVER_STATUS" -ne 0 || -s "$CRASH" ]]; then
    echo "FAIL: runtime xroar=$XROAR_STATUS server=$SERVER_STATUS" >&2
    cat "$SERVER_LOG" >&2 || true
    tail -n 120 "$LOG" >&2 || true
    exit 1
fi
grep -Fq 'S2A7-TX PASS' "$SCREEN" || { echo 'FAIL: TX guest marker missing' >&2; cat "$SCREEN" >&2; echo '--- server ---' >&2; cat "$SERVER_LOG" >&2 || true; echo '--- telemetry ---' >&2; cat "$TELEMETRY" >&2 || true; exit 1; }
grep -Fq 'S2A7-RX PASS' "$SCREEN" || { echo 'FAIL: RX guest marker missing' >&2; cat "$SCREEN" >&2; echo '--- server ---' >&2; cat "$SERVER_LOG" >&2 || true; echo '--- telemetry ---' >&2; cat "$TELEMETRY" >&2 || true; exit 1; }
grep -Fq '*SUPERCOCO S2A7 SHELL RETURN*' "$SCREEN" || { echo 'FAIL: shell-return marker missing' >&2; cat "$SCREEN" >&2; exit 1; }

echo "=== S2A7 MEASUREMENT RECORD ==="
echo "payload_profile=scf_safe_printable_94"
python3 - "$TELEMETRY" <<'__MEASURE_PY__'
from pathlib import Path
import sys
p=Path(sys.argv[1])
if not p.exists():
    raise SystemExit("FAIL: telemetry file missing")
blocks=[]
for raw in p.read_text().strip().split("\n\n"):
    d={}
    for line in raw.splitlines():
        if "=" in line:
            k,v=line.split("=",1); d[k]=v
    if d.get("end_session")=="1":
        blocks.append(d)
if len(blocks)<2:
    raise SystemExit(f"FAIL: expected >=2 telemetry sessions, got {len(blocks)}")
def I(d,k): return int(d[k])
tx=next((d for d in blocks if I(d,"tx_guest_bytes")==65536),None)
rx=next((d for d in blocks if I(d,"rx_guest_bytes")==65536),None)
if tx is None or rx is None:
    raise SystemExit("FAIL: directional telemetry sessions not found")
if I(tx,"tx_backend_bytes")!=65536 or I(tx,"tx_overflows")!=0:
    raise SystemExit("FAIL: TX telemetry bytes/overflow mismatch")
if I(rx,"rx_backend_bytes")!=65536 or I(rx,"rx_guest_bytes")!=65536:
    raise SystemExit("FAIL: RX telemetry byte mismatch")
if I(tx,"tx_fifo_high_water")>256 or I(rx,"rx_fifo_high_water")>256:
    raise SystemExit("FAIL: FIFO high-water exceeds architecture capacity")
rate=I(tx,"event_tick_rate")
def report(name,d,byte_key):
    b=I(d,byte_key); kib=b/1024.0; sec=I(d,"emulated_ticks")/rate
    if sec<=0: raise SystemExit(f"FAIL: {name} non-positive emulated duration")
    print(f"{name}_bytes={b}")
    print(f"{name}_emulated_seconds={sec:.6f}")
    print(f"{name}_throughput_bytes_per_second={b/sec:.3f}")
    print(f"{name}_throughput_kib_per_second={(b/sec)/1024.0:.3f}")
    print(f"{name}_cpu_cycles_per_kib={I(d,'cpu_cycles')/kib:.3f}")
    print(f"{name}_native_irq_assertions_per_kib={I(d,'native_irq_assertions')/kib:.6f}")
report("tx",tx,"tx_backend_bytes")
report("rx",rx,"rx_guest_bytes")
print(f"tx_fifo_high_water={I(tx,'tx_fifo_high_water')}")
print(f"rx_fifo_high_water={I(rx,'rx_fifo_high_water')}")
print(f"tx_full_events={I(tx,'tx_full_events')}")
print(f"tx_wait_arms={I(tx,'tx_wait_arms')}")
print(f"tx_blocked_writes_per_kib={I(tx,'tx_wait_arms')/64.0:.6f}")
print(f"tx_ready_events={I(tx,'tx_ready_events')}")
print(f"tx_overflows={I(tx,'tx_overflows')}")
print("PASS: S2A7 NativeNet directional measurement record")
__MEASURE_PY__
