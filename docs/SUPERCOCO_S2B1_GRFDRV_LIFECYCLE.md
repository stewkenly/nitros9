# SuperCoCo Community Alpha - S2B-1 CoWin/GrfDrv lifecycle integration

Status: CANDIDATE / BUILD GATE FIRST
Owner: NITROS9_SOFTWARE
NitrOS-9 base: `dbaadc16a9aad81f6b226f0c9aca8f4ea974b606`
Architecture authority: `20600994168902ee821a340cf08352f17802631d`
XRoar executable authority: `23d6f425d805de419f0297a62cbe60b6450e92e2`

## Purpose

S2B-1 creates the production bridge between the existing NitrOS-9 Level-2 window stack and the already-proven SuperCoCo GIME-NG memory/display architecture.

It deliberately does **not** pretend that a 153,600-byte MBO-backed framebuffer is another legacy CoCo 3 GIME screen. The old `GrfDrv` path assumes one to four contiguous 8 KiB blocks, an 8-bit physical row stride, and direct MMU mapping. Those assumptions are incompatible with the frozen 640x480 INDEX4 architecture.

Instead, external DWSet style `9` maps to a new internal `GrfDrv` type `7`. Type 7 is intercepted before the legacy MMU and GIME register paths and enters a dedicated SuperCoCo backend.

## S2B-1 accepted scope

The candidate backend owns:

- normal `CoWin` DWSet entry, style 9;
- one 80x60-character / 640x480-pixel production screen at a time;
- two independent 19 x 8 KiB Level-2 RAM allocations;
- two 153,600-byte MBOs in slots 0 and 1;
- `VIDEO|MEDIA`, `READ|WRITE` authority so later R1K drawing does not change framebuffer ownership;
- GIME-NG surfaces 0 and 1 with 320-byte stride;
- RGB888 16-entry startup palette;
- VBLANK-safe GIME-NG enable/disable using the closed S1 event helpers;
- conservative revoke/drain/free on normal DWEnd;
- hiding GIME-NG before selecting a legacy screen;
- use of previously reserved `GrfDrv` direct-page bytes only, preserving all historical legacy state layout.

Legacy CoWin styles 1 through 8 remain unchanged.

## Deliberately deferred from this first code gate

S2B-1 is the lifecycle seam, not the complete graphics driver. It does not yet route normal alpha text, CLS, cursor, line, rectangle, GetBlk/PutBlk, or other `GrfDrv` drawing functions to R1K.

Those operations must not fall through to the old direct-framebuffer implementation for type 7. The next S2 increment attaches the R1K drawing backend and then enables interactive use of style 9.

The included `scgrfprobe` therefore opens `/w15`, creates and validates style 9 without sending text to that window, then performs DWEnd and verifies complete resource drain.

## Build acceptance

Run:

```sh
scripts/test-supercoco-s2b1-build.sh
```

The first gate requires:

- `CoWin` rebuilds with additive style 9;
- `GrfDrv` rebuilds with the S1 helper source plus `scgrf` backend;
- `scgrfprobe` assembles as a real OS-9 module;
- no unresolved diff/whitespace errors;
- type 7 is visibly intercepted before the legacy MMU/select paths.

## Runtime acceptance (next gate)

After the build gate is green, construct a retained boot image containing the rebuilt `CoWin` and `GrfDrv`, then execute `scgrfprobe` under the accepted XRoar machine.

Required runtime marker:

```text
SuperCoCo S2B-1 GrfDrv lifecycle PASS
```

The probe must additionally establish through the S1 service ABI that:

1. surface 0 becomes active after normal style-9 DWSet;
2. MBO0 is VALID+BUSY and MBO1 is VALID+not-BUSY;
3. normal CoWin DWEnd disables native output;
4. both MBO slots become invalid/not-busy after teardown.

No private emulator witness is acceptable for that runtime gate.
