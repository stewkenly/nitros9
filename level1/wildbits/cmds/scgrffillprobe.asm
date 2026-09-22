********************************************************************
* scgrffillprobe - S2B-2 normal GrfDrv CLS -> R1K FILL witness
********************************************************************

                    nam       scgrffillprobe
                    ttl       SuperCoCo S2B-2 R1K CLS fill probe

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

name                fcs       /scgrffillprobe/
                    fcb       edition

pathW15             fcc       @/w15@
                    fcb       C$CR

* ESC $20 DWSet, style 9, x=0 y=0, 80x60 chars, fg=15 bg=0 border=0.
dwset9              fcb       $1B,$20,$09,$00,$00,$50,$3C,$0F,$00,$00
dwset9Len           equ       *-dwset9

* CoWin command $33 is BColor; control $0C is normal CLS.
bcolor5             fcb       $1B,$33,$05
bcolor5Len          equ       *-bcolor5
clsCode             fcb       $0C
clsCodeLen          equ       *-clsCode
bcolor10            fcb       $1B,$33,$0A
bcolor10Len         equ       *-bcolor10

dwend               fcb       $1B,$24
dwendLen            equ       *-dwend

msgDWSet            fcc       /S2B2 R1K DWSET PASS/
                    fcb       C$CR
msgDWSetLen         equ       *-msgDWSet
msgBColor1          fcc       /S2B2 R1K BCOLOR1 PASS/
                    fcb       C$CR
msgBColor1Len       equ       *-msgBColor1
msgCLS1             fcc       /S2B2 R1K CLS1 RETURN PASS/
                    fcb       C$CR
msgCLS1Len          equ       *-msgCLS1
msgBColor2          fcc       /S2B2 R1K BCOLOR2 PASS/
                    fcb       C$CR
msgBColor2Len       equ       *-msgBColor2
msgCLS2             fcc       /S2B2 R1K CLS2 RETURN PASS/
                    fcb       C$CR
msgCLS2Len          equ       *-msgCLS2
msgFill1            fcc       /S2B2 R1K CLS FILL1 PASS/
                    fcb       C$CR
msgFill1Len         equ       *-msgFill1
msgFill2            fcc       /S2B2 R1K CLS FILL2 PASS/
                    fcb       C$CR
msgFill2Len         equ       *-msgFill2
msgPass             fcc       /SuperCoCo S2B-2 R1K CLS fill PASS/
                    fcb       C$CR
msgPassLen          equ       *-msgPass
msgFail             fcc       /scgrffillprobe: S2B-2 R1K CLS fill FAIL/
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

* S2B-1 front/back state plus the new command MBO must be ready.
                    ldx       #SC.VideoActiveSurface
                    lbsr      SC_READ8
                    lbcs      failCleanup
                    tsta
                    lbne      failCleanup
                    ldb       #2
                    lbsr      SC_MBO_STATUS
                    lbcs      failCleanup
                    bita      #SC.MBOStatusValid
                    lbeq      failCleanup
                    bita      #SC.MBOStatusBusy
                    lbne      failCleanup
                    leax      msgDWSet,pcr
                    ldy       #msgDWSetLen
                    lda       #1
                    os9       I$WritLn

* Normal BColor + normal control-code CLS.  The driver synchronously waits
* for MEDIA completion and then presents the completed back buffer at VBLANK.
                    leax      bcolor5,pcr
                    ldy       #bcolor5Len
                    lda       winPath,u
                    os9       I$Write
                    lbcs      failCleanup
                    leax      msgBColor1,pcr
                    ldy       #msgBColor1Len
                    lda       #1
                    os9       I$WritLn
                    leax      clsCode,pcr
                    ldy       #clsCodeLen
                    lda       winPath,u
                    os9       I$Write
                    lbcs      failCleanup
                    leax      msgCLS1,pcr
                    ldy       #msgCLS1Len
                    lda       #1
                    os9       I$WritLn

                    lda       #1
                    lbsr      verifyFront
                    lbcs      failCleanup
                    leax      msgFill1,pcr
                    ldy       #msgFill1Len
                    lda       #1
                    os9       I$WritLn

* Exercise the same command MBO and alternate back surface a second time.
                    leax      bcolor10,pcr
                    ldy       #bcolor10Len
                    lda       winPath,u
                    os9       I$Write
                    lbcs      failCleanup
                    leax      msgBColor2,pcr
                    ldy       #msgBColor2Len
                    lda       #1
                    os9       I$WritLn
                    leax      clsCode,pcr
                    ldy       #clsCodeLen
                    lda       winPath,u
                    os9       I$Write
                    lbcs      failCleanup
                    leax      msgCLS2,pcr
                    ldy       #msgCLS2Len
                    lda       #1
                    os9       I$WritLn

                    clra
                    lbsr      verifyFront
                    lbcs      failCleanup
                    leax      msgFill2,pcr
                    ldy       #msgFill2Len
                    lda       #1
                    os9       I$WritLn

* Normal CoWin DWEnd must release display, both framebuffers and command MBO.
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
* Verify one completed synchronous CLS.
* Entry A = expected active surface (0 or 1).
********************************************************************
verifyFront         pshs      a
                    ldx       #SC.VideoActiveSurface
                    lbsr      SC_READ8
                    lbcs      vfBadDrop
                    cmpa      ,s
                    lbne      vfBadDrop

* MEDIA Job V1 must have been independently ACKed back to IDLE.
                    ldx       #SC.MediaJobBase+SC.JobStateO
                    lbsr      SC_READ8
                    lbcs      vfBadDrop
                    cmpa      #SC.JobIdle
                    lbne      vfBadDrop

* Driver also independently W1C-clears the MEDIA terminal event.
                    lbsr      SC_IRQ_GET
                    bita      #SC.IRQMedia
                    lbne      vfBadDrop

* Command MBO remains reusable and unbound after command snapshot/completion.
                    ldb       #2
                    lbsr      SC_MBO_STATUS
                    lbcs      vfBadDrop
                    bita      #SC.MBOStatusValid
                    lbeq      vfBadDrop
                    bita      #SC.MBOStatusBusy
                    lbne      vfBadDrop

* Exactly the active display framebuffer is busy after the VBLANK flip.
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
