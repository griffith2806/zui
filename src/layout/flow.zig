const std = @import("std");
const geometry = @import("geometry.zig");

const Rect   = geometry.Rect;
const Size   = geometry.Size;
const Margin = geometry.Margin;

pub const FlowLayout = struct {
    gap_x:   u32    = 8,
    gap_y:   u32    = 8,
    padding: Margin = Margin.all(0),

    pub fn compute(self: FlowLayout, bounds: Rect, sizes: []const Size, out: []Rect) void {
        std.debug.assert(out.len == sizes.len);

        const origin_x: i32 = bounds.x + @as(i32, @intCast(self.padding.left));
        const origin_y: i32 = bounds.y + @as(i32, @intCast(self.padding.top));
        const inner_w: u32 = if (bounds.width > self.padding.left + self.padding.right)
            bounds.width - self.padding.left - self.padding.right
        else
            0;

        var cursor_x: i32 = origin_x;
        var cursor_y: i32 = origin_y;
        var row_h: u32 = 0;

        for (sizes, 0..) |s, i| {
            const item_right: i32 = cursor_x + @as(i32, @intCast(s.width));
            const row_limit: i32  = origin_x + @as(i32, @intCast(inner_w));

            if (i > 0 and item_right > row_limit) {
                cursor_x  = origin_x;
                cursor_y += @as(i32, @intCast(row_h + self.gap_y));
                row_h     = 0;
            }

            out[i] = Rect.init(cursor_x, cursor_y, s.width, s.height);

            cursor_x += @as(i32, @intCast(s.width + self.gap_x));
            if (s.height > row_h) row_h = s.height;
        }
    }

    pub fn measure(self: FlowLayout, max_width: u32, sizes: []const Size) Size {
        const inner_w: u32 = if (max_width > self.padding.left + self.padding.right)
            max_width - self.padding.left - self.padding.right
        else
            0;

        var row_w: u32 = 0;
        var row_h: u32 = 0;
        var total_w: u32 = 0;
        var total_h: u32 = self.padding.top + self.padding.bottom;
        var first_in_row = true;

        for (sizes) |s| {
            const needed: u32 = if (first_in_row) s.width else row_w + self.gap_x + s.width;

            if (!first_in_row and needed > inner_w) {
                if (row_w > total_w) total_w = row_w;
                total_h += row_h + self.gap_y;
                row_w = s.width;
                row_h = s.height;
            } else {
                row_w = needed;
                if (s.height > row_h) row_h = s.height;
                first_in_row = false;
            }
        }

        if (!first_in_row) {
            if (row_w > total_w) total_w = row_w;
            total_h += row_h;
        }

        return .{
            .width  = self.padding.left + total_w + self.padding.right,
            .height = total_h,
        };
    }
};

test "FlowLayout compute wraps" {
    const layout = FlowLayout{ .gap_x = 4, .gap_y = 4, .padding = Margin.all(0) };
    const sizes = [_]Size{
        .{ .width = 60, .height = 20 },
        .{ .width = 60, .height = 20 },
        .{ .width = 60, .height = 20 },
    };
    var rects: [3]Rect = undefined;
    layout.compute(Rect.init(0, 0, 130, 200), &sizes, &rects);
    try std.testing.expectEqual(@as(i32, 0),  rects[0].x);
    try std.testing.expectEqual(@as(i32, 0),  rects[0].y);
    try std.testing.expectEqual(@as(i32, 64), rects[1].x);
    try std.testing.expectEqual(@as(i32, 0),  rects[1].y);
    try std.testing.expectEqual(@as(i32, 0),  rects[2].x);
    try std.testing.expectEqual(@as(i32, 24), rects[2].y);
}

test "FlowLayout measure" {
    const layout = FlowLayout{ .gap_x = 4, .gap_y = 4, .padding = Margin.all(0) };
    const sizes = [_]Size{
        .{ .width = 60, .height = 20 },
        .{ .width = 60, .height = 20 },
        .{ .width = 60, .height = 20 },
    };
    const s = layout.measure(130, &sizes);
    try std.testing.expectEqual(@as(u32, 124), s.width);
    try std.testing.expectEqual(@as(u32, 44),  s.height);
}
