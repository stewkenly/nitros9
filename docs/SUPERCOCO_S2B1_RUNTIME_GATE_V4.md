# SuperCoCo S2B-1 runtime gate V4

V4 keeps the known-good `63SDC.VHD` kernel track, boot placement, and storage
stack intact. It replaces only the `CoWin` module inside the existing contiguous
`OS9Boot` allocation, then replaces `CMDS/grfdrv` and installs `scgrfprobe`.

V3 incorrectly assumed that XRoar's 1440-sector CoCoSDC FDC view constrained the
OS9Boot LSN. The known-good image itself disproved that assumption. V4 therefore
uses the stronger invariant: preserve the base image's existing `DD.BT`, RBF file
descriptor, single data extent, and allocation exactly.

The boot patcher refuses to proceed unless:

- the base image uses a contiguous OS9Boot (`DD.BSZ != 0`),
- the OS9Boot file has exactly one RBF data segment,
- LSN0 and the OS9Boot file descriptor agree on the boot-data LSN and size,
- the replacement module is exactly one `CoWin`,
- the rebuilt boot stream fits inside the original contiguous allocation, and
- the patch can be written in place without changing allocation or boot LSN.

This deliberately avoids `os9 gen` and a generic recipe bootfile. The runtime
proof changes only the graphics integration being tested.
