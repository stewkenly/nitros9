# SuperCoCo S2B-2 — R1K CLS Fill Integration

Status: CANDIDATE
Owner: NITROS9_SOFTWARE
Parent NitrOS checkpoint: `0216744e95d2196813a0187d345f560818156783` (S2B-1)
Architecture authority: R1K MEDIA Graphics Services V1 + R1J GIME-NG Display V1
Executable authority: XRoar `23d6f425d805de419f0297a62cbe60b6450e92e2` or descendant

## Purpose

S2B-2 connects the first normal NitrOS graphics operation to the production
SuperCoCo rendering path. A normal CoWin/GrfDrv clear-screen control code on
style 9 is translated into R1K `FILL_RECT`, rendered into the non-visible MBO,
then presented through R1J at VBLANK. Legacy styles 1-8 remain on the existing
GrfDrv implementation. CoWin is unchanged.

## Driver path

```
normal CoWin BColor / CLS
          |
       GrfDrv
       /    \
 legacy   SCGrfType
   |         |
old path  command MBO slot 2
          MEDIA_GRAPHICS_V1
          R1K FILL_RECT
               |
          back MBO 0/1
               |
          MEDIA COMPLETE
               |
          R1J DISPLAY_COMMIT
               |
             VBLANK
```

## Command-buffer ownership

S2B-2 adds one dedicated command buffer: one NitrOS 8 KiB RAM block, R1I MBO
slot 2, one exposed 4 KiB MBO page, MEDIA consumer only, READ permission only,
and one 64-byte Graphics Command V1 record at logical offset 0. Framebuffers
remain slots 0/1, 153,600 bytes each, VIDEO|MEDIA, READ|WRITE.

## Task-1 mapping rule

GrfDrv is a kernel task with its own Task-1 MMU image. `F$MapBlk` updates the
current process DAT and is therefore not the correct mapping seam for memory
that GrfDrv itself reads or writes. S2B-2 reuses GrfDrv's established Task-1
scratch window: `$FFA9` maps one 8 KiB physical block at `$2000-$3FFF`. The
previous mapping is saved and restored around command-record and framebuffer
clear accesses.

This correction applies both to the R1K command producer and the S2B-1
framebuffer-clear helper.

## CLS semantics

For style 9 only, BColor stores an INDEX4 palette index 0..15. CLS homes the
logical cursor, builds a 640x480 `FILL_RECT` for the current back MBO, submits
MEDIA Job V1 synchronously, validates COMPLETE/result/event, W1C-clears MEDIA
independently from Job ACK, ACKs the job to IDLE, and presents the completed
back surface through R1J.

## VBLANK completion fence

R1J VIDEO is a periodic VBLANK event while scanout is active. Event observation
alone is not a unique display-commit completion token. The backend therefore
uses VIDEO as a wakeup and accepts completion only when
`VideoActiveSurface == requested_back`, bounded across four VBLANK observations.

## Legacy isolation

The style-9 BColor special case avoids indexing the historical four-entry
graphics color-mask table with internal type 7. All non-SuperCoCo screen types
execute their original BColor and CLS paths. The legacy pixel-address clear
machinery receives no knowledge of the MBO physical layout.

## Runtime acceptance

`scgrffillprobe` proves through normal window writes that style 9 starts on
surface 0; slot 2 is valid/idle; BColor 5 + CLS flips 0->1; MEDIA returns to
IDLE with its event clear; BColor 10 + CLS reuses the command MBO and flips
1->0; and DWEnd disables display and drains MBO slots 0, 1 and 2.

The runtime harness retains the accepted S2B-1 in-place OS9Boot patching
invariant and does not regenerate or relocate the boot stack.

## Verification history

V2 required only the layout-only `bsr NewEnt` -> `lbsr NewEnt` repair after
code growth. V3 added the active-surface VBLANK fence. V4 isolated the first
live failure as R1K `INVALID_DESCRIPTOR`. V5 proved the root cause was GrfDrv
Task-1 address-space mapping and passed the complete SWAI verification suite.
V6 removes the temporary diagnostic error transport while retaining those
production fixes.

## Deferred

Rectangle/bar, BLIT, glyph/text rendering, scrolling, GetBlk/PutBlk, cursor
rendering and general partial-window clipping consume this same backend seam in
later S2B milestones.
