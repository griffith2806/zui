const std = @import("std");

pub const Weight = enum { thin, light, regular, medium, semibold, bold, extrabold, black };
pub const Style = enum { normal, italic };

pub const Font = struct {
    family: []const u8,
    size_pt: f32,
    weight: Weight,
    style: Style,
    /// Line height in logical pixels. 0 = automatic (font default).
    line_height: f32 = 0,
    /// Letter spacing in logical pixels (Figma `letterSpacing`).
    letter_spacing: f32 = 0,

    pub fn default() Font {
        return .{
            .family = "Segoe UI Variable",
            .size_pt = 12,
            .weight = .regular,
            .style = .normal,
        };
    }

    pub fn heading() Font {
        return .{
            .family = "Segoe UI Variable",
            .size_pt = 20,
            .weight = .semibold,
            .style = .normal,
        };
    }

    pub fn caption() Font {
        return .{
            .family = "Segoe UI Variable",
            .size_pt = 10,
            .weight = .regular,
            .style = .normal,
        };
    }

    pub fn mono() Font {
        return .{
            .family = "Cascadia Code",
            .size_pt = 12,
            .weight = .regular,
            .style = .normal,
        };
    }

    /// Nearest fixed text-scale ladder rung (1..6) for `size_pt`. The ladder is
    /// 14/22/32/44/60/80 px, so this is `round(size_pt / 14)` clamped to 1..6.
    pub fn nearestScale(self: Font) u8 {
        const r = @round(self.size_pt / 14.0);
        if (!(r > 1.0)) return 1;
        if (r > 6.0) return 6;
        return @intFromFloat(r);
    }
};

test "Font presets" {
    try std.testing.expectEqual(@as(f32, 12.0), Font.default().size_pt);
    try std.testing.expectEqual(@as(f32, 20.0), Font.heading().size_pt);
    try std.testing.expectEqual(Weight.semibold, Font.heading().weight);
    try std.testing.expectEqual(@as(f32, 10.0), Font.caption().size_pt);
    try std.testing.expectEqualStrings("Cascadia Code", Font.mono().family);
}

test "Font typography defaults are auto/zero" {
    const f = Font.default();
    try std.testing.expectEqual(@as(f32, 0), f.line_height);
    try std.testing.expectEqual(@as(f32, 0), f.letter_spacing);
}

test "Font carries line_height and letter_spacing" {
    const f = Font{ .family = "Inter", .size_pt = 16, .weight = .medium, .style = .normal, .line_height = 24, .letter_spacing = 0.5 };
    try std.testing.expectEqual(@as(f32, 24), f.line_height);
    try std.testing.expectEqual(@as(f32, 0.5), f.letter_spacing);
}

test "Font.nearestScale maps to the ladder rung" {
    try std.testing.expectEqual(@as(u8, 1), (Font{ .family = "x", .size_pt = 8, .weight = .regular, .style = .normal }).nearestScale());
    try std.testing.expectEqual(@as(u8, 1), Font.default().nearestScale()); // 12pt
    try std.testing.expectEqual(@as(u8, 1), Font.heading().nearestScale()); // 20pt
    try std.testing.expectEqual(@as(u8, 3), (Font{ .family = "x", .size_pt = 40, .weight = .regular, .style = .normal }).nearestScale());
    try std.testing.expectEqual(@as(u8, 4), (Font{ .family = "x", .size_pt = 56, .weight = .regular, .style = .normal }).nearestScale());
    try std.testing.expectEqual(@as(u8, 6), (Font{ .family = "x", .size_pt = 100, .weight = .regular, .style = .normal }).nearestScale());
}
