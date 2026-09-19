********************************************************************
* scinfo - SuperCoCo Community Alpha service discovery utility
*
* Uses only the frozen invariant service portal and capability pages.
* No emulator-only side channel is used.  The same binary is intended to
* identify the future hardware implementation of these frozen contracts.
********************************************************************

                    nam       scinfo
                    ttl       SuperCoCo Community Alpha discovery

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
portalValue         rmb       1
stackSpace          rmb       128
size                equ       .

name                fcs       /scinfo/
                    fcb       edition

msgBanner           fcc       /SuperCoCo Community Alpha discovery/
                    fcb       C$CR
msgBannerLen        equ       *-msgBanner
msgSystem           fcc       /  SYSTEM   ABI 1.1+  portal and event fabric PASS/
                    fcb       C$CR
msgSystemLen        equ       *-msgSystem
msgMBO              fcc       /  MBO      V1  16 slots x 64 pages PASS/
                    fcb       C$CR
msgMBOLen           equ       *-msgMBO
msgVideo            fcc       /  VIDEO    V1  640x480 INDEX4 RGB888 PASS/
                    fcb       C$CR
msgVideoLen         equ       *-msgVideo
msgGraphics         fcc       /  GRAPHICS V1  MEDIA fill, blit, masked PASS/
                    fcb       C$CR
msgGraphicsLen      equ       *-msgGraphics
msgAudio            fcc       /  AUDIO    V1  48k S16LE stereo x16 PASS/
                    fcb       C$CR
msgAudioLen         equ       *-msgAudio
msgReady            fcc       /SuperCoCo R1L software surface READY/
                    fcb       C$CR
msgReadyLen         equ       *-msgReady
msgFail             fcc       /scinfo: required SuperCoCo R1L service missing or incompatible/
                    fcb       C$CR
msgFailLen          equ       *-msgFail

start
                    leax      msgBanner,pcr
                    ldy       #msgBannerLen
                    lbsr      writeln

                    lbsr      checkSystem
                    lbcs      fail
                    leax      msgSystem,pcr
                    ldy       #msgSystemLen
                    lbsr      writeln

                    lbsr      checkMBO
                    lbcs      fail
                    leax      msgMBO,pcr
                    ldy       #msgMBOLen
                    lbsr      writeln

                    lbsr      checkVideo
                    lbcs      fail
                    leax      msgVideo,pcr
                    ldy       #msgVideoLen
                    lbsr      writeln

                    lbsr      checkGraphics
                    lbcs      fail
                    leax      msgGraphics,pcr
                    ldy       #msgGraphicsLen
                    lbsr      writeln

                    lbsr      checkAudio
                    lbcs      fail
                    leax      msgAudio,pcr
                    ldy       #msgAudioLen
                    lbsr      writeln

                    leax      msgReady,pcr
                    ldy       #msgReadyLen
                    lbsr      writeln
                    clrb
                    os9       F$Exit

fail                leax      msgFail,pcr
                    ldy       #msgFailLen
                    lbsr      writeln
                    ldb       #E$NotRdy
                    os9       F$Exit

********************************************************************
* Portal read helper.
* X = 16-bit service address.
* Returns A = data and carry clear, or carry set on timeout/service error.
********************************************************************
portalRead          pshs      b,x,y
                    tfr       x,d
                    stb       >SC.SvcAddrLo
                    sta       >SC.SvcAddrHi
                    lda       #SC.SvcRead
                    sta       >SC.SvcCommand
                    ldy       #$FFFF
prWait              lda       >SC.SvcStatus
                    bita      #SC.SvcDone
                    bne       prDone
                    leay      -1,y
                    bne       prWait
                    puls      b,x,y
                    orcc      #Carry
                    rts
prDone              bita      #SC.SvcError
                    bne       prBad
                    lda       >SC.SvcRData
                    puls      b,x,y
                    andcc     #^Carry
                    rts
