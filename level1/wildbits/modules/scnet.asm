                    nam       scnet
                    ttl       SuperCoCo Native Network SCF Driver

********************************************************************
* scnet - SuperCoCo Native Network v0.1 SCF driver
*
* N3b-0 scope:
* - one /net0 device
* - SuperCoCo Native Network ABI v1 at $FF70-$FF7F
* - direct hardware FIFO Read/Write (no software payload ring)
* - Level 2 reader suspend/wake through the native RX/CLOSE/ERROR IRQ
* - SS.Ready reports the hardware RX FIFO count
* - SS.NetCn submits a versioned asynchronous hostname/port TCP request
* - SS.NetSt returns a versioned native-network state snapshot
* - caller buffers are accessed through Level 2 task-aware primitives
*
* N3b-0 does not yet make TX_READY load-bearing for a blocked writer; that
* remains part of the later N3b transmit-backpressure acceptance step.
*
* The receive IRQ is level-sensitive.  The ISR therefore MASKS the read
* wake sources before waking a blocked reader.  Read re-arms them only
* when it is about to sleep again.  This prevents an IRQ storm while
* keeping payload ownership in reader context.
********************************************************************

                    ifp1
                    use       defsfile
                    use       supercoco.d
                    endc

* Driver policy derived from the shared SuperCoCo contract.
NET_REQUIRED_CAPS   equ       NET_CAP_TCP!NET_CAP_IRQ
NET_IRQ_READ_WAKE   equ       NET_IRQ_RX_READY!NET_IRQ_CLOSED!NET_IRQ_ERROR
NET_IRQ_LATCHED     equ       NET_IRQ_CONNECT!NET_IRQ_CLOSED!NET_IRQ_ERROR!NET_IRQ_TX_READY

* Device memory begins after SCF manager-owned state.  N3a deliberately
* adds no software RX/TX buffers; V.WAKE is the only SCF field we use.
                    org       V.SCF
MemSize             equ       .

rev                 set       1
edition             set       2

                    mod       ModSize,ModName,Drivr+Objct,ReEnt+rev,ModEntry,MemSize

                    fcb       UPDAT.              read/write device

ModName             fcs       /scnet/
                    fcb       edition

* F$IRQ polls native IRQ_STATUS.  Only sources that can release a blocked
* Read are part of this first packet.  Connect/TX events remain masked.
IRQPckt             equ       *
                    fcb       $00                 flip byte
                    fcb       NET_IRQ_READ_WAKE   mask byte
                    fcb       $F1                 priority

ModEntry            lbra      Init
                    lbra      Read
                    lbra      Write
                    lbra      GStt
                    lbra      SStt
                    lbra      Term

********************************************************************
* Init
*
* Validate the register ABI/capabilities, reset the device, clear stale
* latched events, install F$IRQ, and leave all device IRQ sources masked.
********************************************************************
Init                clrb                          default carry clear
                    ldx       V.PORT,u
                    lda       NET_ABI,x
                    cmpa      #NET_ABI_VERSION
                    bne       InitNotReady
                    lda       NET_CAPS,x
                    anda      #NET_REQUIRED_CAPS
                    cmpa      #NET_REQUIRED_CAPS
                    bne       InitNotReady

                    clr       NET_IRQ_MASK,x      never unmask before F$IRQ install
                    lda       #NET_CMD_RESET
                    sta       NET_COMMAND,x
                    lda       #NET_IRQ_LATCHED
                    sta       NET_IRQ_STATUS,x    clear stale edge/latched events
                    clr       V.WAKE,u

                    ldd       V.PORT,u
                    addd      #NET_IRQ_STATUS
                    leax      IRQPckt,pcr
                    leay      IRQSvc,pcr
                    os9       F$IRQ
                    rts                           preserve F$IRQ carry/B on error

InitNotReady        ldb       #E$NotRdy
                    orcc      #Carry
                    rts

********************************************************************
* Term
*
* Silence the device before removing the F$IRQ packet.  RESET closes any
* native socket and returns the ABI to deterministic idle state.
********************************************************************
Term                clrb
                    pshs      cc
                    orcc      #IntMasks
                    ldx       V.PORT,u
                    clr       NET_IRQ_MASK,x
                    lbsr      WakeReader
                    ldx       V.PORT,u
                    lda       #NET_CMD_RESET
                    sta       NET_COMMAND,x
                    lda       #NET_IRQ_LATCHED
                    sta       NET_IRQ_STATUS,x

                    ldd       V.PORT,u
                    addd      #NET_IRQ_STATUS
                    ldx       #$0000
                    leay      IRQSvc,pcr
                    puls      cc
                    os9       F$IRQ
                    rts

