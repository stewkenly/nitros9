# SuperCoCo S2B-6 - Style-9 Alpha Correctness and Bounded Mirror Replay

Status: CANDIDATE
Owner: NITROS9_SOFTWARE
Parent NitrOS checkpoint: `21745dea6911daed1220c88a17199e81fb129e20` (S2B-5)
Required XRoar publication: `f011126cdf4012902885b133ea23fc539223773d` or descendant
Architecture impact: NONE

## Purpose

Interactive S2B-6 validation proved that the style-9 terminal is alive after the
XRoar native-video ownership repair, but exposed two implementation defects in
the S2B-5 alpha path:

1. glyph row 0 shares direct-page storage with the second byte of the Task-1
   map-save scratch pair, corrupting the top row of every character (including
   spaces); and
2. every 8x8 glyph is followed by a 640x480 full-frame BLIT solely to restore
   the mirrored-framebuffer invariant, yielding roughly five characters per
   second in the interactive terminal.

This increment fixes both without changing R1I, R1J, R1K, CoWin semantics or
any guest-visible ABI.

## Direct-page repair

S2B-5 used:

- `grSCMapSave` at `grRsrved+$2D..+$2E`;
- `grSCGlyphRows` at `grRsrved+$2E..+$35`.

The overlap at `+$2E` means `SCG_T1_MAP_BLOCK` overwrites glyph row 0 after the
font rows are copied.  S2B-6 keeps the two-byte map save at `+$2D..+$2E`, moves
the eight glyph rows to `+$2F..+$36`, and aliases the alpha-only mask-key byte
to `grSCColor` at `+$2C`.  Fill/BAR/CLS color construction and alpha command
construction are serialized GrfDrv transactions and do not require those two
aliases simultaneously.  The legacy one-page GrfDrv direct-page layout does
not grow.

## Alpha mirror repair

The accepted S2B-5 transaction was:

1. build and submit an 8x8 `MASKED_BLIT` into the hidden framebuffer;
2. present that framebuffer at VBLANK;
3. build and submit a 640x480 `BLIT` from the new front to the old front.

S2B-6 keeps steps 1 and 2.  After the present swaps `grSCBack`, it patches only
the destination MBO slot/generation in the already-built record-0
`MASKED_BLIT`, then submits that same 8x8 operation once more into the newly
hidden old front.  Both buffers therefore contain the same semantic glyph
result, but the per-character mirror touches 64 pixels instead of 307,200.

The operation still waits for one VBLANK per character.  Buffered multi-glyph
presentation is deliberately deferred until this bounded correctness/performance
repair has interactive evidence.

## Regression evidence

The retained `scgrfmaskprobe` still proves single-character and buffered alpha,
transparent-mask preservation, both framebuffer copies, front-surface state,
and complete DWEnd teardown.  Its command witness now additionally proves that
record 0 was retargeted to the hidden mirror and record 1 remained unused, so
the superseded full-frame alpha mirror could not have run.

`scripts/test-supercoco-s2b6-build.sh` requires the accepted S2B-5 base, proves
that the direct-page ranges are disjoint and bounded, and builds the retained
modules/probe through the forward-compatible S2B-5 regression.

`scripts/test-supercoco-s2b6-runtime.sh` additionally requires the published
XRoar native-video ownership fix at `f011126c...` (or descendant) and runs the
retained native runtime proof.

## Turbo

This increment does not define or implement SuperCoCo MAIN Turbo mode.  Turbo
is the next emulator/product-identity increment after style-9 alpha closure so
that `-machine supercoco`, legacy CoCo speed selection, and the SuperCoCo Turbo
selector can be tested as one coherent machine policy instead of being hidden
inside a NitrOS-9 graphics fix.
