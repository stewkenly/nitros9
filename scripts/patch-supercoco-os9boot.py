#!/usr/bin/env python3
from __future__ import annotations

import argparse
import math
import struct
from pathlib import Path

SECTOR = 256
OS9_SYNC = b"\x87\xcd"


def be16(b: bytes) -> int:
    return int.from_bytes(b, "big")


def be24(b: bytes) -> int:
    return int.from_bytes(b, "big")


def be32(b: bytes) -> int:
    return int.from_bytes(b, "big")


def put_be16(buf: bytearray, off: int, value: int) -> None:
    buf[off:off + 2] = value.to_bytes(2, "big")


def put_be32(buf: bytearray, off: int, value: int) -> None:
    buf[off:off + 4] = value.to_bytes(4, "big")


def decode_os9_name(raw: bytes) -> str:
    out = bytearray()
    for c in raw:
        if c == 0:
            break
        out.append(c & 0x7f)
        if c & 0x80:
            break
    return out.decode("latin-1")


def iter_modules(blob: bytes):
    off = 0
    while off < len(blob):
        if len(blob) - off < 9:
            raise RuntimeError(f"truncated OS-9 module header at offset {off}")
        if blob[off:off + 2] != OS9_SYNC:
            raise RuntimeError(f"bad OS-9 module sync at offset {off:#x}")
        size = be16(blob[off + 2:off + 4])
        name_off = be16(blob[off + 4:off + 6])
        if size < 9 or off + size > len(blob):
            raise RuntimeError(f"invalid OS-9 module size {size} at offset {off:#x}")
        if name_off >= size:
            raise RuntimeError(f"invalid OS-9 module name offset at {off:#x}")
        module = blob[off:off + size]
        name = decode_os9_name(module[name_off:])
        yield off, size, name, module
        off += size
    if off != len(blob):
        raise RuntimeError("OS9Boot module stream did not terminate exactly at EOF")


def replace_module(old_boot: bytes, replacement: bytes, wanted: str) -> tuple[bytes, int, int]:
    reps = list(iter_modules(replacement))
    if len(reps) != 1:
        raise RuntimeError(f"replacement must contain exactly one OS-9 module, found {len(reps)}")
    _, rep_size, rep_name, rep_blob = reps[0]
    if rep_name.lower() != wanted.lower():
        raise RuntimeError(f"replacement module is {rep_name!r}, expected {wanted!r}")

    out = bytearray()
    found = 0
    old_size = 0
    for _, size, name, module in iter_modules(old_boot):
        if name.lower() == wanted.lower():
            found += 1
            old_size = size
            out += rep_blob
        else:
            out += module
    if found != 1:
        raise RuntimeError(f"expected exactly one {wanted} module in OS9Boot, found {found}")
    return bytes(out), old_size, rep_size


def read_sector(image: bytearray, lsn: int) -> bytes:
    off = lsn * SECTOR
    end = off + SECTOR
    if end > len(image):
        raise RuntimeError(f"LSN {lsn} lies outside image")
    return bytes(image[off:end])


def fd_segments(fd: bytes):
    for off in range(16, 256, 5):
        lsn = be24(fd[off:off + 3])
        count = be16(fd[off + 3:off + 5])
        if lsn == 0 or count == 0:
            break
        yield lsn, count


def read_fd_file(image: bytearray, fd_lsn: int) -> tuple[bytes, bytes, list[tuple[int, int]]]:
    fd = read_sector(image, fd_lsn)
    size = be32(fd[9:13])
    segs = list(fd_segments(fd))
    data = bytearray()
    for lsn, count in segs:
        off = lsn * SECTOR
        end = off + count * SECTOR
        if end > len(image):
            raise RuntimeError(f"FD {fd_lsn} segment {lsn}+{count} exceeds image")
        data += image[off:end]
    if size > len(data):
        raise RuntimeError(f"FD {fd_lsn} size {size} exceeds segment capacity {len(data)}")
    return bytes(data[:size]), fd, segs


