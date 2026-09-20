********************************************************************
* scanim - SuperCoCo S2A-2 double-buffer animation demo
*
* Two independent 153,600-byte framebuffers live outside the process'
* 64 KiB logical space. MAIN maps only the 8 KiB blocks it needs while
* drawing. Each framebuffer is published through its own 38-page MBO and
* bound to one frozen R1J GIME-NG surface.
*
* The demo draws only into the inactive surface, commits that surface, waits
* for the R1G VIDEO VBLANK event, proves the old surface is no longer BUSY,
* then reuses it as the next back buffer. 120 flips animate a white rectangle
* over a black 640x480 INDEX4 background without stdin or startup semantics.
********************************************************************

                    nam       scanim
                    ttl       SuperCoCo S2A-2 VBLANK double-buffer animation

                    ifp1
                    use       defsfile
                    use       supercoco.d
                    endc

rev                 set       $00
edition             set       1
tylg                set       Prgrm+Objct
atrv                set       ReEnt+rev

FB.Blocks           equ       19
FB.Pages            equ       38
FB.BlockBytes       equ       $2000
FB.FlagsRAM0        equ       $01
FB.FlagsRAM1        equ       $02
FB.FlagsMBO0        equ       $04
FB.FlagsMBO1        equ       $08
FB.FlagsVideo       equ       $10

Anim.Frames         equ       120
Rect.WidthPixels    equ       32
Rect.WidthBytes     equ       16
Rect.Height         equ       16
Rect.Y              equ       104
Rect.BaseOffset     equ       $8200              104 * 320 bytes
Rect.Step           equ       8
Rect.MaxX           equ       608                640 - 32

                    mod       eom,name,tylg,atrv,start,size

                    org       0
fb0StartBlock       rmb       2
fb1StartBlock       rmb       2
workStartBlock      rmb       2
fbCurrentBlock      rmb       2
fbMapAddress        rmb       2
fbPPN               rmb       2
fbGeneration0       rmb       4
fbGeneration1       rmb       4
fbFlags             rmb       1
fbBlocksLeft        rmb       1
fbPagesLeft         rmb       1
paletteBytesLeft    rmb       1

mboBase             rmb       2
mboStartBlock       rmb       2
mboGenerationPtr    rmb       2
mboSlot             rmb       1
mboFlag             rmb       1

surfaceBase         rmb       2
surfaceGenerationPtr rmb      2
surfaceSlot         rmb       1

backSurface         rmb       1
framesLeft          rmb       1
rectX               rmb       2
rectDir             rmb       1
oldX0               rmb       2
oldX1               rmb       2
drawStartBlock      rmb       2
drawX               rmb       2
drawColor           rmb       1
rowOffset           rmb       2
rowWithin           rmb       2
mapBlock            rmb       2
rowsLeft            rmb       1

stackSpace          rmb       256
size                equ       .

name                fcs       /scanim/
                    fcb       edition

msgBanner           fcc       /SuperCoCo S2A double-buffer animation/
                    fcb       C$CR
msgBannerLen        equ       *-msgBanner
msgAlloc            fcc       /Allocating two independent 153600-byte framebuffers.../
                    fcb       C$CR
msgAllocLen         equ       *-msgAlloc
msgReady            fcc       /Running 120 VBLANK-safe flips.../
                    fcb       C$CR
msgReadyLen         equ       *-msgReady
msgPass             fcc       /SuperCoCo S2A double-buffer PASS/
                    fcb       C$CR
msgPassLen          equ       *-msgPass
msgFail             fcc       /scanim: double-buffer demo failed/
                    fcb       C$CR
msgFailLen          equ       *-msgFail

* EGA-like 16-color RGB888 palette. Animation uses index 0 and index 15.
paletteRGB          fcb       $00,$00,$00
                    fcb       $00,$00,$AA
                    fcb       $00,$AA,$00
                    fcb       $00,$AA,$AA
                    fcb       $AA,$00,$00
                    fcb       $AA,$00,$AA
                    fcb       $AA,$55,$00
                    fcb       $AA,$AA,$AA
                    fcb       $55,$55,$55
                    fcb       $55,$55,$FF
                    fcb       $55,$FF,$55
                    fcb       $55,$FF,$FF
                    fcb       $FF,$55,$55
                    fcb       $FF,$55,$FF
                    fcb       $FF,$FF,$55
                    fcb       $FF,$FF,$FF

