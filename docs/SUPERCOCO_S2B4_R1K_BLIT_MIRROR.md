# SuperCoCo S2B-4 — R1K BLIT Mirror Integration

Status: CANDIDATE
Owner: NITROS9_SOFTWARE
Parent NitrOS checkpoint: `400c0247644bf1468ba1776d2fc1c9134b449dd0` (S2B-3)
Architecture authority: R1I MBO V1 + R1J GIME-NG Display V1 + R1K MEDIA Graphics Services V1
Executable authority: XRoar `23d6f425d805de419f0297a62cbe60b6450e92e2` or descendant

## Purpose

S2B-4 consumes the already-frozen R1K `BLIT` operation in the normal NitrOS
style-9 rendering backend.  S2B-3 established a correctness-first mirrored
framebuffer invariant by replaying each partial semantic FILL into the old
front after the VBLANK flip.  S2B-4 replaces that partial-operation replay
with a general full-frame BLIT from the newly visible authoritative front into
the newly hidden old front.

## Partial-operation sequence

```
normal BAR
   |
R1K FILL_RECT -> hidden back
   |
MEDIA COMPLETE
   |
R1J DISPLAY_COMMIT / VBLANK
   |
new front visible, old front hidden
   |
R1K BLIT 640x480: visible front -> hidden old front
   |
MEDIA COMPLETE
   |
both framebuffer MBOs identical
   |
return to NitrOS
```

The visible source MBO is already held by VIDEO for READ.  R1I permits the
MEDIA engine to take an additional concurrent READ binding; MBO BUSY is a
binding reference count rather than an exclusive lock.  The hidden destination
is bound by MEDIA for WRITE.  MEDIA releases both bindings before the normal
API returns, leaving only the VIDEO binding on the active framebuffer.

## CLS recovery boundary

Full-screen CLS deliberately retains the S2B-3 double-FILL mirror path.  This
keeps the recovery primitive independent of BLIT: if a partial transaction
fails and leaves `SCG.FlagMirrorDirty` set, CLS can still overwrite both full
framebuffers and recover without relying on the operation that may have failed.

## Command record

The mirror command uses Graphics Command V1 operation `BLIT` with source equal
to the active front MBO, destination equal to `grSCBack`, INDEX4 on both
surfaces, offset zero, stride 320, surface size 640x480, source/destination X/Y
zero, and command width/height 640x480.  Existing slot generations are reused;
no new MBOs or guest-visible state are introduced.

## Runtime acceptance

`scgrfblitprobe` drives ordinary CoWin BColor/CLS/FColor/SetDP/BAR commands.  It
checks two successive BAR flips and maps the command MBO after each operation to
prove the final command is BLIT in both directions (surface 0 -> 1 and 1 -> 0)
with exact full-frame geometry.  It also retains the S2B-3 INDEX4 boundary-byte
checks on both framebuffer MBOs and verifies Job/event cleanup and DWEnd drain.

## Deferred

Pattern/LSet BAR variants, BOX/LINE/POINT, direct NitrOS BLIT/PutBlk exposure,
MASKED_BLIT, glyph/text rendering, scrolling, cursor rendering and general
partial-window clipping remain later S2B work.
