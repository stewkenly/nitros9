# SuperCoCo Community Alpha - S1 common system layer

Status: CLOSED / ACCEPTED
Owner: NITROS9_SOFTWARE
Architecture authority: `3850ed925dcae665ceed13a8f1d0e6f3a28ad9fc`
XRoar executable authority: `23d6f425d805de419f0297a62cbe60b6450e92e2`
NitrOS-9 retained-base authority: `12963de229600c098a7058f452eb7b72f38e0e6c`

## Purpose

S1 promotes the previously proven S1A discovery surface and S1B `scsys` helpers into the retained common NitrOS-9 SuperCoCo system layer used by Community Alpha software.

S1 does not invent a new guest ABI. It consumes the frozen invariant `$FF88-$FF8F` service portal and the frozen R1G-R1L service pages.

## Accepted common surface

The shared `scsys` source and Wildbits Level-2 library export the following retained interfaces:

- `SC_READ8`, `SC_WRITE8`
- `SC_READ16LE`, `SC_WRITE16LE`
- `SC_READ32LE`, `SC_WRITE32LE`
- `SC_PROBE_R1L`
- `SC_IRQ_GET`, `SC_IRQ_ACK`
- `SC_IRQ_MASK_GET`, `SC_IRQ_MASK_SET`
- `SC_MBO_BASE`, `SC_MBO_STATUS`
- `SC_MBO_COMMIT`, `SC_MBO_REVOKE`
- `SC_MBO_NEXTGEN`

The OS-9 convention remains carry-clear success and carry-set failure with `B` containing the OS-9 error code.

## Runtime acceptance

The retained S1 closure gate is `scripts/test-supercoco-s1.sh`.

It proves on a real NitrOS-9 boot against the accepted XRoar machine:

1. `SC_PROBE_R1L` discovers the frozen Community Alpha service foundation.
2. `SC_READ32LE` reads the Audio V1 48,000 Hz service value through the invariant portal.
3. `SC_IRQ_MASK_SET` / `SC_IRQ_MASK_GET` round-trip implemented service masks and restore the prior mask.
4. `SC_IRQ_ACK` / `SC_IRQ_GET` exercise the R1G status/W1C surface.
5. MBO slot geometry and invalid-slot error behavior are preserved.
6. `SC_MBO_NEXTGEN` skips generation zero across a 32-bit wrap.
7. `scanim` runs as a real shared-layer client and completes 120 VBLANK-safe flips using repeated `SC_IRQ_GET` / `SC_IRQ_ACK` event handling.
8. The Wildbits Level-2 object library still exports the common `scsys` entry points to a separately linked client.

The S1 gate is descendant-safe: it requires the accepted NitrOS-9 and XRoar authorities to be ancestors of the candidates under test rather than requiring obsolete exact checkpoint HEADs.

## IRQ scope

S1 freezes the common SuperCoCo service-event access layer: status, mask, W1C acknowledgement, and the calling convention used by drivers and commands.

The current acceptance client uses event polling through this common API. Installation of a kernel/device-specific interrupt service routine is owned by the production driver that consumes the event (S2 graphics and S3 audio) and does not change the S1 register/event ABI.

This separation keeps S1 reusable without pre-selecting one NitrOS-9 device-driver interrupt policy for unrelated services.

## Retained clients

The common layer is already consumed by Community Alpha software including:

- `scinfo`
- `scdemo`
- `scanim`
- `scgfxanim`
- `scavdemo`

Native Network v0.1 remains a separate frozen guest service and is retained on the same NitrOS-9 development line.

## Closure

S1 is closed when `scripts/test-supercoco-s1.sh` and the existing SuperCoCo retained build gate pass on a clean candidate descended from the pinned authorities above.

The next Community Alpha critical-path milestone is S2: production NitrOS-9 GIME-NG `grfdrv` integration.
