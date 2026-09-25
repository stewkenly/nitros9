# SuperCoCo S2B6 verification build hygiene

## Problem

An abandoned S2B6 candidate restored the governed source tree to the published
row-strip baseline, but the generated `recipes/coco3_6309/40d/.mods/grfdrv`
artifact survived. Ordinary `make` considered that stale module current, so a
baseline runtime witness injected candidate bytes into an otherwise published
VHD and produced a false D.Crash regression.

A forced rebuild proved the diagnosis: the rebuilt GrfDrv matched the frozen
published V3 module byte-for-byte (size `$3312`, CRC `$1A3EFD`, edition 14), and
the retained runtime proof passed again.

## Policy

SuperCoCo S2B5/S2B6 proof paths must not trust generated-module timestamps at a
governed lifecycle boundary. Candidate verification rebuilds CoWin and GrfDrv
with `make -B` before constructing the runtime VHD. The buffered-alpha build
proof also forces GrfDrv.

D.Crash capture records only the first `$006B` entry (`-trap-range 1-1`) so
cascading ROM-state traps cannot obscure the initiating state.

Runtime evidence records the selected XRoar checkout/head/executable hash, base
VHD path/hash, and the exact CoWin/GrfDrv hashes inserted into the candidate
image.

## Scope

This change alters verification infrastructure only. It does not change GrfDrv,
CoWin, the SuperCoCo ABI, or emulator behavior.
