********************************************************************
* scnettxm - SuperCoCo S2A7 64 KiB TX measurement probe
********************************************************************

                    nam       scnettxm
                    ttl       SuperCoCo S2A7 TX measurement

                    ifp1
                    use       defsfile
                    use       supercoco.d
                    endc

rev                 set       1
edition             set       1
tylg                set       Prgrm+Objct
atrv                set       ReEnt+rev

ConnectPolls        equ       600
Blocks              equ       256
BlockSize           equ       256
RequiredCaps        equ       NET_CAP_TCP!NET_CAP_HOSTNAME!NET_CAP_IRQ

                    org       0
PathNum             rmb       1
PollRemain          rmb       2
BlocksLeft          rmb       2
NetState            rmb       NETST_SIZE
Buffer              rmb       BlockSize
ReadByte            rmb       1
MemSize             equ       .

                    mod       ModSize,ModName,tylg,atrv,Start,MemSize
ModName             fcs       /scnettxm/
                    fcb       edition

Start               lbsr      FillPattern
                    leax      NetPath,pcr
                    lda       #UPDAT.
                    os9       I$Open
                    lbcs      ExitError
                    sta       PathNum,u
                    lbsr      Connect
                    lbcs      ExitPathError
                    ldd       #Blocks
                    std       BlocksLeft,u
TxLoop              lda       PathNum,u
                    leax      Buffer,u
                    ldy       #BlockSize
                    os9       I$Write
                    lbcs      ExitPathError
                    ldd       BlocksLeft,u
                    subd      #1
                    std       BlocksLeft,u
                    bne       TxLoop

* Host closes only after exact 64 KiB receipt.  Block until orderly close.
                    lda       PathNum,u
                    leax      ReadByte,u
                    ldy       #1
                    os9       I$Read
                    lbcc      ProtocolError
                    cmpb      #E$HangUp
                    lbne      ExitPathError
                    lbsr      ClosePath
                    lbcs      ExitError
                    leax      MsgPass,pcr
                    ldy       #MsgPassEnd-MsgPass
                    lda       #1
                    os9       I$WritLn
                    clrb
                    os9       F$Exit

ProtocolError       ldb       #E$NotRdy
                    lbra      ExitPathError

FillPattern         leax      Buffer,u
                    lda       #33                 printable '!'
                    ldy       #BlockSize
FillLoop            sta       ,x+
                    inca
                    cmpa      #127                wrap after '~'
                    bne       FillNext
                    lda       #33
FillNext            leay      -1,y
                    bne       FillLoop
                    rts

Connect             lda       PathNum,u
                    ldb       #SS.NetCn
                    leax      ConnectReq,pcr
                    ldy       #ConnectReqLen
                    os9       I$SetStt
                    bcs       ConnectDone
                    ldd       #ConnectPolls
                    std       PollRemain,u
ConnectWait         bsr       GetNetState
                    bcs       ConnectDone
                    leax      NetState,u
                    lda       NETST_O_VERSION,x
                    cmpa      #NETST_VERSION
                    bne       ConnectProtocol
                    lda       NETST_O_ABI,x
                    cmpa      #NET_ABI_VERSION
                    bne       ConnectProtocol
                    lda       NETST_O_CAPS,x
                    anda      #RequiredCaps
                    cmpa      #RequiredCaps
                    bne       ConnectProtocol
                    lda       NETST_O_STATUS,x
                    bita      #NET_ST_ERROR
                    bne       ConnectProtocol
                    bita      #NET_ST_CONNECTED
                    beq       ConnectPending
                    bita      #NET_ST_CMD_BUSY
                    bne       ConnectPending
                    lda       NETST_O_RESULT,x
                    bne       ConnectProtocol
                    clrb
                    andcc     #^Carry
                    rts
ConnectPending      lda       NETST_O_RESULT,x
                    bne       ConnectProtocol
                    lda       NETST_O_STATUS,x
                    bita      #NET_ST_CONNECTING!NET_ST_CMD_BUSY
                    beq       ConnectProtocol
                    ldd       PollRemain,u
                    subd      #1
                    std       PollRemain,u
                    beq       ConnectProtocol
                    ldx       #1
                    os9       F$Sleep
                    bcs       ConnectDone
                    bra       ConnectWait
ConnectProtocol     ldb       #E$NotRdy
                    orcc      #Carry
ConnectDone         rts

GetNetState         lda       PathNum,u
                    ldb       #SS.NetSt
                    leax      NetState,u
                    ldy       #NETST_SIZE
                    os9       I$GetStt
                    rts

ClosePath           lda       PathNum,u
                    os9       I$Close
                    rts

ExitPathError       pshs      b
                    lda       PathNum,u
                    ldb       #SS.HngUp
                    os9       I$SetStt
                    bsr       ClosePath
                    puls      b
ExitError           os9       F$Exit

NetPath             fcs       |/net0|
ConnectReq          fcb       NETCN_VERSION
                    fcb       9
                    fdb       S2A7_PORT
                    fcc       /127.0.0.1/
ConnectReqEnd       equ       *
ConnectReqLen       equ       ConnectReqEnd-ConnectReq

MsgPass             fcc       /S2A7-TX PASS/
                    fcb       C$CR
MsgPassEnd          equ       *

                    emod
ModSize             equ       *
                    end
