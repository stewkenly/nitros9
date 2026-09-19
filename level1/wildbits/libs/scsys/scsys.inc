********************************************************************
* scsys - SuperCoCo Community Alpha common service helpers
*
* Source-level callable ABI shared by NitrOS-9 clients.  This file is
* intentionally usable both inside directly assembled modules and from the
* Wildbits Level-2 relocatable library.
*
* General result convention:
*   carry clear = success
*   carry set   = failure, B = OS-9 error code
*
* Unless an entry explicitly returns a register, X/Y/U are preserved.
********************************************************************

********************************************************************
* SC_READ8
* Entry: X = 16-bit SuperCoCo service address
* Exit:  A = byte, B = 0, carry clear
*        B = E$NotRdy, carry set on timeout/service error
********************************************************************
SC_READ8            pshs      x,y
                    tfr       x,d
                    stb       >SC.SvcAddrLo
                    sta       >SC.SvcAddrHi
                    lda       #SC.SvcRead
                    sta       >SC.SvcCommand
                    ldy       #$FFFF
scr8Wait            lda       >SC.SvcStatus
                    bita      #SC.SvcDone
                    bne       scr8Done
                    leay      -1,y
                    bne       scr8Wait
                    ldb       #E$NotRdy
                    puls      x,y
                    orcc      #Carry
                    rts
scr8Done            bita      #SC.SvcError
                    bne       scr8Bad
                    lda       >SC.SvcRData
                    clrb
                    puls      x,y
                    andcc     #^Carry
                    rts
scr8Bad             ldb       #E$NotRdy
                    puls      x,y
                    orcc      #Carry
                    rts

********************************************************************
* SC_WRITE8
* Entry: X = 16-bit SuperCoCo service address
*        A = byte
* Exit:  B = 0, carry clear
*        B = E$NotRdy, carry set on timeout/service error
********************************************************************
SC_WRITE8           pshs      x,y
                    pshs      a
                    tfr       x,d
                    stb       >SC.SvcAddrLo
                    sta       >SC.SvcAddrHi
                    lda       ,s
                    sta       >SC.SvcWData
                    lda       #SC.SvcWrite
                    sta       >SC.SvcCommand
                    ldy       #$FFFF
scw8Wait            lda       >SC.SvcStatus
                    bita      #SC.SvcDone
                    bne       scw8Done
                    leay      -1,y
                    bne       scw8Wait
                    ldb       #E$NotRdy
                    leas      1,s
                    puls      x,y
                    orcc      #Carry
                    rts
scw8Done            bita      #SC.SvcError
                    bne       scw8Bad
                    leas      1,s
                    clrb
                    puls      x,y
                    andcc     #^Carry
                    rts
scw8Bad             ldb       #E$NotRdy
                    leas      1,s
                    puls      x,y
                    orcc      #Carry
                    rts

********************************************************************
* SC_READ16LE
* Entry: X = first service address
* Exit:  D = logical 16-bit value read low byte then high byte
********************************************************************
SC_READ16LE         pshs      x
                    lbsr      SC_READ8
                    bcs       scr16Exit
                    pshs      a
                    leax      1,x
                    lbsr      SC_READ8
                    bcs       scr16Drop
                    ldb       ,s
                    leas      1,s
                    puls      x
                    andcc     #^Carry
                    rts
scr16Drop           leas      1,s
scr16Exit           puls      x,pc

********************************************************************
* SC_WRITE16LE
* Entry: X = first service address
*        D = logical 16-bit value; low byte is written first
********************************************************************
SC_WRITE16LE        pshs      x
                    pshs      a
                    tfr       b,a
                    lbsr      SC_WRITE8
                    bcs       scw16Drop
                    leax      1,x
                    lda       ,s
                    lbsr      SC_WRITE8
                    leas      1,s
                    puls      x,pc
scw16Drop           leas      1,s
                    puls      x,pc

********************************************************************
* SC_READ32LE / SC_WRITE32LE
* Entry: X = first service address
*        U = pointer to four little-endian bytes
* Exit:  X/Y/U preserved; a read may have updated a prefix before failure.
********************************************************************
SC_READ32LE         pshs      x,y,u
                    ldy       #4
scr32Loop           lbsr      SC_READ8
                    bcs       scr32Exit
                    sta       ,u+
                    leax      1,x
                    leay      -1,y
                    bne       scr32Loop
scr32Exit           puls      x,y,u,pc

SC_WRITE32LE        pshs      x,y,u
                    ldy       #4
scw32Loop           lda       ,u+
                    lbsr      SC_WRITE8
                    bcs       scw32Exit
                    leax      1,x
                    leay      -1,y
                    bne       scw32Loop
scw32Exit           puls      x,y,u,pc

