********************************************************************
* scgrfbarprobe - S2B-3 normal GrfDrv BAR -> R1K FILL witness
********************************************************************

                    nam       scgrfbarprobe
                    ttl       SuperCoCo S2B-3 R1K BAR fill probe

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

name                fcs       /scgrfbarprobe/
                    fcb       edition

pathW15             fcc       @/w15@
                    fcb       C$CR

* style 9, full 640x480 window
* ESC $20 DWSet, x=0 y=0, 80x60 chars, fg=15 bg=0 border=0.
dwset9              fcb       $1B,$20,$09,$00,$00,$50,$3C,$0F,$00,$00
dwset9Len           equ       *-dwset9
bcolor2             fcb       $1B,$33,$02
bcolor2Len          equ       *-bcolor2
clsCode             fcb       $0C
clsCodeLen          equ       *-clsCode

* FColor is external ESC $32.  SetDP is ESC $40.  BAR is ESC $4A.
* BAR1 deliberately starts/ends on opposite INDEX4 nibbles so the witness can
* prove neighboring pixels survive the accelerator's read-modify-write path.
fcolor7             fcb       $1B,$32,$07
fcolor7Len          equ       *-fcolor7
setdp1              fcb       $1B,$40,$00,$11,$00,$08       x=17,y=8
setdp1Len           equ       *-setdp1
bar1                fcb       $1B,$4A,$00,$2E,$00,$0F       x=46,y=15
bar1Len             equ       *-bar1

* BAR2 supplies its destination backwards; GrfDrv must normalize 99,12 -> 80,4.
fcolor10            fcb       $1B,$32,$0A
fcolor10Len         equ       *-fcolor10
setdp2              fcb       $1B,$40,$00,$63,$00,$0C       x=99,y=12
setdp2Len           equ       *-setdp2
bar2                fcb       $1B,$4A,$00,$50,$00,$04       x=80,y=4
bar2Len             equ       *-bar2

dwend               fcb       $1B,$24
dwendLen            equ       *-dwend

msgBase             fcc       /S2B3 R1K BASE CLS PASS/
                    fcb       C$CR
msgBaseLen          equ       *-msgBase
msgBar1             fcc       /S2B3 R1K BAR1 PASS/
                    fcb       C$CR
msgBar1Len          equ       *-msgBar1
msgBar2             fcc       /S2B3 R1K BAR2 PASS/
                    fcb       C$CR
msgBar2Len          equ       *-msgBar2
msgMirror           fcc       /S2B3 R1K MIRROR PASS/
                    fcb       C$CR
msgMirrorLen        equ       *-msgMirror
msgPass             fcc       /SuperCoCo S2B-3 R1K BAR fill PASS/
                    fcb       C$CR
msgPassLen          equ       *-msgPass
msgFail             fcc       /scgrfbarprobe: S2B-3 R1K BAR fill FAIL/
                    fcb       C$CR
msgFailLen          equ       *-msgFail

start               clr       winOpen,u
                    leax      pathW15,pcr
                    lda       #3
                    os9       I$Open
                    lbcs      fail
                    sta       winPath,u
                    inc       winOpen,u

                    leax      dwset9,pcr
                    ldy       #dwset9Len
                    lda       winPath,u
                    os9       I$Write
                    lbcs      failCleanup

* Establish a known mirrored background through the ordinary BColor+CLS path.
                    leax      bcolor2,pcr
                    ldy       #bcolor2Len
                    lda       winPath,u
                    os9       I$Write
                    lbcs      failCleanup
                    leax      clsCode,pcr
                    ldy       #clsCodeLen
                    lda       winPath,u
                    os9       I$Write
                    lbcs      failCleanup
                    lda       #1
                    lbsr      verifyFront
                    lbcs      failCleanup
                    leax      msgBase,pcr
                    ldy       #msgBaseLen
                    lda       #1
                    os9       I$WritLn

* First normal BAR: color 7, (17,8) through (46,15).
                    leax      fcolor7,pcr
                    ldy       #fcolor7Len
                    lda       winPath,u
                    os9       I$Write
                    lbcs      failCleanup
                    leax      setdp1,pcr
                    ldy       #setdp1Len
                    lda       winPath,u
                    os9       I$Write
                    lbcs      failCleanup
                    leax      bar1,pcr
                    ldy       #bar1Len
                    lda       winPath,u
                    os9       I$Write
                    lbcs      failCleanup
                    clra
                    lbsr      verifyFront
                    lbcs      failCleanup
                    leax      msgBar1,pcr
                    ldy       #msgBar1Len
                    lda       #1
                    os9       I$WritLn

* Second normal BAR: color 10, reversed coordinates normalize to 80..99,4..12.
                    leax      fcolor10,pcr
                    ldy       #fcolor10Len
                    lda       winPath,u
                    os9       I$Write
                    lbcs      failCleanup
                    leax      setdp2,pcr
                    ldy       #setdp2Len
                    lda       winPath,u
                    os9       I$Write
                    lbcs      failCleanup
                    leax      bar2,pcr
                    ldy       #bar2Len
                    lda       winPath,u
                    os9       I$Write
                    lbcs      failCleanup
                    lda       #1
                    lbsr      verifyFront
                    lbcs      failCleanup
                    leax      msgBar2,pcr
                    ldy       #msgBar2Len
                    lda       #1
                    os9       I$WritLn

