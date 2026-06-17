const std     = @import("std");
const builtin = @import("builtin");

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

    /// Convert from pre-multiplied BGRA bytes (B,G,R,A per pixel — the layout
    /// WIC outputs as GUID_WICPixelFormat32bppPBGRA) into 0xAARRGGBB u32.
    pub fn fromPremulBgra(alloc: std.mem.Allocator, bgra: []const u8, width: u32, height: u32) !Image {
        std.debug.assert(bgra.len == width * height * 4);
        const count = width * height;
        const pixels = try alloc.alloc(u32, count);
        for (0..count) |i| {
            const b: u32 = bgra[i * 4 + 0];
            const g: u32 = bgra[i * 4 + 1];
            const r: u32 = bgra[i * 4 + 2];
            const a: u32 = bgra[i * 4 + 3];
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

    // ── File loading ──────────────────────────────────────────────────────────

    /// Load any image format that the platform supports.
    ///
    /// On Windows this delegates to Windows Imaging Component (WIC), which
    /// handles PNG, JPEG, BMP, TIFF, GIF, and more with no extra dependencies.
    ///
    /// On non-Windows platforms this returns `error.NotImplemented`.
    pub fn loadFile(alloc: std.mem.Allocator, path: []const u8) !Image {
        if (builtin.os.tag != .windows) return error.NotImplemented;
        return loadFileWindows(alloc, path);
    }

    /// Load a PNG file.  Delegates to `loadFile` — WIC auto-detects format.
    pub fn loadPng(alloc: std.mem.Allocator, path: []const u8) !Image {
        return loadFile(alloc, path);
    }

    /// Load a JPEG file.  Delegates to `loadFile` — WIC auto-detects format.
    pub fn loadJpeg(alloc: std.mem.Allocator, path: []const u8) !Image {
        return loadFile(alloc, path);
    }
};

// ── Windows implementation ────────────────────────────────────────────────────

fn loadFileWindows(alloc: std.mem.Allocator, path: []const u8) !Image {
    const wic = @import("../platform/win32/wic.zig");
    var w: u32 = 0;
    var h: u32 = 0;
    const bgra = try wic.loadFileAsBgra(alloc, path, &w, &h);
    defer alloc.free(bgra);
    // fromPremulBgra copies into a u32 pixel slice; the raw bgra byte buf is freed above.
    return Image.fromPremulBgra(alloc, bgra, w, h);
}

// ── Tests ─────────────────────────────────────────────────────────────────────

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

test "Image fromPremulBgra" {
    // BGRA bytes: B=30, G=20, R=10, A=200  →  0xC8_0A141E (AARRGGBB)
    const alloc = std.testing.allocator;
    const data = [_]u8{ 30, 20, 10, 200 };
    var img = try Image.fromPremulBgra(alloc, &data, 1, 1);
    defer img.deinit(alloc);
    try std.testing.expectEqual(@as(u32, 0xC8_0A141E), img.pixels[0]);
}

test "Image loadFile returns NotImplemented on non-Windows at comptime" {
    // This test is only meaningful on non-Windows; on Windows it would
    // attempt a real file load and fail with DecoderCreateFailed for a
    // missing file, not NotImplemented.
    if (builtin.os.tag == .windows) return error.SkipZigTest;
    const alloc = std.testing.allocator;
    const result = Image.loadFile(alloc, "nonexistent.png");
    try std.testing.expectError(error.NotImplemented, result);
}
