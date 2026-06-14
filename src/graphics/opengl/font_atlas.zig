const font = @import("../software/font.zig");

pub const GLYPH_W: u32 = font.GLYPH_W;
pub const GLYPH_H: u32 = font.GLYPH_H;
pub const NUM_GLYPHS: u32 = 96; // ASCII 0x20–0x7E
pub const ATLAS_W: u32 = NUM_GLYPHS * GLYPH_W; // 768
pub const ATLAS_H: u32 = GLYPH_H;              // 8

// Build a 768×8 R8 atlas: 1 row of all 96 glyphs, MSB = leftmost pixel.
pub fn build(out: *[ATLAS_H][ATLAS_W]u8) void {
    for (out) |*row| @memset(row, 0);
    for (0..NUM_GLYPHS) |gi| {
        const g = font.glyph(@intCast(gi + 0x20));
        for (g, 0..) |row_bits, ry| {
            var bit: u3 = 7;
            while (true) {
                const px: u32 = @intCast(gi * GLYPH_W + (7 - @as(u32, bit)));
                out[ry][px] = if (row_bits & (@as(u8, 1) << bit) != 0) 255 else 0;
                if (bit == 0) break;
                bit -= 1;
            }
        }
    }
}

// UV rect for a glyph: returns (u0, v0, u1, v1) in [0,1].
pub fn glyphUV(ch: u8) [4]f32 {
    const idx: f32 = @floatFromInt(if (ch >= 0x20 and ch <= 0x7E) ch - 0x20 else 0);
    const left = idx * @as(f32, GLYPH_W) / @as(f32, ATLAS_W);
    const right = left + @as(f32, GLYPH_W) / @as(f32, ATLAS_W);
    return .{ left, 0.0, right, 1.0 };
}
