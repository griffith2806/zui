const std = @import("std");

/// A decoded image stored in 0xAARRGGBB packed pixel format,
/// matching the layout expected by Renderer.drawImageRaw.
pub const Image = struct {
    width:  u32,
    height: u32,
    pixels: []u32,

    pub fn deinit(self: *Image, alloc: std.mem.Allocator) void {
        alloc.free(self.pixels);
    }

    /// Convert from packed RGBA8 bytes (R,G,B,A per pixel) into the
    /// 0xAARRGGBB u32 format used by the software renderer.
    pub fn fromRgba(alloc: std.mem.Allocator, rgba: []const u8, width: u32, height: u32) !Image {
        std.debug.assert(rgba.len == width * height * 4);
        const count = width * height;
        const pixels = try alloc.alloc(u32, count);
        for (0..count) |i| {
            const r: u32 = rgba[i * 4 + 0];
            const g: u32 = rgba[i * 4 + 1];
            const b: u32 = rgba[i * 4 + 2];
            const a: u32 = rgba[i * 4 + 3];
            pixels[i] = (a << 24) | (r << 16) | (g << 8) | b;
        }
        return .{ .width = width, .height = height, .pixels = pixels };
    }

    /// Construct a solid-color image.
    pub fn fromColor(alloc: std.mem.Allocator, width: u32, height: u32, r: u8, g: u8, b: u8, a: u8) !Image {
        const count = width * height;
        const pixels = try alloc.alloc(u32, count);
        const v: u32 = (@as(u32, a) << 24) | (@as(u32, r) << 16) | (@as(u32, g) << 8) | @as(u32, b);
        @memset(pixels, v);
        return .{ .width = width, .height = height, .pixels = pixels };
    }

    /// Create a solid-color image from a packed 0xAARRGGBB value.
    pub fn solid(alloc: std.mem.Allocator, w: u32, h: u32, color: u32) !Image {
        const pixels = try alloc.alloc(u32, w * h);
        @memset(pixels, color);
        return .{ .pixels = pixels, .width = w, .height = h };
    }

    /// Wrap a caller-owned pixel buffer (no copy; caller transfers ownership).
    /// `pixels` must be w * h elements in 0xAARRGGBB format.
    pub fn fromRaw(pixels: []u32, w: u32, h: u32) Image {
        return .{ .pixels = pixels, .width = w, .height = h };
    }
};

test "Image fromColor" {
    const alloc = std.testing.allocator;
    var img = try Image.fromColor(alloc, 4, 4, 255, 0, 0, 255);
    defer img.deinit(alloc);
    try std.testing.expectEqual(@as(u32, 4), img.width);
    try std.testing.expectEqual(@as(u32, 4), img.height);
    try std.testing.expectEqual(@as(u32, 0xFF_FF0000), img.pixels[0]);
}

test "Image fromRgba" {
    const alloc = std.testing.allocator;
    const data = [_]u8{ 10, 20, 30, 200 };
    var img = try Image.fromRgba(alloc, &data, 1, 1);
    defer img.deinit(alloc);
    try std.testing.expectEqual(@as(u32, 0xC8_0A141E), img.pixels[0]);
}

test "Image solid" {
    const alloc = std.testing.allocator;
    var img = try Image.solid(alloc, 3, 3, 0xFF_0000FF);
    defer img.deinit(alloc);
    try std.testing.expectEqual(@as(u32, 3), img.width);
    try std.testing.expectEqual(@as(u32, 3), img.height);
    try std.testing.expectEqual(@as(usize, 9), img.pixels.len);
    try std.testing.expectEqual(@as(u32, 0xFF_0000FF), img.pixels[0]);
    try std.testing.expectEqual(@as(u32, 0xFF_0000FF), img.pixels[8]);
}

test "Image fromRaw" {
    var buf = [_]u32{ 0xFF_112233, 0xFF_445566 };
    const img = Image.fromRaw(&buf, 2, 1);
    try std.testing.expectEqual(@as(u32, 2), img.width);
    try std.testing.expectEqual(@as(u32, 1), img.height);
    try std.testing.expectEqual(@as(u32, 0xFF_112233), img.pixels[0]);
    try std.testing.expectEqual(@as(u32, 0xFF_445566), img.pixels[1]);
}