********************************************************************
* Read
*
* Return one byte directly from RX_DATA.  When RX_COUNT is zero, arm the
* read-wake IRQ sources and suspend the current Level 2 process.  The ISR
* never copies payload; it masks the level source and wakes this reader.
********************************************************************
Read                clrb
                    pshs      cc                  saved CC has carry clear

ReadRetry           orcc      #IntMasks
                    ldx       V.PORT,u
                    lda       NET_RX_COUNT,x
                    bne       ReadPop

* Deliver terminal network state before sleeping.
                    lda       NET_IRQ_STATUS,x
                    bita      #NET_IRQ_CLOSED
                    bne       ReadClosed
                    bita      #NET_IRQ_ERROR
                    bne       ReadHWError
                    lda       NET_STATUS,x
                    bita      #NET_ST_ERROR
                    bne       ReadHWError
                    bita      #NET_ST_CONNECTED
                    beq       ReadNotReady

* Publish the waiter while CPU IRQs are masked, mark the process suspended,
* then arm all events capable of ending this wait.
                    ldd       >D.Proc
                    sta       V.WAKE,u            process descriptors are page aligned
                    tfr       d,x
                    ldb       P$State,x
                    orb       #Suspend
                    stb       P$State,x

                    ldx       V.PORT,u
                    lda       NET_IRQ_MASK,x
                    ora       #NET_IRQ_READ_WAKE
                    sta       NET_IRQ_MASK,x

* Close the count-check/IRQ-arm race.  If data arrived before IRQs are
* re-enabled, cancel the waiter and consume it directly.
                    lda       NET_RX_COUNT,x
                    bne       ReadArmedData

                    ldx       #1                  yield one tick; Suspend keeps us parked
                    andcc     #^IntMasks
                    os9       F$Sleep
                    orcc      #IntMasks

* Honor normal NitrOS-9 abort/interrupt signals and condemned processes.
                    ldx       >D.Proc
                    ldb       P$Signal,x
                    beq       ReadChkState
                    cmpb      #S$Intrpt
                    bls       ReadError
ReadChkState        ldb       P$State,x
                    bitb      #Condem
                    bne       ReadProcAbort

* A real native IRQ clears V.WAKE.  Anything else is a false wake; simply
* re-arm/re-suspend rather than pretending data exists.
                    tst       V.WAKE,u
                    beq       ReadRetry
                    bra       ReadRetry

ReadArmedData       bsr       CancelWait
                    ldx       V.PORT,u
                    bra       ReadPopNow

ReadPop             bsr       CancelWait
                    ldx       V.PORT,u
ReadPopNow          lda       NET_RX_DATA,x
                    puls      cc,pc

ReadClosed          lda       #NET_IRQ_CLOSED
                    sta       NET_IRQ_STATUS,x
                    ldb       #E$HangUp
                    bra       ReadError

ReadHWError         lda       #NET_IRQ_ERROR
                    sta       NET_IRQ_STATUS,x
                    ldb       #E$Read
                    bra       ReadError

ReadNotReady        ldb       #E$NotRdy
                    bra       ReadError

ReadProcAbort       ldb       #E$PrcAbt

ReadError           pshs      b
                    bsr       CancelWait
                    puls      b
                    lda       ,s
                    ora       #Carry
                    sta       ,s
                    puls      cc,pc

********************************************************************
* CancelWait
*
* Called with CPU IRQs masked.  Remove this driver's read-wake sources,
* clear V.WAKE, and ensure the current process is not left Suspended.
********************************************************************
CancelWait          ldx       V.PORT,u
                    lda       NET_IRQ_MASK,x
                    anda      #^NET_IRQ_READ_WAKE
                    sta       NET_IRQ_MASK,x
                    clr       V.WAKE,u

                    ldx       >D.Proc
                    ldb       P$State,x
                    andb      #^Suspend
                    stb       P$State,x
                    rts

