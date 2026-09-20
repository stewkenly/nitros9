# SuperCoCo NitrOS-9 S2A-4: concurrent graphics + audio

S2A-4 keeps the proven S2A-3 R1K animation active while R1L stream 0 consumes
real 48 kHz signed-16-bit little-endian stereo PCM from an independent MBO.
The goal is not merely to show two features independently: the same NitrOS-9
process must maintain VIDEO, MEDIA, and AUDIO ownership at the same time.

## Ownership model

Five independent MBOs are used:

- MBO0: 153,600-byte framebuffer A, VIDEO|MEDIA, READ|WRITE;
- MBO1: 153,600-byte framebuffer B, VIDEO|MEDIA, READ|WRITE;
- MBO2: one-page R1K command backing, MEDIA READ;
- MBO3: one-page tile/sprite source backing, MEDIA READ;
- MBO4: 131,072-byte PCM ring, AUDIO READ.

MAIN never maps framebuffer pixel memory. MEDIA remains the sole framebuffer
writer, while GIME-NG is the display reader. MAIN maps MBO4 backing only during
initial PCM generation, before the audio stream starts.

## Audio workload

MBO4 contains 32,768 stereo frames. At 48 kHz that is about 683 ms of ring
capacity. The ring is filled with a periodic 64-frame square wave (750 Hz):
left amplitude +/-$1800 and right amplitude +/-$1000.

Because the intended waveform repeats exactly at the ring boundary, consumed
slots do not need to be rewritten. Every 16,384 consumed frames, MAIN advances
PRODUCER_STAGE by one half-ring and issues `PROD_COMMIT`. This is a deliberate
ownership proof: a slot is republished only after CONSUMER_SEQ has returned it
to the producer.

The demo uses full 32-bit producer/consumer sequence tracking. It snapshots any
startup underrun count only after real PCM progress begins and requires that no
additional underrun frames occur during the concurrent workload.

## Concurrent workload

For 120 VBLANK-safe frames, `scavdemo` simultaneously performs:

1. R1K FILL of the two animated background bands;
2. R1K BLIT of the moving opaque tile;
3. R1K MASKED BLIT of the transparent sprite;
4. R1J atomic front/back surface flip;
5. R1L producer servicing as half-ring ownership returns.

The final proof requires at least four successful half-ring producer commits,
a still-running/non-stale stream, unchanged post-startup underrun count, and
clean drain of AUDIO, VIDEO, and MEDIA ownership before backing RAM is freed.

## Interactive test

After publication on Venus:

```sh
cd /Volumes/design/nitros9
scripts/prepare-supercoco-s2a4.sh
```

This creates:

```text
/Volumes/design/_transfer/63SDC-S2A4.VHD
```

Copy that VHD to StewsPC, boot it with the current SuperCoCo XRoar R1L build,
and run:

```text
scavdemo
```

Expected result: the S2A-3 accelerated animation remains visible while a stereo
square-wave tone plays, followed by:

```text
SuperCoCo S2A VIDEO+MEDIA+AUDIO PASS
```

## Next milestone

With graphics and audio operating concurrently, the next visible integration
milestone is native networking: drive the already-present SuperCoCo host TCP
backend from NitrOS-9 and prove real bidirectional traffic without NetUART.
