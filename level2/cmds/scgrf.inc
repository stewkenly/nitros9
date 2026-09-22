********************************************************************
* scgrf - SuperCoCo GIME-NG lifecycle backend for GrfDrv
*
* S2B-1 scope:
*   - one production 640x480 INDEX4 screen at a time
*   - two independent 153600-byte framebuffer allocations
*   - framebuffer MBO slots 0/1 with VIDEO|MEDIA authority
*   - GIME-NG surfaces 0/1
*   - VBLANK-safe enable/disable through the S1 event helpers
*   - conservative revoke/drain/free lifetime
*
* Drawing remains deliberately outside this first integration seam.  Later
* S2 increments route GrfDrv operations into R1K without changing style 9 or
* this framebuffer lifetime contract.
********************************************************************

SCG.FBBlocks        equ       19
SCG.FBPages         equ       38
SCG.FBBytes         equ       $2000
SCG.SlotFB0         equ       0
SCG.SlotFB1         equ       1
SCG.SlotCmd         equ       2
SCG.CmdBlocks       equ       1
SCG.CmdPages        equ       1
SCG.CmdBytes        equ       $2000

********************************************************************
* Initialize private state.  Called only on the first GrfDrv init.
********************************************************************
SCG_INIT            clra
                    sta       <grSCFlags
                    sta       <grSCBack
                    std       <grSCScreenTbl
                    std       <grSCFB0Start
                    std       <grSCFB1Start
                    std       <grSCCmdStart
                    std       <grSCGenCmd
                    std       <grSCGenCmd+2
                    rts

********************************************************************
* S2B-1 DWSet implementation.
* Entry: Y = allocated CoWin window table
********************************************************************
SCG_DWSET           pshs      x,y,u

* S2B-1 intentionally accepts only the full production surface.  This keeps
* the first driver seam honest while overlays/subwindows remain on the legacy
* drawing path until the R1K backend is attached.
                    lda       Wt.CPX,y
                    lbne      SCG_DW_BAD
                    lda       Wt.CPY,y
                    lbne      SCG_DW_BAD
                    lda       Wt.SZX,y
                    cmpa      #80
                    lbne      SCG_DW_BAD
                    lda       Wt.SZY,y
                    cmpa      #60
                    lbne      SCG_DW_BAD
                    tst       <grSCFlags
                    lbne      SCG_DW_BAD

                    lbsr      SC_PROBE_R1L
                    lbcs      SCG_DW_BAD
                    lbsr      SCG_PROBE_VIDEO
                    lbcs      SCG_DW_BAD
                    lbsr      SCG_PROBE_GRAPHICS
                    lbcs      SCG_DW_BAD

* Allocate one normal NitrOS screen-table entry, but mark its legacy RAM block
* byte with $FF.  SCG paths intercept this type before old GIME/MMU code can
* interpret that byte as a physical legacy screen allocation.
                    lbsr      FScrTbl
                    lbcs      SCG_DW_BAD
                    stx       Wt.STbl,y
                    stx       <grSCScreenTbl
                    lda       #SCGrfType
                    sta       St.Sty,x
                    lda       #$FF
                    sta       St.SBlk,x
                    clra
                    clrb
                    std       St.LStrt,x
                    clr       St.BRow,x
                    lda       Wt.Fore,y
                    sta       St.Fore,x
                    lda       Wt.Back,y
                    sta       St.Back,x
                    lda       #60
                    sta       St.ScSiz,x

* Window geometry is still expressed in the normal 80x60 character grid and
* 640x480 pixel coordinates so callers do not need a parallel window API.
                    lda       #$FF
                    sta       Wt.BLnk,y
                    clra
                    clrb
                    std       Wt.LStrt,y
                    std       Wt.LStDf,y
                    std       Wt.CurX,y
                    std       Wt.CurY,y
                    lda       #4
                    sta       Wt.CWTmp,y
                    clr       Wt.XBCnt,y
                    ldd       #2560
                    std       Wt.BRow,y
                    ldd       #639
                    std       Wt.MaxX,y
                    ldd       #479
                    std       Wt.MaxY,y
                    ldd       Wt.CPX,y
                    std       Wt.DfCPX,y
                    ldd       Wt.SZX,y
                    std       Wt.DfSZX,y
                    lda       #(TChr!Protect)
                    sta       Wt.BSW,y
                    clr       Wt.LSet,y
                    clr       Wt.PBlk,y

                    lbsr      SCG_ALLOCATE
                    lbcs      SCG_DW_FAIL
                    lbsr      SCG_CLEAR_CMD
                    lbcs      SCG_DW_FAIL
                    ldd       <grSCFB0Start
                    lbsr      SCG_CLEAR_FB
                    lbcs      SCG_DW_FAIL
                    ldd       <grSCFB1Start
                    lbsr      SCG_CLEAR_FB
                    lbcs      SCG_DW_FAIL
                    lbsr      SCG_PROGRAM_MBO0
                    lbcs      SCG_DW_FAIL
                    lbsr      SCG_PROGRAM_MBO1
                    lbcs      SCG_DW_FAIL
                    lbsr      SCG_PROGRAM_CMD_MBO
                    lbcs      SCG_DW_FAIL
                    lbsr      SCG_PROGRAM_SURFACE0
                    lbcs      SCG_DW_FAIL
                    lbsr      SCG_PROGRAM_SURFACE1
                    lbcs      SCG_DW_FAIL
                    lbsr      SCG_PROGRAM_PALETTE
                    lbcs      SCG_DW_FAIL

* Surface 0 becomes front, surface 1 becomes the first future back buffer.
                    lda       #1
                    sta       <grSCBack
                    lbsr      SCG_ENABLE
                    lbcs      SCG_DW_FAIL

                    clrb
                    andcc     #^Carry
                    puls      x,y,u,pc

SCG_DW_FAIL         lbsr      SCG_CLEANUP
SCG_DW_BAD          ldb       #E$NotRdy
                    orcc      #Carry
                    puls      x,y,u,pc

********************************************************************
* Verify the exact R1J surface geometry this backend consumes.
********************************************************************
SCG_PROBE_VIDEO     ldx       #SC.VideoABIMajor
                    lbsr      SC_READ8
                    lbcs      SCG_PV_BAD
                    cmpa      #1
                    lbne      SCG_PV_BAD
                    ldx       #SC.VideoFormat
                    lbsr      SC_READ8
                    lbcs      SCG_PV_BAD
                    cmpa      #SC.VideoFmtIndex4
                    lbne      SCG_PV_BAD
                    ldx       #SC.VideoWidthLo
                    lbsr      SC_READ16LE
                    lbcs      SCG_PV_BAD
                    cmpd      #640
                    lbne      SCG_PV_BAD
                    ldx       #SC.VideoHeightLo
                    lbsr      SC_READ16LE
                    lbcs      SCG_PV_BAD
                    cmpd      #480
                    lbne      SCG_PV_BAD
                    clrb
                    andcc     #^Carry
                    rts
