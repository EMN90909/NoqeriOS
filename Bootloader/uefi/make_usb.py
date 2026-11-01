#!/usr/bin/env python3
"""Make a removable-media UEFI GPT disk from the NoqeriOS FAT ESP.

No root, loop devices or external partitioning programs required.
Image layout: protective MBR, primary GPT, 1 MiB-aligned EFI system partition,
backup GPT. This is a disk image, not a UEFI boot test or hardware certification.
"""
from __future__ import annotations

import argparse
import hashlib
from pathlib import Path
import struct
import uuid
import zlib

SECTOR = 512
ESP_START = 2048
GPT_COUNT = 128
ENTRY_BYTES = 128
TABLE_BYTES = GPT_COUNT * ENTRY_BYTES
TABLE_SECTORS = TABLE_BYTES // SECTOR
ESP_TYPE = uuid.UUID("c12a7328-f81f-11d2-ba4b-00a0c93ec93b")


def _header(current: int, backup: int, first: int, last: int,
            disk_id: uuid.UUID, entries_lba: int, entries_crc: int) -> bytes:
    values = struct.pack(
        "<8sIIIIQQQQ16sQIII",
        b"EFI PART", 0x00010000, 92, 0, 0, current, backup,
        first, last, disk_id.bytes_le, entries_lba,
        GPT_COUNT, ENTRY_BYTES, entries_crc,
    )
    crc = zlib.crc32(values[:92])
    values = values[:16] + struct.pack("<I", crc) + values[20:]
    return values.ljust(SECTOR, b"\0")


def create_usb_image(esp: bytes) -> bytes:
    if len(esp) < 1024 * 1024 or len(esp) % SECTOR:
        raise ValueError("FAT ESP must be >=1 MiB and sector-aligned")
    esp_sectors = len(esp) // SECTOR
    total = ESP_START + esp_sectors + ESP_START
    backup = total - 1
    first_usable, last_usable = 34, backup - 33
    part_last = ESP_START + esp_sectors - 1
    if part_last > last_usable:
        raise ValueError("EFI system partition overlaps backup GPT")
    seed = hashlib.sha256(esp).hexdigest()
    disk_id = uuid.uuid5(uuid.NAMESPACE_URL, "noqerios-uefi-disk-" + seed)
    part_id = uuid.uuid5(disk_id, "esp")
    entries = bytearray(TABLE_BYTES)
    label = "NoqeriOS EFI".encode("utf-16le")
    entries[:56] = struct.pack(
        "<16s16sQQQ",
        ESP_TYPE.bytes_le, part_id.bytes_le, ESP_START, part_last, 0,
    )
    entries[56:56+len(label)] = label
    entries_crc = zlib.crc32(entries)
    image = bytearray(total * SECTOR)

    # Protective MBR. No active MBR partition: this is UEFI-only boot media.
    mbr = 446
    image[mbr+4] = 0xEE
    struct.pack_into("<II", image, mbr+8, 1, min(total-1, 0xFFFFFFFF))
    image[510:512] = b"\x55\xaa"

    image[SECTOR:SECTOR*2] = _header(
        1, backup, first_usable, last_usable, disk_id, 2, entries_crc
    )
    image[2*SECTOR:(2+TABLE_SECTORS)*SECTOR] = entries
    image[ESP_START*SECTOR:ESP_START*SECTOR+len(esp)] = esp

    backup_table = backup - TABLE_SECTORS
    image[backup_table*SECTOR:backup*SECTOR] = entries
    image[backup*SECTOR:(backup+1)*SECTOR] = _header(
        backup, 1, first_usable, last_usable, disk_id,
        backup_table, entries_crc,
    )
    return bytes(image)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("esp", type=Path, help="FAT EFI system partition image")
    parser.add_argument("output", type=Path, help="UEFI removable media GPT image")
    args = parser.parse_args()
    image = create_usb_image(args.esp.read_bytes())
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_bytes(image)
    print(f"NoqeriOS UEFI GPT USB image: {args.output} ({len(image)} bytes)")


if __name__ == "__main__":
    main()