prBad               puls      b,x,y
                    orcc      #Carry
                    rts

********************************************************************
* System ABI and required R1I-R1L capability bits.
********************************************************************
checkSystem         ldx       #SC.SysMagic0
                    lbsr      portalRead
                    lbcs      chkBad
                    cmpa      #'S
                    lbne      chkBad
                    ldx       #SC.SysMagic1
                    lbsr      portalRead
                    lbcs      chkBad
                    cmpa      #'C
                    lbne      chkBad
                    ldx       #SC.SysABIMajor
                    lbsr      portalRead
                    lbcs      chkBad
                    cmpa      #1
                    lbne      chkBad
                    ldx       #SC.SysABIMinor
                    lbsr      portalRead
                    lbcs      chkBad
                    cmpa      #1
                    lbcs      chkBad
                    ldx       #SC.SysCaps0
                    lbsr      portalRead
                    lbcs      chkBad
                    anda      #SC.CapMBOV1!SC.CapVideoV1!SC.CapGraphicsV1
                    cmpa      #SC.CapMBOV1!SC.CapVideoV1!SC.CapGraphicsV1
                    lbne      chkBad
                    ldx       #SC.SysCaps1
                    lbsr      portalRead
                    lbcs      chkBad
                    bita      #SC.Cap1AudioV1
                    lbeq      chkBad
                    andcc     #^Carry
                    rts

checkMBO            ldx       #SC.MBOABIMajor
                    lbsr      portalRead
                    lbcs      chkBad
                    cmpa      #1
                    lbne      chkBad
                    ldx       #SC.MBOABIMinor
                    lbsr      portalRead
                    lbcs      chkBad
                    tsta
                    lbne      chkBad
                    ldx       #SC.MBOSlotCount
                    lbsr      portalRead
                    lbcs      chkBad
                    cmpa      #16
                    lbne      chkBad
                    ldx       #SC.MBOMaxPages
                    lbsr      portalRead
                    lbcs      chkBad
                    cmpa      #64
                    lbne      chkBad
                    ldx       #SC.MBOPageShift
                    lbsr      portalRead
                    lbcs      chkBad
                    cmpa      #12
                    lbne      chkBad
                    ldx       #SC.MBOStrideShift
                    lbsr      portalRead
                    lbcs      chkBad
                    cmpa      #9
                    lbne      chkBad
                    andcc     #^Carry
                    rts

checkVideo          ldx       #SC.VideoABIMajor
                    lbsr      portalRead
                    lbcs      chkBad
                    cmpa      #1
                    lbne      chkBad
                    ldx       #SC.VideoABIMinor
                    lbsr      portalRead
                    lbcs      chkBad
                    tsta
                    lbne      chkBad
                    ldx       #SC.VideoFormat
                    lbsr      portalRead
                    lbcs      chkBad
                    cmpa      #SC.VideoFmtIndex4
                    lbne      chkBad
                    ldx       #SC.VideoWidthLo
                    lbsr      portalRead
                    lbcs      chkBad
                    cmpa      #$80
                    lbne      chkBad
                    ldx       #SC.VideoWidthHi
                    lbsr      portalRead
                    lbcs      chkBad
                    cmpa      #$02
                    lbne      chkBad
                    ldx       #SC.VideoHeightLo
                    lbsr      portalRead
                    lbcs      chkBad
                    cmpa      #$E0
                    lbne      chkBad
                    ldx       #SC.VideoHeightHi
                    lbsr      portalRead
                    lbcs      chkBad
                    cmpa      #$01
                    lbne      chkBad
                    ldx       #SC.VideoStrideLo
                    lbsr      portalRead
                    lbcs      chkBad
                    cmpa      #$40
                    lbne      chkBad
                    ldx       #SC.VideoStrideHi
                    lbsr      portalRead
                    lbcs      chkBad
                    cmpa      #$01
                    lbne      chkBad
                    ldx       #SC.VideoPaletteCount
                    lbsr      portalRead
                    lbcs      chkBad
                    cmpa      #16
                    lbne      chkBad
                    ldx       #SC.VideoSurfaceCount
                    lbsr      portalRead
                    lbcs      chkBad
                    cmpa      #2
                    lbne      chkBad
                    andcc     #^Carry
                    rts

