// NoqeriOS ELF64 x86-64 loader validation, freestanding Zig 0.15.x.
// Firmware integration operates on untrusted bytes before any page writes.
// Keep the first GiB identity-mapped ABI expected by our native kernel.
const std = @import("std");

const header_bytes: usize = 64;
const program_bytes: usize = 56;
const max_phdrs: usize = 128;
const max_image: usize = 512 * 1024;
const identity_limit: u64 = 0x4000_0000;

fn le16(bytes: []const u8, pos: usize) u16 {
    return @as(u16, bytes[pos]) | (@as(u16, bytes[pos + 1]) << 8);
}
fn le32(bytes: []const u8, pos: usize) u32 {
    return @as(u32, bytes[pos]) |
        (@as(u32, bytes[pos + 1]) << 8) |
        (@as(u32, bytes[pos + 2]) << 16) |
        (@as(u32, bytes[pos + 3]) << 24);
}
fn le64(bytes: []const u8, pos: usize) u64 {
    return @as(u64, le32(bytes, pos)) | (@as(u64, le32(bytes, pos + 4)) << 32);
}
// Subtraction instead of start + length prevents integer overflow.
fn rangeFits(start: u64, length: u64, limit: u64) bool {
    return start <= limit and length <= limit - start;
}
fn overlaps(a: u64, a_len: u64, b: u64, b_len: u64) bool {
    if (a_len == 0 or b_len == 0) return false;
    return a < b + b_len and b < a + a_len; // bounds already checked
}

/// Returns false on any unsupported or unsafe ELF64 image.
pub fn validateElf(bytes: []const u8) bool {
    if (bytes.len < header_bytes or bytes.len > max_image) return false;
    if (!std.mem.eql(u8, bytes[0..4], "\x7fELF")) return false;
    if (bytes[4] != 2 or bytes[5] != 1 or bytes[6] != 1) return false;
    if (le16(bytes, 16) != 2 or le16(bytes, 18) != 62 or le32(bytes, 20) != 1) return false;
    if (le16(bytes, 52) != 64) return false;
    const entry = le64(bytes, 24);
    const phoff = le64(bytes, 32);
    const phsize = le16(bytes, 54);
    const phcount = le16(bytes, 56);
    if (entry < 0x10_0000 or entry >= identity_limit) return false;
    if (phsize != 56 or phcount == 0 or phcount > 128) return false;
    if (!rangeFits(phoff, @as(u64, phcount) * 56, @intCast(bytes.len))) return false;

    var executable_entry = false;
    var has_load = false;
    for (0..@as(usize, phcount)) |i| {
        const base: usize = @intCast(phoff);
        const pos: usize = base + i * program_bytes;
        if (le32(bytes, pos) != 1) continue;
        const flags = le32(bytes, pos + 4);
        const file_offset = le64(bytes, pos + 8);
        const vaddr = le64(bytes, pos + 16);
        const paddr = le64(bytes, pos + 24);
        const file_size = le64(bytes, pos + 32);
        const mem_size = le64(bytes, pos + 40);
        if (!rangeFits(file_offset, file_size, @intCast(bytes.len))) return false;
        if (file_size > mem_size or paddr < 0x10_0000) return false;
        if (!rangeFits(paddr, mem_size, identity_limit) or vaddr != paddr) return false;
        if ((paddr & 4095) != (file_offset & 4095)) return false;
        if (mem_size == 0) continue;

        // Loading overlapping segments in place can overwrite the kernel
        // unpredictably, even when each individual segment passes bounds.
        for (0..i) |previous| {
            const old: usize = base + previous * program_bytes;
            if (le32(bytes, old) != 1) continue;
            const old_start = le64(bytes, old + 24);
            const old_len = le64(bytes, old + 40);
            // The earlier segment is already validated.
            if (overlaps(paddr, mem_size, old_start, old_len)) return false;
        }
        has_load = true;
        if ((flags & 1) != 0 and entry >= paddr and entry - paddr < mem_size)
            executable_entry = true;
    }
    return has_load and executable_entry;
}

// C ABI callable from the native UEFI firmware adapter. No heap or libc.
export fn noq_zig_validate_elf(ptr: [*]const u8, len: usize) callconv(.c) u32 {
    if (len < header_bytes or len > max_image) return 0;
    return if (validateElf(ptr[0..len])) 1 else 0;
}

fn sample() [128]u8 {
    var b = [_]u8{0} ** 128;
    b[0] = 0x7f; b[1] = 'E'; b[2] = 'L'; b[3] = 'F';
    b[4] = 2; b[5] = 1; b[6] = 1;
    b[16] = 2; b[18] = 62; b[20] = 1;
    b[24 + 2] = 0x10; // e_entry 0x100000
    b[32] = 64; b[52] = 64; b[54] = 56; b[56] = 1;
    b[64] = 1; // PT_LOAD
    b[64 + 4] = 5; // readable and executable
    b[64 + 16 + 2] = 0x10; // vaddr 0x100000
    b[64 + 24 + 2] = 0x10; // paddr 0x100000
    b[64 + 40] = 64; // memsz
    return b;
}

test "valid kernel header" {
    var b = sample();
    try std.testing.expect(validateElf(&b));
    b[64 + 32] = 129;
    try std.testing.expect(!validateElf(&b)); // out-of-bounds file payload
}
test "reject bad magic, truncated, incorrect architecture and entry" {
    var b = sample();
    try std.testing.expect(!validateElf(&[_]u8{}));
    b[0] = 0;
    try std.testing.expect(!validateElf(&b));
    b = sample();
    b[18] = 3;
    try std.testing.expect(!validateElf(&b));
    b = sample();
    b[24 + 2] = 0x20;
    try std.testing.expect(!validateElf(&b));
}
test "reject invalid segment addresses, sizes and overlap" {
    var b = sample();
    b[64 + 40] = 0;
    try std.testing.expect(!validateElf(&b));
    b = sample();
    b[64 + 24 + 2] = 0;
    try std.testing.expect(!validateElf(&b));
    b = sample();
    b[64 + 32] = 65;
    b[64 + 40] = 64;
    try std.testing.expect(!validateElf(&b));
}
