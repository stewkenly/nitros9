                    nam       scnetlink
                    ttl       SuperCoCo S2A5 Typed Module Link Diagnostic

********************************************************************
* scnetlink
*
* Test-only S2A5 diagnostic.
*
* I$Attach links, in order:
*   device descriptor (Devic)
*   device driver     (Drivr)
*   file manager      (FlMgr)
*
* Fixes 11/12 returned E$MNF ($DD).  Probe each typed link independently,
* then attempt I$Attach after selecting REGMAP_NG.  No production network
* source is changed by this witness.
********************************************************************

                    ifp1
                    use       defsfile
                    endc

tylg                set       Prgrm+Objct
atrv                set       ReEnt+rev
rev                 set       $01
edition             set       1

SC_SERVICE_ADDR_LO   equ       $FF88
SC_SERVICE_ADDR_HI   equ       $FF89
SC_SERVICE_WDATA     equ       $FF8A
SC_SERVICE_COMMAND   equ       $FF8B
SC_SERVICE_STATUS    equ       $FF8C
SC_SERVICE_CMD_WRITE equ       $02
SC_SERVICE_ST_DONE   equ       $02
SC_SERVICE_ST_ERROR  equ       $04
SC_SERVICE_CLEAR     equ       SC_SERVICE_ST_DONE!SC_SERVICE_ST_ERROR
SC_REGMAP_SELECT     equ       $000A
SC_REGMAP_NG         equ       $01
SCNG_MAGIC0          equ       $FF60
SCNG_MAGIC1          equ       $FF61
SCNG_MAGIC2          equ       $FF62
SCNG_MAGIC3          equ       $FF63
SCNG_ABI_MAJOR       equ       $FF64

                    mod       eom,name,tylg,atrv,start,size

                    org       0
size                equ       .

name                fcs       /scnetlink/
                    fcb       edition

start               leax      MsgBanner,pcr
                    ldy       #MsgBannerEnd-MsgBanner
                    lbsr      PrintLine

                    lbsr      SelectNG
                    lbcs      NGFail
                    leax      MsgNG,pcr
                    ldy       #MsgNGEnd-MsgNG
                    lbsr      PrintLine

* Typed device-descriptor lookup.
                    leax      DevName,pcr
                    lda       #Devic
                    os9       F$Link
                    lbcs      DescFail
                    os9       F$UnLink
                    leax      MsgDescPass,pcr
                    ldy       #MsgDescPassEnd-MsgDescPass
                    lbsr      PrintLine

* Typed driver lookup.
                    leax      DriverName,pcr
                    lda       #Drivr
                    os9       F$Link
                    lbcs      DriverFail
                    os9       F$UnLink
                    leax      MsgDriverPass,pcr
                    ldy       #MsgDriverPassEnd-MsgDriverPass
                    lbsr      PrintLine

* Typed file-manager lookup.
                    leax      FMgrName,pcr
                    lda       #FlMgr
                    os9       F$Link
                    lbcs      FMgrFail
                    os9       F$UnLink
                    leax      MsgFMgrPass,pcr
                    ldy       #MsgFMgrPassEnd-MsgFMgrPass
                    lbsr      PrintLine

* Re-run the actual attachment boundary after all three links are proven.
                    leax      DevName,pcr
                    clra
                    os9       I$Attach
                    lbcs      AttachFail
                    os9       I$Detach
                    lbcs      DetachFail
                    leax      MsgAttachPass,pcr
                    ldy       #MsgAttachPassEnd-MsgAttachPass
                    lbsr      PrintLine
                    clrb
                    os9       F$Exit

NGFail              leax      MsgNGFail,pcr
                    ldy       #MsgNGFailEnd-MsgNGFail
                    lbsr      PrintLine
                    clrb
                    os9       F$Exit

DescFail            pshs      b
                    leax      MsgDescFail,pcr
                    ldy       #MsgDescFailEnd-MsgDescFail
                    lbsr      PrintLine
                    puls      b
                    os9       F$PErr
                    clrb
                    os9       F$Exit

DriverFail          pshs      b
                    leax      MsgDriverFail,pcr
                    ldy       #MsgDriverFailEnd-MsgDriverFail
                    lbsr      PrintLine
                    puls      b
                    os9       F$PErr
                    clrb
                    os9       F$Exit

