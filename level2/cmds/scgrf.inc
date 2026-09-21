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

********************************************************************
* Initialize private state.  Called only on the first GrfDrv init.
********************************************************************
SCG_INIT            clra
                    sta       <grSCFlags
                    sta       <grSCBack
                    std       <grSCScreenTbl
                    std       <grSCFB0Start
                    std       <grSCFB1Start
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

                    lbsr      SCG_ALLOCATE
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
                    clrb
                    andcc     #^Carry
                    rts
SCG_ALLOC_BAD       orcc      #Carry
                    rts

********************************************************************
* Entry D = first 8K physical block.  Clear all 19 owned blocks before they
* become visible to VIDEO or writable by MEDIA.
********************************************************************
SCG_CLEAR_FB        pshs      y,u
                    std       <grSCCurrentBlock
                    lda       #SCG.FBBlocks
                    sta       <grSCBlocksLeft
SCG_CF_BLOCK        ldx       <grSCCurrentBlock
                    ldb       #1
                    pshs      u
                    os9       F$MapBlk
                    lbcs      SCG_CF_MAP_BAD
                    tfr       u,x
                    puls      u
                    stx       <grSCMapAddr
                    ldy       #SCG.FBBytes
                    clra
SCG_CF_BYTE         sta       ,x+
                    leay      -1,y
                    lbne      SCG_CF_BYTE

                    pshs      u
                    ldu       <grSCMapAddr
                    ldb       #1
                    os9       F$ClrBlk
                    lbcs      SCG_CF_UNMAP_BAD
                    puls      u

                    ldd       <grSCCurrentBlock
                    addd      #1
                    std       <grSCCurrentBlock
                    dec       <grSCBlocksLeft
                    lbne      SCG_CF_BLOCK
                    clrb
                    andcc     #^Carry
                    puls      y,u,pc
SCG_CF_MAP_BAD      puls      u
                    orcc      #Carry
                    puls      y,u,pc
SCG_CF_UNMAP_BAD    puls      u
                    orcc      #Carry
                    puls      y,u,pc

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
                    bita      #SCG.FlagMBO0!SCG.FlagMBO1!SCG.FlagVideo
                    lbne      SCG_FR_BAD
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
