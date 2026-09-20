********************************************************************
* scavdemo - SuperCoCo S2A-4 concurrent graphics + audio demo
*
* S2A-4 retains the S2A-3 ownership split: MAIN writes only R1K command
* records, MEDIA writes framebuffer pixels, and GIME-NG reads the displayed
* MBO. It adds an independent R1L PCM ring in MBO4 and keeps that stream fed
* while FILL, BLIT, MASKED BLIT, and VBLANK-safe flips continue.
*
* The 32,768-frame audio ring contains a periodic stereo square wave. MAIN
* never needs to rewrite consumed slots because the intended future frames are
* bit-identical; after ownership returns, it republishes half-ring sequence
* windows with PROD_COMMIT. This isolates producer/consumer lifetime semantics
* from CPU copy bandwidth while proving concurrent VIDEO, MEDIA, and AUDIO.
********************************************************************

                    nam       scavdemo
                    ttl       SuperCoCo S2A-4 VIDEO MEDIA AUDIO concurrency

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
Small.Blocks        equ       1
Audio.Blocks        equ       16
Audio.Pages         equ       32
Audio.RingFrames    equ       32768
Audio.HalfFrames    equ       16384

RF0.RAM0            equ       $01
RF0.RAM1            equ       $02
RF0.RAMCmd          equ       $04
RF0.RAMSrc          equ       $08
RF0.MBO0            equ       $10
RF0.MBO1            equ       $20
RF0.MBOCmd          equ       $40
RF0.MBOSrc          equ       $80

RF1.Video           equ       $01
RF1.CmdMapped       equ       $02
RF1.SrcMapped       equ       $04
RF1.RAMAudio        equ       $08
RF1.MBOAudio        equ       $10
RF1.AudioRunning    equ       $20
RF1.AudioMapped     equ       $40

Slot.FB0            equ       0
Slot.FB1            equ       1
Slot.Cmd            equ       2
Slot.Src            equ       3
Slot.Audio          equ       4

Anim.Frames         equ       120
Tile.Width          equ       64
Tile.Height         equ       8
Tile.Y              equ       40
Tile.Step           equ       8
Tile.MaxX           equ       576

Sprite.Width        equ       32
Sprite.Height       equ       16
Sprite.Y            equ       200
Sprite.Step         equ       5
Sprite.MaxX         equ       608

Source.Stride       equ       32
Source.Width        equ       64
Source.Height       equ       32

                    mod       eom,name,tylg,atrv,start,size

                    org       0
fb0StartBlock       rmb       2
fb1StartBlock       rmb       2
cmdStartBlock       rmb       2
srcStartBlock       rmb       2
audioStartBlock     rmb       2

fbGeneration0       rmb       4
fbGeneration1       rmb       4
cmdGeneration       rmb       4
srcGeneration       rmb       4
audioGeneration     rmb       4

resourceFlags0      rmb       1
resourceFlags1      rmb       1

mboBase             rmb       2
mboStartBlock       rmb       2
mboGenerationPtr    rmb       2
mboPPN              rmb       2
mboSlot             rmb       1
mboFlagMask         rmb       1
mboPermissions      rmb       1
mboConsumers        rmb       1
mboPagesLeft        rmb       1

surfaceBase         rmb       2
surfaceGenerationPtr rmb      2
surfaceSlot         rmb       1
paletteBytesLeft    rmb       1

cmdMapAddress       rmb       2
srcMapAddress       rmb       2
sourceRowsLeft      rmb       1

audioCurrentBlock   rmb       2
audioMapAddress     rmb       2
audioBlocksLeft     rmb       1
audioPagesLeft      rmb       1
tonePeriodsLeft     rmb       1
toneFramesLeft      rmb       1
audioConsumer       rmb       4
audioNextRefill     rmb       4
audioRefillCount    rmb       1
audioProducer       rmb       4
audioUnderrunBase   rmb       4
audioUnderrunNow    rmb       4

renderSlot          rmb       1
backSurface         rmb       1
framesLeft          rmb       1

tileX               rmb       2
tileDir             rmb       1
spriteX             rmb       2
spriteDir           rmb       1

cmdColor            rmb       1
cmdSrcX             rmb       2
cmdSrcY             rmb       2
cmdDstX             rmb       2
cmdDstY             rmb       2
cmdWidth            rmb       2
cmdHeight           rmb       2
jobTag              rmb       2

stackSpace          rmb       256
size                equ       .

name                fcs       /scavdemo/
                    fcb       edition

msgBanner           fcc       /SuperCoCo S2A concurrent graphics + audio/
                    fcb       C$CR
msgBannerLen        equ       *-msgBanner
msgAlloc            fcc       /Allocating VIDEO, MEDIA, and AUDIO MBO backing.../
                    fcb       C$CR
msgAllocLen         equ       *-msgAlloc
msgReady            fcc       /R1K animation + 48k stereo PCM, 120 VBLANK flips.../
                    fcb       C$CR
msgReadyLen         equ       *-msgReady
msgPass             fcc       /SuperCoCo S2A VIDEO+MEDIA+AUDIO PASS/
                    fcb       C$CR
msgPassLen          equ       *-msgPass
msgFail             fcc       /scavdemo: concurrent graphics+audio failed/
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

* Packed INDEX4 bytes used for eight opaque BLIT rows.
tileRowColors       fcb       $23,$45,$67,$89,$AB,$CD,$EF,$5A

start               clr       resourceFlags0,u
                    clr       resourceFlags1,u
                    clr       jobTag,u
                    clr       jobTag+1,u
                    leax      msgBanner,pcr
                    ldy       #msgBannerLen
                    lbsr      writeLine

                    lbsr      SC_PROBE_R1L
                    lbcs      demoFail
                    lbsr      probeGraphics
                    lbcs      demoFail
                    lbsr      probeAudio
                    lbcs      demoFail
                    lbsr      prepareSlots
                    lbcs      demoFail

                    leax      msgAlloc,pcr
                    ldy       #msgAllocLen
                    lbsr      writeLine
                    lbsr      allocateBacking
                    lbcs      demoFail
                    lbsr      programFramebufferMBO0
                    lbcs      demoFail
                    lbsr      programFramebufferMBO1
                    lbcs      demoFail
                    lbsr      programCommandMBO
                    lbcs      demoFail
                    lbsr      programSourceMBO
                    lbcs      demoFail
                    lbsr      programAudioMBO
                    lbcs      demoFail
                    lbsr      seedSource
                    lbcs      demoFail
                    lbsr      seedAudio
                    lbcs      demoFail
                    lbsr      programSurface0
                    lbcs      demoFail
                    lbsr      programSurface1
                    lbcs      demoFail
                    lbsr      programPalette
                    lbcs      demoFail

* R1K initializes both framebuffer objects. MAIN never maps either extent.
                    clr       renderSlot,u
                    lda       #1
                    lbsr      fillWholeSurface
                    lbcs      demoFail
                    lda       #1
                    sta       renderSlot,u
                    lda       #1
                    lbsr      fillWholeSurface
                    lbcs      demoFail

                    clr       tileDir,u
                    clr       spriteDir,u
                    clra
                    clrb
                    std       tileX,u
                    std       spriteX,u

* Build the first complete frame before enabling scanout.
                    clr       renderSlot,u
                    lbsr      renderDynamicFrame
                    lbcs      demoFail

