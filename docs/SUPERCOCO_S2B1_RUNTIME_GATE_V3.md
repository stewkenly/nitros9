# SuperCoCo S2B-1 runtime gate V3

V3 keeps the known-good `63SDC.VHD` kernel track and boot/storage stack intact.
It replaces only the `CoWin` module inside the existing contiguous `OS9Boot`
allocation, then replaces `CMDS/grfdrv` and installs `scgrfprobe`.

The boot patcher refuses to proceed unless:

- the base image uses a contiguous OS9Boot (`DD.BSZ != 0`),
- the OS9Boot file has exactly one RBF data segment,
- LSN0 and the OS9Boot file descriptor agree on the boot-data LSN and size,
- the replacement CoWin is the only `CoWin` module in the stream,
- the rebuilt boot stream fits inside the original allocation, and
- the entire contiguous boot stream remains inside LSN 0..1439, the current
  CoCoSDC FDC-visible boot region used by the SuperCoCo XRoar configuration.

This deliberately avoids `os9 gen` and any generic recipe bootfile so the S2B-1
runtime proof changes only the graphics integration being tested.