SCG_PV_BAD          ldb       #E$NotRdy
                    orcc      #Carry
                    rts

********************************************************************
* Verify the exact R1K graphics service geometry consumed by S2B-2.
********************************************************************
SCG_PROBE_GRAPHICS  ldx       #SC.GraphicsABIMajor
                    lbsr      SC_READ8
                    lbcs      SCG_PG_BAD
                    cmpa      #1
                    lbne      SCG_PG_BAD
                    ldx       #SC.GraphicsABIMinor
                    lbsr      SC_READ8
                    lbcs      SCG_PG_BAD
                    tsta
                    lbne      SCG_PG_BAD
                    ldx       #SC.GraphicsCaps0
                    lbsr      SC_READ8
                    lbcs      SCG_PG_BAD
* Required here: FILL_RECT, MBO surfaces, command snapshot, MEDIA event.
                    anda      #%01011001
                    cmpa      #%01011001
                    lbne      SCG_PG_BAD
                    ldx       #SC.GraphicsMediaSlot
                    lbsr      SC_READ8
                    lbcs      SCG_PG_BAD
                    cmpa      #3
                    lbne      SCG_PG_BAD
                    ldx       #SC.GraphicsJobOpcode
                    lbsr      SC_READ8
                    lbcs      SCG_PG_BAD
                    cmpa      #SC.GraphicsOpcode
                    lbne      SCG_PG_BAD
                    ldx       #SC.GraphicsCmdSize
                    lbsr      SC_READ8
                    lbcs      SCG_PG_BAD
                    cmpa      #64
                    lbne      SCG_PG_BAD
                    ldx       #SC.GraphicsAlignShift
                    lbsr      SC_READ8
                    lbcs      SCG_PG_BAD
                    cmpa      #6
                    lbne      SCG_PG_BAD
                    ldx       #SC.GraphicsFormat
                    lbsr      SC_READ8
                    lbcs      SCG_PG_BAD
                    cmpa      #SC.GraphicsFmtIndex4
                    lbne      SCG_PG_BAD
                    ldx       #SC.GraphicsMaxWLo
                    lbsr      SC_READ16LE
                    lbcs      SCG_PG_BAD
                    cmpd      #640
                    lbne      SCG_PG_BAD
                    ldx       #SC.GraphicsMaxHLo
                    lbsr      SC_READ16LE
                    lbcs      SCG_PG_BAD
                    cmpd      #480
                    lbne      SCG_PG_BAD
                    clrb
                    andcc     #^Carry
                    rts
SCG_PG_BAD          ldb       #E$NotRdy
                    orcc      #Carry
                    rts

********************************************************************
* Two independent Level-2 RAM objects.
********************************************************************
SCG_ALLOCATE        ldb       #SCG.FBBlocks
                    os9       F$AllRAM
                    lbcs      SCG_ALLOC_BAD
                    std       <grSCFB0Start
                    lda       <grSCFlags
                    ora       #SCG.FlagRAM0
                    sta       <grSCFlags

                    ldb       #SCG.FBBlocks
                    os9       F$AllRAM
                    lbcs      SCG_ALLOC_BAD
                    std       <grSCFB1Start
                    lda       <grSCFlags
                    ora       #SCG.FlagRAM1
                    sta       <grSCFlags

                    ldb       #SCG.CmdBlocks
                    os9       F$AllRAM
                    lbcs      SCG_ALLOC_BAD
                    std       <grSCCmdStart
                    lda       <grSCFlags
                    ora       #SCG.FlagRAMCmd
                    sta       <grSCFlags
                    clrb
                    andcc     #^Carry
                    rts
SCG_ALLOC_BAD       orcc      #Carry
                    rts

********************************************************************
* GrfDrv executes in Task 1.  F$MapBlk edits the current process DAT image,
* so it is not the mapping seam for memory GrfDrv itself accesses.  Reuse the
* established Task-1 GP scratch window: $FFA9 maps one 8K block at $2000.
* Entry B = physical 8K block.  Exit X = $2000.
********************************************************************
SCG_T1_MAP_BLOCK    lda       <gr0087+2
                    sta       <grSCMapSave
                    lda       <gr0087+3
                    sta       <grSCMapSave+1
                    clr       <gr0087+2
                    stb       <gr0087+3
                    stb       >$FFA9
                    ldx       #$2000
                    rts

SCG_T1_RESTORE      lda       <grSCMapSave
                    sta       <gr0087+2
                    lda       <grSCMapSave+1
                    sta       <gr0087+3
                    sta       >$FFA9
                    rts

********************************************************************
* Entry D = first 8K physical block.  Clear all 19 owned blocks before they
* become visible to VIDEO or writable by MEDIA.
********************************************************************
SCG_CLEAR_FB        pshs      x,y,u
                    std       <grSCCurrentBlock
                    lda       #SCG.FBBlocks
                    sta       <grSCBlocksLeft
SCG_CF_BLOCK        ldb       <grSCCurrentBlock+1
                    lbsr      SCG_T1_MAP_BLOCK
                    ldy       #SCG.FBBytes
                    clra
SCG_CF_BYTE         sta       ,x+
                    leay      -1,y
                    lbne      SCG_CF_BYTE
                    lbsr      SCG_T1_RESTORE

                    ldd       <grSCCurrentBlock
                    addd      #1
                    std       <grSCCurrentBlock
                    dec       <grSCBlocksLeft
                    lbne      SCG_CF_BLOCK
                    clrb
                    andcc     #^Carry
                    puls      x,y,u,pc

********************************************************************
* Clear the dedicated 8K command block before publishing its first 4K page.
********************************************************************
SCG_CLEAR_CMD       pshs      x,y,u
                    ldb       <grSCCmdStart+1
                    lbsr      SCG_T1_MAP_BLOCK
                    ldy       #SCG.CmdBytes
                    clra
SCG_CC_BYTE         sta       ,x+
                    leay      -1,y
                    lbne      SCG_CC_BYTE
                    lbsr      SCG_T1_RESTORE
                    clrb
                    andcc     #^Carry
                    puls      x,y,u,pc

