                    IFNE      SUPERCOCO.D-1
SUPERCOCO.D         set       1

********************************************************************
* SuperCoCo Native Network v0.1 definitions
*
* Guest-visible hardware ABI plus the feature-owned NitrOS-9 control ABI.
* Provisional SuperCoCo status codes intentionally live here rather than in
* the shared os9.d namespace.
********************************************************************

* NitrOS-9 GetStat/SetStat codes.
SS.NetCn            equ       $B1                 SetStat connection request
SS.NetSt            equ       $B2                 GetStat network snapshot

* Register offsets from V.PORT ($FF70).
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

* Capability bits.
NET_CAP_TCP         equ       %00000001
NET_CAP_HOSTNAME    equ       %00000010
NET_CAP_IRQ         equ       %00000100

* Status bits.
NET_ST_LINK_UP      equ       %00000001
NET_ST_CONNECTING   equ       %00000010
NET_ST_CONNECTED    equ       %00000100
NET_ST_RX_READY     equ       %00001000
NET_ST_TX_READY     equ       %00010000
NET_ST_CMD_BUSY     equ       %00100000
NET_ST_ERROR        equ       %01000000

* Commands.
NET_CMD_RESET       equ       $01
NET_CMD_CONNECT     equ       $10
NET_CMD_CLOSE       equ       $11

* Results.
NET_RES_OK          equ       $00
NET_RES_BAD_CMD     equ       $01
NET_RES_BAD_STATE   equ       $02
NET_RES_NO_LINK     equ       $03
NET_RES_BAD_ARG     equ       $04
NET_RES_DNS_FAIL    equ       $05
NET_RES_CONN_FAIL   equ       $06
NET_RES_REMOTE_CLOSE equ      $07
NET_RES_TX_OVERFLOW equ       $08
NET_RES_BACKEND     equ       $09

* IRQ/event bits.
NET_IRQ_RX_READY    equ       %00000001
NET_IRQ_CONNECT     equ       %00000010
NET_IRQ_CLOSED      equ       %00000100
NET_IRQ_ERROR       equ       %00001000
NET_IRQ_TX_READY    equ       %00010000

********************************************************************
* SS.NetCn v1 request
*
* R$X = caller-buffer pointer
* R$Y = full caller-buffer size
*
*   +0  version ($01)
*   +1  hostname length (1..255)
*   +2  destination port, big-endian
*   +4  hostname bytes, no trailing NUL
********************************************************************
NETCN_VERSION       equ       $01
NETCN_O_VERSION     equ       0
NETCN_O_HOSTLEN     equ       1
NETCN_O_PORT        equ       2
NETCN_O_HOST        equ       4
NETCN_FIXED_SIZE    equ       4
NETCN_MAX_HOST      equ       255
NETCN_MAX_SIZE      equ       NETCN_FIXED_SIZE+NETCN_MAX_HOST

********************************************************************
* SS.NetSt v1 response
*
* R$X = caller-buffer pointer
* R$Y = caller-buffer capacity; must be at least NETST_SIZE
********************************************************************
NETST_VERSION       equ       $01
NETST_O_VERSION     equ       0
NETST_O_ABI         equ       1
NETST_O_CAPS        equ       2
NETST_O_STATUS      equ       3
NETST_O_RESULT      equ       4
NETST_O_IRQ         equ       5
NETST_O_RX_COUNT    equ       6
NETST_O_TX_SPACE    equ       7
NETST_SIZE          equ       8

********************************************************************
* SuperCoCo Community Alpha NG service ABI definitions
*
* Frozen executable architecture through ARCH0-R1L.  These constants are
* additive to Native Network v0.1 above.  Guest software must still discover
* capabilities before using a service page.
********************************************************************

* Invariant outer service portal.
SC.SvcAddrLo         equ       $FF88
SC.SvcAddrHi         equ       $FF89
SC.SvcWData          equ       $FF8A
SC.SvcCommand        equ       $FF8B
SC.SvcStatus         equ       $FF8C
SC.SvcRData          equ       $FF8D
SC.SvcIRQStatus      equ       $FF8E
SC.SvcIRQMask        equ       $FF8F

SC.SvcRead           equ       $01
SC.SvcWrite          equ       $02
SC.SvcDone           equ       $02
SC.SvcError          equ       $04

* R1G unified service-event bits.
SC.IRQTask0          equ       $01
SC.IRQTask1          equ       $02
SC.IRQMedia          equ       $04
SC.IRQVideo          equ       $08
SC.IRQAudio          equ       $10
SC.IRQSystem         equ       $20
SC.IRQImplemented    equ       $3F

* Global system discovery.
SC.SysMagic0         equ       $0000
SC.SysMagic1         equ       $0001
SC.SysABIMajor       equ       $0002
SC.SysABIMinor       equ       $0003
SC.SysCaps0          equ       $0004
SC.SysCaps1          equ       $000B

