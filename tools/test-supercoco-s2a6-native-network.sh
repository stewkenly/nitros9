#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

EXPECTED_HEAD="fb312c65c93213ef614b2e220fd8b7fe367f8b74"
ACTUAL_HEAD="$(git rev-parse HEAD)"
[[ "$ACTUAL_HEAD" == "$EXPECTED_HEAD" ]] || {
    echo "FAIL: expected S2A6 FIX15 base $EXPECTED_HEAD, found $ACTUAL_HEAD" >&2
    exit 1
}

SUPERCOCO_EMULATOR_ROOT="${SUPERCOCO_EMULATOR_ROOT:-/Volumes/design/supercoco-emulator}"
XROAR="${XROAR:-$SUPERCOCO_EMULATOR_ROOT/upstream/src/xroar}"
XROAR_CWD="${XROAR_CWD:-$SUPERCOCO_EMULATOR_ROOT/upstream}"
ROMDIR="${ROMDIR:-$SUPERCOCO_EMULATOR_ROOT/roms}"
BASE_VHD="${BASE_VHD:-$SUPERCOCO_EMULATOR_ROOT/images/63SDC.VHD}"
IMAGE_BUILD="$SUPERCOCO_EMULATOR_ROOT/tools/build-supercoco-native-net-vhd.py"
SCNGON_SOURCE="$SUPERCOCO_EMULATOR_ROOT/nitros9/scngon.asm"
TIMEOUT_SECONDS="${S2A6_TIMEOUT:-60}"
HOLD_MS="${S2A6_BACKPRESSURE_HOLD_MS:-1500}"
PAYLOAD_BYTES=$((2 * 1024))
EXPECTED_BASE_SHA="5619e77b2b227d2cc4bffe8184634e4ff3f4e4a073b13d8e03cac23505235ab9"
EXPECTED_STARTUP_SHA="67a2435223c04ac231b5e664f991a3277c65faee1b2aa56a79dc8aa6a3f1c1ff"
EXPECTED_STARTUP_SIZE=497

for cmd in git lwasm os9 python3 shasum cmp grep awk cc; do
    command -v "$cmd" >/dev/null 2>&1 || { echo "FAIL: required command not found: $cmd" >&2; exit 1; }
done
[[ -x "$XROAR" ]] || { echo "FAIL: missing architecture XRoar binary: $XROAR" >&2; exit 1; }
[[ -d "$XROAR_CWD" ]] || { echo "FAIL: missing XRoar cwd: $XROAR_CWD" >&2; exit 1; }
[[ -f "$BASE_VHD" ]] || { echo "FAIL: missing canonical VHD: $BASE_VHD" >&2; exit 1; }
[[ -f "$IMAGE_BUILD" ]] || { echo "FAIL: missing image builder: $IMAGE_BUILD" >&2; exit 1; }
[[ -f "$SCNGON_SOURCE" ]] || { echo "FAIL: missing scngon source: $SCNGON_SOURCE" >&2; exit 1; }
[[ -f "$ROMDIR/coco3.rom" ]] || { echo 'FAIL: missing coco3.rom' >&2; exit 1; }
[[ -f "$ROMDIR/SDC-DOS.raw" ]] || { echo 'FAIL: missing SDC-DOS.raw' >&2; exit 1; }

BASE_SHA="$(shasum -a 256 "$BASE_VHD" | awk '{print $1}')"
[[ "$BASE_SHA" == "$EXPECTED_BASE_SHA" ]] || { echo "FAIL: canonical VHD SHA mismatch: $BASE_SHA" >&2; exit 1; }

expect_blob() {
    local rel="$1" expected="$2" actual
    actual="$(git hash-object "$rel")"
    [[ "$actual" == "$expected" ]] || {
        echo "FAIL: source blob mismatch for $rel" >&2
        echo "expected: $expected" >&2
        echo "actual:   $actual" >&2
        exit 1
    }
}
expect_blob level1/wildbits/modules/net0.asm 77b5680a1fc34872422ab99e50104cdd560da725
expect_blob level1/wildbits/modules/scnet.asm a230a5cff112b4974c5e6afebef1882086da0907

WORK="$(mktemp -d /tmp/supercoco-s2a6-bp.XXXXXX)"
SERVER_PID=""
cleanup() {
    if [[ -n "$SERVER_PID" ]] && kill -0 "$SERVER_PID" 2>/dev/null; then
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
    rm -rf "$WORK"
}
trap cleanup EXIT