********************************************************************
* MBO publication.  Framebuffers are already provisioned for the later R1K
* drawing backend: VIDEO|MEDIA consumers and READ|WRITE authority.
********************************************************************
SCG_PREP_SLOT       lbsr      SC_MBO_STATUS
                    lbcs      SCG_PS_BAD
                    bita      #SC.MBOStatusValid!SC.MBOStatusBusy
                    lbne      SCG_PS_BAD
                    clrb
                    andcc     #^Carry
                    rts
SCG_PS_BAD          ldb       #E$NotRdy
                    orcc      #Carry
                    rts

SCG_PROGRAM_MBO0    ldd       #SC.MBOObjectBase
                    std       <grSCMBOBase
                    ldd       <grSCFB0Start
                    std       <grSCMBOStart
                    ldd       #GrfMem+grSCGen0
                    std       <grSCGenPtr
                    clr       <grSCSlot
                    lda       #SCG.FlagMBO0
                    sta       <grSCFlagMask
                    lbsr      SCG_PROGRAM_MBO
                    rts

SCG_PROGRAM_MBO1    ldd       #SC.MBOObjectBase+SC.MBOObjectStride
                    std       <grSCMBOBase
                    ldd       <grSCFB1Start
                    std       <grSCMBOStart
                    ldd       #GrfMem+grSCGen1
                    std       <grSCGenPtr
                    lda       #1
                    sta       <grSCSlot
                    lda       #SCG.FlagMBO1
                    sta       <grSCFlagMask
                    lbsr      SCG_PROGRAM_MBO
                    rts

SCG_PROGRAM_MBO     ldb       <grSCSlot
                    lbsr      SCG_PREP_SLOT
                    lbcs      SCG_PM_BAD

                    ldx       <grSCMBOBase
                    leax      SC.MBOPermissionsO,x
                    lda       #SC.MBOPermRead!SC.MBOPermWrite
                    lbsr      SC_WRITE8
                    lbcs      SCG_PM_BAD
                    ldx       <grSCMBOBase
                    leax      SC.MBOConsumersO,x
                    lda       #SC.MBOConsumerVideo!SC.MBOConsumerMedia
                    lbsr      SC_WRITE8
                    lbcs      SCG_PM_BAD

* logical length = $00025800 = 153600 bytes
                    ldx       <grSCMBOBase
                    leax      SC.MBOLengthO,x
                    clra
                    lbsr      SC_WRITE8
                    lbcs      SCG_PM_BAD
                    leax      1,x
                    lda       #$58
                    lbsr      SC_WRITE8
                    lbcs      SCG_PM_BAD
                    leax      1,x
                    lda       #$02
                    lbsr      SC_WRITE8
                    lbcs      SCG_PM_BAD
                    leax      1,x
                    clra
                    lbsr      SC_WRITE8
                    lbcs      SCG_PM_BAD

                    ldx       <grSCMBOBase
                    leax      SC.MBOPageCountO,x
                    lda       #SCG.FBPages
                    lbsr      SC_WRITE8
                    lbcs      SCG_PM_BAD

                    ldd       <grSCMBOStart
                    lslb
                    rola
                    std       <grSCPPN
                    lda       #SCG.FBPages
                    sta       <grSCPagesLeft
                    ldx       <grSCMBOBase
                    leax      SC.MBOPageListO,x
SCG_PM_PAGE         ldd       <grSCPPN
                    lbsr      SC_WRITE16LE
                    lbcs      SCG_PM_BAD
                    leax      2,x
                    ldd       <grSCPPN
                    addd      #1
                    std       <grSCPPN
                    dec       <grSCPagesLeft
                    lbne      SCG_PM_PAGE

* Mark potentially live before COMMIT because timeout does not prove rejection.
                    lda       <grSCFlags
                    ora       <grSCFlagMask
                    sta       <grSCFlags
                    ldb       <grSCSlot
                    lbsr      SC_MBO_COMMIT
                    lbcs      SCG_PM_BAD
                    ldb       <grSCSlot
                    lbsr      SC_MBO_STATUS
                    lbcs      SCG_PM_BAD
                    bita      #SC.MBOStatusValid
                    lbeq      SCG_PM_BAD

                    ldx       <grSCMBOBase
                    leax      SC.MBOGenerationO,x
                    pshs      u
                    ldu       <grSCGenPtr
                    lbsr      SC_READ32LE
                    puls      u
                    lbcs      SCG_PM_BAD
                    clrb
                    andcc     #^Carry
                    rts
SCG_PM_BAD          ldb       #E$NotRdy
                    orcc      #Carry
                    rts

********************************************************************
* Dedicated R1K command MBO.  Only the first 4K page is exposed; record 0
* occupies bytes 0..63.  MEDIA receives READ authority only.
********************************************************************
SCG_PROGRAM_CMD_MBO ldb       #SCG.SlotCmd
                    lbsr      SCG_PREP_SLOT
                    lbcs      SCG_PCM_BAD

                    ldd       #SC.MBOObjectBase+(SCG.SlotCmd*SC.MBOObjectStride)
                    std       <grSCMBOBase
                    ldx       <grSCMBOBase
                    leax      SC.MBOPermissionsO,x
                    lda       #SC.MBOPermRead
                    lbsr      SC_WRITE8
                    lbcs      SCG_PCM_BAD
                    ldx       <grSCMBOBase
                    leax      SC.MBOConsumersO,x
                    lda       #SC.MBOConsumerMedia
                    lbsr      SC_WRITE8
                    lbcs      SCG_PCM_BAD

* logical length = one 4K MBO page
                    ldx       <grSCMBOBase
                    leax      SC.MBOLengthO,x
                    clra
                    lbsr      SC_WRITE8
                    lbcs      SCG_PCM_BAD
                    leax      1,x
                    lda       #$10
                    lbsr      SC_WRITE8
                    lbcs      SCG_PCM_BAD
                    leax      1,x
                    clra
                    lbsr      SC_WRITE8
                    lbcs      SCG_PCM_BAD
                    leax      1,x
                    clra
                    lbsr      SC_WRITE8
                    lbcs      SCG_PCM_BAD

                    ldx       <grSCMBOBase
                    leax      SC.MBOPageCountO,x
                    lda       #SCG.CmdPages
                    lbsr      SC_WRITE8
                    lbcs      SCG_PCM_BAD

* First 4K PPN is twice the NitrOS 8K physical block number.
                    ldd       <grSCCmdStart
                    lslb
                    rola
                    ldx       <grSCMBOBase
                    leax      SC.MBOPageListO,x
                    lbsr      SC_WRITE16LE
                    lbcs      SCG_PCM_BAD