* Start R1L only after all graphics backing is initialized. The stream remains
* live while every subsequent MEDIA job and VIDEO flip executes.
                    lbsr      configureAudio
                    lbcs      demoFail
                    lbsr      waitAudioProgress
                    lbcs      demoFail

                    leax      msgReady,pcr
                    ldy       #msgReadyLen
                    lbsr      writeLine
                    lbsr      enableDisplay
                    lbcs      demoFail
                    lbsr      advanceMotion
                    lbsr      animateFrames
                    lbcs      demoFail
                    lbsr      verifyAudioConcurrent
                    lbcs      demoFail
                    lbsr      disableDisplay
                    lbcs      demoFail
                    lbsr      stopAudio
                    lbcs      demoFail
                    lbsr      drainMediaJob
                    lbsr      revokeAudioMBO
                    lbcs      demoFail
                    lbsr      revokeSourceMBO
                    lbcs      demoFail
                    lbsr      revokeCommandMBO
                    lbcs      demoFail
                    lbsr      revokeFramebufferMBO1
                    lbcs      demoFail
                    lbsr      revokeFramebufferMBO0
                    lbcs      demoFail
                    lbsr      freeBacking
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
* Frozen R1K discovery used by this demo.
********************************************************************
probeGraphics       ldx       #SC.GraphicsABIMajor
                    lbsr      SC_READ8
                    lbcs      pgBad
                    cmpa      #1
                    lbne      pgBad
                    ldx       #SC.GraphicsABIMinor
                    lbsr      SC_READ8
                    lbcs      pgBad
                    tsta
                    lbne      pgBad
                    ldx       #SC.GraphicsCaps0
                    lbsr      SC_READ8
                    lbcs      pgBad
                    anda      #$7F
                    cmpa      #$7F
                    lbne      pgBad
                    ldx       #SC.GraphicsMediaSlot
                    lbsr      SC_READ8
                    lbcs      pgBad
                    cmpa      #3
                    lbne      pgBad
                    ldx       #SC.GraphicsJobOpcode
                    lbsr      SC_READ8
                    lbcs      pgBad
                    cmpa      #SC.GraphicsOpcode
                    lbne      pgBad
                    ldx       #SC.GraphicsCmdSize
                    lbsr      SC_READ8
                    lbcs      pgBad
                    cmpa      #64
                    lbne      pgBad
                    ldx       #SC.GraphicsAlignShift
                    lbsr      SC_READ8
                    lbcs      pgBad
                    cmpa      #6
                    lbne      pgBad
                    ldx       #SC.GraphicsFormat
                    lbsr      SC_READ8
                    lbcs      pgBad
                    cmpa      #SC.GraphicsFmtIndex4
                    lbne      pgBad
                    clrb
                    andcc     #^Carry
                    rts
pgBad               ldb       #E$NotRdy
                    orcc      #Carry
                    rts

********************************************************************
* Frozen R1L Audio V1 discovery needed by the concurrent demo.
********************************************************************
probeAudio          ldx       #SC.AudioABIMajor
                    lbsr      SC_READ8
                    lbcs      paBad
                    cmpa      #1
                    lbne      paBad
                    ldx       #SC.AudioABIMinor
                    lbsr      SC_READ8
                    lbcs      paBad
                    tsta
                    lbne      paBad
                    ldx       #SC.AudioFormat
                    lbsr      SC_READ8
                    lbcs      paBad
                    cmpa      #SC.AudioFmtS16LEStereo
                    lbne      paBad
                    ldx       #SC.AudioFrameBytes
                    lbsr      SC_READ8
                    lbcs      paBad
                    cmpa      #4
                    lbne      paBad
                    ldx       #SC.AudioRate0
                    lbsr      SC_READ8
                    lbcs      paBad
                    cmpa      #$80
                    lbne      paBad
                    leax      1,x
                    lbsr      SC_READ8
                    lbcs      paBad
                    cmpa      #$BB
                    lbne      paBad
                    leax      1,x
                    lbsr      SC_READ8
                    lbcs      paBad
                    tsta
                    lbne      paBad
                    leax      1,x
                    lbsr      SC_READ8
                    lbcs      paBad
                    tsta
                    lbne      paBad
                    clrb
                    andcc     #^Carry
                    rts
paBad               ldb       #E$NotRdy
                    orcc      #Carry
                    rts

********************************************************************
* Require MBO slots 0..4 to be idle. The demo never revokes an unknown owner.
********************************************************************
prepareSlots        ldb       #Slot.FB0
                    lbsr      prepareSlot
                    lbcs      pssBad
                    ldb       #Slot.FB1
                    lbsr      prepareSlot
                    lbcs      pssBad
                    ldb       #Slot.Cmd
                    lbsr      prepareSlot
                    lbcs      pssBad
                    ldb       #Slot.Src
                    lbsr      prepareSlot
                    lbcs      pssBad
                    ldb       #Slot.Audio
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
* Allocate five independent Level-2 physical extents.
********************************************************************
allocateBacking     ldb       #FB.Blocks
                    os9       F$AllRAM
                    lbcs      abBad
                    std       fb0StartBlock,u
                    lda       resourceFlags0,u
                    ora       #RF0.RAM0
                    sta       resourceFlags0,u

                    ldb       #FB.Blocks
                    os9       F$AllRAM
                    lbcs      abBad
                    std       fb1StartBlock,u
                    lda       resourceFlags0,u
                    ora       #RF0.RAM1
                    sta       resourceFlags0,u

                    ldb       #Small.Blocks
                    os9       F$AllRAM
                    lbcs      abBad
                    std       cmdStartBlock,u
                    lda       resourceFlags0,u
                    ora       #RF0.RAMCmd
                    sta       resourceFlags0,u

                    ldb       #Small.Blocks
                    os9       F$AllRAM
                    lbcs      abBad
                    std       srcStartBlock,u
                    lda       resourceFlags0,u
                    ora       #RF0.RAMSrc
                    sta       resourceFlags0,u

                    ldb       #Audio.Blocks
                    os9       F$AllRAM
                    lbcs      abBad
                    std       audioStartBlock,u
                    lda       resourceFlags1,u
                    ora       #RF1.RAMAudio
                    sta       resourceFlags1,u
                    clrb
                    andcc     #^Carry
                    rts
abBad               orcc      #Carry
                    rts

********************************************************************
* Publish framebuffer MBOs with VIDEO read and MEDIA write authority.
********************************************************************
programFramebufferMBO0
                    ldd       #SC.MBOObjectBase
                    std       mboBase,u
                    ldd       fb0StartBlock,u
                    std       mboStartBlock,u
                    leax      fbGeneration0,u
                    stx       mboGenerationPtr,u
                    lda       #Slot.FB0
                    sta       mboSlot,u
                    lda       #RF0.MBO0
                    sta       mboFlagMask,u
                    lbsr      programFramebufferMBO
                    rts

programFramebufferMBO1
                    ldd       #SC.MBOObjectBase+SC.MBOObjectStride
                    std       mboBase,u
                    ldd       fb1StartBlock,u
                    std       mboStartBlock,u
                    leax      fbGeneration1,u
                    stx       mboGenerationPtr,u
                    lda       #Slot.FB1
                    sta       mboSlot,u
                    lda       #RF0.MBO1
                    sta       mboFlagMask,u
                    lbsr      programFramebufferMBO
                    rts

programFramebufferMBO
                    ldb       mboSlot,u
                    lbsr      prepareSlot
                    lbcs      pfbBad

                    ldx       mboBase,u
                    leax      SC.MBOPermissionsO,x
                    lda       #SC.MBOPermRead!SC.MBOPermWrite
                    lbsr      SC_WRITE8
                    lbcs      pfbBad
                    ldx       mboBase,u
                    leax      SC.MBOConsumersO,x
                    lda       #SC.MBOConsumerVideo!SC.MBOConsumerMedia
                    lbsr      SC_WRITE8
                    lbcs      pfbBad

* length = $00025800 = 153600 bytes, little endian.
                    ldx       mboBase,u
                    leax      SC.MBOLengthO,x
                    clra
                    lbsr      SC_WRITE8
                    lbcs      pfbBad
                    leax      1,x
                    lda       #$58
                    lbsr      SC_WRITE8
                    lbcs      pfbBad
                    leax      1,x
                    lda       #$02
                    lbsr      SC_WRITE8
                    lbcs      pfbBad
                    leax      1,x
                    clra
                    lbsr      SC_WRITE8
                    lbcs      pfbBad

                    ldx       mboBase,u
                    leax      SC.MBOPageCountO,x
                    lda       #FB.Pages
                    lbsr      SC_WRITE8
                    lbcs      pfbBad

* One Level-2 8 KiB block corresponds to two sequential 4 KiB MBO pages.
                    ldd       mboStartBlock,u
                    lslb
                    rola
                    std       mboPPN,u
                    lda       #FB.Pages
                    sta       mboPagesLeft,u
                    ldx       mboBase,u
                    leax      SC.MBOPageListO,x