SC.CapCoreFabric     equ       $04
SC.CapJobV1          equ       $08
SC.CapGrantV1        equ       $10
SC.CapMBOV1          equ       $20
SC.CapVideoV1        equ       $40
SC.CapGraphicsV1     equ       $80
SC.Cap1AudioV1       equ       $01

* R1I Media Buffer Object V1 discovery and object geometry.
SC.MBODiscBase       equ       $0600
SC.MBOABIMajor       equ       SC.MBODiscBase+$00
SC.MBOABIMinor       equ       SC.MBODiscBase+$01
SC.MBOCaps0          equ       SC.MBODiscBase+$02
SC.MBOSlotCount      equ       SC.MBODiscBase+$03
SC.MBOMaxPages       equ       SC.MBODiscBase+$04
SC.MBOPageShift      equ       SC.MBODiscBase+$05
SC.MBOStrideShift    equ       SC.MBODiscBase+$06
SC.MBOConsumerMask   equ       SC.MBODiscBase+$07
SC.MBOPermissionMask equ       SC.MBODiscBase+$08
SC.MBOPageListOffset equ       SC.MBODiscBase+$09
SC.MBOPageEntrySize  equ       SC.MBODiscBase+$0A
SC.MBOObjectBaseLo   equ       SC.MBODiscBase+$0B
SC.MBOObjectBaseHi   equ       SC.MBODiscBase+$0C

SC.MBOObjectBase     equ       $0800
SC.MBOObjectStride   equ       $0200
SC.MBOStatusO        equ       $00
SC.MBOControlO       equ       $01
SC.MBOPermissionsO   equ       $02
SC.MBOConsumersO     equ       $03
SC.MBOGenerationO    equ       $04
SC.MBOLengthO        equ       $08
SC.MBOPageCountO     equ       $0C
SC.MBOPageListO      equ       $40
SC.MBOStatusValid    equ       $01
SC.MBOStatusBusy     equ       $02
SC.MBOCtlCommit      equ       $01
SC.MBOCtlRevoke      equ       $02
SC.MBOPermRead       equ       $01
SC.MBOPermWrite      equ       $02
SC.MBOConsumerVideo  equ       $01
SC.MBOConsumerMedia  equ       $02
SC.MBOConsumerAudio  equ       $04

* R1J GIME-NG Display V1.
SC.VideoBase         equ       $2800
SC.VideoABIMajor     equ       SC.VideoBase+$00
SC.VideoABIMinor     equ       SC.VideoBase+$01
SC.VideoCaps0        equ       SC.VideoBase+$02
SC.VideoFormat       equ       SC.VideoBase+$03
SC.VideoWidthLo      equ       SC.VideoBase+$04
SC.VideoWidthHi      equ       SC.VideoBase+$05
SC.VideoHeightLo     equ       SC.VideoBase+$06
SC.VideoHeightHi     equ       SC.VideoBase+$07
SC.VideoStrideLo     equ       SC.VideoBase+$08
SC.VideoStrideHi     equ       SC.VideoBase+$09
SC.VideoPaletteCount equ       SC.VideoBase+$0A
SC.VideoSurfaceCount equ       SC.VideoBase+$0B
SC.VideoStatus       equ       SC.VideoBase+$0C
SC.VideoControl      equ       SC.VideoBase+$0D
SC.VideoStageEnable  equ       SC.VideoBase+$0E
SC.VideoStageSurface equ       SC.VideoBase+$0F
SC.VideoActiveSurface equ      SC.VideoBase+$10
SC.VideoError        equ       SC.VideoBase+$11
SC.VideoVBlankSeqLo  equ       SC.VideoBase+$12
SC.VideoVBlankSeqHi  equ       SC.VideoBase+$13
SC.VideoSurface0     equ       SC.VideoBase+$20
SC.VideoSurface1     equ       SC.VideoBase+$30
SC.VideoPalette      equ       SC.VideoBase+$40
SC.VideoCtlCommit    equ       $01
SC.VideoCtlClearErr  equ       $02
SC.VideoFmtIndex4    equ       $01
SC.VideoStatusActive equ       $01
SC.VideoStatusPending equ      $02
SC.VideoStatusError  equ       $04

* R1K MEDIA Graphics Services V1 discovery and command geometry.
SC.GraphicsBase      equ       $2900
SC.GraphicsABIMajor  equ       SC.GraphicsBase+$00
SC.GraphicsABIMinor  equ       SC.GraphicsBase+$01
SC.GraphicsCaps0     equ       SC.GraphicsBase+$02
SC.GraphicsMediaSlot equ       SC.GraphicsBase+$03
SC.GraphicsJobOpcode equ       SC.GraphicsBase+$04
SC.GraphicsCmdSize   equ       SC.GraphicsBase+$05
SC.GraphicsAlignShift equ      SC.GraphicsBase+$06
SC.GraphicsFormat    equ       SC.GraphicsBase+$07
SC.GraphicsMaxWLo    equ       SC.GraphicsBase+$08
SC.GraphicsMaxWHi    equ       SC.GraphicsBase+$09
SC.GraphicsMaxHLo    equ       SC.GraphicsBase+$0A
SC.GraphicsMaxHHi    equ       SC.GraphicsBase+$0B
SC.GraphicsOpcode    equ       $10
SC.GraphicsFmtIndex4 equ       $01
SC.GraphicsOpFill    equ       $01
SC.GraphicsOpBlit    equ       $02
SC.GraphicsOpMasked  equ       $03

