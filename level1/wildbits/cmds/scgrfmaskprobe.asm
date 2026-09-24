********************************************************************
* scgrfmaskprobe - S2B-5 normal alpha text -> R1K MASKED_BLIT witness
********************************************************************

                    nam       scgrfmaskprobe
                    ttl       SuperCoCo S2B-5 R1K masked alpha probe

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
activeSurf          rmb       1
maskKey             rmb       1
sawFore             rmb       1
sawKey              rmb       1
rowCount            rmb       1
cellOffset          rmb       1
cellCount           rmb       1
cmdMap              rmb       2
glyphCopy           rmb       32
stackSpace          rmb       224
size                equ       .

name                fcs       /scgrfmaskprobe/
                    fcb       edition

pathW15             fcc       @/w15@
                    fcb       C$CR

* Full style-9 640x480 window.
dwset9              fcb       $1B,$20,$09,$00,$00,$50,$3C,$0F,$00,$00
dwset9Len           equ       *-dwset9
bcolor2             fcb       $1B,$33,$02
bcolor2Len          equ       *-bcolor2
clsCode             fcb       $0C
clsCodeLen          equ       *-clsCode

* Paint an 8x8 color-10 backing tile at x=0,y=0 through the normal BAR path.
fcolor10            fcb       $1B,$32,$0A
fcolor10Len         equ       *-fcolor10
setdp0              fcb       $1B,$40,$00,$00,$00,$00
setdp0Len           equ       *-setdp0
barBacking          fcb       $1B,$4A,$00,$17,$00,$07
barBackingLen       equ       *-barBacking

* Transparent alpha text: CoWin external escape $3C maps to TCharSw.  Parameter
* 1 clears TChr and enables transparent glyph semantics.
fcolor7             fcb       $1B,$32,$07
fcolor7Len          equ       *-fcolor7
tcharOn             fcb       $1B,$3C,$01
tcharOnLen          equ       *-tcharOn
alphaA              fcb       'A'
alphaALen           equ       *-alphaA
alphaBC             fcc       /BC/
alphaBCLen          equ       *-alphaBC

dwend               fcb       $1B,$24
dwendLen            equ       *-dwend

msgCmd              fcc       /S2B5 R1K MASKED CMD PASS/
                    fcb       C$CR
msgCmdLen           equ       *-msgCmd
msgPixels           fcc       /S2B5 R1K MASK PRESERVE PASS/
                    fcb       C$CR
msgPixelsLen        equ       *-msgPixels
msgSingle           fcc       /S2B5 R1K SINGLE CHAR0 PASS/
                    fcb       C$CR
msgSingleLen        equ       *-msgSingle
msgBuffered         fcc       /S2B5 R1K BUFFERED BC PASS/
                    fcb       C$CR
msgBufferedLen      equ       *-msgBuffered
msgMirror           fcc       /S2B5 R1K MIRROR PASS/
                    fcb       C$CR
msgMirrorLen        equ       *-msgMirror
msgPass             fcc       /SuperCoCo S2B-5 R1K masked alpha PASS/
                    fcb       C$CR
msgPassLen          equ       *-msgPass
msgFail             fcc       /scgrfmaskprobe: S2B-5 R1K masked alpha FAIL/
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

* Establish three non-background 8x8 backing cells at x=0..23 so both the
* single-character and two-character buffered witnesses must preserve real
* destination pixels rather than merely copying the window background.
                    leax      fcolor10,pcr
                    ldy       #fcolor10Len
                    lda       winPath,u
                    os9       I$Write
                    lbcs      failCleanup
                    leax      setdp0,pcr
                    ldy       #setdp0Len
                    lda       winPath,u
                    os9       I$Write
                    lbcs      failCleanup
                    leax      barBacking,pcr
                    ldy       #barBackingLen
                    lda       winPath,u
                    os9       I$Write
                    lbcs      failCleanup