start               clr       fbFlags,u
                    leax      msgBanner,pcr
                    ldy       #msgBannerLen
                    lbsr      writeLine

                    lbsr      SC_PROBE_R1L
                    lbcs      demoFail
                    lbsr      prepareSlots
                    lbcs      demoFail

                    leax      msgAlloc,pcr
                    ldy       #msgAllocLen
                    lbsr      writeLine
                    lbsr      allocateFramebuffers
                    lbcs      demoFail
                    lbsr      clearFramebuffer0
                    lbcs      demoFail
                    lbsr      clearFramebuffer1
                    lbcs      demoFail
                    lbsr      programMBO0
                    lbcs      demoFail
                    lbsr      programMBO1
                    lbcs      demoFail
                    lbsr      programSurface0
                    lbcs      demoFail
                    lbsr      programSurface1
                    lbcs      demoFail
                    lbsr      programPalette
                    lbcs      demoFail

                    leax      msgReady,pcr
                    ldy       #msgReadyLen
                    lbsr      writeLine
                    lbsr      enableDisplay
                    lbcs      demoFail
                    lbsr      animateFrames
                    lbcs      demoFail
                    lbsr      disableDisplay
                    lbcs      demoFail
                    lbsr      revokeMBO1
                    lbcs      demoFail
                    lbsr      revokeMBO0
                    lbcs      demoFail
                    lbsr      freeFramebuffers
                    lbcs      demoFail

                    leax      msgPass,pcr
                    ldy       #msgPassLen
                    lbsr      writeLine
                    clrb
                    os9       F$Exit

demoFail            lbsr      cleanupBestEffort
                    leax      msgFail,pcr
                    ldy       #msgFailLen
                    lbsr      writeLine
                    ldb       #E$NotRdy
                    os9       F$Exit

********************************************************************
* Require MBO slots 0 and 1 to be unowned. There is not yet an OS-side MBO
* allocator, so the demo never revokes an unknown client's descriptor.
********************************************************************
prepareSlots        ldb       #0
                    lbsr      prepareSlot
                    lbcs      pssBad
                    ldb       #1
                    lbsr      prepareSlot
                    lbcs      pssBad
                    clrb
                    andcc     #^Carry
                    rts
pssBad              orcc      #Carry
                    rts

prepareSlot         lbsr      SC_MBO_STATUS
                    lbcs      psltBad
                    bita      #SC.MBOStatusValid!SC.MBOStatusBusy
                    lbeq      psltGood
                    ldb       #E$NotRdy
                    orcc      #Carry
                    rts
psltGood            clrb
                    andcc     #^Carry
                    rts
psltBad             orcc      #Carry
                    rts

********************************************************************
* Allocate two separate 19-block Level-2 extents. They are independent OS RAM
* objects even if the allocator happens to place them adjacent physically.
********************************************************************
allocateFramebuffers ldb      #FB.Blocks
                    os9       F$AllRAM
                    lbcs      allocBad
                    std       fb0StartBlock,u
                    lda       fbFlags,u
                    ora       #FB.FlagsRAM0
                    sta       fbFlags,u

                    ldb       #FB.Blocks
                    os9       F$AllRAM
                    lbcs      allocBad
                    std       fb1StartBlock,u
                    lda       fbFlags,u
                    ora       #FB.FlagsRAM1
                    sta       fbFlags,u
                    clrb
                    andcc     #^Carry
                    rts
allocBad            orcc      #Carry
                    rts

********************************************************************
* Clear both framebuffers to palette index 0. Each 8 KiB physical block is
* mapped only long enough for MAIN to initialize it.
********************************************************************
clearFramebuffer0   ldd       fb0StartBlock,u
                    std       workStartBlock,u
                    lbsr      clearFramebuffer
                    rts