* Mark potentially live before COMMIT because timeout does not prove reject.
                    lda       <grSCFlags
                    ora       #SCG.FlagMBOCmd
                    sta       <grSCFlags
                    ldb       #SCG.SlotCmd
                    lbsr      SC_MBO_COMMIT
                    lbcs      SCG_PCM_BAD
                    ldb       #SCG.SlotCmd
                    lbsr      SC_MBO_STATUS
                    lbcs      SCG_PCM_BAD
                    bita      #SC.MBOStatusValid
                    lbeq      SCG_PCM_BAD

                    ldx       <grSCMBOBase
                    leax      SC.MBOGenerationO,x
                    ldu       #GrfMem+grSCGenCmd
                    lbsr      SC_READ32LE
                    lbcs      SCG_PCM_BAD
                    clrb
                    andcc     #^Carry
                    rts
SCG_PCM_BAD         ldb       #E$NotRdy
                    orcc      #Carry
                    rts

********************************************************************
* Surface descriptors.
********************************************************************
SCG_PROGRAM_SURFACE0
                    ldd       #SC.VideoSurface0
                    std       <grSCSurfaceBase
                    ldd       #GrfMem+grSCGen0
                    std       <grSCSurfaceGenPtr
                    clr       <grSCSurfaceSlot
                    lbsr      SCG_PROGRAM_SURFACE
                    rts

SCG_PROGRAM_SURFACE1
                    ldd       #SC.VideoSurface1
                    std       <grSCSurfaceBase
                    ldd       #GrfMem+grSCGen1
                    std       <grSCSurfaceGenPtr
                    lda       #1
                    sta       <grSCSurfaceSlot
                    lbsr      SCG_PROGRAM_SURFACE
                    rts

SCG_PROGRAM_SURFACE ldx       <grSCSurfaceBase
                    leax      SC.VideoSurfMBOSlotO,x
                    lda       <grSCSurfaceSlot
                    lbsr      SC_WRITE8
                    lbcs      SCG_SURF_BAD
                    ldx       <grSCSurfaceBase
                    leax      SC.VideoSurfFormatO,x
                    lda       #SC.VideoFmtIndex4
                    lbsr      SC_WRITE8
                    lbcs      SCG_SURF_BAD
                    ldx       <grSCSurfaceBase
                    leax      SC.VideoSurfGenerationO,x
                    pshs      u
                    ldu       <grSCSurfaceGenPtr
                    lbsr      SC_WRITE32LE
                    puls      u
                    lbcs      SCG_SURF_BAD

                    ldx       <grSCSurfaceBase
                    leax      SC.VideoSurfOffsetO,x
                    clra
                    lbsr      SC_WRITE8
                    lbcs      SCG_SURF_BAD
                    leax      1,x
                    clra
                    lbsr      SC_WRITE8
                    lbcs      SCG_SURF_BAD
                    leax      1,x
                    clra
                    lbsr      SC_WRITE8
                    lbcs      SCG_SURF_BAD
                    leax      1,x
                    clra
                    lbsr      SC_WRITE8
                    lbcs      SCG_SURF_BAD

                    ldx       <grSCSurfaceBase
                    leax      SC.VideoSurfStrideO,x
                    ldd       #$0140
                    lbsr      SC_WRITE16LE
                    lbcs      SCG_SURF_BAD
                    clrb
                    andcc     #^Carry
                    rts
SCG_SURF_BAD        ldb       #E$NotRdy
                    orcc      #Carry
                    rts

********************************************************************
* Initial RGB888 palette.  The driver will later connect normal palette
* SetStat operations to this same service page.
********************************************************************
SCG_PROGRAM_PALETTE ldx       #SC.VideoPalette
                    leay      SCG_PALETTE,pcr
                    lda       #48
                    sta       <grSCPaletteLeft
SCG_PP_LOOP         lda       ,y+
                    lbsr      SC_WRITE8
                    lbcs      SCG_PP_BAD
                    leax      1,x
                    dec       <grSCPaletteLeft
                    lbne      SCG_PP_LOOP
                    clrb
                    andcc     #^Carry
                    rts
SCG_PP_BAD          ldb       #E$NotRdy
                    orcc      #Carry
                    rts

SCG_PALETTE         fcb       $00,$00,$00
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

********************************************************************
* S2B-3 normal BAR backend.
* CoWin has already copied the current draw pointer to gr0047/gr0049 and the
* destination to gr004B/gr004D.  Reuse GrfDrv's normal scale/range checks and
* coordinate normalization, then issue one semantic R1K rectangle operation.
* Pattern and logical-set variants remain explicitly deferred.
********************************************************************
SCG_BAR_ENTRY       lda       <grSCFlags
                    bita      #SCG.FlagMirrorDirty
                    lbne      SCG_BAR_BAD
                    tst       Wt.PBlk,y
                    lbne      SCG_BAR_BAD
                    tst       Wt.LSet,y
                    lbne      SCG_BAR_BAD

                    lbsr      L1DFD               Scale/check destination X/Y
                    lbcs      SCG_BAR_RETURN
                    lbsr      L1DF6               Scale/check current X/Y
                    lbcs      SCG_BAR_RETURN
                    lbsr      L16A3               Normalize X low..high
                    lbsr      L1716               Normalize Y low..high

                    lda       Wt.Fore,y
                    anda      #$0F
                    sta       <grSCColor
                    lbsr      SCG_RENDER_RECT
                    lbcs      SCG_BAR_BAD
                    clrb
                    andcc     #^Carry
SCG_BAR_RETURN      rts
SCG_BAR_BAD         ldb       #E$NotRdy
                    orcc      #Carry
                    rts

********************************************************************
* S2B-2 normal CLS backend.
* Entry: Y = current style-9 window table.
********************************************************************
SCG_CLS_ENTRY       lda       Wt.Back,y
                    anda      #$0F
                    sta       <grSCColor
                    clra
                    clrb
                    std       Wt.Cur,y
                    std       Wt.CurX,y
                    std       Wt.CurY,y
                    std       <gr0047             rectangle left = 0
                    std       <gr0049             rectangle top = 0
                    sta       Wt.FMsk,y
                    sta       <gr00A9
                    ldd       #639
                    std       <gr004B             rectangle right
                    ldd       #479
                    std       <gr004D             rectangle bottom
                    lda       #SCGrfType
                    sta       <Gr.STYMk
* A full-screen overwrite is also the recovery operation for any conservative
* mirror-dirty state left by an earlier failed partial transaction.
                    lbsr      SCG_RENDER_RECT
                    lbcs      SCG_CLS_BAD
                    clrb
                    andcc     #^Carry
                    rts