* Normal CoWin character output at the untouched text cursor x=0,y=0.  No
* private driver entry is called; SetDP above changed only the graphics cursor.
                    leax      fcolor7,pcr
                    ldy       #fcolor7Len
                    lda       winPath,u
                    os9       I$Write
                    lbcs      failCleanup
                    leax      tcharOn,pcr
                    ldy       #tcharOnLen
                    lda       winPath,u
                    os9       I$Write
                    lbcs      failCleanup
                    leax      alphaA,pcr
                    ldy       #alphaALen
                    lda       winPath,u
                    os9       I$Write
                    lbcs      failCleanup

* Record 0 must remain the MASKED_BLIT command; record 1 must retain the
* post-present full-frame BLIT mirror command.  Copy the staged glyph locally.
                    lbsr      verifyCommands
                    lbcs      failCleanup
                    leax      msgCmd,pcr
                    ldy       #msgCmdLen
                    lda       #1
                    os9       I$WritLn

* Both framebuffer MBOs must contain foreground 7 where glyph bits are one and
* preserved backing color 10 where the staged source contains the mask key.
                    ldb       #0
                    lbsr      verifyOneFB
                    lbcs      failCleanup
                    ldb       #1
                    lbsr      verifyOneFB
                    lbcs      failCleanup
                    leax      msgPixels,pcr
                    ldy       #msgPixelsLen
                    lda       #1
                    os9       I$WritLn
                    leax      msgSingle,pcr
                    ldy       #msgSingleLen
                    lda       #1
                    os9       I$WritLn

* Now issue one two-character buffered write.  Character B must occupy x=8 and
* character C x=16; losing character 0 of this transaction leaves the first
* cell all backing color and is caught by verifyBufferedFB.
                    leax      alphaBC,pcr
                    ldy       #alphaBCLen
                    lda       winPath,u
                    os9       I$Write
                    lbcs      failCleanup
                    ldb       #0
                    lbsr      verifyBufferedFB
                    lbcs      failCleanup
                    ldb       #1
                    lbsr      verifyBufferedFB
                    lbcs      failCleanup
                    leax      msgBuffered,pcr
                    ldy       #msgBufferedLen
                    lda       #1
                    os9       I$WritLn

                    lbsr      verifyFront
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

* DWEnd must drain/revoke all three style-9 MBOs.
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
* Inspect the retained alpha command, prove record 1 stayed unused, and copy the 32-byte glyph tile.
********************************************************************
verifyCommands      pshs      x,y,u
                    ldx       #SC.VideoActiveSurface
                    lbsr      SC_READ8
                    lbcs      vcBad
                    cmpa      #$FF
                    lbeq      vcBad
                    sta       activeSurf,u

                    ldb       #2
                    lbsr      SC_MBO_BASE
                    lbcs      vcBad
                    leax      SC.MBOPageListO,x
                    lbsr      SC_READ16LE
                    lbcs      vcBad
                    bitb      #$01
                    lbne      vcBad
                    lsra
                    rorb
                    tfr       d,x
                    pshs      u
                    ldb       #1
                    os9       F$MapBlk
                    lbcs      vcMapBad
                    tfr       u,x
                    ldy       ,s                  original program-static U
                    stx       cmdMap,y