pfbPage             ldd       mboPPN,u
                    lbsr      SC_WRITE16LE
                    lbcs      pfbBad
                    leax      2,x
                    ldd       mboPPN,u
                    addd      #1
                    std       mboPPN,u
                    dec       mboPagesLeft,u
                    lbne      pfbPage

                    lda       resourceFlags0,u
                    ora       mboFlagMask,u
                    sta       resourceFlags0,u
                    ldb       mboSlot,u
                    lbsr      SC_MBO_COMMIT
                    lbcs      pfbBad
                    lbsr      readCommittedGeneration
                    lbcs      pfbBad
                    clrb
                    andcc     #^Carry
                    rts
pfbBad              ldb       #E$NotRdy
                    orcc      #Carry
                    rts

********************************************************************
* Command and source are separate one-page MEDIA-read MBOs.
********************************************************************
programCommandMBO   ldd       #SC.MBOObjectBase+(SC.MBOObjectStride*Slot.Cmd)
                    std       mboBase,u
                    ldd       cmdStartBlock,u
                    std       mboStartBlock,u
                    leax      cmdGeneration,u
                    stx       mboGenerationPtr,u
                    lda       #Slot.Cmd
                    sta       mboSlot,u
                    lda       #RF0.MBOCmd
                    sta       mboFlagMask,u
                    lbsr      programOnePageMBO
                    rts

programSourceMBO    ldd       #SC.MBOObjectBase+(SC.MBOObjectStride*Slot.Src)
                    std       mboBase,u
                    ldd       srcStartBlock,u
                    std       mboStartBlock,u
                    leax      srcGeneration,u
                    stx       mboGenerationPtr,u
                    lda       #Slot.Src
                    sta       mboSlot,u
                    lda       #RF0.MBOSrc
                    sta       mboFlagMask,u
                    lbsr      programOnePageMBO
                    rts

programOnePageMBO   ldb       mboSlot,u
                    lbsr      prepareSlot
                    lbcs      popBad

                    ldx       mboBase,u
                    leax      SC.MBOPermissionsO,x
                    lda       #SC.MBOPermRead
                    lbsr      SC_WRITE8
                    lbcs      popBad
                    ldx       mboBase,u
                    leax      SC.MBOConsumersO,x
                    lda       #SC.MBOConsumerMedia
                    lbsr      SC_WRITE8
                    lbcs      popBad

* length = $00001000, one 4 KiB physical page from the 8 KiB OS allocation.
                    ldx       mboBase,u
                    leax      SC.MBOLengthO,x
                    clra
                    lbsr      SC_WRITE8
                    lbcs      popBad
                    leax      1,x
                    lda       #$10
                    lbsr      SC_WRITE8
                    lbcs      popBad
                    leax      1,x
                    clra
                    lbsr      SC_WRITE8
                    lbcs      popBad
                    leax      1,x
                    clra
                    lbsr      SC_WRITE8
                    lbcs      popBad

                    ldx       mboBase,u
                    leax      SC.MBOPageCountO,x
                    lda       #1
                    lbsr      SC_WRITE8
                    lbcs      popBad

                    ldd       mboStartBlock,u
                    lslb
                    rola
                    ldx       mboBase,u
                    leax      SC.MBOPageListO,x
                    lbsr      SC_WRITE16LE
                    lbcs      popBad

                    lda       resourceFlags0,u
                    ora       mboFlagMask,u
                    sta       resourceFlags0,u
                    ldb       mboSlot,u
                    lbsr      SC_MBO_COMMIT
                    lbcs      popBad
                    lbsr      readCommittedGeneration
                    lbcs      popBad
                    clrb
                    andcc     #^Carry
                    rts
popBad              ldb       #E$NotRdy
                    orcc      #Carry
                    rts

readCommittedGeneration
                    ldb       mboSlot,u
                    lbsr      SC_MBO_STATUS
                    lbcs      rcgBad
                    bita      #SC.MBOStatusValid
                    lbeq      rcgBad
                    ldx       mboBase,u
                    leax      SC.MBOGenerationO,x
                    pshs      u
                    ldu       mboGenerationPtr,u
                    lbsr      SC_READ32LE
                    puls      u
                    lbcs      rcgBad
                    clrb
                    andcc     #^Carry
                    rts
rcgBad              ldb       #E$NotRdy
                    orcc      #Carry
                    rts

********************************************************************
* MBO4 is a 131072-byte AUDIO-read ring: 16 Level-2 blocks = 32 pages.
********************************************************************
programAudioMBO     ldd       #SC.MBOObjectBase+(SC.MBOObjectStride*Slot.Audio)
                    std       mboBase,u
                    ldd       audioStartBlock,u
                    std       mboStartBlock,u
                    leax      audioGeneration,u
                    stx       mboGenerationPtr,u
                    lda       #Slot.Audio
                    sta       mboSlot,u

                    ldb       mboSlot,u
                    lbsr      prepareSlot
                    lbcs      pamBad
                    ldx       mboBase,u
                    leax      SC.MBOPermissionsO,x
                    lda       #SC.MBOPermRead
                    lbsr      SC_WRITE8
                    lbcs      pamBad
                    ldx       mboBase,u
                    leax      SC.MBOConsumersO,x
                    lda       #SC.MBOConsumerAudio
                    lbsr      SC_WRITE8
                    lbcs      pamBad

* length = $00020000 bytes.
                    ldx       mboBase,u
                    leax      SC.MBOLengthO,x
                    clra
                    lbsr      SC_WRITE8
                    lbcs      pamBad
                    leax      1,x
                    clra
                    lbsr      SC_WRITE8
                    lbcs      pamBad
                    leax      1,x
                    lda       #$02
                    lbsr      SC_WRITE8
                    lbcs      pamBad
                    leax      1,x
                    clra
                    lbsr      SC_WRITE8
                    lbcs      pamBad

                    ldx       mboBase,u
                    leax      SC.MBOPageCountO,x
                    lda       #Audio.Pages
                    lbsr      SC_WRITE8
                    lbcs      pamBad
                    ldd       audioStartBlock,u
                    lslb
                    rola
                    std       mboPPN,u
                    lda       #Audio.Pages
                    sta       audioPagesLeft,u
                    ldx       mboBase,u
                    leax      SC.MBOPageListO,x
pamPage             ldd       mboPPN,u
                    lbsr      SC_WRITE16LE
                    lbcs      pamBad
                    leax      2,x
                    ldd       mboPPN,u
                    addd      #1
                    std       mboPPN,u
                    dec       audioPagesLeft,u
                    lbne      pamPage

* Mark potentially live before COMMIT so failure cleanup never frees backing
* until slot 4 has been proven drained.
                    lda       resourceFlags1,u
                    ora       #RF1.MBOAudio
                    sta       resourceFlags1,u
                    ldb       #Slot.Audio
                    lbsr      SC_MBO_COMMIT
                    lbcs      pamBad
                    lbsr      readCommittedGeneration
                    lbcs      pamBad
                    clrb
                    andcc     #^Carry
                    rts
pamBad              ldb       #E$NotRdy
                    orcc      #Carry
                    rts

********************************************************************
* Seed MBO3 once. Rows 0..7 are an opaque 64x8 BLIT tile. Rows 16..31
* contain a 32x16 MASKED sprite with transparent color 0 and yellow center.
********************************************************************
seedSource          lbsr      mapSource
                    lbcs      ssBad
                    ldx       srcMapAddress,u
                    ldy       #$1000
                    clra
ssClear             sta       ,x+
                    leay      -1,y
                    lbne      ssClear

* Eight opaque tile rows, one packed color pair repeated across each row.
                    ldx       srcMapAddress,u
                    leay      tileRowColors,pcr
                    lda       #8
                    sta       sourceRowsLeft,u
ssTileRow           lda       ,y+
                    ldb       #Source.Stride
ssTileByte          sta       ,x+
                    decb
                    lbne      ssTileByte
                    dec       sourceRowsLeft,u
                    lbne      ssTileRow

* Sprite source starts at y=16. Leave two transparent rows and four
* transparent pixels at each side; fill the 24x12 center with palette 14.
                    ldd       srcMapAddress,u
                    addd      #$0242
                    tfr       d,x
                    lda       #12
                    sta       sourceRowsLeft,u
ssSpriteRow         lda       #$EE
                    ldb       #12
