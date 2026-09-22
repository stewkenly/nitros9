********************************************************************
* scgrfblitprobe - S2B-4 normal BAR mirror -> R1K BLIT witness
********************************************************************

                    nam       scgrfblitprobe
                    ttl       SuperCoCo S2B-4 R1K BLIT mirror probe

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

name                fcs       /scgrfblitprobe/
                    fcb       edition

pathW15             fcc       @/w15@
                    fcb       C$CR

dwset9              fcb       $1B,$20,$09,$00,$00,$50,$3C,$0F,$00,$00
dwset9Len           equ       *-dwset9
bcolor2             fcb       $1B,$33,$02
bcolor2Len          equ       *-bcolor2
clsCode             fcb       $0C
clsCodeLen          equ       *-clsCode
fcolor7             fcb       $1B,$32,$07
fcolor7Len          equ       *-fcolor7
setdp1              fcb       $1B,$40,$00,$11,$00,$08       x=17,y=8
setdp1Len           equ       *-setdp1
bar1                fcb       $1B,$4A,$00,$2E,$00,$0F       x=46,y=15
bar1Len             equ       *-bar1
fcolor10            fcb       $1B,$32,$0A
fcolor10Len         equ       *-fcolor10
setdp2              fcb       $1B,$40,$00,$63,$00,$0C       x=99,y=12
setdp2Len           equ       *-setdp2
bar2                fcb       $1B,$4A,$00,$50,$00,$04       x=80,y=4
bar2Len             equ       *-bar2
dwend               fcb       $1B,$24
dwendLen            equ       *-dwend

msgBlit0            fcc       /S2B4 R1K BLIT0 PASS/
                    fcb       C$CR
msgBlit0Len         equ       *-msgBlit0
msgBlit1            fcc       /S2B4 R1K BLIT1 PASS/
                    fcb       C$CR
msgBlit1Len         equ       *-msgBlit1
msgMirror           fcc       /S2B4 R1K MIRROR PASS/
                    fcb       C$CR
msgMirrorLen        equ       *-msgMirror
msgPass             fcc       /SuperCoCo S2B-4 R1K BLIT mirror PASS/
                    fcb       C$CR
msgPassLen          equ       *-msgPass
msgFail             fcc       /scgrfblitprobe: S2B-4 R1K BLIT mirror FAIL/
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

* BAR1 flips 1 -> 0; final mirror BLIT must be source 0, destination 1.
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
                    clra
                    lbsr      verifyBlitCmd
                    lbcs      failCleanup
                    leax      msgBlit0,pcr
                    ldy       #msgBlit0Len
                    lda       #1
                    os9       I$WritLn

* BAR2 flips 0 -> 1; final mirror BLIT must be source 1, destination 0.
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
                    lda       #1
                    lbsr      verifyBlitCmd
                    lbcs      failCleanup
                    leax      msgBlit1,pcr
                    ldy       #msgBlit1Len
                    lda       #1
                    os9       I$WritLn

* Both framebuffer images must still be exactly mirrored after BLIT.
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
* Verify terminal state and sole VIDEO binding on expected active surface.
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
* Inspect final command-MBO record after a BAR.
* Entry A = expected BLIT source slot (active surface); destination is A^1.
* Preserve A on the system stack because F$MapBlk returns the mapped address
* in U; using probe locals through U after the syscall would read the map.
********************************************************************
verifyBlitCmd       pshs      x,y,u
                    pshs      a                   preserve expected source across F$MapBlk
                    ldb       #2
                    lbsr      SC_MBO_BASE
                    lbcs      vbcBad
                    leax      SC.MBOPageListO,x
                    lbsr      SC_READ16LE
                    lbcs      vbcBad
                    bitb      #$01
                    lbne      vbcBad
                    lsra
                    rorb
                    tfr       d,x
                    ldb       #1
                    os9       F$MapBlk
                    lbcs      vbcBad
                    tfr       u,x

                    lda       SC.GfxCmdABIMajorO,x
                    cmpa      #1
                    lbne      vbcMappedBad
                    lda       SC.GfxCmdOperationO,x
                    cmpa      #SC.GraphicsOpBlit
                    lbne      vbcMappedBad
                    lda       SC.GfxCmdSourceO,x
                    cmpa      ,s                  expected source saved on system stack
                    lbne      vbcMappedBad
                    lda       SC.GfxCmdSourceO+1,x
                    cmpa      #SC.GraphicsFmtIndex4
                    lbne      vbcMappedBad
                    lda       ,s                  expected source saved on system stack
                    eora      #1
                    cmpa      SC.GfxCmdDestO,x
                    lbne      vbcMappedBad
                    lda       SC.GfxCmdDestO+1,x
                    cmpa      #SC.GraphicsFmtIndex4
                    lbne      vbcMappedBad

                    ldd       SC.GfxCmdSrcXO,x
                    lbne      vbcMappedBad
                    ldd       SC.GfxCmdSrcYO,x
                    lbne      vbcMappedBad
                    ldd       SC.GfxCmdDstXO,x
                    lbne      vbcMappedBad
                    ldd       SC.GfxCmdDstYO,x
                    lbne      vbcMappedBad
                    ldd       SC.GfxCmdWidthO,x
                    cmpd      #$8002              LE bytes for 640
                    lbne      vbcMappedBad
                    ldd       SC.GfxCmdHeightO,x
                    cmpd      #$E001              LE bytes for 480
                    lbne      vbcMappedBad

                    ldb       #1
                    os9       F$ClrBlk
                    lbcs      vbcBad
                    leas      1,s                 drop saved expected source
                    puls      x,y,u
                    clrb
                    andcc     #^Carry
                    rts
vbcMappedBad        ldb       #1
                    os9       F$ClrBlk
vbcBad              leas      1,s                 drop saved expected source
                    puls      x,y,u
                    ldb       #E$NotRdy
                    orcc      #Carry
                    rts

********************************************************************
* Pixel witness inherited from S2B-3.  Both MBOs must contain the same image.
* Entry B = framebuffer MBO slot 0 or 1.
********************************************************************
verifyOneFB         pshs      x,y,u
                    lbsr      SC_MBO_BASE
                    lbcs      vofBad
                    leax      SC.MBOPageListO,x
                    lbsr      SC_READ16LE
                    lbcs      vofBad
                    bitb      #$01
                    lbne      vofBad
                    lsra
                    rorb
                    tfr       d,x
                    ldb       #1
                    os9       F$MapBlk
                    lbcs      vofBad
                    tfr       u,x
                    lda       $0000,x
                    cmpa      #$22
                    lbne      vofMappedBad
                    lda       $0A08,x
                    cmpa      #$27
                    lbne      vofMappedBad
                    lda       $0A09,x
                    cmpa      #$77
                    lbne      vofMappedBad
                    lda       $12D7,x
                    cmpa      #$72
                    lbne      vofMappedBad
                    lda       $0528,x
                    cmpa      #$AA
                    lbne      vofMappedBad
                    lda       $0F31,x
                    cmpa      #$AA
                    lbne      vofMappedBad
                    ldb       #1
                    os9       F$ClrBlk
                    lbcs      vofBad
                    puls      x,y,u
                    clrb
                    andcc     #^Carry
                    rts
vofMappedBad        ldb       #1
                    os9       F$ClrBlk
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
