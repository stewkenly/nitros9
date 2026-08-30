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

                    ENDC
