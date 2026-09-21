# SuperCoCo S2B-1 Runtime Gate

This retained candidate gate proves the first production NitrOS-9 graphics
lifecycle seam through the normal window stack:

`/w15 -> CoWin DWSet style 9 -> GrfDrv -> GIME-NG/MBO -> DWEnd`

The gate intentionally rebuilds a real Level-2 bootfile so the test cannot
accidentally run an older CoWin from the base VHD.  It then replaces the
production `CMDS/grfdrv`, installs `scgrfprobe`, runs the witness during normal
startup, rejects D.Crash, and requires the lifecycle PASS marker.

S2B-1 remains a lifecycle milestone.  Drawing dispatch through R1K follows only
after this ownership/presentation/teardown seam is runtime-proven.