********************************************************************
* Write
*
* Write the entry character directly to TX_DATA.  Hardware TX_SPACE is
* the pacing authority.  A full FIFO uses one-tick polling with normal
* signal/condemn checks; TX_READY IRQ is not load-bearing in N3a.
********************************************************************
Write               clrb
                    pshs      cc,a                stacked char is 1,s

WriteRetry          orcc      #IntMasks
                    ldx       V.PORT,u
                    ldb       NET_IRQ_STATUS,x
                    bitb      #NET_IRQ_CLOSED
                    bne       WriteHangup
                    bitb      #NET_IRQ_ERROR
                    bne       WriteHWError
                    ldb       NET_STATUS,x
                    bitb      #NET_ST_ERROR
                    bne       WriteHWError
                    bitb      #NET_ST_CONNECTED
                    beq       WriteNotReady
                    ldb       NET_TX_SPACE,x
                    bne       WriteNow

                    ldx       #1
                    andcc     #^IntMasks
                    os9       F$Sleep
                    orcc      #IntMasks

                    ldx       >D.Proc
                    ldb       P$Signal,x
                    beq       WriteChkState
                    cmpb      #S$Intrpt
                    bls       WriteError
WriteChkState       ldb       P$State,x
                    bitb      #Condem
                    bne       WriteProcAbort
                    bra       WriteRetry

WriteNow            lda       1,s
                    sta       NET_TX_DATA,x
                    puls      cc,a,pc

WriteHangup         ldb       #E$HangUp
                    bra       WriteError

WriteHWError        ldb       #E$Write
                    bra       WriteError

WriteNotReady       ldb       #E$NotRdy
                    bra       WriteError

WriteProcAbort      ldb       #E$PrcAbt

WriteError          lda       ,s
                    ora       #Carry
                    sta       ,s
                    puls      cc,a,pc

********************************************************************
* GStt
*
* N3b retains the stream status calls and adds SS.NetSt.  R$X in the saved
* register packet is a caller-task address under Level 2, so the response is
* written with F$STABX rather than dereferenced directly in system state.
********************************************************************
GStt                clrb
                    pshs      cc
                    ldx       PD.RGS,y
                    cmpa      #SS.EOF
                    beq       GSttOK
                    cmpa      #SS.NetSt
                    beq       GSttNetSt
                    cmpa      #SS.Ready
                    bne       GSttUnknown

                    ldx       V.PORT,u
                    ldb       NET_RX_COUNT,x
                    beq       GSttNotReady
                    ldx       PD.RGS,y
                    stb       R$B,x
GSttOK              puls      cc,pc

* SS.NetSt v1: R$X is the caller destination and R$Y is its capacity.
* F$STABX performs each store in the caller's DAT task without shared scratch.
GSttNetSt           ldx       PD.RGS,y
                    ldd       R$Y,x
                    cmpd      #NETST_SIZE
                    blo       GSttBufSmall
                    ldx       R$X,x
                    pshs      y,u
                    ldy       V.PORT,u
                    ldu       >D.Proc
                    ldb       P$Task,u

                    lda       #NETST_VERSION
                    os9       F$STABX
                    bcs       GSttNetStError
                    leax      1,x
                    lda       NET_ABI,y
                    os9       F$STABX
                    bcs       GSttNetStError
                    leax      1,x
                    lda       NET_CAPS,y
                    os9       F$STABX
                    bcs       GSttNetStError
                    leax      1,x
                    lda       NET_STATUS,y
                    os9       F$STABX
                    bcs       GSttNetStError
                    leax      1,x
                    lda       NET_RESULT,y
                    os9       F$STABX
                    bcs       GSttNetStError
                    leax      1,x
                    lda       NET_IRQ_STATUS,y
                    os9       F$STABX
                    bcs       GSttNetStError
                    leax      1,x
                    lda       NET_RX_COUNT,y
                    os9       F$STABX
                    bcs       GSttNetStError
                    leax      1,x
                    lda       NET_TX_SPACE,y
                    os9       F$STABX
                    bcs       GSttNetStError

                    clrb
                    puls      y,u
                    bra       GSttOK

GSttNetStError     puls      y,u
                    bra       GSttError
GSttBufSmall        ldb       #E$BufSiz
                    bra       GSttError
GSttNotReady        ldb       #E$NotRdy
                    bra       GSttError
