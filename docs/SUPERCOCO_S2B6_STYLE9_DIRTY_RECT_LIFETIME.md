# SuperCoCo S2B6 style-9 dirty-rectangle + lifetime closure V1

## Accepted base

- NitrOS-9 base: `7cf3027b549e9392c313c9645d269aad61134604`
- XRoar alpha floor: `d9661764ae4ecaeb54bf55fb404843efae74c1fa`

The base is already proven for boot, R1J native 640x480, the five-CPU full-speed
contract, R1K/MEDIA graphics, concurrent VIDEO+MEDIA+AUDIO, masked alpha,
buffered style-9, and row-strip batching.

## Dirty-rectangle mirror

This closure retains at most two row-strip MASKED_BLIT records for one
<=64-character H6309 fast write. After the single PRESENT, each retained record
is converted in place to a bounded front-to-hidden BLIT covering only the dirty
rectangle.

Deterministic graphics row work is therefore:

- normal one-row buffered write: 8 render rows + 8 mirror rows = **16 rows**;
- wrapping two-row write: 16 render rows + 16 mirror rows = **32 rows**.

The periodic VIDEO wakeup teardown fence waits for authoritative
`VideoActiveSurface=$FF`, rather than assuming the first VIDEO event corresponds
to the disable commit.

## GrfDrv lifetime closure

Historical CoWin destroyed GrfDrv when the final window disappeared:

1. GrfDrv Term (`$02`);
2. `F$UnLink`;
3. clear `G.GrfEnt`;
4. release `G.GfxTbl`.

That boundary predates the modern VTIO buffered path and SuperCoCo backend.
`G.GrfEnt` is now a shared execution endpoint, and GrfDrv Term also runs
`SCG_TERM`, which destroys shared backend state. Destroying the service merely
because the last window closed therefore invalidates infrastructure that a
subsequent VTIO/window lifecycle expects to reuse.

For Community Alpha, GrfDrv becomes **session-resident after first successful
initialization**. Per-window `DWEnd` remains responsible for disabling scanout
and draining/revoking the style-9 MBOs. Final-window `I$Close` releases the
window but retains the GrfDrv module link, `G.GrfEnt`, `G.GfxTbl`, and initialized
shared backend for reuse. Residency ends with the OS/system session rather than
with the current window count.

This is deliberate bounded residency, not repeated allocation: reopening uses
the same shared service, while each style-9 DWSet/DWEnd cycle creates and tears
down its per-window resources.

## Runtime acceptance

The retained masked-alpha/dirty-rectangle probe now performs a real lifecycle:

1. open `/w15`;
2. enter style-9 and run the existing single/buffered/dirty-rectangle witnesses;
3. `DWEnd` and verify VIDEO plus MBO 0/1/2 are inactive;
4. `I$Close` the final window;
5. reopen `/w15`;
6. enter style-9 again and perform a buffered two-character alpha write;
7. `DWEnd` again and verify VIDEO plus MBO 0/1/2 are inactive;
8. `I$Close` again;
9. require `S2B6 STYLE9 REOPEN PASS` before the existing final PASS marker.

No guest ABI, R1K command format, MBO layout, native-video contract, or shared
machine architecture changes.
