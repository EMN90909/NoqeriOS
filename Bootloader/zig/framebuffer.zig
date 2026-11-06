// NoqeriOS UEFI GOP handoff contract in freestanding Zig.
// The firmware adapter passes primitive values, avoiding C/Zig struct padding.
// Only mapped 32bpp RGB/BGR scanouts can be handed to the Noqeri renderer.
const std = @import("std");

const framebuffer_limit: u64 = 0x8000_0000_00; // first 512 GiB, one PML4 slot
const max_frame_bytes: u64 = 256 * 1024 * 1024;

fn rangeFits(start: u64, length: u64, limit: u64) bool {
    return start <= limit and length <= limit - start;
}

pub fn validFramebuffer(
    address: u64,
    available_bytes: u64,
    pitch: u32,
    width: u32,
    height: u32,
    red_position: u8,
    blue_position: u8,
) bool {
    if (address < 0x100000 or (address & 3) != 0) return false;
    if (width < 320 or height < 240 or width > 4096 or height > 2160) return false;
    if (pitch < width * 4 or pitch > 65536 or pitch % 4 != 0) return false;
    if (!((red_position == 0 and blue_position == 16) or
        (red_position == 16 and blue_position == 0))) return false;

    const visible_bytes: u64 = @as(u64, pitch) * @as(u64, height);
    if (visible_bytes == 0 or visible_bytes > max_frame_bytes) return false;
    if (available_bytes < visible_bytes) return false;
    if (!rangeFits(address, visible_bytes, framebuffer_limit)) return false;
    return true;
}

// SysV x86-64 C ABI; no allocation, firmware calls, or other Zig runtime state.
export fn noq_zig_validate_framebuffer(
    address: u64,
    available_bytes: u64,
    pitch: u32,
    width: u32,
    height: u32,
    red_position: u8,
    blue_position: u8,
) callconv(.c) u32 {
    return if (validFramebuffer(address, available_bytes, pitch, width, height,
        red_position, blue_position)) 1 else 0;
}

test "accepts GOP RGB and BGR modes with scanline padding" {
    try std.testing.expect(validFramebuffer(0xE0000000, 4 * 1024 * 1024,
        4096, 800, 600, 16, 0));
    try std.testing.expect(validFramebuffer(0xE0000000, 4 * 1024 * 1024,
        4096, 800, 600, 0, 16));
}

test "rejects unmapped, overlapping or malformed scanouts" {
    try std.testing.expect(!validFramebuffer(0, 1024 * 1024, 3200, 800, 600, 16, 0));
    try std.testing.expect(!validFramebuffer(0xE0000001, 4 * 1024 * 1024, 3200, 800, 600, 16, 0));
    try std.testing.expect(!validFramebuffer(0xE0000000, 4 * 1024 * 1024, 3196, 800, 600, 16, 0));
    try std.testing.expect(!validFramebuffer(0xE0000000, 1000, 3200, 800, 600, 16, 0));
    try std.testing.expect(!validFramebuffer(0xE0000000, 4 * 1024 * 1024, 3200, 800, 600, 8, 16));
    try std.testing.expect(!validFramebuffer(framebuffer_limit - 4096, 4 * 1024 * 1024,
        3200, 800, 600, 16, 0));
    try std.testing.expect(!validFramebuffer(0xE0000000, 4 * 1024 * 1024,
        3200, 800, 600, 16, 16));
}
