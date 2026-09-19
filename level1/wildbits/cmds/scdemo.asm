********************************************************************
* scdemo - SuperCoCo Community Alpha first-pixels demo
*
* S2A-1 proves that NitrOS-9 Level 2 can own a 153,600-byte framebuffer
* outside the process' 64 KiB logical space, expose it as an MBO, and bind
* it to the frozen GIME-NG 640x480 INDEX4 display service.
*
* The framebuffer is allocated as 19 contiguous 8 KiB Level-2 RAM blocks.
* Those blocks are mapped one at a time for CPU rendering, then exposed to
* SuperCoCo as 38 ordered 4 KiB MBO pages.
********************************************************************

                    nam       scdemo
                    ttl       SuperCoCo 640x480x16 first-pixels demo

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
FB.FlagsRAM         equ       $01
FB.FlagsMBO         equ       $02
FB.FlagsVideo       equ       $04

                    mod       eom,name,tylg,atrv,start,size

                    org       0
fbStartBlock        rmb       2
fbCurrentBlock      rmb       2
fbMapAddress        rmb       2
fbPPN               rmb       2
fbGeneration        rmb       4
fbFlags             rmb       1
fbBlocksLeft        rmb       1
fbPagesLeft         rmb       1
barValue            rmb       1
barBytesLeft        rmb       1
paletteBytesLeft    rmb       1
keyByte             rmb       1
stackSpace          rmb       256
size                equ       .

name                fcs       /scdemo/
                    fcb       edition

msgBanner           fcc       /SuperCoCo S2A first-pixels demo/
                    fcb       C$CR
msgBannerLen        equ       *-msgBanner
msgAlloc            fcc       /Allocating 153600-byte physical framebuffer.../
                    fcb       C$CR
msgAllocLen         equ       *-msgAlloc
msgReady            fcc       /640x480x16 test pattern ready. Press a key to return./
                    fcb       C$CR
msgReadyLen         equ       *-msgReady
msgPass             fcc       /SuperCoCo S2A first-pixels PASS/
                    fcb       C$CR
msgPassLen          equ       *-msgPass
msgFail             fcc       /scdemo: first-pixels demo failed/
                    fcb       C$CR
msgFailLen          equ       *-msgFail

* EGA-like 16-color RGB888 palette.
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

                    leax      msgAlloc,pcr
                    ldy       #msgAllocLen
                    lbsr      writeLine

                    lbsr      allocateFramebuffer
                    lbcs      demoFail
                    lbsr      paintFramebuffer
                    lbcs      demoFail
                    lbsr      programMBO0
                    lbcs      demoFail
                    lbsr      programSurface0
                    lbcs      demoFail
                    lbsr      programPalette
                    lbcs      demoFail

* Tell the user how to return before the new display replaces the text view.
                    leax      msgReady,pcr
                    ldy       #msgReadyLen
                    lbsr      writeLine

                    lbsr      enableDisplay
                    lbcs      demoFail

* Keep the new display visible until one byte arrives on standard input.
                    leax      keyByte,u
                    ldy       #1
                    clra
                    os9       I$Read
                    lbcs      demoFail

                    lbsr      disableDisplay
                    lbcs      demoFail
                    lbsr      revokeMBO0
                    lbcs      demoFail
                    lbsr      freeFramebuffer
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
* Allocate one framebuffer as 19 contiguous Level-2 8 KiB RAM blocks.
********************************************************************
allocateFramebuffer ldb       #FB.Blocks
                    os9       F$AllRAM
                    lbcs      afBad
                    std       fbStartBlock,u
                    lda       fbFlags,u
                    ora       #FB.FlagsRAM
                    sta       fbFlags,u
                    clrb
                    andcc     #^Carry
                    rts
afBad               orcc      #Carry
                    rts

********************************************************************
* Paint 16 vertical color bars.
*
* F$MapBlk maps one owned physical 8 KiB block into a temporary logical
* window. F$ClrBlk removes that mapping before the next block. The renderer
* never requires the full framebuffer to exist in the process address space.
********************************************************************
paintFramebuffer    ldd       fbStartBlock,u
                    std       fbCurrentBlock,u
                    clr       barValue,u
                    lda       #20                 40 pixels = 20 packed bytes
                    sta       barBytesLeft,u
                    lda       #FB.Blocks
                    sta       fbBlocksLeft,u

