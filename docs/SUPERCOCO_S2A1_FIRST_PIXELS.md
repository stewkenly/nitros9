# SuperCoCo Community Alpha - S2A-1 first pixels

Status: candidate software integration checkpoint

Base NitrOS-9 branch: `feature/supercoco-net0`
Base commit: `a434445d2b5182683ec2d164febc0a030b0d36cb`
Executable machine target: XRoar R1L `cdebeb172b8147b615fc8e96c3f0b7b0fdcaaf06`
Frozen architecture target: `e240a509f2caa0ececc6855767612933e2d3036e`

## Purpose

S2A-1 turns the frozen R1I/R1J contracts into the first human-visible NitrOS-9 SuperCoCo graphics client.

The new `scdemo` command allocates a real 153,600-byte 640x480 INDEX4 framebuffer, paints a 16-color test pattern, publishes the physical storage as MBO slot 0, binds that MBO to GIME-NG surface 0, and enables it atomically at VBLANK. The pattern remains visible until a key is pressed, after which the command disables the display at VBLANK, revokes the MBO, waits for drain, and returns the physical RAM to NitrOS-9.

## Level-2 memory model proven here

A 640x480 INDEX4 framebuffer is 153,600 bytes. NitrOS-9 Level 2 cannot and should not pretend that object is a conventional contiguous 64 KiB process buffer.

S2A-1 instead uses the kernel's physical-memory primitives directly:

- `F$AllRAM`: allocate 19 contiguous 8 KiB physical blocks (155,648 bytes);
- `F$MapBlk`: map one owned 8 KiB block into a temporary process window;
- CPU paint through that temporary mapping;
- `F$ClrBlk`: remove the temporary mapping without releasing ownership;
- translate each 8 KiB block into two sequential 4 KiB MBO page numbers;
- publish 38 ordered MBO pages with logical length 153,600 bytes;
- `F$DelRAM`: release all 19 physical blocks only after VIDEO has drained and the MBO is revoked.

The extra 2,048 bytes in the final 8 KiB allocation block are outside the MBO logical length and are never displayed.

## First visual

The CPU renderer produces sixteen 40-pixel-wide vertical bars using an EGA-like RGB888 palette. Each packed INDEX4 byte contains two pixels of the same color. The 320-byte row pattern repeats for all 480 scan lines.

This deliberately uses CPU rendering for the first proof. R1K acceleration comes next, after memory ownership and display lifetime have been proven independently.

## Lifetime rule

Physical RAM is never returned while VIDEO or the MBO can still reference it:

1. stage display disable;
2. commit and wait for the VIDEO VBLANK event;
3. verify no active surface;
4. revoke MBO0;
5. wait for `BUSY` to clear;
6. call `F$DelRAM`.

Failure cleanup is conservative. MBO and VIDEO are marked potentially live before their COMMIT commands are submitted, because a portal timeout can make the command outcome ambiguous. If consumer drain cannot be proven, `scdemo` intentionally leaves the physical allocation owned until reboot rather than create a use-after-free.

S2A-1 does not yet define an OS-wide MBO slot allocator. `scdemo` uses slot 0 only when that slot is already invalid and not busy; it refuses to revoke an unknown live descriptor. A later driver/service layer will own global slot allocation policy.

## ABI definitions added

`defs/supercoco.d` gains the frozen GIME-NG surface descriptor offsets:

- MBO slot: `+0`
- format: `+1`
- generation: `+2`
- logical offset: `+6`
- stride: `+10`
- descriptor size: 12 bytes

These are architecture fields already exercised by the native R1J probe; S2A-1 makes them canonical for NitrOS-9 clients.

## Run it interactively

After S2A-1 is published, the drop installs `scripts/run-supercoco-s2a1.sh`. On the current Venus layout, simply run:

```text
scripts/run-supercoco-s2a1.sh
```

The runner uses `/Volumes/design/supercoco-xroar/src/xroar`, verifies that checkout is still pinned to accepted R1L commit `cdebeb172b8147b615fc8e96c3f0b7b0fdcaaf06`, uses the ROMs and golden `63SDC.VHD` under `/Volumes/design/supercoco-emulator`, and creates a private working image under the user's application-data directory. The golden VHD is never modified. Use `--reset-image` to reseed the private image. All paths have environment overrides for portability.

The script builds the current `scdemo`, installs it into the private VHD, adds `scdemo` to startup once, boots through the normal CoCoSDC `DOS` path, and launches the GUI without a timeout. Press any key on the color-bar screen to disable GIME-NG cleanly and return to NitrOS-9.

## Next

1. Run the interactive S2A-1 launcher and confirm the actual 640x480x16 display.
2. S2A-2: allocate two independent framebuffer MBOs and prove VBLANK-safe front/back flipping.
3. S2A-3: render through R1K `FILL`, `BLIT`, and `MASKED` operations instead of CPU-only painting.
4. S2A-4: add the short R1L PCM proof.
5. Package the stable R1L emulator plus a Community Alpha NitrOS-9 disk into the first install-and-run developer release.