* Record 0: replayed MASKED_BLIT from offset 128 now targets hidden mirror.
                    lda       SC.GfxCmdABIMajorO,x
                    cmpa      #1
                    lbne      vcMappedBad
                    lda       SC.GfxCmdOperationO,x
                    cmpa      #SC.GraphicsOpMasked
                    lbne      vcMappedBad
                    lda       SC.GfxCmdColorO,x
                    anda      #$0F
                    cmpa      #7
                    lbeq      vcMappedBad
                    cmpa      #10
                    lbeq      vcMappedBad
                    sta       maskKey,y
                    lda       SC.GfxCmdSourceO,x
                    cmpa      #2
                    lbne      vcMappedBad
                    lda       SC.GfxCmdSourceO+1,x
                    cmpa      #SC.GraphicsFmtIndex4
                    lbne      vcMappedBad
                    ldd       SC.GfxCmdSourceO+6,x
                    cmpd      #$8000              source offset low bytes = $80,$00
                    lbne      vcMappedBad
                    ldd       SC.GfxCmdSourceO+8,x
                    lbne      vcMappedBad
                    ldd       SC.GfxCmdSourceO+10,x
                    cmpd      #$0400              stride 4 little endian
                    lbne      vcMappedBad
                    ldd       SC.GfxCmdSourceO+12,x
                    cmpd      #$0800              width 8
                    lbne      vcMappedBad
                    ldd       SC.GfxCmdSourceO+14,x
                    cmpd      #$0800              height 8
                    lbne      vcMappedBad
                    lda       activeSurf,y
                    eora      #1
                    cmpa      SC.GfxCmdDestO,x
                    lbne      vcMappedBad
                    lda       SC.GfxCmdDestO+1,x
                    cmpa      #SC.GraphicsFmtIndex4
                    lbne      vcMappedBad
                    ldd       SC.GfxCmdDestO+10,x
                    cmpd      #$4001              stride 320 little endian
                    lbne      vcMappedBad
                    ldd       SC.GfxCmdDstXO,x
                    lbne      vcMappedBad         x=0
                    ldd       SC.GfxCmdDstYO,x
                    lbne      vcMappedBad
                    ldd       SC.GfxCmdWidthO,x
                    cmpd      #$0800
                    lbne      vcMappedBad
                    ldd       SC.GfxCmdHeightO,x
                    cmpd      #$0800
                    lbne      vcMappedBad

* Preserve glyph source and prove it actually contains both foreground and key.
                    clr       sawFore,y
                    clr       sawKey,y
                    ldx       cmdMap,y
                    leax      128,x
                    leau      glyphCopy,y
                    ldb       #32
vcGlyphCopy         lda       ,x+
                    sta       ,u+
                    pshs      a
                    anda      #$F0
                    lsra
                    lsra
                    lsra
                    lsra
                    cmpa      maskKey,y
                    lbeq      vcGlyphHighKey
                    cmpa      #7
                    lbne      vcGlyphStackBad
                    inc       sawFore,y
                    lbra      vcGlyphLow
vcGlyphHighKey      inc       sawKey,y
vcGlyphLow          lda       ,s
                    anda      #$0F
                    cmpa      maskKey,y
                    lbeq      vcGlyphLowKey
                    cmpa      #7
                    lbne      vcGlyphStackBad
                    inc       sawFore,y
                    lbra      vcGlyphNext
vcGlyphLowKey       inc       sawKey,y
vcGlyphNext         leas      1,s
                    decb
                    lbne      vcGlyphCopy
                    tst       sawFore,y
                    lbeq      vcMappedBad
                    tst       sawKey,y
                    lbeq      vcMappedBad

* S2B-6 alpha replay reuses record 0.  Record 1 must remain untouched, proving
* the old 640x480 per-glyph mirror transaction did not run.
                    ldx       cmdMap,y
                    leax      64,x
                    lda       SC.GfxCmdOperationO,x
                    lbne      vcMappedBad

                    ldu       cmdMap,y            restore verifyCommands map for F$ClrBlk
                    ldb       #1
                    os9       F$ClrBlk
                    lbcs      vcInnerBad
                    puls      u
                    puls      x,y,u
                    clrb
                    andcc     #^Carry
                    rts
vcGlyphStackBad     leas      1,s
vcMappedBad         ldu       cmdMap,y            restore verifyCommands map before unmap
                    ldb       #1
                    os9       F$ClrBlk
vcInnerBad          puls      u
vcBad               puls      x,y,u
                    ldb       #E$NotRdy
                    orcc      #Carry
                    rts
vcMapBad            puls      u
                    lbra      vcBad

