const std = @import("std");
const Color = @import("../../style/color.zig").Color;
const Rect  = @import("../../layout/geometry.zig").Rect;

// Pixel format: Win32 DIB BGRA (stored as 0x00RRGGBB u32 on little-endian).
// Blue in byte 0, green in byte 1, red in byte 2, alpha/pad in byte 3.
pub const Renderer = struct {
    pixels: [*]u32,
    width:  u32,
    height: u32,

    pub fn init(pixels: [*]u32, width: u32, height: u32) Renderer {
        return .{ .pixels = pixels, .width = width, .height = height };
    }

    pub fn clear(self: *Renderer, color: Color) void {
        const v = toPixel(color);
        for (0..self.width * self.height) |i| self.pixels[i] = v;
    }

    pub fn fillRect(self: *Renderer, rect: Rect, color: Color) void {
        const v  = toPixel(color);
        const x0 = @max(0, rect.x);
        const y0 = @max(0, rect.y);
        const x1 = @min(@as(i32, @intCast(self.width)),  rect.right());
        const y1 = @min(@as(i32, @intCast(self.height)), rect.bottom());
        if (x0 >= x1 or y0 >= y1) return;
        var y: i32 = y0;
        while (y < y1) : (y += 1) {
            const row: u32 = @as(u32, @intCast(y)) * self.width;
            var x: i32 = x0;
            while (x < x1) : (x += 1) {
                self.pixels[row + @as(u32, @intCast(x))] = v;
            }
        }
    }

    fn toPixel(c: Color) u32 {
        return (@as(u32, c.r) << 16) | (@as(u32, c.g) << 8) | @as(u32, c.b);
    }
};