SCG_CLS_BAD         ldb       #E$NotRdy
                    orcc      #Carry
                    rts

********************************************************************
* Build Graphics Command V1 record 0 in the dedicated command MBO.
********************************************************************
SCG_BUILD_FILL      pshs      x,y,u
                    ldb       <grSCCmdStart+1
                    lbsr      SCG_T1_MAP_BLOCK
                    stx       <grSCMapAddr
                    ldy       #64
                    clra
SCG_BF_ZERO         sta       ,x+
                    leay      -1,y
                    lbne      SCG_BF_ZERO

                    ldx       <grSCMapAddr
                    lda       #1
                    sta       SC.GfxCmdABIMajorO,x
                    lda       #SC.GraphicsOpFill
                    sta       SC.GfxCmdOperationO,x
                    lda       <grSCColor
                    sta       SC.GfxCmdColorO,x

* Destination descriptor: current back MBO, INDEX4, generation, offset 0,
* stride 320, width 640, height 480.
                    leax      SC.GfxCmdDestO,x
                    lda       <grSCBack
                    sta       ,x
                    lda       #SC.GraphicsFmtIndex4
                    sta       1,x
                    lda       <grSCBack
                    lbeq      SCG_BF_GEN0
                    ldu       #GrfMem+grSCGen1
                    lbra      SCG_BF_GENCOPY
SCG_BF_GEN0         ldu       #GrfMem+grSCGen0
SCG_BF_GENCOPY      lda       ,u+
                    sta       2,x
                    lda       ,u+
                    sta       3,x
                    lda       ,u+
                    sta       4,x
                    lda       ,u
                    sta       5,x
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

                    ldx       <grSCMapAddr
* Destination X/Y are the normalized inclusive upper-left coordinates.
                    ldd       <gr0047
                    stb       SC.GfxCmdDstXO,x
                    sta       SC.GfxCmdDstXO+1,x
                    ldd       <gr0049
                    stb       SC.GfxCmdDstYO,x
                    sta       SC.GfxCmdDstYO+1,x
* Convert inclusive end coordinates to width/height.
                    ldd       <gr004B
                    subd      <gr0047
                    incd
                    stb       SC.GfxCmdWidthO,x
                    sta       SC.GfxCmdWidthO+1,x
                    ldd       <gr004D
                    subd      <gr0049
                    incd
                    stb       SC.GfxCmdHeightO,x
                    sta       SC.GfxCmdHeightO+1,x

                    lbsr      SCG_T1_RESTORE
                    clrb
                    andcc     #^Carry
                    puls      x,y,u,pc

********************************************************************
* Execute one semantic rectangle while preserving the mirrored-buffer
* invariant.  grSCBack names the hidden surface on entry.  First render there,
* flip it visible at VBLANK, then replay the same operation into the now-hidden
* old front.  The dirty bit remains set on any failure; a later full CLS can
* safely recover because it overwrites both buffers completely.
********************************************************************
SCG_RENDER_RECT     lda       <grSCFlags
                    ora       #SCG.FlagMirrorDirty
                    sta       <grSCFlags

                    lbsr      SCG_BUILD_FILL
                    lbcs      SCG_RR_BAD
                    lbsr      SCG_SUBMIT_FILL
                    lbcs      SCG_RR_BAD
                    lbsr      SCG_PRESENT_BACK
                    lbcs      SCG_RR_BAD

* Full-screen overwrite remains the recovery primitive from S2B-3.  Keep its
* second FILL independent of BLIT so CLS can recover a dirty mirror even if
* BLIT itself is the operation that previously failed.
                    ldd       <gr0047
                    lbne      SCG_RR_MIRROR_BLIT
                    ldd       <gr0049
                    lbne      SCG_RR_MIRROR_BLIT
                    ldd       <gr004B
                    cmpd      #639
                    lbne      SCG_RR_MIRROR_BLIT
                    ldd       <gr004D
                    cmpd      #479
                    lbne      SCG_RR_MIRROR_BLIT
                    lbsr      SCG_BUILD_FILL
                    lbra      SCG_RR_MIRROR_SUBMIT

* For a partial operation, the just-presented front contains the authoritative
* complete image.  Copy that full image to the newly hidden old front with R1K
* BLIT.  VIDEO and MEDIA may concurrently hold READ bindings on the source MBO;
* R1I BUSY is a binding count, not an exclusive lock.
SCG_RR_MIRROR_BLIT  lbsr      SCG_BUILD_MIRROR_BLIT
SCG_RR_MIRROR_SUBMIT
                    lbcs      SCG_RR_BAD
                    lbsr      SCG_SUBMIT_FILL
                    lbcs      SCG_RR_BAD

                    lda       <grSCFlags
                    anda      #^SCG.FlagMirrorDirty
                    sta       <grSCFlags
                    clrb
                    andcc     #^Carry
                    rts
SCG_RR_BAD          ldb       #E$NotRdy
                    orcc      #Carry
                    rts

********************************************************************
* S2B-4 full-frame mirror BLIT.
* After SCG_PRESENT_BACK, grSCBack names the newly hidden old front and
* grSCBack^1 names the visible authoritative front.  Build a 640x480 BLIT
* from visible -> hidden.  The command MBO and both framebuffer MBOs already
* carry the required MEDIA authority.
********************************************************************
SCG_BUILD_MIRROR_BLIT
                    pshs      x,y,u
                    ldb       <grSCCmdStart+1
                    lbsr      SCG_T1_MAP_BLOCK
                    stx       <grSCMapAddr
                    ldy       #64
                    clra
SCG_BMB_ZERO        sta       ,x+
                    leay      -1,y
                    lbne      SCG_BMB_ZERO

                    ldx       <grSCMapAddr
                    lda       #1
                    sta       SC.GfxCmdABIMajorO,x
                    lda       #SC.GraphicsOpBlit
                    sta       SC.GfxCmdOperationO,x

* Source descriptor = visible front = grSCBack XOR 1.
                    leax      SC.GfxCmdSourceO,x
                    lda       <grSCBack
                    eora      #1
                    sta       ,x
                    lda       #SC.GraphicsFmtIndex4
                    sta       1,x
                    lda       <grSCBack
                    eora      #1
                    lbeq      SCG_BMB_SGEN0
                    ldu       #GrfMem+grSCGen1
                    lbra      SCG_BMB_SGENCOPY
SCG_BMB_SGEN0       ldu       #GrfMem+grSCGen0
SCG_BMB_SGENCOPY    lda       ,u+
                    sta       2,x
                    lda       ,u+
                    sta       3,x
                    lda       ,u+
                    sta       4,x
                    lda       ,u
                    sta       5,x
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

