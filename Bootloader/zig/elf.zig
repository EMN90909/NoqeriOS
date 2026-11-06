// Zig bootloader core: bounds-checked ELF64 validation before firmware
// allocation and copying. Freestanding; no allocator, libc or kernel ABI.
// This deliberately checks the same low-1GiB load contract as UEFI loader.c.
// Stage-0 BIOS real mode and firmware service adapters remain assembly/C
// until their boot paths are individually migrated and verified.
const elf_header_size: usize = 64;
const ph_size: usize = 56;
const max_phdr: usize = 128;
const max_image: usize = 512 * 1024;
const address_limit: u64 = 0x4000_0000;

fn u16le(bytes: []const u8, at: usize) u16 {
    return @as(u16, bytes[at]) | (@as(u16, bytes[at + 1]) << 8);
}
fn u32le(bytes: []const u8, at: usize) u32 {
    return @as(u32, bytes[at]) | (@as(u32, bytes[at + 1]) << 8) |
        (@as(u32, bytes[at + 2]) << 16) | (@as(u32, bytes[at + 3]) << 24);
}
fn u64le(bytes: []const u8, at: usize) u64 {
    return @as(u64, u32le(bytes, at)) | (@as(u64, u32le(bytes, at + 4)) << 32);
}
fn within(start: u64, length: u64, limit: u64) bool {
    return start <= limit and length <= limit - start;
}

pub fn validateElf(file: []const u8) bool {
    if (file.len < elf_header_size or file.len > max_image) return false;
    if (file[0] != 0x7f or file[1] != 'E' or file[2] != 'L' or file[3] != 'F') return false;
    if (file[4] != 2 or file[5] != 1 or file[6] != 1) return false;
    if (u16le(file, 16) != 2 or u16le(file, 18) != 62) return false;
    const phoff = u64le(file, 32);
    const phentsize = u16le(file, 54);
    const phnum = u16le(file, 56);
    if (phentsize != ph_size or phnum == 0 or phnum > max_phdr) return false;
    if (!within(phoff, @as(u64, phnum) * ph_size, @intCast(file.len))) return false;

    var found_load = false;
    for (0..@as(usize, phnum)) |i| {
        const pos: usize = @intCast(phoff + i * ph_size);
        if (u32le(file, pos) != 1) continue;
        found_load = true;
        const offset = u64le(file, pos + 8);
        const vaddr = u64le(file, pos + 16);
        const paddr = u64le(file, pos + 24);
        const filesz = u64le(file, pos + 32);
        const memsz = u64le(file, pos + 40);
        if (!within(offset, filesz, @intCast(file.len))) return false;
        if (filesz > memsz or paddr < 0x100000) return false;
        if (vaddr != paddr or !within(paddr, memsz, address_limit)) return false;
        if ((paddr & 4095) != (offset & 4095)) return false;
    }
    return found_load;
}

// ABI intentionally uses a C pointer + length, not a Zig slice.
export fn noq_zig_validate_elf(bytes: [*]const u8, length: usize) callconv(.c) u32 {
    if (length < elf_header_size or length > max_image) return 0;
    return if (validateElf(bytes[0..length])) 1 else 0;
}

test "rejects short and forged ELF inputs" {
    const std = @import("std");
    try std.testing.expect(!validateElf(&[_]u8{}));
    const b = [_]u8{0} ** 64;
    try std.testing.expect(!validateElf(&b));
}

test "accepts a constrained ELF64 PT_LOAD header" {
    const std = @import("std");
    var b = [_]u8{0} ** 128;
    b[0] = 0x7f; b[1] = 'E'; b[2] = 'L'; b[3] = 'F';
    b[4] = 2; b[5] = 1; b[6] = 1;
    b[16] = 2; b[18] = 62;
    b[32] = 64; b[54] = 56; b[56] = 1;
    b[64] = 1; // PT_LOAD
    b[64 + 16 + 2] = 0x10; // virtual address 0x100000
    b[64 + 24 + 2] = 0x10; // physical address 0x100000
    try std.testing.expect(validateElf(&b));
    b[64 + 32] = 129; // file size exceeds input
    try std.testing.expect(!validateElf(&b));
}
