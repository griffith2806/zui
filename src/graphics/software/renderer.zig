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

    /// Draw text scaled uniformly by `scale` (integer multiple).
    pub fn drawTextScaled(self: *Renderer, text: []const u8, x: i32, y: i32, color: Color, scale: u32) void {
        const v = toPixel(color);
        const s: i32 = @intCast(scale);
        for (text, 0..) |ch, ci| {
            const gx: i32 = x + @as(i32, @intCast(ci)) * @as(i32, font.GLYPH_W) * s;
            const g = font.glyph(ch);
            for (g, 0..) |row_bits, ry| {
                var bit: u3 = 7;
                while (true) {
                    if (row_bits & (@as(u8, 1) << bit) != 0) {
                        const bx: i32 = gx + @as(i32, @intCast(7 - @as(u32, bit))) * s;
                        const by: i32 = y + @as(i32, @intCast(ry)) * s;
                        var dy: i32 = 0;
                        while (dy < s) : (dy += 1) {
                            var dx: i32 = 0;
                            while (dx < s) : (dx += 1) {
                                const px = bx + dx;
                                const py = by + dy;
                                if (px >= 0 and px < @as(i32, @intCast(self.width)) and
                                    py >= 0 and py < @as(i32, @intCast(self.height)))
                                {
                                    self.pixels[@as(u32, @intCast(py)) * self.width + @as(u32, @intCast(px))] = v;
                                }
                            }
                        }
                    }
                    if (bit == 0) break;
                    bit -= 1;
                }
            }
        }
    }

    pub fn resize(self: *Renderer, pixels: [*]u32, w: u32, h: u32) void {
        self.pixels = pixels;
        self.width  = w;
        self.height = h;
    }

    pub fn textWidthScaled(text: []const u8, scale: u32) u32 {
        return @intCast(text.len * font.GLYPH_W * scale);
    }

    /// Alpha-blend `color` over the pixel at (x, y). Skips out-of-bounds.
    fn blendPixel(self: *Renderer, x: u32, y: u32, color: Color) void {
        if (x >= self.width or y >= self.height) return;
        const idx = y * self.width + x;
        if (color.a == 255) {
            self.pixels[idx] = toPixel(color);
        } else if (color.a > 0) {
            const bg  = self.pixels[idx];
            const bg_r: u32 = (bg >> 16) & 0xFF;
            const bg_g: u32 = (bg >> 8) & 0xFF;
            const bg_b: u32 = bg & 0xFF;
            const af  = @as(u32, color.a);
            const oma = 255 - af;
            const r = (color.r * af + bg_r * oma) / 255;
            const g = (color.g * af + bg_g * oma) / 255;
            const b = (color.b * af + bg_b * oma) / 255;
            self.pixels[idx] = (r << 16) | (g << 8) | b;
        }
    }

    /// Draw a filled rounded rectangle. `radius` is clamped to half the
    /// shorter side. Alpha in `color` is composited via `blendPixel`.
    pub fn fillRoundRect(self: *Renderer, rect: Rect, radius: u32, color: Color) void {
        const r: i32 = @intCast(@min(radius, @min(rect.width, rect.height) / 2));
        const x0 = @max(0, rect.x);
        const y0 = @max(0, rect.y);
        const x1 = @min(@as(i32, @intCast(self.width)),  rect.right());
        const y1 = @min(@as(i32, @intCast(self.height)), rect.bottom());
        if (x0 >= x1 or y0 >= y1) return;
        var y = y0;
        while (y < y1) : (y += 1) {
            var x = x0;
            while (x < x1) : (x += 1) {
                const in_left  = x < rect.x + r;
                const in_right = x >= rect.right() - r;
                const in_top   = y < rect.y + r;
                const in_bot   = y >= rect.bottom() - r;
                if ((in_left or in_right) and (in_top or in_bot)) {
                    const cx: i32 = if (in_left) rect.x + r else rect.right() - r;
                    const cy: i32 = if (in_top)  rect.y + r else rect.bottom() - r;
                    const dx = x - cx;
                    const dy = y - cy;
                    if (dx * dx + dy * dy > r * r) continue;
                }
                self.blendPixel(@intCast(x), @intCast(y), color);
            }
        }
    }

    fn toPixel(c: Color) u32 {
        return (@as(u32, c.r) << 16) | (@as(u32, c.g) << 8) | @as(u32, c.b);
    }
};