* Destination descriptor = current hidden back = grSCBack.
                    ldx       <grSCMapAddr
                    leax      SC.GfxCmdDestO,x
                    lda       <grSCBack
                    sta       ,x
                    lda       #SC.GraphicsFmtIndex4
                    sta       1,x
                    lda       <grSCBack
                    lbeq      SCG_BMB_DGEN0
                    ldu       #GrfMem+grSCGen1
                    lbra      SCG_BMB_DGENCOPY
SCG_BMB_DGEN0       ldu       #GrfMem+grSCGen0
SCG_BMB_DGENCOPY    lda       ,u+
                    sta       2,x
                    lda       ,u+
                    sta       3,x
                    lda       ,u+
                    sta       4,x
                    lda       ,u
                    sta       5,x
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

* Command record was zeroed, so SRC_X/SRC_Y/DST_X/DST_Y are all zero.
* width = 640 ($0280), height = 480 ($01E0), little endian.
                    ldx       <grSCMapAddr
                    lda       #$80
                    sta       SC.GfxCmdWidthO,x
                    lda       #$02
                    sta       SC.GfxCmdWidthO+1,x
                    lda       #$E0
                    sta       SC.GfxCmdHeightO,x
                    lda       #$01
                    sta       SC.GfxCmdHeightO+1,x

                    lbsr      SCG_T1_RESTORE
                    clrb
                    andcc     #^Carry
                    puls      x,y,u,pc

********************************************************************
* Submit command MBO slot 2 / record 0 through MEDIA Job V1 and wait until
* COMPLETE.  W1C MEDIA event and Job ACK are deliberately independent.
********************************************************************
SCG_SUBMIT_FILL     pshs      x,y,u
* Initial channel state and descriptor staging.
                    ldx       #SC.MediaJobBase+SC.JobStateO
                    lbsr      SC_READ8
                    lbcs      SCG_SF_BAD
                    cmpa      #SC.JobIdle
                    lbne      SCG_SF_BAD

                    lda       #SC.IRQMedia
                    lbsr      SC_IRQ_ACK

                    ldx       #SC.MediaJobBase+SC.JobOpcodeO
                    lda       #SC.GraphicsOpcode
                    lbsr      SC_WRITE8
                    lbcs      SCG_SF_BAD
                    leax      1,x
                    clra
                    lbsr      SC_WRITE8
                    lbcs      SCG_SF_BAD
* Deterministic tag $B202, little endian.
                    leax      1,x
                    lda       #$02
                    lbsr      SC_WRITE8
                    lbcs      SCG_SF_BAD
                    leax      1,x
                    lda       #$B2
                    lbsr      SC_WRITE8
                    lbcs      SCG_SF_BAD
* ARG0 = command MBO slot 2, high byte reserved zero.
                    leax      1,x
                    lda       #SCG.SlotCmd
                    lbsr      SC_WRITE8
                    lbcs      SCG_SF_BAD
                    leax      1,x
                    clra
                    lbsr      SC_WRITE8
                    lbcs      SCG_SF_BAD
* ARG1/ARG2 = command MBO generation little endian.
                    leax      1,x
                    lda       <grSCGenCmd
                    lbsr      SC_WRITE8
                    lbcs      SCG_SF_BAD
                    leax      1,x
                    lda       <grSCGenCmd+1
                    lbsr      SC_WRITE8
                    lbcs      SCG_SF_BAD
                    leax      1,x
                    lda       <grSCGenCmd+2
                    lbsr      SC_WRITE8
                    lbcs      SCG_SF_BAD
                    leax      1,x
                    lda       <grSCGenCmd+3
                    lbsr      SC_WRITE8
                    lbcs      SCG_SF_BAD
* ARG3 = record index 0.
                    leax      1,x
                    clra
                    lbsr      SC_WRITE8
                    lbcs      SCG_SF_BAD
                    leax      1,x
                    clra
                    lbsr      SC_WRITE8
                    lbcs      SCG_SF_BAD
* Legacy Job V1 buffer descriptors must be zero.
                    ldx       #SC.MediaJobBase+SC.JobBuf0O
SCG_SF_ZBUF         clra
                    lbsr      SC_WRITE8
                    lbcs      SCG_SF_BAD
                    leax      1,x
                    cmpx      #SC.MediaJobBase+SC.JobBufEndO+1
                    lblo      SCG_SF_ZBUF

* Submit only after the complete descriptor has been staged.
                    ldx       #SC.MediaJobBase+SC.JobControlO
                    lda       #SC.JobCtlSubmit
                    lbsr      SC_WRITE8
                    lbcs      SCG_SF_BAD

* Doorbell accepted; poll until the MEDIA job reaches a terminal state.
                    ldy       #$FFFF
SCG_SF_WAIT         ldx       #SC.MediaJobBase+SC.JobStateO
                    lbsr      SC_READ8
                    lbcs      SCG_SF_BAD
                    cmpa      #SC.JobComplete
                    lbeq      SCG_SF_COMPLETE
                    cmpa      #SC.JobErrorState
                    lbeq      SCG_SF_TERM_BAD
                    cmpa      #SC.JobPending
                    lbeq      SCG_SF_NEXT
                    cmpa      #SC.JobBusy
                    lbne      SCG_SF_BAD
SCG_SF_NEXT         leay      -1,y
                    lbne      SCG_SF_WAIT
                    lbra      SCG_SF_BAD

* Terminal ERROR: clear the independent event, ACK the channel, fail.
SCG_SF_TERM_BAD     lda       #SC.IRQMedia
                    lbsr      SC_IRQ_ACK
                    ldx       #SC.MediaJobBase+SC.JobControlO
                    lda       #SC.JobCtlAck
                    lbsr      SC_WRITE8
                    lbra      SCG_SF_BAD

* COMPLETE: validate result/event and preserve independent W1C + Job ACK.
SCG_SF_COMPLETE     ldx       #SC.MediaJobBase+SC.JobResultO
                    lbsr      SC_READ8
                    lbcs      SCG_SF_ACK_BAD
                    tsta
                    lbne      SCG_SF_ACK_BAD
                    lbsr      SC_IRQ_GET
                    bita      #SC.IRQMedia
                    lbeq      SCG_SF_ACK_BAD
                    lda       #SC.IRQMedia
                    lbsr      SC_IRQ_ACK
