# SuperCoCo Community Alpha - S1A discovery surface

Status: RETAINED CHECKPOINT - incorporated into S1 CLOSED / ACCEPTED

Base NitrOS-9 branch: `feature/supercoco-net0`
Base commit: `afc18e25c3b3691b0d2859a34a045eefddc2338f`
Executable machine target: XRoar R1L `cdebeb172b8147b615fc8e96c3f0b7b0fdcaaf06`
Frozen architecture target: `e240a509f2caa0ececc6855767612933e2d3036e`

Closure record: `docs/SUPERCOCO_S1_COMMON_SYSTEM_LAYER.md`

## Purpose

S1A creates the first reusable NitrOS-9 software surface for the Community Alpha architecture without inventing a new OS-side ABI.

It expands `defs/supercoco.d` with the frozen R1G-R1L service namespace and adds `scinfo`, a real NitrOS-9 command that discovers the machine solely through the invariant `$FF88-$FF8F` service portal.

`scinfo` verifies:

- system ABI 1.1 or later;
- MBO V1, 16 slots, 64 pages/object, 4 KiB pages;
- GIME-NG Display V1, 640x480 INDEX4, 16-entry RGB888 palette, two surfaces;
- MEDIA Graphics V1, MEDIA slot 3, opcode `$10`, 64-byte commands, 640x480 maximum;
- Audio V1, 16 S16LE stereo streams, 64-frame minimum FIFO, exact 48 kHz machine rate.

The command does not use an emulator witness backdoor. The same binary is intended to recognize the eventual hardware implementation of the frozen contracts.

## Why this comes before `scsys`

The eventual S1 common runtime layer needs a stable NitrOS-9 calling convention for portal access, MBO ownership, service events, and driver-facing lifetime rules. S1A deliberately does not freeze that software convention before the first real framebuffer client exists.

The next checkpoint will factor the already-proven portal operations into `scsys` while S2A provides the first MBO-backed display owner. That lets the OS API be shaped by real driver needs instead of by speculation.

## Next

1. S1B: reusable `scsys` portal + capability + MBO helpers.
2. S2A: `scdemo` 640x480x16 front/back MBO display with VBLANK flips.
3. S2A+: R1K fill/blit/masked-blit visual demo and R1L PCM demo.
4. S2B: bridge the existing Level-2 windowing system to the SuperCoCo surface/accelerator model.
