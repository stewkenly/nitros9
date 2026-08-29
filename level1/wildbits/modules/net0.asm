********************************************************************
* net0 - SuperCoCo Native Network v0.1 SCF device descriptor
********************************************************************

                    ifp1
                    use       defsfile
                    endc

rev                 set       $01
tylg                set       Devic+Objct
atrv                set       ReEnt+rev

Base                set       $FF70

                    mod       eom,name,tylg,atrv,mgrnam,drvnam

                    fcb       UPDAT.              read/write
                    fcb       HW.Page             extended controller address
                    fdb       Base                SuperCoCo native network register base
                    fcb       initsize-*-1
                    fcb       DT.SCF
                    fcb       $00                 upper/lower case
                    fcb       $01                 backspace style
                    fcb       $00                 delete style
                    fcb       $00                 local echo off
                    fcb       $00                 auto line feed off
                    fcb       $00                 end-of-line null count
                    fcb       $00                 end-of-page pause off
                    fcb       24                  nominal rows
                    fcb       C$BSP
                    fcb       C$DEL
                    fcb       C$CR
                    fcb       C$EOF
                    fcb       C$RPRT
                    fcb       C$RPET
                    fcb       C$PAUS
                    fcb       C$INTR
                    fcb       C$QUIT
                    fcb       C$BSP
                    fcb       C$BELL
                    fcb       PARNONE
                    fcb       STOP1+WORD8         transport format is not UART-configurable
                    fdb       name
                    fcb       $00                 XON unused
                    fcb       $00                 XOFF unused
                    fcb       80                  nominal columns
                    fcb       24                  nominal rows
                    fcb       $00                 extended type
initsize            equ       *

name                fcs       /net0/
mgrnam              fcs       /scf/
drvnam              fcs       /scnet/

                    emod
eom                 equ       *
                    end
