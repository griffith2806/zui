const std = @import("std");
const Rect = @import("geometry.zig").Rect;
const Size = @import("geometry.zig").Size;

/// A single-axis resize constraint, mirroring Figma's constraint model.
///
/// For the horizontal axis: `start` = Left, `end` = Right, `start_end` = Left &
/// Right (stretch), `center` = Center, `scale` = Scale.
/// For the vertical axis: `start` = Top, `end` = Bottom, `start_end` = Top &
/// Bottom (stretch), `center` = Center, `scale` = Scale.
pub const Constraint = enum { start, end, start_end, center, scale };

/// Horizontal + vertical constraints for one child of a resizable frame.
pub const Constraints = struct {
    horizontal: Constraint = .start,
    vertical: Constraint = .start,

    pub const empty = Constraints{};

    /// Recompute a child's rect when its parent frame resizes from
    /// `parent_old` to `parent_new`. `child` is the child's rect under
    /// `parent_old`; the return value is its rect under `parent_new`.
    pub fn apply(self: Constraints, parent_old: Size, parent_new: Size, child: Rect) Rect {
        const h = solve(self.horizontal, parent_old.width, parent_new.width, child.x, child.width);
        const v = solve(self.vertical, parent_old.height, parent_new.height, child.y, child.height);
        return .{
            .x = h.pos,
            .y = v.pos,
            .width = h.size,
            .height = v.size,
        };
    }
};

const Solved = struct { pos: i32, size: u32 };

fn solve(c: Constraint, p0: u32, p1: u32, pos0: i32, size0: u32) Solved {
    const f0: f32 = @floatFromInt(p0);
    const f1: f32 = @floatFromInt(p1);
    const x0: f32 = @floatFromInt(pos0);
    const w0: f32 = @floatFromInt(size0);
    const dp = f1 - f0;
    const ratio: f32 = if (f0 != 0) f1 / f0 else 1.0;

    switch (c) {
        .start => return .{ .pos = pos0, .size = size0 },
        .end => return .{ .pos = roundI(x0 + dp), .size = size0 },
        .start_end => return .{ .pos = pos0, .size = roundU(w0 + dp) },
        .center => {
            const parent_center0 = f0 / 2.0;
            const parent_center1 = f1 / 2.0;
            const child_center0 = x0 + w0 / 2.0;
            const child_center1 = parent_center1 + (child_center0 - parent_center0) * ratio;
            return .{ .pos = roundI(child_center1 - w0 / 2.0), .size = size0 };
        },
        .scale => return .{ .pos = roundI(x0 * ratio), .size = roundU(w0 * ratio) },
    }
}

fn roundI(v: f32) i32 {
    return @intFromFloat(@round(v));
}

fn roundU(v: f32) u32 {
    if (v <= 0) return 0;
    return @intFromFloat(@round(v));
}

// ── Tests ─────────────────────────────────────────────────────────────────────

const P0 = Size{ .width = 100, .height = 100 };

test "Constraints defaults are start/start" {
    const c = Constraints.empty;
    try std.testing.expectEqual(Constraint.start, c.horizontal);
    try std.testing.expectEqual(Constraint.start, c.vertical);
}

test "Constraints.start keeps child fixed (left/top)" {
    const c = Constraints{ .horizontal = .start, .vertical = .start };
    const child = Rect.init(20, 30, 40, 10);
    const out = c.apply(P0, .{ .width = 200, .height = 200 }, child);
    try std.testing.expectEqual(@as(i32, 20), out.x);
    try std.testing.expectEqual(@as(i32, 30), out.y);
    try std.testing.expectEqual(@as(u32, 40), out.width);
    try std.testing.expectEqual(@as(u32, 10), out.height);
}

test "Constraints.end pins child to right/bottom edge" {
    const c = Constraints{ .horizontal = .end, .vertical = .end };
    // child right edge at 20+40=60, so 40 from parent right (100).
    const child = Rect.init(20, 30, 40, 10);
    const out = c.apply(P0, .{ .width = 200, .height = 150 }, child);
    // grows by +100 / +50 -> x=120, y=80
    try std.testing.expectEqual(@as(i32, 120), out.x);
    try std.testing.expectEqual(@as(i32, 80), out.y);
    try std.testing.expectEqual(@as(u32, 40), out.width);
    try std.testing.expectEqual(@as(u32, 10), out.height);
}

