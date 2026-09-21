********************************************************************
* scgrfprobe - S2B-1 production CoWin/GrfDrv lifecycle witness
*
* Opens /w15, creates DWSet style 9 through the normal CoWin escape path,
* verifies GIME-NG/MBO ownership through the shared S1 service layer, then
* performs normal DWEnd and proves the resources drained.
********************************************************************

                    nam       scgrfprobe
                    ttl       SuperCoCo S2B-1 GrfDrv lifecycle probe

                    ifp1
                    use       defsfile
                    use       supercoco.d
                    endc

rev                 set       $00
edition             set       1
tylg                set       Prgrm+Objct
atrv                set       ReEnt+rev

                    mod       eom,name,tylg,atrv,start,size

                    org       0
winPath             rmb       1
winOpen             rmb       1
stackSpace          rmb       192
size                equ       .

name                fcs       /scgrfprobe/
                    fcb       edition

pathW15             fcc       @/w15@
                    fcb       C$CR

* ESC $20 DWSet, style 9, x=0 y=0, 80x60 chars, fg=15 bg=0 border=0.
dwset9              fcb       $1B,$20,$09,$00,$00,$50,$3C,$0F,$00,$00
dwset9Len           equ       *-dwset9

dwend               fcb       $1B,$24
dwendLen            equ       *-dwend

msgPass             fcc       /SuperCoCo S2B-1 GrfDrv lifecycle PASS/
                    fcb       C$CR
msgPassLen          equ       *-msgPass
msgFail             fcc       /scgrfprobe: S2B-1 lifecycle FAIL/
                    fcb       C$CR
msgFailLen          equ       *-msgFail

start               clr       winOpen,u
                    leax      pathW15,pcr
                    lda       #3                  update mode
                    os9       I$Open
                    lbcs      fail
                    sta       winPath,u
                    inc       winOpen,u

                    leax      dwset9,pcr
                    ldy       #dwset9Len
                    lda       winPath,u
                    os9       I$Write
                    lbcs      failCleanup

* The production path must have enabled GIME-NG surface 0.
                    ldx       #SC.VideoActiveSurface
                    lbsr      SC_READ8
                    lbcs      failCleanup
                    tsta
                    lbne      failCleanup

* Front framebuffer is busy; back framebuffer is valid but not busy.
                    ldb       #0
                    lbsr      SC_MBO_STATUS
                    lbcs      failCleanup
                    bita      #SC.MBOStatusValid
                    lbeq      failCleanup
                    bita      #SC.MBOStatusBusy
                    lbeq      failCleanup
                    ldb       #1
                    lbsr      SC_MBO_STATUS
                    lbcs      failCleanup
                    bita      #SC.MBOStatusValid
                    lbeq      failCleanup
                    bita      #SC.MBOStatusBusy
                    lbne      failCleanup

* Normal CoWin DWEnd owns teardown; no private service backdoor is used.
                    leax      dwend,pcr
                    ldy       #dwendLen
                    lda       winPath,u
                    os9       I$Write
                    lbcs      failClose

                    ldx       #SC.VideoActiveSurface
                    lbsr      SC_READ8
                    lbcs      failClose
                    cmpa      #$FF
                    lbne      failClose
                    ldb       #0
                    lbsr      SC_MBO_STATUS
                    lbcs      failClose
                    bita      #SC.MBOStatusValid!SC.MBOStatusBusy
                    lbne      failClose
                    ldb       #1
                    lbsr      SC_MBO_STATUS
                    lbcs      failClose
                    bita      #SC.MBOStatusValid!SC.MBOStatusBusy
                    lbne      failClose

                    lda       winPath,u
                    os9       I$Close
                    clr       winOpen,u
                    leax      msgPass,pcr
                    ldy       #msgPassLen
                    lda       #1
                    os9       I$WritLn
                    clrb
                    os9       F$Exit

failCleanup         leax      dwend,pcr
                    ldy       #dwendLen
                    lda       winPath,u
                    os9       I$Write
failClose           lda       winOpen,u
                    lbeq      fail
                    lda       winPath,u
                    os9       I$Close
                    clr       winOpen,u
fail                leax      msgFail,pcr
                    ldy       #msgFailLen
                    lda       #1
                    os9       I$WritLn
                    ldb       #E$NotRdy
                    os9       F$Exit

* Shared S1 common service helpers.
                    use       ../libs/scsys/scsys.inc

                    emod
eom                 equ       *
                    end
