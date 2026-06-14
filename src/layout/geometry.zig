const std = @import("std");

pub const Point = struct {
    x: i32,
    y: i32,

    pub fn add(self: Point, other: Point) Point {
        return .{ .x = self.x + other.x, .y = self.y + other.y };
    }

    pub fn sub(self: Point, other: Point) Point {
        return .{ .x = self.x - other.x, .y = self.y - other.y };
    }

    pub fn eql(self: Point, other: Point) bool {
        return self.x == other.x and self.y == other.y;
    }
};

pub const Size = struct {
    width: u32,
    height: u32,

    pub fn isEmpty(self: Size) bool {
        return self.width == 0 or self.height == 0;
    }

    pub fn eql(self: Size, other: Size) bool {
        return self.width == other.width and self.height == other.height;
    }
};

pub const Rect = struct {
    x: i32,
    y: i32,
    width: u32,
    height: u32,

    pub fn init(x: i32, y: i32, width: u32, height: u32) Rect {
        return .{ .x = x, .y = y, .width = width, .height = height };
    }

    pub fn right(self: Rect) i32 {
        return self.x + @as(i32, @intCast(self.width));
    }

    pub fn bottom(self: Rect) i32 {
        return self.y + @as(i32, @intCast(self.height));
    }

    pub fn topLeft(self: Rect) Point {
        return .{ .x = self.x, .y = self.y };
    }

    pub fn size(self: Rect) Size {
        return .{ .width = self.width, .height = self.height };
    }

    pub fn contains(self: Rect, p: Point) bool {
        return p.x >= self.x and p.x < self.right() and
            p.y >= self.y and p.y < self.bottom();
    }

    pub fn intersects(self: Rect, other: Rect) bool {
        return self.x < other.right() and self.right() > other.x and
            self.y < other.bottom() and self.bottom() > other.y;
    }

    pub fn intersection(self: Rect, other: Rect) ?Rect {
        const ix = @max(self.x, other.x);
        const iy = @max(self.y, other.y);
        const ir = @min(self.right(), other.right());
        const ib = @min(self.bottom(), other.bottom());
        if (ir <= ix or ib <= iy) return null;
        return Rect.init(ix, iy, @intCast(ir - ix), @intCast(ib - iy));
    }

    pub fn translate(self: Rect, dx: i32, dy: i32) Rect {
        return Rect.init(self.x + dx, self.y + dy, self.width, self.height);
    }
};

pub const Margin = struct {
    top: u32,
    right: u32,
    bottom: u32,
    left: u32,

    pub fn all(v: u32) Margin {
        return .{ .top = v, .right = v, .bottom = v, .left = v };
    }

    pub fn symmetric(h: u32, v: u32) Margin {
        return .{ .top = v, .right = h, .bottom = v, .left = h };
    }
};

test "Rect.contains" {
    const r = Rect.init(10, 10, 100, 100);
    try std.testing.expect(r.contains(.{ .x = 10, .y = 10 }));
    try std.testing.expect(r.contains(.{ .x = 50, .y = 50 }));
    try std.testing.expect(!r.contains(.{ .x = 110, .y = 50 }));
    try std.testing.expect(!r.contains(.{ .x = 9, .y = 10 }));
}

test "Rect.intersection overlapping" {
    const a = Rect.init(0, 0, 100, 100);
    const b = Rect.init(50, 50, 100, 100);
    const i = a.intersection(b) orelse return error.ExpectedIntersection;
    try std.testing.expectEqual(@as(i32, 50), i.x);
    try std.testing.expectEqual(@as(i32, 50), i.y);
    try std.testing.expectEqual(@as(u32, 50), i.width);
    try std.testing.expectEqual(@as(u32, 50), i.height);
}

test "Rect.intersection non-overlapping" {
    const a = Rect.init(0, 0, 10, 10);
    const b = Rect.init(20, 20, 10, 10);
    try std.testing.expectEqual(@as(?Rect, null), a.intersection(b));
}

test "Margin.all" {
    const m = Margin.all(8);
    try std.testing.expectEqual(@as(u32, 8), m.top);
    try std.testing.expectEqual(@as(u32, 8), m.right);
    try std.testing.expectEqual(@as(u32, 8), m.bottom);
    try std.testing.expectEqual(@as(u32, 8), m.left);
}