clearFramebuffer1   ldd       fb1StartBlock,u
                    std       workStartBlock,u
                    lbsr      clearFramebuffer
                    rts

clearFramebuffer    ldd       workStartBlock,u
                    std       fbCurrentBlock,u
                    lda       #FB.Blocks
                    sta       fbBlocksLeft,u

cfBlock             ldx       fbCurrentBlock,u
                    ldb       #1
                    pshs      u
                    os9       F$MapBlk
                    lbcs      cfMapBad
                    tfr       u,x
                    puls      u
                    stx       fbMapAddress,u
                    ldy       #FB.BlockBytes
                    clra
cfByte              sta       ,x+
                    leay      -1,y
                    lbne      cfByte

                    pshs      u
                    ldu       fbMapAddress,u
                    ldb       #1
                    os9       F$ClrBlk
                    lbcs      cfUnmapBad
                    puls      u

                    ldd       fbCurrentBlock,u
                    addd      #1
                    std       fbCurrentBlock,u
                    dec       fbBlocksLeft,u
                    lbne      cfBlock
                    clrb
                    andcc     #^Carry
                    rts
cfMapBad            puls      u
                    orcc      #Carry
                    rts
cfUnmapBad          puls      u
                    orcc      #Carry
                    rts

********************************************************************
* Publish each framebuffer as an independent 38-page MBO.
********************************************************************
programMBO0         ldd       #SC.MBOObjectBase
                    std       mboBase,u
                    ldd       fb0StartBlock,u
                    std       mboStartBlock,u
                    leax      fbGeneration0,u
                    stx       mboGenerationPtr,u
                    clr       mboSlot,u
                    lda       #FB.FlagsMBO0
                    sta       mboFlag,u
                    lbsr      programMBO
                    rts

programMBO1         ldd       #SC.MBOObjectBase+SC.MBOObjectStride
                    std       mboBase,u
                    ldd       fb1StartBlock,u
                    std       mboStartBlock,u
                    leax      fbGeneration1,u
                    stx       mboGenerationPtr,u
                    lda       #1
                    sta       mboSlot,u
                    lda       #FB.FlagsMBO1
                    sta       mboFlag,u
                    lbsr      programMBO
                    rts

programMBO          ldb       mboSlot,u
                    lbsr      prepareSlot
                    lbcs      pmbBad

                    ldx       mboBase,u
                    leax      SC.MBOPermissionsO,x
                    lda       #SC.MBOPermRead
                    lbsr      SC_WRITE8
                    lbcs      pmbBad
                    ldx       mboBase,u
                    leax      SC.MBOConsumersO,x
                    lda       #SC.MBOConsumerVideo
                    lbsr      SC_WRITE8
                    lbcs      pmbBad

* length = $00025800 = 153600 bytes, little endian.
                    ldx       mboBase,u
                    leax      SC.MBOLengthO,x
                    clra
                    lbsr      SC_WRITE8
                    lbcs      pmbBad
                    leax      1,x
                    lda       #$58
                    lbsr      SC_WRITE8
                    lbcs      pmbBad
                    leax      1,x
                    lda       #$02
                    lbsr      SC_WRITE8
                    lbcs      pmbBad
                    leax      1,x
                    clra
                    lbsr      SC_WRITE8
                    lbcs      pmbBad

                    ldx       mboBase,u
                    leax      SC.MBOPageCountO,x
                    lda       #FB.Pages
                    lbsr      SC_WRITE8
                    lbcs      pmbBad

* One 8 KiB Level-2 block is two sequential 4 KiB SuperCoCo physical pages.
                    ldd       mboStartBlock,u
                    lslb
                    rola
                    std       fbPPN,u
                    lda       #FB.Pages
                    sta       fbPagesLeft,u
                    ldx       mboBase,u
                    leax      SC.MBOPageListO,x
pmbPage             ldd       fbPPN,u
                    lbsr      SC_WRITE16LE
                    lbcs      pmbBad
                    leax      2,x
                    ldd       fbPPN,u
                    addd      #1
                    std       fbPPN,u
                    dec       fbPagesLeft,u
                    lbne      pmbPage