********************************************************************
* Compare one framebuffer's 8x8 alpha result against the staged source.
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
                    pshs      u
                    ldb       #1
                    os9       F$MapBlk
                    lbcs      vofMapBad
                    tfr       u,x
                    ldy       ,s                  original program-static U
                    stu       cmdMap,y            preserve F$MapBlk U for F$ClrBlk

* Immediately right of the single-character tile the prepainted backing cell
* must still be color 10 before the buffered BC transaction is issued.
                    lda       4,x
                    cmpa      #$AA
                    lbne      vofMappedBad

* x=0 begins at byte 0.  For each staged source nibble: key means preserve
* backing color A; foreground means write 7.
                    leau      glyphCopy,y
                    lda       #8
                    sta       rowCount,y
vofRow              ldb       #4
vofByte             lda       ,u+
                    pshs      a
                    anda      #$F0
                    lsra
                    lsra
                    lsra
                    lsra
                    cmpa      maskKey,y
                    lbeq      vofHighBack
                    cmpa      #7
                    lbne      vofStackBad
                    lda       ,x
                    anda      #$F0
                    cmpa      #$70
                    lbne      vofStackBad
                    lbra      vofLow
vofHighBack         lda       ,x
                    anda      #$F0
                    cmpa      #$A0
                    lbne      vofStackBad
vofLow              lda       ,s
                    anda      #$0F
                    cmpa      maskKey,y
                    lbeq      vofLowBack
                    cmpa      #7
                    lbne      vofStackBad
                    lda       ,x
                    anda      #$0F
                    cmpa      #$07
                    lbne      vofStackBad
                    lbra      vofByteGood
vofLowBack          lda       ,x
                    anda      #$0F
                    cmpa      #$0A
                    lbne      vofStackBad
vofByteGood         leas      1,s
                    leax      1,x
                    decb
                    lbne      vofByte
                    leax      316,x               next row, x=0 byte position
                    dec       rowCount,y
                    lbne      vofRow

                    ldu       cmdMap,y            F$ClrBlk requires mapped address in U
                    ldb       #1
                    os9       F$ClrBlk
                    lbcs      vofInnerBad
                    puls      u
                    puls      x,y,u
                    clrb
                    andcc     #^Carry
                    rts
vofStackBad         leas      1,s
vofMappedBad        ldu       cmdMap,y            restore mapped address before unmap
                    ldb       #1
                    os9       F$ClrBlk
vofInnerBad         puls      u
vofBad              puls      x,y,u
                    ldb       #E$NotRdy
                    orcc      #Carry
                    rts
vofMapBad           puls      u
                    lbra      vofBad


********************************************************************
* Prove the two-character buffered transaction rendered both cells on one
* coherent R1K path.  Entry B = framebuffer MBO slot 0 or 1.  The single A
* already occupies x=0; buffered B and C must occupy x=8 and x=16.  Each cell
* must contain at least one foreground-7 nibble and one preserved backing-A
* nibble, and no other INDEX4 value is accepted.
********************************************************************
verifyBufferedFB    pshs      x,y,u
                    lbsr      SC_MBO_BASE
                    lbcs      vbfBad
                    leax      SC.MBOPageListO,x
                    lbsr      SC_READ16LE
                    lbcs      vbfBad
                    bitb      #$01
                    lbne      vbfBad
                    lsra
                    rorb
                    tfr       d,x
                    pshs      u
                    ldb       #1
                    os9       F$MapBlk
                    lbcs      vbfMapBad
                    tfr       u,x
                    ldy       ,s                  original program-static U
                    stx       cmdMap,y             reuse private probe pointer storage
                    lda       #4                  x=8 -> byte offset 4 in INDEX4
                    sta       cellOffset,y
                    lda       #2                  buffered B and C
                    sta       cellCount,y

vbfCell             clr       sawFore,y
                    clr       sawKey,y
                    lda       #8
                    sta       rowCount,y
                    ldx       cmdMap,y
                    ldb       cellOffset,y
                    abx