ssSpriteByte        sta       ,x+
                    decb
                    lbne      ssSpriteByte
                    leax      20,x
                    dec       sourceRowsLeft,u
                    lbne      ssSpriteRow

                    lbsr      unmapSource
                    lbcs      ssBad
                    clrb
                    andcc     #^Carry
                    rts
ssBad               ldb       #E$NotRdy
                    orcc      #Carry
                    rts

********************************************************************
* Seed a repeating 750 Hz stereo square wave into MBO4 backing.
* 64 frames/period at 48 kHz. L amplitude=$1800, R amplitude=$1000.
* Each 8 KiB Level-2 block contains exactly 32 complete periods, so the
* waveform is continuous at every block and ring boundary.
********************************************************************
seedAudio           ldd       audioStartBlock,u
                    std       audioCurrentBlock,u
                    lda       #Audio.Blocks
                    sta       audioBlocksLeft,u
saBlock             lbsr      mapAudioCurrent
                    lbcs      saBad
                    ldx       audioMapAddress,u
                    lda       #32
                    sta       tonePeriodsLeft,u
saPeriod            lda       #32
                    sta       toneFramesLeft,u
saPositive          clra
                    sta       ,x+
                    lda       #$18
                    sta       ,x+
                    clra
                    sta       ,x+
                    lda       #$10
                    sta       ,x+
                    dec       toneFramesLeft,u
                    lbne      saPositive

                    lda       #32
                    sta       toneFramesLeft,u
saNegative          clra
                    sta       ,x+
                    lda       #$E8
                    sta       ,x+
                    clra
                    sta       ,x+
                    lda       #$F0
                    sta       ,x+
                    dec       toneFramesLeft,u
                    lbne      saNegative
                    dec       tonePeriodsLeft,u
                    lbne      saPeriod

                    lbsr      unmapAudioCurrent
                    lbcs      saBad
                    ldd       audioCurrentBlock,u
                    addd      #1
                    std       audioCurrentBlock,u
                    dec       audioBlocksLeft,u
                    lbne      saBlock
                    clrb
                    andcc     #^Carry
                    rts
saBad               ldb       #E$NotRdy
                    orcc      #Carry
                    rts

mapAudioCurrent     lda       resourceFlags1,u
                    bita      #RF1.AudioMapped
                    lbne      macBad
                    ldx       audioCurrentBlock,u
                    ldb       #1
                    pshs      u
                    os9       F$MapBlk
                    lbcs      macMapBad
                    tfr       u,x
                    puls      u
                    stx       audioMapAddress,u
                    lda       resourceFlags1,u
                    ora       #RF1.AudioMapped
                    sta       resourceFlags1,u
                    clrb
                    andcc     #^Carry
                    rts
macMapBad           puls      u
macBad              ldb       #E$NotRdy
                    orcc      #Carry
                    rts

unmapAudioCurrent   lda       resourceFlags1,u
                    bita      #RF1.AudioMapped
                    lbeq      uacDone
                    pshs      u
                    ldu       audioMapAddress,u
                    ldb       #1
                    os9       F$ClrBlk
                    lbcs      uacBadStack
                    puls      u
                    lda       resourceFlags1,u
                    anda      #^RF1.AudioMapped
                    sta       resourceFlags1,u
uacDone             clrb
                    andcc     #^Carry
                    rts
uacBadStack         puls      u
                    ldb       #E$NotRdy
                    orcc      #Carry
                    rts

********************************************************************
* CPU mapping helpers. Command/source stay CPU-visible; audio maps only while seeding.
********************************************************************
mapCommand          lda       resourceFlags1,u
                    bita      #RF1.CmdMapped
                    lbne      mcBad
                    ldx       cmdStartBlock,u
                    ldb       #1
                    pshs      u
                    os9       F$MapBlk
                    lbcs      mcMapBad
                    tfr       u,x
                    puls      u
                    stx       cmdMapAddress,u
                    lda       resourceFlags1,u
                    ora       #RF1.CmdMapped
                    sta       resourceFlags1,u
                    clrb
                    andcc     #^Carry
                    rts
mcMapBad            puls      u
mcBad               ldb       #E$NotRdy
                    orcc      #Carry
                    rts

unmapCommand        lda       resourceFlags1,u
                    bita      #RF1.CmdMapped
                    lbeq      ucDone
                    pshs      u
                    ldu       cmdMapAddress,u
                    ldb       #1
                    os9       F$ClrBlk
                    lbcs      ucBadStack
                    puls      u
                    lda       resourceFlags1,u
                    anda      #^RF1.CmdMapped
                    sta       resourceFlags1,u
ucDone              clrb
                    andcc     #^Carry
                    rts
ucBadStack          puls      u
                    ldb       #E$NotRdy
                    orcc      #Carry
                    rts

mapSource           lda       resourceFlags1,u
                    bita      #RF1.SrcMapped
                    lbne      msBad
                    ldx       srcStartBlock,u
                    ldb       #1
                    pshs      u
                    os9       F$MapBlk
                    lbcs      msMapBad
                    tfr       u,x
                    puls      u
                    stx       srcMapAddress,u
                    lda       resourceFlags1,u
                    ora       #RF1.SrcMapped
                    sta       resourceFlags1,u
                    clrb
                    andcc     #^Carry
                    rts
msMapBad            puls      u
msBad               ldb       #E$NotRdy
                    orcc      #Carry
                    rts

unmapSource         lda       resourceFlags1,u
                    bita      #RF1.SrcMapped
                    lbeq      usDone
                    pshs      u
                    ldu       srcMapAddress,u
                    ldb       #1
                    os9       F$ClrBlk
                    lbcs      usBadStack
                    puls      u
                    lda       resourceFlags1,u
                    anda      #^RF1.SrcMapped
                    sta       resourceFlags1,u
usDone              clrb
                    andcc     #^Carry
                    rts
usBadStack          puls      u
                    ldb       #E$NotRdy
                    orcc      #Carry
                    rts

********************************************************************
* Bind framebuffer MBO generations to R1J surfaces 0 and 1.
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
* Command record construction in MBO2.
********************************************************************
beginCommand        lbsr      mapCommand
                    lbcs      bcBad
                    ldx       cmdMapAddress,u
                    ldb       #64
                    clra
bcClear             sta       ,x+
                    decb
                    lbne      bcClear
                    clrb
                    andcc     #^Carry
                    rts
bcBad               orcc      #Carry
                    rts

endCommand          lbsr      unmapCommand
                    rts

writeWordLEMem      stb       ,x
                    sta       1,x
                    rts

writeDestSurface
* X = command surface descriptor. renderSlot selects framebuffer/generation.
                    lda       renderSlot,u
                    sta       ,x
                    lda       #SC.GraphicsFmtIndex4
                    sta       1,x
                    lda       renderSlot,u
                    lbne      wdsOne
                    leay      fbGeneration0,u
                    lbra      wdsGen
wdsOne              leay      fbGeneration1,u
wdsGen              lda       ,y
                    sta       2,x
                    lda       1,y
                    sta       3,x
                    lda       2,y
                    sta       4,x
                    lda       3,y
                    sta       5,x
                    clr       6,x
                    clr       7,x
                    clr       8,x
                    clr       9,x
                    lda       #$40
                    sta       10,x
                    lda       #$01
                    sta       11,x
                    lda       #$80
                    sta       12,x
                    lda       #$02
                    sta       13,x
                    lda       #$E0
                    sta       14,x
                    lda       #$01
                    sta       15,x
                    rts

writeSourceSurface
* X = command source descriptor: MBO3, 64x32, 32-byte stride.
                    lda       #Slot.Src
                    sta       ,x
                    lda       #SC.GraphicsFmtIndex4
                    sta       1,x
                    leay      srcGeneration,u
                    lda       ,y
                    sta       2,x
                    lda       1,y
                    sta       3,x
                    lda       2,y
                    sta       4,x
                    lda       3,y
                    sta       5,x
                    clr       6,x
                    clr       7,x
                    clr       8,x
                    clr       9,x
                    lda       #Source.Stride
                    sta       10,x
                    clr       11,x
                    lda       #Source.Width
                    sta       12,x
                    clr       13,x
                    lda       #Source.Height
                    sta       14,x
                    clr       15,x
                    rts

