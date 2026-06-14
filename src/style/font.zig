const std = @import("std");

pub const Weight = enum { thin, light, regular, medium, semibold, bold, extrabold, black };
pub const Style = enum { normal, italic };

pub const Font = struct {
    family: []const u8,
    size_pt: f32,
    weight: Weight,
    style: Style,

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
};

test "Font presets" {
    try std.testing.expectEqual(@as(f32, 12.0), Font.default().size_pt);
    try std.testing.expectEqual(@as(f32, 20.0), Font.heading().size_pt);
    try std.testing.expectEqual(Weight.semibold, Font.heading().weight);
    try std.testing.expectEqual(@as(f32, 10.0), Font.caption().size_pt);
    try std.testing.expectEqualStrings("Cascadia Code", Font.mono().family);
}
