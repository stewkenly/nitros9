# SuperCoCo S2B-5 — R1K MASKED_BLIT Alpha Text

Status: PROPOSED V7 CANDIDATE
Owner: NITROS9_SOFTWARE
Parent NitrOS checkpoint: `8d3f9b42d0d087e6d6f5eaaaa89a372e46cc0811` (S2B-4)
Architecture authority: R1I MBO V1 + R1J GIME-NG Display V1 + R1K MEDIA Graphics Services V1
Executable authority: XRoar `23d6f425d805de419f0297a62cbe60b6450e92e2` or descendant

V4 verifier correction: the earlier candidate accidentally pinned the S2B-5 runtime gate to `3429056f410ea3d9713ccddc96c492f159bd9a8a`, an R1J experimental branch that diverges from the accepted Community Alpha R1L/R1K lineage. The retained S2B-4 runtime already proves the active emulator is descended from `23d6f425d805de419f0297a62cbe60b6450e92e2`; V4 uses that same accepted executable authority. Production NitrOS-9 source semantics are otherwise identical to V3.

## Purpose

S2B-5 consumes the already-frozen R1K `MASKED_BLIT` operation in the normal
NitrOS-9 style-9 character path.  It is the first S2 increment where ordinary
alpha text no longer falls into the legacy directly-MMU-mapped graphics-font
renderer.

The milestone deliberately remains narrow: fixed 8x8 text is production-backed;
proportional, bold, underline, inverse, scale and any character advance that
would require screen scrolling fail closed for style 9.  Safe style-9 control
codes and scrolling are the next text milestone rather than being hidden inside
this primitive-integration patch.

## Existing memory reused

No new MBO, guest register or ABI is introduced.

The already-published command MBO (slot 2) remains one 4 KiB MEDIA-readable page:

- bytes `0..63`: Graphics Command V1 record 0 — the alpha `MASKED_BLIT`;
- bytes `64..127`: record 1 — the post-present full-frame mirror `BLIT`;
- bytes `128..159`: one staged 8x8 INDEX4 glyph (4 bytes/row x 8 rows).

GrfDrv's historical direct-page reserved tail already extends through the end of
the page.  Existing SuperCoCo state used offsets `+$00..+$2D`; S2B-5 consumes the
final nine bytes only:

- `grSCGlyphRows` at `grRsrved+$2E` through `+$35` — eight raw 1bpp font rows;
- `grSCMaskKey` at `grRsrved+$36` — the R1K chroma key.

The legacy GrfDrv DP size and public layout do not move.

## Character transaction

For a normal fixed 8x8 style-9 character:

1. GrfDrv resolves the selected system font through the existing GP-buffer path.
2. Eight raw font rows are copied into private reserved DP bytes before the
   command-MBO mapping replaces that Task-1 window.
3. The rows are expanded into a 32-byte INDEX4 source tile at offset 128.
4. Graphics Command V1 record 0 is built with operation `MASKED_BLIT`, source
   slot 2 and destination equal to the hidden framebuffer.
5. MEDIA completes the command.
6. R1J presents the completed back surface at VBLANK.
7. Record 1 is built as the retained S2B-4 640x480 `BLIT` from the new visible
   front to the old hidden front.
8. MEDIA completes the mirror command and the mirrored-buffer invariant is
   restored before returning to NitrOS-9.

The two retained records also make native runtime evidence unambiguous: record 0
proves the alpha primitive and record 1 proves the mirror transaction without a
test-only production marker.

## Opaque and transparent semantics

CoWin's existing `TChr` bit remains authoritative.

When transparency is **on** (`TChr` clear), one INDEX4 value distinct from the
foreground is chosen as the R1K mask key.  Zero font bits stage that key and R1K
leaves the existing destination pixel unchanged.

When transparency is **off** (`TChr` set), zero font bits stage the current
background color.  The command still uses `MASKED_BLIT`, but a key distinct from
both foreground and background is selected, so every glyph pixel is copied.

No new text-mode semantic is created.

## Buffered-write boundary and V4 legacy repair

