# SuperCoCo S2B-3 — R1K BAR Fill Integration

Status: CANDIDATE
Owner: NITROS9_SOFTWARE
Parent NitrOS checkpoint: `a35e56a4dcfaeb808a508cb3f7c2d7ac242f91ad` (S2B-2)
Architecture authority: R1K MEDIA Graphics Services V1 + R1J GIME-NG Display V1
Executable authority: XRoar `23d6f425d805de419f0297a62cbe60b6450e92e2` or descendant

## Purpose

S2B-3 connects the first bounded partial drawing primitive to the production
SuperCoCo backend. Normal CoWin/GrfDrv BAR requests on style 9 retain the
existing coordinate/scaling checks and normalization, but render through R1K
`FILL_RECT` instead of legacy pixel-address code. Legacy styles are unchanged.

## Foreground color

Style-9 FColor is a direct INDEX4 palette index 0..15. It bypasses the legacy
four-entry graphics screen-type mask table, matching the S2B-2 BColor rule.

## Mirrored-buffer invariant

A partial operation cannot safely draw only into a stale hidden framebuffer and
then flip it visible. S2B-3 therefore keeps both framebuffer MBOs semantically
identical at every successful API boundary:

1. render the rectangle into the hidden back surface;
2. wait for MEDIA completion;
3. VBLANK-flip that surface visible;
4. replay the same semantic rectangle into the newly hidden old front;
5. return success only after the replay completes.

`SCG.FlagMirrorDirty` records any interrupted transaction. Partial BAR fails
closed while dirty. Full-screen CLS is allowed to recover because it overwrites
both complete framebuffers and clears the dirty state only after both fills
succeed.

This correctness-first rule deliberately avoids introducing BLIT merely to
implement BAR. A later BLIT milestone may optimize framebuffer preservation
without changing the normal NitrOS API.

## BAR semantics

CoWin continues to copy the current graphics cursor and destination coordinates
into the normal GrfDrv working coordinates. S2B-3 reuses GrfDrv's existing
scale/range checks and X/Y normalization, then builds Graphics Command V1 with
explicit DST_X/DST_Y/WIDTH/HEIGHT. Pattern-set and non-normal LSet BAR variants
remain deferred rather than being silently misrendered.

## Runtime acceptance

`scgrfbarprobe` uses only normal CoWin commands. It establishes background 2
with BColor+CLS, draws color-7 BAR `(17,8)..(46,15)`, then draws a color-10 BAR
using reversed coordinates `(99,12)..(80,4)`. It proves Job/event/ownership
state after each operation, then maps the first physical block of both
framebuffer MBOs from the probe process and checks exact INDEX4 bytes.

The first BAR intentionally crosses nibble boundaries, proving adjacent
background pixels are preserved (`0x27` and `0x72` boundary bytes). The final
checks also prove the first BAR survives the second partial update, reversed
coordinates normalize correctly, and both framebuffer MBOs contain the same
image before DWEnd drains all authority.

## Deferred

Pattern/LSet BAR variants, BOX/LINE/POINT, BLIT, glyph/text rendering, scrolling,
GetBlk/PutBlk, cursor rendering and general partial-window clipping remain later
S2B work.
