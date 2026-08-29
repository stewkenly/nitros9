                    nam       scnet
                    ttl       SuperCoCo Native Network SCF Driver

********************************************************************
* scnet - SuperCoCo Native Network v0.1 SCF driver
*
* N3a scope:
* - one /net0 device
* - SuperCoCo Native Network ABI v1 at $FF70-$FF7F
* - direct hardware FIFO Read/Write (no software payload ring)
* - Level 2 reader suspend/wake through the native RX/CLOSE/ERROR IRQ
* - SS.Ready reports the hardware RX FIFO count
* - connection setup is intentionally NOT defined here yet; N3a keeps
*   the guest control ABI separate until the SetStat interface is frozen
*
* The receive IRQ is level-sensitive.  The ISR therefore MASKS the read
* wake sources before waking a blocked reader.  Read re-arms them only
* when it is about to sleep again.  This prevents an IRQ storm while
* keeping payload ownership in reader context.
********************************************************************

                    ifp1
                    use       defsfile
                    endc

* SuperCoCo Native Network v0.1 register offsets from V.PORT ($FF70).
NET_ABI             equ       $00
NET_CAPS            equ       $01
NET_STATUS          equ       $02
NET_COMMAND         equ       $03
NET_RESULT          equ       $04
NET_IRQ_STATUS      equ       $05
NET_IRQ_MASK        equ       $06
NET_PORT_HI         equ       $07
NET_PORT_LO         equ       $08
NET_HOST_LEN        equ       $09
NET_HOST_DATA       equ       $0A
NET_RX_COUNT        equ       $0B
NET_TX_SPACE        equ       $0C
NET_RX_DATA         equ       $0D
NET_TX_DATA         equ       $0E

NET_ABI_VERSION     equ       $01

NET_CAP_TCP         equ       %00000001
NET_CAP_HOSTNAME    equ       %00000010
NET_CAP_IRQ         equ       %00000100
NET_REQUIRED_CAPS   equ       NET_CAP_TCP!NET_CAP_IRQ

NET_ST_LINK_UP      equ       %00000001
NET_ST_CONNECTING   equ       %00000010
NET_ST_CONNECTED    equ       %00000100
NET_ST_RX_READY     equ       %00001000
NET_ST_TX_READY     equ       %00010000
NET_ST_CMD_BUSY     equ       %00100000
NET_ST_ERROR        equ       %01000000

NET_CMD_RESET       equ       $01
NET_CMD_CONNECT     equ       $10
NET_CMD_CLOSE       equ       $11

NET_IRQ_RX_READY    equ       %00000001
NET_IRQ_CONNECT     equ       %00000010
NET_IRQ_CLOSED      equ       %00000100
NET_IRQ_ERROR       equ       %00001000
NET_IRQ_TX_READY    equ       %00010000
NET_IRQ_READ_WAKE   equ       NET_IRQ_RX_READY!NET_IRQ_CLOSED!NET_IRQ_ERROR
NET_IRQ_LATCHED     equ       NET_IRQ_CONNECT!NET_IRQ_CLOSED!NET_IRQ_ERROR!NET_IRQ_TX_READY

* Device memory begins after SCF manager-owned state.  N3a deliberately
* adds no software RX/TX buffers; V.WAKE is the only SCF field we use.
                    org       V.SCF
MemSize             equ       .

rev                 set       1
edition             set       1

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
* N3a implements the two status operations needed by normal stream users:
* SS.EOF is never asserted by SCF; SS.Ready reports the native RX count.
********************************************************************
GStt                clrb
                    pshs      cc
                    ldx       PD.RGS,y
                    cmpa      #SS.EOF
                    beq       GSttOK
                    cmpa      #SS.Ready
                    bne       GSttUnknown

                    ldx       V.PORT,u
                    ldb       NET_RX_COUNT,x
                    beq       GSttNotReady
                    ldx       PD.RGS,y
                    stb       R$B,x
GSttOK              puls      cc,pc

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
* Accept the standard SCF lifecycle/configuration notifications without
* inventing the native connect-control ABI yet.  SS.HngUp maps naturally
* to TCP_CLOSE; SS.Reset maps to the native deterministic RESET command.
********************************************************************
SStt                clrb
                    pshs      cc
                    cmpa      #SS.ComSt
                    beq       SSttOK
                    cmpa      #SS.Open
                    beq       SSttOK
                    cmpa      #SS.Close
                    beq       SSttOK
                    cmpa      #SS.HngUp
                    beq       SSttClose
                    cmpa      #SS.Reset
                    beq       SSttReset

                    ldb       #E$UnkSvc
                    lda       ,s
                    ora       #Carry
                    sta       ,s
                    puls      cc,pc

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
                    lda       NET_IRQ_MASK,x
                    anda      #^NET_IRQ_READ_WAKE
                    sta       NET_IRQ_MASK,x

                    bsr       WakeReader

IRQExit             lda       ,s
                    anda      #^Carry
                    sta       ,s
                    puls      cc,x,pc

                    emod
ModSize             equ       *
                    end
