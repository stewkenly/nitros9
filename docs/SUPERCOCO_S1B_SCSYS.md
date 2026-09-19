# SuperCoCo Community Alpha - S1B shared `scsys` layer

Status: candidate software integration checkpoint

Base NitrOS-9 branch: `feature/supercoco-net0`
Base commit: `a8220376d7caf02af1c150766feff4ca77cca231`
Executable machine target: XRoar R1L `cdebeb172b8147b615fc8e96c3f0b7b0fdcaaf06`
Frozen architecture target: `e240a509f2caa0ececc6855767612933e2d3036e`

## Purpose

S1B freezes the first reusable NitrOS-9 calling convention for the invariant SuperCoCo service fabric. It factors the portal access already proven by `scinfo` into `scsys` and makes that same source available through the Wildbits Level-2 relocatable library.

The API is intentionally small and evidence-driven. S1B owns service transport and MBO descriptor lifetime mechanics. It does **not** yet own large-buffer allocation, DAT/MMU page acquisition, or framebuffer pinning; S2A will prove those policies with real 153,600-byte front/back surfaces.

## Calling convention

All routines use the normal OS-9 carry convention:

- carry clear: success;
- carry set: failure, with `B` containing an OS-9 error code.

The first frozen entry points are:

- `SC_READ8`, `SC_WRITE8` - byte portal transactions;
- `SC_READ16LE`, `SC_WRITE16LE` - 16-bit little-endian service fields;
- `SC_READ32LE`, `SC_WRITE32LE` - four-byte little-endian service fields via `U`;
- `SC_PROBE_R1L` - validate magic, ABI 1.1+, R1G/R1H/R1I/R1J/R1K capability foundation, and R1L Audio;
- `SC_IRQ_GET`, `SC_IRQ_ACK`, `SC_IRQ_MASK_GET`, `SC_IRQ_MASK_SET` - unified R1G event access;
- `SC_MBO_BASE`, `SC_MBO_STATUS`, `SC_MBO_COMMIT`, `SC_MBO_REVOKE` - MBO slot/lifetime operations;
- `SC_MBO_NEXTGEN` - increment a little-endian 32-bit generation while skipping zero.

`SC_READ8`/`SC_WRITE8` preserve `X` and `Y`. The 32-bit helpers preserve `X`, `Y`, and `U`. MBO slot numbers are 0..15; invalid slots return `E$IllArg`.

## First real client

`scinfo` edition 2 is refactored onto `SC_PROBE_R1L` and `SC_READ8`. The old private `portalRead` implementation is removed. That means the shared layer is exercised immediately by existing Community Alpha software rather than being introduced as unused infrastructure.

## Why allocation is not in S1B

A 640x480 INDEX4 surface is 153,600 bytes. Two surfaces are 307,200 bytes. NitrOS-9 Level 2 exposes process DAT images and system-memory primitives, but the correct ownership model for allocating, mapping, describing, and later releasing those non-contiguous 4 KiB physical pages must be proven against a real client.

S2A therefore owns the next decision: allocate real front/back storage, derive the ordered MBO physical page list, establish lifetime rules, and then freeze only the allocation helpers that survive that test.

## Next

1. S2A-1: prove Level-2 large-buffer allocation + physical-page discovery and publish two valid MBOs.
2. S2A-2: bind those MBOs to GIME-NG surfaces and perform VBLANK-safe front/back flips.
3. S2A-3: add R1K fill/blit/masked-blit visual proof.
4. S2A-4: add the short R1L PCM proof.
