const std = @import("std");
const geometry = @import("geometry.zig");

const Rect   = geometry.Rect;
const Size   = geometry.Size;
const Margin = geometry.Margin;

pub const Direction = enum { horizontal, vertical };

pub const BoxLayout = struct {
    direction: Direction = .vertical,
    spacing:   u32       = 8,
    padding:   Margin    = Margin.all(0),

    /// Fills `out` with the rect for each item given its preferred `sizes`.
    /// Items are placed in order; no stretching — each gets exactly its preferred size.
    /// `out.len` must equal `sizes.len`.
    pub fn compute(self: BoxLayout, bounds: Rect, sizes: []const Size, out: []Rect) void {
        std.debug.assert(out.len == sizes.len);
        var cursor_x: i32 = bounds.x + @as(i32, @intCast(self.padding.left));
        var cursor_y: i32 = bounds.y + @as(i32, @intCast(self.padding.top));
        for (sizes, 0..) |s, i| {
            out[i] = Rect.init(cursor_x, cursor_y, s.width, s.height);
            switch (self.direction) {
                .vertical   => cursor_y += @as(i32, @intCast(s.height + self.spacing)),
                .horizontal => cursor_x += @as(i32, @intCast(s.width  + self.spacing)),
            }
        }
    }

    /// Total space this layout needs to hold all `sizes` with spacing and padding.
    pub fn measure(self: BoxLayout, sizes: []const Size) Size {
        var total_w: u32 = self.padding.left + self.padding.right;
        var total_h: u32 = self.padding.top  + self.padding.bottom;
        for (sizes, 0..) |s, i| {
            const gap: u32 = if (i + 1 < sizes.len) self.spacing else 0;
            switch (self.direction) {
                .vertical => {
                    total_h += s.height + gap;
                    total_w  = @max(total_w, self.padding.left + s.width + self.padding.right);
                },
                .horizontal => {
                    total_w += s.width + gap;
                    total_h  = @max(total_h, self.padding.top + s.height + self.padding.bottom);
                },
            }
        }
        return .{ .width = total_w, .height = total_h };
    }
};

test "BoxLayout vertical" {
    const layout = BoxLayout{ .direction = .vertical, .spacing = 4, .padding = Margin.all(0) };
    const sizes = [_]Size{ .{ .width = 100, .height = 20 }, .{ .width = 80, .height = 30 } };
    var rects: [2]Rect = undefined;
    layout.compute(Rect.init(10, 10, 200, 200), &sizes, &rects);
    try std.testing.expectEqual(@as(i32, 10), rects[0].y);
    try std.testing.expectEqual(@as(i32, 34), rects[1].y); // 10 + 20 + 4
}

test "BoxLayout horizontal" {
    const layout = BoxLayout{ .direction = .horizontal, .spacing = 8, .padding = Margin.all(0) };
    const sizes = [_]Size{ .{ .width = 50, .height = 20 }, .{ .width = 60, .height = 20 } };
    var rects: [2]Rect = undefined;
    layout.compute(Rect.init(0, 0, 300, 50), &sizes, &rects);
    try std.testing.expectEqual(@as(i32, 0),  rects[0].x);
    try std.testing.expectEqual(@as(i32, 58), rects[1].x); // 0 + 50 + 8
}