PORT_FILE="$WORK/server-port"
SERVER_LOG="$WORK/server.log"
SERVER_METRICS="$WORK/server.metrics"
SERVER_PY="$WORK/server.py"
CRASH="$WORK/crash.state"
TX_GATE="$WORK/tx-gate.open"
TX_STALL_SEEN="$WORK/tx-stall.seen"
TX_RESUME_SEEN="$WORK/tx-resume.seen"
LAUNCH_BARRIER="$WORK/guest-launch.ready"
INTERPOSER_C="$WORK/tx-gate-interposer.c"
INTERPOSER_DYLIB="$WORK/tx-gate-interposer.dylib"
SCREEN="$WORK/screen.txt"
CONSOLE="$WORK/console.txt"
LOG="$WORK/xroar.log"
PROBE="$WORK/scnetbp"
NET0="$WORK/net0"
SCNET="$WORK/scnet"
PAIR="$WORK/n3realpair"
SCNGON="$WORK/scngon"
ORIGINAL_BOOT="$WORK/original-os9boot"
HYBRID_BOOT="$WORK/hybrid-os9boot"
VHD="$WORK/63SDC-S2A6-BP.VHD"
CANONICAL_STARTUP="$WORK/startup.canonical"
STARTUP="$WORK/startup"
STARTUP_VERIFY="$WORK/startup.verify"

cat >"$SERVER_PY" <<'PY_SERVER'
import os
import socket
import sys
import time
import traceback

port_file, log_file, metrics_file, gate_path, stall_seen, resume_seen, launch_path, hold_ms_text, payload_text = sys.argv[1:10]
hold_ms = int(hold_ms_text)
payload_bytes = int(payload_text)
begin = b"S2A6-BEGIN"
end = b"S2A6-END"


def emit(log, message):
    log.write(message + "\n")
    log.flush()
    print(message, flush=True)


def wait_for_nonempty_file(path, timeout, description):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            if os.path.getsize(path) > 0:
                return
        except OSError:
            pass
        time.sleep(0.01)
    raise RuntimeError(f"timeout waiting for {description}: {path}")


def recv_exact(conn, count, description):
    data = bytearray()
    while len(data) < count:
        try:
            chunk = conn.recv(min(4096, count - len(data)))
        except socket.timeout as exc:
            raise RuntimeError(
                f"idle timeout receiving {description}: {len(data)}/{count} bytes"
            ) from exc
        if not chunk:
            raise RuntimeError(
                f"peer closed while receiving {description}: {len(data)}/{count} bytes"
            )
        data.extend(chunk)
    return bytes(data)