FMgrFail            pshs      b
                    leax      MsgFMgrFail,pcr
                    ldy       #MsgFMgrFailEnd-MsgFMgrFail
                    lbsr      PrintLine
                    puls      b
                    os9       F$PErr
                    clrb
                    os9       F$Exit

AttachFail          pshs      b
                    leax      MsgAttachFail,pcr
                    ldy       #MsgAttachFailEnd-MsgAttachFail
                    lbsr      PrintLine
                    puls      b
                    os9       F$PErr
                    clrb
                    os9       F$Exit

DetachFail          pshs      b
                    leax      MsgDetachFail,pcr
                    ldy       #MsgDetachFailEnd-MsgDetachFail
                    lbsr      PrintLine
                    puls      b
                    os9       F$PErr
                    clrb
                    os9       F$Exit

********************************************************************
* SelectNG - select the production NG register-map personality and verify
* the fast-aperture signature before testing module attachment.
********************************************************************
SelectNG            lda       #SC_REGMAP_SELECT
                    sta       >SC_SERVICE_ADDR_LO
                    clr       >SC_SERVICE_ADDR_HI
                    lda       #SC_REGMAP_NG
                    sta       >SC_SERVICE_WDATA
                    lda       #SC_SERVICE_CLEAR
                    sta       >SC_SERVICE_STATUS
                    lda       #SC_SERVICE_CMD_WRITE
                    sta       >SC_SERVICE_COMMAND
                    ldx       #$4000
SNGWait             lda       >SC_SERVICE_STATUS
                    bita      #SC_SERVICE_ST_ERROR
                    bne       SNGBad
                    bita      #SC_SERVICE_ST_DONE
                    bne       SNGVerify
                    leax      -1,x
                    bne       SNGWait
                    bra       SNGBad
SNGVerify           lda       >SCNG_MAGIC0
                    cmpa      #'S
                    bne       SNGBad
                    lda       >SCNG_MAGIC1
                    cmpa      #'C
                    bne       SNGBad
                    lda       >SCNG_MAGIC2
                    cmpa      #'N
                    bne       SNGBad
                    lda       >SCNG_MAGIC3
                    cmpa      #'G
                    bne       SNGBad
                    lda       >SCNG_ABI_MAJOR
                    cmpa      #$01
                    bne       SNGBad
                    clrb
                    andcc     #^Carry
                    rts
SNGBad              ldb       #E$NotRdy
                    orcc      #Carry
                    rts

PrintLine           lda       #1
                    os9       I$WritLn
                    rts

DevName             fcs       /net0/
DriverName          fcs       /scnet/
FMgrName            fcs       /SCF/

MsgBanner           fcc       /SuperCoCo S2A5 typed module-link diagnostic/
                    fcb       C$CR
MsgBannerEnd        equ       *
MsgNG               fcc       /S2A5-NG PASS/
                    fcb       C$CR
MsgNGEnd            equ       *
MsgNGFail           fcc       /S2A5-NG FAIL/
                    fcb       C$CR
MsgNGFailEnd        equ       *
MsgDescPass         fcc       /S2A5-LINK-DESC PASS net0 Devic/
                    fcb       C$CR
MsgDescPassEnd      equ       *
MsgDescFail         fcc       /S2A5-LINK-DESC FAIL net0 Devic/
                    fcb       C$CR
MsgDescFailEnd      equ       *
MsgDriverPass       fcc       /S2A5-LINK-DRIVER PASS scnet Drivr/
                    fcb       C$CR
MsgDriverPassEnd    equ       *
MsgDriverFail       fcc       /S2A5-LINK-DRIVER FAIL scnet Drivr/
                    fcb       C$CR
MsgDriverFailEnd    equ       *
MsgFMgrPass         fcc       /S2A5-LINK-FMGR PASS SCF FlMgr/
                    fcb       C$CR
MsgFMgrPassEnd      equ       *
MsgFMgrFail         fcc       /S2A5-LINK-FMGR FAIL SCF FlMgr/
                    fcb       C$CR
MsgFMgrFailEnd      equ       *
MsgAttachPass       fcc       /S2A5-IATTACH PASS net0/
                    fcb       C$CR
MsgAttachPassEnd    equ       *
MsgAttachFail       fcc       /S2A5-IATTACH FAIL net0/
                    fcb       C$CR
MsgAttachFailEnd    equ       *
MsgDetachFail       fcc       /S2A5-IDETACH FAIL net0/
                    fcb       C$CR
MsgDetachFailEnd    equ       *

                    emod
eom                 equ       *
                    end