********************************************************************
* SC_PROBE_R1L
* Validate the frozen Community Alpha service foundation needed by S2.
* Exit success: A = CAPS0, B = CAPS1, carry clear.
********************************************************************
SC_PROBE_R1L        pshs      x
                    ldx       #SC.SysMagic0
                    lbsr      SC_READ8
                    lbcs      scpBad
                    cmpa      #'S
                    lbne      scpBad
                    ldx       #SC.SysMagic1
                    lbsr      SC_READ8
                    lbcs      scpBad
                    cmpa      #'C
                    lbne      scpBad
                    ldx       #SC.SysABIMajor
                    lbsr      SC_READ8
                    lbcs      scpBad
                    cmpa      #1
                    lbne      scpBad
                    ldx       #SC.SysABIMinor
                    lbsr      SC_READ8
                    lbcs      scpBad
                    cmpa      #1
                    lbcs      scpBad
                    ldx       #SC.SysCaps0
                    lbsr      SC_READ8
                    lbcs      scpBad
                    pshs      a
                    anda      #SC.CapCoreFabric!SC.CapJobV1!SC.CapGrantV1!SC.CapMBOV1!SC.CapVideoV1!SC.CapGraphicsV1
                    cmpa      #SC.CapCoreFabric!SC.CapJobV1!SC.CapGrantV1!SC.CapMBOV1!SC.CapVideoV1!SC.CapGraphicsV1
                    lbne      scpDropBad
                    ldx       #SC.SysCaps1
                    lbsr      SC_READ8
                    lbcs      scpDropBad
                    bita      #SC.Cap1AudioV1
                    lbeq      scpDropBad
                    tfr       a,b
                    puls      a
                    puls      x
                    andcc     #^Carry
                    rts
scpDropBad          leas      1,s
scpBad              ldb       #E$NotRdy
                    puls      x
                    orcc      #Carry
                    rts

********************************************************************
* Unified service-event helpers.  These access the invariant MMIO bytes
* directly; no service-page transaction is required.
********************************************************************
SC_IRQ_GET          lda       >SC.SvcIRQStatus
                    anda      #SC.IRQImplemented
                    clrb
                    andcc     #^Carry
                    rts

SC_IRQ_ACK          anda      #SC.IRQImplemented
                    sta       >SC.SvcIRQStatus
                    clrb
                    andcc     #^Carry
                    rts

SC_IRQ_MASK_GET     lda       >SC.SvcIRQMask
                    anda      #SC.IRQImplemented
                    clrb
                    andcc     #^Carry
                    rts

SC_IRQ_MASK_SET     anda      #SC.IRQImplemented
                    sta       >SC.SvcIRQMask
                    clrb
                    andcc     #^Carry
                    rts

********************************************************************
* MBO helpers.
********************************************************************
* SC_MBO_BASE
* Entry: B = slot 0..15
* Exit:  X = object page base, B = 0, carry clear
*        B = E$IllArg, carry set for invalid slot
SC_MBO_BASE         cmpb      #16
                    lbcc      scmbBad
                    lslb
                    tfr       b,a
                    clrb
                    addd      #SC.MBOObjectBase
                    tfr       d,x
                    clrb
                    andcc     #^Carry
                    rts
scmbBad             ldb       #E$IllArg
                    orcc      #Carry
                    rts

* SC_MBO_STATUS
* Entry: B = slot
* Exit:  A = status byte on success
SC_MBO_STATUS       pshs      x
                    lbsr      SC_MBO_BASE
                    bcs       scmbsExit
                    leax      SC.MBOStatusO,x
                    lbsr      SC_READ8
scmbsExit           puls      x,pc

* SC_MBO_COMMIT / SC_MBO_REVOKE
* Entry: B = slot
SC_MBO_COMMIT       pshs      x
                    lbsr      SC_MBO_BASE
                    bcs       scmbcExit
                    leax      SC.MBOControlO,x
                    lda       #SC.MBOCtlCommit
                    lbsr      SC_WRITE8
scmbcExit           puls      x,pc

SC_MBO_REVOKE       pshs      x
                    lbsr      SC_MBO_BASE
                    bcs       scmbrExit
                    leax      SC.MBOControlO,x
                    lda       #SC.MBOCtlRevoke
                    lbsr      SC_WRITE8
scmbrExit           puls      x,pc

* SC_MBO_NEXTGEN
* Entry: U = pointer to a four-byte little-endian generation counter.
* Exit:  counter incremented, with zero skipped; B = 0, carry clear.
SC_MBO_NEXTGEN      inc       ,u
                    bne       scngDone
                    inc       1,u
                    bne       scngDone
                    inc       2,u
                    bne       scngDone
                    inc       3,u
                    bne       scngDone
                    inc       ,u
scngDone            clrb
                    andcc     #^Carry
                    rts