with open(log_file, "w", encoding="ascii", buffering=1) as log:
    try:
        server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server.bind(("127.0.0.1", 0))
        server.listen(1)
        port = server.getsockname()[1]
        emit(log, f"S2A6-PHASE listen 127.0.0.1:{port}")
        with open(port_file, "w", encoding="ascii") as handle:
            handle.write(f"{port}\n")

        # Building the port-specific guest module and disposable VHD happens
        # after the port is published.  Do not charge that deterministic build
        # time against the guest TCP-connect window.
        wait_for_nonempty_file(launch_path, 90.0, "guest launch barrier")
        emit(log, "S2A6-PHASE launch-barrier-released")
        server.settimeout(30.0)
        conn, peer = server.accept()
        emit(log, f"S2A6-PHASE accepted {peer!r}")
        with conn:
            conn.settimeout(15.0)
            wait_for_nonempty_file(stall_seen, 30.0, "deterministic TX stall")
            emit(log, "S2A6-PHASE gate-stall-observed")
            if os.path.exists(gate_path):
                raise RuntimeError("TX gate unexpectedly open before hold")

            time.sleep(hold_ms / 1000.0)
            if os.path.exists(gate_path):
                raise RuntimeError("TX gate unexpectedly opened during hold")
            emit(log, f"S2A6-PHASE blocked-hold-complete {hold_ms}ms")

            with open(gate_path, "w", encoding="ascii") as gate:
                gate.write("release\n")
            release = time.monotonic()
            emit(log, "S2A6-PHASE gate-released")

            wait_for_nonempty_file(resume_seen, 10.0, "first successful post-release send")
            emit(log, "S2A6-PHASE backend-send-resumed")

            got = recv_exact(conn, len(begin), "begin marker")
            if got != begin:
                raise RuntimeError(f"begin marker mismatch: {got!r}")
            emit(log, "S2A6-PHASE begin-marker-exact")

            payload = recv_exact(conn, payload_bytes, "payload")
            expected = bytes((i & 0xff) for i in range(payload_bytes))
            if payload != expected:
                for i, (actual, wanted) in enumerate(zip(payload, expected)):
                    if actual != wanted:
                        raise RuntimeError(
                            f"payload mismatch at absolute offset {i}: got {actual:02x}, expected {wanted:02x}"
                        )
                raise RuntimeError("payload mismatch")
            payload_done = time.monotonic()
            emit(log, f"S2A6-PHASE payload-exact {payload_bytes}")

            tail = recv_exact(conn, len(end), "end marker")
            if tail != end:
                raise RuntimeError(f"end marker mismatch: {tail!r}")
            finish = time.monotonic()
            emit(log, "S2A6-PHASE end-marker-exact")

            conn.settimeout(5.0)
            try:
                trailer = conn.recv(1)
                if trailer not in (b"",):
                    raise RuntimeError(f"unexpected post-end byte: {trailer!r}")
                emit(log, "S2A6-PHASE guest-close-observed")
            except socket.timeout:
                emit(log, "S2A6-PHASE guest-close-pending-screen-arbitration")

            elapsed_payload = payload_done - release
            elapsed_total = finish - release
            rate = payload_bytes / elapsed_payload if elapsed_payload > 0 else 0.0
            with open(metrics_file, "w", encoding="ascii") as metrics:
                metrics.write(f"payload_bytes={payload_bytes}\n")
                metrics.write(f"hold_ms={hold_ms}\n")
                metrics.write(f"release_to_payload_seconds={elapsed_payload:.6f}\n")
                metrics.write(f"release_to_end_seconds={elapsed_total:.6f}\n")
                metrics.write(f"diagnostic_tx_bytes_per_second={rate:.3f}\n")
                metrics.write(f"diagnostic_tx_kib_per_second={rate/1024.0:.3f}\n")
            emit(log, "PASS: exact S2A6 deterministic backpressure payload after release")
        server.close()
    except Exception:
        traceback.print_exc(file=log)
        traceback.print_exc(file=sys.stdout)
        sys.stdout.flush()
        sys.exit(1)
PY_SERVER

cat >"$INTERPOSER_C" <<'C_INTERPOSER'
#include <sys/types.h>
#include <sys/socket.h>
#include <errno.h>
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static int stall_marked;
static int resume_marked;

static void mark_file_once(const char *env_name, const char *text, int *marked) {
    if (*marked)
        return;
    const char *path = getenv(env_name);
    if (!path || !*path)
        return;
    int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (fd < 0)
        return;
    size_t length = strlen(text);
    const char *cursor = text;
    while (length != 0) {
        ssize_t n = write(fd, cursor, length);
        if (n <= 0)
            break;
        cursor += (size_t)n;
        length -= (size_t)n;
    }
    close(fd);
    *marked = 1;
}

static ssize_t supercoco_test_send(int fd, const void *buf, size_t len, int flags) {
    const char *gate = getenv("SUPERCOCO_NET_TX_GATE");
    if (gate && *gate && access(gate, F_OK) != 0) {
        mark_file_once("SUPERCOCO_NET_TX_STALL_SEEN", "stalled\n", &stall_marked);
        errno = EWOULDBLOCK;
        return -1;
    }

    /* Avoid resolving/calling send from inside an interposed send hook. */
    ssize_t result = sendto(fd, buf, len, flags, NULL, 0);
    int saved_errno = errno;
    if (result > 0)
        mark_file_once("SUPERCOCO_NET_TX_RESUME_SEEN", "resumed\n", &resume_marked);
    errno = saved_errno;
    return result;
}

__attribute__((used)) static struct {
    const void *replacement;
    const void *replacee;
} _interpose_send __attribute__((section("__DATA,__interpose"))) = {
    (const void *)(unsigned long)&supercoco_test_send,
    (const void *)(unsigned long)&send
};
C_INTERPOSER

cc -dynamiclib -O2 -Wall -Wextra -o "$INTERPOSER_DYLIB" "$INTERPOSER_C"
[[ -s "$INTERPOSER_DYLIB" ]] || { echo 'FAIL: TX gate interposer build produced no dylib' >&2; exit 1; }
echo 'PASS: built deterministic XRoar TX gate interposer'

