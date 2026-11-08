// NoqeriOS x86-64 linear framebuffer driver (Zig 0.15.x).
// Runs after the firmware supplies a Multiboot2 framebuffer tag.
// MMIO writes are volatile. No UEFI calls, allocator, libc or global state.
const std = @import("std");
const max_phys: u64 = 0x8000_0000_00; // first 512 GiB PML4 slot
const Fbuf = struct {
    address: usize,
    stride: usize,
    width: usize,
    height: usize,
    swap: bool,
};
fn u32le(p: [*]const u8, at: usize) u32 {
    return @as(u32, p[at]) | (@as(u32, p[at+1]) << 8) |
        (@as(u32, p[at+2]) << 16) | (@as(u32, p[at+3]) << 24);
}
fn u64le(p: [*]const u8, at: usize) u64 {
    return @as(u64, u32le(p, at)) | (@as(u64, u32le(p, at+4)) << 32);
}
fn descriptor(tag: usize) ?Fbuf {
    if (tag == 0 or tag % 8 != 0) return null;
    const p: [*]const u8 = @ptrFromInt(tag);
    if (u32le(p, 0) != 8 or u32le(p, 4) < 38) return null;
    const address = u64le(p, 8);
    const pitch = u32le(p, 16);
    const width = u32le(p, 20);
    const height = u32le(p, 24);
    if (p[28] != 32 or p[29] != 1 or address == 0 or address >= max_phys) return null;
    if (width < 320 or height < 240 or width > 4096 or height > 2160) return null;
    if (pitch < width * 4 or pitch > 65536 or pitch % 4 != 0 or address % 4 != 0) return null;
    const bytes = @as(u64, pitch) * height;
    if (bytes > max_phys - address) return null;
    if (p[33] != 8 or p[35] != 8 or p[37] != 8 or p[34] != 8) return null;
    const red = p[32];
    const blue = p[36];
    if (!((red == 0 and blue == 16) or (red == 16 and blue == 0))) return null;
    return .{
        .address = @intCast(address),
        .stride = @as(usize, pitch) / 4,
        .width = width,
        .height = height,
        .swap = red == 0,
    };
}
fn pack(rgb: u32, swap: bool) u32 {
    const value = rgb & 0x00ff_ffff;
    if (!swap) return value;
    return ((value & 0xff) << 16) | (value & 0x00ff00) | ((value >> 16) & 0xff);
}
fn put(fb: Fbuf, x: usize, y: usize, rgb: u32) void {
    const p: *volatile u32 = @ptrFromInt(fb.address + (y * fb.stride + x) * 4);
    p.* = pack(rgb, fb.swap);
}
fn fill(fb: Fbuf, left: usize, top: usize, width: usize, height: usize, rgb: u32) bool {
    if (left >= fb.width or top >= fb.height) return true;
    const w = @min(width, fb.width - left);
    const h = @min(height, fb.height - top);
    if (w == 0 or h == 0) return true;
    const value = pack(rgb, fb.swap);
    for (0..h) |y| {
        const base = fb.address + ((top + y) * fb.stride + left) * 4;
        const row: [*]volatile u32 = @ptrFromInt(base);
        for (0..w) |x| row[x] = value;
    }
    return true;
}
export fn zig_fb_valid(tag: usize) callconv(.c) bool {
    return descriptor(tag) != null;
}
export fn zig_fb_fill_rect(tag: usize, left: usize, top: usize, width: usize, height: usize, rgb: u32) callconv(.c) bool {
    const fb = descriptor(tag) orelse return false;
    return fill(fb, left, top, width, height, rgb);
}
export fn zig_fb_pixel(tag: usize, x: usize, y: usize, rgb: u32) callconv(.c) bool {
    const fb = descriptor(tag) orelse return false;
    if (x >= fb.width or y >= fb.height) return false;
    put(fb, x, y, rgb);
    return true;
}
// Matches Noqeri's FramebufferImage record: 4 machine-word fields.
const Image = extern struct {
    pixels: usize,
    stride: usize,
    width: usize,
    height: usize,
};
export fn zig_fb_blit(tag: usize, dest_x: usize, dest_y: usize, image_addr: usize) callconv(.c) bool {
    const fb = descriptor(tag) orelse return false;
    if (image_addr == 0 or dest_x >= fb.width or dest_y >= fb.height) return false;
    const image: *const Image = @ptrFromInt(image_addr);
    if (image.pixels == 0 or image.width == 0 or image.height == 0 or
        image.stride < image.width or image.stride > 16384) return false;
    const w = @min(image.width, fb.width - dest_x);
    const h = @min(image.height, fb.height - dest_y);
    const pixels: [*]const u32 = @ptrFromInt(image.pixels);
    for (0..h) |y| {
        for (0..w) |x| put(fb, dest_x + x, dest_y + y, pixels[y * image.stride + x]);
    }
    return true;
}
test "RGB/BGR channel packing" {
    try std.testing.expectEqual(@as(u32, 0x00112233), pack(0x00112233, false));
    try std.testing.expectEqual(@as(u32, 0x00332211), pack(0x00112233, true));
}
test "reject null and misaligned tags" {
    try std.testing.expect(!zig_fb_valid(0));
    try std.testing.expect(!zig_fb_valid(3));
}
test "clipping and row pitch in memory framebuffer" {
    var pixels = [_]u32{0} ** (330 * 240);
    const fb = Fbuf{.address = @intFromPtr(&pixels), .stride = 330, .width = 320, .height = 240, .swap = false};
    try std.testing.expect(fill(fb, 318, 239, 20, 20, 0xabcdef));
    try std.testing.expectEqual(@as(u32, 0xabcdef), pixels[239 * 330 + 318]);
    try std.testing.expectEqual(@as(u32, 0xabcdef), pixels[239 * 330 + 319]);
    try std.testing.expectEqual(@as(u32, 0), pixels[239 * 330 + 320]);
}