* Both framebuffer MBOs must contain the same exact image after the API returns.
                    ldb       #0
                    lbsr      verifyOneFB
                    lbcs      failCleanup
                    ldb       #1
                    lbsr      verifyOneFB
                    lbcs      failCleanup
                    leax      msgMirror,pcr
                    ldy       #msgMirrorLen
                    lda       #1
                    os9       I$WritLn

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
                    ldb       #2
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

********************************************************************
* Verify completion/ownership state after one synchronous semantic operation.
* Entry A = expected active surface.
********************************************************************
verifyFront         pshs      a
                    ldx       #SC.VideoActiveSurface
                    lbsr      SC_READ8
                    lbcs      vfBadDrop
                    cmpa      ,s
                    lbne      vfBadDrop
                    ldx       #SC.MediaJobBase+SC.JobStateO
                    lbsr      SC_READ8
                    lbcs      vfBadDrop
                    cmpa      #SC.JobIdle
                    lbne      vfBadDrop
                    lbsr      SC_IRQ_GET
                    bita      #SC.IRQMedia
                    lbne      vfBadDrop
                    ldb       #2
                    lbsr      SC_MBO_STATUS
                    lbcs      vfBadDrop
                    bita      #SC.MBOStatusValid
                    lbeq      vfBadDrop
                    bita      #SC.MBOStatusBusy
                    lbne      vfBadDrop
                    lda       ,s
                    beq       vfFront0
                    ldb       #1
                    lbsr      SC_MBO_STATUS
                    lbcs      vfBadDrop
                    anda      #SC.MBOStatusValid!SC.MBOStatusBusy
                    cmpa      #SC.MBOStatusValid!SC.MBOStatusBusy
                    lbne      vfBadDrop
                    ldb       #0
                    lbsr      SC_MBO_STATUS
                    lbcs      vfBadDrop
                    bita      #SC.MBOStatusValid
                    lbeq      vfBadDrop
                    bita      #SC.MBOStatusBusy
                    lbne      vfBadDrop
                    bra       vfGood
vfFront0            ldb       #0
                    lbsr      SC_MBO_STATUS
                    lbcs      vfBadDrop
                    anda      #SC.MBOStatusValid!SC.MBOStatusBusy
                    cmpa      #SC.MBOStatusValid!SC.MBOStatusBusy
                    lbne      vfBadDrop
                    ldb       #1
                    lbsr      SC_MBO_STATUS
                    lbcs      vfBadDrop
                    bita      #SC.MBOStatusValid
                    lbeq      vfBadDrop
                    bita      #SC.MBOStatusBusy
                    lbne      vfBadDrop
vfGood              leas      1,s
                    clrb
                    andcc     #^Carry
                    rts
vfBadDrop           leas      1,s
                    ldb       #E$NotRdy
                    orcc      #Carry
                    rts

********************************************************************
* Read the first physical 8K block of one framebuffer MBO through a mapping
* owned by this probe process.  Both buffers must contain the same final image.
* Entry B = framebuffer MBO slot 0 or 1.
********************************************************************
verifyOneFB         pshs      x,y,u
                    lbsr      SC_MBO_BASE
                    lbcs      vofBad
                    leax      SC.MBOPageListO,x
                    lbsr      SC_READ16LE         D = first 4K PPN
                    lbcs      vofBad
                    bitb      #$01                must be first half of an 8K NitrOS block
                    lbne      vofBad
                    lsra
                    rorb                          D = NitrOS 8K block number
                    tfr       d,x
                    ldb       #1
                    os9       F$MapBlk
                    lbcs      vofBad
                    tfr       u,x                 X = mapped framebuffer base

* untouched background
                    lda       $0000,x
                    cmpa      #$22
                    lbne      vofMappedBad
* BAR1 x=17..46 at y=8..15.  Boundary bytes prove neighboring nibble preserve.
                    lda       $0A07,x             x=14/15, outside
                    cmpa      #$22
                    lbne      vofMappedBad
                    lda       $0A08,x             x=16 bg, x=17 color7
                    cmpa      #$27
                    lbne      vofMappedBad
                    lda       $0A09,x             interior x=18/19
                    cmpa      #$77
                    lbne      vofMappedBad
                    lda       $12D7,x             y=15, x=46 color7, x=47 bg
                    cmpa      #$72
                    lbne      vofMappedBad
                    lda       $0A18,x             x=48/49, outside
                    cmpa      #$22
                    lbne      vofMappedBad
* BAR2 normalized x=80..99, y=4..12.
                    lda       $0527,x             x=78/79, outside
                    cmpa      #$22
                    lbne      vofMappedBad
                    lda       $0528,x             x=80/81
                    cmpa      #$AA
                    lbne      vofMappedBad
                    lda       $0F31,x             y=12, x=98/99
                    cmpa      #$AA
                    lbne      vofMappedBad
                    lda       $0532,x             x=100/101, outside
                    cmpa      #$22
                    lbne      vofMappedBad

                    ldb       #1
                    os9       F$ClrBlk
                    lbcs      vofBad
                    puls      x,y,u
                    clrb
                    andcc     #^Carry
                    rts
vofMappedBad        ldb       #1
                    os9       F$ClrBlk            best-effort unmap before failure
vofBad              puls      x,y,u
                    ldb       #E$NotRdy
                    orcc      #Carry
                    rts

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

                    use       ../libs/scsys/scsys.inc

                    emod
eom                 equ       *
                    end