rm -f "$PORT_FILE" "$SERVER_LOG" "$SERVER_METRICS" "$CRASH" "$TX_GATE" "$TX_STALL_SEEN" "$TX_RESUME_SEEN" "$LAUNCH_BARRIER"
python3 -u "$SERVER_PY" "$PORT_FILE" "$SERVER_LOG" "$SERVER_METRICS" "$TX_GATE" "$TX_STALL_SEEN" "$TX_RESUME_SEEN" "$LAUNCH_BARRIER" "$HOLD_MS" "$PAYLOAD_BYTES" &
SERVER_PID=$!
for _ in {1..100}; do
    [[ -s "$PORT_FILE" ]] && break
    if ! kill -0 "$SERVER_PID" 2>/dev/null; then
        echo 'FAIL: S2A6 server exited before publishing port' >&2
        cat "$SERVER_LOG" >&2 || true
        exit 1
    fi
    sleep 0.05
done
[[ -s "$PORT_FILE" ]] || { echo 'FAIL: S2A6 server did not publish port' >&2; exit 1; }
SERVER_PORT="$(tr -d '[:space:]' < "$PORT_FILE")"
case "$SERVER_PORT" in ''|*[!0-9]*) echo "FAIL: invalid server port: $SERVER_PORT" >&2; exit 1;; esac