test "Constraints.start_end stretches child" {
    const c = Constraints{ .horizontal = .start_end, .vertical = .start_end };
    const child = Rect.init(20, 30, 40, 10);
    const out = c.apply(P0, .{ .width = 200, .height = 100 }, child);
    try std.testing.expectEqual(@as(i32, 20), out.x);
    try std.testing.expectEqual(@as(i32, 30), out.y);
    try std.testing.expectEqual(@as(u32, 140), out.width); // 40 + 100
    try std.testing.expectEqual(@as(u32, 10), out.height);  // no vertical delta
}

test "Constraints.center with zero offset stays centered" {
    const c = Constraints{ .horizontal = .center, .vertical = .center };
    // child centered in 100x100: x=40,w=20 -> center 50
    const child = Rect.init(40, 40, 20, 20);
    const out = c.apply(P0, .{ .width = 200, .height = 200 }, child);
    // new parent center 100, offset 0 -> child center 100 -> x=90
    try std.testing.expectEqual(@as(i32, 90), out.x);
    try std.testing.expectEqual(@as(i32, 90), out.y);
    try std.testing.expectEqual(@as(u32, 20), out.width);
}

test "Constraints.center scales the center offset" {
    const c = Constraints{ .horizontal = .center, .vertical = .start };
    // child center 30, parent center 50 -> offset -20; parent doubles -> -40
    const child = Rect.init(20, 0, 20, 20);
    const out = c.apply(P0, .{ .width = 200, .height = 100 }, child);
    // new center = 100 - 40 = 60 -> x = 50
    try std.testing.expectEqual(@as(i32, 50), out.x);
    try std.testing.expectEqual(@as(u32, 20), out.width);
}

test "Constraints.scale scales position and size" {
    const c = Constraints{ .horizontal = .scale, .vertical = .scale };
    const child = Rect.init(20, 30, 20, 10);
    const out = c.apply(P0, .{ .width = 200, .height = 50 }, child);
    try std.testing.expectEqual(@as(i32, 40), out.x);   // 20 * 2
    try std.testing.expectEqual(@as(i32, 15), out.y);   // 30 * 0.5
    try std.testing.expectEqual(@as(u32, 40), out.width);  // 20 * 2
    try std.testing.expectEqual(@as(u32, 5), out.height);  // 10 * 0.5
}

test "Constraints.scale shrinks" {
    const c = Constraints{ .horizontal = .scale, .vertical = .scale };
    const child = Rect.init(20, 20, 20, 20);
    const out = c.apply(P0, .{ .width = 50, .height = 50 }, child);
    try std.testing.expectEqual(@as(i32, 10), out.x);
    try std.testing.expectEqual(@as(u32, 10), out.width);
}

test "Constraints mixed axes: stretch horizontal, bottom vertical" {
    const c = Constraints{ .horizontal = .start_end, .vertical = .end };
    const child = Rect.init(10, 10, 30, 30);
    const out = c.apply(P0, .{ .width = 150, .height = 100 }, child);
    try std.testing.expectEqual(@as(i32, 10), out.x);
    try std.testing.expectEqual(@as(u32, 80), out.width); // 30 + 50
    try std.testing.expectEqual(@as(i32, 10), out.y);     // no vertical delta
    try std.testing.expectEqual(@as(u32, 30), out.height);
}

test "Constraints.zero parent width does not divide by zero" {
    const c = Constraints{ .horizontal = .scale, .vertical = .scale };
    const child = Rect.init(0, 0, 0, 0);
    const out = c.apply(.{ .width = 0, .height = 0 }, .{ .width = 100, .height = 100 }, child);
    try std.testing.expectEqual(@as(i32, 0), out.x);
    try std.testing.expectEqual(@as(u32, 0), out.width);
}
