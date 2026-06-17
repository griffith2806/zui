const std = @import("std");
const geometry = @import("geometry.zig");

const Rect   = geometry.Rect;
const Size   = geometry.Size;
const Margin = geometry.Margin;

pub const Direction = enum { horizontal, vertical };

/// Pairs a preferred size with optional min/max clamps for use with
/// `BoxLayout.computeConstrained`. `flex` is reserved for future use.
pub const ItemConstraint = struct {
    preferred: Size,
    min: ?Size = null,
    max: ?Size = null,
    flex: u32  = 0,
};

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

    pub fn computeWithFlex(
        self: BoxLayout,
        bounds: Rect,
        sizes: []const Size,
        flex: []const u32,
        out: []Rect,
    ) void {
        std.debug.assert(out.len == sizes.len);
        std.debug.assert(flex.len == sizes.len);

        var total_flex: u32 = 0;
        for (flex) |f| total_flex += f;

        const inner_w: u32 = if (bounds.width > self.padding.left + self.padding.right)
            bounds.width - self.padding.left - self.padding.right
        else
            0;
        const inner_h: u32 = if (bounds.height > self.padding.top + self.padding.bottom)
            bounds.height - self.padding.top - self.padding.bottom
        else
            0;

        const total_spacing: u32 = if (sizes.len > 1) self.spacing * @as(u32, @intCast(sizes.len - 1)) else 0;

        var fixed_main: u32 = 0;
        for (sizes, 0..) |s, i| {
            if (flex[i] == 0) {
                fixed_main += switch (self.direction) {
                    .vertical   => s.height,
                    .horizontal => s.width,
                };
            }
        }

        const available_main: u32 = switch (self.direction) {
            .vertical   => inner_h,
            .horizontal => inner_w,
        };

        const remaining: u32 = if (available_main > fixed_main + total_spacing)
            available_main - fixed_main - total_spacing
        else
            0;

        var cursor_x: i32 = bounds.x + @as(i32, @intCast(self.padding.left));
        var cursor_y: i32 = bounds.y + @as(i32, @intCast(self.padding.top));

        for (sizes, 0..) |s, i| {
            const item_w: u32 = switch (self.direction) {
                .vertical   => inner_w,
                .horizontal => if (flex[i] > 0 and total_flex > 0)
                    (remaining * flex[i]) / total_flex
                else
                    s.width,
            };
            const item_h: u32 = switch (self.direction) {
                .vertical   => if (flex[i] > 0 and total_flex > 0)
                    (remaining * flex[i]) / total_flex
                else
                    s.height,
                .horizontal => inner_h,
            };

            out[i] = Rect.init(cursor_x, cursor_y, item_w, item_h);

            switch (self.direction) {
                .vertical   => cursor_y += @as(i32, @intCast(item_h + self.spacing)),
                .horizontal => cursor_x += @as(i32, @intCast(item_w + self.spacing)),
            }
        }
    }

    /// Like `compute`, but each item carries optional min/max constraints that
    /// clamp the preferred size before placement. `flex` is not used here —
    /// items get exactly their (clamped) preferred size.
    /// `out.len` must equal `constraints.len`.
    pub fn computeConstrained(
        self: BoxLayout,
        bounds: Rect,
        constraints: []const ItemConstraint,
        out: []Rect,
    ) void {
        std.debug.assert(out.len == constraints.len);
        var cursor_x: i32 = bounds.x + @as(i32, @intCast(self.padding.left));
        var cursor_y: i32 = bounds.y + @as(i32, @intCast(self.padding.top));
        for (constraints, 0..) |c, i| {
            var w = c.preferred.width;
            var h = c.preferred.height;
            if (c.min) |mn| { w = @max(w, mn.width); h = @max(h, mn.height); }
            if (c.max) |mx| { w = @min(w, mx.width); h = @min(h, mx.height); }
            out[i] = Rect.init(cursor_x, cursor_y, w, h);
            switch (self.direction) {
                .vertical   => cursor_y += @as(i32, @intCast(h + self.spacing)),
                .horizontal => cursor_x += @as(i32, @intCast(w + self.spacing)),
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

test "BoxLayout computeWithFlex vertical" {
    const layout = BoxLayout{ .direction = .vertical, .spacing = 0, .padding = Margin.all(0) };
    const sizes = [_]Size{
        .{ .width = 100, .height = 20 },
        .{ .width = 100, .height = 0 },
    };
    const flex = [_]u32{ 0, 1 };
    var rects: [2]Rect = undefined;
    layout.computeWithFlex(Rect.init(0, 0, 100, 120), &sizes, &flex, &rects);
    try std.testing.expectEqual(@as(u32, 20), rects[0].height);
    try std.testing.expectEqual(@as(i32, 20), rects[1].y);
    try std.testing.expectEqual(@as(u32, 100), rects[1].height);
}

test "BoxLayout horizontal" {
    const layout = BoxLayout{ .direction = .horizontal, .spacing = 8, .padding = Margin.all(0) };
    const sizes = [_]Size{ .{ .width = 50, .height = 20 }, .{ .width = 60, .height = 20 } };
    var rects: [2]Rect = undefined;
    layout.compute(Rect.init(0, 0, 300, 50), &sizes, &rects);
    try std.testing.expectEqual(@as(i32, 0),  rects[0].x);
    try std.testing.expectEqual(@as(i32, 58), rects[1].x); // 0 + 50 + 8
}

test "BoxLayout computeConstrained clamps min/max" {
    const layout = BoxLayout{ .direction = .vertical, .spacing = 4, .padding = Margin.all(0) };
    const constraints = [_]ItemConstraint{
        .{ .preferred = .{ .width = 100, .height = 10 }, .min = .{ .width = 100, .height = 20 } },
        .{ .preferred = .{ .width = 100, .height = 50 }, .max = .{ .width = 100, .height = 30 } },
        .{ .preferred = .{ .width = 100, .height = 25 } },
    };
    var rects: [3]Rect = undefined;
    layout.computeConstrained(Rect.init(0, 0, 200, 300), &constraints, &rects);
    // Item 0: preferred height 10 clamped up to min 20
    try std.testing.expectEqual(@as(u32, 20), rects[0].height);
    // Item 1: preferred height 50 clamped down to max 30; y = 0 + 20 + 4 = 24
    try std.testing.expectEqual(@as(i32, 24), rects[1].y);
    try std.testing.expectEqual(@as(u32, 30), rects[1].height);
    // Item 2: preferred height 25 unclamped; y = 24 + 30 + 4 = 58
    try std.testing.expectEqual(@as(i32, 58), rects[2].y);
    try std.testing.expectEqual(@as(u32, 25), rects[2].height);
}
