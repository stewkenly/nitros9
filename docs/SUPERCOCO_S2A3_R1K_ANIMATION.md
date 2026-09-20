# SuperCoCo NitrOS-9 S2A-3: R1K accelerated animation

S2A-3 moves framebuffer rendering out of MAIN and into the frozen R1K MEDIA
Graphics Services V1 engine while retaining the S2A-2 double-buffer/VBLANK
ownership discipline.

## Ownership model

Four independent MBOs are used:

- MBO0: 153,600-byte framebuffer A, VIDEO|MEDIA, READ|WRITE;
- MBO1: 153,600-byte framebuffer B, VIDEO|MEDIA, READ|WRITE;
- MBO2: one-page 64-byte graphics-command backing, MEDIA READ;
- MBO3: one-page tile/sprite source backing, MEDIA READ.

MAIN allocates the framebuffer extents with `F$AllRAM`, publishes their page
lists, and never maps their pixel memory. It maps only the command block while
constructing a command and the source block once during asset initialization.
MEDIA is therefore the only framebuffer writer and GIME-NG is the display
reader.

## Visible scene

`scgfxanim` initializes both framebuffers with R1K FILL, then runs 120 swaps.
Each back-buffer frame executes four MEDIA jobs:

1. FILL a 640x8 top band;
2. FILL a 640x16 sprite band;
3. BLIT an opaque 64x8 multicolor tile across the top band;
4. MASKED BLIT a 32x16 sprite across the lower band with palette index 0 as
   transparent.

Every job must reach COMPLETE with result zero and emit the R1G MEDIA event.
Only after all back-buffer jobs finish is the surface staged for the next R1J
VBLANK. The new front MBO must be BUSY and the old front MBO must be released
before the next frame is rendered.

## Development image

On Venus after publication:

```sh
cd /Volumes/design/nitros9
scripts/prepare-supercoco-s2a3.sh
```

The default output is:

```text
/Volumes/design/_transfer/63SDC-S2A3.VHD
```

On StewsPC it is available through Titan as:

```text
/mnt/v/_transfer/63SDC-S2A3.VHD
```

Copy it to WSL-local runtime storage, boot with XRoar commit
`3429056f410ea3d9713ccddc96c492f159bd9a8a`, and run:

```text
scgfxanim
```

## Next milestone

S2A-4 keeps the accelerated animation running while R1L streams real 48 kHz
S16LE stereo PCM from an MBO-backed ring. That will prove concurrent VIDEO,
MEDIA, and AUDIO service ownership in one visible/audible workload.