* COMMIT can time out after taking effect, so mark the slot potentially live
* before submission. Cleanup will prove it idle before RAM can be returned.
                    lda       fbFlags,u
                    ora       mboFlag,u
                    sta       fbFlags,u
                    ldb       mboSlot,u
                    lbsr      SC_MBO_COMMIT
                    lbcs      pmbBad
                    ldb       mboSlot,u
                    lbsr      SC_MBO_STATUS
                    lbcs      pmbBad
                    bita      #SC.MBOStatusValid
                    lbeq      pmbBad

                    ldx       mboBase,u
                    leax      SC.MBOGenerationO,x
                    pshs      u
                    ldu       mboGenerationPtr,u
                    lbsr      SC_READ32LE
                    puls      u
                    lbcs      pmbBad
                    clrb
                    andcc     #^Carry
                    rts
pmbBad              ldb       #E$NotRdy
                    orcc      #Carry
                    rts

********************************************************************
* Bind the two MBO generations to R1J surfaces 0 and 1.
********************************************************************
programSurface0     ldd       #SC.VideoSurface0
                    std       surfaceBase,u
                    clr       surfaceSlot,u
                    leax      fbGeneration0,u
                    stx       surfaceGenerationPtr,u
                    lbsr      programSurface
                    rts

programSurface1     ldd       #SC.VideoSurface1
                    std       surfaceBase,u
                    lda       #1
                    sta       surfaceSlot,u
                    leax      fbGeneration1,u
                    stx       surfaceGenerationPtr,u
                    lbsr      programSurface
                    rts

programSurface      ldx       surfaceBase,u
                    leax      SC.VideoSurfMBOSlotO,x
                    lda       surfaceSlot,u
                    lbsr      SC_WRITE8
                    lbcs      psBad
                    ldx       surfaceBase,u
                    leax      SC.VideoSurfFormatO,x
                    lda       #SC.VideoFmtIndex4
                    lbsr      SC_WRITE8
                    lbcs      psBad

                    ldx       surfaceBase,u
                    leax      SC.VideoSurfGenerationO,x
                    pshs      u
                    ldu       surfaceGenerationPtr,u
                    lbsr      SC_WRITE32LE
                    puls      u
                    lbcs      psBad

                    ldx       surfaceBase,u
                    leax      SC.VideoSurfOffsetO,x
                    clra
                    lbsr      SC_WRITE8
                    lbcs      psBad
                    leax      1,x
                    clra
                    lbsr      SC_WRITE8
                    lbcs      psBad
                    leax      1,x
                    clra
                    lbsr      SC_WRITE8
                    lbcs      psBad
                    leax      1,x
                    clra
                    lbsr      SC_WRITE8
                    lbcs      psBad

                    ldx       surfaceBase,u
                    leax      SC.VideoSurfStrideO,x
                    ldd       #$0140
                    lbsr      SC_WRITE16LE
                    lbcs      psBad
                    clrb
                    andcc     #^Carry
                    rts
psBad               ldb       #E$NotRdy
                    orcc      #Carry
                    rts

programPalette      ldx       #SC.VideoPalette
                    leay      paletteRGB,pcr
                    lda       #48
                    sta       paletteBytesLeft,u
ppLoop              lda       ,y+
                    lbsr      SC_WRITE8
                    lbcs      ppBad
                    leax      1,x
                    dec       paletteBytesLeft,u
                    lbne      ppLoop
                    clrb
                    andcc     #^Carry
                    rts
ppBad               ldb       #E$NotRdy
                    orcc      #Carry
                    rts

********************************************************************
* R1G VIDEO event helper.
********************************************************************
waitVideoEvent      ldy       #$FFFF
wveLoop             lbsr      SC_IRQ_GET
                    bita      #SC.IRQVideo
                    lbne      wveSeen
                    leay      -1,y
                    lbne      wveLoop
                    ldb       #E$NotRdy
                    orcc      #Carry
                    rts