def find_root_entry(image: bytearray, root_fd_lsn: int, wanted: str) -> int:
    data, _, _ = read_fd_file(image, root_fd_lsn)
    for off in range(0, len(data) - 31, 32):
        ent = data[off:off + 32]
        if ent[0] == 0:
            continue
        name = decode_os9_name(ent[:29])
        if name.lower() == wanted.lower():
            return be24(ent[29:32])
    raise RuntimeError(f"root directory does not contain {wanted}")


def main() -> int:
    ap = argparse.ArgumentParser(description="Patch CoWin inside an existing contiguous OS9Boot without reallocating it")
    ap.add_argument("image", type=Path)
    ap.add_argument("cowin", type=Path)
    args = ap.parse_args()

    image = bytearray(args.image.read_bytes())
    cowin = args.cowin.read_bytes()
    if len(image) < SECTOR:
        raise RuntimeError("image is too small to contain OS-9 LSN0")

    lsn0 = bytearray(image[:SECTOR])
    total_sectors = be24(lsn0[0:3])
    root_fd_lsn = be24(lsn0[8:11])
    boot_data_lsn = be24(lsn0[21:24])
    boot_size = be16(lsn0[24:26])

    if boot_size == 0:
        raise RuntimeError("base image already uses extended/fragmented boot; expected contiguous OS9Boot")
    if boot_data_lsn == 0:
        raise RuntimeError("base image has no contiguous OS9Boot LSN")
    if total_sectors * SECTOR > len(image):
        raise RuntimeError("LSN0 total-sector count exceeds image length")

    boot_fd_lsn = find_root_entry(image, root_fd_lsn, "OS9Boot")
    old_boot, boot_fd, segs = read_fd_file(image, boot_fd_lsn)
    if len(segs) != 1:
        raise RuntimeError(f"base OS9Boot is not single-segment: {segs}")
    seg_lsn, seg_count = segs[0]
    if seg_lsn != boot_data_lsn:
        raise RuntimeError(
            f"LSN0 boot data LSN {boot_data_lsn} does not match OS9Boot segment LSN {seg_lsn}"
        )
    if len(old_boot) != boot_size:
        raise RuntimeError(
            f"LSN0 boot size {boot_size} does not match OS9Boot FD size {len(old_boot)}"
        )

    new_boot, old_cowin_size, new_cowin_size = replace_module(old_boot, cowin, "CoWin")
    capacity = seg_count * SECTOR
    if len(new_boot) > capacity:
        raise RuntimeError(
            f"candidate OS9Boot grew from {len(old_boot)} to {len(new_boot)} bytes, "
            f"exceeding existing {capacity}-byte contiguous allocation"
        )
    sectors_needed = math.ceil(len(new_boot) / SECTOR)
    allocation_end_lsn = boot_data_lsn + seg_count - 1
    candidate_end_lsn = boot_data_lsn + sectors_needed - 1

    # Overwrite the existing data extent in place. Do not touch allocation bits,
    # directory entries, kernel track, or any module other than CoWin.
    data_off = boot_data_lsn * SECTOR
    image[data_off:data_off + len(new_boot)] = new_boot
    if len(new_boot) < capacity:
        image[data_off + len(new_boot):data_off + capacity] = b"\x00" * (capacity - len(new_boot))

    # Update OS9Boot FD size and the contiguous-boot byte count in LSN0.
    boot_fd_off = boot_fd_lsn * SECTOR
    put_be32(image, boot_fd_off + 9, len(new_boot))
    put_be16(image, 24, len(new_boot))

    args.image.write_bytes(image)

    print(f"PASS: patched CoWin in existing contiguous OS9Boot")
    print(f"OS9Boot FD LSN:     {boot_fd_lsn}")
    print(f"OS9Boot data LSN:   {boot_data_lsn}")
    print(f"OS9Boot allocation: {capacity} bytes ({seg_count} sectors)")
    print(f"OS9Boot size:       {len(old_boot)} -> {len(new_boot)} bytes")
    print(f"CoWin size:         {old_cowin_size} -> {new_cowin_size} bytes")
    print(f"OS9Boot allocation LSNs: {boot_data_lsn}..{allocation_end_lsn}")
    print(f"Candidate data LSNs:    {boot_data_lsn}..{candidate_end_lsn}")
    print("Boot location preserved exactly from the known-good base image")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