V4 retains V3/V2's renderer selection before character 0 enters the legacy
buffered-write pipeline.  `fast.chr` inspects the target window table before
fetching the first character.  Non-style-9 writes fall through to the accepted
S2B-4 path; style 9 owns the complete buffered transaction and sends every byte
through the same `L0F4B.1` / `SCG_ALPHA_ENTRY` path.

DIAG-F2 and DIAG-F4 proved that the target screen-table style and `Gr.STYMk`
agree at the actual `L0F4D` renderer decision, ruling out the earlier stale-style
hypothesis.  They also reproduced the retained symptom exactly: character 0 of
normal buffered hardware-text output was absent while later characters were
correct.

The root cause is condition-code ownership.  Accepted GrfDrv performs:

```asm
ldb   <Gr.STYMk
bpl   L0F73
```

The `BPL` intentionally consumes N from `LDB` to distinguish hardware text
(negative style marker) from graphics.  S2B-5 inserted `CMPB #SCGrfType` between
those instructions; that compare replaced N.  V4 retains the V3 `TSTB` repair on the legacy
branch before the historical `BPL`, recreating the accepted sign test while
preserving B.  The SuperCoCo equality case still enters `SCG_ALPHA_ENTRY`
directly.

The alpha seam itself returns Carry/B normally to its caller.  A buffered caller
unwinds its saved source pointer before a top-level error return; the single-char
entry propagates a style-9 backend failure only after its nested call has
returned.  No nested alpha routine jumps directly out through `SysRet`.

## Runtime acceptance

`scgrfmaskprobe` drives only normal CoWin/NitrOS operations:

1. open `/w15` and DWSet style 9;
2. CLS with background color 2;
3. use normal BAR to paint three 8x8 color-10 backing cells at x=0..23;
4. select foreground 7, set the normal draw/text point to x=0,y=0;
5. enable transparent characters through the existing CoWin switch;
6. write ordinary single character `A` through `I$Write`;
7. then issue one two-character buffered `BC` write through `I$Write`.

The probe then proves:

- record 0 is `MASKED_BLIT`, source slot 2 offset 128, 8x8 INDEX4, destination
  x=0,y=0 on the active surface;
- the staged glyph contains both foreground 7 and mask-key pixels;
- on **both** framebuffer MBOs, the single `A` foreground glyph pixels are 7
  while key pixels preserve the pre-existing color-10 backing tile;
- both cells of the buffered `BC` write contain foreground-7 and preserved
  backing-10 pixels at x=8 and x=16, proving character 0 and the following
  character of the buffered transaction were both rendered;
- record 1 is the retained full-frame `BLIT` in the correct front-to-hidden
  direction;
- MEDIA returns IDLE, its event is clear, the command MBO is not BUSY, only the
  active framebuffer remains VIDEO-bound, and DWEnd drains/revokes all MBOs.

## Deferred

The next S2 text/control work owns safe style-9 control-code cursor movement,
line feed/scrolling and the remaining font attributes.  BOX/LINE/POINT,
GetBlk/PutBlk exposure, general clipping and cursor rendering also remain later
S2 work unless S2 closure evidence shows they are required earlier.


## V5 runtime-proof correction

V5 does not change the S2B-5 production renderer. G1 proved the alpha write and both command records were valid; G2 then showed the first framebuffer verifier failed without a pixel-mismatch trap. The verifier had reused U as its glyphCopy pointer after F$MapBlk, then called F$ClrBlk without restoring the mapped address required in U. V5 preserves that address in cmdMap and restores U on both success and mapped-error cleanup paths.

## V6 runtime-proof correction

V6 leaves the production S2B-5 renderer unchanged. G1 validated the alpha write, active surface, command mapping, record 0 MASKED_BLIT, glyph tile, and record 1 mirror. V5 fixed verifyOneFB's mapped-address cleanup but still failed before the first command PASS marker. Inspection showed verifyCommands had the same ownership bug: after F$MapBlk it reused U for glyphCopy and then called F$ClrBlk without restoring the mapped address. V6 restores U from cmdMap on both verifyCommands success and mapped-error cleanup paths, with source guards for both restores.
