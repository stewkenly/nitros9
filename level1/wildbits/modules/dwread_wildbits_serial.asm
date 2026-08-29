*******************************************************
*
* DWRead
*    Receive a response from the DriveWire server.
*    Times out if serial port goes idle for more than 1.4 (0.7) seconds.
*    Serial data format:  1-8-N-1
*
* Entry:
*    X  = starting address where data is to be stored
*    Y  = number of bytes expected
*
* Exit:
*    CC = carry set on framing error, Z set if all bytes received
*    X  = starting address of data received
*    Y  = checksum
*    U is preserved.  All accumulators are clobbered
*

DWRead              clra                          clear carry (no framing error)
                    clrb
                    pshs      u,x,d,cc            preserve registers
                    orcc      #IntMasks           mask interrupts
                    leau      ,x
                    ldx       #$0000
loop@               ldd       #$0000              store counter
                    std       1,s
loop2@              lda       UART.Base+UART_LSR  get the LSR register value
                    bita      #LSR_DATA_AVAIL     test for data available
                    bne       getbyte@            if available, get byte
                    ldd       1,s
                    addb      #$01
                    adca      #$00
                    std       1,s
                    cmpd      #$0000
                    bne       loop2@
                    lda       ,s                  get CC off stack
                    anda      #^$04               clear the Z flag to indicate not all bytes received.
                    sta       ,s
* RX resync purge (2026-08-28): after a timeout, the server's remaining
* bytes may still arrive and sit in the 16-byte FIFO, poisoning the NEXT
* transaction (the cascading-#244 pattern). Drain the FIFO and any late
* stragglers until the line has been idle for 10+ character times.
* Bounded (max ~1200 discards); IRQs are still masked here; X is
* restored from the stack at exit so it is free to use.
                    ldy       #1200               max stale bytes to discard
prg0@               ldx       #256                idle window, ~0.5ms (>10 char times at 230400)
prg1@               lda       UART.Base+UART_LSR
                    bita      #LSR_DATA_AVAIL
                    bne       prg2@               late byte - discard it, restart idle window
                    leax      -1,x
                    bne       prg1@
                    bra       bye@                line went idle - resync complete
prg2@               lda       UART.Base+UART_TRHB discard stale byte
                    leay      -1,y
                    bne       prg0@
                    bra       bye@                discard cap hit - stop draining
getbyte@            ldb       UART.Base+UART_TRHB get the data byte
                    stb       ,u+                 save off acquired byte
                    abx                           update checksum
                    leay      ,-y                 decrement Y
                    bne       loop@               branch if more to obtain
                    leay      ,x                  return checksum in Y
bye@                puls      cc,d,x,u,pc         restore registers and return
