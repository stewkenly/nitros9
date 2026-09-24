# SuperCoCo S2B-6 - Buffered Style-9 Alpha Row Strip

Status: CANDIDATE
Owner: NITROS9_SOFTWARE
Parent NitrOS checkpoint: `fbcb28aa3dda339c62e18a7dcf832753ef2fb83a` (`S2B6_STYLE9_BUFFERED_ALPHA_BATCH_V3_PUBLISHED`)
Required XRoar publication: `f011126cdf4012902885b133ea23fc539223773d` or descendant
Architecture impact: NONE

## Evidence entering this increment

The published buffered-presentation V3 closed the presentation side cleanly: live SDL/RGB testing retained correct glyph shapes and perfectly coherent framebuffer output. A normal shell `dir` completes in less than one second, while the SuperCoCo style-9 terminal still required about 4.5 seconds.

V3 removed per-character `DISPLAY_COMMIT`, but every buffered glyph still performed its own synchronous MEDIA Graphics V1 lifecycle: descriptor staging through the service portal, SUBMIT, PENDING/BUSY/COMPLETE polling, MEDIA event handling, ACK, and return to IDLE. The remaining optimization target is therefore the number of MEDIA transactions per buffered write.

## Bounded change

The guest-visible R1K Graphics V1 ABI is unchanged. The existing `MASKED_BLIT` operation already supports arbitrary rectangle widths, so the driver now batches adjacent fixed 8x8 glyphs into a row-wide source strip rather than inventing a new multi-glyph opcode.

The command MBO remains one 4K page. Bytes 0..63 remain command record 0, bytes 64..127 remain record 1, and offset 128 is reused as a fixed 640x8 INDEX4 source surface with 320-byte stride. Its complete footprint ends at byte 2687, safely inside the published 4K MBO.

During a multi-character `fast.chr` transaction:

1. the existing V3 high-bit count marker still owns the buffered transaction and its rollback semantics;
2. each glyph still goes through the accepted fixed-font lookup and copies its eight 1bpp rows before the command MBO is mapped over the Task-1 scratch window;
3. the glyph is expanded directly into its x-position in the 640x8 strip, with no MEDIA submission;
4. the logical cursor advances exactly as before;
5. when the cursor wraps to x=0, the completed physical row is submitted as one MASKED_BLIT and strip state is reset at the new row origin;
6. the final partial row is flushed once by `SCG_ALPHA_BATCH_COMMIT`;
7. the accumulated hidden framebuffer is presented once; and
8. record 1 performs the same one final 640x480 front-to-hidden mirror retained from V3.

Because the H6309 CoWin fast buffer is at most 64 characters, a buffered transaction can cross at most one 80-column row boundary. Normal buffered output therefore needs one strip MEDIA job, or at most two when the write begins late enough in a row to wrap, instead of one MEDIA job per character.

The ordinary one-character buffered path remains the published S2B-6 immediate transaction: one 8x8 draw, one present, and one 8x8 replay. No Turbo behavior changes are included.

## Direct-page and MBO ownership

No direct-page allocation is added. Strip start X, strip count, and strip start Y are alpha-only aliases of allocation/MBO-programming temporaries whose lifetimes do not overlap active alpha rendering. The historical reserved tail remains unchanged.

No MBO is added or resized. The command MBO remains READ-only to MEDIA and one 4K page long.

## Failure semantics

The V3 fail-closed model is retained. `MirrorDirty` becomes owned by the batch when the first glyph is staged. A strip submission failure occurs before any visible present, so the caller restores the buffered transaction's starting logical cursor and leaves `MirrorDirty` asserted; the untouched front remains authoritative until full CLS recovery.

If the final visible present succeeds but the one final mirror fails, the advanced cursor is retained because the new front is already authoritative, while `MirrorDirty` remains asserted.

## Runtime evidence

The retained probe still proves the unchanged single-character path first. Its buffered `BC` write must then:

- leave B and C correct in both framebuffer MBOs;
- toggle active-surface parity exactly once relative to the preceding single A;
- retain record 0 as one 16x8 MASKED_BLIT with source offset 128, source stride 320, source width 640, source x=8, destination x=8, and command width 16; and
- retain record 1 as the one final 640x480 front-to-hidden mirror.

## Live acceptance

Rebuild the S2B6 VHD from the published strip candidate and repeat the normal-rate SDL/RGB style-9 terminal witness. Glyph shape and framebuffer coherence must remain correct. The performance question is whether `dir` moves materially toward the sub-second standard-shell behavior from the approximately 4.5-second V3 baseline.

If it does not, the next step is instrumentation of CoWin buffer/write cadence and service-portal cost rather than another speculative rendering rewrite.