echo '=== S2A6 BUILD CURRENT NATIVE-NET MODULES + BACKPRESSURE PROBE ==='
DEFDIR="$ROOT/level2/coco3_6309"
COMMON_DEFS="$ROOT/defs"
AS=(
    lwasm
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
"${AS[@]}" --output="$NET0" "$ROOT/level1/wildbits/modules/net0.asm"
"${AS[@]}" --output="$SCNET" "$ROOT/level1/wildbits/modules/scnet.asm"
"${AS[@]}" --output="$SCNGON" "$SCNGON_SOURCE"
"${AS[@]}" -DS2A6_PORT="$SERVER_PORT" --output="$PROBE" "$ROOT/level1/wildbits/cmds/scnetbp.asm"
for spec in "$NET0:net0" "$SCNET:scnet" "$SCNGON:scngon" "$PROBE:scnetbp"; do
    module="${spec%%:*}"; name="${spec##*:}"
    [[ -s "$module" ]] || { echo "FAIL: assembled module missing: $name" >&2; exit 1; }
    os9 ident "$module" | grep -Fqi "Header for : $name" || { echo "FAIL: module identity mismatch: $name" >&2; exit 1; }
done
cat "$NET0" "$SCNET" > "$PAIR"
PAIR_SHA="$(shasum -a 256 "$PAIR" | awk '{print $1}')"
[[ "$PAIR_SHA" == "83f3bd10084ba5826dabe4dbbf62e17aa638e8e4f887ad1aeb4d8a1b5e2fdc65" ]] || {
    echo "FAIL: current native-net pair no longer matches canonical architecture pair: $PAIR_SHA" >&2
    exit 1
}
SCNGON_SHA="$(shasum -a 256 "$SCNGON" | awk '{print $1}')"
[[ "$SCNGON_SHA" == "dec626fb0e633f72963ce399dfb5971619497a3f549ee86b11ee14bb0311f81e" ]] || {
    echo "FAIL: scngon hash mismatch: $SCNGON_SHA" >&2
    exit 1
}
echo 'PASS: current NitrOS-9 native-net pair matches canonical architecture bytes'

echo '=== S2A6 BUILD DISPOSABLE IMAGE ==='
os9 copy "$BASE_VHD,OS9Boot" "$ORIGINAL_BOOT"
rm -f "$VHD" "$HYBRID_BOOT"
python3 "$IMAGE_BUILD" \
    --source "$BASE_VHD" \
    --output "$VHD" \
    --original-boot "$ORIGINAL_BOOT" \
    --pair "$PAIR" \
    --selector "$SCNGON" \
    --hybrid-output "$HYBRID_BOOT"

CMD_DIR='CMDS'
os9 dir "$VHD,$CMD_DIR" >/dev/null 2>&1 || CMD_DIR='cmds'
os9 dir "$VHD,$CMD_DIR" >/dev/null 2>&1 || { echo 'FAIL: no CMDS directory in disposable VHD' >&2; exit 1; }
os9 del "$VHD,$CMD_DIR/scnetbp" >/dev/null 2>&1 || true
os9 copy "$PROBE" "$VHD,$CMD_DIR/scnetbp"
os9 attr "$VHD,$CMD_DIR/scnetbp" -e -pe

echo '=== S2A6 PRESERVE CANONICAL STARTUP ==='
os9 copy "$BASE_VHD,startup" "$CANONICAL_STARTUP"
SIZE="$(wc -c < "$CANONICAL_STARTUP" | tr -d ' ')"
SHA="$(shasum -a 256 "$CANONICAL_STARTUP" | awk '{print $1}')"
[[ "$SIZE" == "$EXPECTED_STARTUP_SIZE" ]] || { echo "FAIL: canonical startup size mismatch: $SIZE" >&2; exit 1; }
[[ "$SHA" == "$EXPECTED_STARTUP_SHA" ]] || { echo "FAIL: canonical startup SHA mismatch: $SHA" >&2; exit 1; }
python3 - "$CANONICAL_STARTUP" "$STARTUP" <<'PY_STARTUP'
from pathlib import Path
import sys
src, dst = map(Path, sys.argv[1:3])
raw = src.read_bytes()
if not raw.endswith(b'\r'):
    raise SystemExit('FAIL: canonical startup does not end in CR')
lines = [
    'echo *SUPERCOCO S2A6 SESSION BEGIN*',
    'scngon',
    'echo *SUPERCOCO S2A6 NG SELECTED*',
    'iniz /net0',
    'echo *SUPERCOCO S2A6 INIZ OK*',
    'scnetbp',
    'echo *SUPERCOCO S2A6 PROBE RETURNED*',
    'deiniz /net0',
    'echo *SUPERCOCO S2A6 DEINIZ OK*',
    'echo *SUPERCOCO S2A6 SHELL RETURN*',
]
dst.write_bytes(raw + ('\r'.join(lines) + '\r').encode('ascii'))
PY_STARTUP
os9 del "$VHD,startup" >/dev/null 2>&1 || true
os9 copy "$STARTUP" "$VHD,startup"
os9 copy "$VHD,startup" "$STARTUP_VERIFY"
cmp "$STARTUP" "$STARTUP_VERIFY"

echo '=== S2A6 RUN DETERMINISTIC TX BACKPRESSURE ==='
rm -f "$SCREEN" "$CONSOLE" "$LOG" "$CRASH" "$TX_GATE" "$TX_STALL_SEEN" "$TX_RESUME_SEEN"
printf 'launch\n' > "$LAUNCH_BARRIER"
echo 'S2A6-PHASE guest-launch-barrier-open'
pushd "$XROAR_CWD" >/dev/null
set +e
DYLD_INSERT_LIBRARIES="$INTERPOSER_DYLIB" \
SUPERCOCO_NET_TX_GATE="$TX_GATE" \
SUPERCOCO_NET_TX_STALL_SEEN="$TX_STALL_SEEN" \
SUPERCOCO_NET_TX_RESUME_SEEN="$TX_RESUME_SEEN" \
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
    -load-hd0 "$VHD" \
    -console-capture "$CONSOLE" \
    -screen-capture "$SCREEN" \
    -trap pc=0x006b \
    -trap-range 1 \
    -trap-state "$CRASH" \
    -trap-timeout 0.5 \
    -type $'DOS\r' \
    -timeout "$TIMEOUT_SECONDS" \
    >"$LOG" 2>&1
XROAR_STATUS=$?
set -e
popd >/dev/null

for _ in {1..100}; do
    if ! kill -0 "$SERVER_PID" 2>/dev/null; then break; fi
    sleep 0.05
done
set +e
if kill -0 "$SERVER_PID" 2>/dev/null; then
    echo 'server did not finish after emulator exit' >> "$SERVER_LOG"
    kill "$SERVER_PID" 2>/dev/null
    wait "$SERVER_PID" 2>/dev/null
    SERVER_STATUS=124
else
    wait "$SERVER_PID"
    SERVER_STATUS=$?
fi
set -e
SERVER_PID=""

echo '=== S2A6 SERVER RESULT ==='
cat "$SERVER_LOG" || true
echo "server_status=$SERVER_STATUS"
echo "xroar_status=$XROAR_STATUS"

[[ ! -s "$CRASH" ]] || { echo 'FAIL: D.Crash trap fired during S2A6' >&2; cat "$CRASH" >&2; exit 1; }
[[ "$XROAR_STATUS" -eq 0 ]] || { echo "FAIL: XRoar returned $XROAR_STATUS" >&2; tail -n 200 "$LOG" >&2; exit 1; }
[[ "$SERVER_STATUS" -eq 0 ]] || { echo 'FAIL: deterministic S2A6 host server failed' >&2; exit 1; }
[[ -s "$TX_STALL_SEEN" ]] || { echo 'FAIL: deterministic TX gate interposer never stalled send()' >&2; exit 1; }
[[ -s "$TX_RESUME_SEEN" ]] || { echo 'FAIL: XRoar backend never completed a send after gate release' >&2; exit 1; }
[[ -s "$SCREEN" ]] || { echo 'FAIL: no NitrOS-9 screen capture produced' >&2; exit 1; }
[[ -s "$SERVER_METRICS" ]] || { echo 'FAIL: no S2A6 server metrics produced' >&2; exit 1; }

for marker in \
    'S2A6-BACKPRESSURE PASS' \
    '*SUPERCOCO S2A6 PROBE RETURNED*' \
    '*SUPERCOCO S2A6 DEINIZ OK*' \
    '*SUPERCOCO S2A6 SHELL RETURN*'
do
    grep -Fq "$marker" "$SCREEN" || { echo "FAIL: missing screen marker: $marker" >&2; cat "$SCREEN" >&2; exit 1; }
done
if grep -Fq 'S2A6-BACKPRESSURE FAIL' "$SCREEN"; then
    echo 'FAIL: guest backpressure probe reported failure' >&2
    cat "$SCREEN" >&2
    exit 1
fi
if grep -Fq 'Error #' "$SCREEN"; then
    echo 'FAIL: OS-9 reported an error during S2A6' >&2
    cat "$SCREEN" >&2
    exit 1
fi

python3 - "$SCREEN" "$SERVER_METRICS" <<'PY_ACCEPT'
from pathlib import Path
import sys
screen_path, metrics_path = map(Path, sys.argv[1:3])
text = screen_path.read_text(encoding='utf-8', errors='replace')
marker = '*SUPERCOCO S2A6 SHELL RETURN*'
prompt = '{Term|02}/DD:'
if marker not in text:
    raise SystemExit('FAIL: missing S2A6 shell-return marker')
after = text.split(marker, 1)[1]
if prompt not in after:
    raise SystemExit('FAIL: interactive Shell+ prompt not observed after S2A6 shell-return marker')
metrics = {}
for line in metrics_path.read_text().splitlines():
    if '=' in line:
        k, v = line.split('=', 1)
        metrics[k] = v
payload = int(metrics['payload_bytes'])
if payload <= 256:
    raise SystemExit('FAIL: payload is not larger than the architecture TX FIFO')
print('same_session_shell_prompt=1')
print('tx_fifo_capacity_bytes=256')
print(f'payload_bytes={payload}')
print(f'payload_fifo_depths={payload/256.0:.1f}')
print(f"deterministic_hold_ms={metrics['hold_ms']}")
print(f"release_to_payload_seconds={metrics['release_to_payload_seconds']}")
print(f"diagnostic_tx_bytes_per_second={metrics['diagnostic_tx_bytes_per_second']}")
print(f"diagnostic_tx_kib_per_second={metrics['diagnostic_tx_kib_per_second']}")
PY_ACCEPT

echo
echo '=== S2A6 ACCEPTANCE ==='
echo 's2a5_full_session_retained=1'
echo 'deterministic_backend_stall_observed=1'
echo 'tx_fifo_capacity_bytes=256'
echo 'guest_write_exceeds_fifo=1'
echo 'writer_forced_to_backpressure_path=1'
echo 'deterministic_tx_gate_hold=1'
echo 'host_release_after_block=1'
echo 'backend_send_resumed_after_release=1'
echo 'writer_resumed_after_release=1'
echo 'tx_ready_clean_release_path=PINNED_DRIVER_CAUSAL_PROOF'
echo 'exact_2k_tx_payload=1'
echo 'tx_overflow_observed=0'
echo 'guest_path_close_returned=1'
echo 'deiniz_returned=1'
echo 'same_session_shell_return=1'
echo 'cpu_cycles_per_kib=DEFERRED_TO_S2A7_LIGHTWEIGHT_EMULATOR_TELEMETRY'
echo 'irqs_per_kib=DEFERRED_TO_S2A7_LIGHTWEIGHT_EMULATOR_TELEMETRY'
echo 'rx_throughput=DEFERRED_TO_S2A7_LIGHTWEIGHT_EMULATOR_TELEMETRY'
echo 'rx_fifo_high_water=DEFERRED_TO_S2A7_LIGHTWEIGHT_EMULATOR_TELEMETRY'
echo
echo 'PASS: S2A6 deterministic NativeNet TX backpressure release witness'
