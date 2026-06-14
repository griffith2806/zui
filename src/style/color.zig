const std = @import("std");

pub const Color = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8 = 255,

    pub fn rgb(r: u8, g: u8, b: u8) Color {
        return .{ .r = r, .g = g, .b = b, .a = 255 };
    }

    pub fn rgba(r: u8, g: u8, b: u8, a: u8) Color {
        return .{ .r = r, .g = g, .b = b, .a = a };
    }

    pub fn fromU32(v: u32) Color {
        return .{
            .r = @truncate(v >> 24),
            .g = @truncate(v >> 16),
            .b = @truncate(v >> 8),
            .a = @truncate(v),
        };
    }

    pub fn toU32(self: Color) u32 {
        return (@as(u32, self.r) << 24) |
            (@as(u32, self.g) << 16) |
            (@as(u32, self.b) << 8) |
            @as(u32, self.a);
    }

    pub fn toF32(self: Color) [4]f32 {
        return .{
            @as(f32, @floatFromInt(self.r)) / 255.0,
            @as(f32, @floatFromInt(self.g)) / 255.0,
            @as(f32, @floatFromInt(self.b)) / 255.0,
            @as(f32, @floatFromInt(self.a)) / 255.0,
        };
    }

    pub fn premultiplied(self: Color) Color {
        const af: f32 = @as(f32, @floatFromInt(self.a)) / 255.0;
        return .{
            .r = @intFromFloat(@as(f32, @floatFromInt(self.r)) * af),
            .g = @intFromFloat(@as(f32, @floatFromInt(self.g)) * af),
            .b = @intFromFloat(@as(f32, @floatFromInt(self.b)) * af),
            .a = self.a,
        };
    }

    pub fn lerp(self: Color, other: Color, t: f32) Color {
        const tc = std.math.clamp(t, 0.0, 1.0);
        const blend = struct {
            fn ch(a: u8, b: u8, tf: f32) u8 {
                return @intFromFloat(@round(@as(f32, @floatFromInt(a)) * (1.0 - tf) + @as(f32, @floatFromInt(b)) * tf));
            }
        }.ch;
        return .{
            .r = blend(self.r, other.r, tc),
            .g = blend(self.g, other.g, tc),
            .b = blend(self.b, other.b, tc),
            .a = blend(self.a, other.a, tc),
        };
    }

    pub const transparent = Color.rgba(0, 0, 0, 0);
    pub const black       = Color.rgb(0, 0, 0);
    pub const white       = Color.rgb(255, 255, 255);
    pub const red         = Color.rgb(255, 0, 0);
    pub const green       = Color.rgb(0, 128, 0);
    pub const blue        = Color.rgb(0, 0, 255);
};

test "fromU32 toU32 round-trip" {
    const v: u32 = 0xFF8040C0;
    const c = Color.fromU32(v);
    try std.testing.expectEqual(v, c.toU32());
}

test "lerp midpoint" {
    const c = Color.black.lerp(Color.white, 0.5);
    try std.testing.expectEqual(@as(u8, 128), c.r);
    try std.testing.expectEqual(@as(u8, 128), c.g);
    try std.testing.expectEqual(@as(u8, 128), c.b);
}

test "premultiplied half-transparent" {
    const c = Color.rgba(200, 100, 50, 128);
    const p = c.premultiplied();
    // channels should be roughly halved
    try std.testing.expect(p.r < 105 and p.r > 95);
    try std.testing.expectEqual(@as(u8, 128), p.a);
}
