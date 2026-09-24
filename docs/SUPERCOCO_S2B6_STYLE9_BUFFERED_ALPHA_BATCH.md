# SuperCoCo S2B-6 - Buffered Style-9 Alpha Batch

Status: CANDIDATE
Owner: NITROS9_SOFTWARE
Parent NitrOS checkpoint: `1e99541240dc98baf8a814f8e6520876a4cbba3a` (`S2B6_STYLE9_ALPHA_CLOSURE_V2_PUBLISHED`)
Required XRoar publication: `f011126cdf4012902885b133ea23fc539223773d` or descendant
Architecture impact: NONE

## Evidence entering this increment

The published S2B-6 alpha repair fixed the malformed glyph top row and retained coherent dual-framebuffer output. Replacing the old per-glyph 640x480 mirror with an 8x8 replay did not materially improve normal-rate interactive throughput. Running XRoar without host rate limiting improved wall-clock throughput by only about 50 percent. The remaining bottleneck is therefore dominated by the per-character synchronization policy rather than the number of pixels copied by the mirror step.

## Bounded change

Only the style-9 `fast.chr` buffered-write path changes.  A one-character buffered write deliberately retains the published S2B-6 immediate draw/present/8x8-replay path; batching starts only when the buffer contains more than one character.  This preserves interactive single-character latency and the retained single-character runtime witness.

The accepted 6309 fast buffer contains at most 64 characters. Bit 7 of the existing private count byte is therefore reused as a transient batch marker; no new GrfDrv direct-page storage is consumed.

For a multi-character batch, character 0 still enters `L0F4B.1`, preserving normal window/font setup and all existing fixed-8x8 validation. Subsequent buffered characters enter at `Not8Wd`, reusing the already mapped font/window setup exactly as the historical optimized graphics-text path does.

While the batch marker is active, each glyph still snapshots and synchronously completes its R1K `MASKED_BLIT`, but `SCG_RENDER_GLYPH` defers `DISPLAY_COMMIT` and the mirror replay. All glyphs therefore accumulate on the same hidden back surface. At the end of the buffered write, one `SCG_PRESENT_BACK` makes the complete batch visible, followed by one record-1 640x480 front-to-hidden BLIT to restore the mirrored-buffer invariant.

The single-character alpha path is unchanged from the published S2B-6 behavior.

## V2 verification correction

The first package attempt stopped safely in VERIFY because the retained S2B-5 source guard still required the historical `SCG_FC_NEXT` and `SCG_FC_BAD` labels. V2 preserves those labels. It also scopes the older no-full-frame-alpha-mirror regression check to `SCG_RENDER_GLYPH`, where that rule still belongs; the new batch commit is intentionally allowed to issue one record-1 full-frame mirror after its single present.

V2 additionally repairs all batch error exits so clearing the private count byte cannot accidentally clear the OS-9 Carry/error indication.

## V3 assembler-range correction

The V2 candidate reached the real GrfDrv assembly and exposed one layout-sensitive legacy short branch: `bmi fast.set`. The new batch control block increased the backward displacement beyond the signed 8-bit branch range. V3 changes only that retained legacy branch encoding to `lbmi fast.set`; the target and condition are unchanged. The build gate requires the widened form and forbids the now-out-of-range short form.

## Failure semantics

`fast.chr` refuses to start a batch if `MirrorDirty` was already set. During an owned batch, `MirrorDirty` remains asserted between hidden draws and is accepted only because the count byte carries the private batch marker.

The starting logical cursor is saved on the GrfDrv stack. If any glyph fails before the final present, the visible front never changed; the cursor is restored and `MirrorDirty` remains set so later partial drawing fails closed until full CLS recovery.

`SCG_ALPHA_BATCH_COMMIT` reports whether failure occurred before or after the present. If the present succeeded but the final mirror failed, the new front is already authoritative, so the advanced cursor is retained while `MirrorDirty` remains set.

## Runtime evidence

The retained `scgrfmaskprobe` still proves the published single-character S2B-6 path first: record 0 is the replayed 8x8 MASKED_BLIT and record 1 remains unused.

It then performs buffered `BC`. Both framebuffers must contain B and C correctly. Because the two-character buffered transaction now presents once rather than twice, the active-surface parity must toggle exactly once relative to the preceding single A. The probe then proves record 0 is the last glyph command for C at x=16 on the current front, while record 1 is a 640x480 BLIT from that front to the hidden surface.

## Deferred

This increment does not add a multi-glyph R1K command ABI, combine multiple glyphs into one MEDIA job, or implement Turbo. Those remain separate decisions if one-present-per-buffered-write still leaves unacceptable throughput after the live normal-rate witness.