* MEDIA Job V1 channel used by R1K.
SC.MediaJobBase      equ       $02C0
SC.JobStateO         equ       $04
SC.JobErrorO         equ       $05
SC.JobResultO        equ       $06
SC.JobControlO       equ       $07
SC.JobOpcodeO        equ       $10
SC.JobFlagsO         equ       $11
SC.JobTagLoO         equ       $12
SC.JobTagHiO         equ       $13
SC.JobArg0LoO        equ       $14
SC.JobArg0HiO        equ       $15
SC.JobArg1LoO        equ       $16
SC.JobArg1HiO        equ       $17
SC.JobArg2LoO        equ       $18
SC.JobArg2HiO        equ       $19
SC.JobArg3LoO        equ       $1A
SC.JobArg3HiO        equ       $1B
SC.JobBuf0O          equ       $1C
SC.JobBufEndO        equ       $27
SC.JobCtlSubmit      equ       $01
SC.JobCtlAck         equ       $02
SC.JobIdle           equ       $00
SC.JobPending        equ       $01
SC.JobBusy           equ       $02
SC.JobComplete       equ       $03
SC.JobErrorState     equ       $04

* R1K 64-byte Graphics Command V1 record.
SC.GfxCmdABIMajorO   equ       $00
SC.GfxCmdABIMinorO   equ       $01
SC.GfxCmdOperationO  equ       $02
SC.GfxCmdFlagsO      equ       $03
SC.GfxCmdColorO      equ       $04
SC.GfxCmdSourceO     equ       $08
SC.GfxCmdDestO       equ       $18
SC.GfxCmdSrcXO       equ       $28
SC.GfxCmdSrcYO       equ       $2A
SC.GfxCmdDstXO       equ       $2C
SC.GfxCmdDstYO       equ       $2E
SC.GfxCmdWidthO      equ       $30
SC.GfxCmdHeightO     equ       $32

* R1L Audio V1 global page and stream layout.
SC.AudioBase         equ       $2A00
SC.AudioABIMajor     equ       SC.AudioBase+$00
SC.AudioABIMinor     equ       SC.AudioBase+$01
SC.AudioCaps0        equ       SC.AudioBase+$02
SC.AudioStreamCount  equ       SC.AudioBase+$03
SC.AudioFormat       equ       SC.AudioBase+$04
SC.AudioFrameBytes   equ       SC.AudioBase+$05
SC.AudioFIFOMin      equ       SC.AudioBase+$06
SC.AudioStrideShift  equ       SC.AudioBase+$07
SC.AudioRate0        equ       SC.AudioBase+$08
SC.AudioRate1        equ       SC.AudioBase+$09
SC.AudioRate2        equ       SC.AudioBase+$0A
SC.AudioRate3        equ       SC.AudioBase+$0B
SC.AudioStreamBaseLo equ       SC.AudioBase+$0C
SC.AudioStreamBaseHi equ       SC.AudioBase+$0D
SC.AudioMasterGainL  equ       SC.AudioBase+$10
SC.AudioMasterGainR  equ       SC.AudioBase+$11
SC.AudioActiveMaskLo equ       SC.AudioBase+$12
SC.AudioActiveMaskHi equ       SC.AudioBase+$13

SC.AudioStreamBase   equ       $2B00
SC.AudioStreamStride equ       $0040
SC.AudioStrStatusO   equ       $00
SC.AudioStrControlO  equ       $01
SC.AudioStrEventStatusO equ    $02
SC.AudioStrEventMaskO equ      $03
SC.AudioStrMBOSlotO  equ       $04
SC.AudioStrFormatO   equ       $05
SC.AudioStrGenerationO equ     $06
SC.AudioStrOffsetO   equ       $0A
SC.AudioStrRingFramesO equ     $0E
SC.AudioStrProdStageO equ      $12
SC.AudioStrProdActiveO equ     $16
SC.AudioStrConsumerO equ       $1A
SC.AudioStrAvailableO equ      $1E
SC.AudioStrUnderrunO equ       $22
SC.AudioStrLowWaterO equ       $26
SC.AudioStrGainLO    equ       $28
SC.AudioStrGainRO    equ       $29
SC.AudioStrFIFOLevelO equ      $2A
SC.AudioStrRunning   equ       $01
SC.AudioStrLow       equ       $02
SC.AudioStrUnderrun  equ       $04
SC.AudioStrStale     equ       $08
SC.AudioEvLow        equ       $01
SC.AudioEvUnderrun   equ       $02
SC.AudioEvStale      equ       $04
SC.AudioCtlStart     equ       $01
SC.AudioCtlStop      equ       $02
SC.AudioCtlProdCommit equ      $04
SC.AudioFmtS16LEStereo equ     $01

                    ENDC