vbfRow              ldb       #4
vbfByte             lda       ,x
                    pshs      a
                    anda      #$F0
                    cmpa      #$70
                    lbeq      vbfHighFore
                    cmpa      #$A0
                    lbne      vbfStackBad
                    inc       sawKey,y
                    lbra      vbfLow
vbfHighFore         inc       sawFore,y
vbfLow              lda       ,s
                    anda      #$0F
                    cmpa      #$07
                    lbeq      vbfLowFore
                    cmpa      #$0A
                    lbne      vbfStackBad
                    inc       sawKey,y
                    lbra      vbfNibbleGood
vbfLowFore          inc       sawFore,y
vbfNibbleGood       leas      1,s
                    leax      1,x
                    decb
                    lbne      vbfByte
                    leax      316,x
                    dec       rowCount,y
                    lbne      vbfRow
                    tst       sawFore,y
                    lbeq      vbfMappedBad
                    tst       sawKey,y
                    lbeq      vbfMappedBad
                    lda       cellOffset,y
                    adda      #4
                    sta       cellOffset,y
                    dec       cellCount,y
                    lbne      vbfCell

                    ldb       #1
                    os9       F$ClrBlk
                    lbcs      vbfInnerBad
                    puls      u
                    puls      x,y,u
                    clrb
                    andcc     #^Carry
                    rts
vbfStackBad         leas      1,s
vbfMappedBad        ldb       #1
                    os9       F$ClrBlk
vbfInnerBad         puls      u
vbfBad              puls      x,y,u
                    ldb       #E$NotRdy
                    orcc      #Carry
                    rts
vbfMapBad           puls      u
                    lbra      vbfBad

********************************************************************
* Completion/ownership state after the alpha transaction.
********************************************************************
verifyFront         pshs      x,y,u
                    ldx       #SC.VideoActiveSurface
                    lbsr      SC_READ8
                    lbcs      vfBad
                    cmpa      activeSurf,u
                    lbne      vfBad
                    ldx       #SC.MediaJobBase+SC.JobStateO
                    lbsr      SC_READ8
                    lbcs      vfBad
                    cmpa      #SC.JobIdle
                    lbne      vfBad
                    lbsr      SC_IRQ_GET
                    bita      #SC.IRQMedia
                    lbne      vfBad
                    ldb       #2
                    lbsr      SC_MBO_STATUS
                    lbcs      vfBad
                    bita      #SC.MBOStatusValid
                    lbeq      vfBad
                    bita      #SC.MBOStatusBusy
                    lbne      vfBad

                    lda       activeSurf,u
                    lbeq      vfFront0
                    ldb       #1
                    lbsr      SC_MBO_STATUS
                    lbcs      vfBad
                    anda      #SC.MBOStatusValid!SC.MBOStatusBusy
                    cmpa      #SC.MBOStatusValid!SC.MBOStatusBusy
                    lbne      vfBad
                    ldb       #0
                    lbsr      SC_MBO_STATUS
                    lbcs      vfBad
                    bita      #SC.MBOStatusValid
                    lbeq      vfBad
                    bita      #SC.MBOStatusBusy
                    lbne      vfBad
                    lbra      vfGood
vfFront0            ldb       #0
                    lbsr      SC_MBO_STATUS
                    lbcs      vfBad
                    anda      #SC.MBOStatusValid!SC.MBOStatusBusy
                    cmpa      #SC.MBOStatusValid!SC.MBOStatusBusy
                    lbne      vfBad
                    ldb       #1
                    lbsr      SC_MBO_STATUS
                    lbcs      vfBad
                    bita      #SC.MBOStatusValid
                    lbeq      vfBad
                    bita      #SC.MBOStatusBusy
                    lbne      vfBad
vfGood              puls      x,y,u
                    clrb
                    andcc     #^Carry
                    rts
vfBad               puls      x,y,u
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