checkGraphics       ldx       #SC.GraphicsABIMajor
                    lbsr      portalRead
                    lbcs      chkBad
                    cmpa      #1
                    lbne      chkBad
                    ldx       #SC.GraphicsABIMinor
                    lbsr      portalRead
                    lbcs      chkBad
                    tsta
                    lbne      chkBad
                    ldx       #SC.GraphicsMediaSlot
                    lbsr      portalRead
                    lbcs      chkBad
                    cmpa      #3
                    lbne      chkBad
                    ldx       #SC.GraphicsJobOpcode
                    lbsr      portalRead
                    lbcs      chkBad
                    cmpa      #SC.GraphicsOpcode
                    lbne      chkBad
                    ldx       #SC.GraphicsCmdSize
                    lbsr      portalRead
                    lbcs      chkBad
                    cmpa      #64
                    lbne      chkBad
                    ldx       #SC.GraphicsFormat
                    lbsr      portalRead
                    lbcs      chkBad
                    cmpa      #SC.GraphicsFmtIndex4
                    lbne      chkBad
                    ldx       #SC.GraphicsMaxWLo
                    lbsr      portalRead
                    lbcs      chkBad
                    cmpa      #$80
                    lbne      chkBad
                    ldx       #SC.GraphicsMaxWHi
                    lbsr      portalRead
                    lbcs      chkBad
                    cmpa      #$02
                    lbne      chkBad
                    ldx       #SC.GraphicsMaxHLo
                    lbsr      portalRead
                    lbcs      chkBad
                    cmpa      #$E0
                    lbne      chkBad
                    ldx       #SC.GraphicsMaxHHi
                    lbsr      portalRead
                    lbcs      chkBad
                    cmpa      #$01
                    lbne      chkBad
                    andcc     #^Carry
                    rts

checkAudio          ldx       #SC.AudioABIMajor
                    lbsr      portalRead
                    lbcs      chkBad
                    cmpa      #1
                    lbne      chkBad
                    ldx       #SC.AudioABIMinor
                    lbsr      portalRead
                    lbcs      chkBad
                    tsta
                    lbne      chkBad
                    ldx       #SC.AudioStreamCount
                    lbsr      portalRead
                    lbcs      chkBad
                    cmpa      #16
                    lbne      chkBad
                    ldx       #SC.AudioFormat
                    lbsr      portalRead
                    lbcs      chkBad
                    cmpa      #SC.AudioFmtS16LEStereo
                    lbne      chkBad
                    ldx       #SC.AudioFrameBytes
                    lbsr      portalRead
                    lbcs      chkBad
                    cmpa      #4
                    lbne      chkBad
                    ldx       #SC.AudioFIFOMin
                    lbsr      portalRead
                    lbcs      chkBad
                    cmpa      #64
                    lbne      chkBad
                    ldx       #SC.AudioRate0
                    lbsr      portalRead
                    lbcs      chkBad
                    cmpa      #$80
                    lbne      chkBad
                    ldx       #SC.AudioRate1
                    lbsr      portalRead
                    lbcs      chkBad
                    cmpa      #$BB
                    lbne      chkBad
                    ldx       #SC.AudioRate2
                    lbsr      portalRead
                    lbcs      chkBad
                    tsta
                    lbne      chkBad
                    ldx       #SC.AudioRate3
                    lbsr      portalRead
                    lbcs      chkBad
                    tsta
                    lbne      chkBad
                    andcc     #^Carry
                    rts

chkBad              orcc      #Carry
                    rts

writeln             lda       #1
                    os9       I$WritLn
                    rts

                    emod
eom                 equ       *
                    end
