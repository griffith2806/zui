const std = @import("std");
const Color = @import("color.zig").Color;
const Style = @import("style.zig").Style;

/// A lightweight CSS-like stylesheet parser.
///
/// Format (one rule per line):
///   key: value
///
/// Lines starting with '#' are comments; blank lines are ignored.
/// No selectors — this is a flat property map applied to a single Style.
///
/// Supported keys:
///   bg, fg, border  — #RRGGBB or #RRGGBBAA hex color
///   radius          — unsigned integer (logical pixels)
///   padding         — unsigned integer (logical pixels)
///
/// Example:
///   # zui stylesheet
///   bg: #1a1a1e
///   fg: #ffffff
///   radius: 8
///   padding: 12
pub const Stylesheet = struct {
    style: Style = .{},

    /// Parse `src` text into a Stylesheet.
    /// Returns `error.InvalidColor` for malformed hex colors,
    /// or `error.InvalidCharacter` / `error.Overflow` for bad integers.
    pub fn parse(src: []const u8) !Stylesheet {
        var sheet = Stylesheet{};
        var lines = std.mem.splitScalar(u8, src, '\n');
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0 or trimmed[0] == '#') continue;
            const colon = std.mem.indexOfScalar(u8, trimmed, ':') orelse continue;
            const key = std.mem.trim(u8, trimmed[0..colon], " \t");
            const val = std.mem.trim(u8, trimmed[colon + 1 ..], " \t");
            try sheet.applyProp(key, val);
        }
        return sheet;
    }

    fn applyProp(self: *Stylesheet, key: []const u8, val: []const u8) !void {
        if (std.mem.eql(u8, key, "bg")) {
            self.style.bg = try parseColor(val);
        } else if (std.mem.eql(u8, key, "fg")) {
            self.style.fg = try parseColor(val);
        } else if (std.mem.eql(u8, key, "border")) {
            self.style.border = try parseColor(val);
        } else if (std.mem.eql(u8, key, "radius")) {
            self.style.radius = try std.fmt.parseInt(u32, val, 10);
        } else if (std.mem.eql(u8, key, "padding")) {
            self.style.padding = try std.fmt.parseInt(u32, val, 10);
        }
        // Unknown keys are silently ignored for forward compatibility.
    }
};

/// Parse a CSS hex color: #RRGGBB or #RRGGBBAA.
fn parseColor(s: []const u8) !Color {
    if (s.len == 0 or s[0] != '#') return error.InvalidColor;
    const hex = s[1..];
    switch (hex.len) {
        6 => {
            const v = try std.fmt.parseInt(u32, hex, 16);
            return Color.rgb(
                @truncate(v >> 16),
                @truncate(v >> 8),
                @truncate(v),
            );
        },
        8 => {
            const v = try std.fmt.parseInt(u32, hex, 16);
            return Color.rgba(
                @truncate(v >> 24),
                @truncate(v >> 16),
                @truncate(v >> 8),
                @truncate(v),
            );
        },
        else => return error.InvalidColor,
    }
}

test "Stylesheet.parse: basic properties" {
    const src =
        \\# zui stylesheet
        \\bg: #1a1a1e
        \\fg: #ffffff
        \\radius: 8
        \\padding: 12
    ;
    const sheet = try Stylesheet.parse(src);
    const s = sheet.style;

    try std.testing.expectEqual(Color.rgb(0x1a, 0x1a, 0x1e), s.bg.?);
    try std.testing.expectEqual(Color.rgb(0xff, 0xff, 0xff), s.fg.?);
    try std.testing.expectEqual(@as(u32, 8), s.radius.?);
    try std.testing.expectEqual(@as(u32, 12), s.padding.?);
    try std.testing.expectEqual(@as(?Color, null), s.border);
}

test "Stylesheet.parse: #RRGGBBAA color" {
    const src = "border: #ff000080";
    const sheet = try Stylesheet.parse(src);
    const expected = Color.rgba(0xff, 0x00, 0x00, 0x80);
    try std.testing.expectEqual(expected, sheet.style.border.?);
}

test "Stylesheet.parse: blank lines and comments ignored" {
    const src =
        \\
        \\# comment line
        \\
        \\radius: 4
        \\
    ;
    const sheet = try Stylesheet.parse(src);
    try std.testing.expectEqual(@as(u32, 4), sheet.style.radius.?);
    try std.testing.expectEqual(@as(?Color, null), sheet.style.bg);
}

test "Stylesheet.parse: unknown keys are silently ignored" {
    const src = "unknown_key: foobar";
    const sheet = try Stylesheet.parse(src);
    try std.testing.expectEqual(Style.empty, sheet.style);
}

test "Stylesheet.parse: invalid color returns error" {
    try std.testing.expectError(error.InvalidColor, Stylesheet.parse("bg: red"));
    try std.testing.expectError(error.InvalidColor, Stylesheet.parse("bg: #xyz"));
    try std.testing.expectError(error.InvalidColor, Stylesheet.parse("bg: #12345"));
}

test "Stylesheet.parse: lines without colon are skipped" {
    const src = "no colon here";
    const sheet = try Stylesheet.parse(src);
    try std.testing.expectEqual(Style.empty, sheet.style);
}