wveSeen             lda       #SC.IRQVideo
                    lbsr      SC_IRQ_ACK
                    clrb
                    andcc     #^Carry
                    rts

********************************************************************
* Enter native output on surface 0. Surface 0 must become BUSY and surface 1
* must remain free for MAIN to draw as the first back buffer.
********************************************************************
enableDisplay       lda       #SC.IRQVideo
                    lbsr      SC_IRQ_ACK
                    ldx       #SC.VideoStageEnable
                    lda       #1
                    lbsr      SC_WRITE8
                    lbcs      edBad
                    ldx       #SC.VideoStageSurface
                    clra
                    lbsr      SC_WRITE8
                    lbcs      edBad
                    lda       fbFlags,u
                    ora       #FB.FlagsVideo
                    sta       fbFlags,u
                    ldx       #SC.VideoControl
                    lda       #SC.VideoCtlCommit
                    lbsr      SC_WRITE8
                    lbcs      edBad
                    lbsr      waitVideoEvent
                    lbcs      edBad
                    ldx       #SC.VideoActiveSurface
                    lbsr      SC_READ8
                    lbcs      edBad
                    tsta
                    lbne      edBad
                    ldb       #0
                    lbsr      SC_MBO_STATUS
                    lbcs      edBad
                    bita      #SC.MBOStatusBusy
                    lbeq      edBad
                    ldb       #1
                    lbsr      SC_MBO_STATUS
                    lbcs      edBad
                    bita      #SC.MBOStatusBusy
                    lbne      edBad
                    lda       #1
                    sta       backSurface,u
                    clrb
                    andcc     #^Carry
                    rts
edBad               ldb       #E$NotRdy
                    orcc      #Carry
                    rts

********************************************************************
* Animate 120 committed frames. Each framebuffer remembers the rectangle
* position it contained the last time it was back buffer: erase that old
* rectangle to black, draw the new white rectangle, then flip atomically.
********************************************************************
animateFrames       lda       #Anim.Frames
                    sta       framesLeft,u
                    clr       rectDir,u
                    clra
                    clrb
                    std       rectX,u
                    ldd       #$FFFF
                    std       oldX0,u
                    std       oldX1,u

afLoop              lda       backSurface,u
                    lbeq      afUse0

                    ldd       fb1StartBlock,u
                    std       drawStartBlock,u
                    ldd       oldX1,u
                    cmpd      #$FFFF
                    lbeq      afDraw1
                    std       drawX,u
                    clr       drawColor,u
                    lbsr      drawRect
                    lbcs      animBad
afDraw1             ldd       rectX,u
                    std       drawX,u
                    lda       #$FF
                    sta       drawColor,u
                    lbsr      drawRect
                    lbcs      animBad
                    ldd       rectX,u
                    std       oldX1,u
                    lbra      afFlip

afUse0             ldd       fb0StartBlock,u
                    std       drawStartBlock,u
                    ldd       oldX0,u
                    cmpd      #$FFFF
                    lbeq      afDraw0
                    std       drawX,u
                    clr       drawColor,u
                    lbsr      drawRect
                    lbcs      animBad
afDraw0             ldd       rectX,u
                    std       drawX,u
                    lda       #$FF
                    sta       drawColor,u
                    lbsr      drawRect
                    lbcs      animBad
                    ldd       rectX,u
                    std       oldX0,u

afFlip              lbsr      flipDisplay
                    lbcs      animBad
                    lbsr      advanceRect
                    dec       framesLeft,u
                    lbne      afLoop
                    clrb
                    andcc     #^Carry
                    rts
animBad             ldb       #E$NotRdy
                    orcc      #Carry
                    rts

********************************************************************
* Draw a byte-aligned 32x16 solid rectangle into the selected back buffer.
* Rect.Y=104 was chosen so each 16-byte row remains inside one 8 KiB block for
* every legal X position. The runtime range guard retains that invariant.
********************************************************************
drawRect            ldd       drawX,u
                    lsra
                    rorb
                    addd      #Rect.BaseOffset
                    std       rowOffset,u
                    lda       #Rect.Height
                    sta       rowsLeft,u