buildFillCommand    lbsr      beginCommand
                    lbcs      bfcBad
                    ldx       cmdMapAddress,u
                    lda       #1
                    sta       SC.GfxCmdABIMajorO,x
                    lda       #SC.GraphicsOpFill
                    sta       SC.GfxCmdOperationO,x
                    lda       cmdColor,u
                    sta       SC.GfxCmdColorO,x
                    leax      SC.GfxCmdDestO,x
                    lbsr      writeDestSurface
                    ldx       cmdMapAddress,u
                    leax      SC.GfxCmdDstXO,x
                    ldd       cmdDstX,u
                    lbsr      writeWordLEMem
                    ldx       cmdMapAddress,u
                    leax      SC.GfxCmdDstYO,x
                    ldd       cmdDstY,u
                    lbsr      writeWordLEMem
                    ldx       cmdMapAddress,u
                    leax      SC.GfxCmdWidthO,x
                    ldd       cmdWidth,u
                    lbsr      writeWordLEMem
                    ldx       cmdMapAddress,u
                    leax      SC.GfxCmdHeightO,x
                    ldd       cmdHeight,u
                    lbsr      writeWordLEMem
                    lbsr      endCommand
                    rts
bfcBad              orcc      #Carry
                    rts

buildBlitCommand    lbsr      beginCommand
                    lbcs      bbcBad
                    ldx       cmdMapAddress,u
                    lda       #1
                    sta       SC.GfxCmdABIMajorO,x
                    lda       #SC.GraphicsOpBlit
                    sta       SC.GfxCmdOperationO,x
                    leax      SC.GfxCmdSourceO,x
                    lbsr      writeSourceSurface
                    ldx       cmdMapAddress,u
                    leax      SC.GfxCmdDestO,x
                    lbsr      writeDestSurface
                    lbsr      writeCommandCoordinates
                    lbsr      endCommand
                    rts
bbcBad              orcc      #Carry
                    rts

buildMaskedCommand  lbsr      beginCommand
                    lbcs      bmcBad
                    ldx       cmdMapAddress,u
                    lda       #1
                    sta       SC.GfxCmdABIMajorO,x
                    lda       #SC.GraphicsOpMasked
                    sta       SC.GfxCmdOperationO,x
                    lda       #0
                    sta       SC.GfxCmdColorO,x
                    leax      SC.GfxCmdSourceO,x
                    lbsr      writeSourceSurface
                    ldx       cmdMapAddress,u
                    leax      SC.GfxCmdDestO,x
                    lbsr      writeDestSurface
                    lbsr      writeCommandCoordinates
                    lbsr      endCommand
                    rts
bmcBad              orcc      #Carry
                    rts

writeCommandCoordinates
                    ldx       cmdMapAddress,u
                    leax      SC.GfxCmdSrcXO,x
                    ldd       cmdSrcX,u
                    lbsr      writeWordLEMem
                    ldx       cmdMapAddress,u
                    leax      SC.GfxCmdSrcYO,x
                    ldd       cmdSrcY,u
                    lbsr      writeWordLEMem
                    ldx       cmdMapAddress,u
                    leax      SC.GfxCmdDstXO,x
                    ldd       cmdDstX,u
                    lbsr      writeWordLEMem
                    ldx       cmdMapAddress,u
                    leax      SC.GfxCmdDstYO,x
                    ldd       cmdDstY,u
                    lbsr      writeWordLEMem
                    ldx       cmdMapAddress,u
                    leax      SC.GfxCmdWidthO,x
                    ldd       cmdWidth,u
                    lbsr      writeWordLEMem
                    ldx       cmdMapAddress,u
                    leax      SC.GfxCmdHeightO,x
                    ldd       cmdHeight,u
                    lbsr      writeWordLEMem
                    rts

********************************************************************
* MEDIA Job V1 submission. MBO2 contains record index 0.
********************************************************************
submitGraphics      ldx       #SC.MediaJobBase+SC.JobStateO
                    lbsr      SC_READ8
                    lbcs      sgBad
                    cmpa      #SC.JobIdle
                    lbne      sgBad

                    ldd       jobTag,u
                    addd      #1
                    std       jobTag,u

                    ldx       #SC.MediaJobBase+SC.JobOpcodeO
                    lda       #SC.GraphicsOpcode
                    lbsr      SC_WRITE8
                    lbcs      sgBad
                    ldx       #SC.MediaJobBase+SC.JobFlagsO
                    clra
                    lbsr      SC_WRITE8
                    lbcs      sgBad
                    ldx       #SC.MediaJobBase+SC.JobTagLoO
                    lda       jobTag+1,u
                    lbsr      SC_WRITE8
                    lbcs      sgBad
                    leax      1,x
                    lda       jobTag,u
                    lbsr      SC_WRITE8
                    lbcs      sgBad

* ARG0 = command MBO slot 2.
                    ldx       #SC.MediaJobBase+SC.JobArg0LoO
                    lda       #Slot.Cmd
                    lbsr      SC_WRITE8
                    lbcs      sgBad
                    leax      1,x
                    clra
                    lbsr      SC_WRITE8
                    lbcs      sgBad

* ARG1/ARG2 are the little-endian command-MBO generation.
                    ldx       #SC.MediaJobBase+SC.JobArg1LoO
                    lda       cmdGeneration,u
                    lbsr      SC_WRITE8
                    lbcs      sgBad
                    leax      1,x
                    lda       cmdGeneration+1,u
                    lbsr      SC_WRITE8
                    lbcs      sgBad
                    leax      1,x
                    lda       cmdGeneration+2,u
                    lbsr      SC_WRITE8
                    lbcs      sgBad
                    leax      1,x
                    lda       cmdGeneration+3,u
                    lbsr      SC_WRITE8
                    lbcs      sgBad

* ARG3 record index = 0.
                    ldx       #SC.MediaJobBase+SC.JobArg3LoO
                    clra
                    lbsr      SC_WRITE8
                    lbcs      sgBad
                    leax      1,x
                    clra
                    lbsr      SC_WRITE8
                    lbcs      sgBad

* Legacy Job buffer descriptors must remain all zero for R1K.
                    ldx       #SC.MediaJobBase+SC.JobBuf0O
sgZeroBuf           clra
                    lbsr      SC_WRITE8
                    lbcs      sgBad
                    leax      1,x
                    cmpx      #SC.MediaJobBase+SC.JobBufEndO+1
                    lblo      sgZeroBuf

                    lda       #SC.IRQMedia
                    lbsr      SC_IRQ_ACK
                    ldx       #SC.MediaJobBase+SC.JobControlO
                    lda       #SC.JobCtlSubmit
                    lbsr      SC_WRITE8
                    lbcs      sgBad
                    clrb
                    andcc     #^Carry
                    rts
sgBad               ldb       #E$NotRdy
                    orcc      #Carry
                    rts

waitGraphicsJob     ldy       #$FFFF
wgjLoop             ldx       #SC.MediaJobBase+SC.JobStateO
                    lbsr      SC_READ8
                    lbcs      wgjBad
                    cmpa      #SC.JobComplete
                    lbeq      wgjDone
                    cmpa      #SC.JobErrorState
                    lbeq      wgjBad
                    cmpa      #SC.JobPending
                    lbeq      wgjNext
                    cmpa      #SC.JobBusy
                    lbeq      wgjNext
                    lbra      wgjBad
wgjNext             leay      -1,y
                    lbne      wgjLoop
                    lbra      wgjBad
wgjDone             ldx       #SC.MediaJobBase+SC.JobResultO
                    lbsr      SC_READ8
                    lbcs      wgjBad
                    tsta
                    lbne      wgjBad
                    lbsr      SC_IRQ_GET
                    bita      #SC.IRQMedia
                    lbeq      wgjBad
                    lda       #SC.IRQMedia
                    lbsr      SC_IRQ_ACK
                    ldx       #SC.MediaJobBase+SC.JobControlO
                    lda       #SC.JobCtlAck
                    lbsr      SC_WRITE8
                    lbcs      wgjBad
                    ldx       #SC.MediaJobBase+SC.JobStateO
                    lbsr      SC_READ8
                    lbcs      wgjBad
                    cmpa      #SC.JobIdle
                    lbne      wgjBad
                    clrb
                    andcc     #^Carry
                    rts