* Event clear must not clear Job COMPLETE.
                    ldx       #SC.MediaJobBase+SC.JobStateO
                    lbsr      SC_READ8
                    lbcs      SCG_SF_ACK_BAD
                    cmpa      #SC.JobComplete
                    lbne      SCG_SF_ACK_BAD
                    ldx       #SC.MediaJobBase+SC.JobControlO
                    lda       #SC.JobCtlAck
                    lbsr      SC_WRITE8
                    lbcs      SCG_SF_BAD
                    ldx       #SC.MediaJobBase+SC.JobStateO
                    lbsr      SC_READ8
                    lbcs      SCG_SF_BAD
                    cmpa      #SC.JobIdle
                    lbne      SCG_SF_BAD
                    clrb
                    andcc     #^Carry
                    puls      x,y,u,pc

* Best-effort terminal ACK on malformed completion protocol.
SCG_SF_ACK_BAD      ldx       #SC.MediaJobBase+SC.JobControlO
                    lda       #SC.JobCtlAck
                    lbsr      SC_WRITE8
SCG_SF_BAD          orcc      #Carry
                    puls      x,y,u,pc

********************************************************************
* Atomically expose the completed back buffer at VBLANK, then swap roles.
********************************************************************
SCG_PRESENT_BACK    pshs      x,y
                    lda       <grSCFlags
                    bita      #SCG.FlagVideo
                    lbeq      SCG_PB_BAD

* VIDEO is a periodic VBLANK event while GIME-NG scanout is active.  It is
* therefore a wakeup, not a unique completion token for this DISPLAY_COMMIT.
* Clear the currently latched event, submit the bundle, then tolerate a stale
* or unrelated VBLANK and fence on the authoritative active-surface state.
                    lda       #SC.IRQVideo
                    lbsr      SC_IRQ_ACK
                    ldx       #SC.VideoStageEnable
                    lda       #1
                    lbsr      SC_WRITE8
                    lbcs      SCG_PB_BAD
                    ldx       #SC.VideoStageSurface
                    lda       <grSCBack
                    lbsr      SC_WRITE8
                    lbcs      SCG_PB_BAD
                    ldx       #SC.VideoControl
                    lda       #SC.VideoCtlCommit
                    lbsr      SC_WRITE8
                    lbcs      SCG_PB_BAD

* A VBLANK may have occurred after the W1C above but before DISPLAY_COMMIT.
* In that case the first observed event belongs to the old surface.  Wait for
* up to four VBLANK observations and accept only when the requested surface is
* actually active.  SCG_WAIT_VIDEO preserves Y.
                    ldy       #4
SCG_PB_WAIT_ACTIVE  lbsr      SCG_WAIT_VIDEO
                    lbcs      SCG_PB_BAD
                    ldx       #SC.VideoActiveSurface
                    lbsr      SC_READ8
                    lbcs      SCG_PB_BAD
                    cmpa      <grSCBack
                    lbeq      SCG_PB_ACTIVE
                    leay      -1,y
                    lbne      SCG_PB_WAIT_ACTIVE
                    lbra      SCG_PB_BAD
SCG_PB_ACTIVE       lda       <grSCBack
                    eora      #1
                    sta       <grSCBack
                    clrb
                    andcc     #^Carry
                    puls      x,y,pc
SCG_PB_BAD          ldb       #E$NotRdy
                    orcc      #Carry
                    puls      x,y,pc

********************************************************************
* VBLANK event wait.
********************************************************************
SCG_WAIT_VIDEO      pshs      y
                    ldy       #$FFFF
SCG_WV_LOOP         lbsr      SC_IRQ_GET
                    bita      #SC.IRQVideo
                    lbne      SCG_WV_SEEN
                    leay      -1,y
                    lbne      SCG_WV_LOOP
                    ldb       #E$NotRdy
                    orcc      #Carry
                    puls      y,pc
SCG_WV_SEEN         lda       #SC.IRQVideo
                    lbsr      SC_IRQ_ACK
                    clrb
                    andcc     #^Carry
                    puls      y,pc

********************************************************************
* Present the current front surface.  grSCBack always names the other surface.
********************************************************************
SCG_ENABLE          lda       <grSCFlags
                    bita      #SCG.FlagVideo
                    lbne      SCG_EN_DONE

                    lda       #SC.IRQVideo
                    lbsr      SC_IRQ_ACK
                    ldx       #SC.VideoStageEnable
                    lda       #1
                    lbsr      SC_WRITE8
                    lbcs      SCG_EN_BAD
                    lda       <grSCBack
                    eora      #1
                    sta       <grSCSlot            Save expected front surface
                    ldx       #SC.VideoStageSurface
                    lbsr      SC_WRITE8
                    lbcs      SCG_EN_BAD

                    lda       <grSCFlags
                    ora       #SCG.FlagVideo
                    sta       <grSCFlags
                    ldx       #SC.VideoControl
                    lda       #SC.VideoCtlCommit
                    lbsr      SC_WRITE8
                    lbcs      SCG_EN_BAD
                    lbsr      SCG_WAIT_VIDEO
                    lbcs      SCG_EN_BAD
                    ldx       #SC.VideoActiveSurface
                    lbsr      SC_READ8
                    lbcs      SCG_EN_BAD
                    cmpa      <grSCSlot
                    lbne      SCG_EN_BAD
SCG_EN_DONE         clrb
                    andcc     #^Carry
                    rts
SCG_EN_BAD          ldb       #E$NotRdy
                    orcc      #Carry
                    rts

SCG_DISABLE         lda       <grSCFlags
                    bita      #SCG.FlagVideo
                    lbeq      SCG_DIS_DONE
                    lda       #SC.IRQVideo
                    lbsr      SC_IRQ_ACK
                    ldx       #SC.VideoStageEnable
                    clra
                    lbsr      SC_WRITE8
                    lbcs      SCG_DIS_BAD
                    ldx       #SC.VideoControl
                    lda       #SC.VideoCtlCommit
                    lbsr      SC_WRITE8
                    lbcs      SCG_DIS_BAD
                    lbsr      SCG_WAIT_VIDEO
                    lbcs      SCG_DIS_BAD
                    ldx       #SC.VideoActiveSurface
                    lbsr      SC_READ8
                    lbcs      SCG_DIS_BAD
                    cmpa      #$FF
                    lbne      SCG_DIS_BAD
                    lda       <grSCFlags
                    anda      #^SCG.FlagVideo
                    sta       <grSCFlags
SCG_DIS_DONE        clrb
                    andcc     #^Carry
                    rts
SCG_DIS_BAD         ldb       #E$NotRdy
                    orcc      #Carry
                    rts

