********************************************************************
* scnetbp - SuperCoCo S2A6 NativeNet TX backpressure probe
********************************************************************

                    nam       scnetbp
                    ttl       SuperCoCo S2A6 NativeNet TX backpressure

                    ifp1
                    use       defsfile
                    use       supercoco.d
                    endc

rev                 set       1
edition             set       1
tylg                set       Prgrm+Objct
atrv                set       ReEnt+rev

ConnectPolls        equ       600
TxBlocks            equ       8                  8 * 256 = 2 KiB
TxBlockSize         equ       256
RequiredCaps        equ       NET_CAP_TCP!NET_CAP_HOSTNAME!NET_CAP_IRQ
WitnessAddr         equ       $FF7F              reserved NG register
WitnessValue        equ       $A6

                    org       0
PathNum             rmb       1
PollRemain          rmb       2
BlocksLeft          rmb       2
NetState            rmb       NETST_SIZE
TxBuffer            rmb       TxBlockSize
MemSize             equ       .

                    mod       ModSize,ModName,tylg,atrv,Start,MemSize

ModName             fcs       /scnetbp/
                    fcb       edition

Start               lbsr      FillPattern

                    leax      NetPath,pcr
                    lda       #UPDAT.
                    os9       I$Open
                    lbcs      ExitError
                    sta       PathNum,u

                    lda       PathNum,u
                    ldb       #SS.NetCn
                    leax      ConnectReq,pcr
                    ldy       #ConnectReqLen
                    os9       I$SetStt
                    lbcs      ExitPathError

                    ldd       #ConnectPolls
                    std       PollRemain,u

WaitConnect         lbsr      GetNetState
                    lbcs      ExitPathError
                    leax      NetState,u
                    lda       NETST_O_VERSION,x
                    cmpa      #NETST_VERSION
                    lbne      ProtocolError
                    lda       NETST_O_ABI,x
                    cmpa      #NET_ABI_VERSION
                    lbne      ProtocolError
                    lda       NETST_O_CAPS,x
                    anda      #RequiredCaps
                    cmpa      #RequiredCaps
                    lbne      ProtocolError
                    lda       NETST_O_STATUS,x
                    bita      #NET_ST_ERROR
                    lbne      ProtocolError
                    bita      #NET_ST_CONNECTED
                    beq       ConnectPending
                    bita      #NET_ST_CMD_BUSY
                    bne       ConnectPending
                    lda       NETST_O_RESULT,x
                    lbne      ProtocolError
                    bra       Connected

ConnectPending      lda       NETST_O_RESULT,x
                    lbne      ProtocolError
                    lda       NETST_O_STATUS,x
                    bita      #NET_ST_CONNECTING!NET_ST_CMD_BUSY
                    lbeq      ProtocolError
                    ldd       PollRemain,u
                    subd      #1
                    std       PollRemain,u
                    lbeq      ProtocolError
                    ldx       #1
                    os9       F$Sleep
                    lbcs      ExitPathError
                    bra       WaitConnect

Connected           lda       PathNum,u
                    leax      BeginMarker,pcr
                    ldy       #BeginMarkerLen
                    os9       I$Write
                    lbcs      ExitPathError

                    ldd       #TxBlocks
                    std       BlocksLeft,u

TxLoop              lda       PathNum,u
                    leax      TxBuffer,u
                    ldy       #TxBlockSize
                    os9       I$Write
                    lbcs      ExitPathError
                    ldd       BlocksLeft,u
                    subd      #1
                    std       BlocksLeft,u
                    bne       TxLoop

                    lda       PathNum,u
                    leax      EndMarker,pcr
                    ldy       #EndMarkerLen
                    os9       I$Write
                    lbcs      ExitPathError

                    lbsr      GetNetState
                    lbcs      ExitPathError
                    leax      NetState,u
                    lda       NETST_O_STATUS,x
                    bita      #NET_ST_ERROR!NET_ST_CONNECTING!NET_ST_CMD_BUSY
                    lbne      ProtocolError
                    bita      #NET_ST_CONNECTED
                    lbeq      ProtocolError
                    lda       NETST_O_RESULT,x
                    lbne      ProtocolError

* Test-only success sentinel.  The register is reserved and ignores writes.
                    lda       #WitnessValue
                    sta       >WitnessAddr

                    leax      MsgPass,pcr
                    ldy       #MsgPassEnd-MsgPass
                    lbsr      PrintLine

                    lda       PathNum,u
                    ldb       #SS.HngUp
                    os9       I$SetStt
                    lbcs      ExitPathError
                    lda       PathNum,u
                    os9       I$Close
                    lbcs      ExitError

                    clrb
                    os9       F$Exit

FillPattern         leax      TxBuffer,u
                    clra
                    ldy       #TxBlockSize
FillLoop            sta       ,x+
                    inca
                    leay      -1,y
                    bne       FillLoop
                    rts

GetNetState         lda       PathNum,u
                    ldb       #SS.NetSt
                    leax      NetState,u
                    ldy       #NETST_SIZE
                    os9       I$GetStt
                    rts

ProtocolError       ldb       #E$NotRdy

ExitPathError       pshs      b
                    lda       PathNum,u
                    ldb       #SS.HngUp
                    os9       I$SetStt
                    lda       PathNum,u
                    os9       I$Close
                    leax      MsgFail,pcr
                    ldy       #MsgFailEnd-MsgFail
                    lbsr      PrintLine
                    puls      b
ExitError           os9       F$Exit

PrintLine           lda       #1
                    os9       I$WritLn
                    rts

NetPath             fcs       |/net0|

ConnectReq          fcb       NETCN_VERSION
                    fcb       9
                    fdb       S2A6_PORT
                    fcc       /127.0.0.1/
ConnectReqEnd       equ       *
ConnectReqLen       equ       ConnectReqEnd-ConnectReq

BeginMarker         fcc       /S2A6-BEGIN/
BeginMarkerEnd      equ       *
BeginMarkerLen      equ       BeginMarkerEnd-BeginMarker
EndMarker           fcc       /S2A6-END/
EndMarkerEnd        equ       *
EndMarkerLen        equ       EndMarkerEnd-EndMarker

MsgPass             fcc       /S2A6-BACKPRESSURE PASS/
                    fcb       C$CR
MsgPassEnd          equ       *
MsgFail             fcc       /S2A6-BACKPRESSURE FAIL/
                    fcb       C$CR
MsgFailEnd          equ       *

                    emod
ModSize             equ       *
                    end
