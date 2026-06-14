const std = @import("std");
const Color = @import("../../style/color.zig").Color;
const Rect  = @import("../../layout/geometry.zig").Rect;
const font  = @import("font.zig");

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

    /// Draw a single line of ASCII text. Non-printable bytes are skipped.
    pub fn drawText(self: *Renderer, text: []const u8, x: i32, y: i32, color: Color) void {
        const v = toPixel(color);
        for (text, 0..) |ch, ci| {
            const gx: i32 = x + @as(i32, @intCast(ci)) * @as(i32, font.GLYPH_W);
            const g = font.glyph(ch);
            for (g, 0..) |row_bits, ry| {
                var bit: u3 = 7;
                while (true) {
                    if (row_bits & (@as(u8, 1) << bit) != 0) {
                        const px = gx + @as(i32, 7 - bit);
                        const py = y  + @as(i32, @intCast(ry));
                        if (px >= 0 and px < @as(i32, @intCast(self.width)) and
                            py >= 0 and py < @as(i32, @intCast(self.height)))
                        {
                            self.pixels[@as(u32, @intCast(py)) * self.width + @as(u32, @intCast(px))] = v;
                        }
                    }
                    if (bit == 0) break;
                    bit -= 1;
                }
            }
        }
    }

    /// Measure the pixel width of a text string.
    pub fn textWidth(text: []const u8) u32 {
        return @intCast(text.len * font.GLYPH_W);
    }

    fn toPixel(c: Color) u32 {
        return (@as(u32, c.r) << 16) | (@as(u32, c.g) << 8) | @as(u32, c.b);
    }
};