drRow               ldd       rowOffset,u
                    ldx       drawStartBlock,u

drFindBlock         cmpd      #FB.BlockBytes
                    lblo      drHaveBlock
                    subd      #FB.BlockBytes
                    leax      1,x
                    lbra      drFindBlock

drHaveBlock         cmpd      #FB.BlockBytes-Rect.WidthBytes
                    lbhi      drBad
                    std       rowWithin,u
                    stx       mapBlock,u

                    ldx       mapBlock,u
                    ldb       #1
                    pshs      u
                    os9       F$MapBlk
                    lbcs      drMapBad
                    tfr       u,x
                    puls      u
                    stx       fbMapAddress,u

                    ldd       fbMapAddress,u
                    addd      rowWithin,u
                    tfr       d,x
                    lda       drawColor,u
                    ldb       #Rect.WidthBytes
drFill              sta       ,x+
                    decb
                    lbne      drFill

                    pshs      u
                    ldu       fbMapAddress,u
                    ldb       #1
                    os9       F$ClrBlk
                    lbcs      drUnmapBad
                    puls      u

                    ldd       rowOffset,u
                    addd      #$0140
                    std       rowOffset,u
                    dec       rowsLeft,u
                    lbne      drRow
                    clrb
                    andcc     #^Carry
                    rts

drMapBad            puls      u
                    orcc      #Carry
                    rts
drUnmapBad          puls      u
                    orcc      #Carry
                    rts
drBad               ldb       #E$NotRdy
                    orcc      #Carry
                    rts

********************************************************************
* VBLANK-only swap. The newly selected surface must be active and BUSY after
* the event; the old surface must already be non-BUSY before MAIN reuses it.
********************************************************************
flipDisplay         lda       #SC.IRQVideo
                    lbsr      SC_IRQ_ACK
                    ldx       #SC.VideoStageSurface
                    lda       backSurface,u
                    lbsr      SC_WRITE8
                    lbcs      fdBad
                    ldx       #SC.VideoControl
                    lda       #SC.VideoCtlCommit
                    lbsr      SC_WRITE8
                    lbcs      fdBad
                    lbsr      waitVideoEvent
                    lbcs      fdBad
                    ldx       #SC.VideoActiveSurface
                    lbsr      SC_READ8
                    lbcs      fdBad
                    cmpa      backSurface,u
                    lbne      fdBad

                    ldb       backSurface,u
                    lbsr      SC_MBO_STATUS
                    lbcs      fdBad
                    bita      #SC.MBOStatusBusy
                    lbeq      fdBad

                    ldb       backSurface,u
                    eorb      #1
                    lbsr      SC_MBO_STATUS
                    lbcs      fdBad
                    bita      #SC.MBOStatusBusy
                    lbne      fdBad

                    lda       backSurface,u
                    eora      #1
                    sta       backSurface,u
                    clrb
                    andcc     #^Carry
                    rts
fdBad               ldb       #E$NotRdy
                    orcc      #Carry
                    rts

advanceRect         lda       rectDir,u
                    lbne      arLeft
                    ldd       rectX,u
                    addd      #Rect.Step
                    cmpd      #Rect.MaxX
                    lblo      arStoreRight
                    ldd       #Rect.MaxX
                    std       rectX,u
                    lda       #1
                    sta       rectDir,u
                    rts
arStoreRight        std       rectX,u
                    rts
arLeft              ldd       rectX,u
                    subd      #Rect.Step
                    std       rectX,u
                    lbne      arDone
                    clr       rectDir,u
arDone              rts

********************************************************************
* Disable native output at VBLANK.
********************************************************************
disableDisplay      lda       fbFlags,u
                    bita      #FB.FlagsVideo
                    lbeq      ddDone
                    lda       #SC.IRQVideo
                    lbsr      SC_IRQ_ACK
                    ldx       #SC.VideoStageEnable
                    clra
                    lbsr      SC_WRITE8
                    lbcs      ddBad
                    ldx       #SC.VideoControl
                    lda       #SC.VideoCtlCommit
                    lbsr      SC_WRITE8
                    lbcs      ddBad
                    lbsr      waitVideoEvent
                    lbcs      ddBad
                    ldx       #SC.VideoActiveSurface
                    lbsr      SC_READ8
                    lbcs      ddBad
                    cmpa      #$FF
                    lbne      ddBad
                    lda       fbFlags,u
                    anda      #^FB.FlagsVideo
                    sta       fbFlags,u
