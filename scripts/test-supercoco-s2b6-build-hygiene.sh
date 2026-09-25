#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

python3 - <<'PY2'
from pathlib import Path

def need(path, token):
    text = Path(path).read_text()
    if token not in text:
        raise SystemExit(f"FAIL: {path}: missing {token}")

def forbid(path, token):
    text = Path(path).read_text()
    if token in text:
        raise SystemExit(f"FAIL: {path}: stale token remains: {token}")

need('scripts/test-supercoco-s2b5-build.sh', 'make -B -C "$RECIPE" --no-print-directory .mods/cowin.io .mods/grfdrv')
forbid('scripts/test-supercoco-s2b5-build.sh', 'make -C "$RECIPE" --no-print-directory .mods/cowin.io .mods/grfdrv')

need('scripts/test-supercoco-s2b5-runtime.sh', 'make -B -C "$RECIPE" --no-print-directory .mods/cowin.io .mods/grfdrv')
need('scripts/test-supercoco-s2b5-runtime.sh', '-trap-range 1-1')
forbid('scripts/test-supercoco-s2b5-runtime.sh', '-trap-range 1 -trap-state')
for token in (
    'Runtime XRoar HEAD:',
    'Runtime XRoar SHA256:',
    'Runtime base VHD SHA256:',
    'Runtime CoWin SHA256:',
    'Runtime GrfDrv SHA256:',
):
    need('scripts/test-supercoco-s2b5-runtime.sh', token)

need('scripts/test-supercoco-s2b6-batch-build.sh', 'make -B -C "$RECIPE" --no-print-directory .mods/grfdrv')
need('scripts/test-supercoco-s2b6-strip-build.sh', 'make -B -C "$RECIPE" --no-print-directory .mods/grfdrv')

print('PASS: SuperCoCo S2B6 verifier forces fresh generated modules and captures first-fault/provenance evidence')
PY2