wgjBad              ldb       #E$NotRdy
                    orcc      #Carry
                    rts

issueFill           lbsr      buildFillCommand
                    lbcs      ifBad
                    lbsr      submitGraphics
                    lbcs      ifBad
                    lbsr      waitGraphicsJob
                    rts
ifBad               orcc      #Carry
                    rts

issueBlit           lbsr      buildBlitCommand
                    lbcs      ibBad
                    lbsr      submitGraphics
                    lbcs      ibBad
                    lbsr      waitGraphicsJob
                    rts
ibBad               orcc      #Carry
                    rts

issueMasked         lbsr      buildMaskedCommand
                    lbcs      imBad
                    lbsr      submitGraphics
                    lbcs      imBad
                    lbsr      waitGraphicsJob
                    rts
imBad               orcc      #Carry
                    rts

********************************************************************
* R1K rendering. Full-screen initialization plus four operations/frame.
********************************************************************
fillWholeSurface
* Entry A = palette index, renderSlot selects destination.
                    sta       cmdColor,u
                    clra
                    clrb
                    std       cmdDstX,u
                    std       cmdDstY,u
                    ldd       #640
                    std       cmdWidth,u
                    ldd       #480
                    std       cmdHeight,u
                    lbsr      issueFill
                    rts

renderDynamicFrame
* FILL top tile band with dark red.
                    lda       #4
                    sta       cmdColor,u
                    clra
                    clrb
                    std       cmdDstX,u
                    ldd       #Tile.Y
                    std       cmdDstY,u
                    ldd       #640
                    std       cmdWidth,u
                    ldd       #Tile.Height
                    std       cmdHeight,u
                    lbsr      issueFill
                    lbcs      rdfBad

* FILL sprite band with green, making masked transparency obvious.
                    lda       #2
                    sta       cmdColor,u
                    clra
                    clrb
                    std       cmdDstX,u
                    ldd       #Sprite.Y
                    std       cmdDstY,u
                    ldd       #640
                    std       cmdWidth,u
                    ldd       #Sprite.Height
                    std       cmdHeight,u
                    lbsr      issueFill
                    lbcs      rdfBad

* Opaque BLIT: MBO3 rows 0..7 -> moving 64x8 tile.
                    clra
                    clrb
                    std       cmdSrcX,u
                    std       cmdSrcY,u
                    ldd       tileX,u
                    std       cmdDstX,u
                    ldd       #Tile.Y
                    std       cmdDstY,u
                    ldd       #Tile.Width
                    std       cmdWidth,u
                    ldd       #Tile.Height
                    std       cmdHeight,u
                    lbsr      issueBlit
                    lbcs      rdfBad

* MASKED BLIT: MBO3 rows 16..31 -> moving 32x16 sprite, color 0 transparent.
                    clra
                    clrb
                    std       cmdSrcX,u
                    ldd       #16
                    std       cmdSrcY,u
                    ldd       spriteX,u
                    std       cmdDstX,u
                    ldd       #Sprite.Y
                    std       cmdDstY,u
                    ldd       #Sprite.Width
                    std       cmdWidth,u
                    ldd       #Sprite.Height
                    std       cmdHeight,u
                    lbsr      issueMasked
                    lbcs      rdfBad
                    clrb
                    andcc     #^Carry
                    rts
rdfBad              ldb       #E$NotRdy
                    orcc      #Carry
                    rts

********************************************************************
* R1L stream 0. The ring is periodic and immutable, so after a half-ring has
* been consumed MAIN can republish those returned slots without rewriting.
********************************************************************
configureAudio      ldx       #SC.AudioStreamBase+SC.AudioStrStatusO
                    lbsr      SC_READ8
                    lbcs      caBad
                    bita      #SC.AudioStrRunning
                    lbne      caBad

                    ldx       #SC.AudioStreamBase+SC.AudioStrMBOSlotO
                    lda       #Slot.Audio
                    lbsr      SC_WRITE8
                    lbcs      caBad
                    ldx       #SC.AudioStreamBase+SC.AudioStrFormatO
                    lda       #SC.AudioFmtS16LEStereo
                    lbsr      SC_WRITE8
                    lbcs      caBad
                    ldx       #SC.AudioStreamBase+SC.AudioStrGenerationO
                    pshs      u
                    leau      audioGeneration,u
                    lbsr      SC_WRITE32LE
                    puls      u
                    lbcs      caBad

* offset = 0.
                    ldx       #SC.AudioStreamBase+SC.AudioStrOffsetO
                    clra
                    lbsr      SC_WRITE8
                    lbcs      caBad
                    leax      1,x
                    clra
                    lbsr      SC_WRITE8
                    lbcs      caBad
                    leax      1,x
                    clra
                    lbsr      SC_WRITE8
                    lbcs      caBad
                    leax      1,x
                    clra
                    lbsr      SC_WRITE8
                    lbcs      caBad

* ring_frames = producer_stage = 32768 ($00008000).
                    clr       audioProducer,u
                    lda       #$80
                    sta       audioProducer+1,u
                    clr       audioProducer+2,u
                    clr       audioProducer+3,u
                    ldx       #SC.AudioStreamBase+SC.AudioStrRingFramesO
                    pshs      u
                    leau      audioProducer,u
                    lbsr      SC_WRITE32LE
                    puls      u
                    lbcs      caBad
                    lbsr      writeAudioProducerStage
                    lbcs      caBad

* Low-water/events are not part of this proof; keep local causes masked so
* VIDEO/MEDIA event observation remains independent while audio streams.
                    ldx       #SC.AudioStreamBase+SC.AudioStrLowWaterO
                    clra
                    lbsr      SC_WRITE8
                    lbcs      caBad
                    leax      1,x
                    lda       #$10
                    lbsr      SC_WRITE8
                    lbcs      caBad
                    ldx       #SC.AudioStreamBase+SC.AudioStrGainLO
                    lda       #$FF
                    lbsr      SC_WRITE8
                    lbcs      caBad
                    leax      1,x
                    lda       #$FF
                    lbsr      SC_WRITE8
                    lbcs      caBad
                    ldx       #SC.AudioStreamBase+SC.AudioStrEventMaskO
                    clra
                    lbsr      SC_WRITE8
                    lbcs      caBad
                    ldx       #SC.AudioStreamBase+SC.AudioStrEventStatusO
                    lda       #SC.AudioEvLow!SC.AudioEvUnderrun!SC.AudioEvStale
                    lbsr      SC_WRITE8
                    lbcs      caBad
                    lda       #SC.IRQAudio
                    lbsr      SC_IRQ_ACK

* First returned half-ring boundary is sequence $00004000.
                    clr       audioNextRefill,u
                    lda       #$40
                    sta       audioNextRefill+1,u
                    clr       audioNextRefill+2,u
                    clr       audioNextRefill+3,u
                    clr       audioRefillCount,u
* START may take effect even if a later observation fails, so cleanup owns it
* from this point forward.
                    lda       resourceFlags1,u
                    ora       #RF1.AudioRunning
                    sta       resourceFlags1,u
                    ldx       #SC.AudioStreamBase+SC.AudioStrControlO
                    lda       #SC.AudioCtlStart
                    lbsr      SC_WRITE8
                    lbcs      caBad
                    clrb
                    andcc     #^Carry
                    rts
caBad               ldb       #E$NotRdy
                    orcc      #Carry
                    rts

writeAudioProducerStage
                    ldx       #SC.AudioStreamBase+SC.AudioStrProdStageO
                    pshs      u
                    leau      audioProducer,u
                    lbsr      SC_WRITE32LE
                    puls      u
                    rts

commitAudioProducer lbsr      writeAudioProducerStage
                    lbcs      capBad
                    ldx       #SC.AudioStreamBase+SC.AudioStrControlO
                    lda       #SC.AudioCtlProdCommit
                    lbsr      SC_WRITE8
                    rts
capBad              orcc      #Carry
                    rts

readAudioConsumer32 ldx       #SC.AudioStreamBase+SC.AudioStrConsumerO
                    pshs      u
                    leau      audioConsumer,u
                    lbsr      SC_READ32LE
                    puls      u
                    rts