pfBlock             ldx       fbCurrentBlock,u
                    ldb       #1
                    pshs      u
                    os9       F$MapBlk
                    lbcs      pfMapBad
                    tfr       u,x
                    puls      u
                    stx       fbMapAddress,u
                    ldy       #FB.BlockBytes

pfByte              lda       barValue,u
                    sta       ,x+
                    dec       barBytesLeft,u
                    lbne      pfSameBar
                    lda       #20
                    sta       barBytesLeft,u
                    lda       barValue,u
                    cmpa      #$FF
                    lbeq      pfResetColor
                    adda      #$11
                    sta       barValue,u
                    lbra      pfSameBar
pfResetColor        clr       barValue,u
pfSameBar           leay      -1,y
                    lbne      pfByte

* Remove the temporary 8 KiB mapping while retaining ownership of the RAM.
                    pshs      u
                    ldu       fbMapAddress,u
                    ldb       #1
                    os9       F$ClrBlk
                    lbcs      pfUnmapBad
                    puls      u

                    ldd       fbCurrentBlock,u
                    addd      #1
                    std       fbCurrentBlock,u
                    dec       fbBlocksLeft,u
                    lbne      pfBlock
                    clrb
                    andcc     #^Carry
                    rts

pfMapBad            puls      u
                    orcc      #Carry
                    rts
pfUnmapBad          puls      u
                    orcc      #Carry
                    rts

********************************************************************
* Slot 0 has no OS-side allocator yet. S2A-1 therefore requires it to be
* unused instead of revoking a descriptor that may belong to another client.
********************************************************************
prepareMBO0         ldb       #0
                    lbsr      SC_MBO_STATUS
                    lbcs      pm0Bad
                    bita      #SC.MBOStatusValid!SC.MBOStatusBusy
                    lbeq      pm0Good
                    ldb       #E$NotRdy
                    orcc      #Carry
                    rts
pm0Good             clrb
                    andcc     #^Carry
                    rts
pm0Bad              orcc      #Carry
                    rts

********************************************************************
* Publish the 153,600-byte framebuffer as MBO slot 0.
* 19 contiguous 8 KiB OS blocks become 38 contiguous 4 KiB MBO pages.
********************************************************************
programMBO0         lbsr      prepareMBO0
                    lbcs      pmbBad

                    ldx       #SC.MBOObjectBase+SC.MBOPermissionsO
                    lda       #SC.MBOPermRead
                    lbsr      SC_WRITE8
                    lbcs      pmbBad
                    ldx       #SC.MBOObjectBase+SC.MBOConsumersO
                    lda       #SC.MBOConsumerVideo
                    lbsr      SC_WRITE8
                    lbcs      pmbBad

* length = $00025800 = 153600 bytes, little endian.
                    ldx       #SC.MBOObjectBase+SC.MBOLengthO
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

                    ldx       #SC.MBOObjectBase+SC.MBOPageCountO
                    lda       #FB.Pages
                    lbsr      SC_WRITE8
                    lbcs      pmbBad

* Convert first 8 KiB block number to first 4 KiB physical page number.
                    ldd       fbStartBlock,u
                    lslb
                    rola
                    std       fbPPN,u
                    lda       #FB.Pages
                    sta       fbPagesLeft,u
                    ldx       #SC.MBOObjectBase+SC.MBOPageListO

pmbPage             ldd       fbPPN,u
                    lbsr      SC_WRITE16LE
                    lbcs      pmbBad
                    leax      2,x
                    ldd       fbPPN,u
                    addd      #1
                    std       fbPPN,u
                    dec       fbPagesLeft,u
                    lbne      pmbPage

* Once COMMIT is attempted, a timeout makes the outcome ambiguous. Mark the
* slot potentially live first so failure cleanup will prove/revoke it before
* physical RAM can be returned.
                    lda       fbFlags,u
                    ora       #FB.FlagsMBO
                    sta       fbFlags,u
                    ldb       #0
                    lbsr      SC_MBO_COMMIT
                    lbcs      pmbBad

                    ldb       #0
                    lbsr      SC_MBO_STATUS
                    lbcs      pmbBad
                    bita      #SC.MBOStatusValid
                    lbeq      pmbBad

