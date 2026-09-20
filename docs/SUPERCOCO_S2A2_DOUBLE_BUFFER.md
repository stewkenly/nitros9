# SuperCoCo NitrOS-9 S2A-2: Double-buffer animation

S2A-2 turns the static first-pixels proof into a real front/back display loop.
It deliberately stays on the frozen R1J display ABI; R1K acceleration comes in
the next milestone.

## What `scanim` proves

- two **independent** 19 x 8 KiB Level-2 RAM allocations;
- two independent 153,600-byte MBOs (slots 0 and 1, 38 x 4 KiB pages each);
- R1J surface 0 bound to MBO0 and surface 1 bound to MBO1;
- MAIN draws only through temporary 8 KiB DAT apertures;
- only the non-BUSY/back framebuffer is modified;
- every surface change is staged and committed through the R1J VBLANK boundary;
- after each VIDEO event the new surface must be active/BUSY and the old one
  must be non-BUSY before MAIN reuses it;
- 120 swaps complete without depending on stdin, so the exact same command is
  usable both by Venus headless regression and StewsPC graphical testing;
- native output is disabled and both MBO/RAM lifetimes are drained before exit.

The visible demo is a 32x16 white rectangle moving horizontally over a black
640x480 INDEX4 display. Each framebuffer retains its own previous rectangle
position, erases it when that framebuffer becomes the back buffer again, draws
the next position, and then flips.

## Development image

On Venus after the change is published:

```sh
cd /Volumes/design/nitros9
scripts/prepare-supercoco-s2a2.sh
```

The default output is:

```text
/Volumes/design/_transfer/63SDC-S2A2.VHD
```

On StewsPC this is visible through Titan as:

```text
/mnt/v/_transfer/63SDC-S2A2.VHD
```

Copy it into WSL-local runtime storage, boot with the SuperCoCo XRoar build,
and type `scanim` at the NitrOS-9 shell.

## Next milestone

S2A-3 replaces the MAIN-drawn rectangle path with R1K MEDIA `FILL`, `BLIT`, and
`MASKED` commands while retaining the same back-buffer/VBLANK discipline.