readAudioUnderrunBase
                    ldx       #SC.AudioStreamBase+SC.AudioStrUnderrunO
                    pshs      u
                    leau      audioUnderrunBase,u
                    lbsr      SC_READ32LE
                    puls      u
                    rts

readAudioUnderrunNow
                    ldx       #SC.AudioStreamBase+SC.AudioStrUnderrunO
                    pshs      u
                    leau      audioUnderrunNow,u
                    lbsr      SC_READ32LE
                    puls      u
                    rts

waitAudioProgress   ldy       #$FFFF
wapLoop             lbsr      readAudioConsumer32
                    lbcs      wapBad
                    lda       audioConsumer,u
                    ora       audioConsumer+1,u
                    ora       audioConsumer+2,u
                    ora       audioConsumer+3,u
                    lbne      wapSeen
                    leay      -1,y
                    lbne      wapLoop
                    lbra      wapBad
wapSeen             ldx       #SC.AudioStreamBase+SC.AudioStrStatusO
                    lbsr      SC_READ8
                    lbcs      wapBad
                    bita      #SC.AudioStrRunning
                    lbeq      wapBad
                    ldb       #Slot.Audio
                    lbsr      SC_MBO_STATUS
                    lbcs      wapBad
                    bita      #SC.MBOStatusBusy
                    lbeq      wapBad
* Startup may legally record underrun frames before the FIFO primes. Snapshot
* that baseline only after real PCM progress has begun; S2A-4 forbids any new
* underrun frames during the concurrent graphics workload.
                    lbsr      readAudioUnderrunBase
                    lbcs      wapBad
                    clrb
                    andcc     #^Carry
                    rts
wapBad              ldb       #E$NotRdy
                    orcc      #Carry
                    rts

consumerAtNext      lda       audioConsumer+3,u
                    cmpa      audioNextRefill+3,u
                    lbhi      canYes
                    lblo      canNo
                    lda       audioConsumer+2,u
                    cmpa      audioNextRefill+2,u
                    lbhi      canYes
                    lblo      canNo
                    lda       audioConsumer+1,u
                    cmpa      audioNextRefill+1,u
                    lbhi      canYes
                    lblo      canNo
                    lda       audioConsumer,u
                    cmpa      audioNextRefill,u
                    lbcc      canYes
canNo               clra
                    clrb
                    andcc     #^Carry
                    rts
canYes              lda       #1
                    clrb
                    andcc     #^Carry
                    rts

addHalfProducer     lda       audioProducer+1,u
                    adda      #$40
                    sta       audioProducer+1,u
                    lbcc      ahpDone
                    inc       audioProducer+2,u
                    lbne      ahpDone
                    inc       audioProducer+3,u
ahpDone             rts

addHalfNext         lda       audioNextRefill+1,u
                    adda      #$40
                    sta       audioNextRefill+1,u
                    lbcc      ahnDone
                    inc       audioNextRefill+2,u
                    lbne      ahnDone
                    inc       audioNextRefill+3,u
ahnDone             rts

serviceAudio        lda       resourceFlags1,u
                    bita      #RF1.AudioRunning
                    lbeq      sarDone
                    lbsr      readAudioConsumer32
                    lbcs      sarBad
sarAgain            lbsr      consumerAtNext
                    lbcs      sarBad
                    tsta
                    lbeq      sarDone
* Exactly one returned half-ring (16384 frames) becomes newly publishable.
                    lbsr      addHalfProducer
                    lbsr      commitAudioProducer
                    lbcs      sarBad
                    lbsr      addHalfNext
                    inc       audioRefillCount,u
                    lbra      sarAgain
sarDone             clrb
                    andcc     #^Carry
                    rts
sarBad              ldb       #E$NotRdy
                    orcc      #Carry
                    rts

verifyAudioConcurrent
* Two seconds of VBLANK-paced animation must cross several half-ring ownership
* boundaries. Four producer commits proves the stream continued consuming while
* MEDIA jobs and VIDEO swaps were active.
                    lda       audioRefillCount,u
                    cmpa      #4
                    lblo      vacBad
                    lbsr      readAudioConsumer32
                    lbcs      vacBad
                    lda       audioConsumer,u
                    ora       audioConsumer+1,u
                    ora       audioConsumer+2,u
                    ora       audioConsumer+3,u
                    lbeq      vacBad
                    ldx       #SC.AudioStreamBase+SC.AudioStrStatusO
                    lbsr      SC_READ8
                    lbcs      vacBad
                    bita      #SC.AudioStrRunning
                    lbeq      vacBad
                    bita      #SC.AudioStrStale
                    lbne      vacBad
* No underrun frames may be added after the post-startup baseline.
                    lbsr      readAudioUnderrunNow
                    lbcs      vacBad
                    lda       audioUnderrunNow,u
                    cmpa      audioUnderrunBase,u
                    lbne      vacBad
                    lda       audioUnderrunNow+1,u
                    cmpa      audioUnderrunBase+1,u
                    lbne      vacBad
                    lda       audioUnderrunNow+2,u
                    cmpa      audioUnderrunBase+2,u
                    lbne      vacBad
                    lda       audioUnderrunNow+3,u
                    cmpa      audioUnderrunBase+3,u
                    lbne      vacBad
                    clrb
                    andcc     #^Carry
                    rts
vacBad              ldb       #E$NotRdy
                    orcc      #Carry
                    rts

stopAudio           lda       resourceFlags1,u
                    bita      #RF1.AudioRunning
                    lbeq      staDone
* If START never took effect (or stale authority already stopped the stream),
* clear our conservative cleanup flag without issuing an illegal STOP.
                    ldx       #SC.AudioStreamBase+SC.AudioStrStatusO
                    lbsr      SC_READ8
                    lbcs      staBad
                    bita      #SC.AudioStrRunning
                    lbeq      staStopped
                    ldx       #SC.AudioStreamBase+SC.AudioStrControlO
                    lda       #SC.AudioCtlStop
                    lbsr      SC_WRITE8
                    lbcs      staBad
                    ldy       #$FFFF
staWait             ldx       #SC.AudioStreamBase+SC.AudioStrStatusO
                    lbsr      SC_READ8
                    lbcs      staBad
                    bita      #SC.AudioStrRunning
                    lbeq      staStopped
                    leay      -1,y
                    lbne      staWait
                    lbra      staBad
staStopped          ldb       #Slot.Audio
                    lbsr      SC_MBO_STATUS
                    lbcs      staBad
                    bita      #SC.MBOStatusBusy
                    lbne      staBad
                    lda       resourceFlags1,u
                    anda      #^RF1.AudioRunning
                    sta       resourceFlags1,u
staDone             clrb
                    andcc     #^Carry
                    rts
staBad              ldb       #E$NotRdy
                    orcc      #Carry
                    rts

********************************************************************
* Enter native output on surface 0; surface 1 becomes the first back buffer.
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
                    lda       resourceFlags1,u
                    ora       #RF1.Video
                    sta       resourceFlags1,u
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
                    ldb       #Slot.FB0
                    lbsr      SC_MBO_STATUS
                    lbcs      edBad
                    bita      #SC.MBOStatusBusy
                    lbeq      edBad
                    ldb       #Slot.FB1
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

animateFrames       lda       #Anim.Frames
                    sta       framesLeft,u
afLoop              lbsr      serviceAudio
                    lbcs      afBad
                    lda       backSurface,u
                    sta       renderSlot,u
                    lbsr      renderDynamicFrame
                    lbcs      afBad
                    lbsr      serviceAudio
                    lbcs      afBad
                    lbsr      flipDisplay
                    lbcs      afBad
                    lbsr      serviceAudio
                    lbcs      afBad
                    lbsr      advanceMotion
                    dec       framesLeft,u
                    lbne      afLoop
                    clrb
                    andcc     #^Carry
                    rts
afBad               ldb       #E$NotRdy
                    orcc      #Carry
                    rts

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

advanceMotion       lbsr      advanceTile
                    lbsr      advanceSprite
                    rts