* Snapshot the generation selected by the MBO commit.
                    ldx       #SC.MBOObjectBase+SC.MBOGenerationO
                    pshs      u
                    leau      fbGeneration,u
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
* Bind MBO0 to VIDEO surface 0: INDEX4, generation snapshot, offset 0,
* stride 320 bytes.
********************************************************************
programSurface0     ldx       #SC.VideoSurface0+SC.VideoSurfMBOSlotO
                    clra
                    lbsr      SC_WRITE8
                    lbcs      psBad
                    ldx       #SC.VideoSurface0+SC.VideoSurfFormatO
                    lda       #SC.VideoFmtIndex4
                    lbsr      SC_WRITE8
                    lbcs      psBad

                    ldx       #SC.VideoSurface0+SC.VideoSurfGenerationO
                    pshs      u
                    leau      fbGeneration,u
                    lbsr      SC_WRITE32LE
                    puls      u
                    lbcs      psBad

                    ldx       #SC.VideoSurface0+SC.VideoSurfOffsetO
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

                    ldx       #SC.VideoSurface0+SC.VideoSurfStrideO
                    ldd       #$0140
                    lbsr      SC_WRITE16LE
                    lbcs      psBad
                    clrb
                    andcc     #^Carry
                    rts
psBad               ldb       #E$NotRdy
                    orcc      #Carry
                    rts

********************************************************************
* Load the 16-entry RGB888 palette.
********************************************************************
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
* VIDEO lifecycle.
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
* As with MBO commit, a portal timeout after issuing VIDEO COMMIT is an
* ambiguous result. Treat the display as potentially live before submission.
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

* A live display consumer must hold the MBO busy.
                    ldb       #0
                    lbsr      SC_MBO_STATUS
                    lbcs      edBad
                    bita      #SC.MBOStatusBusy
                    lbeq      edBad
                    clrb
                    andcc     #^Carry
                    rts
edBad               ldb       #E$NotRdy
                    orcc      #Carry
                    rts

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
* Revoke slot 0 and wait until all consumers have drained.
********************************************************************
revokeMBO0          lda       fbFlags,u
                    bita      #FB.FlagsMBO
                    lbeq      rmDone

* If the commit attempt never became live, status can already be fully idle.
                    ldb       #0
                    lbsr      SC_MBO_STATUS
                    lbcs      rmBad
                    bita      #SC.MBOStatusValid!SC.MBOStatusBusy
                    lbeq      rmClear

                    ldb       #0
                    lbsr      SC_MBO_REVOKE
                    lbcc      rmWaitStart

* A timed-out/failed revoke is safe only if a status reread proves no live or
* draining authority remains.
                    ldb       #0
                    lbsr      SC_MBO_STATUS
                    lbcs      rmBad
                    bita      #SC.MBOStatusValid!SC.MBOStatusBusy
                    lbeq      rmClear
                    lbra      rmBad

rmWaitStart         ldy       #$FFFF
rmWait              ldb       #0
                    lbsr      SC_MBO_STATUS
                    lbcs      rmBad
                    bita      #SC.MBOStatusBusy
                    lbeq      rmClear
                    leay      -1,y
                    lbne      rmWait
                    lbra      rmBad
rmClear             lda       fbFlags,u
                    anda      #^FB.FlagsMBO
                    sta       fbFlags,u
rmDone              clrb
                    andcc     #^Carry
                    rts
rmBad               ldb       #E$NotRdy
                    orcc      #Carry
                    rts

********************************************************************
* Return the 19 owned physical blocks only after the display and MBO have
* released them.
********************************************************************
freeFramebuffer     lda       fbFlags,u
                    bita      #FB.FlagsRAM
                    lbeq      ffDone
                    lda       fbFlags,u
                    bita      #FB.FlagsMBO!FB.FlagsVideo
                    lbne      ffBad
                    ldb       #FB.Blocks
                    ldx       fbStartBlock,u
                    os9       F$DelRAM
                    lbcs      ffBad
                    lda       fbFlags,u
                    anda      #^FB.FlagsRAM
                    sta       fbFlags,u
ffDone              clrb
                    andcc     #^Carry
                    rts
ffBad               ldb       #E$NotRdy
                    orcc      #Carry
                    rts

********************************************************************
* Failure cleanup is conservative: never free physical RAM while a consumer
* may still own it. A failed drain can leak until reboot, but cannot create a
* use-after-free against VIDEO.
********************************************************************
cleanupBestEffort   lbsr      disableDisplay
                    lbcs      cbKeep
                    lbsr      revokeMBO0
                    lbcs      cbKeep
                    lbsr      freeFramebuffer
cbKeep              rts

writeLine           lda       #1
                    os9       I$WritLn
                    rts

* Shared S1B SuperCoCo service helpers.
                    use       ../libs/scsys/scsys.inc

                    emod
eom                 equ       *
                    end
