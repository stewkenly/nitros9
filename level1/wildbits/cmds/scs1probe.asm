********************************************************************
* scs1probe - SuperCoCo S1 common service/IRQ runtime acceptance
*
* This native NitrOS-9 program exercises the reusable S1 scsys layer
* against the frozen Community Alpha machine.  It intentionally leaves
* generation of real VIDEO events to scanim, which follows this probe in
* the retained S1 closure test.
********************************************************************

                    nam       scs1probe
                    ttl       SuperCoCo S1 common service/IRQ probe

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
savedMask           rmb       1
generation          rmb       4
rateBytes           rmb       4
stackSpace          rmb       128
size                equ       .

name                fcs       /scs1probe/
                    fcb       edition

msgDiscovery        fcc       /S1 DISCOVERY PORTAL PASS/
                    fcb       C$CR
msgDiscoveryLen     equ       *-msgDiscovery
msgIRQ              fcc       /S1 IRQ MASK STATUS W1C PASS/
                    fcb       C$CR
msgIRQLen           equ       *-msgIRQ
msgMBO              fcc       /S1 MBO HELPER PASS/
                    fcb       C$CR
msgMBOLen           equ       *-msgMBO
msgFinal            fcc       /SUPERCOCO S1 PASS/
                    fcb       C$CR
msgFinalLen         equ       *-msgFinal
msgFail             fcc       /SUPERCOCO S1 FAIL/
                    fcb       C$CR
msgFailLen          equ       *-msgFail

start
* Shared discovery must recognize the currently frozen R1L foundation.
                    lbsr      SC_PROBE_R1L
                    lbcs      fail

* Exercise the 32-bit portal helper on the fixed 48000 Hz Audio V1 rate.
                    pshs      u
                    leau      rateBytes,u
                    ldx       #SC.AudioRate0
                    lbsr      SC_READ32LE
                    lbcs      rateBad
                    lda       ,u
                    cmpa      #$80
                    lbne      rateBad
                    lda       1,u
                    cmpa      #$BB
                    lbne      rateBad
                    lda       2,u
                    lbne      rateBad
                    lda       3,u
                    lbne      rateBad
                    puls      u

                    leax      msgDiscovery,pcr
                    ldy       #msgDiscoveryLen
                    lbsr      writeLine

* Exercise mask get/set without leaving a live mask behind.  Clear all
* implemented summary causes before enabling any mask so a stale event cannot
* assert a CPU IRQ during this short register-level acceptance window.
                    lbsr      SC_IRQ_MASK_GET
                    lbcs      fail
                    sta       savedMask,u

                    lda       #SC.IRQImplemented
                    lbsr      SC_IRQ_ACK
                    lbcs      fail
                    lbsr      SC_IRQ_GET
                    lbcs      fail
                    anda      #SC.IRQImplemented
                    lbne      fail

                    lda       #SC.IRQVideo!SC.IRQAudio
                    lbsr      SC_IRQ_MASK_SET
                    lbcs      failRestoreMask
                    lbsr      SC_IRQ_MASK_GET
                    lbcs      failRestoreMask
                    cmpa      #SC.IRQVideo!SC.IRQAudio
                    lbne      failRestoreMask

                    lda       #SC.IRQVideo
                    lbsr      SC_IRQ_ACK
                    lbcs      failRestoreMask
                    lbsr      SC_IRQ_GET
                    lbcs      failRestoreMask
                    bita      #SC.IRQVideo
                    lbne      failRestoreMask

                    lda       savedMask,u
                    lbsr      SC_IRQ_MASK_SET
                    lbcs      fail
                    lbsr      SC_IRQ_MASK_GET
                    lbcs      fail
                    cmpa      savedMask,u
                    lbne      fail

                    leax      msgIRQ,pcr
                    ldy       #msgIRQLen
                    lbsr      writeLine

* Exercise MBO geometry/error handling plus wrap-safe non-zero generation.
                    ldb       #15
                    lbsr      SC_MBO_BASE
                    lbcs      fail
                    cmpx      #$2600
                    lbne      fail

                    ldb       #16
                    lbsr      SC_MBO_BASE
                    lbcc      fail
                    cmpb      #E$IllArg
                    lbne      fail

                    pshs      u
                    leau      generation,u
                    lda       #$FF
                    sta       ,u
                    sta       1,u
                    sta       2,u
                    sta       3,u
                    lbsr      SC_MBO_NEXTGEN
                    lbcs      genBad
                    lda       ,u
                    cmpa      #1
                    lbne      genBad
                    lda       1,u
                    lbne      genBad
                    lda       2,u
                    lbne      genBad
                    lda       3,u
                    lbne      genBad
                    puls      u

                    leax      msgMBO,pcr
                    ldy       #msgMBOLen
                    lbsr      writeLine

                    leax      msgFinal,pcr
                    ldy       #msgFinalLen
                    lbsr      writeLine
                    clrb
                    os9       F$Exit

rateBad             puls      u
                    lbra      fail

genBad              puls      u
                    lbra      fail

failRestoreMask     lda       savedMask,u
                    lbsr      SC_IRQ_MASK_SET

fail                leax      msgFail,pcr
                    ldy       #msgFailLen
                    lbsr      writeLine
                    ldb       #E$NotRdy
                    os9       F$Exit

writeLine           lda       #1
                    os9       I$WritLn
                    rts

* Shared S1 SuperCoCo service helpers under acceptance.
                    use       ../libs/scsys/scsys.inc

                    emod
eom                 equ       *
                    end
