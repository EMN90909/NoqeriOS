# NoqeriOS Explorer (Windows 11-inspired, experimental)

The NoqeriOS framebuffer compositor displays a light-themed File Explorer,
with a sidebar, root location, file list and highlighted selection. It is
**not** Microsoft File Explorer and uses only NoqeriOS code.

## Keyboard controls

- `F` opens/closes Explorer (from the GUI or COM1).
- `J` and `K` move down/up through entries in the current directory.
- `E` / Enter opens the selected folder.
- `B` / Backspace navigates up.
- Other keys remain available for the existing desktop navigation.

A GUI-capable boot needs a 32-bit UEFI GOP framebuffer and PS/2 keyboard or
COM1. No native USB HID pointer is implemented. The file list is read-only:
rename/delete/move/copy and writing are intentionally unavailable.

## NoqFS format

Legacy **NoqFS v1** volumes remain readable. Their 32-byte directory records
contain only numeric file keys, sector, size and flags. They cannot supply
names or a directory hierarchy.

**NoqFS v2** changes only the superblock version to 2, and uses 64-byte
directory records with the following little-endian layout:

| Offset | Width | Field |
|---|---:|---|
| 0 | 8 | Unique nonzero key |
| 8 | 8 | First data sector |
| 16 | 8 | Size in bytes |
| 24 | 4 | Flags: 1=file, 2=directory |
| 28 | 4 | UTF-8 name length (1–24 bytes) |
| 32 | 8 | Parent key (0=root) |
| 40 | 24 | Filename bytes, padded with zeroes |

Superblock (sector 0) retains the v1 fields: `NQFS`, version, root
directory sector, entry count, sector size 512. Entries are an indexed flat
directory table, 8 entries per sector. Folder navigation filters entries
on parent key. It does not yet implement symlinks, long filenames, nested
directory tables, or filesystem mutation.

The GUI caps enumeration at 128 entries and displays up to seven rows
without scrolling. The mini bitmap font has limited glyph coverage, so
lowercase ASCII names render uppercase; unsupported characters may not draw.
Names are real volume metadata, not invented Windows user folders.

## Testing

Run `python3 Tests/gui-smoke.py` after building the UEFI ISO. The test
creates a read-only v2 disk with HELLO.TXT and DOCUMENTS/README.TXT,
boots QEMU OVMF, opens Explorer with `F`, moves the selection with `J`,
and compares real framebuffer screenshots. Existing NoqFS v1 kernel tests
continue to run independently.

### Important limitations

This is an early native application within the single-process compositor,
not a privileged Windows file manager. NoqFS currently has no safe
filesystem write/journaling layer, and NoqeriOS only recognizes its
experimental VirtIO block device. Running it on a physical Windows
partition cannot browse NTFS or exFAT files. Do not expect access to
host Linux/Windows files or attach production disks.