GSttUnknown         ldb       #E$UnkSvc
GSttError           lda       ,s
                    ora       #Carry
                    sta       ,s
                    puls      cc,pc

********************************************************************
* SStt
*
* N3b adds SS.NetCn as a versioned asynchronous connection request.  The
* caller buffer remains in the caller's DAT task; F$LDABX is used for all
* buffer reads so no Level 2 user pointer is dereferenced in system state.
********************************************************************
SStt                clrb
                    pshs      cc
                    cmpa      #SS.ComSt
                    lbeq      SSttOK
                    cmpa      #SS.Open
                    lbeq      SSttOK
                    cmpa      #SS.Close
                    lbeq      SSttOK
                    cmpa      #SS.NetCn
                    beq       SSttNetCn
                    cmpa      #SS.HngUp
                    lbeq      SSttClose
                    cmpa      #SS.Reset
                    lbeq      SSttReset

SSttUnknown         ldb       #E$UnkSvc
                    lbra      SSttError

* SS.NetCn v1: validate the fixed header before touching hardware.  A valid
* request stages port/hostname and issues TCP_CONNECT, then returns immediately;
* completion is observed later through SS.NetSt/CMD_BUSY/result/event state.
SSttNetCn           ldx       PD.RGS,y
                    ldd       R$Y,x
                    cmpd      #NETCN_FIXED_SIZE
                    lblo      SSttNetCnBufSmall
                    ldx       R$X,x

* Preserve the driver's entry context, retain caller capacity, and allocate a
* four-byte system-stack copy of the fixed request header.
                    pshs      y,u
                    pshs      d
                    leas      -NETCN_FIXED_SIZE,s

                    ldy       V.PORT,u
                    ldu       >D.Proc
                    ldb       P$Task,u

                    os9       F$LDABX
                    bcs       SSttNetCnReadError
                    sta       NETCN_O_VERSION,s
                    leax      1,x
                    os9       F$LDABX
                    bcs       SSttNetCnReadError
                    sta       NETCN_O_HOSTLEN,s
                    leax      1,x
                    os9       F$LDABX
                    bcs       SSttNetCnReadError
                    sta       NETCN_O_PORT,s
                    leax      1,x
                    os9       F$LDABX
                    bcs       SSttNetCnReadError
                    sta       NETCN_O_PORT+1,s
                    leax      1,x              X now points to hostname bytes

                    lda       NETCN_O_VERSION,s
                    cmpa      #NETCN_VERSION
                    bne       SSttNetCnBadArg
                    lda       NETCN_O_HOSTLEN,s
                    beq       SSttNetCnBadArg
                    ldd       NETCN_O_PORT,s
                    beq       SSttNetCnBadArg

* Required size is fixed header plus hostname length.  Capacity is immediately
* above the four-byte local header on the system stack.
                    clra
                    ldb       NETCN_O_HOSTLEN,s
                    addd      #NETCN_FIXED_SIZE
                    cmpd      NETCN_FIXED_SIZE,s
                    bhi       SSttNetCnBufSmallStack

* Hostname connect is the only N3b connection request form.  Preserve N3a Init
* compatibility, but refuse SS.NetCn if this backend does not advertise it.
                    lda       NET_CAPS,y
                    bita      #NET_CAP_HOSTNAME
                    beq       SSttNetCnNotReady

* Reject a second/incompatible connection command synchronously.  Link/backend
* failures remain asynchronous hardware results, matching the native ABI.
                    lda       NET_STATUS,y
                    bita      #NET_ST_CONNECTING!NET_ST_CONNECTED!NET_ST_CMD_BUSY
                    bne       SSttNetCnBusy

* Retire stale edge events from the previous command before starting this one.
                    lda       #NET_IRQ_LATCHED
                    sta       NET_IRQ_STATUS,y
                    lda       NETCN_O_PORT,s
                    sta       NET_PORT_HI,y
                    lda       NETCN_O_PORT+1,s
                    sta       NET_PORT_LO,y
                    lda       NETCN_O_HOSTLEN,s
                    sta       NET_HOST_LEN,y

* Reacquire the caller task number after the size calculation used D.  The
* process cannot resume while this SetStat is executing, so its request buffer
* remains stable for the duration of this loop.
                    ldb       P$Task,u