ddDone              clrb
                    andcc     #^Carry
                    rts
ddBad               ldb       #E$NotRdy
                    orcc      #Carry
                    rts

********************************************************************
* Revoke either MBO and wait for consumer drain before freeing physical RAM.
********************************************************************
revokeMBO0          clr       mboSlot,u
                    lda       #FB.FlagsMBO0
                    sta       mboFlag,u
                    lbsr      revokeMBO
                    rts

revokeMBO1          lda       #1
                    sta       mboSlot,u
                    lda       #FB.FlagsMBO1
                    sta       mboFlag,u
                    lbsr      revokeMBO
                    rts

revokeMBO           lda       fbFlags,u
                    anda      mboFlag,u
                    lbeq      rmDone
                    ldb       mboSlot,u
                    lbsr      SC_MBO_STATUS
                    lbcs      rmBad
                    bita      #SC.MBOStatusValid!SC.MBOStatusBusy
                    lbeq      rmClear

                    ldb       mboSlot,u
                    lbsr      SC_MBO_REVOKE
                    lbcc      rmWaitStart
                    ldb       mboSlot,u
                    lbsr      SC_MBO_STATUS
                    lbcs      rmBad
                    bita      #SC.MBOStatusValid!SC.MBOStatusBusy
                    lbeq      rmClear
                    lbra      rmBad

rmWaitStart         ldy       #$FFFF
rmWait              ldb       mboSlot,u
                    lbsr      SC_MBO_STATUS
                    lbcs      rmBad
                    bita      #SC.MBOStatusBusy
                    lbeq      rmClear
                    leay      -1,y
                    lbne      rmWait
                    lbra      rmBad

rmClear             lda       mboFlag,u
                    coma
                    anda      fbFlags,u
                    sta       fbFlags,u
rmDone              clrb
                    andcc     #^Carry
                    rts
rmBad               ldb       #E$NotRdy
                    orcc      #Carry
                    rts

********************************************************************
* Return physical RAM only after VIDEO and both MBO authorities are gone.
********************************************************************
freeFramebuffers    lda       fbFlags,u
                    bita      #FB.FlagsMBO0!FB.FlagsMBO1!FB.FlagsVideo
                    lbne      ffBad

                    lda       fbFlags,u
                    bita      #FB.FlagsRAM1
                    lbeq      ffTry0
                    ldb       #FB.Blocks
                    ldx       fb1StartBlock,u
                    os9       F$DelRAM
                    lbcs      ffBad
                    lda       fbFlags,u
                    anda      #^FB.FlagsRAM1
                    sta       fbFlags,u

ffTry0              lda       fbFlags,u
                    bita      #FB.FlagsRAM0
                    lbeq      ffDone
                    ldb       #FB.Blocks
                    ldx       fb0StartBlock,u
                    os9       F$DelRAM
                    lbcs      ffBad
                    lda       fbFlags,u
                    anda      #^FB.FlagsRAM0
                    sta       fbFlags,u
ffDone              clrb
                    andcc     #^Carry
                    rts
ffBad               ldb       #E$NotRdy
                    orcc      #Carry
                    rts

********************************************************************
* Conservative failure cleanup. A failure may intentionally leak RAM until
* reboot, but physical blocks are never returned while a consumer may own them.
********************************************************************
cleanupBestEffort   lbsr      disableDisplay
                    lbsr      revokeMBO1
                    lbsr      revokeMBO0
                    lbsr      freeFramebuffers
                    rts

writeLine           lda       #1
                    os9       I$WritLn
                    rts

* Shared S1B SuperCoCo service helpers.
                    use       ../libs/scsys/scsys.inc

                    emod
eom                 equ       *
                    end