advanceTile         lda       tileDir,u
                    lbne      atLeft
                    ldd       tileX,u
                    addd      #Tile.Step
                    cmpd      #Tile.MaxX
                    lblo      atStoreRight
                    ldd       #Tile.MaxX
                    std       tileX,u
                    lda       #1
                    sta       tileDir,u
                    rts
atStoreRight        std       tileX,u
                    rts
atLeft              ldd       tileX,u
                    subd      #Tile.Step
                    std       tileX,u
                    lbne      atDone
                    clr       tileDir,u
atDone              rts

advanceSprite       lda       spriteDir,u
                    lbne      asLeft
                    ldd       spriteX,u
                    addd      #Sprite.Step
                    cmpd      #Sprite.MaxX
                    lblo      asStoreRight
                    ldd       #Sprite.MaxX
                    std       spriteX,u
                    lda       #1
                    sta       spriteDir,u
                    rts
asStoreRight        std       spriteX,u
                    rts
asLeft              ldd       spriteX,u
                    subd      #Sprite.Step
                    lbpl      asStoreLeft
                    clra
                    clrb
                    std       spriteX,u
                    clr       spriteDir,u
                    rts
asStoreLeft         std       spriteX,u
                    lbne      asDone
                    clr       spriteDir,u
asDone              rts

********************************************************************
* Disable native output at VBLANK.
********************************************************************
disableDisplay      lda       resourceFlags1,u
                    bita      #RF1.Video
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
                    lda       resourceFlags1,u
                    anda      #^RF1.Video
                    sta       resourceFlags1,u
ddDone              clrb
                    andcc     #^Carry
                    rts
ddBad               ldb       #E$NotRdy
                    orcc      #Carry
                    rts

********************************************************************
* Best-effort MEDIA terminal drain for cleanup.
********************************************************************
drainMediaJob       ldy       #$FFFF
dmjLoop             ldx       #SC.MediaJobBase+SC.JobStateO
                    lbsr      SC_READ8
                    lbcs      dmjBad
                    cmpa      #SC.JobIdle
                    lbeq      dmjDone
                    cmpa      #SC.JobComplete
                    lbeq      dmjAck
                    cmpa      #SC.JobErrorState
                    lbeq      dmjAck
                    cmpa      #SC.JobPending
                    lbeq      dmjNext
                    cmpa      #SC.JobBusy
                    lbeq      dmjNext
                    lbra      dmjBad
dmjNext             leay      -1,y
                    lbne      dmjLoop
                    lbra      dmjBad
dmjAck              lda       #SC.IRQMedia
                    lbsr      SC_IRQ_ACK
                    ldx       #SC.MediaJobBase+SC.JobControlO
                    lda       #SC.JobCtlAck
                    lbsr      SC_WRITE8
                    lbcs      dmjBad
dmjDone             clrb
                    andcc     #^Carry
                    rts
dmjBad              ldb       #E$NotRdy
                    orcc      #Carry
                    rts

********************************************************************
* Revoke MBOs and wait for all consumer bindings to drain.
********************************************************************
revokeAudioMBO      lda       resourceFlags1,u
                    bita      #RF1.MBOAudio
                    lbeq      ramDone
                    ldb       #Slot.Audio
                    lbsr      SC_MBO_STATUS
                    lbcs      ramBad
                    bita      #SC.MBOStatusBusy
                    lbne      ramBad
                    bita      #SC.MBOStatusValid
                    lbeq      ramClear
                    ldb       #Slot.Audio
                    lbsr      SC_MBO_REVOKE
                    lbcs      ramBad
ramClear            lda       resourceFlags1,u
                    anda      #^RF1.MBOAudio
                    sta       resourceFlags1,u
ramDone             clrb
                    andcc     #^Carry
                    rts
ramBad              ldb       #E$NotRdy
                    orcc      #Carry
                    rts

revokeFramebufferMBO0
                    lda       #Slot.FB0
                    sta       mboSlot,u
                    lda       #RF0.MBO0
                    sta       mboFlagMask,u
                    lbsr      revokeMBO
                    rts

revokeFramebufferMBO1
                    lda       #Slot.FB1
                    sta       mboSlot,u
                    lda       #RF0.MBO1
                    sta       mboFlagMask,u
                    lbsr      revokeMBO
                    rts

revokeCommandMBO    lda       #Slot.Cmd
                    sta       mboSlot,u
                    lda       #RF0.MBOCmd
                    sta       mboFlagMask,u
                    lbsr      revokeMBO
                    rts

revokeSourceMBO     lda       #Slot.Src
                    sta       mboSlot,u
                    lda       #RF0.MBOSrc
                    sta       mboFlagMask,u
                    lbsr      revokeMBO
                    rts

revokeMBO           lda       resourceFlags0,u
                    anda      mboFlagMask,u
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
rmClear             lda       mboFlagMask,u
                    coma
                    anda      resourceFlags0,u
                    sta       resourceFlags0,u
rmDone              clrb
                    andcc     #^Carry
                    rts
rmBad               ldb       #E$NotRdy
                    orcc      #Carry
                    rts

********************************************************************
* Return OS RAM only after maps, VIDEO ownership, and all MBOs are gone.
********************************************************************
freeBacking         lda       resourceFlags0,u
                    anda      #RF0.MBO0!RF0.MBO1!RF0.MBOCmd!RF0.MBOSrc
                    lbne      fbkBad
                    lda       resourceFlags1,u
                    bita      #RF1.Video!RF1.CmdMapped!RF1.SrcMapped!RF1.MBOAudio!RF1.AudioRunning!RF1.AudioMapped
                    lbne      fbkBad

                    lda       resourceFlags1,u
                    bita      #RF1.RAMAudio
                    lbeq      fbkSrc
                    ldb       #Audio.Blocks
                    ldx       audioStartBlock,u
                    os9       F$DelRAM
                    lbcs      fbkBad
                    lda       resourceFlags1,u
                    anda      #^RF1.RAMAudio
                    sta       resourceFlags1,u
fbkSrc              lda       resourceFlags0,u
                    bita      #RF0.RAMSrc
                    lbeq      fbkCmd
                    ldb       #Small.Blocks
                    ldx       srcStartBlock,u
                    os9       F$DelRAM
                    lbcs      fbkBad
                    lda       resourceFlags0,u
                    anda      #^RF0.RAMSrc
                    sta       resourceFlags0,u
fbkCmd              lda       resourceFlags0,u
                    bita      #RF0.RAMCmd
                    lbeq      fbkFB1
                    ldb       #Small.Blocks
                    ldx       cmdStartBlock,u
                    os9       F$DelRAM
                    lbcs      fbkBad
                    lda       resourceFlags0,u
                    anda      #^RF0.RAMCmd
                    sta       resourceFlags0,u
fbkFB1              lda       resourceFlags0,u
                    bita      #RF0.RAM1
                    lbeq      fbkFB0
                    ldb       #FB.Blocks
                    ldx       fb1StartBlock,u
                    os9       F$DelRAM
                    lbcs      fbkBad
                    lda       resourceFlags0,u
                    anda      #^RF0.RAM1
                    sta       resourceFlags0,u
fbkFB0              lda       resourceFlags0,u
                    bita      #RF0.RAM0
                    lbeq      fbkDone
                    ldb       #FB.Blocks
                    ldx       fb0StartBlock,u
                    os9       F$DelRAM
                    lbcs      fbkBad
                    lda       resourceFlags0,u
                    anda      #^RF0.RAM0
                    sta       resourceFlags0,u
fbkDone             clrb
                    andcc     #^Carry
                    rts
fbkBad              ldb       #E$NotRdy
                    orcc      #Carry
                    rts

cleanupBestEffort   lbsr      drainMediaJob
                    lbsr      disableDisplay
                    lbsr      stopAudio
                    lbsr      unmapCommand
                    lbsr      unmapSource
                    lbsr      unmapAudioCurrent
                    lbsr      revokeAudioMBO
                    lbsr      revokeSourceMBO
                    lbsr      revokeCommandMBO
                    lbsr      revokeFramebufferMBO1
                    lbsr      revokeFramebufferMBO0
                    lbsr      freeBacking
                    rts

writeLine           lda       #1
                    os9       I$WritLn
                    rts

* Shared S1B SuperCoCo service helpers.
                    use       ../libs/scsys/scsys.inc

                    emod
eom                 equ       *
                    end