fn testGopTag() [48]u8 {
    // MB2 tag 8: 1366x768, 32-bpp, 5464 bytes/row (Intel laptop-like).
    var tag = [_]u8{0} ** 48;
    tag[0] = 8; tag[4] = 38;
    tag[10] = 0x40; // physical linear framebuffer 0x00400000
    tag[16] = 0x58; tag[17] = 0x15; // pitch 5464
    tag[20] = 0x56; tag[21] = 0x05; // width 1366
    tag[25] = 3; // height 768
    tag[28] = 32; tag[29] = 1; // direct-RGB
    tag[32] = 16; tag[33] = 8;
    tag[34] = 8; tag[35] = 8;
    tag[36] = 0; tag[37] = 8;
    return tag;
}
test "validate actual GOP stride and reject malformed channel layouts" {
    var tag: [48]u8 align(8) = testGopTag();
    const frame = descriptor(@intFromPtr(&tag)) orelse return error.InvalidGopFixture;
    try std.testing.expectEqual(@as(usize, 1366), frame.width);
    try std.testing.expectEqual(@as(usize, 768), frame.height);
    try std.testing.expectEqual(@as(usize, 1366), frame.stride);
    try std.testing.expect(!frame.swap);
    tag[35] = 7; // non-eight-bit green mask
    try std.testing.expect(descriptor(@intFromPtr(&tag)) == null);
    tag[35] = 8;
    tag[16] = 0; tag[17] = 0; // invalid pitch
    try std.testing.expect(descriptor(@intFromPtr(&tag)) == null);
}
test "reject framebuffer extending beyond the mapped physical aperture" {
    var tag: [48]u8 align(8) = testGopTag();
    // Set framebuffer base at 512 GiB - 4096, but framebuffer spans ~4 MiB.
    tag[8] = 0; tag[9] = 0xf0; tag[10] = 0xff;
    tag[11] = 0xff; tag[12] = 0x7f;
    try std.testing.expect(descriptor(@intFromPtr(&tag)) == null);
}
