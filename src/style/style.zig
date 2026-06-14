const std = @import("std");
const Color = @import("color.zig").Color;
const Font = @import("font.zig").Font;

/// A composable set of style overrides that widgets can hold and merge.
/// Every field is optional — null means "inherit / use default".
pub const Style = struct {
    fg: ?Color = null,
    bg: ?Color = null,
    border: ?Color = null,
    radius: ?u32 = null,
    padding: ?u32 = null,
    font: ?Font = null,

    /// Return a new Style with non-null fields from `override` replacing ours.
    pub fn merge(base: Style, override: Style) Style {
        return .{
            .fg = override.fg orelse base.fg,
            .bg = override.bg orelse base.bg,
            .border = override.border orelse base.border,
            .radius = override.radius orelse base.radius,
            .padding = override.padding orelse base.padding,
            .font = override.font orelse base.font,
        };
    }

    pub const empty = Style{};
};

test "Style.merge: override wins" {
    const base = Style{
        .bg = Color.black,
        .fg = Color.white,
        .radius = 4,
        .padding = 8,
    };
    const over = Style{
        .bg = Color.red,
        .radius = 12,
    };
    const result = base.merge(over);
    try std.testing.expectEqual(Color.red, result.bg.?);
    try std.testing.expectEqual(Color.white, result.fg.?);
    try std.testing.expectEqual(@as(u32, 12), result.radius.?);
    try std.testing.expectEqual(@as(u32, 8), result.padding.?);
    try std.testing.expectEqual(@as(?Color, null), result.border);
    try std.testing.expectEqual(@as(?Font, null), result.font);
}

test "Style.merge: empty override leaves base unchanged" {
    const base = Style{
        .fg = Color.blue,
        .padding = 16,
    };
    const result = base.merge(Style.empty);
    try std.testing.expectEqual(Color.blue, result.fg.?);
    try std.testing.expectEqual(@as(u32, 16), result.padding.?);
}

test "Style.empty has all null fields" {
    const s = Style.empty;
    try std.testing.expectEqual(@as(?Color, null), s.fg);
    try std.testing.expectEqual(@as(?Color, null), s.bg);
    try std.testing.expectEqual(@as(?Color, null), s.border);
    try std.testing.expectEqual(@as(?u32, null), s.radius);
    try std.testing.expectEqual(@as(?u32, null), s.padding);
    try std.testing.expectEqual(@as(?Font, null), s.font);
}