********************************************************************
* Select hooks used by GrfDrv.  A SuperCoCo screen never enters the legacy
* GIME select/MMU path.
********************************************************************
SCG_SELECT_WINDOW   lbsr      SCG_ENABLE
                    lbcs      SCG_SELECT_BAD
                    sty       <gr002E
                    ldx       Wt.STbl,y
                    stx       <gr0030
                    clrb
                    jmp       >GrfStrt+L0F78
SCG_SELECT_BAD      jmp       >GrfStrt+SysRet

SCG_HIDE_FOR_LEGACY lbsr      SCG_DISABLE
                    rts

********************************************************************
* Revoke and drain one framebuffer MBO.
* Entry B=slot, A=flag mask.
********************************************************************
SCG_REVOKE_MBO      sta       <grSCFlagMask
                    stb       <grSCSlot
                    bita      <grSCFlags
                    lbeq      SCG_RM_DONE
                    lbsr      SC_MBO_STATUS
                    lbcs      SCG_RM_BAD
                    bita      #SC.MBOStatusValid!SC.MBOStatusBusy
                    lbeq      SCG_RM_CLEAR
                    ldb       <grSCSlot
                    lbsr      SC_MBO_REVOKE
                    lbcc      SCG_RM_WAIT_START
                    ldb       <grSCSlot
                    lbsr      SC_MBO_STATUS
                    lbcs      SCG_RM_BAD
                    bita      #SC.MBOStatusValid!SC.MBOStatusBusy
                    lbeq      SCG_RM_CLEAR
                    lbra      SCG_RM_BAD
SCG_RM_WAIT_START   pshs      y
                    ldy       #$FFFF
SCG_RM_WAIT         ldb       <grSCSlot
                    lbsr      SC_MBO_STATUS
                    lbcs      SCG_RM_WAIT_BAD
                    bita      #SC.MBOStatusBusy
                    lbeq      SCG_RM_WAIT_DONE
                    leay      -1,y
                    lbne      SCG_RM_WAIT
SCG_RM_WAIT_BAD     puls      y
                    lbra      SCG_RM_BAD
SCG_RM_WAIT_DONE    puls      y
SCG_RM_CLEAR        lda       <grSCFlagMask
                    coma
                    anda      <grSCFlags
                    sta       <grSCFlags
SCG_RM_DONE         clrb
                    andcc     #^Carry
                    rts
SCG_RM_BAD          ldb       #E$NotRdy
                    orcc      #Carry
                    rts

********************************************************************
* Free RAM only after no consumer authority remains.
********************************************************************
SCG_FREE_RAM        lda       <grSCFlags
                    bita      #SCG.FlagMBO0!SCG.FlagMBO1!SCG.FlagMBOCmd!SCG.FlagVideo
                    lbne      SCG_FR_BAD
                    bita      #SCG.FlagRAMCmd
                    lbeq      SCG_FR_1
                    ldx       <grSCCmdStart
                    ldb       #SCG.CmdBlocks
                    os9       F$DelRAM
                    lbcs      SCG_FR_BAD
                    lda       <grSCFlags
                    anda      #^SCG.FlagRAMCmd
                    sta       <grSCFlags
SCG_FR_1            lda       <grSCFlags
                    bita      #SCG.FlagRAM1
                    lbeq      SCG_FR_0
                    ldx       <grSCFB1Start
                    ldb       #SCG.FBBlocks
                    os9       F$DelRAM
                    lbcs      SCG_FR_BAD
                    lda       <grSCFlags
                    anda      #^SCG.FlagRAM1
                    sta       <grSCFlags
SCG_FR_0            lda       <grSCFlags
                    bita      #SCG.FlagRAM0
                    lbeq      SCG_FR_DONE
                    ldx       <grSCFB0Start
                    ldb       #SCG.FBBlocks
                    os9       F$DelRAM
                    lbcs      SCG_FR_BAD
                    lda       <grSCFlags
                    anda      #^SCG.FlagRAM0
                    sta       <grSCFlags
SCG_FR_DONE         clrb
                    andcc     #^Carry
                    rts
SCG_FR_BAD          ldb       #E$NotRdy
                    orcc      #Carry
                    rts

********************************************************************
* Conservative complete teardown.
********************************************************************
SCG_CLEANUP         pshs      x,y
                    lbsr      SCG_DISABLE
                    lbcs      SCG_CL_BAD
                    lda       #SCG.FlagMBOCmd
                    ldb       #SCG.SlotCmd
                    lbsr      SCG_REVOKE_MBO
                    lbcs      SCG_CL_BAD
                    lda       #SCG.FlagMBO1
                    ldb       #SCG.SlotFB1
                    lbsr      SCG_REVOKE_MBO
                    lbcs      SCG_CL_BAD
                    lda       #SCG.FlagMBO0
                    ldb       #SCG.SlotFB0
                    lbsr      SCG_REVOKE_MBO
                    lbcs      SCG_CL_BAD
                    lbsr      SCG_FREE_RAM
                    lbcs      SCG_CL_BAD

                    ldx       <grSCScreenTbl
                    beq       SCG_CL_NO_TABLE
                    clr       St.SBlk,x
SCG_CL_NO_TABLE     clra
                    clrb
                    std       <grSCScreenTbl
                    std       <grSCFB0Start
                    std       <grSCFB1Start
                    std       <grSCCmdStart
                    std       <grSCGenCmd
                    std       <grSCGenCmd+2
                    sta       <grSCBack
                    sta       <grSCFlags
                    andcc     #^Carry
                    puls      x,y,pc
SCG_CL_BAD          orcc      #Carry
                    puls      x,y,pc

********************************************************************
* GrfDrv DWEnd hook.
********************************************************************
SCG_DWEND_ENTRY     lbsr      SCG_CLEANUP
                    lbcs      SCG_DWEND_BAD
                    ldd       #$FFFF
                    std       Wt.STbl,y
                    cmpy      <gr002E
                    lbne      SCG_DWEND_OK
                    clra
                    clrb
                    std       <gr002E
                    std       <gr0030
SCG_DWEND_OK        clrb
                    jmp       >GrfStrt+SysRet
SCG_DWEND_BAD       jmp       >GrfStrt+SysRet

********************************************************************
* Best-effort GrfDrv termination hook.  Never return physical RAM while an
* MBO or VIDEO consumer can still own it.
********************************************************************
SCG_TERM            lda       <grSCFlags
                    lbeq      SCG_TERM_DONE
                    lbsr      SCG_CLEANUP
                    rts
SCG_TERM_DONE       clrb
                    andcc     #^Carry
                    rts