SSttNetCnHost       os9       F$LDABX
                    bcs       SSttNetCnHostFault
                    sta       NET_HOST_DATA,y
                    leax      1,x
                    dec       NETCN_O_HOSTLEN,s
                    bne       SSttNetCnHost

                    lda       #NET_CMD_CONNECT
                    sta       NET_COMMAND,y
                    clrb
                    bra       SSttNetCnDone

* A task-read fault after staging has begun is returned to OS-9 and the native
* device is reset so a partially loaded hostname cannot leak into a later call.
SSttNetCnHostFault  lda       #NET_CMD_RESET
                    sta       NET_COMMAND,y
                    lda       #NET_IRQ_LATCHED
                    sta       NET_IRQ_STATUS,y
                    bra       SSttNetCnCleanupError

SSttNetCnReadError  bra       SSttNetCnCleanupError
SSttNetCnBadArg     ldb       #E$IllArg
                    bra       SSttNetCnCleanupError
SSttNetCnBufSmallStack
                    ldb       #E$BufSiz
                    bra       SSttNetCnCleanupError
SSttNetCnNotReady   ldb       #E$NotRdy
                    bra       SSttNetCnCleanupError
SSttNetCnBusy       ldb       #E$DevBsy
                    bra       SSttNetCnCleanupError

SSttNetCnDone       leas      NETCN_FIXED_SIZE+2,s
                    puls      y,u
                    bra       SSttOK
SSttNetCnCleanupError
                    leas      NETCN_FIXED_SIZE+2,s
                    puls      y,u
                    bra       SSttError

SSttNetCnBufSmall   ldb       #E$BufSiz
                    bra       SSttError

SSttClose           ldx       V.PORT,u
                    lda       #NET_CMD_CLOSE
                    sta       NET_COMMAND,x
                    bra       SSttOK

SSttReset           orcc      #IntMasks
                    ldx       V.PORT,u
                    clr       NET_IRQ_MASK,x
                    bsr       WakeReader
                    ldx       V.PORT,u
                    lda       #NET_CMD_RESET
                    sta       NET_COMMAND,x
                    lda       #NET_IRQ_LATCHED
                    sta       NET_IRQ_STATUS,x
SSttOK              puls      cc,pc

SSttError           lda       ,s
                    ora       #Carry
                    sta       ,s
                    puls      cc,pc

********************************************************************
* WakeReader
*
* Release the Level 2 reader currently recorded in V.WAKE, if any.
* Caller must already have CPU IRQs masked when racing device IRQ state.
********************************************************************
WakeReader          clrb
                    lda       V.WAKE,u
                    beq       WakeDone
                    stb       V.WAKE,u
                    tfr       d,x
                    lda       P$State,x
                    anda      #^Suspend
                    sta       P$State,x
WakeDone            rts

********************************************************************
* IRQSvc
*
* F$IRQ called us because one of NET_IRQ_READ_WAKE matched.  Mask those
* sources FIRST so a level RX_READY cannot retrigger forever.  Then wake
* the blocked Level 2 reader, if any.  Payload remains in hardware.
********************************************************************
IRQSvc              pshs      cc,x
                    ldx       V.PORT,u

* F$IRQ polls raw IRQ_STATUS, while the native device asserts CPU IRQ only
* for IRQ_STATUS & IRQ_MASK.  Reject stale level status observed while the
* native source is masked; an unrelated system IRQ must continue polling.
                    lda       NET_IRQ_STATUS,x
                    anda      NET_IRQ_MASK,x
                    anda      #NET_IRQ_READ_WAKE
                    beq       IRQNotOurs

* This device really is requesting service.  Mask all read-wake sources
* before releasing the waiter so level RX_READY cannot immediately retrigger.
                    lda       NET_IRQ_MASK,x
                    anda      #^NET_IRQ_READ_WAKE
                    sta       NET_IRQ_MASK,x

                    bsr       WakeReader

IRQExit             lda       ,s
                    anda      #^Carry
                    sta       ,s
                    puls      cc,x,pc

* Raw IRQ_STATUS may remain asserted after this driver's runtime mask is
* removed.  Carry set tells IOMan this poll-table hit was not the source
* of the current CPU IRQ and allows polling to continue.
IRQNotOurs          lda       ,s
                    ora       #Carry
                    sta       ,s
                    puls      cc,x,pc

                    emod
ModSize             equ       *
                    end
